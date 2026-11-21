import 'package:PiliPlus/common/style.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:material_ui/material_ui.dart';

/// Preserve the window's rail insets after individual pages consume MediaQuery.
class RailViewportScope extends InheritedWidget {
  const RailViewportScope({
    super.key,
    required this.insets,
    required this.windowWidth,
    this.normalizedTop = false,
    required super.child,
  });
  final EdgeInsets insets;
  final double windowWidth;
  final bool normalizedTop;
  static RailViewportScope? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<RailViewportScope>();
  @override
  bool updateShouldNotify(RailViewportScope oldWidget) =>
      insets != oldWidget.insets ||
      windowWidth != oldWidget.windowWidth ||
      normalizedTop != oldWidget.normalizedTop;
}

/// The viewport paints to the window edge, while each page retains its normal
/// content width. The next page can pass under the rail without reflowing grids.
class RailPageViewport extends StatelessWidget {
  const RailPageViewport({
    super.key,
    required this.axis,
    required this.child,
    this.allowExtension = true,
    this.leadingPanelWidth = 0,
    this.trailingPanelWidth = 0,
  });

  final Axis axis;
  final bool allowExtension;

  /// Fixed siblings of this pager, excluded from its content width.
  final double leadingPanelWidth, trailingPanelWidth;

  /// 左右滑动的页面，每一页用 [RailPagePadding] 包住
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scope = RailViewportScope.of(context);
    final enabled = scope != null && allowExtension && axis == Axis.horizontal;
    return _RailViewport(
      insets: enabled ? scope.insets : EdgeInsets.zero,
      windowWidth: scope?.windowWidth ?? 0,
      leadingPanelWidth: enabled ? leadingPanelWidth : 0,
      trailingPanelWidth: enabled ? trailingPanelWidth : 0,
      child: child,
    );
  }
}

class _RailViewport extends SingleChildRenderObjectWidget {
  const _RailViewport({
    required this.insets,
    required this.windowWidth,
    required this.leadingPanelWidth,
    required this.trailingPanelWidth,
    super.child,
  });

  final EdgeInsets insets;
  final double windowWidth;
  final double leadingPanelWidth, trailingPanelWidth;

  @override
  _RenderRailViewport createRenderObject(BuildContext context) =>
      _RenderRailViewport(
        insets,
        windowWidth,
        leadingPanelWidth,
        trailingPanelWidth,
      );

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderRailViewport renderObject,
  ) {
    renderObject
      ..insets = insets
      ..windowWidth = windowWidth
      ..leadingPanelWidth = leadingPanelWidth
      ..trailingPanelWidth = trailingPanelWidth;
  }
}

class _RenderRailViewport extends RenderProxyBox {
  _RenderRailViewport(
    this._insets,
    this._windowWidth,
    this._leadingPanelWidth,
    this._trailingPanelWidth,
  );

  double _leadingPanelWidth;
  set leadingPanelWidth(double value) {
    if (_leadingPanelWidth == value) return;
    _leadingPanelWidth = value;
    markNeedsLayout();
  }

  double _trailingPanelWidth;
  set trailingPanelWidth(double value) {
    if (_trailingPanelWidth == value) return;
    _trailingPanelWidth = value;
    markNeedsLayout();
  }

  EdgeInsets _insets;
  set insets(EdgeInsets value) {
    if (_insets == value) return;
    _insets = value;
    markNeedsLayout();
  }

  double _windowWidth;
  set windowWidth(double value) {
    if (_windowWidth == value) return;
    _windowWidth = value;
    markNeedsLayout();
  }

  /// 延伸到竖状态栏下面的宽度，每一页的右边距
  double _right = 0;

  final Set<_RenderRailPagePadding> _pages = {};

  double _rightFor(BoxConstraints constraints) {
    final inset = _insets.right;
    if (inset > 0 &&
        constraints.hasBoundedWidth &&
        constraints.hasBoundedHeight) {
      final gap =
          _windowWidth -
          constraints.maxWidth -
          _leadingPanelWidth -
          _trailingPanelWidth;
      if (gap >= inset - 1 && gap <= _insets.horizontal + 1) {
        // Reach the window edge even when a fixed panel follows the pager.
        // Each page reserves this whole extension, retaining its content size.
        return inset + _trailingPanelWidth;
      }
    }
    return 0;
  }

  BoxConstraints _childConstraints(BoxConstraints constraints, double right) {
    if (right == 0) return constraints;
    final width = constraints.maxWidth + right;
    return BoxConstraints(
      minWidth: width,
      maxWidth: width,
      minHeight: constraints.minHeight,
      maxHeight: constraints.maxHeight,
    );
  }

  @override
  Size computeDryLayout(covariant BoxConstraints constraints) {
    final right = _rightFor(constraints);
    final childSize =
        child?.getDryLayout(_childConstraints(constraints, right)) ?? Size.zero;
    return constraints.constrain(
      Size(childSize.width - right, childSize.height),
    );
  }

  @override
  void performLayout() {
    final right = _rightFor(constraints);
    if (right != _right) {
      _right = right;
      // 页面宽度可能刚好没变（例如窗口同时变窄），这时页面不会重新布局，
      // 要主动通知它们更新右边距
      if (_pages.isNotEmpty) {
        invokeLayoutCallback<BoxConstraints>((_) {
          for (final page in _pages) {
            page.markNeedsLayout();
          }
        });
      }
    }
    final child = this.child;
    if (child == null) {
      size = constraints.smallest;
      return;
    }
    child.layout(_childConstraints(constraints, right), parentUsesSize: true);
    size = constraints.constrain(
      Size(child.size.width - right, child.size.height),
    );
  }

  final _panelClip = LayerHandle<ClipPathLayer>();

  @override
  void dispose() {
    _panelClip.layer = null;
    super.dispose();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final child = this.child;
    if (_right > 0 && _trailingPanelWidth > 0 && child != null) {
      // The incoming page may paint beneath the native rail, but must never
      // paint over/through the fixed UP panel between this pager and the rail.
      final clip = Path()
        ..addRect(Offset.zero & size)
        ..addRect(
          Rect.fromLTRB(
            size.width + _trailingPanelWidth,
            0,
            child.size.width,
            size.height,
          ),
        );
      _panelClip.layer = context.pushClipPath(
        needsCompositing,
        offset,
        Offset.zero & child.size,
        clip,
        (context, offset) => context.paintChild(child, offset),
        clipBehavior: Clip.hardEdge,
        oldLayer: _panelClip.layer,
      );
    } else {
      _panelClip.layer = null;
      super.paint(context, offset);
    }
  }
}

/// 包住 [RailPageViewport] 里的每一页，留出竖状态栏的宽度
class RailPagePadding extends SingleChildRenderObjectWidget {
  const RailPagePadding({super.key, super.child});

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderRailPagePadding();
}

class _RenderRailPagePadding extends RenderShiftedBox {
  _RenderRailPagePadding() : super(null);

  _RenderRailViewport? _viewport;

  double get _right => _viewport?._right ?? 0;

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    RenderObject? node = parent;
    while (node != null && node is! _RenderRailViewport) {
      node = node.parent;
    }
    _viewport = node as _RenderRailViewport?;
    _viewport?._pages.add(this);
  }

  @override
  void detach() {
    _viewport?._pages.remove(this);
    _viewport = null;
    super.detach();
  }

  @override
  double computeMinIntrinsicWidth(double height) =>
      (child?.getMinIntrinsicWidth(height) ?? 0) + _right;

  @override
  double computeMaxIntrinsicWidth(double height) =>
      (child?.getMaxIntrinsicWidth(height) ?? 0) + _right;

  @override
  double computeMinIntrinsicHeight(double width) =>
      child?.getMinIntrinsicHeight(
        (width - _right).clamp(0, double.infinity),
      ) ??
      0;

  @override
  double computeMaxIntrinsicHeight(double width) =>
      child?.getMaxIntrinsicHeight(
        (width - _right).clamp(0, double.infinity),
      ) ??
      0;

  @override
  Size computeDryLayout(covariant BoxConstraints constraints) {
    final right = _right;
    final child = this.child;
    if (child == null) return constraints.constrain(Size(right, 0));
    final childSize = child.getDryLayout(
      constraints.deflate(EdgeInsets.only(right: right)),
    );
    return constraints.constrain(
      Size(childSize.width + right, childSize.height),
    );
  }

  @override
  void performLayout() {
    final right = _right;
    final child = this.child;
    if (child == null) {
      size = constraints.constrain(Size(right, 0));
      return;
    }
    child.layout(
      constraints.deflate(EdgeInsets.only(right: right)),
      parentUsesSize: true,
    );
    (child.parentData! as BoxParentData).offset = Offset.zero;
    size = constraints.constrain(
      Size(child.size.width + right, child.size.height),
    );
  }
}

/// 见 [RailPageViewport]
class RailTabBarView extends StatelessWidget {
  const RailTabBarView({
    super.key,
    required this.children,
    this.controller,
    this.physics,
    this.scrollDirection = Axis.horizontal,
    this.hitTestBehavior = HitTestBehavior.opaque,
    this.horizontalDragGestureRecognizer = HorizontalDragGestureRecognizer.new,
    this.dragStartBehavior = DragStartBehavior.start,
    this.viewportFraction = 1.0,
    this.clipBehavior = Clip.hardEdge,
    this.leadingPanelWidth = 0,
    this.trailingPanelWidth = 0,
  });
  final List<Widget> children;
  final TabController? controller;
  final ScrollPhysics? physics;
  final Axis scrollDirection;
  final HitTestBehavior hitTestBehavior;
  final ValueGetter<HorizontalDragGestureRecognizer>
  horizontalDragGestureRecognizer;
  final DragStartBehavior dragStartBehavior;
  final double viewportFraction;
  final Clip clipBehavior;
  final double leadingPanelWidth, trailingPanelWidth;
  @override
  Widget build(BuildContext context) => RailPageViewport(
    axis: scrollDirection,
    allowExtension: viewportFraction == 1,
    leadingPanelWidth: leadingPanelWidth,
    trailingPanelWidth: trailingPanelWidth,
    child: TabBarView(
      controller: controller,
      physics: physics,
      scrollDirection: scrollDirection,
      hitTestBehavior: hitTestBehavior,
      horizontalDragGestureRecognizer: horizontalDragGestureRecognizer,
      dragStartBehavior: dragStartBehavior,
      viewportFraction: viewportFraction,
      clipBehavior: clipBehavior,
      children: [
        for (final child in children) RailPagePadding(child: child),
      ],
    ),
  );
}

class RailPageView extends StatelessWidget {
  const RailPageView({
    super.key,
    this.children = const [],
    this.controller,
    this.physics,
    this.onPageChanged,
    this.scrollDirection = Axis.horizontal,
    this.horizontalDragGestureRecognizer = HorizontalDragGestureRecognizer.new,
    this.allowImplicitScrolling = false,
    this.pageSnapping = true,
    this.padEnds = true,
    this.reverse = false,
    this.clipBehavior = Clip.hardEdge,
    this.hitTestBehavior = HitTestBehavior.opaque,
    this.dragStartBehavior = DragStartBehavior.start,
    this.leadingPanelWidth = 0,
    this.trailingPanelWidth = 0,
  }) : itemBuilder = null,
       itemCount = null;
  const RailPageView.builder({
    super.key,
    required this.itemBuilder,
    this.itemCount,
    this.controller,
    this.physics,
    this.onPageChanged,
    this.scrollDirection = Axis.horizontal,
    this.horizontalDragGestureRecognizer = HorizontalDragGestureRecognizer.new,
    this.allowImplicitScrolling = false,
    this.pageSnapping = true,
    this.padEnds = true,
    this.reverse = false,
    this.clipBehavior = Clip.hardEdge,
    this.hitTestBehavior = HitTestBehavior.opaque,
    this.dragStartBehavior = DragStartBehavior.start,
    this.leadingPanelWidth = 0,
    this.trailingPanelWidth = 0,
  }) : children = const [];
  final List<Widget> children;
  final NullableIndexedWidgetBuilder? itemBuilder;
  final int? itemCount;
  final PageController? controller;
  final ScrollPhysics? physics;
  final ValueChanged<int>? onPageChanged;
  final Axis scrollDirection;
  final ValueGetter<HorizontalDragGestureRecognizer>
  horizontalDragGestureRecognizer;
  final bool allowImplicitScrolling, pageSnapping, padEnds, reverse;
  final Clip clipBehavior;
  final HitTestBehavior hitTestBehavior;
  final DragStartBehavior dragStartBehavior;
  final double leadingPanelWidth, trailingPanelWidth;
  @override
  Widget build(BuildContext context) => RailPageViewport(
    axis: scrollDirection,
    allowExtension: (controller?.viewportFraction ?? 1) == 1,
    leadingPanelWidth: leadingPanelWidth,
    trailingPanelWidth: trailingPanelWidth,
    child: PageView.builder(
      controller: controller,
      physics: physics,
      onPageChanged: onPageChanged,
      scrollDirection: scrollDirection,
      horizontalDragGestureRecognizer: horizontalDragGestureRecognizer,
      allowImplicitScrolling: allowImplicitScrolling,
      pageSnapping: pageSnapping,
      padEnds: padEnds,
      reverse: reverse,
      clipBehavior: clipBehavior,
      hitTestBehavior: hitTestBehavior,
      dragStartBehavior: dragStartBehavior,
      itemCount: itemBuilder == null ? children.length : itemCount,
      itemBuilder: (context, index) {
        final child = itemBuilder == null
            ? children[index]
            : itemBuilder!(context, index);
        return child == null ? null : RailPagePadding(child: child);
      },
    ),
  );
}

/// Native rail space is reserved once by NativeSafeArea. Page gutters must not
/// add another gap on top of the user-selected native-point margin.
abstract final class RailSpacing {
  static const footprint = 72.0;
  static const clearance = 4.0;
  static const maxClearance = 32.0;

  static double normalizeClearance(Object? value) =>
      value is num && value.isFinite
      ? value.toDouble().clamp(0.0, maxClearance).roundToDouble()
      : clearance;

  static double rightInset(
    double systemInset, {
    required bool fullScreen,
    double contentMargin = clearance,
  }) => fullScreen
      ? 0
      : (systemInset >= footprint
            ? footprint + normalizeClearance(contentMargin)
            : systemInset);
}

double railTrailingSpace(BuildContext context, double normal) =>
    (RailViewportScope.of(context)?.insets.right ?? 0) > 0 ? 0 : normal;

/// Only for the outside gutter of a page/list, never for card internals.
EdgeInsets railPageInsets(BuildContext context, EdgeInsets normal) =>
    normal.copyWith(right: railTrailingSpace(context, normal.right));

/// The production recommendation/live feed frame, including its clipped outer
/// gutter. Sharing it makes the visible card-to-rail clearance measurable.
class RailFeedFrame extends StatelessWidget {
  const RailFeedFrame({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => Container(
    clipBehavior: Clip.hardEdge,
    margin: EdgeInsets.only(
      left: Style.safeSpace,
      right: railTrailingSpace(context, Style.safeSpace),
    ),
    decoration: const BoxDecoration(borderRadius: Style.mdRadius),
    child: child,
  );
}
