import 'package:PiliPlus/utils/ios/native_navigation_observer.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late NativeNavigationObserver observer;
  late List<NativeRailTransition> samples;
  late GlobalKey<NavigatorState> key;
  String? publishedPage;
  final entryOwners = <String?>[];
  Future<void> start(WidgetTester tester) async {
    samples = [];
    entryOwners.clear();
    publishedPage = null;
    key = GlobalKey<NavigatorState>();
    observer = NativeNavigationObserver(
      onCanGoBackChanged: (_) {},
      onTopRouteChanged: (route) => publishedPage = route?.settings.name,
      onRailTransition: (state) {
        samples.add(state);
        if (state.active && !state.returning) entryOwners.add(publishedPage);
      },
    );
    await tester.pumpWidget(
      CupertinoApp(
        navigatorKey: key,
        navigatorObservers: [observer],
        builder: (_, child) => Listener(
          onPointerUp: (_) => observer.releaseRailGesture(),
          child: child!,
        ),
        home: const CupertinoPageScaffold(child: SizedBox.expand()),
      ),
    );
    await tester.pumpAndSettle();
  }

  CupertinoPageRoute<void> page(String name) => CupertinoPageRoute(
    settings: RouteSettings(name: name),
    builder: (_) => const CupertinoPageScaffold(child: SizedBox.expand()),
  );

  testWidgets('destination is published before root and nested entry begins', (
    tester,
  ) async {
    await start(tester);
    key.currentState!.push(page('/a'));
    expect(entryOwners.first, '/a');
    await tester.pumpAndSettle();
    entryOwners.clear();
    key.currentState!.push(page('/b'));
    expect(entryOwners.first, '/b');
    await tester.pumpAndSettle();
  });

  testWidgets(
    'push and pop stream actual intermediate progress through completion',
    (tester) async {
      await start(tester);
      final detail = page('/detail');
      key.currentState!.push(detail);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(
        samples.any((e) => e.active && e.secondary > 0 && e.secondary < 1),
        isTrue,
        reason: samples.map((e) => e.toMap()).toString(),
      );
      await tester.pumpAndSettle();
      expect(samples.last.active, isFalse);
      expect(samples.last.secondary, 1);
      expect(samples.last.returning, isFalse);
      samples.clear();
      key.currentState!.pop();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(
        observer.canGoBack,
        isFalse,
        reason: 'page ownership changes before the visual pop completes',
      );
      expect(samples.last.active, isTrue);
      expect(samples.last.secondary, inExclusiveRange(0, 1));
      await tester.pumpAndSettle();
      expect(samples.last.secondary, 0);
      expect(samples.last.active, isFalse);
      expect(samples.last.returning, isTrue);
    },
  );

  testWidgets(
    'cancelled real edge swipe restores the detail capsule and keeps tabs covered',
    (tester) async {
      await start(tester);
      key.currentState!.push(page('/detail'));
      await tester.pumpAndSettle();
      samples.clear();
      final gesture = await tester.startGesture(const Offset(2, 250));
      await gesture.moveBy(const Offset(180, 0));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));
      expect(samples.last.interactive, isTrue);
      observer.releaseRailGesture();
      await tester.idle();
      expect(samples.last.interactive, isFalse);
      expect(
        samples.last.active,
        isTrue,
        reason: 'release keeps the route progress stream running for spring settling',
      );
      expect(
        samples.any((e) => e.returning && e.secondary < 1 && e.secondary > 0),
        isTrue,
      );
      await gesture.moveBy(const Offset(-100, 0));
      await tester.pump(const Duration(milliseconds: 100));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(observer.canGoBack, isTrue);
      expect(samples.last.active, isFalse);
      expect(samples.last.secondary, 1);
      expect(samples.every((e) => e.returning), isTrue);
    },
  );

  testWidgets(
    'completed edge swipe reveals root without a second animation clock',
    (tester) async {
      await start(tester);
      key.currentState!.push(page('/detail'));
      await tester.pumpAndSettle();
      samples.clear();
      final gesture = await tester.startGesture(const Offset(2, 250));
      await gesture.moveBy(const Offset(650, 0));
      await tester.pump(const Duration(milliseconds: 100));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(observer.canGoBack, isFalse);
      expect(samples.last.secondary, 0);
      expect(samples.last.active, isFalse);
      expect(
        samples.map((e) => e.id).toSet(),
        hasLength(1),
        reason: 'didPop must keep the gesture progress stream',
      );
    },
  );

  testWidgets(
    'secondary-to-secondary navigation never reveals root navigation',
    (tester) async {
      await start(tester);
      key.currentState!.push(page('/a'));
      await tester.pumpAndSettle();
      samples.clear();
      key.currentState!.push(page('/b'));
      await tester.pumpAndSettle();
      expect(samples.any((e) => e.active && !e.returning), isTrue);
      expect(samples.every((e) => e.secondary == 1), isTrue);
      expect(samples.last.active, isFalse);
      samples.clear();
      key.currentState!.pop();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(samples.last.active, isTrue);
      expect(samples.last.returning, isTrue);
      expect(samples.every((e) => e.secondary == 1), isTrue);
      await tester.pumpAndSettle();
      expect(samples.last.active, isFalse);
      expect(observer.canGoBack, isTrue);
      await observer.returnToRoot();
      await tester.pumpAndSettle();
      expect(samples.last.secondary, 0);
    },
  );

  testWidgets('rapid push then pop supersedes the entering motion', (
    tester,
  ) async {
    await start(tester);
    key.currentState!.push(page('/a'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    final pushID = samples.last.id;
    key.currentState!.pop();
    await tester.pumpAndSettle();
    expect(samples.last.id, greaterThan(pushID));
    expect(samples.last.returning, isTrue);
    expect(samples.last.active, isFalse);
    expect(samples.last.secondary, 0);
  });

  testWidgets('removing an animating page closes its listener', (tester) async {
    await start(tester);
    final route = page('/a');
    key.currentState!.push(route);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    key.currentState!.removeRoute(route);
    await tester.pumpAndSettle();
    expect(
      samples.last.secondary,
      0,
      reason: samples.map((e) => e.toMap()).toString(),
    );
    expect(samples.last.active, isFalse);
    final count = samples.length;
    await tester.pump(const Duration(seconds: 1));
    expect(samples, hasLength(count));
  });

  testWidgets('return completion waits for the final frame', (tester) async {
    await start(tester);
    final route = ControlledRailRoute();
    key.currentState!.push(route);
    await tester.pumpAndSettle();
    key.currentState!.pop();
    await tester.pump();
    samples.clear();
    route.finishReturn();
    expect(
      samples.where((e) => !e.active),
      isEmpty,
      reason: 'status listeners run before the outgoing page is painted',
    );
    await tester.pump();
    expect(samples.last.active, isFalse);
    expect(samples.last.secondary, 0);
  });

  testWidgets('a new route invalidates an unpainted return completion', (
    tester,
  ) async {
    await start(tester);
    final route = ControlledRailRoute();
    key.currentState!.push(route);
    await tester.pumpAndSettle();
    key.currentState!.pop();
    await tester.pump();
    samples.clear();
    route.finishReturn();
    final oldID = samples.last.id;
    key.currentState!.push(page('/new-detail'));
    await tester.pumpAndSettle();
    expect(samples.where((e) => e.id == oldID && !e.active), isEmpty);
    expect(samples.last.secondary, 1);
    expect(samples.last.returning, isFalse);
  });

  testWidgets('nested edge swipe holds commands without exposing root', (
    tester,
  ) async {
    await start(tester);
    key.currentState!.push(page('/a'));
    await tester.pumpAndSettle();
    key.currentState!.push(page('/dynamicDetail'));
    await tester.pumpAndSettle();
    samples.clear();
    final gesture = await tester.startGesture(const Offset(2, 250));
    await gesture.moveBy(const Offset(650, 0));
    await tester.pump(const Duration(milliseconds: 100));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(samples.any((e) => e.active && e.returning), isTrue);
    expect(samples.every((e) => e.secondary == 1), isTrue);
    expect(samples.last.active, isFalse);
    expect(observer.canGoBack, isTrue);
  });

  testWidgets('button return commits before the outgoing animation finishes', (
    tester,
  ) async {
    await start(tester);
    key.currentState!.push(page('/dynamicDetail'));
    await tester.pumpAndSettle();
    samples.clear();
    key.currentState!.pop();
    expect(samples.last.active, isTrue);
    expect(samples.last.interactive, isFalse);
    expect(samples.last.committed, isTrue);
    expect(samples.last.destinationSecondary, 0);
    await tester.pumpAndSettle();
  });

  testWidgets('held drag locks commands and release commits during settling', (
    tester,
  ) async {
    await start(tester);
    key.currentState!.push(page('/dynamicDetail'));
    await tester.pumpAndSettle();
    samples.clear();
    final gesture = await tester.startGesture(const Offset(2, 250));
    await gesture.moveBy(const Offset(600, 0));
    await tester.pump(const Duration(milliseconds: 200));
    expect(samples.last.interactive, isTrue);
    expect(samples.last.committed, isNull);
    await gesture.up();
    await tester.idle();
    expect(
      samples.any(
        (e) =>
            e.active &&
            !e.interactive &&
            e.committed == true &&
            e.destinationSecondary == 0,
      ),
      isTrue,
    );
    await tester.pumpAndSettle();
  });

  testWidgets('cancelled release restores the detail destination', (
    tester,
  ) async {
    await start(tester);
    key.currentState!.push(page('/dynamicDetail'));
    await tester.pumpAndSettle();
    samples.clear();
    final gesture = await tester.startGesture(const Offset(2, 250));
    await gesture.moveBy(const Offset(150, 0));
    await tester.pump(const Duration(milliseconds: 200));
    await gesture.up();
    await tester.idle();
    expect(
      samples.any(
        (e) =>
            e.active &&
            !e.interactive &&
            e.committed == false &&
            e.destinationSecondary == 1,
      ),
      isTrue,
    );
    expect(samples.any((e) => e.committed == true), isFalse);
    await tester.pumpAndSettle();
    expect(observer.canGoBack, isTrue);
  });
}

class ControlledRailRoute extends CupertinoPageRoute<void> {
  ControlledRailRoute()
    : super(
        builder: (_) => const CupertinoPageScaffold(child: SizedBox.expand()),
      );
  void finishReturn() {
    controller!.stop();
    controller!.value = 0;
  }
}
