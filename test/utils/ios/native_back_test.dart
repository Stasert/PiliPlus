import 'package:PiliPlus/utils/ios/native_tab_bar.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  setUp(() {
    AppBar.hideImpliedBackButton = IOSNativeTabBar.hidesPageBackButton;
    IOSNativeTabBar.backAvailable.value = false;
  });

  tearDown(() {
    AppBar.hideImpliedBackButton = null;
    IOSNativeTabBar.backAvailable.value = false;
  });

  final navigatorKey = GlobalKey<NavigatorState>();

  Widget app() => MaterialApp(
    navigatorKey: navigatorKey,
    // 和 main.dart 一样，标题紧贴返回键
    theme: ThemeData(appBarTheme: const AppBarTheme(titleSpacing: 0)),
    builder: (context, child) => NativeBackScope(child: child!),
    home: const Scaffold(body: Text('root')),
  );

  Future<void> pushPage(WidgetTester tester) async {
    navigatorKey.currentState!.push(
      MaterialPageRoute<void>(
        builder: (_) => Scaffold(appBar: AppBar(title: const Text('二级页面'))),
      ),
    );
    await tester.pumpAndSettle();
  }

  double titleLeft(WidgetTester tester) =>
      tester.getTopLeft(find.text('二级页面')).dx;

  testWidgets('没有竖状态栏时，二级页面照常有返回键', (tester) async {
    await tester.pumpWidget(app());
    await pushPage(tester);
    expect(find.byType(BackButton), findsOneWidget);
  });

  testWidgets('竖状态栏接管返回键后保留原有标题位置', (tester) async {
    IOSNativeTabBar.backAvailable.value = true;
    await tester.pumpWidget(app());
    await pushPage(tester);
    expect(find.byType(BackButton), findsNothing);
    expect(titleLeft(tester), kToolbarHeight);
  });

  testWidgets('开合时跟着重建', (tester) async {
    await tester.pumpWidget(app());
    await pushPage(tester);
    expect(find.byType(BackButton), findsOneWidget);

    IOSNativeTabBar.backAvailable.value = true;
    await tester.pump();
    expect(find.byType(BackButton), findsNothing);

    IOSNativeTabBar.backAvailable.value = false;
    await tester.pump();
    expect(find.byType(BackButton), findsOneWidget);
  });

  testWidgets('弹窗里的 AppBar 保留返回键', (tester) async {
    IOSNativeTabBar.backAvailable.value = true;
    await tester.pumpWidget(app());
    showDialog<void>(
      context: navigatorKey.currentContext!,
      builder: (_) => Dialog(
        child: SizedBox(
          height: 120,
          child: Scaffold(appBar: AppBar(title: const Text('弹窗'))),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(BackButton), findsOneWidget);
  });
  testWidgets(
    'title and actions stay fixed with native back on/off, leadingWidth and RTL',
    (tester) async {
      for (final direction in [TextDirection.ltr, TextDirection.rtl]) {
        for (final width in [56.0, 72.0]) {
          final key = GlobalKey<NavigatorState>();
          await tester.pumpWidget(
            MaterialApp(
              navigatorKey: key,
              theme: ThemeData(appBarTheme: const AppBarTheme(titleSpacing: 0)),
              builder: (_, child) => NativeBackScope(
                child: Directionality(textDirection: direction, child: child!),
              ),
              home: const Scaffold(),
            ),
          );
          key.currentState!.push(
            MaterialPageRoute<void>(
              builder: (context) => Scaffold(
                appBar: AppBar(
                  leadingWidth: width,
                  title: const Text('Title'),
                  actions: [
                    IconButton(
                      onPressed: () {},
                      icon: const Icon(Icons.search),
                    ),
                  ],
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          final title = tester.getRect(find.text('Title'));
          final action = tester.getRect(find.byIcon(Icons.search));
          IOSNativeTabBar.backAvailable.value = true;
          await tester.pump();
          expect(find.byType(BackButton), findsNothing);
          expect(tester.getRect(find.text('Title')), title);
          expect(tester.getRect(find.byIcon(Icons.search)), action);
          IOSNativeTabBar.backAvailable.value = false;
          await tester.pumpWidget(const SizedBox());
        }
      }
    },
  );

  testWidgets(
    'deliberately leading-free toolbars stay leading-free',
    (tester) async {
      IOSNativeTabBar.backAvailable.value = true;
      await tester.pumpWidget(app());
      navigatorKey.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => Scaffold(
            appBar: AppBar(
              automaticallyImplyLeading: false,
              title: const Text('二级页面'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(BackButton), findsNothing);
      expect(titleLeft(tester), 0);
    },
  );

  testWidgets(
    'custom relocated controls retain width but have no hits or semantics',
    (tester) async {
      var tapped = 0;
      final hidden = ValueNotifier(false);
      addTearDown(hidden.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ValueListenableBuilder(
              valueListenable: hidden,
              builder: (_, value, _) => Row(
                children: [
                  NativeBackSlot(
                    hidden: value,
                    child: SizedBox(
                      width: 42,
                      height: 34,
                      child: IconButton(
                        tooltip: '返回',
                        onPressed: () => tapped++,
                        icon: const Icon(Icons.arrow_back),
                      ),
                    ),
                  ),
                  const Text('neighbor'),
                ],
              ),
            ),
          ),
        ),
      );
      final point = tester.getCenter(find.byType(IconButton));
      final neighbor = tester.getRect(find.text('neighbor'));
      await tester.tapAt(point);
      expect(tapped, 1);
      hidden.value = true;
      await tester.pump();
      expect(tester.getRect(find.text('neighbor')), neighbor);
      await tester.tapAt(point);
      expect(tapped, 1);
      expect(find.byTooltip('返回').hitTestable(), findsNothing);
      expect(find.bySemanticsLabel('返回'), findsNothing);
      hidden.value = false;
      await tester.pump();
      await tester.tapAt(point);
      expect(tapped, 2);
    },
  );
}
