import 'package:PiliPlus/common/widgets/scaffold/simple_scaffold.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';

/// Uses the stable R12 scaffold slots for both normal and floating headers.
/// Changing the layout flag only changes the render object's reserved height;
/// the body and its scroll/selection state are never reparented or rebuilt.
class FloatingAppBarScaffold extends StatelessWidget {
  const FloatingAppBarScaffold({
    super.key,
    required this.floating,
    required this.showFloatingAppBar,
    required this.appBarBuilder,
    required this.body,
    this.fab,
  });

  final bool floating;
  final RxBool showFloatingAppBar;
  final PreferredSizeWidget Function() appBarBuilder;
  final Widget body;
  final Widget? fab;

  @override
  Widget build(BuildContext context) => SimpleScaffold(
    overlayAppBar: floating,
    appBar: Obx(() {
      final show = showFloatingAppBar.value;
      final visible = !floating || show;
      return IgnorePointer(
        ignoring: !visible,
        child: AnimatedOpacity(
          opacity: visible ? 1 : 0,
          duration: const Duration(milliseconds: 300),
          child: appBarBuilder(),
        ),
      );
    }),
    body: body,
    fab: fab,
  );
}
