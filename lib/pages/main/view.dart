import 'dart:async';

import 'package:PiliPlus/common/widgets/native_root_surface.dart';

import 'package:PiliPlus/utils/ios/native_tab_tools.dart';
import 'package:PiliPlus/common/widgets/rail_page_view.dart';

import 'dart:io';

import 'package:PiliPlus/common/style.dart';
import 'package:PiliPlus/common/widgets/home_tools_slot.dart';
import 'package:PiliPlus/common/widgets/floating_navigation_bar.dart';
import 'package:PiliPlus/common/widgets/flutter/pop_scope.dart';
import 'package:PiliPlus/common/widgets/image/network_img_layer.dart';
import 'package:PiliPlus/common/widgets/main_layout.dart';
import 'package:PiliPlus/common/widgets/route_aware_mixin.dart';
import 'package:PiliPlus/models/common/nav_bar_config.dart';
import 'package:PiliPlus/pages/home/view.dart';
import 'package:PiliPlus/pages/main/controller.dart';
import 'package:PiliPlus/utils/ios/native_page_actions.dart';
import 'package:PiliPlus/utils/android/bindings.g.dart';
import 'package:PiliPlus/utils/app_scheme.dart';
import 'package:PiliPlus/utils/desktop/tray_controller.dart';
import 'package:PiliPlus/utils/desktop/window_controller.dart';
import 'package:PiliPlus/utils/extension/theme_ext.dart';
import 'package:PiliPlus/utils/ios/foldable_helper.dart';
import 'package:PiliPlus/utils/ios/native_tab_bar.dart';
import 'package:PiliPlus/utils/mobile_observer.dart';
import 'package:PiliPlus/utils/platform_utils.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';
import 'package:nativeapi/nativeapi.dart' as nativeapi;

class MainApp extends StatefulWidget {
  const MainApp({super.key});

  @override
  State<MainApp> createState() => _MainAppState();
}

class _MainAppState extends PopScopeState<MainApp>
    with RouteAware, RouteAwareMixin, WidgetsBindingObserver {
  final _mainController = Get.put(MainController());
  late EdgeInsets _padding;
  late ColorScheme _colorScheme;
  // 切换状态栏导航与其他布局时保留页面状态
  final _bodyKey = GlobalKey();
  Brightness? _brightness;
  ModalRoute<dynamic>? _homeRoute;
  bool _homeToolsScheduled = false;

  @override
  bool get initCanPop => false;

  @override
  void initState() {
    super.initState();
    addObserverMobile(this);
    if (Platform.isMacOS) {
      HardwareKeyboard.instance.addHandler(_handleKeyEvent);
    }
    if (PlatformUtils.isDesktop) {
      WindowController.instance.init();
      TrayController.instance.init();
    }
    if (!Platform.isMacOS) {
      PiliScheme.init();
    }
    if (Platform.isIOS) {
      IOSNativeTabBar.rightRailDevice.addListener(_onNativeHomeChanged);
      IOSNativeTabBar.homeToolsAvailable.addListener(_onNativeHomeChanged);
      _nativeTabBarWorkers.addAll([
        ever(_mainController.selectedIndex, (_) => _onNativeHomeChanged()),
        ever(
          _mainController.accountService.isLogin,
          (_) => _scheduleHomeTools(),
        ),
        ever(_mainController.msgUnReadCount, (_) => _scheduleHomeTools()),
      ]);
      _attachNativeTabBar();
      IOSNativeTabBar.topBarRegion.addListener(_onTopBarRegion);
      if (IOSFoldableHelper.isIPhone && _mainController.hasHome) {
        final showTopBar = _mainController.homeController.showTopBar;
        _homeTopWorkers.addAll([
          ever(_mainController.selectedIndex, (_) => _syncHomeStatusBar()),
          if (_mainController.barOffset case final barOffset?)
            ever(barOffset, (_) => _syncHomeStatusBar()),
          if (showTopBar != null) ever(showTopBar, (_) => _syncHomeStatusBar()),
        ]);
      }
    }
  }

  final List<Worker> _homeTopWorkers = [];

  /// 主页面是否在最上层（没有打开二级页面）
  bool _isCurrent = true;

  /// iPhone Duo 展开竖屏：首页顶栏收起时连同顶部的状态栏一起隐藏，
  /// 和 B 站官方客户端一样；打开其他页面或切到其他标签时恢复
  void _syncHomeStatusBar({bool force = false}) {
    final main = _mainController;
    var hide = false;
    if (main.homeTopInStatusBar &&
        _isCurrent &&
        main.hasHome &&
        main.homeController.hideTopBar &&
        main.navigationBars[main.selectedIndex.value] == .home) {
      if (main.barOffset case final barOffset?) {
        hide = barOffset.value > main.topBarExtent / 2;
      } else if (main.homeController.showTopBar case final showTopBar?) {
        hide = !showTopBar.value;
      }
    }
    IOSNativeTabBar.setMainHidesStatusBar(hide, force: force);
  }

  final List<Worker> _nativeTabBarWorkers = [];

  void _onNativeHomeChanged() {
    if (!mounted) return;
    setState(_updateNavMode);
    _scheduleHomeTools();
  }

  void _scheduleHomeTools() {
    if (_homeToolsScheduled) return;
    _homeToolsScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _homeToolsScheduled = false;
      if (!mounted || _homeRoute == null) {
        return;
      }
      if (!IOSNativeTabBar.rightRailDevice.value) {
        IOSNativeTabBar.removePageActions(_homeRoute!);
        return;
      }
      final tools = nativeTabTools(
        loggedIn: _mainController.accountService.isLogin.value,
        unread: _mainController.msgUnReadCount.value,
        badgeMode: _mainController.msgBadgeMode,
      );
      IOSNativeTabBar.setPageActions(
        route: _homeRoute!,
        homeTools: true,
        actions: [
          for (final tool in tools)
            NativePageAction(
              id: tool.id,
              title: tool.title,
              badge: tool.badge,
              symbol: tool.symbol,
              image: tool.image,
              group: tool.group,
            ),
        ],
        onAction: (id) {
          if (!mounted || !(_homeRoute?.isCurrent ?? false)) return;
          switch (id) {
            case 'search':
              Get.toNamed(
                '/search',
                parameters:
                    _mainController.hasHome &&
                        _mainController.homeController.enableSearchWord
                    ? {
                        'hintText':
                            _mainController.homeController.defaultSearch.value,
                      }
                    : null,
              );
            case 'notifications':
              if (!_mainController.accountService.isLogin.value) {
                Get.toNamed('/loginPage');
                return;
              }
              _mainController
                ..clearUnreadMsg()
                ..lastCheckUnreadAt = DateTime.now().millisecondsSinceEpoch;
              Get.toNamed('/whisper');
          }
        },
      );
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  Future<void> _attachNativeTabBar() async {
    final tabs = _mainController.navigationBars;
    final attached = await IOSNativeTabBar.attach(
      tabs: [for (final tab in tabs) (id: tab.name, title: tab.label)],
      selected: _mainController.selectedIndex.value,
      onSelect: _mainController.setIndex,
    );
    if (!attached || !mounted) return;
    _nativeTabBarWorkers.addAll([
      ever(_mainController.selectedIndex, IOSNativeTabBar.setSelected),
      ever(_mainController.dynCount, (int count) {
        final index = tabs.indexOf(.dynamics);
        if (index == -1) return;
        IOSNativeTabBar.setBadge(
          index,
          count > 0 && _mainController.dynamicBadgeMode != .hidden
              ? (_mainController.dynamicBadgeMode == .number ? '$count' : '')
              : null,
        );
      }),
    ]);
    setState(() {
      _mainController.useNativeTabBar = true;
      _updateNavMode();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _padding = MediaQuery.viewPaddingOf(context);
    _colorScheme = ColorScheme.of(context);
    final brightness = _colorScheme.brightness;
    NetworkImgLayer.reduce =
        NetworkImgLayer.reduceLuxColor != null && brightness.isDark;
    if (PlatformUtils.isDesktop) {
      if (_brightness != brightness) {
        _brightness = brightness;
        nativeapi.Application.instance.setBrightness(
          brightness == .dark ? .dark : .light,
        );
      }
    }
    _updateNavMode();
    _homeRoute = ModalRoute.of(context);
    IOSNativeTabBar.setSurfaceAppearance(
      color: Theme.of(context).canvasColor.toARGB32(),
      dark: _colorScheme.brightness == Brightness.dark,
    );
    _scheduleHomeTools();
  }

  void _updateNavMode() {
    // iPhone Duo 的系统状态栏位于右侧竖条（安全区约 84pt），导航放入其中；
    // 普通 iPhone 横屏时灵动岛一侧的安全区约 60pt，不会触发
    _mainController.useStatusBarNav =
        !_mainController.useNativeTabBar &&
        !_mainController.useSideBar &&
        IOSFoldableHelper.isIPhone &&
        _mainController.navigationBars.length > 1 &&
        _padding.right >= 72;
    // 系统标签栏接管导航时，页面按手机布局显示顶部搜索栏
    if (_mainController.useNativeTabBar ||
        _mainController.useStatusBarNav ||
        IOSNativeTabBar.rightRailDevice.value) {
      _mainController.useBottomNav = true;
    } else if (!_mainController.useSideBar) {
      _mainController.useBottomNav = MediaQuery.isPortraitOf(context);
    }
    _updateHomeTop();
  }

  /// iPhone Duo 展开竖屏时状态栏只占顶部右上角，首页的头像、搜索和消息放进
  /// 这一行（见 [HomePage]），位置用系统给的 [IOSNativeTabBar.topBarRegion]。
  /// 普通 iPhone 的最短边不到 600，不会触发
  void _updateHomeTop() {
    final size = MediaQuery.sizeOf(context);
    final region = IOSNativeTabBar.topBarRegion.value;
    final homeTop =
        region != null &&
        region.height >= region.padding.top + region.extent &&
        IOSFoldableHelper.isIPhone &&
        _mainController.useBottomNav &&
        !_mainController.useStatusBarNav &&
        size.height > size.width &&
        size.shortestSide >= 600;
    final next = homeTop ? region : null;
    final changed = homeTop != _mainController.homeTopInStatusBar;
    // 首页监听它，开合、旋转时即使首页自己没有重建也会切换顶栏
    _mainController
      ..homeTopBar.value = next
      ..topBarExtent = next?.height ?? Style.topBarHeight;
    if (changed) {
      // 换了布局，顶栏和底栏重新显示。不能在构建过程中改
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _mainController
          ..barOffset?.value = 0.0
          ..showBottomBar?.value = true
          ..setSearchBar();
        _syncHomeStatusBar(force: true);
      });
    }
    _mainController.homeToolsPlacement.value = next != null
        ? HomeToolsPlacement.top
        : resolveHomeToolsPlacement(
            useBottomNav: _mainController.useBottomNav,
            nativeToolsAvailable: IOSNativeTabBar.homeToolsAvailable.value,
          );
  }

  /// 系统给的顶栏位置晚于布局到达（要等原生层布局完成）
  void _onTopBarRegion() {
    if (mounted) setState(_updateNavMode);
  }

  // 系统标签栏的隐藏和恢复由 IOSNativeTabBar.navigationObserver 负责：这里只能
  // 收到 GetX 页面的通知，图片查看器等其他页面盖在主页上时收不到
  @override
  void didPopNext() {
    _isCurrent = true;
    _syncHomeStatusBar(force: true);
    addObserverMobile(this);
    _mainController
      ..checkUnreadDynamic()
      ..checkDefaultSearch(true)
      ..checkUnread(_mainController.useBottomNav);
    super.didPopNext();
    _scheduleHomeTools();
  }

  @override
  void didPushNext() {
    // 原生层保留一级导航实例，用路由动画驱动遮盖层。
    IOSNativeTabBar.setHidden(true);
    _isCurrent = false;
    _syncHomeStatusBar(force: true);
    removeObserverMobile(this);
    super.didPushNext();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _mainController
        ..checkUnreadDynamic()
        ..checkDefaultSearch(true)
        ..checkUnread(_mainController.useBottomNav);
    }
  }

  @override
  void dispose() {
    if (Platform.isIOS) {
      IOSNativeTabBar.rightRailDevice.removeListener(_onNativeHomeChanged);
      IOSNativeTabBar.homeToolsAvailable.removeListener(_onNativeHomeChanged);
    }
    if (_homeRoute case final route?) IOSNativeTabBar.removePageActions(route);
    if (Platform.isMacOS) {
      HardwareKeyboard.instance.removeHandler(_handleKeyEvent);
    }
    if (PlatformUtils.isDesktop) {
      WindowController.instance.dispose();
      TrayController.instance.dispose();
    }
    removeObserverMobile(this);
    for (final worker in _nativeTabBarWorkers) {
      worker.dispose();
    }
    for (final worker in _homeTopWorkers) {
      worker.dispose();
    }
    IOSNativeTabBar.topBarRegion.removeListener(_onTopBarRegion);
    PiliScheme.listener?.cancel();
    GStorage.close();
    super.dispose();
  }

  bool _handleKeyEvent(KeyEvent event) {
    return event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.keyR &&
        HardwareKeyboard.instance.isMetaPressed &&
        _mainController.refreshRecommendations();
  }

  @pragma('vm:prefer-inline')
  static void _onBack() {
    if (Platform.isAndroid) {
      AndroidHelper.back();
    }
  }

  @override
  void onPopInvokedWithResult(bool didPop, Object? result) {
    if (_mainController.directExitOnBack) {
      _onBack();
    } else {
      if (_mainController.selectedIndex.value != 0) {
        _mainController
          ..setIndex(0)
          ..barOffset?.value = 0.0
          ..showBottomBar?.value = true
          ..setSearchBar();
      } else {
        _onBack();
      }
    }
  }

  Widget? get _bottomNav {
    Widget? bottomNav;
    if (_mainController.navigationBars.length > 1) {
      if (_mainController.floatingNavBar) {
        bottomNav = Obx(
          () => FloatingNavigationBar(
            onDestinationSelected: _mainController.setIndex,
            selectedIndex: _mainController.selectedIndex.value,
            destinations: _mainController.navigationBars
                .map(
                  (e) => FloatingNavigationDestination(
                    label: e.label,
                    icon: _buildIcon(type: e),
                    selectedIcon: _buildIcon(type: e, selected: true),
                  ),
                )
                .toList(),
          ),
        );
      } else if (_mainController.enableMYBar) {
        bottomNav = Obx(
          () => NavigationBar(
            maintainBottomViewPadding: true,
            onDestinationSelected: _mainController.setIndex,
            selectedIndex: _mainController.selectedIndex.value,
            destinations: _mainController.navigationBars
                .map(
                  (e) => NavigationDestination(
                    label: e.label,
                    icon: _buildIcon(type: e),
                    selectedIcon: _buildIcon(type: e, selected: true),
                  ),
                )
                .toList(),
          ),
        );
      } else {
        bottomNav = Obx(
          () => BottomNavigationBar(
            currentIndex: _mainController.selectedIndex.value,
            onTap: _mainController.setIndex,
            iconSize: 16,
            selectedFontSize: 12,
            unselectedFontSize: 12,
            type: .fixed,
            items: _mainController.navigationBars
                .map(
                  (e) => BottomNavigationBarItem(
                    label: e.label,
                    icon: _buildIcon(type: e),
                    activeIcon: _buildIcon(type: e, selected: true),
                  ),
                )
                .toList(),
          ),
        );
      }

      if (_mainController.hideBottomBar) {
        if (_mainController.barOffset case final barOffset?) {
          return Obx(
            () => FractionalTranslation(
              translation: Offset(
                0.0,
                barOffset.value / _mainController.topBarExtent,
              ),
              child: bottomNav,
            ),
          );
        }
        if (_mainController.showBottomBar case final showBottomBar?) {
          return Obx(
            () => AnimatedSlide(
              curve: Curves.easeInOutCubicEmphasized,
              duration: const Duration(milliseconds: 500),
              offset: Offset(0, showBottomBar.value ? 0 : 1),
              child: bottomNav,
            ),
          );
        }
      }
    }

    return bottomNav;
  }

  Widget _statusBarNav() {
    return MediaQuery.removePadding(
      context: context,
      removeLeft: true,
      removeTop: true,
      removeRight: true,
      child: Obx(
        () => NavigationRail(
          minWidth: _padding.right,
          groupAlignment: 0.0,
          labelType: _mainController.hideSideBarLabel ? .none : .all,
          backgroundColor: Colors.transparent,
          onDestinationSelected: _mainController.setIndex,
          selectedIndex: _mainController.selectedIndex.value,
          destinations: _mainController.navigationBars
              .map(
                (e) => NavigationRailDestination(
                  label: Text(e.label),
                  icon: _buildIcon(type: e),
                  selectedIcon: _buildIcon(type: e, selected: true),
                ),
              )
              .toList(),
        ),
      ),
    );
  }

  Widget _sideBar() {
    if (_mainController.navigationBars.length > 1) {
      if (MediaQuery.isTabletOf(context) && _mainController.optTabletNav) {
        return Padding(
          padding: const .only(top: 25),
          child: MediaQuery.removePadding(
            context: context,
            removeRight: true,
            child: Obx(
              () => DrawerTheme(
                data: DrawerThemeData(
                  width:
                      (_mainController.hideSideBarLabel ? 80 : 130) +
                      _padding.left,
                ),
                child: NavigationDrawer(
                  /// apply `lib/scripts/navigation_drawer.patch`
                  flex: 5,
                  backgroundColor: Colors.transparent,
                  onDestinationSelected: _mainController.setIndex,
                  selectedIndex: _mainController.selectedIndex.value,
                  header: Expanded(flex: 4, child: userAndSearchVertical()),
                  tilePadding: const .symmetric(vertical: 5, horizontal: 12),
                  indicatorShape: _mainController.hideSideBarLabel
                      ? const RoundedRectangleBorder(
                          borderRadius: .all(.circular(12)),
                        )
                      : const RoundedRectangleBorder(
                          borderRadius: .all(.circular(16)),
                        ),
                  children: _mainController.navigationBars
                      .map(
                        (e) => NavigationDrawerDestination(
                          label: _mainController.hideSideBarLabel
                              ? Semantics(
                                  label: e.label,
                                  child: const SizedBox.shrink(),
                                )
                              : Text(e.label),
                          icon: _buildIcon(type: e),
                          selectedIcon: _buildIcon(type: e, selected: true),
                        ),
                      )
                      .toList(),
                ),
              ),
            ),
          ),
        );
      }
      return Obx(
        () => NavigationRail(
          groupAlignment: 0.5,
          labelType: _mainController.hideSideBarLabel ? .none : .selected,
          leading: userAndSearchVertical(),
          backgroundColor: Colors.transparent,
          onDestinationSelected: _mainController.setIndex,
          selectedIndex: _mainController.selectedIndex.value,
          destinations: _mainController.navigationBars
              .map(
                (e) => NavigationRailDestination(
                  label: Text(e.label),
                  icon: _buildIcon(type: e),
                  selectedIcon: _buildIcon(type: e, selected: true),
                ),
              )
              .toList(),
        ),
      );
    }
    return Container(
      width: 80,
      margin: .only(top: 12 + _padding.top, left: _padding.left),
      child: userAndSearchVertical(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pages = _mainController.navigationBars.map((tab) {
      final inStatusRow =
          _mainController.homeTopInStatusBar &&
          [
            NavigationBarType.home,
            NavigationBarType.dynamics,
            NavigationBarType.mine,
          ].contains(tab);
      final top =
          !_mainController.useBottomNav ||
              _mainController.useStatusBarNav ||
              inStatusRow
          ? 0.0
          : tab == NavigationBarType.home
          ? homePageTopSpacing(
              _padding.top,
              _mainController.homeToolsPlacement.value,
              alreadyNormalized:
                  RailViewportScope.of(context)?.normalizedTop ?? false,
            )
          : _padding.top;
      return Padding(
        padding: EdgeInsets.only(top: top),
        child: ClipRect(clipper: const _ClipAbove(), child: tab.page),
      );
    }).toList();
    Widget child;
    if (_mainController.mainTabBarView) {
      child = RailTabBarView(
        controller: _mainController.controller,
        physics: const NeverScrollableScrollPhysics(),
        scrollDirection: _mainController.useBottomNav ? .horizontal : .vertical,
        children: pages,
      );
    } else {
      child = RailPageView(
        controller: _mainController.controller,
        physics: const NeverScrollableScrollPhysics(),
        children: pages,
      );
    }
    child = KeyedSubtree(key: _bodyKey, child: child);

    Widget? sideBar;
    Widget? bottomNav;
    final EdgeInsets padding;
    if (_mainController.useStatusBarNav) {
      child = Material(
        child: Row(
          children: [
            Expanded(
              child: MediaQuery.removePadding(
                context: context,
                removeRight: true,
                child: Padding(
                  padding: .only(left: _padding.left),
                  child: child,
                ),
              ),
            ),
            _statusBarNav(),
          ],
        ),
      );
      return AnnotatedRegion<SystemUiOverlayStyle>(
        value: _systemUiOverlayStyle,
        child: child,
      );
    } else if (_mainController.useBottomNav) {
      bottomNav = _mainController.useNativeTabBar ? null : _bottomNav;
      if (bottomNav != null) {
        bottomNav = MediaQuery.removePadding(
          context: context,
          removeTop: true,
          child: bottomNav,
        );
      }
      padding = _padding.copyWith(top: 0, bottom: 0);
    } else {
      sideBar = DecoratedBox(
        decoration: BoxDecoration(
          border: Border(
            right: BorderSide(
              color: _colorScheme.outline.withValues(alpha: 0.06),
            ),
          ),
        ),
        child: _sideBar(),
      );
      padding = .only(right: _padding.right);
    }

    child = Material(
      child: MainLayout(
        sideBar: sideBar,
        bottomNav: bottomNav,
        body: Padding(padding: padding, child: child),
      ),
    );

    if (IOSNativeTabBar.rightRailDevice.value &&
        _mainController.useNativeTabBar) {
      child = ValueListenableBuilder(
        valueListenable: IOSNativeTabBar.pageSurfaceRaised,
        builder: (_, raised, child) =>
            NativeRootSurface(raised: raised, child: child!),
        child: child,
      );
    }
    if (PlatformUtils.isMobile) {
      return AnnotatedRegion<SystemUiOverlayStyle>(
        value: _systemUiOverlayStyle,
        child: child,
      );
    }

    return child;
  }

  SystemUiOverlayStyle get _systemUiOverlayStyle => SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarBrightness: _colorScheme.brightness,
    statusBarIconBrightness: _colorScheme.brightness.reverse,
    systemStatusBarContrastEnforced: false,
    systemNavigationBarColor: Colors.transparent,
    systemNavigationBarIconBrightness: _colorScheme.brightness.reverse,
  );

  Widget _buildIcon({required NavigationBarType type, bool selected = false}) {
    final icon = selected ? type.selectIcon : type.icon;
    return type == .dynamics
        ? Obx(() {
            final dynCount = _mainController.dynCount.value;
            return Badge(
              isLabelVisible: dynCount > 0,
              label: _mainController.dynamicBadgeMode == .number
                  ? Text(dynCount.toString())
                  : null,
              padding: const .symmetric(horizontal: 6),
              child: icon,
            );
          })
        : icon;
  }

  Widget userAndSearchVertical() {
    return Column(
      children: [
        userAvatar(colorScheme: _colorScheme, mainController: _mainController),
        const SizedBox(height: 8),
        msgBadge(_mainController),
        IconButton(
          tooltip: '搜索',
          icon: const Icon(Icons.search_outlined, semanticLabel: '搜索'),
          onPressed: () => Get.toNamed('/search'),
        ),
      ],
    );
  }
}

/// 只裁掉页面顶边以上的部分。页面在里面让开顶部安全区，原来外层的页面容器从
/// 状态栏下面开始，会裁掉往上收起的顶栏；现在容器从屏幕顶边开始（iPhone Duo
/// 展开竖屏时首页要画进状态栏那一行），由这里补上。左右不裁，页面里左右滑动的
/// 内容要能延伸到竖状态栏下面
class _ClipAbove extends CustomClipper<Rect> {
  const _ClipAbove();

  @override
  Rect getClip(Size size) =>
      Rect.fromLTRB(-size.width, 0, size.width * 2, size.height * 2);

  @override
  bool shouldReclip(_ClipAbove oldClipper) => false;
}
