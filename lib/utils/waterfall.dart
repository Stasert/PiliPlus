import 'package:PiliPlus/common/skeleton/dynamic_card.dart';
import 'package:PiliPlus/common/sliver_single_child_delegate.dart';
import 'package:PiliPlus/common/style.dart';
import 'package:PiliPlus/common/widgets/sliver/sliver_constrained_cross_axis.dart';
import 'package:PiliPlus/utils/global_data.dart';
import 'package:PiliPlus/utils/grid.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:PiliPlus/utils/ios/foldable_helper.dart';
import 'package:flutter/rendering.dart' show SliverConstraints;
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart'
    show SliverSimpleGridDelegate;
import 'package:material_ui/material_ui.dart';

mixin DynMixin<T extends StatefulWidget> on State<T> {
  int Function(int) get _columnPolicy {
    final automatic = IOSFoldableHelper.isAuto;
    // MediaQuery is the owning route's viewport. The global first FlutterView
    // can still contain the previous display's metrics during route migration.
    final unfolded =
        (MediaQuery.sizeOf(context) * Pref.uiScale).shortestSide >= 600;
    return (count) =>
        automatic ? (unfolded ? (count < 2 ? 2 : count) : 1) : count;
  }

  SliverSimpleGridDelegateWithMaxCrossAxisExtent_ get dynGridDelegate =>
      SliverSimpleGridDelegateWithMaxCrossAxisExtent_(
        maxCrossAxisExtent: Grid.smallCardWidth * 2,
        adjustCrossAxisCount: _columnPolicy,
      );

  Widget buildPage(Widget child) {
    if (GlobalData().dynamicsWaterfallFlow) {
      return child;
    }
    return CenteredSliverConstrainedCrossAxis(
      maxExtent: Grid.smallCardWidth * 2,
      sliver: child,
    );
  }

  Widget get dynSkeleton {
    if (GlobalData().dynamicsWaterfallFlow) {
      final delegate = dynGridDelegate;
      return SliverLayoutBuilder(
        builder: (context, constraints) {
          final count = delegate.getCrossAxisCount(constraints, 4);
          final width = (constraints.crossAxisExtent - 4 * (count - 1)) / count;
          return SliverGrid(
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: count,
              crossAxisSpacing: 4,
              mainAxisSpacing: 4,
              mainAxisExtent: width / Style.aspectRatio + 50,
            ),
            delegate: const SliverSingleChildDelegate(
              count: 10,
              child: DynamicCardSkeleton(),
            ),
          );
        },
      );
    }
    return const SliverPrototypeExtentList(
      prototypeItem: DynamicCardSkeleton(),
      delegate: SliverSingleChildDelegate(
        count: 10,
        child: DynamicCardSkeleton(),
      ),
    );
  }
}

// ignore: camel_case_types
class SliverSimpleGridDelegateWithMaxCrossAxisExtent_
    extends SliverSimpleGridDelegate {
  /// Creates a delegate that makes grid layouts with tiles that have a maximum
  /// cross-axis extent.
  ///
  /// The [maxCrossAxisExtent] argument must be greater than zero.
  SliverSimpleGridDelegateWithMaxCrossAxisExtent_({
    required this.maxCrossAxisExtent,
    this.adjustCrossAxisCount,
  }) : assert(maxCrossAxisExtent > 0);

  /// {@template fsgv.global.maxCrossAxisExtent}
  /// The maximum extent of tiles in the cross axis.
  ///
  /// This delegate will select a cross-axis extent for the tiles that is as
  /// large as possible subject to the following conditions:
  ///
  ///  - The extent evenly divides the cross-axis extent of the grid.
  ///  - The extent is at most [maxCrossAxisExtent].
  ///
  /// For example, if the grid is vertical, the grid is 500.0 pixels wide, and
  /// [maxCrossAxisExtent] is 150.0, this delegate will create a grid with 4
  /// columns that are 125.0 pixels wide.
  /// {@endtemplate}
  final double maxCrossAxisExtent;

  /// 按当前约束算出列数后再调整；相同宽度也必须重新应用显示策略。
  final int Function(int count)? adjustCrossAxisCount;

  @override
  int getCrossAxisCount(
    SliverConstraints constraints,
    double crossAxisSpacing,
  ) {
    final count =
        (constraints.crossAxisExtent / (maxCrossAxisExtent + crossAxisSpacing))
            .ceil();
    final adjusted = adjustCrossAxisCount?.call(count) ?? count;
    return adjusted < 1 ? 1 : adjusted;
  }

  @override
  bool shouldRelayout(
    SliverSimpleGridDelegateWithMaxCrossAxisExtent_ oldDelegate,
  ) {
    return oldDelegate.maxCrossAxisExtent != maxCrossAxisExtent ||
        oldDelegate.adjustCrossAxisCount != adjustCrossAxisCount;
  }
}
