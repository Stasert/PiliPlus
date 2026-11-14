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

  testWidgets('竖状态栏里有返回键时，页面左上角不再显示，标题留出间距', (tester) async {
    IOSNativeTabBar.backAvailable.value = true;
    await tester.pumpWidget(app());
    await pushPage(tester);
    expect(find.byType(BackButton), findsNothing);
    expect(titleLeft(tester), NavigationToolbar.kMiddleSpacing);
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
}
