import 'package:PiliPlus/common/widgets/rail_page_view.dart';
import 'package:PiliPlus/common/widgets/native_root_surface.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

const _pager = Key('pager');
const _first = Key('first');
const _second = Key('second');
const _panel = Key('up-panel');

Widget _scene({
  required String position,
  required TabController tabs,
  required Key boundary,
  double width = 800,
  double rail = 84,
  List<Widget>? children,
}) {
  final leading = position == 'leftFixed' ? 64.0 : 0.0;
  final trailing = position == 'rightFixed' ? 64.0 : 0.0;
  Widget body = RailTabBarView(
    key: _pager,
    controller: tabs,
    leadingPanelWidth: leading,
    trailingPanelWidth: trailing,
    children:
        children ??
        const [
          ColoredBox(
            color: Colors.red,
            child: SizedBox.expand(key: _first),
          ),
          ColoredBox(
            color: Colors.blue,
            child: SizedBox.expand(key: _second),
          ),
        ],
  );
  if (leading > 0) {
    body = Row(
      children: [
        const SizedBox(key: _panel, width: 64),
        Expanded(child: body),
      ],
    );
  } else if (trailing > 0) {
    body = Row(
      children: [
        Expanded(child: body),
        const SizedBox(key: _panel, width: 64),
      ],
    );
  } else if (position == 'top') {
    body = Column(
      children: [
        const SizedBox(key: _panel, height: 76),
        Expanded(child: body),
      ],
    );
  }
  return MaterialApp(
    home: RailViewportScope(
      insets: EdgeInsets.only(right: rail),
      windowWidth: width,
      child: RepaintBoundary(
        key: boundary,
        child: NativeRootSurface(
          raised: false,
          child: Padding(
            padding: EdgeInsets.only(right: rail),
            child: RailPageView(
              children: [
                Scaffold(
                  primary: false,
                  backgroundColor: Colors.transparent,
                  appBar: const PreferredSize(
                    preferredSize: Size.fromHeight(50),
                    child: SizedBox(height: 50),
                  ),
                  body: body,
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

ScrollPosition _position(WidgetTester tester) => tester
    .state<ScrollableState>(
      find.descendant(
        of: find.byKey(_pager),
        matching: find.byType(Scrollable),
      ),
    )
    .position;

Future<List<int>> _pixel(
  WidgetTester tester,
  GlobalKey key,
  int x, {
  double scale = 1,
}) async {
  late List<int> result;
  await tester.runAsync(() async {
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: scale);
    final bytes = (await image.toByteData())!;
    final offset = (300 * image.width + x) * 4;
    result = [for (var i = 0; i < 4; i++) bytes.getUint8(offset + i)];
    image.dispose();
  });
  return result;
}

void main() {
  for (final side in [
    'top',
    'leftFixed',
    'rightFixed',
    'leftDrawer',
    'rightDrawer',
  ]) {
    testWidgets(
      '$side paints the incoming tab under the rail without covering its fixed panel',
      (tester) async {
        final tabs = TabController(length: 2, vsync: tester);
        addTearDown(tabs.dispose);
        final boundary = GlobalKey();
        await tester.pumpWidget(
          _scene(position: side, tabs: tabs, boundary: boundary),
        );
        final fixed = side.endsWith('Fixed');
        final contentWidth = fixed ? 652.0 : 716.0;
        final viewport = side == 'leftFixed' ? 736.0 : 800.0;
        expect(_position(tester).viewportDimension, viewport);
        expect(tester.getSize(find.byKey(_first)).width, contentWidth);
        final origin = tester.getTopLeft(find.byKey(_first));
        final panel = fixed ? tester.getRect(find.byKey(_panel)) : null;
        expect((await _pixel(tester, boundary, 760))[3], 0);
        _position(tester).jumpTo(100);
        await tester.pump();
        expect(await _pixel(tester, boundary, 760), [33, 150, 243, 255]);
        if (fixed) {
          expect(tester.getRect(find.byKey(_panel)), panel);
          expect(tester.getSize(find.byKey(_panel)).width, 64);
          // The fixed right panel remains clear even as the incoming tab passes
          // behind the native rail on its other side.
          expect(
            (await _pixel(
              tester,
              boundary,
              side == 'rightFixed' ? 680 : 32,
            ))[3],
            0,
          );
        }
        _position(tester).jumpTo(0); // Cancel.
        await tester.pump();
        expect(tester.getTopLeft(find.byKey(_first)), origin);
        expect(tester.getSize(find.byKey(_first)).width, contentWidth);
        _position(tester).jumpTo(viewport); // Complete.
        await tester.pump();
        expect(tester.getTopLeft(find.byKey(_second)), origin);
        expect(tester.getSize(find.byKey(_second)).width, contentWidth);
        expect((await _pixel(tester, boundary, 760))[3], 0);
      },
    );
  }

  testWidgets('fixed panels retain rail painting at different UI scales', (
    tester,
  ) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.view.physicalSize = const Size(800, 600);
    for (final scale in [0.8, 1.0, 1.3]) {
      tester.view.devicePixelRatio = scale;
      for (final side in ['leftFixed', 'rightFixed']) {
        final tabs = TabController(length: 2, vsync: tester);
        final boundary = GlobalKey();
        await tester.pumpWidget(
          _scene(
            position: side,
            tabs: tabs,
            boundary: boundary,
            width: 800 / scale,
            rail: 84 / scale,
          ),
        );
        expect(
          tester.getSize(find.byKey(_first)).width,
          closeTo(716 / scale - 64, 0.001),
        );
        _position(tester).jumpTo(100 / scale);
        await tester.pump();
        expect(await _pixel(tester, boundary, 760, scale: scale), [
          33,
          150,
          243,
          255,
        ]);
        await tester.pumpWidget(const SizedBox.shrink());
        tabs.dispose();
      }
    }
  });

  for (final side in ['leftFixed', 'rightFixed']) {
    testWidgets(
      '$side preserves the selected page State across fullscreen and fold sizes',
      (tester) async {
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        tester.view.devicePixelRatio = 1;
        final tabs = TabController(length: 2, vsync: tester, initialIndex: 1);
        addTearDown(tabs.dispose);
        final boundary = GlobalKey(), kept = GlobalKey();
        State? previous;
        for (final (width, rail) in [
          (800.0, 84.0),
          (800.0, 0.0),
          (951.0, 84.0),
          (800.0, 84.0),
        ]) {
          tester.view.physicalSize = Size(width, 600);
          await tester.pumpWidget(
            _scene(
              position: side,
              tabs: tabs,
              boundary: boundary,
              width: width,
              rail: rail,
              children: [
                const SizedBox.expand(),
                _Kept(key: kept),
              ],
            ),
          );
          await tester.pumpAndSettle();
          final current = tester.state(find.byKey(kept));
          previous ??= current;
          expect(current, same(previous));
          expect(tabs.index, 1);
          expect(tester.getSize(find.byKey(kept)).width, width - rail - 64);
        }
      },
    );
  }

  testWidgets('declared fixed panels do not extend an unrelated narrow pane', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: RailViewportScope(
          insets: EdgeInsets.only(right: 84),
          windowWidth: 800,
          child: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 350,
              height: 400,
              child: RailPageView(
                leadingPanelWidth: 64,
                children: [SizedBox.expand(key: _first)],
              ),
            ),
          ),
        ),
      ),
    );
    expect(tester.getSize(find.byKey(_first)), const Size(350, 400));
  });
}

class _Kept extends StatefulWidget {
  const _Kept({super.key});
  @override
  State<_Kept> createState() => _KeptState();
}

class _KeptState extends State<_Kept> {
  @override
  Widget build(BuildContext context) => const SizedBox.expand();
}
