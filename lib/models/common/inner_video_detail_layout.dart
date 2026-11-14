import 'package:PiliPlus/models/common/enum_with_label.dart';

enum InnerVideoDetailLayout with EnumWithLabel {
  auto('自动'),
  split('固定左右双栏');

  const InnerVideoDetailLayout(this.label);

  @override
  final String label;

  static InnerVideoDetailLayout fromStorage(Object? value) =>
      value is int && value >= 0 && value < values.length
      ? values[value]
      : auto;
}
