import 'package:PiliPlus/common/widgets/view_safe_area.dart';
import 'package:PiliPlus/utils/ios/native_tab_bar.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  const box = Key('box');

  /// 和播放器全屏时的锁定按钮一样：贴左边，可以铺到竖状态栏上
  Widget page({bool left = true, bool right = false}) => MediaQuery(
    data: const MediaQueryData(size: Size(800, 400)),
    child: Directionality(
      textDirection: TextDirection.ltr,
      child: NativeSafeArea(
        scale: 1,
        child: Row(
          children: [
            Expanded(
              child: ViewSafeArea(
                left: left,
                right: right,
                overVerticalBar: true,
                child: const Align(
                  alignment: Alignment.centerLeft,
                  child: SizedBox(key: box, width: 40, height: 40),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );

  double boxLeft(WidgetTester tester) => tester.getTopLeft(find.byKey(box)).dx;

  tearDown(() => IOSNativeTabBar.safeArea.value = null);

  testWidgets('sits over the vertical status bar on the left', (tester) async {
    IOSNativeTabBar.safeArea.value = const EdgeInsets.only(left: 84);
    await tester.pumpWidget(page());

    expect(boxLeft(tester), 0);
  });

  testWidgets('keeps clear of the Dynamic Island on a normal iPhone', (
    tester,
  ) async {
    IOSNativeTabBar.safeArea.value = const EdgeInsets.only(left: 62);
    await tester.pumpWidget(page());

    expect(boxLeft(tester), 62);
  });

  testWidgets('follows the inset when folding or rotating', (tester) async {
    IOSNativeTabBar.safeArea.value = const EdgeInsets.only(left: 62);
    await tester.pumpWidget(page());
    expect(boxLeft(tester), 62);

    IOSNativeTabBar.safeArea.value = const EdgeInsets.only(left: 84);
    await tester.pump();
    expect(boxLeft(tester), 0);

    IOSNativeTabBar.safeArea.value = EdgeInsets.zero;
    await tester.pump();
    expect(boxLeft(tester), 0);
  });

  testWidgets('sits over the vertical status bar on the right', (
    tester,
  ) async {
    IOSNativeTabBar.safeArea.value = const EdgeInsets.only(right: 84);
    await tester.pumpWidget(page(left: false, right: true));

    expect(
      tester
          .widget<Padding>(
            find.descendant(
              of: find.byType(ViewSafeArea),
              matching: find.byType(Padding),
            ),
          )
          .padding,
      EdgeInsets.zero,
    );
  });

  testWidgets('keeps the old behavior without the flag', (tester) async {
    IOSNativeTabBar.safeArea.value = const EdgeInsets.only(left: 84);
    await tester.pumpWidget(
      const MediaQuery(
        data: MediaQueryData(size: Size(800, 400)),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: NativeSafeArea(
            scale: 1,
            child: ViewSafeArea(
              right: false,
              child: Align(
                alignment: Alignment.centerLeft,
                child: SizedBox(key: box, width: 40, height: 40),
              ),
            ),
          ),
        ),
      ),
    );

    expect(boxLeft(tester), 84);
  });
}
