import 'package:PiliPlus/plugin/pl_player/system_player.dart';
import 'package:PiliPlus/plugin/pl_player/widgets/system_player_video.dart';
import 'package:flutter/widgets.dart';
import 'package:media_kit_video/media_kit_video.dart';

/// A surface is mounted only while its current engine has a controller.
/// The player's outer container retains layout, fill and loading controls.
class PlayerVideoSurface extends StatelessWidget {
  const PlayerVideoSurface({
    super.key,
    required this.systemActive,
    required this.systemPlayer,
    required this.videoController,
    required this.fill,
    this.width,
    this.height,
    this.aspectRatio,
  });

  final bool systemActive;
  final SystemPlayer? systemPlayer;
  final VideoController? videoController;
  final Color fill;
  final int? width, height;
  final double? aspectRatio;

  @override
  Widget build(BuildContext context) {
    if (systemActive) {
      final player = systemPlayer;
      if (player == null) return const SizedBox.shrink();
      return SystemPlayerVideo(
        key: ObjectKey(player),
        player: player,
        width: width,
        height: height,
        aspectRatio: aspectRatio,
      );
    }
    final controller = videoController;
    if (controller == null) return const SizedBox.shrink();
    return SimpleVideo(
      key: ObjectKey(controller),
      controller: controller,
      fill: fill,
      aspectRatio: aspectRatio,
    );
  }
}
