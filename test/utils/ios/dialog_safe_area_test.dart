import 'package:PiliPlus/utils/ios/native_tab_bar.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  const screen = Size(466, 800);

  setUp(() => DialogRoute.safeAreaBuilder = IOSNativeTabBar.dialogSafeArea);

  tearDown(() {
    DialogRoute.safeAreaBuilder = null;
    IOSNativeTabBar.playerFullScreen.value = false;
  });

  /// 合上时竖屏：右边是 84pt 的竖状态栏，底部是 Home 条
  Future<void> open(
    WidgetTester tester, {
    double contentHeight = 100,
    FakeViewPadding padding = const FakeViewPadding(right: 84, bottom: 34),
  }) async {
    tester.view
      ..physicalSize = screen
      ..devicePixelRatio = 1
      ..padding = padding
      ..viewPadding = padding;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => AlertDialog(
                title: const Text('播放信息'),
                content: SizedBox(height: contentHeight, width: 1000),
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  Rect dialogRect(WidgetTester tester) => tester.getRect(
    find.descendant(of: find.byType(Dialog), matching: find.byType(Material)),
  );

  testWidgets('centers on the screen when the vertical bar is hidden', (
    tester,
  ) async {
    IOSNativeTabBar.playerFullScreen.value = true;
    await open(tester);

    final rect = dialogRect(tester);
    expect(rect.center.dx, screen.width / 2);
    expect(rect.center.dy, screen.height / 2);
    expect(rect.left, 40);
    expect(rect.right, screen.width - 40);
  });

  testWidgets('keeps a tall dialog clear of the camera at the top', (
    tester,
  ) async {
    IOSNativeTabBar.playerFullScreen.value = true;
    await open(tester, contentHeight: 2000);

    final rect = dialogRect(tester);
    // 上下各留出竖状态栏的宽度，再加上对话框自己的 24pt 边距
    expect(rect.top, 84 + 24);
    expect(rect.bottom, screen.height - 84 - 24);
  });

  testWidgets('keeps clear of the vertical bar while it is shown', (
    tester,
  ) async {
    await open(tester);

    final rect = dialogRect(tester);
    expect(rect.left, 40);
    expect(rect.right, screen.width - 84 - 40);
  });

  testWidgets('follows the vertical bar when it hides', (tester) async {
    await open(tester);
    expect(dialogRect(tester).right, screen.width - 84 - 40);

    IOSNativeTabBar.playerFullScreen.value = true;
    await tester.pumpAndSettle();
    expect(dialogRect(tester).center.dx, screen.width / 2);
  });

  testWidgets('is unchanged on a normal iPhone', (tester) async {
    await open(
      tester,
      padding: const FakeViewPadding(top: 62, bottom: 34),
    );

    final rect = dialogRect(tester);
    expect(rect.left, 40);
    expect(rect.right, screen.width - 40);
    // 和 Flutter 默认的 SafeArea 一样，在上下安全区之间居中
    expect(rect.center.dy, (62 + screen.height - 34) / 2);
  });
}
