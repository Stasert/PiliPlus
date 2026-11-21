import 'package:PiliPlus/common/widgets/rail_page_view.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  const windowWidth = 800.0;
  const rail = 72.0;

  Widget wrap(Widget child) => Directionality(
    textDirection: TextDirection.ltr,
    child: MediaQuery(
      data: const MediaQueryData(size: Size(windowWidth, 600)),
      child: RailViewportScope(
        insets: const EdgeInsets.only(right: rail),
        windowWidth: windowWidth,
        child: child,
      ),
    ),
  );

  Widget pages(double width) => wrap(
    Align(
      alignment: Alignment.topLeft,
      child: SizedBox(
        width: width,
        height: 600,
        child: RailPageView(
          children: [
            for (var i = 0; i < 2; i++)
              SizedBox.expand(key: ValueKey(i), child: Text('$i')),
          ],
        ),
      ),
    ),
  );

  testWidgets('让出竖状态栏时页面延伸到它下面，每页留出它的宽度', (tester) async {
    await tester.pumpWidget(pages(windowWidth - rail));

    expect(tester.getSize(find.byType(PageView)).width, windowWidth);
    expect(tester.getSize(find.byKey(const ValueKey(0))).width, 728);
    expect(tester.getTopLeft(find.byKey(const ValueKey(0))).dx, 0);

    // 滑到一半：下一页从竖状态栏下面进来，两页之间隔着竖状态栏的宽度
    final gesture = await tester.startGesture(const Offset(600, 300));
    await gesture.moveBy(const Offset(-300, 0));
    await gesture.moveBy(const Offset(-100, 0));
    await tester.pump();
    final first = tester.getTopLeft(find.byKey(const ValueKey(0))).dx;
    final second = tester.getTopLeft(find.byKey(const ValueKey(1))).dx;
    expect(first, lessThan(0));
    expect(second - first, windowWidth);
    await gesture.up();
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.byKey(const ValueKey(1))).dx, 0);
    expect(tester.getSize(find.byKey(const ValueKey(1))).width, 728);
  });

  testWidgets('较窄的区域不延伸', (tester) async {
    await tester.pumpWidget(pages(500));

    expect(tester.getSize(find.byType(PageView)).width, 500);
    expect(tester.getSize(find.byKey(const ValueKey(0))).width, 500);
  });

  testWidgets('宽度不变但竖状态栏出现时，页面也更新右边距', (tester) async {
    Widget build(double inset) => Directionality(
      textDirection: TextDirection.ltr,
      child: RailViewportScope(
        insets: EdgeInsets.only(right: inset),
        windowWidth: windowWidth,
        child: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: windowWidth - inset,
            height: 600,
            child: RailPageView(
              children: const [SizedBox.expand(key: ValueKey(0))],
            ),
          ),
        ),
      ),
    );

    await tester.pumpWidget(build(0));
    expect(tester.getSize(find.byKey(const ValueKey(0))).width, windowWidth);

    await tester.pumpWidget(build(rail));
    expect(tester.getSize(find.byType(PageView)).width, windowWidth);
    expect(tester.getSize(find.byKey(const ValueKey(0))).width, 728);
  });

  // 视频页展开时，简介从标签页里移到播放器下方。标签页所在的部件带
  // GlobalKey 被整体搬到右侧，旧的简介页会重新激活；页面若要等到布局时
  // 才更新，旧页面会先用旧配置重建，把简介抢回去，左下变成空白（#46）
  testWidgets('页面在构建时就更新，带 GlobalKey 的内容能移出标签页', (tester) async {
    final introKey = GlobalKey();
    final tabsKey = GlobalKey();

    Widget intro() =>
        SliverToBoxAdapter(key: introKey, child: const Text('intro'));
    const related = SliverToBoxAdapter(child: Text('related'));

    Widget tabs(List<Widget> slivers) => KeyedSubtree(
      key: tabsKey,
      child: DefaultTabController(
        length: 1,
        child: RailTabBarView(
          children: [CustomScrollView(slivers: slivers)],
        ),
      ),
    );

    Widget build({required bool wide}) => wrap(
      wide
          ? Row(
              children: [
                Expanded(child: CustomScrollView(slivers: [intro()])),
                Expanded(child: tabs(const [related])),
              ],
            )
          : Column(
              children: [
                Expanded(child: tabs([intro(), related])),
              ],
            ),
    );

    await tester.pumpWidget(build(wide: false));
    expect(find.text('intro'), findsOneWidget);

    await tester.pumpWidget(build(wide: true));
    expect(tester.takeException(), isNull);
    expect(find.text('intro'), findsOneWidget);
    expect(find.text('related'), findsOneWidget);
    expect(tester.getTopLeft(find.text('intro')).dx, lessThan(400));

    await tester.pumpWidget(build(wide: false));
    expect(tester.takeException(), isNull);
    expect(find.text('intro'), findsOneWidget);
  });
}
