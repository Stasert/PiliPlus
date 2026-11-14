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
  });

  final ValueChanged<bool> onCanGoBackChanged;
  final ValueChanged<Route<dynamic>?>? onTopRouteChanged;
  final ValueChanged<bool>? onModalOverlayChanged;
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
      if (navigator == null || !await navigator.maybePop() || route.isActive)
        return false;
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
    _notify();
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _stack.remove(route);
    _notifyModalOverlay();
    if (!_routes.remove(route)) return;
    _notify();
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _stack.remove(route);
    _notifyModalOverlay();
    if (!_routes.remove(route)) return;
    _notify();
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
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
