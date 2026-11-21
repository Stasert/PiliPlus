import 'package:PiliPlus/common/widgets/rail_page_view.dart';
import 'package:PiliPlus/common/widgets/scaffold/mini_scaffold.dart';
import 'package:PiliPlus/pages/video/widgets/inner_video_split_layout.dart';
import 'package:PiliPlus/pages/video/widgets/video_detail_body_insets.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

const _player = Key('player'), _pager = Key('right-tabs');
const _related = Key('related'), _comments = Key('comments');

Widget _scene({
  required TabController tabs,
  required GlobalKey boundary,
  String layout = 'fixed',
  bool enabled = true,
  bool fullScreen = false,
  double rail = 84,
  double left = 0,
  ScrollController? commentsScroll,
}) => MaterialApp(
  home: Builder(
    builder: (context) {
      final query = MediaQuery.of(context);
      final right = fullScreen ? 0.0 : rail;
      final safeLeft = fullScreen ? 0.0 : left;
      Widget details(double leading) => MiniScaffold(
        body: Column(
          children: [
            const SizedBox(height: 48),
            Expanded(
              child: RailTabBarView(
                key: _pager,
                controller: tabs,
                leadingPanelWidth: enabled ? leading : 0,
                children: [
                  const _Pane(key: _related, color: Colors.red),
                  _Pane(
                    key: _comments,
                    color: Colors.blue,
                    scroll: commentsScroll,
                  ),
                ],
              ),
            ),
          ],
        ),
      );
      final available = query.size.width - safeLeft - right;
      final height = query.size.height;
      Widget body;
      if (layout == 'fixed') {
        body = InnerVideoSplitLayout(
          fullScreen: fullScreen,
          playerBuilder: (_, width, height) =>
              const _Pane(key: _player, color: Colors.green),
          detailsBuilder: (_, width, height) => details(available - width),
        );
      } else {
        final videoWidth = layout == 'vertical'
            ? height / (16 / 9)
            : available * 0.6;
        final introWidth = layout == 'vertical'
            ? (available - videoWidth) / 2
            : 0.0;
        body = Row(
          children: [
            if (introWidth > 0)
              SizedBox(
                width: introWidth,
                child: const ColoredBox(
                  color: Colors.amber,
                  child: SizedBox.expand(),
                ),
              ),
            SizedBox(
              width: videoWidth,
              child: const _Pane(key: _player, color: Colors.green),
            ),
            Expanded(child: details(introWidth + videoWidth)),
          ],
        );
      }
      return RailViewportScope(
        insets: EdgeInsets.only(left: safeLeft, right: right),
        windowWidth: query.size.width,
        child: RepaintBoundary(
          key: boundary,
          child: MediaQuery(
            data: query.copyWith(
              padding: EdgeInsets.only(left: safeLeft, right: right),
              viewPadding: EdgeInsets.only(left: safeLeft, right: right),
            ),
            child: VideoDetailBodyInsets(
              extendRight: false,
              fullScreen: fullScreen,
              child: body,
            ),
          ),
        ),
      );
    },
  ),
);

ScrollPosition _position(WidgetTester tester) => tester
    .state<ScrollableState>(
      find
          .descendant(of: find.byKey(_pager), matching: find.byType(Scrollable))
          .first,
    )
    .position;

Future<List<int>> _pixel(
  WidgetTester tester,
  GlobalKey key, {
  double scale = 1,
}) async {
  late List<int> result;
  await tester.runAsync(() async {
    final render =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await render.toImage(pixelRatio: scale);
    final bytes = (await image.toByteData())!;
    final index = (300 * image.width + image.width - 42) * 4;
    result = [for (var i = 0; i < 4; i++) bytes.getUint8(index + i)];
    image.dispose();
  });
  return result;
}

void main() {
  Future<void> size(WidgetTester tester, {double scale = 1}) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.view.physicalSize = const Size(951, 669);
    tester.view.devicePixelRatio = scale;
  }

  testWidgets(
    'fixed inner split paints tabs under the rail without moving player or changing column width',
    (tester) async {
      await size(tester);
      final tabs = TabController(length: 2, vsync: tester);
      addTearDown(tabs.dispose);
      final boundary = GlobalKey();
      await tester.pumpWidget(
        _scene(tabs: tabs, boundary: boundary, enabled: false),
      );
      final playerState = tester.state(find.byKey(_player));
      final playerRect = tester.getRect(find.byKey(_player));
      final originalWidth = tester.getSize(find.byKey(_related)).width;
      _position(tester).jumpTo(100);
      await tester.pump();
      expect(
        (await _pixel(tester, boundary))[3],
        0,
        reason: 'A generic narrow pane remains protected',
      );
      _position(tester).jumpTo(0);
      await tester.pumpWidget(_scene(tabs: tabs, boundary: boundary));
      final viewport = _position(tester).viewportDimension;
      expect(viewport, closeTo(originalWidth + 84, 0.001));
      _position(tester).jumpTo(100);
      await tester.pump();
      expect(await _pixel(tester, boundary), [33, 150, 243, 255]);
      expect(tester.getRect(find.byKey(_player)), playerRect);
      expect(tester.state(find.byKey(_player)), same(playerState));
      expect(tester.getSize(find.byKey(_related)).width, originalWidth);
      _position(tester).jumpTo(0);
      await tester.pump();
      expect(tester.getRect(find.byKey(_related)).right, 867);
      expect((await _pixel(tester, boundary))[3], 0);
      _position(tester).jumpTo(viewport);
      await tester.pump();
      expect(tester.getRect(find.byKey(_comments)).right, closeTo(867, 0.001));
      expect(
        tester.getSize(find.byKey(_comments)).width,
        closeTo(originalWidth, 0.001),
      );
      expect((await _pixel(tester, boundary))[3], 0);
    },
  );

  for (final layout in ['auto', 'vertical']) {
    testWidgets(
      '$layout rightmost tabs pass under the rail and leave other columns fixed',
      (tester) async {
        await size(tester);
        final tabs = TabController(length: 2, vsync: tester);
        addTearDown(tabs.dispose);
        final boundary = GlobalKey();
        await tester.pumpWidget(
          _scene(tabs: tabs, boundary: boundary, layout: layout),
        );
        final player = tester.getRect(find.byKey(_player));
        final width = tester.getSize(find.byKey(_related)).width;
        expect(_position(tester).viewportDimension, closeTo(width + 84, 0.001));
        _position(tester).jumpTo(100);
        await tester.pump();
        expect(await _pixel(tester, boundary), [33, 150, 243, 255]);
        expect(tester.getRect(find.byKey(_player)), player);
        expect(tester.getSize(find.byKey(_related)).width, width);
      },
    );
  }

  testWidgets(
    'fullscreen and window changes retain player, selected tab and reply state',
    (tester) async {
      await size(tester);
      final tabs = TabController(length: 2, vsync: tester, initialIndex: 1);
      addTearDown(tabs.dispose);
      final boundary = GlobalKey();
      State? player, comments;
      for (final (width, fullscreen) in [
        (951.0, false),
        (951.0, true),
        (1280.0, false),
        (951.0, false),
      ]) {
        tester.view.physicalSize = Size(width, 669);
        await tester.pumpWidget(
          _scene(tabs: tabs, boundary: boundary, fullScreen: fullscreen),
        );
        await tester.pumpAndSettle();
        final state = tester.state(find.byKey(_player));
        player ??= state;
        expect(state, same(player));
        expect(tabs.index, 1);
        if (fullscreen) {
          expect(
            tester.getRect(find.byKey(_player)),
            Rect.fromLTWH(0, 0, width, 669),
          );
        } else {
          final state = tester.state(find.byKey(_comments));
          comments ??= state;
          expect(state, same(comments));
          expect(
            tester.getRect(find.byKey(_comments)).right,
            closeTo(width - 84, 0.001),
          );
        }
      }
    },
  );

  testWidgets('inner tab extension respects UI scale and a left safe inset', (
    tester,
  ) async {
    await size(tester);
    for (final scale in [0.8, 1.0, 1.3]) {
      tester.view.devicePixelRatio = scale;
      final tabs = TabController(length: 2, vsync: tester);
      final boundary = GlobalKey();
      await tester.pumpWidget(
        _scene(
          tabs: tabs,
          boundary: boundary,
          rail: 84 / scale,
          left: 12 / scale,
        ),
      );
      final player = tester.getRect(find.byKey(_player));
      expect(player.left, closeTo(12 / scale, 0.001));
      _position(tester).jumpTo(100 / scale);
      await tester.pump();
      expect(await _pixel(tester, boundary, scale: scale), [33, 150, 243, 255]);
      expect(tester.getRect(find.byKey(_player)), player);
      await tester.pumpWidget(const SizedBox.shrink());
      tabs.dispose();
    }
  });

  testWidgets(
    'scrolling comments and swiping back preserves reply offset and player position',
    (tester) async {
      await size(tester);
      final tabs = TabController(length: 2, vsync: tester, initialIndex: 1);
      final scroll = ScrollController();
      addTearDown(tabs.dispose);
      addTearDown(scroll.dispose);
      final boundary = GlobalKey();
      await tester.pumpWidget(
        _scene(tabs: tabs, boundary: boundary, commentsScroll: scroll),
      );
      final player = tester.getRect(find.byKey(_player));
      scroll.jumpTo(240);
      await tester.pump();
      final width = _position(tester).viewportDimension;
      _position(tester).jumpTo(width - 100);
      await tester.pump();
      expect(await _pixel(tester, boundary), [33, 150, 243, 255]);
      _position(tester).jumpTo(width);
      await tester.pump();
      expect(scroll.offset, 240);
      expect(tester.getRect(find.byKey(_player)), player);
    },
  );
}

class _Pane extends StatefulWidget {
  const _Pane({super.key, required this.color, this.scroll});
  final Color color;
  final ScrollController? scroll;
  @override
  State<_Pane> createState() => _PaneState();
}

class _PaneState extends State<_Pane> {
  @override
  Widget build(BuildContext context) => ColoredBox(
    color: widget.color,
    child: widget.scroll == null
        ? const SizedBox.expand()
        : ListView.builder(
            controller: widget.scroll,
            itemExtent: 80,
            itemCount: 40,
            itemBuilder: (_, index) => Text('评论 $index'),
          ),
  );
}
