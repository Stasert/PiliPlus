import 'dart:io';

import 'package:PiliPlus/common/widgets/home_tools_slot.dart';
import 'package:PiliPlus/common/widgets/rail_page_view.dart';
import 'package:PiliPlus/models/common/bar_hide_type.dart';
import 'package:PiliPlus/models/common/home_tab_type.dart';
import 'package:PiliPlus/pages/home/controller.dart';
import 'package:PiliPlus/pages/home/view.dart';
import 'package:PiliPlus/pages/hot/controller.dart';
import 'package:PiliPlus/pages/main/controller.dart';
import 'package:PiliPlus/pages/rcmd/controller.dart';
import 'package:PiliPlus/pages/rcmd/view.dart';
import 'package:PiliPlus/services/account_service.dart';
import 'package:PiliPlus/utils/ios/native_tab_bar.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:PiliPlus/utils/storage_key.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:hive_ce/hive.dart';
import 'package:material_ui/material_ui.dart';

class _Main extends MainController {
  @override
  // Skip startup network requests in this layout-only fixture.
  // ignore: must_call_super
  void onInit() {
    useBottomNav = true;
    hideBottomBar = false;
    controller = PageController();
  }
}

class _Rcmd extends RcmdController {
  @override
  Future<void> queryData([bool isRefresh = true]) async {}
}

class _Hot extends HotController {
  @override
  Future<void> queryData([bool isRefresh = true]) async {}
}

void main() {
  late Directory dir;
  setUpAll(() async {
    dir = await Directory.systemTemp.createTemp('piliplus-home-collapse-');
    Hive.init(dir.path);
    GStorage.setting = await Hive.openBox('setting');
    GStorage.video = await Hive.openBox('video');
    GStorage.localCache = await Hive.openBox('localCache');
    GStorage.userInfo = await Hive.openBox('userInfo');
  });
  tearDownAll(() async {
    await Hive.close();
    await dir.delete(recursive: true);
  });
  tearDown(() {
    IOSNativeTabBar.rightRailDevice.value = false;
    Get.reset();
  });
  Future<MainController> pumpHome(
    WidgetTester tester,
    BarHideType mode, {
    bool enabled = true,
    HomeToolsPlacement placement = HomeToolsPlacement.rightRail,
    double nativeTop = 0,
    double scale = 1,
  }) async {
    tester.view.physicalSize = const Size(466, 678);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.runAsync(
      () => GStorage.setting.putAll({
        SettingBoxKey.hideTopBar: enabled,
        SettingBoxKey.barHideType: mode.index,
        SettingBoxKey.useSideBar: false,
        SettingBoxKey.enableSearchWord: false,
        SettingBoxKey.showHotRcmd: false,
        SettingBoxKey.tabBarSort: [
          HomeTabType.rcmd.index,
          HomeTabType.hot.index,
        ],
      }),
    );
    Get.testMode = true;
    Get.put(AccountService());
    final main = Get.put<MainController>(_Main());
    main.homeToolsPlacement.value = placement;
    IOSNativeTabBar.rightRailDevice.value =
        placement == HomeToolsPlacement.rightRail;
    Get
      ..put<RcmdController>(_Rcmd())
      ..put<HotController>(_Hot());
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: Builder(
          builder: (context) {
            final padding = EdgeInsets.only(top: nativeTop / scale);
            return MediaQuery(
              data: MediaQuery.of(context).copyWith(
                viewPadding: padding,
                padding: padding,
              ),
              child: RailViewportScope(
                insets: padding,
                windowWidth: 466,
                normalizedTop: nativeTop > 0,
                child: Padding(
                  padding: EdgeInsets.only(
                    top: homePageTopSpacing(
                      padding.top,
                      placement,
                      alreadyNormalized: nativeTop > 0,
                    ),
                  ),
                  child: const ClipRect(child: Scaffold(body: HomePage())),
                ),
              ),
            );
          },
        ),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
    return main;
  }

  Finder getFeed() => find.descendant(
    of: find.byType(RcmdPage),
    matching: find.byType(CustomScrollView),
  );
  Future<void> drag(WidgetTester tester, Offset offset) async {
    await tester.drag(getFeed(), offset);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
  }

  for (final mode in BarHideType.values) {
    testWidgets(
      'actual rail home sections collapse and return in ${mode.name} mode without losing page state',
      (tester) async {
        final main = await pumpHome(tester, mode);
        final state = tester.state(find.byType(RcmdPage));
        final tabController = Get.find<HomeController>().tabController;
        final top = tester.getTopLeft(getFeed()).dy;
        expect(top, 44);
        await drag(tester, const Offset(0, -240));
        expect(tester.getTopLeft(getFeed()).dy, closeTo(0, .01));
        expect(tester.state(find.byType(RcmdPage)), same(state));
        expect(tabController.index, 0);
        final hiddenOffset = main.barOffset?.value;
        final hiddenVisible = Get.find<HomeController>().showTopBar?.value;
        await drag(tester, const Offset(-240, 0));
        expect(main.barOffset?.value, hiddenOffset);
        expect(Get.find<HomeController>().showTopBar?.value, hiddenVisible);
        tabController.index = 0;
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        await drag(tester, const Offset(0, 200));
        expect(tester.getTopLeft(getFeed()).dy, closeTo(top, .01));
        expect(tester.state(find.byType(RcmdPage)), same(state));
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
    testWidgets(
      'disabled home setting keeps rail sections visible in ${mode.name} mode',
      (tester) async {
        await pumpHome(tester, mode, enabled: false);
        final top = tester.getTopLeft(getFeed()).dy;
        await drag(tester, const Offset(0, -240));
        expect(tester.getTopLeft(getFeed()).dy, top);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
  for (final mode in BarHideType.values) {
    for (final scale in [0.8, 1.0, 1.3]) {
      testWidgets(
        'normalized home top inset collapses with sections in ${mode.name} at scale $scale',
        (tester) async {
          await pumpHome(tester, mode, nativeTop: 12, scale: scale);
          final state = tester.state(find.byType(RcmdPage));
          final visibleTop = tester.getTopLeft(getFeed()).dy;
          expect(visibleTop, closeTo(44 + 12 / scale, .01));
          await drag(tester, const Offset(0, -240));
          expect(tester.getTopLeft(getFeed()).dy, closeTo(0, .01));
          // The feed must also remain hittable at the window's first pixel,
          // not merely be laid out there beneath a stationary clip/inset.
          final scrollable = find
              .descendant(
                of: getFeed(),
                matching: find.byType(Scrollable),
              )
              .first;
          expect(
            scrollable.hitTestable(at: const Alignment(0, -0.999)),
            findsOneWidget,
          );
          expect(tester.state(find.byType(RcmdPage)), same(state));
          await drag(tester, const Offset(0, 200));
          expect(tester.getTopLeft(getFeed()).dy, closeTo(visibleTop, .01));
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
        },
      );
    }
    testWidgets(
      'normalized top spacing remains when collapse is disabled in ${mode.name}',
      (tester) async {
        await pumpHome(tester, mode, nativeTop: 12, enabled: false);
        expect(tester.getTopLeft(getFeed()).dy, 56);
        await drag(tester, const Offset(0, -240));
        expect(tester.getTopLeft(getFeed()).dy, 56);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
  testWidgets(
    'ordinary phone still collapses its search row and keeps the section bar',
    (tester) async {
      await pumpHome(
        tester,
        BarHideType.sync,
        placement: HomeToolsPlacement.top,
      );
      final top = tester.getTopLeft(getFeed()).dy;
      expect(top, 98);
      await drag(tester, const Offset(0, -240));
      expect(tester.getTopLeft(getFeed()).dy, closeTo(46, .01));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
