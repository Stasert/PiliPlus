import 'dart:io';

import 'package:PiliPlus/common/skeleton/video_card_v.dart';
import 'package:PiliPlus/common/widgets/rail_page_view.dart';
import 'package:PiliPlus/common/widgets/view_safe_area.dart';
import 'package:PiliPlus/pages/rcmd/controller.dart';
import 'package:PiliPlus/pages/rcmd/view.dart';
import 'package:PiliPlus/utils/ios/native_tab_bar.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:PiliPlus/utils/storage_key.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:hive_ce/hive.dart';
import 'package:material_ui/material_ui.dart';

class _OfflineRcmdController extends RcmdController {
  @override
  Future<void> queryData([bool isRefresh = true]) async {} // Keep the production loading layout offline.
}

void main() {
  late Directory directory;
  setUpAll(() async {
    directory = await Directory.systemTemp.createTemp('piliplus-rail-margin-');
    Hive.init(directory.path);
    GStorage.setting = await Hive.openBox('setting');
    GStorage.video = await Hive.openBox('video');
    GStorage.localCache = await Hive.openBox('localCache');
  });
  tearDownAll(() async {
    await Hive.close();
    await directory.delete(recursive: true);
  });
  tearDown(() {
    IOSNativeTabBar.safeArea.value = null;
    IOSNativeTabBar.rightRailDevice.value = false;
    IOSNativeTabBar.playerFullScreen.value = false;
    IOSNativeTabBar.railContentMargin.value = RailSpacing.clearance;
  });

  test('margin validates imported settings and leaves ordinary devices/fullscreen unchanged', () {
    for (final value in [null, '12', double.nan, double.infinity]) {
      expect(RailSpacing.normalizeClearance(value), 4);
    }
    expect(RailSpacing.normalizeClearance(-5), 0);
    expect(RailSpacing.normalizeClearance(100), 32);
    expect(RailSpacing.normalizeClearance(12.4), 12);
    for (final margin in [0.0, 4.0, 18.0, 32.0]) {
      expect(
        RailSpacing.rightInset(84, fullScreen: false, contentMargin: margin),
        72 + margin,
      );
      expect(
        RailSpacing.rightInset(84, fullScreen: true, contentMargin: margin),
        0,
      );
      expect(
        RailSpacing.rightInset(59, fullScreen: false, contentMargin: margin),
        59,
      );
    }
  });

  testWidgets(
    'actual home recommendation page follows saved margin without an extra gutter or state reset',
    (tester) async {
      tester.view.physicalSize = const Size(466, 678);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      Get.testMode = true;
      final controller = Get.put<RcmdController>(_OfflineRcmdController());
      IOSNativeTabBar.safeArea.value = const EdgeInsets.only(right: 84);
      IOSNativeTabBar.rightRailDevice.value = true;
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: const NativeSafeArea(
            scale: 1,
            child: SideSafeArea(child: RcmdPage()),
          ),
        ),
      );
      final state = tester.state(find.byType(RcmdPage));
      double rightEdge() =>
          tester.getRect(find.byType(VideoCardVSkeleton).at(1)).right;
      expect(rightEdge(), closeTo(466 - 72 - 4, .001));
      controller.scrollController.jumpTo(25);
      await tester.pump();
      for (final margin in [0.0, 12.0, 32.0, 4.0]) {
        await tester.runAsync(
          () => IOSNativeTabBar.setRailContentMargin(margin),
        );
        await tester.pump();
        expect(Pref.railContentMargin, margin);
        expect(GStorage.setting.get(SettingBoxKey.railContentMargin), margin);
        expect(rightEdge(), closeTo(466 - 72 - margin, .001));
        expect(tester.state(find.byType(RcmdPage)), same(state));
        expect(controller.scrollController.offset, 25);
        expect(tester.takeException(), isNull);
      }
      await tester.pumpWidget(const SizedBox());
      Get.reset();
    },
  );
}
