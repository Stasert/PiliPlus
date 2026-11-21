import 'package:PiliPlus/utils/ios/native_navigation_batch.dart';
import 'package:PiliPlus/utils/ios/native_page_actions.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('NativePageActionRegistry', () {
    late List<Map<String, Object>> published;
    late NativePageActionRegistry registry;

    setUp(() {
      published = [];
      registry = NativePageActionRegistry(onChanged: published.add);
    });

    test('publishes only the top page buttons', () {
      final a = Object(), b = Object();
      registry
        ..register(
          page: a,
          actions: const [NativePageAction(id: 'like', title: '点赞')],
          handler: (_) {},
        )
        ..setTopPage(b);
      expect(published.last['owner'], 0);
      expect(published.last['items'], isEmpty);

      registry.setTopPage(a);
      expect(published.last['owner'], isNot(0));
      expect(published.last['items'], [
        {'id': 'like', 'title': '点赞', 'selected': false, 'enabled': true},
      ]);
    });

    test(
      'a tap from an old owner or for a disabled button is ignored',
      () async {
        final a = Object(), b = Object();
        final taps = <String>[];
        registry
          ..register(
            page: a,
            actions: const [
              NativePageAction(id: 'like', title: '点赞'),
              NativePageAction(id: 'repost', title: '转发', enabled: false),
            ],
            handler: taps.add,
          )
          ..setTopPage(a);
        final owner = published.last['owner']! as int;

        await registry.handle(owner: owner, id: 'repost');
        expect(taps, isEmpty);

        registry
          ..register(
            page: b,
            actions: const [NativePageAction(id: 'like', title: '点赞')],
            handler: (_) {},
          )
          ..setTopPage(b);
        await registry.handle(owner: owner, id: 'like');
        expect(taps, isEmpty);

        registry.setTopPage(a);
        await registry.handle(owner: owner, id: 'like');
        expect(taps, ['like']);
      },
    );

    test('unregistering the top page clears its buttons', () {
      final a = Object();
      registry
        ..register(
          page: a,
          actions: const [NativePageAction(id: 'like', title: '点赞')],
          handler: (_) {},
        )
        ..setTopPage(a)
        ..unregister(a);
      expect(published.last['owner'], 0);
      expect(published.last['items'], isEmpty);
    });
  });

  test(
    'scroll item remains registered while hidden and cannot be invoked',
    () async {
      final page = Object();
      late Map<String, Object> state;
      final taps = <String>[];
      final registry = NativePageActionRegistry(onChanged: (v) => state = v)
        ..setTopPage(page, backOnly: true)
        ..register(
          page: page,
          actions: const [
            NativePageAction(id: 'scrollToTop', title: '回顶', visible: false),
            NativePageAction(id: 'comment', title: '评论', count: '8'),
          ],
          handler: taps.add,
        );
      final owner = state['owner'] as int;
      expect(state['backOnly'], true);
      expect((state['items'] as List).length, 2);
      expect(((state['items'] as List).first as Map)['hidden'], true);
      await registry.handle(owner: owner, id: 'scrollToTop');
      expect(taps, isEmpty);
      registry.register(
        page: page,
        actions: const [
          NativePageAction(id: 'scrollToTop', title: '回顶'),
          NativePageAction(id: 'comment', title: '评论', count: '8'),
        ],
        handler: taps.add,
      );
      expect(state['owner'], owner);
      expect(state['backOnly'], true);
      await registry.handle(owner: owner, id: 'scrollToTop');
      expect(taps, ['scrollToTop']);
      registry.setTopPage(Object());
      expect(state['backOnly'], true);
    },
  );

  test(
    'only an explicit video detail opts into Home and pop restores policy',
    () {
      final settings = Object(), video = Object(), comments = Object();
      late Map<String, Object> state;
      final registry = NativePageActionRegistry(onChanged: (v) => state = v)
        ..setTopPage(settings);
      expect(state['backOnly'], true);
      registry.setTopPage(
        video,
        backOnly: false,
        initialVideo: const NativeVideoChrome(
          controlsVisible: false,
          fullScreen: false,
          locked: false,
        ),
      );
      expect(state['backOnly'], false);
      expect(state['video'], isA<Map<String, Object>>());
      registry.setTopPage(comments);
      expect(state['backOnly'], true);
      expect(state['video'], false);
      registry.setTopPage(video, backOnly: false);
      expect(state['backOnly'], false);
      registry.setTopPage(settings);
      expect(state['backOnly'], true);
    },
  );

  group('NativeNavigationBatch', () {
    test('sends the last value once per flush and skips repeats', () {
      void Function()? pending;
      final sent = <Map<String, Object>>[];
      final batch =
          NativeNavigationBatch(
              schedule: (flush) => pending = flush,
              onChanged: sent.add,
            )
            ..submit('page', {'owner': 0})
            ..submit('page', {'owner': 1});
      pending!();
      expect(sent, [
        {
          'page': {'owner': 1},
        },
      ]);

      batch.submit('page', {'owner': 1});
      pending!();
      expect(sent, hasLength(1), reason: 'unchanged values are not resent');
    });
  });
}
