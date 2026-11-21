import 'package:PiliPlus/utils/ios/native_page_actions.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'initial video controls are visual only until real handler registers',
    () async {
      late Map<String, Object> state;
      final registry = NativePageActionRegistry(
        onChanged: (value) => state = value,
      );
      final page = Object();
      const actions = [NativePageAction(id: 'fullscreen', title: '全屏')];
      registry.setTopPage(page, backOnly: false, initialActions: actions);
      expect((state['items'] as List).single, containsPair('id', 'fullscreen'));
      expect(state['owner'], 0);
      await registry.handle(owner: 0, id: 'fullscreen');
      final called = <String>[];
      registry.register(page: page, actions: actions, handler: called.add);
      await registry.handle(owner: state['owner'] as int, id: 'fullscreen');
      expect(called, ['fullscreen']);
      registry.setTopPage(Object());
      expect(state['items'], isEmpty);
    },
  );
  const like = NativePageAction(id: 'like', title: '点赞', count: '428');
  test(
    'commands stay with their route across modals and stacked details',
    () async {
      late Map<String, Object> state;
      final registry = NativePageActionRegistry(
        onChanged: (value) => state = value,
      );
      final first = Object();
      final second = Object();
      final modal = Object();
      final called = <String>[];
      registry
        ..setTopPage(first)
        ..register(
          page: first,
          actions: [like],
          handler: (id) => called.add('first:$id'),
        );
      final firstOwner = state['owner'] as int;
      registry.register(
        page: second,
        actions: [like],
        handler: (id) => called.add('second:$id'),
      );
      expect(state['owner'], firstOwner);
      registry.setTopPage(second);
      final secondOwner = state['owner'] as int;
      await registry.handle(owner: firstOwner, id: 'like');
      expect(called, isEmpty);
      await registry.handle(owner: secondOwner, id: 'like');
      expect(called, ['second:like']);
      registry.setTopPage(modal);
      expect(state['items'], isEmpty);
      await registry.handle(owner: secondOwner, id: 'like');
      expect(called.length, 1);
      registry.setTopPage(first);
      expect(state['owner'], firstOwner);
      await registry.handle(owner: firstOwner, id: 'like');
      expect(called.last, 'first:like');
    },
  );

  test(
    'updates keep owner stable; disabled and removed actions cannot dispatch',
    () async {
      late Map<String, Object> state;
      final registry = NativePageActionRegistry(
        onChanged: (value) => state = value,
      );
      final page = Object();
      final called = <String>[];
      registry
        ..setTopPage(page)
        ..register(page: page, actions: [like], handler: called.add);
      final owner = state['owner'] as int;
      registry.register(
        page: page,
        actions: [
          const NativePageAction(
            id: 'like',
            title: '点赞',
            count: '429',
            selected: true,
          ),
          const NativePageAction(id: 'compose', title: '写评论', enabled: false),
        ],
        handler: called.add,
      );
      expect(state['owner'], owner);
      expect((state['items'] as List).first, containsPair('selected', true));
      await registry.handle(owner: owner, id: 'compose');
      await registry.handle(owner: owner, id: 'unknown');
      expect(called, isEmpty);
      registry.unregister(page);
      expect(state['items'], isEmpty);
      await registry.handle(owner: owner, id: 'like');
      expect(called, isEmpty);
      registry.register(page: page, actions: [like], handler: called.add);
      expect(state['owner'], isNot(owner));
      await registry.handle(owner: owner, id: 'like');
      expect(called, isEmpty);
    },
  );
  test('stacked videos reject covered updates and stale disposal', () {
    final a = Object(), b = Object();
    final published = <Map<String, Object>>[];
    final registry = NativePageActionRegistry(onChanged: published.add);
    const playing = NativeVideoChrome(
      controlsVisible: false,
      fullScreen: false,
      locked: false,
    );
    const paused = NativeVideoChrome(
      controlsVisible: true,
      fullScreen: false,
      locked: false,
      paused: true,
    );
    registry
      ..register(
        page: a,
        actions: const [NativePageAction(id: 'home', title: '主页')],
        handler: (_) {},
        video: playing,
      )
      ..setTopPage(a, backOnly: false);
    final ownerA = published.last['owner'];
    registry
      ..register(
        page: b,
        actions: const [NativePageAction(id: 'home', title: '主页')],
        handler: (_) {},
        video: paused,
      )
      ..setTopPage(b, backOnly: false);
    final stateB = published.last;
    final count = published.length;
    registry.register(
      page: a,
      actions: const [NativePageAction(id: 'home', title: '主页')],
      handler: (_) {},
      video: playing,
    );
    expect(published.length, count);
    expect(published.last, stateB);
    registry
      ..setTopPage(a, backOnly: false)
      ..unregister(b);
    expect(published.last['owner'], ownerA);
    expect(published.last['backOnly'], false);
    expect(published.last['video'], playing.toMap());
  });
}
