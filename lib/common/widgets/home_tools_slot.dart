import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

enum HomeToolsPlacement { top, sideBar, rightRail }

HomeToolsPlacement resolveHomeToolsPlacement({
  required bool useBottomNav,
  required bool nativeToolsAvailable,
}) => nativeToolsAvailable
    ? HomeToolsPlacement.rightRail
    : useBottomNav
    ? HomeToolsPlacement.top
    : HomeToolsPlacement.sideBar;

double homeTopSpacing(
  double spacing,
  HomeToolsPlacement placement, {
  bool alreadyNormalized = false,
}) => placement == HomeToolsPlacement.rightRail && !alreadyNormalized
    ? spacing / 2
    : spacing;

/// A covered route's hidden buttons do not revoke its native tool placement.
class HomeToolsAvailability extends ValueNotifier<bool> {
  HomeToolsAvailability() : super(false);

  void acknowledgeVisibility(bool visible) {
    if (visible) value = true;
  }
}

/// Rebuild even when the kept-alive HomePage itself is a constant widget.
/// A native request alone must never remove the fallback search entry.
class HomeTopTools extends StatelessWidget {
  const HomeTopTools({super.key, required this.placement, required this.child});

  final ValueListenable<HomeToolsPlacement> placement;
  final Widget child;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
    valueListenable: placement,
    builder: (_, value, child) =>
        value == HomeToolsPlacement.top ? child! : const SizedBox.shrink(),
    child: child,
  );
}
