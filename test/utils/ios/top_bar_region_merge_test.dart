import 'package:PiliPlus/utils/ios/native_tab_bar.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  const region = TopBarRegion(
    height: 82,
    padding: EdgeInsets.only(top: 26, left: 16, right: 144),
    extent: 44,
    center: 48,
    minTop: 16,
  );

  setUp(() {
    AppBar.statusBarRowPadding = IOSNativeTabBar.statusBarRowPadding;
    AppBar.hideImpliedBackButton = IOSNativeTabBar.hidesPageBackButton;
    IOSNativeTabBar.topBarRegion.value = region;
    IOSNativeTabBar.backAvailable.value = false;
  });
  tearDown(() {
    AppBar.statusBarRowPadding = null;
    AppBar.hideImpliedBackButton = null;
    IOSNativeTabBar.topBarRegion.value = null;
    IOSNativeTabBar.backAvailable.value = false;
  });

  test('toolbar heights use the system center with a minimum top', () {
    expect(region.topFor(44), 26);
    expect(region.topFor(56), 20);
    expect(region.topFor(80), 16);
  });

  Future<void> open(WidgetTester tester, {double safeTop = 82}) async {
    tester.view
      ..physicalSize = const Size(669, 951)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final key = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: key,
        builder: (_, child) => MediaQuery(
          data: MediaQueryData(
            size: const Size(669, 951),
            padding: EdgeInsets.only(top: safeTop),
          ),
          child: TopBarRegionScope(child: NativeBackScope(child: child!)),
        ),
        home: const Scaffold(),
      ),
    );
    key.currentState!.push(
      MaterialPageRoute<void>(
        builder: (_) => Scaffold(
          appBar: AppBar(
            title: const Text('detail'),
            actions: [
              TextButton(onPressed: () {}, child: const Text('action')),
            ],
          ),
          body: const SizedBox.expand(key: Key('body')),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('top-row placement and invisible back slot coexist', (
    tester,
  ) async {
    await open(tester);
    final title = tester.getRect(find.text('detail'));
    final action = tester.getRect(find.text('action'));
    expect(tester.getTopLeft(find.byKey(const Key('body'))).dy, 76);
    expect(action.right, lessThanOrEqualTo(525));
    expect(find.byType(BackButton), findsOneWidget);
    IOSNativeTabBar.backAvailable.value = true;
    await tester.pump();
    expect(find.byType(BackButton), findsNothing);
    expect(tester.getRect(find.text('detail')), title);
    expect(tester.getRect(find.text('action')), action);
  });

  testWidgets('consumed safe area does not apply the row a second time', (
    tester,
  ) async {
    await open(tester, safeTop: 0);
    expect(tester.getTopLeft(find.byKey(const Key('body'))).dy, kToolbarHeight);
  });

  testWidgets('removing the inner top region restores standard safe area', (
    tester,
  ) async {
    await open(tester);
    IOSNativeTabBar.topBarRegion.value = null;
    await tester.pump();
    expect(
      tester.getTopLeft(find.byKey(const Key('body'))).dy,
      82 + kToolbarHeight,
    );
  });
}
