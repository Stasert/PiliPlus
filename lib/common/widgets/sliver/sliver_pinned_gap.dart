import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// 给浮在内容上面的顶栏让位：前面的内容在视口里露出的部分不到 [extent] 时，
/// 在它下面撑开一段空白，补足到 [extent]；平时不占位置，也不增加滚动距离。
///
/// 放在 NestedScrollView 的头部最后，正文（比如标签栏）滑到顶时会停在顶栏
/// 下面，而不是钻到顶栏底下
class SliverPinnedGap extends LeafRenderObjectWidget {
  const SliverPinnedGap({super.key, required this.extent});

  final double extent;

  @override
  RenderSliverPinnedGap createRenderObject(BuildContext context) =>
      RenderSliverPinnedGap(extent);

  @override
  void updateRenderObject(
    BuildContext context,
    RenderSliverPinnedGap renderObject,
  ) => renderObject.extent = extent;
}

class RenderSliverPinnedGap extends RenderSliver {
  RenderSliverPinnedGap(this._extent);

  double _extent;
  set extent(double value) {
    if (_extent == value) return;
    _extent = value;
    markNeedsLayout();
  }

  @override
  void performLayout() {
    // 前面的内容已经占用的视口高度
    final painted =
        constraints.viewportMainAxisExtent - constraints.remainingPaintExtent;
    final gap = math.max(
      0.0,
      math.min(_extent - painted, constraints.remainingPaintExtent),
    );
    geometry = SliverGeometry(
      paintExtent: gap,
      layoutExtent: gap,
      maxPaintExtent: _extent,
    );
  }
}
