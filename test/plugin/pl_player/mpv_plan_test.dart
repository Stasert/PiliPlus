import 'package:PiliPlus/plugin/pl_player/models/mpv_plan.dart';
import 'package:PiliPlus/plugin/pl_player/models/tone_mapping_type.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DolbyVisionProfile.of', () {
    test('profile 5 from its Dolby Vision codec string', () {
      expect(
        DolbyVisionProfile.of({'codecs': 'dvh1.05.06', 'videoRange': 'PQ'}),
        DolbyVisionProfile.p5,
      );
      // A dvhe sample entry, and the SDR range the SPS of some profile 5
      // streams leads to.
      expect(
        DolbyVisionProfile.of({'codecs': 'dvhe.05.09', 'videoRange': 'SDR'}),
        DolbyVisionProfile.p5,
      );
    });

    test('profile 8.4 from the HLG range or the db4h brand', () {
      expect(
        DolbyVisionProfile.of({
          'codecs': 'hvc1.2.4.L153.90',
          'supplementalCodecs': 'dvh1.08.06/db4h',
          'videoRange': 'HLG',
        }),
        DolbyVisionProfile.p84,
      );
      expect(
        DolbyVisionProfile.of({
          'codecs': 'hvc1.2.4.L153.90',
          'videoRange': 'HLG',
        }),
        DolbyVisionProfile.p84,
      );
      expect(
        DolbyVisionProfile.of({
          'codecs': 'hvc1.2.4.L153.90',
          'supplementalCodecs': 'dvh1.08.06/db4h',
          'videoRange': 'SDR',
        }),
        DolbyVisionProfile.p84,
      );
    });

    test('other profiles play as they are', () {
      // Profile 8.1: PQ base layer.
      expect(
        DolbyVisionProfile.of({
          'codecs': 'hvc1.2.4.L153.90',
          'supplementalCodecs': 'dvh1.08.06/db1p',
          'videoRange': 'PQ',
        }),
        DolbyVisionProfile.other,
      );
      expect(
        DolbyVisionProfile.of({'codecs': 'dvh1.08.06', 'videoRange': 'PQ'}),
        DolbyVisionProfile.other,
      );
    });

    test("reads the system player's info as well as a probe", () {
      expect(
        DolbyVisionProfile.of({
          'videoCodecs': 'dvh1.05.06',
          'videoRange': 'PQ',
          'rate': 1.0,
        }),
        DolbyVisionProfile.p5,
      );
      expect(
        DolbyVisionProfile.of({
          'videoCodecs': 'hvc1.2.4.L153.90',
          'videoRange': 'HLG',
        }),
        DolbyVisionProfile.p84,
      );
    });

    test('unknown without codecs', () {
      expect(DolbyVisionProfile.of(null), isNull);
      expect(DolbyVisionProfile.of({}), isNull);
      // The system player before it read the stream: no codecs, but a rate.
      expect(DolbyVisionProfile.of({'rate': 1.0, 'videoRange': 'HLG'}), isNull);
    });
  });

  group('MpvPlan.extrasFor', () {
    test('profile 8.4 gets the HLG transfer and light back', () {
      expect(
        MpvPlan.extrasFor(
          hdr: true,
          profile84: true,
          toneMapping: ToneMappingType.auto,
        ),
        {'vf': 'format:gamma=hlg:light=hlg'},
      );
    });

    test('HDR gets the chosen tone mapping, auto adds nothing', () {
      expect(
        MpvPlan.extrasFor(hdr: true, toneMapping: ToneMappingType.auto),
        isEmpty,
      );
      for (final type in ToneMappingType.values.skip(1)) {
        expect(MpvPlan.extrasFor(hdr: true, toneMapping: type), {
          'tone-mapping': type.name,
        });
      }
      expect(
        MpvPlan.extrasFor(
          hdr: true,
          profile84: true,
          toneMapping: ToneMappingType.hable,
        ),
        {'vf': 'format:gamma=hlg:light=hlg', 'tone-mapping': 'hable'},
      );
    });

    test('SDR gets no tone mapping', () {
      expect(
        MpvPlan.extrasFor(hdr: false, toneMapping: ToneMappingType.mobius),
        isEmpty,
      );
    });

    test('no value has a comma (media_kit joins the options with commas)', () {
      for (final type in ToneMappingType.values) {
        final extras = MpvPlan.extrasFor(
          hdr: true,
          profile84: true,
          toneMapping: type,
        );
        for (final MapEntry(:key, :value) in extras.entries) {
          expect(key.contains(','), isFalse);
          expect(value.contains(','), isFalse);
        }
      }
    });
  });

  test('tone mapping values are mpv option values', () {
    expect(ToneMappingType.values.map((e) => e.name), [
      'auto',
      'hable',
      'mobius',
      'reinhard',
      'clip',
    ]);
    expect(ToneMappingType.auto.label, '自动（默认）');
  });
}
