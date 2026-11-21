import 'package:PiliPlus/models/common/super_resolution_type.dart';
import 'package:PiliPlus/pages/video/controller.dart';
import 'package:PiliPlus/plugin/pl_player/controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('sdrNeedsMpv', () {
    bool run({
      double speed = 1,
      double maxSpeed = PlPlayerController.systemPlayerMaxSpeed,
      SuperResolutionType superResolution = SuperResolutionType.disable,
    }) => VideoDetailController.sdrNeedsMpv(
      speed: speed,
      maxSpeed: maxSpeed,
      superResolution: superResolution,
    );

    test('SDR stays on the system player up to its speed', () {
      expect(run(), isFalse);
      expect(run(speed: 0.5), isFalse);
      expect(run(speed: 2), isFalse);
      expect(
        run(
          speed: 3,
          maxSpeed: PlPlayerController.systemPlayerFastForwardMaxSpeed,
        ),
        isFalse,
      );
    });

    test('SDR faster than the system player plays on mpv', () {
      expect(run(speed: 2.25), isTrue);
      expect(run(speed: 3), isTrue);
      expect(
        run(
          speed: 4,
          maxSpeed: PlPlayerController.systemPlayerFastForwardMaxSpeed,
        ),
        isTrue,
      );
    });

    test('SDR with super resolution plays on mpv', () {
      expect(run(superResolution: SuperResolutionType.efficiency), isTrue);
      expect(run(superResolution: SuperResolutionType.quality), isTrue);
    });
  });

  group('mpvSuperResolution', () {
    SuperResolutionType run({
      SuperResolutionType? player,
      int? pgcType,
      SuperResolutionType setting = SuperResolutionType.quality,
    }) => VideoDetailController.mpvSuperResolution(
      player: player,
      pgcType: pgcType,
      setting: setting,
    );

    test('before mpv exists, the setting applies to anime only', () {
      for (final type in [1, 4]) {
        expect(run(pgcType: type), SuperResolutionType.quality);
        expect(
          run(pgcType: type, setting: SuperResolutionType.disable),
          SuperResolutionType.disable,
        );
      }
      for (final type in [null, 2, 3, 5]) {
        expect(run(pgcType: type), SuperResolutionType.disable);
      }
    });

    test('once mpv exists, it keeps its own', () {
      // An anime opened first set it up; a video opened from there gets it.
      expect(
        run(player: SuperResolutionType.efficiency),
        SuperResolutionType.efficiency,
      );
      // A video opened first left it off; an anime opened from there too.
      for (final type in [1, 4]) {
        expect(
          run(player: SuperResolutionType.disable, pgcType: type),
          SuperResolutionType.disable,
        );
      }
    });
  });
}
