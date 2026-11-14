import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:PiliPlus/models_new/download/bili_download_entry_info.dart';
import 'package:PiliPlus/models_new/download/bili_download_media_file_info.dart';
import 'package:PiliPlus/services/download/download_manager.dart';
import 'package:PiliPlus/services/download/download_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

/// 模拟 CDN：支持 Range，可以按次数让响应提前结束、卡住或忽略 Range。
class _FakeServer implements HttpClientAdapter {
  _FakeServer(this.content);

  Uint8List content;

  /// 第 n 次请求（从 0 开始）只发送这么多字节就正常结束连接
  final Map<int, int> cutAfter = {};

  /// 第 n 次请求发完响应头后不再发数据
  final Set<int> stallOn = {};

  bool ignoreRange = false;

  final List<String?> ranges = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final index = ranges.length;
    final range = options.headers['range'] as String?;
    ranges.add(range);
    final total = content.length;
    var start = int.parse(RegExp(r'bytes=(\d+)-').firstMatch(range!)![1]!);
    if (ignoreRange) {
      start = 0;
    } else if (start >= total) {
      return ResponseBody.fromString(
        'Requested Range Not Satisfiable',
        416,
        headers: {
          'content-range': ['bytes */$total'],
        },
      );
    }
    final body = content.sublist(start);
    final controller = StreamController<Uint8List>();
    cancelFuture?.then((_) {
      if (!controller.isClosed) {
        controller
          ..addError(
            DioException.requestCancelled(requestOptions: options, reason: 0),
          )
          ..close();
      }
    });
    if (!stallOn.contains(index)) {
      final sent = cutAfter[index] ?? body.length;
      scheduleMicrotask(() {
        // 分两块发，模拟真实下载
        final half = sent ~/ 2;
        controller
          ..add(body.sublist(0, half))
          ..add(body.sublist(half, sent))
          ..close();
      });
    }
    return ResponseBody(
      controller.stream,
      ignoreRange ? 200 : 206,
      headers: {
        'content-length': ['${body.length}'],
        if (!ignoreRange)
          'content-range': ['bytes $start-${total - 1}/$total'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

Uint8List _bytes(int length, [int seed = 0]) =>
    Uint8List.fromList(List.generate(length, (i) => (i * 7 + seed) % 256));

void main() {
  late Directory dir;
  late String filePath;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('download_manager_test');
    filePath = '${dir.path}/video.m4s';
  });

  tearDown(() => dir.deleteSync(recursive: true));

  Future<(DownloadManager, Object?)> download(
    _FakeServer server, {
    int maxRetries = 3,
    Duration idleTimeout = const Duration(seconds: 5),
  }) async {
    Object? error;
    var doneCount = 0;
    final manager = DownloadManager(
      url: 'https://example.com/video.m4s',
      path: filePath,
      onReceiveProgress: null,
      onDone: ([e]) {
        doneCount++;
        error = e;
      },
      maxRetries: maxRetries,
      retryDelay: Duration.zero,
      idleTimeout: idleTimeout,
      dio: Dio()..httpClientAdapter = server,
    );
    await manager.task;
    expect(doneCount, 1, reason: 'onDone 只应调用一次');
    return (manager, error);
  }

  test('响应提前结束后自动续传，文件完整', () async {
    final content = _bytes(1000);
    final server = _FakeServer(content)..cutAfter[0] = 400;
    final (manager, error) = await download(server);

    expect(error, isNull);
    expect(manager.status, DownloadStatus.completed);
    expect(File(filePath).readAsBytesSync(), content);
    expect(server.ranges, ['bytes=0-', 'bytes=400-']);
  });

  test('每次都提前结束：标为失败而不是完成，并保留已下载部分', () async {
    final content = _bytes(1000);
    final server = _FakeServer(content)
      ..cutAfter.addAll({0: 300, 1: 300, 2: 300});
    final (manager, error) = await download(server, maxRetries: 2);

    expect(manager.status, DownloadStatus.failDownload);
    expect(error, isA<IncompleteDownloadException>());
    expect(File(filePath).lengthSync(), 900);
    expect(server.ranges, ['bytes=0-', 'bytes=300-', 'bytes=600-']);
  });

  test('收不到数据时超时，续传后完成', () async {
    final content = _bytes(1000);
    final server = _FakeServer(content)..stallOn.add(0);
    final (manager, error) = await download(
      server,
      idleTimeout: const Duration(milliseconds: 50),
    );

    expect(error, isNull);
    expect(manager.status, DownloadStatus.completed);
    expect(File(filePath).readAsBytesSync(), content);
  });

  test('服务器忽略 Range 返回整个文件时，不接在旧数据后面', () async {
    final content = _bytes(1000);
    File(filePath).writeAsBytesSync(content.sublist(0, 500));
    final server = _FakeServer(content)..ignoreRange = true;
    final (manager, error) = await download(server);

    expect(error, isNull);
    expect(manager.status, DownloadStatus.completed);
    expect(File(filePath).readAsBytesSync(), content);
  });

  test('本地文件已完整时 416 算完成，不写入响应内容', () async {
    final content = _bytes(1000);
    File(filePath).writeAsBytesSync(content);
    final server = _FakeServer(content);
    final (manager, error) = await download(server);

    expect(error, isNull);
    expect(manager.status, DownloadStatus.completed);
    expect(File(filePath).readAsBytesSync(), content);
  });

  test('本地文件比服务器上的大（换了流）时从头下载，而不是直接完成', () async {
    File(filePath).writeAsBytesSync(_bytes(1500, 3));
    final content = _bytes(1000);
    final server = _FakeServer(content);
    final (manager, error) = await download(server);

    expect(error, isNull);
    expect(manager.status, DownloadStatus.completed);
    expect(File(filePath).readAsBytesSync(), content);
    expect(server.ranges, ['bytes=1500-', 'bytes=0-']);
  });

  test('暂停后不再续传', () async {
    final content = _bytes(1000);
    final server = _FakeServer(content)..stallOn.add(0);
    Object? error;
    final manager = DownloadManager(
      url: 'https://example.com/video.m4s',
      path: filePath,
      onReceiveProgress: null,
      onDone: ([e]) => error = e,
      retryDelay: Duration.zero,
      dio: Dio()..httpClientAdapter = server,
    );
    await Future<void>.delayed(const Duration(milliseconds: 20));
    await manager.cancel(isDelete: false);

    expect(manager.status, DownloadStatus.pause);
    expect(error, isA<DioException>());
    expect(server.ranges, hasLength(1));
  });

  test('解析 Content-Range', () {
    final a = ContentRange.tryParse('bytes 100-999/1000')!;
    expect((a.start, a.total), (100, 1000));
    final b = ContentRange.tryParse('bytes */1000')!;
    expect((b.start, b.total), (null, 1000));
    final c = ContentRange.tryParse('bytes 0-99/*')!;
    expect((c.start, c.total), (0, null));
    expect(ContentRange.tryParse('garbage'), isNull);
    expect(ContentRange.tryParse(null), isNull);
  });

  group('续传前判断是否同一条流', () {
    Type2File file(int id, int codecid, int bandwidth) => Type2File(
      id: id,
      baseUrl: 'https://example.com/$id',
      bandwidth: bandwidth,
      codecid: codecid,
      size: 0,
      md5: '',
      noRexcode: false,
      frameRate: '',
      width: 1920,
      height: 1080,
      dashDrmType: 0,
    );
    Type2 info(Type2File video, Type2File? audio) => Type2(
      duration: 100,
      video: [video],
      audio: audio == null ? null : [audio],
    );

    test('相同的流可以续传（CDN 地址不同也一样）', () {
      expect(
        DownloadService.isSameMediaStream(
          info(file(80, 7, 100), file(30280, 0, 10)),
          info(file(80, 7, 100), file(30280, 0, 10)),
        ),
        (true, true),
      );
    });

    test('换了编码或音质时作废对应的部分', () {
      expect(
        DownloadService.isSameMediaStream(
          info(file(80, 7, 100), file(30280, 0, 10)),
          info(file(80, 12, 90), file(30216, 0, 5)),
        ),
        (false, false),
      );
      expect(
        DownloadService.isSameMediaStream(
          info(file(80, 7, 100), file(30280, 0, 10)),
          info(file(80, 7, 100), file(30232, 0, 8)),
        ),
        (true, false),
      );
    });

    test('没有旧记录时都作废', () {
      expect(
        DownloadService.isSameMediaStream(null, info(file(80, 7, 100), null)),
        (false, false),
      );
    });
  });
}
