import 'package:PiliPlus/models/common/inner_video_detail_layout.dart';
import 'package:PiliPlus/pages/video/widgets/inner_video_split_layout.dart';
import 'package:PiliPlus/pages/video/widgets/video_detail_body_insets.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'inner details reserve the rail and fullscreen releases it without replacing player',
    (tester) async {
      Future<void> render(bool fullscreen) => tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: MediaQuery(
            data: const MediaQueryData(
              padding: EdgeInsets.only(right: 84),
              viewPadding: EdgeInsets.only(right: 84),
            ),
            child: VideoDetailBodyInsets(
              extendRight: false,
              fullScreen: fullscreen,
              child: InnerVideoSplitLayout(
                fullScreen: fullscreen,
                playerBuilder: (_, width, height) =>
                    const _PlayerProbe(key: Key('video')),
                detailsBuilder: (_, width, height) =>
                    const SizedBox.expand(key: Key('details')),
              ),
            ),
          ),
        ),
      );
      await render(false);
      final state = tester.state(find.byKey(const Key('video')));
      expect(tester.getRect(find.byKey(const Key('details'))).right, 716);
      await render(true);
      expect(
        tester.getRect(find.byKey(const Key('video'))),
        const Rect.fromLTWH(0, 0, 800, 600),
      );
      expect(tester.state(find.byKey(const Key('video'))), same(state));
      await render(false);
      expect(tester.getRect(find.byKey(const Key('details'))).right, 716);
      expect(tester.state(find.byKey(const Key('video'))), same(state));
    },
  );
  test(
    'fixed layout uses wide inner windows and falls back in narrow portrait',
    () {
      for (final size in [const Size(626, 890), const Size(890, 626)]) {
        expect(
          usesInnerVideoSplit(
            isIPhone: true,
            windowSize: size,
            layout: InnerVideoDetailLayout.split,
          ),
          size.width >= 820,
        );
        expect(
          usesInnerVideoSplit(
            isIPhone: true,
            windowSize: size,
            layout: InnerVideoDetailLayout.auto,
          ),
          isFalse,
        );
      }
      expect(
        usesInnerVideoSplit(
          isIPhone: true,
          windowSize: const Size(466, 678),
          layout: InnerVideoDetailLayout.split,
        ),
        isFalse,
      );
      expect(
        usesInnerVideoSplit(
          isIPhone: false,
          windowSize: const Size(890, 626),
          layout: InnerVideoDetailLayout.split,
        ),
        isFalse,
      );
    },
  );

  test('saved mode restores auto or split and safely defaults to auto', () {
    expect(InnerVideoDetailLayout.fromStorage(0), InnerVideoDetailLayout.auto);
    expect(InnerVideoDetailLayout.fromStorage(1), InnerVideoDetailLayout.split);
    for (final value in [null, -1, 2, '1']) {
      expect(
        InnerVideoDetailLayout.fromStorage(value),
        InnerVideoDetailLayout.auto,
      );
    }
  });

  testWidgets('player fills the left column and details fill the right edge', (
    tester,
  ) async {
    for (final size in [
      const Size(890, 626),
      const Size(626, 890),
      const Size(560, 800),
    ]) {
      await tester.binding.setSurfaceSize(size);
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: InnerVideoSplitLayout(
            fullScreen: false,
            playerBuilder: (_, width, height) =>
                const SizedBox.expand(key: Key('video')),
            detailsBuilder: (_, width, height) =>
                const SizedBox.expand(key: Key('details')),
          ),
        ),
      );
      final video = tester.getRect(find.byKey(const Key('video')));
      final details = tester.getRect(find.byKey(const Key('details')));
      expect(video.left, 0);
      expect(video.top, 0);
      expect(video.height, size.height);
      expect(details.top, 0);
      expect(details.height, size.height);
      expect(details.left, video.right);
      expect(details.right, size.width);
      expect(details.width, greaterThanOrEqualTo(280));
      expect(tester.takeException(), isNull);
    }
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets(
    'scrolling the right pane leaves the video fixed; fullscreen retains state',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(890, 626));
      final scrollController = ScrollController();
      addTearDown(scrollController.dispose);
      Future<void> render(bool fullScreen) => tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: InnerVideoSplitLayout(
            fullScreen: fullScreen,
            playerBuilder: (_, width, height) =>
                const _PlayerProbe(key: Key('video')),
            detailsBuilder: (_, width, height) => ListView.builder(
              key: const Key('details'),
              controller: scrollController,
              itemExtent: 100,
              itemCount: 40,
              itemBuilder: (_, index) => Text('详情 $index'),
            ),
          ),
        ),
      );
      await render(false);
      final playerState = tester.state(find.byKey(const Key('video')));
      final video = tester.getRect(find.byKey(const Key('video')));
      await tester.drag(
        find.byKey(const Key('details')),
        const Offset(0, -300),
      );
      await tester.pumpAndSettle();
      final offset = scrollController.offset;
      expect(offset, greaterThan(0));
      expect(tester.getRect(find.byKey(const Key('video'))), video);
      await render(true);
      expect(find.byKey(const Key('details')), findsNothing);
      expect(tester.state(find.byKey(const Key('video'))), same(playerState));
      expect(
        tester.getRect(find.byKey(const Key('video'))),
        const Rect.fromLTWH(0, 0, 890, 626),
      );
      await render(false);
      expect(tester.getRect(find.byKey(const Key('video'))), video);
      expect(tester.state(find.byKey(const Key('video'))), same(playerState));
      expect(scrollController.offset, offset);
      expect(tester.takeException(), isNull);
      await tester.binding.setSurfaceSize(null);
    },
  );
}

class _PlayerProbe extends StatefulWidget {
  const _PlayerProbe({super.key});

  @override
  State<_PlayerProbe> createState() => _PlayerProbeState();
}

class _PlayerProbeState extends State<_PlayerProbe> {
  @override
  Widget build(BuildContext context) => const SizedBox.expand();
}
