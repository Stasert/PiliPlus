import 'package:PiliPlus/models/common/enum_with_label.dart';

/// iOS「内置播放器 HDR 色调映射」: mpv's `--tone-mapping`, stored by [name].
/// These are the curves of libmpv 0.39's gpu renderer; it takes any other
/// value as auto (bt.2390).
enum ToneMappingType implements EnumWithLabel {
  auto('自动（默认）'),
  hable('hable'),
  mobius('mobius'),
  reinhard('reinhard'),
  clip('clip'),
  ;

  @override
  final String label;
  const ToneMappingType(this.label);
}
