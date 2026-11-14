import 'package:PiliPlus/utils/ios/native_navigation_observer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  testWidgets('global rail tab closes stacked pages and a root popup', (
    tester,
  ) async {
    final observer = NativeNavigationObserver(onCanGoBackChanged: (_) {});
    final key = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: key,
        navigatorObservers: [observer],
        home: const Scaffold(body: Text('home')),
      ),
    );
    for (final text in ['first', 'second']) {
      key.currentState!.push(
        MaterialPageRoute<void>(builder: (_) => Scaffold(body: Text(text))),
      );
      await tester.pumpAndSettle();
    }
    expect(await observer.returnToRoot(), true);
    await tester.pumpAndSettle();
    expect(find.text('home'), findsOneWidget);
    showDialog<void>(
      context: key.currentContext!,
      builder: (_) => const AlertDialog(title: Text('modal')),
    );
    await tester.pumpAndSettle();
    // v3 keeps popup routes out of the rail's page state. Explicit Home still closes them.
    expect(observer.canGoBack, false);
    expect(await observer.returnToRoot(), true);
    await tester.pumpAndSettle();
    expect(observer.canGoBack, false);
  });

  testWidgets('global rail tab does not discard a guarded draft', (
    tester,
  ) async {
    final observer = NativeNavigationObserver(onCanGoBackChanged: (_) {});
    final key = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: key,
        navigatorObservers: [observer],
        home: const Scaffold(),
      ),
    );
    key.currentState!.push(
      MaterialPageRoute<void>(
        builder: (_) =>
            const PopScope(canPop: false, child: Scaffold(body: Text('draft'))),
      ),
    );
    await tester.pumpAndSettle();
    expect(await observer.returnToRoot(), false);
    expect(observer.canGoBack, true);
    expect(find.text('draft'), findsOneWidget);
  });
  testWidgets('back follows pushes, modals, replacements and removals', (
    tester,
  ) async {
    final changes = <bool>[];
    final observer = NativeNavigationObserver(onCanGoBackChanged: changes.add);
    final key = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: key,
        navigatorObservers: [observer],
        home: const Scaffold(body: Text('home')),
      ),
    );
    expect(changes.last, false);
    final page = MaterialPageRoute<void>(
      builder: (_) => const Scaffold(body: Text('page')),
    );
    key.currentState!.push(page);
    await tester.pumpAndSettle();
    expect(changes.last, true);
    showDialog<void>(
      context: key.currentContext!,
      builder: (_) => const AlertDialog(title: Text('modal')),
    );
    await tester.pumpAndSettle();
    expect(changes.last, true);
    key.currentState!.pop();
    await tester.pumpAndSettle();
    expect(changes.last, true);
    final replacement = MaterialPageRoute<void>(
      builder: (_) => const Scaffold(body: Text('replacement')),
    );
    key.currentState!.pushReplacement(replacement);
    await tester.pumpAndSettle();
    expect(changes.last, true);
    key.currentState!.removeRoute(replacement);
    await tester.pumpAndSettle();
    expect(changes.last, false);
  });

  testWidgets('maybePop retains page PopScope interception', (tester) async {
    final observer = NativeNavigationObserver(onCanGoBackChanged: (_) {});
    final key = GlobalKey<NavigatorState>();
    var intercepted = 0;
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: key,
        navigatorObservers: [observer],
        home: const Scaffold(body: Text('home')),
      ),
    );
    key.currentState!.push(
      MaterialPageRoute<void>(
        builder: (_) => PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, result) {
            if (!didPop) intercepted++;
          },
          child: const Scaffold(body: Text('draft')),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await key.currentState!.maybePop();
    await tester.pumpAndSettle();
    expect(intercepted, 1);
    expect(observer.canGoBack, true);
    expect(find.text('draft'), findsOneWidget);
  });
}
