import 'dart:async' show scheduleMicrotask, StreamSubscription;

import 'package:PiliPlus/utils/storage.dart';
import 'package:PiliPlus/utils/storage_key.dart';
import 'package:PiliPlus/utils/storage_pref.dart';

import 'package:PiliPlus/utils/ios/native_navigation_batch.dart';
import 'package:PiliPlus/utils/ios/foldable_helper.dart';
import 'package:PiliPlus/common/widgets/rail_page_view.dart';
import 'package:PiliPlus/utils/ios/native_page_actions.dart';
import 'package:PiliPlus/utils/ios/native_comment_actions.dart';
import 'package:PiliPlus/common/widgets/home_tools_slot.dart';

import 'dart:io' show Platform;
import 'dart:math' show max;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// iOS 26+ iPhone 上用系统液态玻璃标签栏作为主导航（见 ios/Runner/SceneDelegate.swift）。
///
/// 原生层不可用时（系统版本过低、非 iPhone）[attach] 返回 false，
/// 继续由 Flutter 绘制导航。
abstract final class IOSNativeTabBar {
  static bool get isAvailable =>
      Platform.isIOS &&
      IOSFoldableHelper.isIPhone &&
      IOSFoldableHelper.systemMajorVersion >= 26;

  static bool hidesPageBackButton(BuildContext context) =>
      NativeBackScope.isVisible(context) && ModalRoute.of(context) is PageRoute;

  static const _channel = MethodChannel('piliplus/native_tab_bar');
  static final topBarRegion = ValueNotifier<TopBarRegion?>(null);
  static const double verticalBarMinInset = 72;

  static bool _enabled = false;
  static bool _canGoBack = false;
  static bool get enabled => _enabled;

  static ValueChanged<int>? _onSelect;
  static Future<bool> Function()? onReturnToRoot;
  static int _selectedIndex = 0;
  static bool _selectingTab = false;
  static Future<void> Function()? onBack;
  static final backButtonVisible = ValueNotifier(false);
  static ValueNotifier<bool> get backAvailable => backButtonVisible;
  static bool _isVideoRoute = false;
  static bool get sheetUseSafeArea => !_isVideoRoute && !playerFullScreen.value;
  static final pageActionsVisible = ValueNotifier(false);
  static final videoNavigationEnabled = ValueNotifier(false);
  static final playerFullScreen = ValueNotifier(false);

  /// Root stays in its original UIKit hierarchy at rest. During a page
  /// transition it leaves the rail transparent before the native lift.
  static final pageSurfaceRaised = ValueNotifier(false);

  static bool _modalOverlayVisible = false;
  static void setModalOverlayVisible(bool visible) {
    _modalOverlayVisible = visible;
    _comments.refresh();
    if (Platform.isIOS) {
      _navigationBatch.submit('presentation', {'modal': visible});
    }
  }

  /// Sticky for this device session, so folding/temporary bar hiding cannot
  /// re-enable the incompatible Flutter sidebar preference.
  static final rightRailDevice = ValueNotifier(false);
  static final railContentMargin = ValueNotifier<double>(RailSpacing.clearance);
  static StreamSubscription<Object?>? _railMarginSubscription;

  static Future<void> setRailContentMargin(double value) async {
    final margin = RailSpacing.normalizeClearance(value);
    await GStorage.setting.put(SettingBoxKey.railContentMargin, margin);
    railContentMargin.value = margin;
  }

  static final homeToolsVisible = ValueNotifier(false);

  /// The first native acknowledgement fixes the home layout for this session.
  /// Covering the home route must not recreate its fallback search row.
  static final homeToolsAvailable = HomeToolsAvailability();
  static final commentOwnerVisible = ValueNotifier(0);
  static final commentButtonsAvailable = ValueNotifier(false);
  static final _comments = NativeCommentActions(
    canPresent: () =>
        _enabled &&
        rightRailDevice.value &&
        !playerFullScreen.value &&
        !_modalOverlayVisible,
    onChanged: (state) => _sendNavigationState('setCommentAction', state),
  );
  static bool _commentFrameScheduled = false;

  static int registerCommentButton({
    required Object source,
    required Route<dynamic> route,
    required bool Function() isVisible,
    required VoidCallback onPressed,
    required String label,
  }) {
    final owner = _comments.register(
      source: source,
      page: route,
      isVisible: isVisible,
      onPressed: onPressed,
      label: label,
    );
    _watchCommentFrames();
    WidgetsBinding.instance.ensureVisualUpdate();
    return owner;
  }

  static void unregisterCommentButton(Object source) =>
      _comments.unregister(source);

  static void _watchCommentFrames() {
    if (_commentFrameScheduled || !_comments.hasCandidates) return;
    _commentFrameScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _commentFrameScheduled = false;
      _comments.refresh();
      // Observe frames caused by navigation/scrolling without requesting idle frames.
      _watchCommentFrames();
    });
  }

  static final _pageActions = NativePageActionRegistry(
    onChanged: (state) => _sendNavigationState('setPageActions', state),
  );

  static EdgeInsets? statusBarRowPadding(
    BuildContext context,
    double toolbarHeight,
  ) {
    final region = context
        .dependOnInheritedWidgetOfExactType<TopBarRegionScope>()
        ?.notifier
        ?.value;
    if (region == null) return null;
    final size = MediaQuery.sizeOf(context);
    if (size.height <= size.width || size.shortestSide < 600) return null;
    // 顶部安全区已被外层用掉（不在屏幕顶边），或状态栏已隐藏
    if (MediaQuery.paddingOf(context).top < region.height - 0.5) return null;
    return EdgeInsets.only(
      top: region.topFor(toolbarHeight),
      left: region.padding.left,
      right: region.padding.right,
    );
  }

  /// 主标题栏（高 [toolbarHeight]）离屏幕顶边的距离：展开竖屏时它放在状态栏
  /// 那一行里（见 [statusBarRowPadding]），其他时候在顶部安全区 [safeTop]
  /// 下面。自己按「顶部安全区 + 标题栏高度」排版的页面（可折叠头部的高度、
  /// 头部背景里内容的位置）用它代替顶部安全区，和标题栏对齐
  static double appBarTop(
    BuildContext context, {
    double toolbarHeight = 56,
    double? safeTop,
  }) =>
      statusBarRowPadding(context, toolbarHeight)?.top ??
      safeTop ??
      MediaQuery.paddingOf(context).top;

  static Widget dialogSafeArea(BuildContext context, Widget dialog) =>
      ValueListenableBuilder<bool>(
        valueListenable: playerFullScreen,
        builder: (context, hidden, dialog) {
          if (!_isVideoRoute && !hidden) return SafeArea(child: dialog!);
          final padding = MediaQuery.paddingOf(context);
          final vertical = [
            padding.top,
            padding.bottom,
            padding.left,
            padding.right,
          ].reduce(max);
          return SafeArea(
            left: false,
            right: false,
            minimum: EdgeInsets.symmetric(vertical: vertical),
            child: dialog!,
          );
        },
        child: dialog,
      );

  static bool? _mainHidesStatusBar;
  static void setMainHidesStatusBar(bool hides, {bool force = false}) {
    if (!Platform.isIOS || (!force && hides == _mainHidesStatusBar)) return;
    _mainHidesStatusBar = hides;
    _channel.invokeMethod('setMainHidesStatusBar', hides).ignore();
  }

  static void setTopRoute(Route<dynamic>? route) {
    _comments.setTopPage(route);
    final path = Uri.tryParse(route?.settings.name ?? '')?.path;
    _isVideoRoute =
        route is PageRoute && {'/videoV', '/VideoDetailPageV'}.contains(path);
    if (!_isVideoRoute && playerFullScreen.value) setFullScreen(false);
    _pageActions.setTopPage(
      route,
      // Home belongs only to the two video-detail route names above.
      backOnly: !_isVideoRoute,
      initialActions: _isVideoRoute
          ? const [
              NativePageAction(id: 'home', title: '返回主页'),
              NativePageAction(id: 'fullscreen', title: '全屏'),
            ]
          : const [],
      initialVideo: _isVideoRoute
          ? const NativeVideoChrome(
              controlsVisible: false,
              fullScreen: false,
              locked: false,
            )
          : null,
    );
  }

  static void setPageActions({
    required Route<dynamic> route,
    required List<NativePageAction> actions,
    required NativePageActionHandler onAction,
    NativeVideoChrome? video,
    bool homeTools = false,
  }) => _pageActions.register(
    page: route,
    actions: actions,
    handler: onAction,
    video: video,
    homeTools: homeTools,
  );

  static void removePageActions(Route<dynamic> route) =>
      _pageActions.unregister(route);

  static bool hasNativeActions(BuildContext context) =>
      NativePageActionsScope.isVisible(context) &&
      (ModalRoute.of(context)?.isCurrent ?? false);

  static bool usesNativeVideoNavigation(BuildContext context) =>
      NativeVideoNavigationScope.isEnabled(context) &&
      (ModalRoute.of(context)?.isCurrent ?? false);

  /// Read through the scope so AppBars rebuild when UIKit moves/hides the button.
  static bool hasNativeBack(BuildContext context) =>
      NativeBackScope.isVisible(context) &&
      (ModalRoute.of(context)?.isCurrent ?? false);

  static final _navigationBatch = NativeNavigationBatch(
    schedule: (flush) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => scheduleMicrotask(flush),
      );
      WidgetsBinding.instance.ensureVisualUpdate();
    },
    onChanged: (state) => _invokeNavigation('setNavigationState', state),
  );

  static Future<void> _sendNavigationState(String method, Object value) async {
    if (!Platform.isIOS) return;
    if (method == 'setPageActions' && value is Map<String, Object>) {
      _navigationBatch.submit('page', {...value, 'canGoBack': _canGoBack});
    } else if (method == 'setCommentAction' && value is Map<String, Object>) {
      _navigationBatch.submit('comment', value);
    } else {
      await _invokeNavigation(method, value);
    }
  }

  static Future<void> _invokeNavigation(String method, Object value) async {
    try {
      await _channel.invokeMethod<void>(method, value);
    } on MissingPluginException {
      // Older iOS and non-iPhone devices keep their Flutter navigation.
    }
  }

  static Map<String, Object>? _surfaceAppearance;
  static void setSurfaceAppearance({required int color, required bool dark}) {
    if (!isAvailable) return;
    final previous = _surfaceAppearance;
    if (previous?['color'] == color && previous?['dark'] == dark) return;
    _surfaceAppearance = {'color': color, 'dark': dark};
    _invokeNavigation('setSurfaceAppearance', _surfaceAppearance!);
  }

  /// Sent directly per animation frame, ahead of the coalesced page-owner update.
  static Map<String, Object>? _pendingRailTransition;
  static bool _preparingPageSurface = false;
  static void setRailTransition(Map<String, Object> state) {
    if (!Platform.isIOS) return;
    if (_preparingPageSurface) {
      _pendingRailTransition = state;
    } else if (state['active'] == true && !pageSurfaceRaised.value) {
      pageSurfaceRaised.value = true;
      _preparingPageSurface = true;
      _pendingRailTransition = state;
      // Paint the transparent root rail first; coalesce progress while UIKit
      // is waiting so an older first frame cannot rewind an edge swipe.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _preparingPageSurface = false;
        final pending = _pendingRailTransition;
        _pendingRailTransition = null;
        if (pending != null) _sendRailTransition(pending);
      });
      WidgetsBinding.instance.ensureVisualUpdate();
    } else {
      _sendRailTransition(state);
    }
  }

  static void _sendRailTransition(Map<String, Object> state) {
    final entering = state['active'] == true && state['returning'] == false;
    final commands = entering ? _navigationBatch.takeChanges() : null;
    _invokeNavigation('setRailTransition', {
      ...state,
      if (commands != null && commands.isNotEmpty) 'navigation': commands,
    });
  }

  static void setCanGoBack(bool value) {
    // The observer publishes the route immediately afterwards. Bundle this
    // value with its commands so UIKit never animates an intermediate empty bar.
    _canGoBack = value;
  }

  static void setFullScreen(bool value) {
    playerFullScreen.value = value;
    _comments.refresh();
    _sendNavigationState('setFullScreen', value);
  }

  /// 原生容器的安全区。Flutter 视图不是窗口根控制器时拿不到系统安全区，
  /// 由原生层转发；为 null 时使用 Flutter 自己的值
  static final safeArea = ValueNotifier<EdgeInsets?>(null);

  static Future<void> init() async {
    if (!Platform.isIOS) return;
    railContentMargin.value = Pref.railContentMargin;
    _railMarginSubscription ??= GStorage.setting
        .watch(key: SettingBoxKey.railContentMargin)
        .listen((_) {
          railContentMargin.value = Pref.railContentMargin;
        });
    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'pageAction':
          final args = Map<Object?, Object?>.from(call.arguments as Map);
          await _pageActions.handle(
            owner: args['owner'] as int,
            id: args['id'] as String,
          );
        case 'commentAction':
          await _comments.handle(call.arguments as int);
        case 'commentButtonVisible':
          final args = Map<Object?, Object?>.from(call.arguments as Map);
          commentOwnerVisible.value = args['visible'] == true
              ? args['owner'] as int
              : 0;
        case 'videoNavigationEnabled':
          videoNavigationEnabled.value = call.arguments as bool;
        case 'pageActionsVisible':
          pageActionsVisible.value = call.arguments as bool;
        case 'homeToolsVisible':
          homeToolsVisible.value = call.arguments as bool;
          homeToolsAvailable.acknowledgeVisibility(call.arguments as bool);
        case 'rightRailDevice':
          if (call.arguments == true) rightRailDevice.value = true;
        case 'back':
          await onBack?.call();
        case 'home':
          await onReturnToRoot?.call();
        case 'pageSurfaceRaised':
          pageSurfaceRaised.value = call.arguments == true;
        case 'backButtonVisible':
          backButtonVisible.value = call.arguments as bool;
        case 'select':
          if (_selectingTab) return;
          _selectingTab = true;
          try {
            if (await onReturnToRoot?.call() ?? true) {
              _onSelect?.call(call.arguments as int);
            } else {
              setSelected(_selectedIndex);
            }
          } finally {
            _selectingTab = false;
          }
        case 'topBarRegion':
          topBarRegion.value = TopBarRegion.fromMap(call.arguments);
        case 'safeArea':
          _setSafeArea(call.arguments);
        case 'verticalBarHidden':
          verticalBarHidden.value = call.arguments as bool;
      }
    });
    try {
      _setSafeArea(await _channel.invokeMethod('getSafeArea'));
      topBarRegion.value = TopBarRegion.fromMap(
        await _channel.invokeMethod('getTopBarRegion'),
      );
      final capabilities = await _channel.invokeMapMethod<String, bool>(
        'getNavigationCapabilities',
      );
      if (capabilities?['verticalRail'] == true) rightRailDevice.value = true;
      if (capabilities?['commentActions'] == true) {
        commentButtonsAvailable.value = true;
      }
    } on MissingPluginException {
      // 没有原生标签栏容器
    }
  }

  static void _setSafeArea(Object? value) {
    if (value is! Map) return;
    double side(String key) => (value[key] as num?)?.toDouble() ?? 0;
    safeArea.value = EdgeInsets.fromLTRB(
      side('left'),
      side('top'),
      side('right'),
      side('bottom'),
    );
  }

  static Future<bool> attach({
    required List<({String id, String title})> tabs,
    required int selected,
    required ValueChanged<int> onSelect,
  }) async {
    if (!Platform.isIOS || tabs.length < 2) return false;
    _onSelect = onSelect;
    _selectedIndex = selected;
    try {
      _enabled =
          await _channel.invokeMethod<bool>('setTabs', {
            'tabs': [
              for (final e in tabs) {'id': e.id, 'title': e.title},
            ],
            'selected': selected,
          }) ??
          false;
    } on MissingPluginException {
      _enabled = false;
    }
    _comments.refresh();
    return _enabled;
  }

  static void setSelected(int index) {
    _selectedIndex = index;
    if (_enabled) _channel.invokeMethod('setSelected', index);
  }

  /// [value] 为 null 时隐藏角标，为空字符串时显示红点
  static void setBadge(int index, String? value) {
    if (_enabled) {
      _channel.invokeMethod('setBadge', {'index': index, 'value': value});
    }
  }

  static void setHidden(bool hidden) {
    if (_enabled) _channel.invokeMethod('setHidden', hidden);
  }

  /// Actual status-bar visibility; never use this to choose content width.
  static final verticalBarHidden = ValueNotifier(false);
}

/// 用原生层转发的安全区覆盖 [MediaQuery] 的内边距
class NativeSafeArea extends StatelessWidget {
  const NativeSafeArea({super.key, required this.scale, required this.child});

  final double scale;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<double>(
      valueListenable: IOSNativeTabBar.railContentMargin,
      builder: (context, contentMargin, child) => NativeBackScope(
        child: NativePageActionsScope(
          child: NativeVideoNavigationScope(
            child: ValueListenableBuilder<EdgeInsets?>(
              valueListenable: IOSNativeTabBar.safeArea,
              builder: (context, insets, child) {
                if (insets == null) return child!;
                return ValueListenableBuilder<bool>(
                  valueListenable: IOSNativeTabBar.playerFullScreen,
                  builder: (context, fullscreen, child) {
                    return ValueListenableBuilder<bool>(
                      valueListenable: IOSNativeTabBar.rightRailDevice,
                      builder: (context, rail, child) {
                        final mediaQuery = MediaQuery.of(context);
                        var nativeInsets = insets;
                        final verticalRail = rail && insets.right >= 72;
                        if (rail) {
                          // Reserve the rail plus a single, configurable native-point margin.
                          // Page gutters never add another trailing inset.
                          final right = RailSpacing.rightInset(
                            insets.right,
                            fullScreen: fullscreen,
                            contentMargin: contentMargin,
                          );
                          nativeInsets = insets.copyWith(
                            right: right,
                            top: fullscreen
                                ? 0
                                : (verticalRail ? 12 : insets.top),
                          );
                        }
                        final viewPadding = nativeInsets / scale;
                        return MediaQuery(
                          data: mediaQuery.copyWith(
                            viewPadding: viewPadding,
                            padding: viewPadding.copyWith(
                              bottom: max(
                                0,
                                viewPadding.bottom -
                                    mediaQuery.viewInsets.bottom,
                              ),
                            ),
                          ),
                          child: RailViewportScope(
                            insets: rail ? viewPadding : EdgeInsets.zero,
                            windowWidth: mediaQuery.size.width,
                            normalizedTop: verticalRail,
                            child: child!,
                          ),
                        );
                      },
                      child: child,
                    );
                  },
                  child: child,
                );
              },
              child: child,
            ),
          ),
        ),
      ),
      child: child,
    );
  }
}

/// Retains a relocated control's original size, without paint, hits or semantics.
class NativeBackSlot extends StatelessWidget {
  const NativeBackSlot({super.key, required this.hidden, required this.child});
  final bool hidden;
  final Widget child;

  @override
  Widget build(BuildContext context) => Visibility(
    visible: !hidden,
    maintainSize: true,
    maintainAnimation: true,
    maintainState: true,
    child: child,
  );
}

/// Keeps page-local back controls in sync with the native button's actual visibility.
class NativeBackScope extends InheritedNotifier<ValueNotifier<bool>> {
  NativeBackScope({super.key, required super.child})
    : super(notifier: IOSNativeTabBar.backButtonVisible);

  static bool isVisible(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<NativeBackScope>()
          ?.notifier
          ?.value ??
      false;
}

class NativePageActionsScope extends InheritedNotifier<ValueNotifier<bool>> {
  NativePageActionsScope({super.key, required super.child})
    : super(notifier: IOSNativeTabBar.pageActionsVisible);

  static bool isVisible(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<NativePageActionsScope>()
          ?.notifier
          ?.value ??
      false;
}

class NativeVideoNavigationScope
    extends InheritedNotifier<ValueNotifier<bool>> {
  NativeVideoNavigationScope({super.key, required super.child})
    : super(notifier: IOSNativeTabBar.videoNavigationEnabled);

  static bool isEnabled(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<NativeVideoNavigationScope>()
          ?.notifier
          ?.value ??
      false;
}

class TopBarRegionScope
    extends InheritedNotifier<ValueNotifier<TopBarRegion?>> {
  TopBarRegionScope({super.key, required super.child})
    : super(notifier: IOSNativeTabBar.topBarRegion);
}

/// 状态栏那一行里能放顶栏的位置，见 [IOSNativeTabBar.topBarRegion]
@immutable
class TopBarRegion {
  const TopBarRegion({
    required this.height,
    required this.padding,
    required this.extent,
    required this.center,
    required this.minTop,
  });

  /// 状态栏那一行的高度（状态栏显示时的顶部安全区）
  final double height;

  /// 顶栏在这一行里的位置：上边距，以及左右避开圆角和状态栏的距离
  final EdgeInsets padding;

  /// 顶栏的高度
  final double extent;

  /// 系统让顶栏在这一行里垂直居中的中线位置（距屏幕顶边）
  final double center;

  /// 顶栏离屏幕顶边的最小距离
  final double minTop;

  /// 高度为 [barHeight] 的顶栏离屏幕顶边的距离，和系统放顶栏的方式一致：
  /// 以 [center] 居中，但不小于 [minTop]
  double topFor(double barHeight) => max(minTop, center - barHeight / 2);

  /// 原生层的值是原生 pt，按界面缩放换算成 Flutter 的逻辑像素，和
  /// [NativeSafeArea] 一样
  static TopBarRegion? fromMap(Object? value) {
    if (value is! Map) return null;
    final scale = Pref.uiScale;
    double get(String key) => ((value[key] as num?)?.toDouble() ?? 0) / scale;
    return TopBarRegion(
      height: get('height'),
      padding: EdgeInsets.only(
        top: get('top'),
        left: get('left'),
        right: get('right'),
      ),
      extent: get('extent'),
      center: get('center'),
      minTop: get('minTop'),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is TopBarRegion &&
      other.height == height &&
      other.padding == padding &&
      other.extent == extent &&
      other.center == center &&
      other.minTop == minTop;

  @override
  int get hashCode => Object.hash(height, padding, extent, center, minTop);
}
