import 'package:PiliPlus/utils/ios/native_navigation_observer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late NativeNavigationObserver observer;
  late List<bool> canGoBack;
  late List<String?> topNames;
  late List<bool> modalChanges;
  final navigatorKey = GlobalKey<NavigatorState>();

  Future<void> pumpApp(WidgetTester tester) async {
    canGoBack = [];
    topNames = [];
    modalChanges = [];
    observer = NativeNavigationObserver(
      onCanGoBackChanged: canGoBack.add,
      onModalOverlayChanged: modalChanges.add,
      onTopRouteChanged: (route) => topNames.add(route?.settings.name),
    );
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        navigatorObservers: [observer],
        home: const SizedBox(),
      ),
    );
  }

  MaterialPageRoute<void> page(String name) => MaterialPageRoute(
    settings: RouteSettings(name: name),
    builder: (_) => const SizedBox(),
  );

  testWidgets('the root page cannot go back', (tester) async {
    await pumpApp(tester);
    expect(observer.canGoBack, isFalse);
    expect(observer.topRoute?.isFirst, isTrue);
  });

  testWidgets('a pushed page can go back, and popping returns', (
    tester,
  ) async {
    await pumpApp(tester);
    navigatorKey.currentState!.push(page('/detail'));
    await tester.pumpAndSettle();
    expect(observer.canGoBack, isTrue);
    expect(topNames.last, '/detail');

    navigatorKey.currentState!.pop();
    await tester.pumpAndSettle();
    expect(observer.canGoBack, isFalse);
    expect(canGoBack.last, isFalse);
  });

  testWidgets('a dialog on a root page is not a secondary page', (
    tester,
  ) async {
    await pumpApp(tester);
    final calls = canGoBack.length;
    showDialog<void>(
      context: navigatorKey.currentContext!,
      builder: (_) => const AlertDialog(),
    );
    await tester.pumpAndSettle();
    expect(observer.canGoBack, isFalse);
    expect(canGoBack.length, calls, reason: 'popups are not reported');

    navigatorKey.currentState!.pop();
    await tester.pumpAndSettle();
    expect(observer.canGoBack, isFalse);
    expect(canGoBack.length, calls);
  });

  testWidgets('a bottom sheet over a secondary page keeps that page on top', (
    tester,
  ) async {
    await pumpApp(tester);
    navigatorKey.currentState!.push(page('/detail'));
    await tester.pumpAndSettle();
    showModalBottomSheet<void>(
      context: navigatorKey.currentContext!,
      builder: (_) => const SizedBox(height: 100),
    );
    await tester.pumpAndSettle();
    expect(observer.canGoBack, isTrue);
    expect(observer.topRoute?.settings.name, '/detail');
  });

  testWidgets('replacing a page keeps the stack depth', (tester) async {
    await pumpApp(tester);
    navigatorKey.currentState!.push(page('/a'));
    await tester.pumpAndSettle();
    navigatorKey.currentState!.pushReplacement(page('/b'));
    await tester.pumpAndSettle();
    expect(observer.canGoBack, isTrue);
    expect(observer.topRoute?.settings.name, '/b');

    navigatorKey.currentState!.pop();
    await tester.pumpAndSettle();
    expect(observer.canGoBack, isFalse);
  });
  testWidgets(
    'nested modal editors keep underlying rail blocked until all close',
    (tester) async {
      await pumpApp(tester);
      navigatorKey.currentState!.push(page('/dynamicDetail'));
      await tester.pumpAndSettle();
      final calls = canGoBack.length;
      for (var i = 0; i < 2; i++) {
        showDialog<void>(
          context: navigatorKey.currentContext!,
          builder: (_) => const AlertDialog(),
        );
        await tester.pumpAndSettle();
      }
      expect(observer.hasModalOverlay, isTrue);
      expect(modalChanges, [true]);
      expect(topNames.last, '/dynamicDetail');
      expect(canGoBack.length, calls);
      navigatorKey.currentState!.pop();
      await tester.pumpAndSettle();
      expect(modalChanges, [true]);
      navigatorKey.currentState!.pop();
      await tester.pumpAndSettle();
      expect(modalChanges, [true, false]);
      expect(observer.canGoBack, isTrue);
    },
  );

  testWidgets(
    'removing and replacing a popup updates coverage without treating it as a page',
    (tester) async {
      await pumpApp(tester);
      final popup = DialogRoute<void>(
        context: navigatorKey.currentContext!,
        builder: (_) => const SizedBox(),
      );
      navigatorKey.currentState!.push(popup);
      await tester.pumpAndSettle();
      expect(observer.canGoBack, isFalse);
      expect(modalChanges, [true]);
      final other = DialogRoute<void>(
        context: navigatorKey.currentContext!,
        builder: (_) => const SizedBox(),
      );
      navigatorKey.currentState!.replace(oldRoute: popup, newRoute: other);
      await tester.pumpAndSettle();
      expect(modalChanges, [true]);
      navigatorKey.currentState!.removeRoute(other);
      await tester.pumpAndSettle();
      expect(modalChanges, [true, false]);
      expect(observer.canGoBack, isFalse);
    },
  );
}
