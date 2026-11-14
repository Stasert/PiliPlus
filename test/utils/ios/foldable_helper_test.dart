import 'dart:io';

import 'package:PiliPlus/utils/ios/foldable_helper.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:PiliPlus/utils/storage_key.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';

void main() {
  late Directory dir;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    dir = await Directory.systemTemp.createTemp('foldable_helper_test');
    Hive.init(dir.path);
    GStorage.setting = await Hive.openBox<dynamic>('setting');
  });

  tearDownAll(() async {
    await Hive.close();
    await dir.delete(recursive: true);
  });

  setUp(() async {
    await GStorage.setting.clear();
    IOSFoldableHelper.debugIsIPhone = true;
  });

  tearDown(() => IOSFoldableHelper.debugIsIPhone = false);

  test('uses automatic mode on a new install', () {
    expect(IOSFoldableHelper.isAuto, isTrue);
  });

  test(
    'keeps 横屏适配 on for a user who enabled it before automatic mode',
    () async {
      await GStorage.setting.put(SettingBoxKey.horizontalScreen, true);

      expect(IOSFoldableHelper.isAuto, isFalse);
      expect(Pref.horizontalScreen, isTrue);
    },
  );

  test('uses automatic mode when the old switch was off', () async {
    await GStorage.setting.put(SettingBoxKey.horizontalScreen, false);

    expect(IOSFoldableHelper.isAuto, isTrue);
  });

  test('a choice made in settings wins over the old switch', () async {
    await GStorage.setting.putAll({
      SettingBoxKey.horizontalScreen: true,
      SettingBoxKey.foldableAutoHorizontal: true,
    });

    expect(IOSFoldableHelper.isAuto, isTrue);
  });

  test('is never automatic on other devices', () {
    IOSFoldableHelper.debugIsIPhone = false;

    expect(IOSFoldableHelper.isAuto, isFalse);
  });
}
