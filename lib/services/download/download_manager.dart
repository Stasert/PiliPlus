import 'dart:async';
import 'dart:io';

import 'package:PiliPlus/http/init.dart';
import 'package:PiliPlus/models_new/download/bili_download_entry_info.dart';
import 'package:PiliPlus/utils/extension/file_ext.dart';
import 'package:PiliPlus/utils/extension/string_ext.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;

/// 下载流在收到全部字节前结束（连接被断开但没有报错）。
class IncompleteDownloadException implements Exception {
  const IncompleteDownloadException(this.received, this.total);

  final int received;
  final int total;

  @override
  String toString() => 'IncompleteDownloadException: $received/$total bytes';
}

/// 服务器返回的数据和本地已下载的部分对不上，需要从头下载。
class _RestartDownload implements Exception {
  const _RestartDownload();
}

class DownloadManager {
  final String url;
  final String path;
  final void Function(int, int)? onReceiveProgress;
  final void Function([Object? error]) onDone;

  /// 网络中断或数据不完整时，自动续传的次数
  final int maxRetries;

  /// 两次续传之间的等待时间
  final Duration retryDelay;

  /// 下载过程中多久收不到数据算超时
  final Duration idleTimeout;

  /// 仅测试时传入
  final Dio? dio;

  DownloadStatus _status = DownloadStatus.downloading;

  DownloadStatus get status => _status;
  final _cancelToken = CancelToken();
  late Future<void> task;

  DownloadManager({
    required this.url,
    required this.path,
    required this.onReceiveProgress,
    required this.onDone,
    this.maxRetries = 3,
    this.retryDelay = const Duration(seconds: 2),
    this.idleTimeout = const Duration(seconds: 30),
    this.dio,
  }) {
    task = _start();
  }

  bool get _isCancelled => _cancelToken.isCancelled;

  Future<void> _start() async {
    final file = File(path);
    int attempt = 0;
    while (true) {
      try {
        await _download(file);
        _status = DownloadStatus.completed;
        onDone();
        return;
      } on _RestartDownload {
        // 本地数据作废，删掉后立即从头下载
        await file.tryDel();
        if (_isCancelled) {
          return _fail(_cancelError);
        }
        if (attempt++ >= maxRetries) {
          return _fail(const IncompleteDownloadException(0, -1));
        }
      } catch (e) {
        if (_isCancelled || !_canRetry(e) || attempt++ >= maxRetries) {
          return _fail(e);
        }
        // 保留已下载的部分，稍后续传
        await Future.any([
          Future<void>.delayed(retryDelay),
          _cancelToken.whenCancel,
        ]);
        if (_isCancelled) {
          return _fail(_cancelError);
        }
      }
    }
  }

  Object get _cancelError =>
      _cancelToken.cancelError ??
      DioException.requestCancelled(
        requestOptions: RequestOptions(path: url),
        reason: null,
      );

  void _fail(Object e) {
    if (_status == DownloadStatus.downloading) {
      _status = DownloadStatus.failDownload;
    }
    onDone(e);
  }

  static bool _canRetry(Object e) {
    if (e is DioException) {
      return switch (e.type) {
        // 地址过期、无权限等，重试也没用
        DioExceptionType.badResponse ||
        DioExceptionType.cancel ||
        DioExceptionType.badCertificate => false,
        _ => true,
      };
    }
    return e is IncompleteDownloadException ||
        e is TimeoutException ||
        e is IOException;
  }

  /// 下载一次，直到文件完整为止。不完整时抛出异常。
  Future<void> _download(File file) async {
    int received = file.existsSync() ? await file.length() : 0;

    final response = await (dio ?? Request.http11Dio).get<ResponseBody>(
      url.http2https,
      options: Options(
        headers: {'range': 'bytes=$received-'},
        responseType: ResponseType.stream,
        validateStatus: (status) =>
            status != null &&
            (status == 416 || (status >= 200 && status < 300)),
      ),
      cancelToken: _cancelToken,
    );
    final data = response.data!;
    final contentRange = ContentRange.tryParse(
      data.headers['content-range']?.firstOrNull,
    );

    int total;
    switch (data.statusCode) {
      case 416:
        // 请求的起点已超出文件末尾：只有本地文件刚好完整时才算完成
        _drain(data);
        if (received > 0 && contentRange?.total == received) {
          onReceiveProgress?.call(received, received);
          return;
        }
        throw const _RestartDownload();
      case 206:
        if (contentRange != null && contentRange.start != received) {
          _drain(data);
          throw const _RestartDownload();
        }
        total =
            contentRange?.total ??
            (data.contentLength < 0 ? -1 : data.contentLength + received);
      default:
        // 服务器忽略了 Range，返回的是整个文件，从头写
        received = 0;
        total = data.contentLength;
    }

    if (total >= 0 && received > total) {
      _drain(data);
      throw const _RestartDownload();
    }

    if (!file.existsSync()) {
      file.createSync(recursive: true);
    }
    final sink = file.openWrite(
      mode: received == 0 ? FileMode.writeOnly : FileMode.writeOnlyAppend,
    );

    onReceiveProgress?.call(received, total);

    int? last;
    try {
      await for (final chunk in data.stream.timeout(idleTimeout)) {
        sink.add(chunk);
        received += chunk.length;
        final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
        if (last != now) {
          last = now;
          onReceiveProgress?.call(received, total);
        }
      }
    } finally {
      try {
        await sink.close();
      } catch (_) {}
    }

    if (_isCancelled) {
      throw _cancelError;
    }
    if (total >= 0 && received != total) {
      throw IncompleteDownloadException(received, total);
    }
    onReceiveProgress?.call(received, total);
  }

  static void _drain(ResponseBody data) {
    data.stream.listen(null, onError: (_) {}).cancel();
  }

  Future<void> cancel({required bool isDelete}) {
    if (!isDelete && _status == DownloadStatus.downloading) {
      _status = DownloadStatus.pause;
    }
    if (!_cancelToken.isCancelled) {
      _cancelToken.cancel();
    }
    return task;
  }
}

/// `Content-Range: bytes start-end/total` 或 `bytes */total`
@visibleForTesting
class ContentRange {
  const ContentRange(this.start, this.total);

  /// 未知时为 null（`bytes */total`）
  final int? start;

  /// 未知时为 null（`/*`）
  final int? total;

  static final _regExp = RegExp(r'^bytes\s+(?:(\d+)-\d+|\*)/(\d+|\*)$');

  static ContentRange? tryParse(String? value) {
    if (value == null) return null;
    final match = _regExp.firstMatch(value.trim());
    if (match == null) return null;
    return ContentRange(
      match.group(1) == null ? null : int.parse(match.group(1)!),
      int.tryParse(match.group(2)!),
    );
  }
}
