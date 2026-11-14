import 'package:PiliPlus/common/widgets/view_safe_area.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

class _Probe extends StatefulWidget {
  const _Probe({required this.onInit, required this.onBuild});

  final VoidCallback onInit;
  final ValueChanged<BuildContext> onBuild;

  @override
  State<_Probe> createState() => _ProbeState();
}

class _ProbeState extends State<_Probe> {
  @override
  void initState() {
    super.initState();
    widget.onInit();
  }

  @override
  Widget build(BuildContext context) {
    widget.onBuild(context);
    return const SizedBox.expand();
  }
}

void main() {
  late int inits;
  late BuildContext probeContext;

  Widget page(EdgeInsets padding) => MediaQuery(
    data: MediaQueryData(
      size: const Size(800, 600),
      padding: padding,
      viewPadding: padding,
    ),
    child: Directionality(
      textDirection: TextDirection.ltr,
      child: SideSafeArea(
        child: _Probe(
          onInit: () => inits++,
          onBuild: (context) => probeContext = context,
        ),
      ),
    ),
  );

  setUp(() => inits = 0);

  testWidgets(
    'keeps the page state when the side inset appears and goes away',
    (
      tester,
    ) async {
      await tester.pumpWidget(page(EdgeInsets.zero));
      await tester.pumpWidget(page(const EdgeInsets.only(right: 84)));
      await tester.pumpWidget(page(EdgeInsets.zero));

      expect(inits, 1);
    },
  );

  testWidgets('pads the page once and removes the inset from MediaQuery', (
    tester,
  ) async {
    await tester.pumpWidget(page(const EdgeInsets.only(right: 84)));

    expect(tester.getSize(find.byType(_Probe)).width, 716);
    expect(MediaQuery.paddingOf(probeContext).right, 0);
    expect(MediaQuery.viewPaddingOf(probeContext).right, 0);
  });

  testWidgets('paints no background without a side inset', (tester) async {
    await tester.pumpWidget(page(EdgeInsets.zero));

    final box = tester.widget<ColoredBox>(find.byType(ColoredBox));
    expect(box.color, Colors.transparent);
  });
}
