import 'dart:ui' show VoidCallback;

import 'package:PiliPlus/plugin/pl_player/models/data_source.dart';
import 'package:PiliPlus/plugin/pl_player/models/tone_mapping_type.dart';

/// Reads what the system player found out about the video it loaded (see
/// `SystemPlayer.info`).
typedef SystemPlayerInfoReader = Future<Map<String, Object?>> Function();

/// Asked right before mpv opens a video. [systemInfo] is given when the
/// system player loaded or tried this video, as it may have read the stream
/// already.
typedef MpvPlanner = Future<MpvPlan?> Function(
  SystemPlayerInfoReader? systemInfo,
);

/// iOS: how mpv plays a video it cannot show right with its usual options.
/// There mpv renders 8-bit SDR, tone mapping HDR, and libmpv 0.39's gpu
/// renderer has no Dolby Vision reshaping.
class MpvPlan {
  const MpvPlan({
    this.dataSource,
    this.extras = const {},
    this.toast,
    this.onUse,
  });

  /// Played instead of the source given to `setDataSource`.
  final DataSource? dataSource;

  /// Per-file mpv options. media_kit joins them with commas, so no value may
  /// contain one.
  final Map<String, String> extras;

  /// Shown when mpv opens the video.
  final String? toast;

  /// Called when mpv opens the video with this plan, so the page can show
  /// what plays.
  final VoidCallback? onUse;

  /// Per-file options for a stream mpv plays as it is.
  ///
  /// Dolby Vision profile 8.4 gets HLG's scene-referred light back. libmpv
  /// 0.39 decodes it as PQ (the Dolby Vision mapping), and its gpu renderer
  /// restores the HLG base layer's transfer but not its light, so it skips
  /// HLG's OOTF and the picture comes out too bright and flat. `gamma=hlg`
  /// keeps it HLG on a newer libmpv, which may not restore the transfer.
  ///
  /// HDR gets the tone mapping chosen in the settings.
  static Map<String, String> extrasFor({
    required bool hdr,
    bool profile84 = false,
    required ToneMappingType toneMapping,
  }) => {
    if (profile84) 'vf': 'format:gamma=hlg:light=hlg',
    if (hdr && toneMapping != ToneMappingType.auto)
      'tone-mapping': toneMapping.name,
  };
}

/// What mpv on iOS does with a Dolby Vision stream (see [MpvPlan]).
enum DolbyVisionProfile {
  /// No backward-compatible base layer: nothing makes mpv show it right, so
  /// another quality plays instead.
  p5,

  /// HLG base layer (compatibility id 4), played with
  /// [MpvPlan.extrasFor]'s `profile84`.
  p84,

  /// Any other profile: mpv shows its base layer like other HDR.
  other,
  ;

  /// From the stream as the native side read it: `SystemPlayer.probe`'s
  /// `codecs`, or `SystemPlayer.info`'s `videoCodecs`. null when it read none.
  static DolbyVisionProfile? of(Map<String, Object?>? stream) {
    final codecs = stream?['codecs'] ?? stream?['videoCodecs'];
    if (codecs is! String) return null;
    if (codecs.startsWith('dvh1.05') || codecs.startsWith('dvhe.05')) {
      return p5;
    }
    final supplemental = stream?['supplementalCodecs'];
    if (stream?['videoRange'] == 'HLG' ||
        (supplemental is String && supplemental.endsWith('/db4h'))) {
      return p84;
    }
    return other;
  }
}
