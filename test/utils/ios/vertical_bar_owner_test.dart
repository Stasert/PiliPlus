import 'package:PiliPlus/utils/ios/vertical_bar_owner.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('VerticalBarOwner', () {
    late List<bool> sent;
    late List<VoidCallback> pending;
    late VerticalBarOwner owner;

    setUp(() {
      sent = [];
      pending = [];
      owner = VerticalBarOwner(onChanged: sent.add, schedule: pending.add);
    });

    void endFrame() {
      final callbacks = List.of(pending);
      pending.clear();
      for (final callback in callbacks) {
        callback();
      }
    }

    const a = 'A', b = 'B';

    test('B 返回 A：先 A 的 didPopNext 再 B 的 didPop，仍保持隐藏', () {
      owner
        ..claim(b)
        ..claim(a)
        ..release(b);
      endFrame();
      expect(sent.last, isTrue);
      expect(owner.owner, a);
    });

    test('B 返回 A：先 B 的 didPop 再 A 的 didPopNext，仍保持隐藏', () {
      owner
        ..claim(b)
        ..release(b)
        ..claim(a);
      endFrame();
      expect(sent.last, isTrue);
      expect(owner.owner, a);
    });

    test('离开最后一个视频页时恢复显示', () {
      owner
        ..claim(a)
        ..release(a);
      expect(sent.last, isTrue, reason: '等这一帧结束再决定');
      endFrame();
      expect(sent.last, isFalse);
      expect(owner.owner, isNull);
    });

    test('从 A 打开 B 时不会先显示再隐藏', () {
      owner
        ..claim(a)
        ..release(a)
        ..claim(b);
      endFrame();
      expect(sent, [true, true]);
    });

    test('交还后同一帧里又回到最上层，仍保持隐藏', () {
      owner
        ..claim(a)
        ..release(a)
        ..claim(a);
      endFrame();
      expect(sent.last, isTrue);
      expect(owner.owner, a);
    });

    test('不是拥有者的页面交还时什么也不做', () {
      owner
        ..claim(a)
        ..release(b);
      endFrame();
      expect(sent, [true]);
      expect(pending, isEmpty);
    });
  });

  // 用真实的 Navigator 和 RouteObserver 验证通知顺序，页面的写法和视频页一致
  group('与 RouteObserver 一起', () {
    late List<bool> sent;
    late VerticalBarOwner owner;
    late RouteObserver<PageRoute<dynamic>> observer;
    final navigatorKey = GlobalKey<NavigatorState>();

    Future<void> pumpApp(WidgetTester tester) async {
      sent = [];
      owner = VerticalBarOwner(
        onChanged: sent.add,
        schedule: (callback) {
          WidgetsBinding.instance.addPostFrameCallback((_) => callback());
        },
      );
      observer = RouteObserver<PageRoute<dynamic>>();
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigatorKey,
          navigatorObservers: [observer],
          home: const Text('home'),
        ),
      );
    }

    Future<void> pushVideo(WidgetTester tester, String name) async {
      navigatorKey.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) =>
              _FakeVideoPage(name: name, owner: owner, observer: observer),
        ),
      );
      await tester.pumpAndSettle();
    }

    Future<void> pop(WidgetTester tester) async {
      navigatorKey.currentState!.pop();
      await tester.pumpAndSettle();
    }

    testWidgets('视频 A → 视频 B → 返回 A：竖状态栏保持隐藏', (tester) async {
      await pumpApp(tester);
      await pushVideo(tester, 'A');
      expect(sent.last, isTrue);

      await pushVideo(tester, 'B');
      expect(sent.last, isTrue);
      expect(sent, isNot(contains(false)), reason: '打开 B 时不应闪一下');

      await pop(tester);
      expect(sent.last, isTrue);
      expect(owner.owner, isA<_FakeVideoPageState>());
    });

    testWidgets('离开最后一个视频页时恢复显示', (tester) async {
      await pumpApp(tester);
      await pushVideo(tester, 'A');
      await pushVideo(tester, 'B');
      await pop(tester);
      await pop(tester);
      expect(sent.last, isFalse);
      expect(owner.owner, isNull);
    });

    testWidgets('停在 B 时被盖住的 A 开合、旋转也不会改回显示', (tester) async {
      await pumpApp(tester);
      await pushVideo(tester, 'A');
      await pushVideo(tester, 'B');
      sent.clear();

      // 开合、旋转会让所有页面的 MediaQuery 变化
      tester.view.physicalSize = const Size(2400, 1600);
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpAndSettle();
      expect(sent, everyElement(isTrue));
      expect(sent, isNotEmpty);
    });
  });
}

class _FakeVideoPage extends StatefulWidget {
  const _FakeVideoPage({
    required this.name,
    required this.owner,
    required this.observer,
  });

  final String name;
  final VerticalBarOwner owner;
  final RouteObserver<PageRoute<dynamic>> observer;

  @override
  State<_FakeVideoPage> createState() => _FakeVideoPageState();
}

class _FakeVideoPageState extends State<_FakeVideoPage> with RouteAware {
  bool _isOnTop = false;
  bool _subscribed = false;

  void _update() {
    if (_isOnTop) {
      widget.owner.claim(this);
    } else {
      widget.owner.release(this);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_subscribed) {
      _subscribed = true;
      widget.observer.subscribe(this, ModalRoute.of(context)! as PageRoute);
    }
    MediaQuery.sizeOf(context);
    if (_isOnTop) _update();
  }

  @override
  void didPush() => _isOnTop = true;

  @override
  void didPop() {
    _isOnTop = false;
    _update();
  }

  @override
  void didPushNext() {
    _isOnTop = false;
    _update();
  }

  @override
  void didPopNext() {
    _isOnTop = true;
    _update();
  }

  @override
  void dispose() {
    widget.observer.unsubscribe(this);
    widget.owner.release(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Text(widget.name);
}
