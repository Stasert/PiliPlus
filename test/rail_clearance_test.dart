import 'package:PiliPlus/common/widgets/rail_page_view.dart';
import 'package:PiliPlus/common/widgets/scaffold/simple_scaffold.dart';
import 'package:PiliPlus/common/widgets/view_safe_area.dart';
import 'package:PiliPlus/pages/video/widgets/video_detail_body_insets.dart';
import 'package:PiliPlus/utils/ios/native_tab_bar.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  test(
    'every vertical rail uses 72pt footprint plus exactly 4pt clearance',
    () {
      for (final raw in [72.0, 84.0, 96.0, 112.0]) {
        expect(RailSpacing.rightInset(raw, fullScreen: false), 76);
        expect(RailSpacing.rightInset(raw, fullScreen: true), 0);
      }
      for (final raw in [0.0, 22.0, 59.0]) {
        expect(RailSpacing.rightInset(raw, fullScreen: false), raw);
      }
    },
  );

  const content = Key('content-edge');
  final variants = <String, Widget Function(BuildContext)>{
    'titled secondary page': (context) => SideSafeArea(
      child: SimpleScaffold(
        appBar: AppBar(title: const Text('设置 / 搜索 / 历史')),
        body: ViewSafeArea(
          child: Builder(
            builder: (context) => Padding(
              padding: railPageInsets(context, const EdgeInsets.all(16)),
              child: const SizedBox.expand(key: content),
            ),
          ),
        ),
      ),
    ),
    'recommendation and live grid': (context) => SideSafeArea(
      child: RailFeedFrame(
        child: GridView.count(
          padding: EdgeInsets.zero,
          crossAxisCount: 2,
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          children: const [
            SizedBox(),
            SizedBox(key: content),
          ],
        ),
      ),
    ),
    'horizontal page switching': (context) => SideSafeArea(
      child: RailPageView(
        children: [
          Builder(
            builder: (context) => Padding(
              padding: railPageInsets(
                context,
                const EdgeInsets.symmetric(horizontal: 12),
              ),
              child: const SizedBox.expand(key: content),
            ),
          ),
          const SizedBox(),
        ],
      ),
    ),
    'comments with nested safe area': (context) => SideSafeArea(
      child: ViewSafeArea(
        child: Builder(
          builder: (context) => ListView(
            padding: railPageInsets(
              context,
              const EdgeInsets.fromLTRB(12, 10, 8, 10),
            ),
            children: const [SizedBox(key: content, height: 100)],
          ),
        ),
      ),
    ),
    'details below edge-to-edge video': (context) => VideoDetailBodyInsets(
      extendRight: false,
      child: ViewSafeArea(
        child: Builder(
          builder: (context) => Padding(
            padding: railPageInsets(
              context,
              const EdgeInsets.symmetric(horizontal: 12),
            ),
            child: const SizedBox.expand(key: content),
          ),
        ),
      ),
    ),
  };
  for (final entry in variants.entries) {
    testWidgets(
      '${entry.key} reserves configured clearance once across scales and system insets',
      (tester) async {
        tester.view.physicalSize = const Size(466 * 2, 678 * 2);
        tester.view.devicePixelRatio = 2;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        IOSNativeTabBar.rightRailDevice.value = true;
        addTearDown(() {
          IOSNativeTabBar.rightRailDevice.value = false;
          IOSNativeTabBar.safeArea.value = null;
          IOSNativeTabBar.railContentMargin.value = RailSpacing.clearance;
        });
        for (final scale in [0.8, 1.0, 1.5]) {
          for (final (raw, margin) in [
            for (final raw in [72.0, 84.0, 96.0])
              for (final margin in [0.0, 4.0, 12.0, 32.0]) (raw, margin),
          ]) {
            IOSNativeTabBar.railContentMargin.value = margin;
            IOSNativeTabBar.safeArea.value = EdgeInsets.only(right: raw);
            await tester.pumpWidget(
              MaterialApp(
                home: NativeSafeArea(
                  scale: scale,
                  child: Builder(builder: entry.value),
                ),
              ),
            );
            final edge = tester.getRect(find.byKey(content)).right;
            final nativeClearance = (466 - 72 / scale - edge) * scale;
            expect(
              nativeClearance,
              closeTo(margin, 0.001),
              reason: '${entry.key}, scale=$scale, system=$raw, margin=$margin',
            );
            expect(tester.takeException(), isNull);
          }
        }
      },
    );
  }
}
