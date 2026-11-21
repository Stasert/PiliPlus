import 'package:PiliPlus/models/common/video/base_quality.dart';
import 'package:PiliPlus/models/common/video/cdn_type.dart';
import 'package:PiliPlus/models/video/play/url.dart';
import 'package:PiliPlus/plugin/pl_player/system_player.dart';
import 'package:PiliPlus/utils/ios/airplay_helper.dart';
import 'package:PiliPlus/utils/video_utils.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// As the TV API hands them out: http, with a signed query.
String _tv(Object id, String codecs) =>
    'http://upos-sz-mirrorcosov.bilivideo.com/upgcxcode/01/$id-$codecs.m4s'
    '?os=cosovbv&upsig=sig%2Fx&hdnts=exp%3D1~hmac%3Dab';

/// What AirPlay gets: the same URL over https.
String _url(Object id, String codecs) => 'https${_tv(id, codecs).substring(4)}';

/// A video in the shape of x/tv/playurl with fnval=4048.
Map<String, Object> _video(
  int id,
  String codecs, {
  int width = 1920,
  int height = 1080,
  String frameRate = '25',
}) => {
  'id': id,
  'codecs': codecs,
  'width': width,
  'height': height,
  'frame_rate': frameRate,
  'bandwidth': id * 10000,
  'base_url': _tv(id, codecs),
  'backup_url': [
    'https://upos-hz-mirrorakam.akamaized.net/upgcxcode/01/$id.m4s?hdnts=x',
  ],
  'segment_base': {'initialization': '0-1171', 'index_range': '1172-1707'},
};

Map<String, Object> _audio(int id, String codecs) => {
  'id': id,
  'codecs': codecs,
  'bandwidth': 100000,
  'base_url': _tv(id, codecs),
  'segment_base': {'initialization': '0-933', 'index_range': '934-1481'},
};

PlayUrlModel _playUrl(
  List<Map<String, Object>> videos, {
  List<Map<String, Object>>? audios,
  Map<String, Object>? flac,
}) => PlayUrlModel.fromJson({
  'quality': 64,
  'dash': {
    'duration': 100,
    'video': videos,
    'audio': ?audios,
    if (flac != null) 'flac': {'audio': flac},
  },
});

final _aac = [_audio(30280, 'mp4a.40.2'), _audio(30232, 'mp4a.40.2')];

void main() {
  setUp(() {
    VideoUtils.cdnService = CDNService.backupUrl;
    VideoUtils.disableAudioCDN = false;
  });

  group('AirPlayDash.pick', () {
    AirPlayDash? pick(
      PlayUrlModel data,
      VideoQuality quality, {
      int? mp4Quality,
      int? audioQuality,
    }) => AirPlayDash.pick(
      data,
      quality: quality.code,
      mp4Quality: mp4Quality,
      audioQuality: audioQuality,
    );

    test('picks AVC at the playing quality up to 1080P, over HEVC and AV1', () {
      final dash = pick(
        _playUrl([
          _video(80, 'hev1.1.6.L150.90'),
          _video(80, 'avc1.640032'),
          _video(80, 'av01.0.08M.08.0.110.01.01.01.0'),
          _video(64, 'hev1.1.6.L120.90', width: 1280, height: 720),
        ], audios: _aac),
        VideoQuality.high1080,
      )!;
      // https, with the signed query untouched.
      expect(dash.video.url, _url(80, 'avc1.640032'));
      expect(
        dash.video.url,
        endsWith('?os=cosovbv&upsig=sig%2Fx&hdnts=exp%3D1~hmac%3Dab'),
      );
      expect(dash.audio!.url, startsWith('https://'));
      expect(dash.video.indexEnd, 1707);
      expect(dash.video.bandwidth, 800000);
      expect(dash.frameRate, 25);
      expect(dash.quality, '1080P');
      // SDR: no second variant.
      expect(dash.fallback, isNull);
      expect(dash.fallbackFrameRate, isNull);
      expect(dash.fallbackQuality, isNull);
    });

    test('picks HEVC above 1080P, over AVC', () {
      final dash = pick(
        _playUrl([
          _video(120, 'avc1.640033', width: 3840, height: 2160),
          _video(120, 'hev1.1.6.L153.90', width: 3840, height: 2160),
        ], audios: _aac),
        VideoQuality.super4K,
      )!;
      expect(dash.video.url, _url(120, 'hev1.1.6.L153.90'));
    });

    test('picks Dolby Vision for a Dolby Vision video', () {
      final dash = pick(
        _playUrl([
          _video(126, 'dvh1.08.07', width: 3840, height: 2160),
          _video(
            120,
            'hev1.1.6.L153.90',
            width: 3840,
            height: 2160,
            frameRate: '50',
          ),
          _video(80, 'hev1.1.6.L150.90'),
        ], audios: _aac),
        VideoQuality.dolbyVision,
      )!;
      expect(dash.video.url, _url(126, 'dvh1.08.07'));
      expect(dash.quality, '杜比视界');
      // No HDR10: the best SDR goes next to it.
      expect(dash.fallback!.url, _url(120, 'hev1.1.6.L153.90'));
      expect(dash.fallback!.indexEnd, 1707);
      expect(dash.fallbackFrameRate, 50);
      // For the cast page while the receiver plays it.
      expect(dash.fallbackQuality, '4K');
    });

    test('offers HDR10 next to Dolby Vision, SDR next to HDR10', () {
      final data = _playUrl([
        _video(126, 'dvh1.08.07', width: 3840, height: 2160),
        _video(125, 'hev1.2.4.L153.90', width: 3840, height: 2160),
        _video(120, 'hev1.1.6.L153.90', width: 3840, height: 2160),
        _video(80, 'avc1.640032'),
        _video(80, 'hev1.1.6.L150.90'),
      ], audios: _aac);
      final dolby = pick(data, VideoQuality.dolbyVision)!;
      expect(dolby.fallback!.url, _url(125, 'hev1.2.4.L153.90'));
      expect(dolby.quality, '杜比视界');
      expect(dolby.fallbackQuality, 'HDR');
      expect(
        pick(
          _playUrl([
            _video(129, 'hev1.2.4.L153.90', width: 3840, height: 2160),
            _video(125, 'hev1.2.4.L153.90', width: 3840, height: 2160),
          ], audios: _aac),
          VideoQuality.hdrVivid,
        )!.fallback!.url,
        _url(125, 'hev1.2.4.L153.90'),
      );
      final hdr10 = pick(data, VideoQuality.hdr)!;
      expect(hdr10.video.url, _url(125, 'hev1.2.4.L153.90'));
      expect(hdr10.fallback!.url, _url(120, 'hev1.1.6.L153.90'));
      expect(hdr10.fallbackQuality, '4K');
      expect(pick(data, VideoQuality.super4K)!.fallback, isNull);
      // An SDR fallback up to 1080P is AVC, like the main stream.
      expect(
        pick(
          _playUrl([
            _video(125, 'hev1.2.4.L153.90', width: 3840, height: 2160),
            _video(80, 'hev1.1.6.L150.90'),
            _video(80, 'avc1.640032'),
          ], audios: _aac),
          VideoQuality.hdr,
        )!.fallback!.url,
        _url(80, 'avc1.640032'),
      );
    });

    test('offers no fallback worse than the MP4, or none at all', () {
      final dash = pick(
        _playUrl([
          _video(125, 'hev1.2.4.L153.90', width: 3840, height: 2160),
          _video(32, 'avc1.64001F', width: 852, height: 480),
        ], audios: _aac),
        VideoQuality.hdr,
        mp4Quality: 64,
      )!;
      expect(dash.video.url, _url(125, 'hev1.2.4.L153.90'));
      expect(dash.fallback, isNull);
      expect(
        pick(
          _playUrl([
            _video(125, 'hev1.2.4.L153.90', width: 3840, height: 2160),
          ], audios: _aac),
          VideoQuality.hdr,
        )!.fallback,
        isNull,
      );
    });

    test('leaves out 8K, AV1 and anything above 2160p', () {
      final data = _playUrl([
        _video(127, 'hev1.1.6.L183.90', width: 7680, height: 4320),
        _video(126, 'av01.0.13M.10', width: 3840, height: 2160),
        _video(125, 'hev1.2.4.L156.90', width: 4096, height: 2304),
        _video(120, 'hev1.1.6.L153.90', width: 3840, height: 2160),
      ], audios: _aac);
      expect(
        pick(data, VideoQuality.super8k)!.video.url,
        _url(120, 'hev1.1.6.L153.90'),
      );
    });

    test('measures portrait video by its short side', () {
      final dash = pick(
        _playUrl([
          _video(120, 'hev1.1.6.L153.90', width: 2160, height: 3840),
        ], audios: _aac),
        VideoQuality.super4K,
      )!;
      expect(dash.quality, '4K');
    });

    test('takes the closest lower quality, or the lowest there is', () {
      final data = _playUrl([
        _video(126, 'hev1.2.4.L153.90', width: 3840, height: 2160),
        _video(120, 'hev1.1.6.L153.90', width: 3840, height: 2160),
        _video(80, 'hev1.1.6.L150.90'),
      ], audios: _aac);
      expect(pick(data, VideoQuality.hdr)!.quality, '4K');
      expect(pick(data, VideoQuality.fluent360)!.quality, '1080P');
    });

    test('takes HEVC where a quality up to 1080P has no AVC', () {
      final dash = pick(
        _playUrl([
          _video(80, 'av01.0.08M.08.0.110.01.01.01.0'),
          _video(80, 'hev1.1.6.L150.90'),
          _video(64, 'avc1.640028', width: 1280, height: 720),
        ], audios: _aac),
        VideoQuality.high1080,
      )!;
      expect(dash.video.url, _url(80, 'hev1.1.6.L150.90'));
    });

    test('casts the MP4 when the DASH stream is not better', () {
      final data = _playUrl([
        _video(64, 'hev1.1.6.L120.90', width: 1280, height: 720),
      ], audios: _aac);
      expect(pick(data, VideoQuality.high1080, mp4Quality: 80), isNull);
      // A 720P DASH stream for a 720P MP4 still gets better audio.
      expect(pick(data, VideoQuality.high1080, mp4Quality: 64), isNotNull);
      expect(pick(_playUrl([]), VideoQuality.high1080), isNull);
      expect(
        AirPlayDash.pick(
          PlayUrlModel.fromJson({'quality': 64}),
          quality: VideoQuality.high1080.code,
        ),
        isNull,
      );
      expect(
        pick(
          _playUrl([
            _video(80, 'av01.0.08M.08.0.110.01.01.01.0'),
          ], audios: _aac),
          VideoQuality.high1080,
        ),
        isNull,
      );
    });

    test('takes AAC or E-AC-3 audio closest to the playing audio', () {
      final data = _playUrl(
        [_video(80, 'hev1.1.6.L150.90')],
        audios: [
          _audio(30250, 'ec-3'),
          _audio(30280, 'mp4a.40.2'),
          _audio(30232, 'mp4a.40.2'),
          _audio(30216, 'mp4a.40.5'),
        ],
        flac: _audio(30251, 'fLaC'),
      );
      String? audio(int? quality) => pick(
        data,
        VideoQuality.high1080,
        audioQuality: quality,
      )!.audio?.url;
      expect(audio(AudioQuality.k132.code), _url(30232, 'mp4a.40.2'));
      expect(audio(AudioQuality.dolby_30250.code), _url(30250, 'ec-3'));
      // No FLAC: Dolby is the closest below Hi-Res.
      expect(audio(AudioQuality.hiRes.code), _url(30250, 'ec-3'));
      expect(audio(null), _url(30280, 'mp4a.40.2'));
      expect(
        pick(data, VideoQuality.high1080)!.audio!.indexEnd,
        1481,
      );
    });

    test('casts the MP4 when no audio fits, but not for silent video', () {
      expect(
        pick(
          _playUrl(
            [_video(80, 'hev1.1.6.L150.90')],
            flac: _audio(30251, 'fLaC'),
          ),
          VideoQuality.high1080,
        ),
        isNull,
      );
      final silent = pick(
        _playUrl([_video(80, 'hev1.1.6.L150.90')]),
        VideoQuality.high1080,
      )!;
      expect(silent.audio, isNull);
    });

    test('labels', () {
      expect(AirPlayDash.label(126), '杜比视界');
      expect(AirPlayDash.label(125), 'HDR');
      expect(AirPlayDash.label(120), '4K');
      expect(AirPlayDash.label(112), '1080P+');
      expect(AirPlayDash.label(64), '720P');
    });
  });

  group('AirPlayHelper', () {
    TestWidgetsFlutterBinding.ensureInitialized();
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    const channel = MethodChannel('piliplus/airplay');
    final calls = <MethodCall>[];
    // What the native side answers to "start": the session to send the DASH
    // stream for, or null when it casts the MP4 without waiting.
    int? session;

    setUp(() {
      calls.clear();
      session = 7;
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return call.method == 'start' ? session : null;
      });
    });

    tearDown(() => messenger.setMockMethodCallHandler(channel, null));

    const stream = AirPlayDash(
      video: SystemPlayerTrack(
        url: 'https://example.com/v.m4s',
        indexEnd: 1707,
        bandwidth: 800000,
      ),
      audio: SystemPlayerTrack(
        url: 'https://example.com/a.m4s',
        indexEnd: 1481,
        bandwidth: 100000,
      ),
      frameRate: 25,
      fallback: SystemPlayerTrack(
        url: 'https://example.com/f.m4s',
        indexEnd: 1600,
        bandwidth: 500000,
      ),
      fallbackFrameRate: 50,
      quality: '杜比视界',
      fallbackQuality: 'HDR',
    );

    test(
      'opens the device list first, then sends a DASH stream fetched for it',
      () async {
        var fetched = 0;
        await AirPlayHelper.start(
          url: 'https://example.com/v.mp4',
          title: 'title',
          start: const Duration(seconds: 3),
          quality: '720P',
          dash: () async {
            fetched++;
            // The device list is already open.
            expect(calls.map((e) => e.method), ['start']);
            return stream;
          },
        );
        expect(fetched, 1);
        expect(calls.map((e) => e.method), ['start', 'dash']);
        expect(calls.first.arguments, {
          'url': 'https://example.com/v.mp4',
          'title': 'title',
          'startMs': 3000,
          'quality': '720P',
          'withDash': true,
        });
        expect(calls.last.arguments, {
          'session': 7,
          'dash': {
            'video': {
              'url': 'https://example.com/v.m4s',
              'indexEnd': 1707,
              'bandwidth': 800000,
            },
            'audio': {
              'url': 'https://example.com/a.m4s',
              'indexEnd': 1481,
              'bandwidth': 100000,
            },
            'frameRate': 25.0,
            'fallback': {
              'url': 'https://example.com/f.m4s',
              'indexEnd': 1600,
              'bandwidth': 500000,
            },
            'fallbackFrameRate': 50.0,
            'quality': '杜比视界',
            'fallbackQuality': 'HDR',
          },
        });
      },
    );

    test('fetches the DASH stream anew for every cast', () async {
      var fetched = 0;
      Future<AirPlayDash?> load() async {
        fetched++;
        return stream;
      }

      await AirPlayHelper.start(url: 'https://example.com/v.mp4', dash: load);
      session = 8;
      await AirPlayHelper.start(url: 'https://example.com/v.mp4', dash: load);
      expect(fetched, 2);
      expect(
        calls
            .where((e) => e.method == 'dash')
            .map((e) => e.arguments['session']),
        [7, 8],
      );
    });

    test('casts the MP4 at once when there is no DASH stream', () async {
      await AirPlayHelper.start(
        url: 'https://example.com/v.mp4',
        dash: () async => null,
      );
      await AirPlayHelper.start(
        url: 'https://example.com/v.mp4',
        dash: () => Future.error(Exception('network')),
      );
      final sent = calls.where((e) => e.method == 'dash').toList();
      expect(sent.map((e) => e.arguments), [
        {'session': 7},
        {'session': 7},
      ]);
    });

    test('fetches nothing when the native side casts the MP4', () async {
      session = null; // e.g. iOS 14
      var fetched = 0;
      await AirPlayHelper.start(
        url: 'https://example.com/v.mp4',
        dash: () async {
          fetched++;
          return stream;
        },
      );
      expect(fetched, 0);
      expect(calls.map((e) => e.method), ['start']);
    });

    test('start without a DASH stream sends the MP4 only', () async {
      await AirPlayHelper.start(url: 'https://example.com/v.mp4');
      expect(calls.single.arguments, {
        'url': 'https://example.com/v.mp4',
        'startMs': 0,
        'withDash': false,
      });
      // Without a fallback its keys are left out.
      expect(
        const AirPlayDash(
          video: SystemPlayerTrack(
            url: 'https://example.com/v.m4s',
            indexEnd: 1707,
            bandwidth: 800000,
          ),
          quality: '1080P',
        ).toMap().keys,
        ['video', 'quality'],
      );
    });

    test('state carries the quality being cast', () {
      final state = AirPlayState.fromMap(const {
        'active': true,
        'connected': true,
        'quality': '杜比视界',
      });
      expect(state.quality, '杜比视界');
      expect(AirPlayState.fromMap(const {'active': true}).quality, isNull);
    });
  });
}
