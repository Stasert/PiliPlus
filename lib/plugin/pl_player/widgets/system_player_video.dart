import 'dart:async';

import 'package:PiliPlus/plugin/pl_player/system_player.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Shows the iOS system player's AVPlayerLayer. Sized to the video's aspect
/// ratio like `SimpleVideo`, so the surrounding FittedBox / zoom / flip work
/// the same as with mpv.
class SystemPlayerVideo extends StatefulWidget {
  const SystemPlayerVideo({
    super.key,
    required this.player,
    this.width,
    this.height,
    this.aspectRatio,
  });

  final SystemPlayer player;

  /// Video size known before AVPlayer reports one.
  final int? width;
  final int? height;

  /// Forced aspect ratio (video fit 4:3 / 16:9), like `SimpleVideo`.
  final double? aspectRatio;

  @override
  State<SystemPlayerVideo> createState() => _SystemPlayerVideoState();
}

class _SystemPlayerVideoState extends State<SystemPlayerVideo> {
  StreamSubscription<(int, int)>? _subscription;
  late int _width = widget.width ?? 16;
  late int _height = widget.height ?? 9;

  @override
  void initState() {
    super.initState();
    _listen();
  }

  @override
  void didUpdateWidget(SystemPlayerVideo oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.player != widget.player) {
      _subscription?.cancel();
      _listen();
    }
  }

  void _listen() {
    _subscription = widget.player.size.listen((size) {
      final (width, height) = size;
      if (width > 0 && height > 0 && (width != _width || height != _height)) {
        setState(() {
          _width = width;
          _height = height;
        });
      }
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final height = _height.toDouble();
    final width = widget.aspectRatio == null
        ? _width.toDouble()
        : height * widget.aspectRatio!;
    return SizedBox(
      width: width,
      height: height,
      // The player's gesture Listener only receives touches when something
      // below it is hit (mpv's Texture is). ColoredBox is an opaque hit target,
      // while the native view itself never takes touches.
      child: ColoredBox(
        color: Colors.black,
        child: IgnorePointer(
          child: UiKitView(
            // A new native view per player, so it attaches to the right AVPlayer.
            key: ValueKey(widget.player.id),
            viewType: SystemPlayer.viewType,
            creationParams: {'id': widget.player.id},
            creationParamsCodec: const StandardMessageCodec(),
          ),
        ),
      ),
    );
  }
}
