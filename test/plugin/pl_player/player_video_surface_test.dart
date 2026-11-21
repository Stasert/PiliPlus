import 'dart:async';

import 'package:PiliPlus/plugin/pl_player/widgets/player_video_surface.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

class _Streams implements PlayerStream {
  _Streams(this.size);
  @override
  final Stream<(int, int)> size;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Player implements Player {
  _Player() {
    stream = _Streams(sizes.stream);
  }
  final sizes = StreamController<(int, int)>.broadcast(sync: true);
  @override
  final state = PlayerState(width: 16, height: 9);
  @override
  late final PlayerStream stream;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TextureController extends VideoController {
  _TextureController(_Player player, int texture)
    : super(player, const VideoControllerConfiguration()) {
    id.value = texture;
    rect.value = const Rect.fromLTWH(0, 0, 160, 90);
  }
  @override
  Future<void>? setSize({int? width, int? height}) => null;
}

void main() {
  late Rxn<VideoController> output;
  late RxBool systemActive;
  late List<_Player> players;
  setUp(() {
    output = Rxn<VideoController>();
    systemActive = false.obs;
    players = [];
  });
  tearDown(() async {
    for (final player in players) {
      await player.sizes.close();
    }
  });
  _TextureController texture(int id) {
    final player = _Player();
    players.add(player);
    return _TextureController(player, id);
  }

  Future<void> pump(WidgetTester tester) => tester.pumpWidget(
    MediaQuery(
      data: const MediaQueryData(),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: SizedBox(
          width: 320,
          height: 180,
          child: FittedBox(
            child: Obx(
              () => PlayerVideoSurface(
                systemActive: systemActive.value,
                systemPlayer: null,
                videoController: output.value,
                fill: const Color(0xFF000000),
                aspectRatio: 16 / 9,
              ),
            ),
          ),
        ),
      ),
    ),
  );

  testWidgets('initializing has no texture and readiness alone mounts it', (
    tester,
  ) async {
    await pump(tester);
    expect(find.byType(SimpleVideo), findsNothing);
    expect(tester.takeException(), isNull);
    output.value = texture(1);
    await tester.pump();
    expect(find.byType(SimpleVideo), findsOneWidget);
    expect(tester.widget<Texture>(find.byType(Texture)).textureId, 1);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('disposing a controller unmounts its texture and subscription', (
    tester,
  ) async {
    output.value = texture(1);
    await pump(tester);
    expect(players.single.sizes.hasListener, isTrue);
    output.value = null;
    await tester.pump();
    expect(find.byType(SimpleVideo), findsNothing);
    expect(players.single.sizes.hasListener, isFalse);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'a replacement texture gets new state and releases the old listener',
    (tester) async {
      output.value = texture(1);
      await pump(tester);
      final oldState = tester.state(find.byType(SimpleVideo));
      output.value = texture(2);
      await tester.pump();
      expect(tester.state(find.byType(SimpleVideo)), isNot(same(oldState)));
      expect(players.first.sizes.hasListener, isFalse);
      expect(players.last.sizes.hasListener, isTrue);
      expect(tester.widget<Texture>(find.byType(Texture)).textureId, 2);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'a missing system session cannot accidentally mount an idle mpv texture',
    (tester) async {
      output.value = texture(1);
      systemActive.value = true;
      await pump(tester);
      expect(find.byType(SimpleVideo), findsNothing);
      expect(players.single.sizes.hasListener, isFalse);
      systemActive.value = false;
      await tester.pump();
      expect(find.byType(SimpleVideo), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'rapid controller handoffs preserve the frame bounds and latest output',
    (tester) async {
      await pump(tester);
      final frame = tester.getRect(find.byType(FittedBox));
      for (var id = 1; id <= 12; id++) {
        output.value = texture(id);
        await tester.pump();
        expect(tester.widget<Texture>(find.byType(Texture)).textureId, id);
        if (id > 1) expect(players[id - 2].sizes.hasListener, isFalse);
        final video = tester.widget<SimpleVideo>(find.byType(SimpleVideo));
        expect(video.aspectRatio, 16 / 9);
        expect(video.fill, const Color(0xFF000000));
      }
      output.value = null;
      await tester.pump();
      expect(tester.getRect(find.byType(FittedBox)), frame);
      expect(players.every((p) => !p.sizes.hasListener), isTrue);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
