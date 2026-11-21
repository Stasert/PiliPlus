import 'dart:async' show scheduleMicrotask;

import 'package:flutter/widgets.dart';

/// Tracks the pages on the root navigator for the native vertical bar
/// (iPhone Duo), so it can show a back button on secondary pages and the top
/// page's own buttons.
///
/// Only [PageRoute]s count. Dialogs, bottom sheets and other popups are not
/// pages: counting them would make a popup on a root tab look like a
/// secondary page, and would replace the page's buttons while it is open.
class NativeNavigationObserver extends NavigatorObserver {
  NativeNavigationObserver({
    required this.onCanGoBackChanged,
    this.onTopRouteChanged,
    this.onModalOverlayChanged,
    this.onRailTransition,
  });

  final ValueChanged<bool> onCanGoBackChanged;
  final ValueChanged<Route<dynamic>?>? onTopRouteChanged;
  final ValueChanged<bool>? onModalOverlayChanged;
  final ValueChanged<NativeRailTransition>? onRailTransition;
  Animation<double>? _railAnimation;
  PageRoute<dynamic>? _railRoute;
  int _transitionID = 0;
  bool _returning = false;
  bool _rootBoundary = true;
  bool _interactiveDrag = false;
  bool? _returnCommitted;
  int _finishGeneration = 0;

  void _watchRail(
    PageRoute<dynamic> route, {
    required bool returning,
    bool interactive = false,
    bool rootBoundary = true,
  }) {
    _finishGeneration++;
    _unwatchRail();
    Animation<double>? animation = route.animation;
    // ModalRoute temporarily substitutes kAlwaysCompleteAnimation while it
    // measures an offstage page. Follow the controller-facing public proxy
    // parent so that layout cannot finish the rail transition prematurely.
    while (animation is ProxyAnimation && animation.parent != null) {
      animation = animation.parent;
    }
    if (animation == null) return;
    _transitionID++;
    _returning = returning;
    _rootBoundary = rootBoundary;
    _interactiveDrag = interactive;
    _returnCommitted = returning && !interactive ? true : null;
    _railRoute = route;
    _railAnimation = animation;
    animation
      ..addListener(_railTick)
      ..addStatusListener(_railStatus);
    _railTick();
  }

  void _railTick() {
    final animation = _railAnimation;
    if (animation == null) return;
    onRailTransition?.call(
      NativeRailTransition(
        id: _transitionID,
        secondary: _rootBoundary ? animation.value.clamp(0, 1) : 1,
        active: true,
        returning: _returning,
        interactive: _interactiveDrag,
        committed: _returnCommitted,
        destinationSecondary: _returnCommitted == true && _rootBoundary ? 0 : 1,
      ),
    );
  }

  void _railStatus(AnimationStatus status) {
    if (status == .dismissed ||
        (status == .completed &&
            !(navigator?.userGestureInProgress ?? false))) {
      _finishRail(status == .completed ? 1 : 0);
    }
  }

  void _finishRail(double secondary) {
    final id = _transitionID;
    final returning = _returning;
    final settledSecondary = _rootBoundary ? secondary : 1.0;
    final generation = ++_finishGeneration;
    _interactiveDrag = false;
    _unwatchRail();
    // AnimationStatus precedes the final paint. Final cleanup waits for that
    // frame; committed return animations can already run during settling.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (generation != _finishGeneration || id != _transitionID) return;
      onRailTransition?.call(
        NativeRailTransition(
          id: id,
          secondary: settledSecondary,
          active: false,
          returning: returning,
        ),
      );
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  void releaseRailGesture() {
    if (!_interactiveDrag) return;
    final id = _transitionID;
    // Pointer-up reaches the app listener before the route's recognizer makes
    // its pop/cancel decision. Publish release after that event is processed.
    scheduleMicrotask(() {
      if (id != _transitionID || !_interactiveDrag || _railAnimation == null) {
        return;
      }
      _interactiveDrag = false;
      _returnCommitted = _railRoute?.isCurrent == false;
      _railTick();
    });
  }

  void _unwatchRail() {
    _railAnimation?.removeListener(_railTick);
    _railAnimation?.removeStatusListener(_railStatus);
    _railAnimation = null;
    _railRoute = null;
  }

  @override
  void didStartUserGesture(
    Route<dynamic> route,
    Route<dynamic>? previousRoute,
  ) {
    if (route is PageRoute && previousRoute is PageRoute) {
      _watchRail(
        route,
        returning: true,
        interactive: true,
        rootBoundary: previousRoute.isFirst,
      );
    }
  }

  @override
  void didStopUserGesture() {
    _interactiveDrag = false;
    final animation = _railAnimation;
    if (animation?.status == .completed && _railRoute?.isCurrent == true) {
      _finishRail(1); // A cancelled edge swipe can stop without another tick.
    }
  }

  bool _lastModalOverlay = false;
  bool get hasModalOverlay => _stack.isNotEmpty && _stack.last is PopupRoute;
  void _notifyModalOverlay() {
    final covered = hasModalOverlay;
    if (_lastModalOverlay == covered) return;
    _lastModalOverlay = covered;
    onModalOverlayChanged?.call(covered);
  }

  final List<Route<dynamic>> _routes = [];
  final List<Route<dynamic>> _stack = [];

  bool get canGoBack => _routes.isNotEmpty && !_routes.last.isFirst;

  Route<dynamic>? get topRoute => _routes.isEmpty ? null : _routes.last;

  Future<bool> returnToRoot() async {
    while (_stack.isNotEmpty && !_stack.last.isFirst) {
      final route = _stack.last;
      final navigator = route.navigator;
      if (navigator == null || !await navigator.maybePop() || route.isActive) {
        return false;
      }
    }
    return true;
  }

  void _notify() {
    onCanGoBackChanged(canGoBack);
    onTopRouteChanged?.call(topRoute);
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _stack.add(route);
    _notifyModalOverlay();
    if (route is! PageRoute) return;
    _routes.add(route);
    // Prepare the destination before emitting progress zero. Nested pushes
    // also need an entering phase, while keeping the root rail covered.
    _notify();
    if (_routes.length > 1) {
      _watchRail(
        route,
        returning: false,
        rootBoundary: _routes.length == 2 && _routes.first.isFirst,
      );
    } else if (_railAnimation != null) {
      _finishRail(1);
    }
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _stack.remove(route);
    _notifyModalOverlay();
    if (!_routes.remove(route)) return;
    if (route is PageRoute &&
        _routes.isNotEmpty &&
        (_railRoute != route || !_returning)) {
      _watchRail(
        route,
        returning: true,
        rootBoundary: _routes.length == 1 && _routes.first.isFirst,
      );
    }
    if (_railRoute == route && _returning) {
      _returnCommitted = true;
      _railTick();
    }
    _notify();
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _stack.remove(route);
    _notifyModalOverlay();
    if (!_routes.remove(route)) return;
    if (_railRoute == route) _finishRail(canGoBack ? 1 : 0);
    _notify();
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    if (_railRoute == oldRoute) _finishRail(newRoute?.isFirst == true ? 0 : 1);
    final stackIndex = oldRoute == null ? -1 : _stack.indexOf(oldRoute);
    if (stackIndex >= 0) {
      if (newRoute == null) {
        _stack.removeAt(stackIndex);
      } else {
        _stack[stackIndex] = newRoute;
      }
    } else if (newRoute != null) {
      _stack.add(newRoute);
    }
    _notifyModalOverlay();
    final index = oldRoute == null ? -1 : _routes.indexOf(oldRoute);
    final newPage = newRoute is PageRoute ? newRoute : null;
    if (index != -1) {
      if (newPage == null) {
        _routes.removeAt(index);
      } else {
        _routes[index] = newPage;
      }
    } else if (newPage != null) {
      // The replaced route was not tracked (for example a popup), but the new
      // one is a page and is now on top.
      _routes.add(newPage);
    } else {
      return;
    }
    _notify();
  }
}

/// Page transition progress, including interactive cancellation.
/// Nested returns hold [secondary] at one so root navigation stays covered.
class NativeRailTransition {
  const NativeRailTransition({
    required this.id,
    required this.secondary,
    required this.active,
    required this.returning,
    this.interactive = false,
    this.committed,
    this.destinationSecondary,
  });
  final int id;
  final double secondary;
  final bool active;
  final bool returning;
  final bool interactive;
  final bool? committed;
  final double? destinationSecondary;
  Map<String, Object> toMap() => {
    'id': id,
    'secondary': secondary,
    'active': active,
    'returning': returning,
    'interactive': interactive,
    'committed': ?committed,
    'destinationSecondary': ?destinationSecondary,
  };
}
