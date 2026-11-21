import 'package:PiliPlus/common/widgets/scaffold/floating_app_bar_scaffold.dart';
import 'package:PiliPlus/common/widgets/sliver/sliver_pinned_gap.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';

/// 记录 State 被创建了几次，用来确认开合时内容没有被卸载重建
class _Probe extends StatefulWidget {
  const _Probe({super.key, required this.child});

  final Widget child;

  static int created = 0;

  @override
  State<_Probe> createState() => _ProbeState();
}

class _ProbeState extends State<_Probe> {
  @override
  void initState() {
    super.initState();
    _Probe.created++;
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

void main() {
  const statusBar = 24.0;
  const probe = Key('probe');

  late ValueNotifier<bool> floating;
  late RxBool showTitle;
  late ScrollController scrollController;

  setUp(() {
    _Probe.created = 0;
    floating = ValueNotifier(false);
    showTitle = false.obs;
    scrollController = ScrollController();
  });

  tearDown(() {
    floating.dispose();
    scrollController.dispose();
  });

  Widget app() => MaterialApp(
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(padding: const EdgeInsets.only(top: statusBar)),
      child: child!,
    ),
    home: ValueListenableBuilder(
      valueListenable: floating,
      builder: (context, floating, _) => FloatingAppBarScaffold(
        floating: floating,
        showFloatingAppBar: showTitle,
        appBarBuilder: () => AppBar(title: const Text('标题')),
        body: _Probe(
          key: probe,
          child: ListView.builder(
            controller: scrollController,
            itemCount: 200,
            itemExtent: 50,
            itemBuilder: (_, i) => Text('item $i'),
          ),
        ),
      ),
    ),
  );

  double bodyTop(WidgetTester tester) =>
      tester.getTopLeft(find.byKey(probe)).dy;

  testWidgets('开合时滚动位置和 State 都保留', (tester) async {
    await tester.pumpWidget(app());
    final state = tester.state(find.byKey(probe));
    scrollController.jumpTo(1000);
    await tester.pump();

    for (final value in [true, false, true]) {
      floating.value = value;
      await tester.pump();
      expect(scrollController.offset, 1000);
      expect(tester.state(find.byKey(probe)), same(state));
      expect(_Probe.created, 1);
    }
  });

  testWidgets('不浮动时顶栏照常占住顶部', (tester) async {
    await tester.pumpWidget(app());

    expect(find.byType(AppBar), findsOneWidget);
    final appBarHeight = tester.getSize(find.byType(AppBar)).height;
    expect(appBarHeight, statusBar + kToolbarHeight);
    expect(tester.getTopLeft(find.byType(AppBar)).dy, 0);
    expect(bodyTop(tester), appBarHeight);
    expect(find.text('标题').hitTestable(), findsOneWidget);
  });

  testWidgets('浮动时内容只让开状态栏，顶栏平时隐藏、滑过后淡入', (tester) async {
    floating.value = true;
    await tester.pumpWidget(app());

    expect(bodyTop(tester), statusBar);
    // 只有浮动的那一份在台上，普通顶栏的位置高度为 0
    expect(find.byType(AppBar), findsOneWidget);
    expect(tester.getTopLeft(find.byType(AppBar)).dy, 0);
    expect(
      tester.getSize(find.byType(AppBar)).height,
      statusBar + kToolbarHeight,
    );
    expect(find.text('标题').hitTestable(), findsNothing);
    expect(
      tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity)).opacity,
      0,
    );

    showTitle.value = true;
    await tester.pumpAndSettle();
    expect(find.text('标题').hitTestable(), findsOneWidget);
    expect(
      tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity)).opacity,
      1,
    );
    // 顶栏出现不影响内容的位置
    expect(bodyTop(tester), statusBar);
  });

  testWidgets('来回开合后外观和初始状态一致', (tester) async {
    await tester.pumpWidget(app());
    final normalTop = bodyTop(tester);

    floating.value = true;
    await tester.pump();
    final floatingTop = bodyTop(tester);

    floating.value = false;
    await tester.pump();
    expect(bodyTop(tester), normalTop);
    expect(find.text('标题').hitTestable(), findsOneWidget);

    floating.value = true;
    await tester.pump();
    expect(bodyTop(tester), floatingTop);
    expect(find.text('标题').hitTestable(), findsNothing);
  });

  testWidgets('SliverPinnedGap 高度为 0 时不占位置', (tester) async {
    const after = Key('after');
    final extent = ValueNotifier(kToolbarHeight);
    addTearDown(extent.dispose);
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: ValueListenableBuilder(
          valueListenable: extent,
          builder: (context, extent, _) => CustomScrollView(
            controller: scrollController,
            slivers: [
              const SliverToBoxAdapter(child: SizedBox(height: 100)),
              SliverPinnedGap(extent: extent),
              const SliverToBoxAdapter(
                child: SizedBox(key: after, height: 50),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 2000)),
            ],
          ),
        ),
      ),
    );

    // 前面的内容只露出 20，补足到顶栏高度
    scrollController.jumpTo(80);
    await tester.pump();
    expect(tester.getTopLeft(find.byKey(after)).dy, kToolbarHeight);

    extent.value = 0;
    await tester.pump();
    expect(scrollController.offset, 80);
    expect(tester.getTopLeft(find.byKey(after)).dy, 20);
  });
}
