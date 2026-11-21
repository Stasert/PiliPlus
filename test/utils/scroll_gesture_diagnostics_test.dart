import 'dart:convert';

import 'package:PiliPlus/utils/scroll_gesture_diagnostics.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late ScrollGestureDiagnostics monitor;
  late ScrollController controller;

  Future<void> setup(WidgetTester tester) async {
    tester.view.physicalSize = const Size(400, 700);
    tester.view.devicePixelRatio = 1;
    monitor = ScrollGestureDiagnostics()
      ..attach(tester.binding)
      ..routeName = () => '/dynamics?private=not-exported';
    controller = ScrollController(initialScrollOffset: 1000);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(platform: TargetPlatform.iOS),
        home: ScrollGestureScope(
          diagnostics: monitor,
          child: ListView.builder(
            controller: controller,
            physics: const AlwaysScrollableScrollPhysics(),
            itemExtent: 80,
            itemCount: 200,
            itemBuilder: (_, i) => Text('card $i'),
          ),
        ),
      ),
    );
    await tester.pump();
    addTearDown(() async {
      monitor.detach();
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
  }

  Map<String, dynamic> report() => jsonDecode(monitor.exportReport());
  ScrollPositionWithSingleContext getPosition() =>
      controller.position as ScrollPositionWithSingleContext;
  // ignore: invalid_use_of_protected_member
  ScrollActivity? activity() => controller.position.activity;

  Future<void> fling(WidgetTester tester, {int pointer = 10}) =>
      tester.flingFrom(
        const Offset(200, 350),
        const Offset(0, -200),
        1600,
        pointer: pointer,
      );

  Future<void> expectMomentum(WidgetTester tester) async {
    final released = controller.offset;
    expect(activity(), isA<BallisticScrollActivity>());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    expect(controller.offset - released, greaterThan(100));
  }

  testWidgets('normal iOS inertia is preserved without recovery', (
    tester,
  ) async {
    await setup(tester);
    await fling(tester);
    await expectMomentum(tester);
    expect(report()['recoveries'], 0);
    expect(report()['activePointers'], isEmpty);
  });

  testWidgets('bottom-edge second finger cannot swallow accepted drag end', (
    tester,
  ) async {
    await setup(tester);
    final first = await tester.startGesture(const Offset(200, 350), pointer: 1);
    await first.moveBy(
      const Offset(0, -100),
      timeStamp: const Duration(milliseconds: 60),
    );
    final bottom = await tester.startGesture(
      const Offset(200, 690),
      pointer: 2,
    );
    await first.up(timeStamp: const Duration(milliseconds: 90));
    await bottom.up(timeStamp: const Duration(milliseconds: 100));
    // Assert before the recovery frame, so the SDK fix must work by itself.
    expect(activity(), isNot(isA<DragScrollActivity>()));
    await tester.pumpAndSettle();
    expect(report()['recoveries'], 0);
    await fling(tester);
    await expectMomentum(tester);
  });

  testWidgets(
    'bottom-edge first touch is rejected without blocking next drag',
    (
      tester,
    ) async {
      await setup(tester);
      final bottom = await tester.startGesture(
        const Offset(200, 690),
        pointer: 1,
      );
      await bottom.moveBy(const Offset(0, -180));
      expect(controller.offset, 1000);
      await fling(tester);
      await expectMomentum(tester);
      await bottom.up();
      await tester.pumpAndSettle();
      expect(report()['recoveries'], 0);
    },
  );

  testWidgets('accepted drag remains valid with two accepted fingers', (
    tester,
  ) async {
    await setup(tester);
    final first = await tester.startGesture(const Offset(100, 350), pointer: 1);
    await first.moveBy(const Offset(0, -100));
    final second = await tester.startGesture(
      const Offset(200, 300),
      pointer: 2,
    );
    await second.moveBy(const Offset(0, -100));
    await first.up();
    await tester.pump();
    expect(report()['activePointers'], [2]);
    expect(report()['recoveries'], 0);
    await second.up();
    expect(activity(), isNot(isA<DragScrollActivity>()));
    await tester.pumpAndSettle();
    expect(report()['recoveries'], 0);
  });

  testWidgets('long-held finger is never timed out by recovery', (
    tester,
  ) async {
    await setup(tester);
    final held = await tester.startGesture(const Offset(200, 350), pointer: 1);
    await held.moveBy(const Offset(0, -100));
    await tester.pump(const Duration(seconds: 30));
    expect(activity(), isA<DragScrollActivity>());
    expect(report()['recoveries'], 0);
    expect(report()['activePointers'], [1]);
    await held.up();
    await tester.pumpAndSettle();
  });

  testWidgets('orphaned drag releases only after pointer end and next frame', (
    tester,
  ) async {
    await setup(tester);
    // A touch outside the list owns no recognizer. Inject a leftover activity
    // to reproduce a missing drag-end callback independently of the SDK fix.
    final touch = await tester.startGesture(Offset.zero, pointer: 1);
    getPosition().drag(DragStartDetails(), () {});
    await touch.up();
    expect(activity(), isA<DragScrollActivity>());
    await tester.pump();
    expect(activity(), isA<IdleScrollActivity>());
    expect(report()['recoveries'], 1);
    await fling(tester);
    await expectMomentum(tester);
  });

  testWidgets('orphaned hold releases without changing position', (
    tester,
  ) async {
    await setup(tester);
    getPosition().hold(() {});
    final offset = controller.offset;
    monitor.restoreScrolling();
    expect(activity(), isA<HoldScrollActivity>());
    await tester.pump();
    expect(activity(), isA<IdleScrollActivity>());
    expect(controller.offset, offset);
    expect(report()['recoveries'], 1);
  });

  testWidgets('a new touch invalidates queued recovery', (tester) async {
    await setup(tester);
    getPosition().hold(() {});
    monitor.restoreScrolling();
    final held = await tester.startGesture(const Offset(200, 350), pointer: 1);
    final heldActivity = activity();
    await tester.pump();
    expect(activity(), same(heldActivity));
    expect(report()['activePointers'], [1]);
    expect(report()['recoveries'], 0);
    await held.up();
    await tester.pumpAndSettle();
  });

  testWidgets('programmatic scrolling is not interrupted', (tester) async {
    await setup(tester);
    final animation = controller.animateTo(
      2000,
      duration: const Duration(seconds: 1),
      curve: Curves.linear,
    );
    monitor.restoreScrolling();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(activity(), isA<DrivenScrollActivity>());
    expect(report()['recoveries'], 0);
    await tester.pumpAndSettle();
    await animation;
    expect(controller.offset, 2000);
  });

  testWidgets(
    'manual recovery cancels an unmatched touch and restores inertia',
    (
      tester,
    ) async {
      await setup(tester);
      await tester.startGesture(const Offset(30, 100), pointer: 1);
      for (final id in [2, 3]) {
        await fling(tester, pointer: id);
        final released = controller.offset;
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 120));
        expect(controller.offset, released);
        expect(activity(), isA<DragScrollActivity>());
        expect(report()['recoveries'], 0);
      }
      monitor.restoreScrolling();
      await tester.idle();
      await tester.pump();
      expect(report()['activePointers'], isEmpty);
      await fling(tester, pointer: 4);
      await expectMomentum(tester);
    },
  );

  testWidgets(
    'backgrounding cancels stale touch and resume preserves scrolling',
    (
      tester,
    ) async {
      await setup(tester);
      await tester.startGesture(const Offset(30, 100), pointer: 1);
      await fling(tester, pointer: 2);
      monitor.didChangeAppLifecycleState(AppLifecycleState.inactive);
      await tester.idle();
      monitor.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await tester.pump();
      expect(report()['activePointers'], isEmpty);
      await fling(tester, pointer: 3);
      await expectMomentum(tester);
    },
  );

  testWidgets('records are bounded and omit content, coordinates and query', (
    tester,
  ) async {
    await setup(tester);
    for (var i = 1; i <= 120; i++) {
      final touch = await tester.startGesture(Offset.zero, pointer: i);
      await touch.up();
    }
    await tester.pump();
    final data = report();
    expect(
      (data['events'] as List).length,
      ScrollGestureDiagnostics.recordLimit,
    );
    expect(data['activePointers'], isEmpty);
    expect(data['build'], isNotNull);
    expect(data['buildTimeUnix'], isNotNull);
    final encoded = jsonEncode(data);
    expect(encoded, isNot(contains('not-exported')));
    expect(encoded, isNot(contains('localPosition')));
    expect(encoded, isNot(contains('card ')));
    expect(data['events'].last['route'], '/dynamics');
  });

  testWidgets('disposed scrollables are ignored during pending recovery', (
    tester,
  ) async {
    await setup(tester);
    getPosition().hold(() {});
    monitor.restoreScrolling();
    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.takeException(), isNull);
    expect(report()['recoveries'], 0);
  });

  testWidgets('detaching monitor invalidates pending recovery', (tester) async {
    await setup(tester);
    getPosition().hold(() {});
    monitor
      ..restoreScrolling()
      ..detach();
    await tester.pump();
    expect(activity(), isA<HoldScrollActivity>());
    expect(report()['recoveries'], 0);
    getPosition().goIdle();
  });
}
