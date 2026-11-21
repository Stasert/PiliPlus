import 'package:PiliPlus/pages/video/widgets/header_control.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Map<String, String> rows(Map<String, Object?> info) => {
    for (final (title, value) in HeaderControlState.systemPlayerInfoItems(info))
      title: value,
  };

  test('shows the declared range next to the stream format', () {
    final r = rows({
      'videoCodecs': 'hvc1.2.4.L153.90',
      'supplementalCodecs': 'dvh1.08.06/db4h',
      'videoRange': 'HLG',
      'formatSubtype': 'hvc1',
      'transferFunction': 'ITU_R_2100_HLG',
      'colorPrimaries': 'ITU_R_2020',
      'yCbCrMatrix': 'ITU_R_2020',
      'bitsPerComponent': 10,
      'masteringDisplay': true,
      'contentLightLevel': false,
      'dolbyVisionConfig': 'dvvC',
      'containsHDRVideo': true,
      'averageVideoBitrate': 12500000.0,
      'stalls': 2,
      'startupTime': 0.534,
      'eligibleForHDR': true,
      'edrHeadroom': 1.0,
      'potentialEdrHeadroom': 8.0,
    });
    expect(r['VideoRange (declared)'], 'HLG');
    expect(r.containsKey('VideoRange'), isFalse);
    expect(r['DolbyVision'], 'dvh1.08.06/db4h');
    expect(r['StreamFormat'], 'hvc1');
    expect(r['TransferFunction'], 'ITU_R_2100_HLG');
    expect(r['ColorPrimaries'], 'ITU_R_2020');
    expect(r['YCbCrMatrix'], 'ITU_R_2020');
    expect(r['BitsPerComponent'], '10');
    expect(r['HDRMetadata'], 'MasteringDisplayColorVolume');
    expect(r['DolbyVisionConfig'], 'dvvC');
    expect(r['ContainsHDRVideo'], 'true');
    expect(r['AverageVideoBitrate'], '12.50 Mbps');
    expect(r['Stalls'], '2');
    expect(r['StartupTime'], '0.53 s');
    expect(r['EligibleForHDR'], 'true');
    expect(r['EDRHeadroom'], '1.00 (potential 8.00)');
  });

  test('says none when the stream has no HDR or Dolby Vision boxes', () {
    final r = rows({
      'masteringDisplay': false,
      'contentLightLevel': false,
      'dolbyVisionConfig': '',
      'eligibleForHDR': false,
    });
    expect(r['HDRMetadata'], 'none');
    expect(r['DolbyVisionConfig'], 'none');
    // Shown either way now, not only when HDR is not supported.
    expect(r['EligibleForHDR'], 'false');
    expect(r.containsKey('HDR'), isFalse);
  });

  test('leaves out what could not be read', () {
    final r = rows({'stalls': -1, 'startupTime': -1.0});
    expect(r['VideoRange (declared)'], 'SDR');
    expect(r['StreamFormat'], '-');
    expect(r['BitsPerComponent'], '-');
    expect(r['HDRMetadata'], '-');
    expect(r['DolbyVisionConfig'], '-');
    expect(r['ContainsHDRVideo'], '-');
    expect(r['Stalls'], '-');
    expect(r['StartupTime'], '-');
    expect(r['AverageVideoBitrate'], '-');
    expect(r['EligibleForHDR'], '-');
    // Only on iOS 16+.
    expect(r.containsKey('EDRHeadroom'), isFalse);
  });
}
