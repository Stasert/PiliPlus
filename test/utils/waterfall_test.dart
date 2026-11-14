import 'package:PiliPlus/utils/waterfall.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

SliverConstraints _constraints(double crossAxisExtent) => SliverConstraints(
  axisDirection: AxisDirection.down,
  growthDirection: GrowthDirection.forward,
  userScrollDirection: ScrollDirection.idle,
  scrollOffset: 0,
  precedingScrollExtent: 0,
  overlap: 0,
  remainingPaintExtent: 800,
  crossAxisExtent: crossAxisExtent,
  crossAxisDirection: AxisDirection.right,
  viewportMainAxisExtent: 800,
  remainingCacheExtent: 800,
  cacheOrigin: 0,
);

void main() {
  test('列数按宽度计算', () {
    final delegate = SliverSimpleGridDelegateWithMaxCrossAxisExtent_(
      maxCrossAxisExtent: 480,
    );
    expect(delegate.getCrossAxisCount(_constraints(382), 4), 1);
    expect(delegate.getCrossAxisCount(_constraints(478), 4), 1);
    expect(delegate.getCrossAxisCount(_constraints(742), 4), 2);
  });

  test('列数调整：展开时至少两列，合上时单列，宽度变化时重新调整', () {
    var unfolded = true;
    final delegate = SliverSimpleGridDelegateWithMaxCrossAxisExtent_(
      maxCrossAxisExtent: 480,
      adjustCrossAxisCount: (count) => unfolded ? (count < 2 ? 2 : count) : 1,
    );
    // 展开竖着拿：扣掉竖状态栏和左侧 UP 主栏后不到两张卡片宽
    expect(delegate.getCrossAxisCount(_constraints(478), 4), 2);
    // 宽度够多列时不受影响
    expect(delegate.getCrossAxisCount(_constraints(1500), 4), 4);
    // 合上横着拿：宽度够两列也只显示一列
    unfolded = false;
    expect(delegate.getCrossAxisCount(_constraints(594), 4), 1);
  });
  test('same width reapplies fold policy and cross-axis spacing', () {
    var unfolded = true;
    final delegate = SliverSimpleGridDelegateWithMaxCrossAxisExtent_(
      maxCrossAxisExtent: 480,
      adjustCrossAxisCount: (count) => unfolded ? (count < 2 ? 2 : count) : 1,
    );
    final constraints = _constraints(478);
    expect(delegate.getCrossAxisCount(constraints, 4), 2);
    unfolded = false;
    expect(delegate.getCrossAxisCount(constraints, 4), 1);
    unfolded = true;
    expect(delegate.getCrossAxisCount(constraints, 4), 2);
    final plain = SliverSimpleGridDelegateWithMaxCrossAxisExtent_(
      maxCrossAxisExtent: 480,
    );
    expect(plain.getCrossAxisCount(_constraints(970), 4), 3);
    expect(plain.getCrossAxisCount(_constraints(970), 10), 2);
  });

  test(
    'a replacement display policy requests layout even at the same width',
    () {
      final inner = SliverSimpleGridDelegateWithMaxCrossAxisExtent_(
        maxCrossAxisExtent: 480,
        adjustCrossAxisCount: (_) => 2,
      );
      final outer = SliverSimpleGridDelegateWithMaxCrossAxisExtent_(
        maxCrossAxisExtent: 480,
        adjustCrossAxisCount: (_) => 1,
      );
      expect(outer.shouldRelayout(inner), isTrue);
      expect(outer.getCrossAxisCount(_constraints(478), 4), 1);
    },
  );
}
