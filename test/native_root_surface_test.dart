import 'dart:ui' as ui;

import 'package:PiliPlus/common/widgets/native_root_surface.dart';
import 'package:PiliPlus/common/widgets/view_safe_area.dart';
import 'package:material_ui/material_ui.dart' show Theme, ThemeData;
import 'package:PiliPlus/common/widgets/rail_page_view.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

Future<List<int>> pixel(GlobalKey key, int x, int y) async {
  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final image = await boundary.toImage(pixelRatio: 1);
  final data = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
  final offset = (y * image.width + x) * 4;
  final rgba = data.buffer.asUint8List().sublist(offset, offset + 4);
  image.dispose();
  return rgba;
}

void main() {
  testWidgets(
    'only root-page paint leaves the native rail transparent without changing layout',
    (tester) async {
      final capture = GlobalKey();
      final content = GlobalKey();
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: RepaintBoundary(
              key: capture,
              child: SizedBox(
                width: 400,
                height: 600,
                child: RailViewportScope(
                  insets: const EdgeInsets.only(right: 84),
                  windowWidth: 400,
                  child: NativeRootSurface(
                    child: ColoredBox(
                      key: content,
                      color: const Color(0xFF227733),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      expect(tester.getSize(find.byKey(content)), const Size(400, 600));
      expect(await tester.runAsync(() => pixel(capture, 310, 500)), [
        34,
        119,
        51,
        255,
      ]);
      expect((await tester.runAsync(() => pixel(capture, 390, 500)))!.last, 0);
    },
  );

  testWidgets(
    'inset changes retain the root render object and do not paint over native tabs',
    (tester) async {
      final right = ValueNotifier(84.0);
      addTearDown(right.dispose);
      final content = GlobalKey();
      final capture = GlobalKey();
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: RepaintBoundary(
              key: capture,
              child: SizedBox(
                width: 400,
                height: 600,
                child: ValueListenableBuilder(
                  valueListenable: right,
                  builder: (_, value, child) => RailViewportScope(
                    insets: EdgeInsets.only(right: value),
                    windowWidth: 400,
                    child: NativeRootSurface(child: child!),
                  ),
                  child: ColoredBox(
                    key: content,
                    color: const Color(0xFF227733),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      final original = content.currentContext!.findRenderObject();
      for (final value in [56.0, 105.0, 0.0, 84.0]) {
        right.value = value;
        await tester.pump();
        expect(content.currentContext!.findRenderObject(), same(original));
        expect(tester.getSize(find.byKey(content)), const Size(400, 600));
        expect(
          (await tester.runAsync(() => pixel(capture, 390, 500)))!.last,
          value == 0 ? 255 : 0,
        );
      }
    },
  );

  testWidgets(
    'resting root keeps its immersive paint; raising it preserves the same render object',
    (tester) async {
      final raised = ValueNotifier(false);
      addTearDown(raised.dispose);
      final capture = GlobalKey(), content = GlobalKey();
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: RepaintBoundary(
              key: capture,
              child: SizedBox(
                width: 400,
                height: 600,
                child: RailViewportScope(
                  insets: const EdgeInsets.only(right: 84),
                  windowWidth: 400,
                  child: ValueListenableBuilder(
                    valueListenable: raised,
                    builder: (_, value, child) =>
                        NativeRootSurface(raised: value, child: child!),
                    child: ColoredBox(
                      key: content,
                      color: const Color(0xFF227733),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      final original = content.currentContext!.findRenderObject();
      for (final value in [false, true, false]) {
        raised.value = value;
        await tester.pump();
        expect(content.currentContext!.findRenderObject(), same(original));
        expect(
          (await tester.runAsync(() => pixel(capture, 390, 500)))!.last,
          value ? 0 : 255,
        );
      }
    },
  );

  testWidgets(
    'side-safe secondary page paints its rail during entry, cancelled swipe and pop',
    (tester) async {
      final capture = GlobalKey();
      final navigator = GlobalKey<NavigatorState>();
      final root = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: capture,
          child: CupertinoApp(
            navigatorKey: navigator,
            onGenerateRoute: (_) => _RootRoute(
              RailViewportScope(
                insets: const EdgeInsets.only(right: 80),
                windowWidth: 800,
                child: NativeRootSurface(
                  child: CupertinoPageScaffold(
                    key: root,
                    backgroundColor: const Color(0xFF000000),
                    child: const SizedBox.expand(),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final original = root.currentContext!.findRenderObject();
      expect((await tester.runAsync(() => pixel(capture, 780, 570)))!.last, 0);
      final route = _DetailRoute();
      navigator.currentState!.push(route);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 90));
      expect((await tester.runAsync(() => pixel(capture, 780, 570)))!, [
        18,
        78,
        112,
        255,
      ]);
      await tester.pumpAndSettle();
      final gesture = await tester.startGesture(const Offset(2, 250));
      await gesture.moveBy(const Offset(160, 0));
      await tester.pump(const Duration(milliseconds: 80));
      expect(
        (await tester.runAsync(() => pixel(capture, 780, 570)))!.last,
        255,
        reason: 'The moving page must already cover native tabs inside its side inset',
      );
      await gesture.moveBy(const Offset(-145, 0));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(navigator.currentState!.canPop(), isTrue);
      navigator.currentState!.pop();
      await tester.pumpAndSettle();
      expect(root.currentContext!.findRenderObject(), same(original));
      expect((await tester.runAsync(() => pixel(capture, 780, 570)))!.last, 0);
    },
  );
}

class _DetailRoute extends CupertinoPageRoute<void> {
  _DetailRoute()
    : super(
        builder: (context) => Theme(
          data: ThemeData(scaffoldBackgroundColor: const Color(0xFF124E70)),
          child: MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(padding: const EdgeInsets.only(right: 80)),
            child: const SideSafeArea(
              child: CupertinoPageScaffold(
                backgroundColor: Color(0xFF124E70),
                child: SizedBox.expand(),
              ),
            ),
          ),
        ),
      );
  @override
  Color? get barrierColor => null;
}

class _RootRoute extends CupertinoPageRoute<void> {
  _RootRoute(Widget child) : super(builder: (_) => child);
  // GetPageRoute (the production root route) has no modal barrier color.
  @override
  Color? get barrierColor => null;
}
