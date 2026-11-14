import 'dart:ui' show clampDouble;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:media_kit_video/media_kit_video.dart'
    show SubtitleViewConfiguration;

/// Subtitles while the iOS system player plays. Same look and drag-to-move
/// behaviour as media_kit's `SubtitleView`, which only reads mpv's subtitles.
class SystemSubtitleView extends StatefulWidget {
  const SystemSubtitleView({
    super.key,
    required this.text,
    required this.configuration,
    this.enableDragSubtitle = false,
    this.onUpdatePadding,
  });

  final ValueListenable<String> text;
  final SubtitleViewConfiguration configuration;
  final bool enableDragSubtitle;
  final ValueChanged<EdgeInsets>? onUpdatePadding;

  @override
  State<SystemSubtitleView> createState() => _SystemSubtitleViewState();
}

class _SystemSubtitleViewState extends State<SystemSubtitleView> {
  late EdgeInsets _padding = widget.configuration.padding;

  @override
  void didUpdateWidget(SystemSubtitleView oldWidget) {
    super.didUpdateWidget(oldWidget);
    _padding = widget.configuration.padding;
  }

  @override
  Widget build(BuildContext context) {
    final config = widget.configuration;
    Widget text(String value, TextStyle style) => Text(
      value,
      style: style,
      textAlign: config.textAlign,
      textScaler: TextScaler.noScaling,
    );

    final subtitle = ValueListenableBuilder<String>(
      valueListenable: widget.text,
      builder: (context, value, _) {
        if (value.isEmpty) return const SizedBox.shrink();
        if (config.strokeStyle case final stroke?) {
          return Stack(
            clipBehavior: Clip.none,
            children: [text(value, stroke), text(value, config.style)],
          );
        }
        return text(value, config.style);
      },
    );

    return AnimatedContainer(
      margin: _padding,
      duration: const Duration(milliseconds: 100),
      alignment: Alignment.bottomCenter,
      child: widget.enableDragSubtitle
          ? GestureDetector(
              behavior: HitTestBehavior.opaque,
              onVerticalDragUpdate: (details) => setState(() {
                _padding = _padding.copyWith(
                  bottom: clampDouble(
                    _padding.bottom - details.delta.dy,
                    0,
                    200,
                  ),
                );
              }),
              onVerticalDragEnd: (_) => widget.onUpdatePadding?.call(_padding),
              child: subtitle,
            )
          : subtitle,
    );
  }
}
