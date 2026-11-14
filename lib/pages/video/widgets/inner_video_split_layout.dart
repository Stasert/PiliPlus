import 'package:PiliPlus/models/common/inner_video_detail_layout.dart';
import 'package:flutter/widgets.dart';

bool usesInnerVideoSplit({
  required bool isIPhone,
  required Size windowSize,
  required InnerVideoDetailLayout layout,
}) =>
    isIPhone &&
    windowSize.shortestSide >= 600 &&
    windowSize.width >= 820 &&
    layout == InnerVideoDetailLayout.split;

typedef VideoPaneBuilder = Widget Function(
  BuildContext context,
  double width,
  double height,
);

/// One full-height player on the left, with all scrolling details on the right.
/// The row structure stays the same in fullscreen to retain player/tab state.
class InnerVideoSplitLayout extends StatelessWidget {
  const InnerVideoSplitLayout({
    super.key,
    required this.fullScreen,
    required this.playerBuilder,
    required this.detailsBuilder,
  });

  final bool fullScreen;
  final VideoPaneBuilder playerBuilder;
  final VideoPaneBuilder detailsBuilder;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final width = constraints.maxWidth;
      final height = constraints.maxHeight;
      // Narrow inner displays need enough room for metadata and action buttons.
      final detailsWidth = (width * 0.37).clamp(280.0, 425.0).clamp(0.0, width);
      final playerWidth = fullScreen ? width : width - detailsWidth;
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: playerWidth,
            height: height,
            child: playerBuilder(context, playerWidth, height),
          ),
          Offstage(
            offstage: fullScreen,
            child: SizedBox(
              width: detailsWidth,
              height: height,
              child: detailsBuilder(context, detailsWidth, height),
            ),
          ),
        ],
      );
    },
  );
}
