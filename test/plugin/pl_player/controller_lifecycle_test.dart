import 'dart:io';
import 'dart:async';

import 'package:PiliPlus/plugin/pl_player/controller.dart';
import 'package:PiliPlus/http/init.dart';
import 'package:PiliPlus/models/common/sponsor_block/skip_type.dart';
import 'package:PiliPlus/plugin/pl_player/models/data_source.dart';
import 'package:PiliPlus/plugin/pl_player/view/view.dart';
import 'package:PiliPlus/plugin/pl_player/widgets/player_video_surface.dart';
import 'package:PiliPlus/utils/storage_key.dart';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:PiliPlus/plugin/pl_player/models/data_status.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late PlPlayerController controller;
  var released = false;
  setUpAll(() async {
    directory = await Directory.systemTemp.createTemp('player-lifecycle-');
    Hive.init(directory.path);
    GStorage.setting = await Hive.openBox('setting');
    GStorage.video = await Hive.openBox('video');
    GStorage.localCache = await Hive.openBox('localCache');
    GStorage.userInfo = await Hive.openBox('userInfo');
    await GStorage.setting.putAll({
      SettingBoxKey.enableHA: false,
      SettingBoxKey.enableSponsorBlock: false,
      SettingBoxKey.pgcSkipType: SkipType.disable.index,
      SettingBoxKey.showViewPoints: false,
      SettingBoxKey.showDmChart: false,
    });
    Request();
    Request.dio.interceptors.insert(
      0,
      InterceptorsWrapper(
        onRequest: (o, h) {
          h.resolve(
            Response(requestOptions: o, data: {'code': -1}, statusCode: 200),
          );
        },
      ),
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler(
          'dev.flutter.pigeon.wakelock_plus_platform_interface.WakelockPlusApi.toggle',
          (_) async => const StandardMessageCodec().encodeMessage([null]),
        );
  });
  setUp(() {
    released = false;
    controller = PlPlayerController.getInstance();
  });
  tearDown(() async {
    if (!released) controller.dispose();
    await pumpEventQueue();
  });
  tearDownAll(() async {
    await Hive.close();
    await directory.delete(recursive: true);
  });

  test('reading completion before a player exists is safe and false', () {
    expect(controller.isCompleted, isFalse);
    controller.dataStatus.value = DataStatus.loaded;
    expect(controller.isCompleted, isFalse);
    controller.updateDuration(const Duration(minutes: 5));
    expect(controller.isCompleted, isFalse);
  });
  test(
    'double tap while unready or after disposal does not access an engine',
    () async {
      await controller.onDoubleTapCenter();
      controller.dataStatus.value = DataStatus.loaded;
      await controller.onDoubleTapCenter();
      controller.usingSystemPlayer.value = true;
      await controller.onDoubleTapCenter();
      controller.dispose();
      released = true;
      await controller.onDoubleTapCenter();
      expect(controller.isCompleted, isFalse);
    },
  );

  test('a selected system engine without a session is not complete', () {
    controller.dataStatus.value = DataStatus.loaded;
    controller.usingSystemPlayer.value = true;
    expect(controller.isCompleted, isFalse);
    controller.updateDuration(Duration.zero);
    expect(controller.isCompleted, isFalse);
  });

  test('disposing while a source plan awaits cannot publish a late error or controller', () async {
    final started = Completer<void>();
    final finish = Completer<void>();
    final load = controller.setDataSource(
      NetworkSource(
        videoSource: 'https://invalid.test/video',
        audioSource: null,
      ),
      mpvPlan: (_) async {
        started.complete();
        await finish.future;
        return null;
      },
    );
    await started.future;
    expect(controller.processing, isTrue);
    controller.dispose();
    released = true;
    finish.complete();
    await load;
    expect(controller.dataStatus.value, DataStatus.none);
    expect(controller.processing, isFalse);
    expect(controller.videoController, isNull);
    expect(controller.videoPlayerController, isNull);
    expect(controller.isCompleted, isFalse);
  });

  test('releasing one shared page does not destroy the current session', () {
    expect(PlPlayerController.getInstance(), same(controller));
    controller.dataStatus.value = DataStatus.loading;
    controller.dispose();
    expect(controller.dataStatus.value, DataStatus.loading);
  });

  test(
    'a newer load keeps ownership when the earlier source plan finishes',
    () async {
      final starts = [Completer<void>(), Completer<void>()];
      final finishes = [Completer<void>(), Completer<void>()];
      Future<void> load(int index) => controller.setDataSource(
        NetworkSource(
          videoSource: 'https://invalid.test/$index',
          audioSource: null,
        ),
        mpvPlan: (_) async {
          starts[index].complete();
          await finishes[index].future;
          return null;
        },
      );
      final first = load(0);
      await starts[0].future;
      final second = load(1);
      await starts[1].future;
      finishes[0].complete();
      await first;
      expect(controller.dataStatus.value, DataStatus.loading);
      expect(controller.processing, isTrue);
      expect(controller.videoController, isNull);
      controller.dispose();
      released = true;
      finishes[1].complete();
      await second;
      expect(controller.dataStatus.value, DataStatus.none);
      expect(controller.processing, isFalse);
      expect(controller.isCompleted, isFalse);
    },
  );

  for (final isLive in [false, true]) {
    testWidgets(
      'the actual player builds before initialization and during teardown (live=$isLive)',
      (tester) async {
        controller.isLive = isLive;
        await tester.pumpWidget(
          MaterialApp(
            home: SizedBox(
              width: 320,
              height: 180,
              child: PLVideoPlayer(
                maxWidth: 320,
                maxHeight: 180,
                plPlayerController: controller,
                headerControl: const SizedBox.shrink(),
                bottomControl: const SizedBox.shrink(),
              ),
            ),
          ),
        );
        expect(find.byType(PlayerVideoSurface), findsOneWidget);
        expect(tester.takeException(), isNull);
        controller.dispose();
        released = true;
        await tester.pump();
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        expect(tester.takeException(), isNull);
      },
    );
  }
}
