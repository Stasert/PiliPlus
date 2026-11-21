import 'package:PiliPlus/plugin/pl_player/system_player.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SystemPlayer.interpolate', () {
    Duration run({
      int last = 10000,
      int elapsed = 100,
      double rate = 1,
      bool advancing = true,
      int duration = 0,
    }) => SystemPlayer.interpolate(
      last: Duration(milliseconds: last),
      elapsed: Duration(milliseconds: elapsed),
      rate: rate,
      advancing: advancing,
      duration: Duration(milliseconds: duration),
    );

    test('advances by elapsed time at the playback rate', () {
      expect(run(), const Duration(milliseconds: 10100));
      expect(run(rate: 2), const Duration(milliseconds: 10200));
      expect(run(rate: 0.5), const Duration(milliseconds: 10050));
    });

    test('stays at the last position while paused or buffering', () {
      expect(run(advancing: false), const Duration(milliseconds: 10000));
      expect(
        run(advancing: false, elapsed: 60000),
        const Duration(milliseconds: 10000),
      );
    });

    test('runs ahead of the last update by at most maxInterpolation', () {
      const max = SystemPlayer.maxInterpolation;
      expect(run(elapsed: 60000), const Duration(milliseconds: 10000) + max);
      expect(
        run(elapsed: 400, rate: 2),
        const Duration(milliseconds: 10000) + max,
      );
    });

    test('never passes the duration', () {
      expect(
        run(last: 9900, elapsed: 400, duration: 10000),
        const Duration(milliseconds: 10000),
      );
      // Unknown duration: no limit.
      expect(
        run(last: 9900, elapsed: 400),
        const Duration(milliseconds: 10300),
      );
    });
  });

  group('SystemPlayer events', () {
    TestWidgetsFlutterBinding.ensureInitialized();
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    const channel = MethodChannel('piliplus/system_player');
    const events = EventChannel('piliplus/system_player/events');
    late MockStreamHandlerEventSink sink;

    final calls = <MethodCall>[];

    setUpAll(() {
      messenger
        ..setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          if (call.method == 'create') return 7;
          return null;
        })
        ..setMockStreamHandler(
          events,
          MockStreamHandler.inline(onListen: (_, s) => sink = s),
        );
    });

    tearDownAll(() {
      messenger
        ..setMockMethodCallHandler(channel, null)
        ..setMockStreamHandler(events, null);
    });

    Future<void> emit(String type, Map<String, Object> payload) async {
      sink.success({'id': 7, 'type': type, ...payload});
      await pumpEventQueue();
    }

    test('position stops advancing while buffering', () async {
      final player = await SystemPlayer.create();
      final subs = [
        player.position.listen((_) {}),
        player.playing.listen((_) {}),
        player.buffering.listen((_) {}),
        player.duration.listen((_) {}),
      ];
      await pumpEventQueue();

      await emit('duration', {'ms': 60000});
      await emit('playing', {'value': true});
      await emit('position', {'ms': 5000, 'bufferedMs': 6000});
      await Future<void>.delayed(const Duration(milliseconds: 50));
      final playing = player.currentPosition;
      expect(playing, greaterThan(const Duration(milliseconds: 5000)));
      expect(
        playing,
        lessThanOrEqualTo(
          const Duration(milliseconds: 5000) + SystemPlayer.maxInterpolation,
        ),
      );

      // Stalled: still "playing" (waiting to play), but time stands still.
      await emit('buffering', {'value': true});
      expect(player.currentPosition, const Duration(milliseconds: 5000));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(player.currentPosition, const Duration(milliseconds: 5000));

      // Resumed: counts from now, not from before the stall.
      await emit('buffering', {'value': false});
      final resumed = player.currentPosition;
      expect(
        resumed,
        lessThan(const Duration(milliseconds: 5000 + 40)),
        reason: 'the stall must not count as played time',
      );

      // Paused: stays put.
      await emit('playing', {'value': false});
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(player.currentPosition, const Duration(milliseconds: 5000));

      for (final s in subs) {
        await s.cancel();
      }
    });

    test('canPlayFastForward follows the item and resets on load', () async {
      final player = await SystemPlayer.create();
      final values = <bool>[];
      final sub = player.fastForward.listen(values.add);
      await pumpEventQueue();
      expect(player.canPlayFastForward, isFalse);

      // A download, once ready.
      await emit('fastForward', {'value': false});
      await emit('fastForward', {'value': true});
      expect(values, [false, true]);
      expect(player.canPlayFastForward, isTrue);

      // The next item is not known to play faster than 2x until it is ready.
      const source = SystemPlayerSource(
        video: SystemPlayerTrack(
          url: 'https://a/v.m4s',
          indexEnd: 1,
          bandwidth: 1,
        ),
        isHdr: false,
      );
      await player.load(source, headers: const {}, bufferSec: 16);
      expect(player.canPlayFastForward, isFalse);

      // Another session's events do not count.
      sink.success({'id': 8, 'type': 'fastForward', 'value': true});
      await pumpEventQueue();
      expect(player.canPlayFastForward, isFalse);

      await sub.cancel();
    });

    test('load passes the buffer setting', () async {
      final player = await SystemPlayer.create();
      const source = SystemPlayerSource(
        video: SystemPlayerTrack(
          url: 'https://a/v.m4s',
          indexEnd: 1,
          bandwidth: 1,
        ),
        isHdr: true,
      );
      calls.clear();
      await player.load(source, headers: const {}, bufferSec: 45.5);
      await player.load(source, headers: const {});
      final loads = calls.where((c) => c.method == 'load').toList();
      expect(loads, hasLength(2));
      expect((loads[0].arguments as Map)['bufferSec'], 45.5);
      expect((loads[1].arguments as Map).containsKey('bufferSec'), isFalse);
    });
  });

  group('SystemPlayer.probe', () {
    TestWidgetsFlutterBinding.ensureInitialized();
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    const channel = MethodChannel('piliplus/system_player');
    const video = SystemPlayerTrack(
      url: 'https://a/v.m4s',
      indexEnd: 1234,
      bandwidth: 5,
    );
    const headers = {'Referer': 'https://www.bilibili.com'};

    tearDown(() => messenger.setMockMethodCallHandler(channel, null));

    test('passes the track and headers and returns what was read', () async {
      MethodCall? probe;
      messenger.setMockMethodCallHandler(channel, (call) async {
        probe = call;
        return {
          'codecs': 'hvc1.2.4.L153.90',
          'supplementalCodecs': 'dvh1.08.06/db4h',
          'videoRange': 'HLG',
        };
      });
      final result = await SystemPlayer.probe(video, headers: headers);
      expect(probe?.method, 'probe');
      expect(probe?.arguments, {'video': video.toMap(), 'headers': headers});
      expect(result, {
        'codecs': 'hvc1.2.4.L153.90',
        'supplementalCodecs': 'dvh1.08.06/db4h',
        'videoRange': 'HLG',
      });
    });

    test('null when nothing was read or the call fails', () async {
      messenger.setMockMethodCallHandler(channel, (_) async => null);
      expect(await SystemPlayer.probe(video, headers: headers), isNull);

      messenger.setMockMethodCallHandler(
        channel,
        (_) async => throw PlatformException(code: 'failed'),
      );
      expect(await SystemPlayer.probe(video, headers: headers), isNull);

      // No native side at all (MissingPluginException).
      messenger.setMockMethodCallHandler(channel, null);
      expect(await SystemPlayer.probe(video, headers: headers), isNull);
    });
  });
}
