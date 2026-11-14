import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// State of the AirPlay cast, reported by `ios/Runner/AirPlayPlugin.swift`.
@immutable
class AirPlayState {
  const AirPlayState({
    required this.connected,
    required this.playing,
    required this.position,
    required this.duration,
    this.device,
    this.title,
    this.error,
  });

  factory AirPlayState.fromMap(Map map) => AirPlayState(
    connected: map['connected'] == true,
    playing: map['playing'] == true,
    position: Duration(milliseconds: map['positionMs'] as int? ?? 0),
    duration: Duration(milliseconds: map['durationMs'] as int? ?? 0),
    device: map['device'] as String?,
    title: map['title'] as String?,
    error: map['error'] as String?,
  );

  /// Whether a receiver is connected (the device list may still be open).
  final bool connected;
  final bool playing;
  final Duration position;
  final Duration duration;
  final String? device;
  final String? title;
  final String? error;
}

/// AirPlay casting on iOS. The receiver downloads the video itself (the same
/// progressive MP4 URL as DLNA casting); the cast page is the remote control.
abstract final class AirPlayHelper {
  static const _channel = MethodChannel('piliplus/airplay');

  /// The current cast, or null when nothing is being cast.
  static final state = ValueNotifier<AirPlayState?>(null);

  static bool _initialized = false;

  static void _init() {
    if (_initialized) return;
    _initialized = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'state') _update(call.arguments as Map);
    });
  }

  static void _update(Map map) {
    state.value = map['active'] == true ? AirPlayState.fromMap(map) : null;
  }

  /// Loads the current state, e.g. when the cast page opens again.
  static Future<void> refresh() async {
    _init();
    final map = await _channel.invokeMapMethod<String, Object?>('state');
    if (map != null) _update(map);
  }

  /// Shows the AirPlay device list and plays [url] from [start] on the
  /// chosen receiver. Closing the list without choosing one cancels.
  static Future<void> start({
    required String url,
    String? title,
    Duration start = Duration.zero,
  }) {
    _init();
    return _channel.invokeMethod('start', {
      'url': url,
      'title': ?title,
      'startMs': start.inMilliseconds,
    });
  }

  static Future<void> play() => _channel.invokeMethod('play');

  static Future<void> pause() => _channel.invokeMethod('pause');

  static Future<void> seek(Duration position) =>
      _channel.invokeMethod('seek', {'ms': position.inMilliseconds});

  /// Ends the cast on the receiver.
  static Future<void> stop() => _channel.invokeMethod('stop');
}
