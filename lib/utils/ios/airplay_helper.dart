import 'dart:math' show max, min;

import 'package:PiliPlus/models/common/video/base_quality.dart';
import 'package:PiliPlus/models/video/play/url.dart';
import 'package:PiliPlus/plugin/pl_player/system_player.dart';
import 'package:PiliPlus/utils/extension/iterable_ext.dart';
import 'package:PiliPlus/utils/video_utils.dart';
import 'package:collection/collection.dart';
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
    this.quality,
    this.error,
  });

  factory AirPlayState.fromMap(Map map) => AirPlayState(
    connected: map['connected'] == true,
    playing: map['playing'] == true,
    position: Duration(milliseconds: map['positionMs'] as int? ?? 0),
    duration: Duration(milliseconds: map['durationMs'] as int? ?? 0),
    device: map['device'] as String?,
    title: map['title'] as String?,
    quality: map['quality'] as String?,
    error: map['error'] as String?,
  );

  /// Whether a receiver is connected (the device list may still be open).
  final bool connected;
  final bool playing;
  final Duration position;
  final Duration duration;
  final String? device;
  final String? title;

  /// Quality of what is being cast, e.g. 杜比视界 or 720P.
  final String? quality;
  final String? error;
}

/// The DASH stream AirPlay casts instead of bilibili's TV MP4, which is SDR
/// and at most 720P. It comes from the TV API too (`fnval` 4048), whose URLs
/// need no Referer, so the receiver can load it; the native side builds HLS
/// playlists from it, as for the system player.
@immutable
class AirPlayDash {
  const AirPlayDash({
    required this.video,
    this.audio,
    this.frameRate,
    this.fallback,
    this.fallbackFrameRate,
    required this.quality,
    this.fallbackQuality,
  });

  final SystemPlayerTrack video;
  final SystemPlayerTrack? audio;
  final double? frameRate;

  /// A second variant for receivers that cannot play an HDR [video], e.g. a
  /// first-generation Apple TV 4K, whose specs list no HLG (the base layer
  /// of bilibili's Dolby Vision), or a TV without HDR: HDR10 next to Dolby
  /// Vision or HDR Vivid, otherwise SDR. The receiver picks what it can play.
  final SystemPlayerTrack? fallback;
  final double? fallbackFrameRate;

  /// Shown on the cast page, see [label]: [quality], and once the receiver
  /// plays the [fallback], both, e.g. 杜比视界 / HDR (the native side cannot
  /// tell when it switches back).
  final String quality;
  final String? fallbackQuality;

  static const _maxHeight = 2160;

  /// Codecs AirPlay receivers play.
  static const _hevc = ['hev1', 'hvc1', 'dvh1', 'dvhe'];
  static const _avc = 'avc1';
  static const _audio = ['mp4a', 'ec-3']; // AAC, E-AC-3 (Dolby)

  static const _hdrQualities = {
    125, // HDR 真彩
    126, // 杜比视界
    129, // HDR Vivid
  };

  /// The video closest to [quality] (the one playing on the phone) that
  /// receivers can play: AVC, HEVC or Dolby Vision, at most 2160p, no AV1 or
  /// 8K. Audio as close to [audioQuality] as AAC or E-AC-3 gets.
  ///
  /// Null, so the MP4 is cast, when there is no such video, when it is worse
  /// than the MP4's [mp4Quality], or when there is audio but none of it fits.
  static AirPlayDash? pick(
    PlayUrlModel data, {
    required int quality,
    int? mp4Quality,
    int? audioQuality,
  }) {
    final videos = data.dash?.video?.where(_castable).toList();
    if (videos == null || videos.isEmpty) return null;
    final target = videos.findTargetMedia((e) => e.id, quality).id;
    if (mp4Quality != null && target < mp4Quality) return null;
    final video = _preferred(videos.where((e) => e.id == target));
    final fallback = _fallback(videos, video.id, mp4Quality);

    AudioItem? audio;
    if (data.dash?.audio case final audios? when audios.isNotEmpty) {
      final castable = audios
          .where(
            (e) =>
                e.playUrls.isNotEmpty &&
                _audio.any((e.codecs ?? '').startsWith),
          )
          .toList();
      if (castable.isEmpty) return null;
      audio =
          castable.firstWhereOrNull((e) => e.id == audioQuality) ??
          VideoUtils.findTargetAudio(
            castable,
            audioQuality ?? AudioQuality.k192.code,
          );
    }

    return AirPlayDash(
      video: _videoTrack(video),
      audio: audio == null
          ? null
          : SystemPlayerTrack.fromItem(
              audio,
              _https(VideoUtils.getCdnUrl(audio.playUrls, isAudio: true)),
            ),
      frameRate: double.tryParse(video.frameRate ?? ''),
      fallback: fallback == null ? null : _videoTrack(fallback),
      fallbackFrameRate: double.tryParse(fallback?.frameRate ?? ''),
      quality: label(video.id),
      fallbackQuality: fallback == null ? null : label(fallback.id),
    );
  }

  /// The stream of one quality that most receivers play: AVC up to 1080P,
  /// which all AirPlay receivers decode, HEVC or Dolby Vision above.
  /// bilibili's SDR HEVC is mostly `hev1` (parameter sets in the samples),
  /// which Apple's HLS authoring spec advises against (rule 1.10).
  static VideoItem _preferred(Iterable<VideoItem> sameQuality) {
    bool isAvc(VideoItem e) => (e.codecs ?? '').startsWith(_avc);
    final first = sameQuality.first;
    return first.id <= VideoQuality.high108060.code
        ? sameQuality.firstWhereOrNull(isAvc) ?? first
        : sameQuality.firstWhereOrNull((e) => !isAvc(e)) ?? first;
  }

  /// The [fallback] for a video of quality [main], if that is HDR: HDR10 next
  /// to Dolby Vision or HDR Vivid, otherwise the best SDR there is, unless it
  /// is worse than the MP4's [mp4Quality].
  static VideoItem? _fallback(
    List<VideoItem> videos,
    int main,
    int? mp4Quality,
  ) {
    if (!_hdrQualities.contains(main)) return null;
    final hdr10 = VideoQuality.hdr.code;
    if (main != hdr10 && videos.any((e) => e.id == hdr10)) {
      return _preferred(videos.where((e) => e.id == hdr10));
    }
    final sdr = videos.where((e) => !_hdrQualities.contains(e.id)).toList();
    if (sdr.isEmpty) return null;
    final best = sdr.map((e) => e.id).max;
    if (mp4Quality != null && best < mp4Quality) return null;
    return _preferred(sdr.where((e) => e.id == best));
  }

  static SystemPlayerTrack _videoTrack(VideoItem video) =>
      SystemPlayerTrack.fromItem(
        video,
        _https(VideoUtils.getCdnUrl(video.playUrls)),
      );

  /// The TV API hands out http URLs, and the CDN serves the same URLs over
  /// https. The phone loads them too (the segment index, and AVPlayer until
  /// the receiver takes over), where App Transport Security blocks http.
  /// Only the scheme changes: the signed query must stay byte for byte.
  static String _https(String url) =>
      url.startsWith('http://') ? 'https://${url.substring(7)}' : url;

  static bool _castable(VideoItem e) {
    final codecs = e.codecs ?? '';
    final width = e.width ?? 0;
    final height = e.height ?? 0;
    // The short side, so portrait 4K counts as 2160p.
    final short = width > 0 && height > 0
        ? min(width, height)
        : max(width, height);
    return e.playUrls.isNotEmpty &&
        e.id != VideoQuality.super8k.code &&
        short <= _maxHeight &&
        (_hevc.any(codecs.startsWith) || codecs.startsWith(_avc));
  }

  /// Short name of a bilibili quality code, e.g. 杜比视界, 4K or 1080P+.
  static String label(int quality) => quality == VideoQuality.dolbyVision.code
      ? VideoQuality.dolbyVision.desc
      : VideoQuality.fromCode(quality).shortDesc;

  Map<String, Object> toMap() => {
    'video': video.toMap(),
    'audio': ?audio?.toMap(),
    'frameRate': ?frameRate,
    'fallback': ?fallback?.toMap(),
    'fallbackFrameRate': ?fallbackFrameRate,
    'quality': quality,
    'fallbackQuality': ?fallbackQuality,
  };
}

/// Fetches the [AirPlayDash] to cast, null when there is none. Called for
/// every cast: bilibili's CDN answers 403 once the same signed URLs have been
/// pulled a few times, so a retry must not reuse those of the last cast.
typedef AirPlayDashLoader = Future<AirPlayDash?> Function();

/// AirPlay casting on iOS. The receiver downloads the video itself: the DASH
/// stream when there is one ([AirPlayDash]), otherwise the same progressive
/// MP4 as DLNA casting. The cast page is the remote control.
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

  /// Shows the AirPlay device list and plays the DASH stream from [dash], or
  /// the MP4 [url] of [quality], from [start] on the chosen receiver. The MP4
  /// is also the fallback when there is no DASH stream or the receiver cannot
  /// play it. Closing the list without choosing a device cancels.
  ///
  /// The list opens right away; [dash] runs meanwhile.
  static Future<void> start({
    required String url,
    String? title,
    Duration start = Duration.zero,
    String? quality,
    AirPlayDashLoader? dash,
  }) async {
    _init();
    // Null when the native side casts the MP4 without waiting (iOS 14).
    final session = await _channel.invokeMethod<int>('start', {
      'url': url,
      'title': ?title,
      'startMs': start.inMilliseconds,
      'quality': ?quality,
      'withDash': dash != null,
    });
    if (session == null || dash == null) return;
    AirPlayDash? stream;
    try {
      stream = await dash();
    } catch (_) {
      // The MP4 then.
    }
    // Also without a stream: the MP4 is cast at once instead of on timeout.
    await _channel.invokeMethod('dash', {
      'session': session,
      'dash': ?stream?.toMap(),
    });
  }

  static Future<void> play() => _channel.invokeMethod('play');

  static Future<void> pause() => _channel.invokeMethod('pause');

  static Future<void> seek(Duration position) =>
      _channel.invokeMethod('seek', {'ms': position.inMilliseconds});

  /// Ends the cast on the receiver.
  static Future<void> stop() => _channel.invokeMethod('stop');
}
