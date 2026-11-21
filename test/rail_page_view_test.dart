import 'package:PiliPlus/common/widgets/rail_page_view.dart';
import 'package:PiliPlus/common/widgets/view_safe_area.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  testWidgets(
    'nested horizontal pages paint through the rail with stable content widths',
    (tester) async {
      final inner = PageController();
      addTearDown(inner.dispose);
      final boundaryKey = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          home: RailViewportScope(
            insets: const EdgeInsets.only(right: 84),
            windowWidth: 800,
            child: RepaintBoundary(
              key: boundaryKey,
              child: Padding(
                padding: const EdgeInsets.only(right: 84),
                child: RailPageView(
                  children: [
                    RailPageView(
                      controller: inner,
                      children: [
                        const ColoredBox(
                          color: Colors.red,
                          child: SizedBox.expand(key: Key('first')),
                        ),
                        const ColoredBox(
                          color: Colors.blue,
                          child: SizedBox.expand(key: Key('second')),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      expect(tester.getSize(find.byKey(const Key('first'))).width, 716);
      expect(inner.position.viewportDimension, 800);
      inner.jumpTo(100);
      await tester.pump();
      expect(tester.getSize(find.byKey(const Key('first'))).width, 716);
      expect(tester.getRect(find.byKey(const Key('second'))).left, 700);
      // The incoming page is actually painted beyond the old viewport edge x=716.
      await tester.runAsync(() async {
        final boundary =
            boundaryKey.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        final image = await boundary.toImage();
        final data = (await image.toByteData())!;
        final pixel = (300 * image.width + 760) * 4;
        expect(data.getUint8(pixel + 2), 243);
        expect(
          data.getUint8(pixel),
          33,
        ); // Material Colors.blue RGB(33,150,243) below.
        image.dispose();
      });
      inner.jumpTo(0); // Cancel the switch.
      await tester.pump();
      expect(tester.getRect(find.byKey(const Key('first'))).left, 0);
      expect(tester.getSize(find.byKey(const Key('first'))).width, 716);
      inner.jumpTo(800);
      await tester.pump();
      expect(tester.getRect(find.byKey(const Key('second'))).left, 0);
      expect(tester.getSize(find.byKey(const Key('second'))).width, 716);
    },
  );

  testWidgets(
    'inner half panes and vertical paging retain their own dimensions',
    (tester) async {
      final page = PageController();
      addTearDown(page.dispose);
      for (final axis in [Axis.horizontal, Axis.vertical]) {
        await tester.pumpWidget(
          MaterialApp(
            home: RailViewportScope(
              insets: const EdgeInsets.only(right: 84),
              windowWidth: 800,
              child: Align(
                alignment: Alignment.topLeft,
                child: SizedBox(
                  width: 350,
                  height: 400,
                  child: RailPageView(
                    controller: page,
                    scrollDirection: axis,
                    children: const [SizedBox.expand(key: Key('pane'))],
                  ),
                ),
              ),
            ),
          ),
        );
        expect(
          tester.getSize(find.byKey(const Key('pane'))),
          const Size(350, 400),
        );
      }
    },
  );

  testWidgets('fullscreen and fold insets preserve live page State', (
    tester,
  ) async {
    final key = GlobalKey();
    State? kept;
    for (final right in [84.0, 0.0, 84.0]) {
      await tester.pumpWidget(
        MaterialApp(
          home: RailViewportScope(
            insets: EdgeInsets.only(right: right),
            windowWidth: 800,
            child: Padding(
              padding: EdgeInsets.only(right: right),
              child: RailPageView(children: [_KeptPage(key: key)]),
            ),
          ),
        ),
      );
      final state = tester.state(find.byKey(key));
      kept ??= state;
      expect(state, same(kept));
    }
    kept = null;
  });

  testWidgets(
    'fractional coin and carousel pages keep their original viewport',
    (tester) async {
      final controller = PageController(viewportFraction: 0.3);
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: RailViewportScope(
            insets: const EdgeInsets.only(right: 84),
            windowWidth: 800,
            child: Padding(
              padding: const EdgeInsets.only(right: 84),
              child: RailPageView(
                controller: controller,
                children: const [SizedBox.expand(key: Key('coin'))],
              ),
            ),
          ),
        ),
      );
      expect(controller.position.viewportDimension, 716);
      expect(
        tester.getSize(find.byKey(const Key('coin'))).width,
        closeTo(716 * 0.3, 0.001),
      );
    },
  );

  testWidgets('rail pages retain content width across UI scales', (
    tester,
  ) async {
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    tester.view.physicalSize = const Size(800, 600);
    for (final scale in [0.8, 1.0, 1.3]) {
      tester.view.devicePixelRatio = scale;
      final controller = PageController();
      await tester.pumpWidget(
        MaterialApp(
          home: RailViewportScope(
            insets: EdgeInsets.only(right: 84 / scale),
            windowWidth: 800 / scale,
            child: Padding(
              padding: EdgeInsets.only(right: 84 / scale),
              child: RailPageView(
                controller: controller,
                children: const [SizedBox.expand(key: Key('scaled'))],
              ),
            ),
          ),
        ),
      );
      expect(
        controller.position.viewportDimension,
        closeTo(800 / scale, 0.001),
      );
      expect(
        tester.getSize(find.byKey(const Key('scaled'))).width,
        closeTo(716 / scale, 0.001),
      );
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    }
  });

  testWidgets(
    'route background covers native tabs throughout entry and pop without changing content width',
    (tester) async {
      final nav = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: nav,
          builder: (context, child) => MediaQuery(
            data: const MediaQueryData(
              padding: EdgeInsets.only(right: 84),
              viewPadding: EdgeInsets.only(right: 84),
            ),
            child: child!,
          ),
          home: const Scaffold(),
        ),
      );
      nav.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) =>
              const SideSafeArea(child: SizedBox.expand(key: Key('route'))),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      final mask = find
          .descendant(
            of: find.byType(SideSafeArea),
            matching: find.byType(ColoredBox),
          )
          .first;
      expect(tester.widget<ColoredBox>(mask).color, isNot(Colors.transparent));
      expect(tester.getSize(find.byKey(const Key('route'))).width, 716);
      await tester.pumpAndSettle();
      expect(tester.widget<ColoredBox>(mask).color, isNot(Colors.transparent));
      nav.currentState!.pop();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));
      expect(tester.widget<ColoredBox>(mask).color, isNot(Colors.transparent));
      expect(tester.getSize(find.byKey(const Key('route'))).width, 716);
      await tester.pumpAndSettle();
    },
  );
}

class _KeptPage extends StatefulWidget {
  const _KeptPage({super.key});
  @override
  State<_KeptPage> createState() => _KeptPageState();
}

class _KeptPageState extends State<_KeptPage> {
  @override
  Widget build(BuildContext context) => const SizedBox.expand();
}
