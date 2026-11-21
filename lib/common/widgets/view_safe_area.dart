import 'package:get/get.dart';
import 'package:PiliPlus/utils/ios/native_tab_bar.dart';
import 'package:material_ui/material_ui.dart';

class ViewSafeArea extends StatelessWidget {
  const ViewSafeArea({
    super.key,
    this.top = false,
    this.left = true,
    this.right = true,
    this.overVerticalBar = false,
    required this.child,
  });

  final bool top;
  final bool left;
  final bool right;

  /// Whether a side inset that is iPhone Duo's vertical status bar is left
  /// out. Its camera is only at one end, so a widget in the middle of the
  /// side can sit over the bar.
  final bool overVerticalBar;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final padding = MediaQuery.viewPaddingOf(context);
    // The native insets change together with the padding above, so this
    // widget rebuilds when they do.
    final native = overVerticalBar ? IOSNativeTabBar.safeArea.value : null;
    const minBar = IOSNativeTabBar.verticalBarMinInset;
    final leftIsBar = native != null && native.left >= minBar;
    final rightIsBar = native != null && native.right >= minBar;
    return Padding(
      padding: .only(
        top: top ? padding.top : 0.0,
        left: left && !leftIsBar ? padding.left : 0.0,
        right: right && !rightIsBar ? padding.right : 0.0,
      ),
      child: child,
    );
  }
}

/// Keeps a whole page clear of the left and right insets, such as iPhone Duo's
/// vertical status bar, and removes them from [MediaQuery] so widgets inside
/// do not add them again.
class SideSafeArea extends StatelessWidget {
  const SideSafeArea({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final padding = MediaQuery.paddingOf(context);
    final content = SafeArea(top: false, bottom: false, child: child);
    return ColoredBox(
      color: padding.left == 0 && padding.right == 0
          ? Colors.transparent
          : Theme.of(context).scaffoldBackgroundColor,
      child: content,
    );
  }
}

/// Also usable by Navigator.push(GetPageRoute(...)).
class SideSafeRouteMiddleware extends GetMiddleware {
  @override
  Widget onPageBuilt(Widget page) => SideSafeArea(child: page);
}
