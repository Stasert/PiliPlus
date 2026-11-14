import 'package:PiliPlus/common/widgets/refresh_indicator.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  testWidgets(
    'legacy redundant Obx reproduces the comment-area error placeholder',
    (tester) async {
      final refreshing = false.obs;
      await tester.pumpWidget(
        MaterialApp(
          home: Stack(
            children: [
              const SizedBox.expand(),
              Positioned(
                top: 100,
                left: 0,
                right: 0,
                child: Obx(() => RefreshIndicator_(isRefreshing: refreshing)),
              ),
            ],
          ),
        ),
      );
      expect(
        tester.takeException().toString(),
        contains('improper use of a GetX'),
      );
      expect(find.byType(ErrorWidget), findsOneWidget);
    },
  );

  testWidgets(
    'refresh indicator owns Rx subscription and never covers or blocks comment content',
    (tester) async {
      final refreshing = false.obs;
      var taps = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: Stack(
            children: [
              Positioned.fill(
                child: GestureDetector(
                  onTap: () => taps++,
                  child: const ColoredBox(color: Colors.black),
                ),
              ),
              Positioned(
                top: 100,
                left: 0,
                right: 0,
                child: RefreshIndicator_(isRefreshing: refreshing),
              ),
            ],
          ),
        ),
      );
      expect(find.byType(ErrorWidget), findsNothing);
      await tester.tapAt(const Offset(40, 200));
      expect(taps, 1);
      refreshing.value = true;
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(
        tester.getSize(find.byType(CircularProgressIndicator)),
        const Size(28, 28),
      );
      await tester.tapAt(const Offset(40, 200));
      expect(taps, 2);
      refreshing.value = false;
      await tester.pumpAndSettle();
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byType(ErrorWidget), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
