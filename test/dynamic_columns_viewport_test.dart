import 'dart:io';

import 'package:PiliPlus/common/skeleton/dynamic_card.dart';
import 'package:PiliPlus/utils/global_data.dart';
import 'package:PiliPlus/utils/ios/foldable_helper.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:PiliPlus/utils/storage_key.dart';
import 'package:PiliPlus/utils/waterfall.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:material_ui/material_ui.dart';

class _Feed extends StatefulWidget {
  const _Feed({super.key, required this.loading});
  final bool loading;
  @override
  State<_Feed> createState() => _FeedState();
}

class _FeedState extends State<_Feed> with DynMixin {
  final scroll = ScrollController();
  @override
  void dispose() {
    scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.topLeft,
    child: SizedBox(
      width: 478,
      child: CustomScrollView(
        controller: scroll,
        slivers: [
          widget.loading
              ? dynSkeleton
              : SliverMasonryGrid(
                  crossAxisSpacing: 4,
                  gridDelegate: dynGridDelegate,
                  delegate: SliverChildBuilderDelegate(
                    (_, index) =>
                        SizedBox(key: ValueKey('card-$index'), height: 90),
                    childCount: 40,
                  ),
                ),
        ],
      ),
    ),
  );
}

void main() {
  late Directory dir;
  setUpAll(() async {
    dir = await Directory.systemTemp.createTemp('piliplus-dynamic-columns-');
    Hive.init(dir.path);
    GStorage.setting = await Hive.openBox('setting');
    GStorage.video = await Hive.openBox('video');
    GStorage.localCache = await Hive.openBox('localCache');
  });
  tearDownAll(() async {
    await Hive.close();
    await dir.delete(recursive: true);
  });
  setUp(() {
    IOSFoldableHelper.debugIsIPhone = true;
    GlobalData().dynamicsWaterfallFlow = true;
  });
  tearDown(() {
    IOSFoldableHelper.debugIsIPhone = false;
  });

  for (final scale in [.8, 1.0, 1.5]) {
    testWidgets(
      'route viewport controls loading/loaded columns through popup return at UI scale $scale',
      (tester) async {
        // Leave the global FlutterView reporting the inner display, while the
        // route has already moved to the outer display. Width is unchanged.
        tester.view.physicalSize = const Size(951, 669);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.runAsync(
          () => GStorage.setting.put(SettingBoxKey.uiScale, scale),
        );
        final nav = GlobalKey<NavigatorState>();
        final feed = GlobalKey<_FeedState>();
        final viewport = ValueNotifier(const Size(466, 678));
        final loading = ValueNotifier(true);
        addTearDown(viewport.dispose);
        addTearDown(loading.dispose);
        await tester.pumpWidget(
          MaterialApp(
            navigatorKey: nav,
            builder: (context, child) => ValueListenableBuilder<Size>(
              valueListenable: viewport,
              builder: (context, size, _) => MediaQuery(
                data: MediaQuery.of(context).copyWith(size: size / scale),
                child: child!,
              ),
            ),
            home: ValueListenableBuilder<bool>(
              valueListenable: loading,
              builder: (_, value, _) => _Feed(key: feed, loading: value),
            ),
          ),
        );
        await tester.pump();
        final skeleton = tester.widget<SliverGrid>(find.byType(SliverGrid));
        expect(
          (skeleton.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount)
              .crossAxisCount,
          1,
        );
        expect(find.byType(DynamicCardSkeleton), findsWidgets);
        loading.value = false;
        await tester.pump();
        final state = feed.currentState!;
        double cardX(int i) =>
            tester.getTopLeft(find.byKey(ValueKey('card-$i'))).dx;
        expect(cardX(0), cardX(1));
        state.scroll.jumpTo(120);
        await tester.pump();
        final offset = state.scroll.offset;
        showDialog<void>(
          context: nav.currentContext!,
          builder: (_) => const AlertDialog(),
        );
        await tester.pumpAndSettle();
        nav.currentState!.pop();
        await tester.pumpAndSettle();
        expect(feed.currentState, same(state));
        expect(state.scroll.offset, offset);
        state.scroll.jumpTo(0);
        await tester.pump();
        expect(cardX(0), cardX(1));
        viewport.value = const Size(951, 669);
        await tester.pump();
        expect(cardX(1), greaterThan(cardX(0)));
        viewport.value = const Size(466, 678);
        await tester.pump();
        expect(cardX(0), cardX(1));
        expect(feed.currentState, same(state));
        expect(tester.takeException(), isNull);
      },
    );
  }
}
