import 'package:PiliPlus/utils/accounts.dart';
import 'package:PiliPlus/pages/login/controller.dart';

import 'dart:async';

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
import 'package:PiliPlus/utils/extension/context_ext.dart';
import 'package:PiliPlus/utils/extension/size_ext.dart';
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
  StreamSubscription<void>? _accountsListener;

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
      _accountsListener = Accounts.account.watch().listen(
        (_) => _scheduleHomeTools(),
      );
      _nativeTabBarWorkers.add(
        ever(_mainController.accountService.face, (_) => _scheduleHomeTools()),
      );
      _attachNativeTabBar();
    }
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
        hasAccount: Accounts.account.isNotEmpty,
        unread: _mainController.msgUnReadCount.value,
        badgeMode: _mainController.msgBadgeMode,
        face: _mainController.accountService.face.value,
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
        onAction: (id) async {
          if (!mounted || !(_homeRoute?.isCurrent ?? false)) return;
          switch (id) {
            case 'mine':
              if (_mainController.accountService.isLogin.value ||
                  Accounts.account.isNotEmpty) {
                await LoginPageController.switchAccountDialog(context);
              }
              _mainController.toMinePage();

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
      _mainController.useBottomNav = MediaQuery.sizeOf(context).isPortrait;
    }
    _mainController.homeToolsPlacement.value = resolveHomeToolsPlacement(
      useBottomNav: _mainController.useBottomNav,
      nativeToolsAvailable: IOSNativeTabBar.homeToolsAvailable.value,
    );
  }

  @override
  void didPopNext() {
    IOSNativeTabBar.setHidden(false);
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
    // 进入二级页面时隐藏系统标签栏
    IOSNativeTabBar.setHidden(true);
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
    PiliScheme.listener?.cancel();
    GStorage.close();
    _accountsListener?.cancel();
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
              translation: Offset(0.0, barOffset.value / Style.topBarHeight),
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
      if (context.isTablet && _mainController.optTabletNav) {
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
    Widget child;
    if (_mainController.mainTabBarView) {
      child = RailTabBarView(
        controller: _mainController.controller,
        physics: const NeverScrollableScrollPhysics(),
        scrollDirection: _mainController.useBottomNav ? .horizontal : .vertical,
        children: _mainController.navigationBars.map((i) => i.page).toList(),
      );
    } else {
      child = RailPageView(
        controller: _mainController.controller,
        physics: const NeverScrollableScrollPhysics(),
        children: _mainController.navigationBars.map((i) => i.page).toList(),
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
                  padding: .only(top: _padding.top, left: _padding.left),
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
      final isHome =
          _mainController.navigationBars[_mainController.selectedIndex.value] ==
          NavigationBarType.home;
      padding = _padding.copyWith(
        bottom: 0,
        top: isHome
            ? homeTopSpacing(
                _padding.top,
                _mainController.homeToolsPlacement.value,
                alreadyNormalized:
                    RailViewportScope.of(context)?.normalizedTop ?? false,
              )
            : _padding.top,
      );
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
      padding = .only(top: _padding.top, right: _padding.right);
    }

    child = Material(
      child: MainLayout(
        sideBar: sideBar,
        bottomNav: bottomNav,
        body: Padding(padding: padding, child: child),
      ),
    );

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
