import 'package:PiliPlus/common/style.dart';
import 'package:flutter/gestures.dart';
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
    required this.builder,
    this.allowExtension = true,
  });
  final Axis axis;
  final bool allowExtension;
  final Widget Function(double rightInset) builder;
  @override
  Widget build(BuildContext context) {
    final scope = RailViewportScope.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        if (!constraints.hasBoundedWidth || !constraints.hasBoundedHeight) {
          return builder(0);
        }
        final gap =
            (scope?.windowWidth ?? constraints.maxWidth) - constraints.maxWidth;
        final insets = scope?.insets ?? EdgeInsets.zero;
        final extendsToRail =
            allowExtension &&
            axis == Axis.horizontal &&
            insets.right > 0 &&
            gap >= insets.right - 1 &&
            gap <= insets.horizontal + 1;
        final right = extendsToRail ? insets.right : 0.0;
        final width = constraints.maxWidth + right;
        // Keep this tree stable when fullscreen releases the inset or the device
        // folds; the live page and player State must survive those changes.
        return OverflowBox(
          alignment: Alignment.topLeft,
          minWidth: width,
          maxWidth: width,
          minHeight: constraints.maxHeight,
          maxHeight: constraints.maxHeight,
          child: builder(right),
        );
      },
    );
  }
}

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
  @override
  Widget build(BuildContext context) => RailPageViewport(
    axis: scrollDirection,
    allowExtension: viewportFraction == 1,
    builder: (right) => TabBarView(
      controller: controller,
      physics: physics,
      scrollDirection: scrollDirection,
      hitTestBehavior: hitTestBehavior,
      horizontalDragGestureRecognizer: horizontalDragGestureRecognizer,
      dragStartBehavior: dragStartBehavior,
      viewportFraction: viewportFraction,
      clipBehavior: clipBehavior,
      children: [
        for (final child in children)
          Padding(
            padding: EdgeInsets.only(right: right),
            child: child,
          ),
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
  @override
  Widget build(BuildContext context) => RailPageViewport(
    axis: scrollDirection,
    allowExtension: (controller?.viewportFraction ?? 1) == 1,
    builder: (right) => PageView.builder(
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
        return child == null
            ? null
            : Padding(
                padding: EdgeInsets.only(right: right),
                child: child,
              );
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
