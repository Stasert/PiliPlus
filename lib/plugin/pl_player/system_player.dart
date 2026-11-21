import 'dart:async';
import 'dart:io' show Platform;

import 'package:PiliPlus/models/video/play/url.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/services.dart';

/// One bilibili DASH representation handed to the native system player.
class SystemPlayerTrack {
  const SystemPlayerTrack({
    required this.url,
    required this.indexEnd,
    required this.bandwidth,
  });

  final String url;

  /// End of `segment_base.index_range`: the file head up to here holds
  /// ftyp + moov + sidx, from which the native side builds an HLS playlist.
  /// 0 when unknown: the native side then reads the first 512 KB.
  final int indexEnd;
  final int bandwidth;

  /// A downloaded file. The native side opens it directly instead of building
  /// an HLS playlist, so no segment index is needed.
  factory SystemPlayerTrack.file(String path) => SystemPlayerTrack(
    url: Uri.file(path).toString(),
    indexEnd: 0,
    bandwidth: 0,
  );

  static SystemPlayerTrack fromItem(BaseItem? item, String url) {
    final base = item?.segmentBase;
    final range = base?['index_range'] ?? base?['indexRange'];
    final end = range is String ? int.tryParse(range.split('-').last) : null;
    return SystemPlayerTrack(
      url: url,
      indexEnd: end != null && end > 0 ? end : 0,
      bandwidth: item?.bandWidth ?? 0,
    );
  }

  Map<String, Object> toMap() => {
    'url': url,
    'indexEnd': indexEnd,
    'bandwidth': bandwidth,
  };
}

/// What to play with the system player instead of mpv.
class SystemPlayerSource {
  const SystemPlayerSource({
    required this.video,
    this.audio,
    this.frameRate,
    required this.isHdr,
  });

  final SystemPlayerTrack video;
  final SystemPlayerTrack? audio;
  final double? frameRate;

  /// HDR / Dolby Vision, which only the system player shows right. SDR plays
  /// here only because「所有视频」is on, and looks the same on mpv.
  final bool isHdr;
}

/// Dart side of `ios/Runner/SystemPlayerPlugin.swift`: AVPlayer for HDR /
/// Dolby Vision (and optionally all on-demand) videos on iOS.
class SystemPlayer {
  SystemPlayer._(this.id);

  static const _channel = MethodChannel('piliplus/system_player');
  static const _events = EventChannel('piliplus/system_player/events');
  static const viewType = 'piliplus/system_player_view';

  static bool get isSupported => Platform.isIOS;

  static final Stream<Map> _allEvents = _events
      .receiveBroadcastStream()
      .cast<Map>()
      .asBroadcastStream();

  final int id;

  late final Stream<Map> _myEvents = _allEvents.where((e) => e['id'] == id);

  Stream<Map> _of(String type) => _myEvents.where((e) => e['type'] == type);

  late final Stream<Duration> position = _of('position').map((e) {
    final d = Duration(milliseconds: e['ms'] as int);
    _lastPosition = d;
    _lastPositionAt = DateTime.now();
    return d;
  });
  late final Stream<Duration> buffered = _of(
    'position',
  ).map((e) => Duration(milliseconds: e['bufferedMs'] as int));
  late final Stream<Duration> duration = _of('duration').map((e) {
    _duration = Duration(milliseconds: e['ms'] as int);
    return _duration;
  });
  late final Stream<bool> playing = _of('playing').map((e) {
    _setState(playing: e['value'] as bool);
    return _playing;
  });
  late final Stream<bool> buffering = _of('buffering').map((e) {
    _setState(buffering: e['value'] as bool);
    return _buffering;
  });
  late final Stream<void> completed = _of('completed');
  late final Stream<String> error = _of(
    'error',
  ).map((e) => e['message']?.toString() ?? '');
  late final Stream<(int, int)> size = _of(
    'size',
  ).map((e) => (e['width'] as int, e['height'] as int));
  late final Stream<bool> fastForward = _of('fastForward').map((e) {
    _canPlayFastForward = e['value'] as bool;
    return _canPlayFastForward;
  });

  Duration _lastPosition = Duration.zero;
  DateTime _lastPositionAt = DateTime.now();
  Duration _duration = Duration.zero;
  bool _playing = false;
  bool _buffering = false;
  double _rate = 1;
  bool _canPlayFastForward = false;

  bool get isPlaying => _playing;
  double get rate => _rate;

  /// Whether AVPlayer can play the current item faster than 2x
  /// (`AVPlayerItem.canPlayFastForward`). Downloads can once they are ready;
  /// online videos (HLS without an I-frame playlist) never can. Kept up to
  /// date while [fastForward] is listened to.
  bool get canPlayFastForward => _canPlayFastForward;

  /// Most media time [currentPosition] runs ahead of the last native update.
  /// Updates come every 200 ms of media time, so this only bridges a late one;
  /// if they stop without a buffering event, the position stops soon after.
  static const maxInterpolation = Duration(milliseconds: 500);

  /// Position interpolated between the 200 ms native updates, so danmaku
  /// stays smooth like with mpv.
  Duration get currentPosition => interpolate(
    last: _lastPosition,
    elapsed: DateTime.now().difference(_lastPositionAt),
    rate: _rate,
    advancing: _playing && !_buffering,
    duration: _duration,
  );

  /// [last] advanced by [elapsed] at [rate] while [advancing] (playing and not
  /// waiting for data), at most by [maxInterpolation] and never past
  /// [duration] (when known, i.e. > 0).
  @visibleForTesting
  static Duration interpolate({
    required Duration last,
    required Duration elapsed,
    required double rate,
    required bool advancing,
    required Duration duration,
  }) {
    if (!advancing || elapsed <= Duration.zero) return last;
    var ahead = elapsed * rate;
    if (ahead > maxInterpolation) ahead = maxInterpolation;
    final position = last + ahead;
    return duration > Duration.zero && position > duration
        ? duration
        : position;
  }

  void _setState({bool? playing, bool? buffering}) {
    final wasAdvancing = _playing && !_buffering;
    _playing = playing ?? _playing;
    _buffering = buffering ?? _buffering;
    // Time stood still while not advancing: count from now, not from the last
    // update. When it stops, stay at the last reported position.
    if (!wasAdvancing && _playing && !_buffering) {
      _lastPositionAt = DateTime.now();
    }
  }

  static Future<SystemPlayer> create() async {
    final id = await _channel.invokeMethod<int>('create');
    return SystemPlayer._(id!);
  }

  /// `load` result when it was cancelled (superseded or the page closed).
  static const cancelled = 'cancelled';

  /// `load` result for a source known not to play (e.g. a downloaded `hev1`
  /// file); mpv takes over without a message.
  static const unsupported = 'unsupported';

  /// Returns an error message, [cancelled], [unsupported], or null on success.
  /// [bufferSec] is the「缓冲时长」setting: the native side buffers that much
  /// playing time ahead, kept within 30–60 s.
  Future<String?> load(
    SystemPlayerSource source, {
    required Map<String, String> headers,
    Duration? start,
    double? bufferSec,
  }) {
    _lastPosition = start ?? Duration.zero;
    _lastPositionAt = DateTime.now();
    _duration = Duration.zero;
    // Not known for the new item until AVPlayer has it ready.
    _canPlayFastForward = false;
    return _channel.invokeMethod<String>('load', {
      'id': id,
      'video': source.video.toMap(),
      'audio': ?source.audio?.toMap(),
      'frameRate': ?source.frameRate,
      'headers': headers,
      'startMs': start?.inMilliseconds ?? 0,
      'bufferSec': ?bufferSec,
    });
  }

  Future<void> play() => _channel.invokeMethod('play', {'id': id});

  Future<void> pause() => _channel.invokeMethod('pause', {'id': id});

  Future<void> seek(Duration position) {
    _lastPosition = position;
    _lastPositionAt = DateTime.now();
    return _channel.invokeMethod('seek', {
      'id': id,
      'ms': position.inMilliseconds,
    });
  }

  Future<void> setRate(double rate) {
    _rate = rate;
    return _channel.invokeMethod('setRate', {'id': id, 'rate': rate});
  }

  Future<void> setVolume(double volume) =>
      _channel.invokeMethod('setVolume', {'id': id, 'volume': volume});

  /// The current frame as PNG (HDR tone mapped to SDR), or null.
  Future<Uint8List?> screenshot() =>
      _channel.invokeMethod<Uint8List>('screenshot', {'id': id});

  /// Details for the playback info panel (see `SystemPlayerSession.info`).
  Future<Map<String, Object?>> info() async =>
      (await _channel.invokeMapMethod<String, Object?>('info', {'id': id})) ??
      const {};

  Future<void> dispose() => _channel.invokeMethod('dispose', {'id': id});

  static Future<bool> supportsHardwareDecode(String codec) async =>
      await _channel.invokeMethod<bool>('supportsHardwareDecode', {
        'codec': codec,
      }) ??
      true;

  /// [video]'s `codecs`, `supplementalCodecs` and `videoRange` (SDR / PQ /
  /// HLG), read from its init section as [load] would, without playing it:
  /// one range request online, the file head offline. For mpv's Dolby Vision
  /// handling, which mpv waits for. null on any error, or when it takes too
  /// long (the native side gives up after 2 s).
  static Future<Map<String, Object?>?> probe(
    SystemPlayerTrack video, {
    required Map<String, String> headers,
  }) async {
    try {
      return await _channel
          .invokeMapMethod<String, Object?>('probe', {
            'video': video.toMap(),
            'headers': headers,
          })
          .timeout(const Duration(seconds: 3));
    } catch (_) {
      return null;
    }
  }
}
