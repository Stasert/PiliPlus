import 'package:PiliPlus/common/widgets/rail_page_view.dart';
import 'package:flutter/widgets.dart';

/// While raised, the root leaves its native rail unpainted. A detail page
/// paints its own full background above the original UIKit tabs. The native
/// tabs are never faded, cropped or replaced by Flutter controls.
class NativeRootSurface extends StatelessWidget {
  const NativeRootSurface({super.key, this.raised = true, required this.child});
  final bool raised;
  final Widget child;
  @override
  Widget build(BuildContext context) {
    final viewport = RailViewportScope.of(context);
    final right = viewport?.insets.right ?? 0;
    return ClipRect(clipper: _RootPageClip(raised ? right : 0), child: child);
  }
}

class _RootPageClip extends CustomClipper<Rect> {
  const _RootPageClip(this.right);
  final double right;
  @override
  Rect getClip(Size size) => Rect.fromLTWH(
    0,
    0,
    (size.width - right).clamp(0, size.width),
    size.height,
  );
  @override
  bool shouldReclip(_RootPageClip oldClipper) => oldClipper.right != right;
}
