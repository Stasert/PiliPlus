import 'package:PiliPlus/utils/ios/native_tab_bar.dart';
import 'package:PiliPlus/common/style.dart';
import 'package:PiliPlus/common/widgets/home_tools_slot.dart';
import 'package:PiliPlus/common/widgets/rail_page_view.dart';
import 'package:PiliPlus/common/widgets/custom_height_widget.dart';
import 'package:PiliPlus/common/widgets/image/network_img_layer.dart';
import 'package:PiliPlus/common/widgets/scroll_physics.dart' show tabBarView;
import 'package:PiliPlus/pages/common/common_page.dart';
import 'package:PiliPlus/pages/home/controller.dart';
import 'package:PiliPlus/pages/main/controller.dart';
import 'package:PiliPlus/pages/mine/controller.dart';
import 'package:PiliPlus/utils/extension/get_ext.dart';
import 'package:PiliPlus/utils/feed_back.dart';
import 'package:flutter/foundation.dart' show clampDouble;
import 'package:get/get.dart';
import 'package:material_design_icons_flutter/material_design_icons_flutter.dart';
import 'package:material_ui/material_ui.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends CommonPageState<HomePage>
    with AutomaticKeepAliveClientMixin {
  late ColorScheme _colorScheme;
  final _homeController = Get.putOrFind(HomeController.new);
  final _mainController = Get.find<MainController>();

  @override
  bool get needsCorrection => _homeController.hideTopBar;

  @override
  bool get wantKeepAlive => true;

  double get _railTopSpacing =>
      _mainController.useBottomNav &&
          !_mainController.useStatusBarNav &&
          !_mainController.homeTopInStatusBar &&
          _mainController.homeToolsPlacement.value ==
              HomeToolsPlacement.rightRail &&
          (RailViewportScope.of(context)?.normalizedTop ?? false)
      ? MediaQuery.viewPaddingOf(context).top
      : 0;

  double get _tabBarHeight =>
      _railTopSpacing +
      (_homeController.tabs.length > 1
          ? 42 + homeTopSpacing(4, _mainController.homeToolsPlacement.value)
          : 6);

  @override
  double get scrollCorrectionExtent =>
      _mainController.homeToolsPlacement.value == HomeToolsPlacement.rightRail
      ? _tabBarHeight
      : super.scrollCorrectionExtent;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _colorScheme = ColorScheme.of(context);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    Widget tabBar;
    if (_homeController.tabs.length > 1) {
      tabBar = ValueListenableBuilder(
        valueListenable: _mainController.homeToolsPlacement,
        builder: (_, placement, child) => Padding(
          padding: EdgeInsets.only(top: homeTopSpacing(4, placement)),
          child: child,
        ),
        child: SizedBox(
          height: 42,
          width: double.infinity,
          child: TabBar(
            controller: _homeController.tabController,
            tabs: _homeController.tabs.map((e) => Tab(text: e.label)).toList(),
            isScrollable: true,
            dividerColor: Colors.transparent,
            dividerHeight: 0,
            splashBorderRadius: Style.mdRadius,
            tabAlignment: TabAlignment.center,
            onTap: (_) {
              feedBack();
              if (!_homeController.tabController.indexIsChanging) {
                _homeController.animateToTop();
              }
            },
          ),
        ),
      );
      if (_homeController.hideTopBar &&
          _mainController.barHideType == .instant) {
        tabBar = Material(color: _colorScheme.surface, child: tabBar);
      }
    } else {
      tabBar = const SizedBox(height: 6);
    }
    return Column(
      children: [
        HomeTopTools(
          placement: _mainController.homeToolsPlacement,
          child: ValueListenableBuilder(
            valueListenable: _mainController.homeTopBar,
            builder: (_, region, _) =>
                region == null ? customAppBar() : statusBarAppBar(region),
          ),
        ),
        _collapsibleTabs(tabBar),
        Expanded(
          child: onBuild(
            tabBarView(
              controller: _homeController.tabController,
              children: _homeController.tabs.map((e) => e.page).toList(),
            ),
          ),
        ),
      ],
    );
  }

  Widget _collapsibleTabs(Widget tabs) => ValueListenableBuilder(
    valueListenable: _mainController.homeToolsPlacement,
    builder: (_, placement, child) {
      if (_railTopSpacing > 0) {
        child = Padding(
          padding: EdgeInsets.only(top: _railTopSpacing),
          child: child,
        );
      }
      if (!_homeController.hideTopBar ||
          placement != HomeToolsPlacement.rightRail) {
        return child!;
      }
      Widget reveal(double factor, Widget child) => ExcludeSemantics(
        excluding: factor == 0,
        child: ClipRect(
          child: Align(
            alignment: Alignment.bottomCenter,
            heightFactor: factor,
            child: child,
          ),
        ),
      );
      if (_mainController.barOffset case final offset?) {
        return Obx(
          () => reveal(
            clampDouble(1 - offset.value / Style.topBarHeight, 0, 1),
            child!,
          ),
        );
      }
      if (_homeController.showTopBar case final visible?) {
        return Obx(
          () => TweenAnimationBuilder<double>(
            tween: Tween(end: visible.value ? 1 : 0),
            duration: const Duration(milliseconds: 500),
            curve: Curves.easeInOutCubicEmphasized,
            builder: (_, value, child) =>
                Opacity(opacity: value, child: reveal(value, child!)),
            child: child,
          ),
        );
      }
      return child!;
    },
    child: tabs,
  );

  Widget customAppBar() {
    const padding = EdgeInsets.fromLTRB(14, 6, 14, 0);
    final child = Row(
      children: [
        searchBar(),
        const SizedBox(width: 4),
        msgBadge(_mainController),
        const SizedBox(width: 8),
        userAvatar(colorScheme: _colorScheme, mainController: _mainController),
      ],
    );
    if (_homeController.hideTopBar) {
      if (_mainController.barOffset case final barOffset?) {
        return Obx(() {
          final offset = barOffset.value;
          return CustomHeightWidget(
            offset: Offset(0, -offset),
            height: Style.topBarHeight - offset,
            child: Padding(padding: padding, child: child),
          );
        });
      }
      if (_homeController.showTopBar case final showTopBar?) {
        return Obx(() {
          final showSearchBar = showTopBar.value;
          return AnimatedOpacity(
            opacity: showSearchBar ? 1 : 0,
            duration: const Duration(milliseconds: 300),
            child: AnimatedContainer(
              curve: Curves.easeInOutCubicEmphasized,
              duration: const Duration(milliseconds: 500),
              height: showSearchBar ? Style.topBarHeight : 0,
              padding: padding,
              child: child,
            ),
          );
        });
      }
    }
    return Container(
      height: Style.topBarHeight,
      padding: padding,
      child: child,
    );
  }

  /// iPhone Duo 展开竖屏：状态栏只占右上角，左边空着。头像、搜索和消息放进
  /// 状态栏这一行，位置和右边让开的距离都用系统给的 [region]；上滑时这一行
  /// 连同状态栏一起收起，标签栏移到最上面，和 B 站官方客户端一样
  Widget statusBarAppBar(TopBarRegion region) {
    final height = region.height;
    final child = SizedBox(
      height: height,
      child: Padding(
        padding: region.padding,
        child: Align(
          alignment: .topCenter,
          child: SizedBox(
            height: region.extent,
            child: Row(
              children: [
                searchBar(height: region.extent),
                msgBadge(_mainController),
              ],
            ),
          ),
        ),
      ),
    );
    if (_homeController.hideTopBar) {
      if (_mainController.barOffset case final barOffset?) {
        return Obx(() {
          final offset = clampDouble(barOffset.value, 0.0, height);
          return CustomHeightWidget(
            offset: Offset(0, -offset),
            height: height - offset,
            child: child,
          );
        });
      }
      if (_homeController.showTopBar case final showTopBar?) {
        return Obx(() {
          final show = showTopBar.value;
          return AnimatedOpacity(
            opacity: show ? 1 : 0,
            duration: const Duration(milliseconds: 300),
            child: AnimatedContainer(
              curve: Curves.easeInOutCubicEmphasized,
              duration: const Duration(milliseconds: 500),
              height: show ? height : 0,
              child: OverflowBox(
                alignment: .bottomCenter,
                minHeight: height,
                maxHeight: height,
                child: child,
              ),
            ),
          );
        });
      }
    }
    return child;
  }

  Widget searchBar({double height = 44}) {
    const borderRadius = BorderRadius.all(Radius.circular(25));
    return Expanded(
      child: SizedBox(
        height: height,
        child: Material(
          borderRadius: borderRadius,
          color: _colorScheme.onSecondaryContainer.withValues(alpha: 0.05),
          child: InkWell(
            borderRadius: borderRadius,
            splashColor: _colorScheme.primaryContainer.withValues(alpha: 0.3),
            onTap: () => Get.toNamed(
              '/search',
              parameters: _homeController.enableSearchWord
                  ? {'hintText': _homeController.defaultSearch.value}
                  : null,
            ),
            child: Row(
              children: [
                const SizedBox(width: 14),
                Icon(
                  Icons.search_outlined,
                  color: _colorScheme.onSecondaryContainer,
                  semanticLabel: '搜索',
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Obx(
                    () => Text(
                      _homeController.defaultSearch.value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: _colorScheme.outline),
                    ),
                  ),
                ),
                const SizedBox(width: 5),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

Widget userAvatar({
  required ColorScheme colorScheme,
  required MainController mainController,
}) {
  return Semantics(
    label: "我的",
    child: Obx(() {
      if (mainController.accountService.isLogin.value) {
        return Stack(
          clipBehavior: .none,
          children: [
            NetworkImgLayer(
              type: .avatar,
              width: 34,
              height: 34,
              src: mainController.accountService.face.value,
            ),
            Positioned.fill(
              child: Material(
                type: .transparency,
                child: InkWell(
                  onTap: mainController.toMinePage,
                  splashColor: colorScheme.primaryContainer.withValues(
                    alpha: 0.3,
                  ),
                  customBorder: const CircleBorder(),
                ),
              ),
            ),
            Positioned(
              right: -4,
              bottom: -4,
              child: Obx(
                () => MineController.anonymity.value
                    ? IgnorePointer(
                        child: Container(
                          padding: const .all(2),
                          decoration: BoxDecoration(
                            shape: .circle,
                            color: colorScheme.secondaryContainer,
                          ),
                          child: Icon(
                            size: 14,
                            MdiIcons.incognito,
                            color: colorScheme.onSecondaryContainer,
                          ),
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
            ),
          ],
        );
      }
      return SizedBox(
        width: 38,
        height: 38,
        child: IconButton(
          tooltip: '点击登录',
          style: IconButton.styleFrom(
            padding: .zero,
            backgroundColor: colorScheme.onInverseSurface,
          ),
          onPressed: mainController.toMinePage,
          icon: Icon(
            Icons.person_rounded,
            size: 22,
            color: colorScheme.primary,
          ),
        ),
      );
    }),
  );
}

Widget msgBadge(MainController mainController) {
  return Obx(() {
    if (mainController.accountService.isLogin.value) {
      final count = mainController.msgUnReadCount.value;
      final isNumBadge = mainController.msgBadgeMode == .number;
      return IconButton(
        tooltip: '消息',
        onPressed: () {
          mainController
            ..clearUnreadMsg()
            ..lastCheckUnreadAt = DateTime.now().millisecondsSinceEpoch;
          Get.toNamed('/whisper');
        },
        icon: Badge(
          isLabelVisible:
              mainController.msgBadgeMode != .hidden && count != null,
          alignment: isNumBadge
              ? const Alignment(0.0, -0.85)
              : const Alignment(1.0, -0.85),
          label: isNumBadge && count != null ? Text(count) : null,
          child: const Icon(Icons.notifications_none),
        ),
      );
    }
    return const SizedBox.shrink();
  });
}
