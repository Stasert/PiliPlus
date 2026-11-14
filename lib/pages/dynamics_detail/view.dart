import 'package:PiliPlus/common/widgets/appbar/rail_floating_app_bar.dart';
import 'package:PiliPlus/common/widgets/native_comment_button.dart';
import 'package:PiliPlus/common/widgets/rail_page_view.dart';
import 'package:PiliPlus/utils/ios/native_page_actions.dart';
import 'package:PiliPlus/utils/ios/native_tab_bar.dart';

import 'dart:async';
import 'dart:math';

import 'package:PiliPlus/common/style.dart';
import 'package:PiliPlus/common/widgets/custom_icon.dart';
import 'package:PiliPlus/common/widgets/flutter/dyn_tab_bar.dart';
import 'package:PiliPlus/common/widgets/flutter/refresh_indicator.dart';
import 'package:PiliPlus/common/widgets/flutter/text_field/controller.dart';
import 'package:PiliPlus/common/widgets/gesture/horizontal_drag_gesture_recognizer.dart';
import 'package:PiliPlus/common/widgets/pair.dart';
import 'package:PiliPlus/common/widgets/refresh_indicator.dart';
import 'package:PiliPlus/common/widgets/scaffold/mini_scaffold.dart';
import 'package:PiliPlus/common/widgets/scaffold/simple_scaffold.dart';
import 'package:PiliPlus/common/widgets/scroll_behavior.dart'
    show NoOverscrollIndicator;
import 'package:PiliPlus/common/widgets/scroll_physics.dart'
    show ReloadScrollPhysics, platformAlwaysClampingPhysics;
import 'package:PiliPlus/common/widgets/sliver/sliver_floating_header.dart';
import 'package:PiliPlus/common/widgets/sliver/sliver_to_box_adapter.dart';
import 'package:PiliPlus/common/widgets/tap_region_surface.dart';
import 'package:PiliPlus/http/constants.dart';
import 'package:PiliPlus/http/dynamics.dart';
import 'package:PiliPlus/http/loading_state.dart';
import 'package:PiliPlus/models/common/reply/reply_option_type.dart';
import 'package:PiliPlus/models/dynamics/result.dart';
import 'package:PiliPlus/pages/common/dyn/common_dyn_page.dart';
import 'package:PiliPlus/pages/common/dyn/like_list/controller.dart';
import 'package:PiliPlus/pages/common/dyn/like_list/view.dart';
import 'package:PiliPlus/pages/common/dyn/repost_list/controller.dart';
import 'package:PiliPlus/pages/common/dyn/repost_list/view.dart';
import 'package:PiliPlus/pages/dynamics/widgets/author_panel.dart';
import 'package:PiliPlus/pages/dynamics/widgets/dynamic_panel.dart';
import 'package:PiliPlus/pages/dynamics_create/view.dart';
import 'package:PiliPlus/pages/dynamics_detail/controller.dart';
import 'package:PiliPlus/pages/dynamics_repost/view.dart';
import 'package:PiliPlus/utils/extension/get_ext.dart';
import 'package:PiliPlus/utils/grid.dart';
import 'package:PiliPlus/utils/num_utils.dart';
import 'package:PiliPlus/utils/reply_scheme_helper.dart';
import 'package:PiliPlus/utils/request_utils.dart';
import 'package:PiliPlus/utils/share_utils.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';

class DynamicDetailPage extends StatefulWidget {
  const DynamicDetailPage({super.key});

  @override
  State<DynamicDetailPage> createState() => _DynamicDetailPageState();
}

class _DynamicDetailPageState extends CommonDynPageMultiState<DynamicDetailPage>
    with DynReplyLocateStateMixin {
  @override
  late final DynamicDetailController controller;
  late final DynRepostController _repostController;
  late final DynLikeController _likeController;

  late final RxBool _isRefreshing = false.obs;

  void _stopRefresh() {
    if (!mounted) return;
    _isRefreshing.value = false;
  }

  void _onRefresh(Future<void> future) {
    _isRefreshing.value = true;
    future.whenComplete(_stopRefresh);
  }

  @override
  dynamic get arguments => {'item': controller.dynItem};

  @override
  void initState() {
    super.initState();
    final Map args = Get.arguments;
    final item = args['item'] as DynamicItemModel;
    final id = item.idStr.toString();
    if (args['viewComment'] == true || args.containsKey(rootRpIdKey)) {
      WidgetsBinding.instance.addPostFrameCallback(_jumpToComment);
    }
    final stat = item.modules.moduleStat;
    controller = Get.putOrFind<DynamicDetailController>(
      () => DynamicDetailController(count: stat?.comment?.count ?? -1),
      tag: id,
    );
    _repostController = Get.putOrFind<DynRepostController>(
      () => DynRepostController(id, count: stat?.forward?.count ?? -1),
      tag: id,
    );
    _likeController = Get.putOrFind<DynLikeController>(
      () => DynLikeController(id, count: stat?.like?.count ?? -1),
      tag: id,
    );
    _nativeWorkers.addAll([
      ever(controller.count, (_) => _scheduleNativeActions()),
      ever(controller.replyMetadataReady, (_) => _scheduleNativeActions()),
    ]);
  }

  ScrollableState? _scrollable;
  ModalRoute<dynamic>? _nativeRoute;
  final _pageScroll = ScrollController();
  final _horizontalReplyScroll = ScrollController();
  final _nestedScrollKey = GlobalKey<NestedScrollViewState>();
  final List<Worker> _nativeWorkers = [];
  bool _nativeUpdateScheduled = false;
  bool _canScrollToTop = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route != _nativeRoute) {
      if (_nativeRoute case final previous?) {
        IOSNativeTabBar.removePageActions(previous);
      }
      _nativeRoute = route;
    }
    _scheduleNativeActions();
  }

  void _scheduleNativeActions() {
    if (_nativeUpdateScheduled) return;
    _nativeUpdateScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _nativeUpdateScheduled = false;
      if (mounted && _nativeRoute != null) _publishNativeActions();
    });
  }

  String? _countLabel(int? value) =>
      value == null || value < 0 ? null : NumUtils.compactCount(value);

  void _publishNativeActions() {
    final stat = controller.dynItem.modules.moduleStat;
    IOSNativeTabBar.setPageActions(
      route: _nativeRoute!,
      actions: [
        if (_canScrollToTop)
          const NativePageAction(id: 'scrollToTop', title: '回到顶部'),
        if (controller.showDynActionBar) ...[
          NativePageAction(
            id: 'like',
            title: '点赞',
            count: _countLabel(stat?.like?.count),
            selected: stat?.like?.status ?? false,
            selectedColor: Theme.of(context).colorScheme.primary.toARGB32(),
          ),
          NativePageAction(
            id: 'comment',
            title: '查看评论',
            count: _countLabel(
              controller.count.value >= 0
                  ? controller.count.value
                  : stat?.comment?.count,
            ),
          ),
          NativePageAction(
            id: 'repost',
            title: '转发',
            enabled: controller.replyMetadataReady.value,
            count: _countLabel(stat?.forward?.count),
          ),
          const NativePageAction(id: 'share', title: '分享'),
        ],
      ],
      onAction: _onNativeAction,
    );
  }

  Future<void> _onNativeAction(String id) async {
    if (!mounted || !(_nativeRoute?.isCurrent ?? false)) return;
    switch (id) {
      case 'scrollToTop':
        await _scrollToTop();
      case 'like':
        await RequestUtils.onLikeDynamic(
          controller.dynItem,
          controller.dynItem.modules.moduleStat?.like?.status ?? false,
          () {
            if (mounted) setState(() {});
          },
        );
      case 'comment':
        _jumpToComment();
      case 'repost':
        await _showRepostPanel();
      case 'share':
        await ShareUtils.shareText(
          '${HttpString.opusBaseUrl}/${controller.dynItem.idStr}',
        );
    }
    if (mounted) _scheduleNativeActions();
  }

  Future<void> _showRepostPanel() async {
    final item = controller.dynItem;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => RepostPanel(
        item: item,
        onSuccess: () {
          final forward = item.modules.moduleStat?.forward;
          if (forward != null) forward.count = (forward.count ?? 0) + 1;
          if (mounted) setState(() {});
        },
        replyInfo: (oid: controller.oid, replyType: controller.replyType),
        mentionItem: item.modules.moduleAuthor?.mentionItem,
      ),
    );
  }

  bool _onPageScroll(ScrollNotification notification) {
    final positions = [
      ..._pageScroll.positions,
      ...?_nestedScrollKey.currentState?.innerController.positions,
      ..._horizontalReplyScroll.positions,
    ];
    final canScroll =
        positions.any((position) => position.pixels > 40) ||
        (notification.metrics.axis == Axis.vertical &&
            notification.metrics.pixels > 40);
    if (canScroll != _canScrollToTop) {
      _canScrollToTop = canScroll;
      _scheduleNativeActions();
    }
    return false;
  }

  Future<void> _scrollToTop() async {
    if (isPortrait) {
      // NestedScrollView's outer position coordinates the inner positions too.
      if (_pageScroll.hasClients) {
        await _pageScroll.animateTo(
          0,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    } else {
      final positions = <ScrollPosition>{
        ..._pageScroll.positions,
        ..._horizontalReplyScroll.positions,
        ...?PrimaryScrollController.maybeOf(context)?.positions,
      };
      await Future.wait(
        positions.map(
          (position) => position.animateTo(
            position.minScrollExtent,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          ),
        ),
      );
    }
    if (mounted) {
      _canScrollToTop = false;
      _scheduleNativeActions();
    }
  }

  @override
  void dispose() {
    if (_nativeRoute case final route?) {
      IOSNativeTabBar.removePageActions(route);
    }
    for (final worker in _nativeWorkers) {
      worker.dispose();
    }
    _pageScroll.dispose();
    _horizontalReplyScroll.dispose();
    _scrollable = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _scheduleNativeActions();
    final overlayHeader =
        isPortrait && (RailViewportScope.of(context)?.normalizedTop ?? false);
    return NotificationListener<ScrollNotification>(
      onNotification: _onPageScroll,
      child: SelectionTapRegionSurface(
        /// apply `lib/scripts/scrollable.patch`
        isScrolling: () => _scrollable?.shouldIgnorePointer ?? false,
        child: SimpleScaffold(
          overlayAppBar: overlayHeader,
          appBar: Obx(
            () => RailFloatingAppBar(
              overlay: overlayHeader,
              visible: controller.showTitle.value,
              child: _buildAppBar(),
            ),
          ),
          body: Padding(
            padding: EdgeInsets.only(left: padding.left, right: padding.right),
            child: _buildBody(),
          ),
          fab: CommentFabTransition(
            position: fabAnimation,
            child:
                IOSNativeTabBar.enabled && IOSNativeTabBar.rightRailDevice.value
                ? fabButton
                : _buildBottom(),
          ),
        ),
      ),
    );
  }

  void _onEdit() {
    final item = controller.dynItem;
    List<RichTextItem>? items;
    final moduleDynamic = item.modules.moduleDynamic;
    final desc = moduleDynamic?.desc;
    final opus = moduleDynamic?.major?.opus;

    Pair<int, String>? topic;
    if (moduleDynamic?.topic case final t?) {
      try {
        topic = Pair(first: t.id!, second: t.name!);
      } catch (_) {
        if (kDebugMode) rethrow;
      }
    }

    final richTextNodes = desc?.richTextNodes ?? opus?.summary?.richTextNodes;
    if (richTextNodes != null && richTextNodes.isNotEmpty) {
      items = <RichTextItem>[];
      final buffer = StringBuffer();
      try {
        for (final e in richTextNodes) {
          if (e.type == 'RICH_TEXT_NODE_TYPE_EMOJI') {
            items.add(
              RichTextItem(
                text: Style.placeHolder,
                rawText: e.origText,
                type: .emoji,
                range: TextRange(
                  start: buffer.length,
                  end: buffer.length + Style.placeHolder.length,
                ),
                emote: Emote(url: e.emoji!.url!, width: 22),
              ),
            );
            buffer.write(Style.placeHolder);
            continue;
          }
          final range = TextRange(
            start: buffer.length,
            end: buffer.length + e.origText!.length,
          );
          final item = switch (e.type) {
            'RICH_TEXT_NODE_TYPE_AT' => RichTextItem(
              text: e.origText!,
              type: .at,
              range: range,
              id: e.rid,
            ),
            'RICH_TEXT_NODE_TYPE_BV' ||
            'RICH_TEXT_NODE_TYPE_TOPIC' ||
            'RICH_TEXT_NODE_TYPE_LOTTERY' ||
            'RICH_TEXT_NODE_TYPE_VIEW_PICTURE' => RichTextItem(
              text: e.origText!,
              type: .common,
              range: range,
              id: e.rid,
            ),
            'RICH_TEXT_NODE_TYPE_VOTE' => RichTextItem(
              text: e.origText!,
              type: .vote,
              range: range,
              id: e.rid,
            ),
            _ => RichTextItem(text: e.origText!, range: range),
          };
          items.add(item);
          buffer.write(e.origText!);
        }

        bool isValid = true;
        int cursor = 0;
        for (final e in items) {
          final range = e.range;
          if (range.start == cursor) {
            cursor = range.end;
          } else {
            isValid = false;
            break;
          }
        }
        assert(isValid);
      } catch (e) {
        if (kDebugMode) rethrow;
      }
    } else {
      final text = desc?.text ?? opus?.summary?.text;
      if (text != null && text.isNotEmpty) {
        items = [RichTextItem.fromStart(text)];
      }
    }
    ReplyOptionType? replyOption;
    if (controller.loadingState.value case Error(:final code)) {
      if (code == 12061 || code == 12002) {
        replyOption = .close;
      }
    }
    CreateDynPanel.onCreateDyn(
      context,
      title: opus?.title,
      items: items,
      pics: opus?.pics,
      topic: topic,
      replyOption: replyOption ?? .allow,
      isPrivate: item.modules.moduleAuthor?.badgeText != null,
      editConfig: (dynId: item.idStr, repostDynId: item.orig?.idStr),
      onSuccess: () {
        Timer(const Duration(milliseconds: 500), () async {
          if (!mounted) return;
          final res = await DynamicsHttp.dynamicDetail(id: item.idStr);
          if (res case Success(:final response)) {
            if (mounted) {
              controller.dynItem = response;
              setState(() {});
            }
          }
        });
      },
    );
  }

  PreferredSizeWidget _buildAppBar() => AppBar(
    automaticallyImplyLeading: !IOSNativeTabBar.hasNativeBack(context),
    title: Padding(
      padding: const EdgeInsets.only(right: 12),
      child: Obx(() {
        final showTitle = controller.showTitle.value;
        return AnimatedOpacity(
          opacity: showTitle ? 1 : 0,
          duration: const Duration(milliseconds: 300),
          child: IgnorePointer(
            ignoring: !showTitle,
            child: AuthorPanel(
              item: controller.dynItem,
              isDetail: true,
              onSetPubSetting: controller.onSetPubSetting,
              onEdit: _onEdit,
              onSetReplySubject: controller.onSetReplySubject,
            ),
          ),
        );
      }),
    ),
    actions: isPortrait
        ? null
        : [ratioWidget(maxWidth), const SizedBox(width: 16)],
  );

  Widget _buildTabBar() {
    return SizedBox(
      height: 40,
      child: DynTabBar(
        padding: .zero,
        // isScrollable: true,
        indicatorSize: .tab,
        tabAlignment: .start,
        controller: tabController,
        labelPadding: const .symmetric(horizontal: 12),
        dividerColor: theme.colorScheme.outline.withValues(alpha: 0.1),
        onTap: (value) {
          if (!tabController.indexIsChanging) {
            final positions = PrimaryScrollController.of(context).positions;
            if (positions.length == 1) {
              final postion = positions.single;
              if (postion.pixels >= postion.maxScrollExtent) {
                postion.jumpTo(postion.pixels);
              }
              switch (value) {
                case 0:
                  _onRefresh(_repostController.onRefresh());
                case 1:
                  _onRefresh(controller.onRefresh());
                case 2:
                  _onRefresh(_likeController.onRefresh());
              }
            } else if (positions.length > 1) {
              positions.elementAt(1).jumpTo(0);
            }
          }
        },
        tabs: DynType.values
            .map(
              (e) => Tab(
                child: Obx(() {
                  final count = switch (e) {
                    .repost => _repostController.count.value,
                    .reply => controller.count.value,
                    .like => _likeController.count.value,
                  };
                  return Text(
                    '${e.label}${count < 0 ? '' : ' ${NumUtils.numFormat(count)}'}',
                  );
                }),
              ),
            )
            .toList(),
      ),
    );
  }

  Widget _buildTabBody([bool isPortrait = true]) {
    Widget reply = CustomScrollView(
      controller: isPortrait ? null : _horizontalReplyScroll,
      primary: isPortrait,
      key: const PageStorageKey(DynType.reply),
      physics: ReloadScrollPhysics(
        controller: controller,
        parent: isPortrait ? platformAlwaysClampingPhysics : null,
      ),
      slivers: [
        buildReplyHeader(isPortrait),
        Obx(() => replyList(controller.loadingState.value)),
      ],
    );
    if (!isPortrait) {
      reply = refreshIndicator(onRefresh: controller.onRefresh, child: reply);
    }

    final child = RailTabBarView(
      controller: tabController,
      hitTestBehavior: .translucent,
      physics: const NeverScrollableScrollPhysics(),
      horizontalDragGestureRecognizer:
          CustomHorizontalDragGestureRecognizer.new,
      children: DynType.values
          .map(
            (e) => switch (e) {
              .repost => DynRepostPage(
                isPortrait: isPortrait,
                id: controller.dynItem.idStr,
                controller: _repostController,
              ),
              .reply => reply,
              .like => DynLikePage(
                isPortrait: isPortrait,
                id: controller.dynItem.idStr,
                controller: _likeController,
              ),
            },
          )
          .toList(),
    );
    if (isPortrait) {
      return Stack(
        clipBehavior: .none,
        children: [
          child,
          Positioned(
            left: 0,
            right: 0,
            top: displacement,
            child: RefreshIndicator_(isRefreshing: _isRefreshing),
          ),
        ],
      );
    }
    return child;
  }

  Widget _buildDynPanel() {
    return SliverToBoxWithOffsetAdapter(
      offset: 55,
      onVisibilityChanged: controller.showTitle.call,
      child: Builder(
        builder: (context) {
          _scrollable = Scrollable.maybeOf(context);
          return DynamicPanel(
            item: controller.dynItem,
            isDetail: true,
            isDetailPortraitW: isPortrait,
            onSetPubSetting: controller.onSetPubSetting,
            onEdit: _onEdit,
            onSetReplySubject: controller.onSetReplySubject,
          );
        },
      ),
    );
  }

  Widget _buildPortrait(double padding) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: padding),
      child: NestedScrollView(
        key: _nestedScrollKey,
        controller: _pageScroll,
        scrollBehavior: const NoOverscrollIndicator(),
        headerSliverBuilder: (context, innerBoxIsScrolled) {
          return [_buildDynPanel()];
        },
        body: Column(
          children: [
            _buildTabBar(),
            Expanded(child: _buildTabBody()),
          ],
        ),
      ),
    );
  }

  Widget _buildHorizontal(double padding) {
    padding = padding / 4;
    final flex = controller.ratio[0].toInt();
    final flex1 = controller.ratio[1].toInt();
    final child = Row(
      children: [
        Expanded(
          flex: flex,
          child: CustomScrollView(
            controller: _pageScroll,
            primary: false,
            slivers: [
              SliverPadding(
                padding: .only(
                  left: padding,
                  bottom:
                      this.padding.bottom +
                      (IOSNativeTabBar.hasNativeActions(context) ? 16 : 100),
                ),
                sliver: _buildDynPanel(),
              ),
            ],
          ),
        ),
        Expanded(
          flex: flex1,
          child: Padding(
            // The native rail already reserves its side safe area, shared with
            // the back button above. Keep this based on geometry, even while
            // a popup temporarily takes over the native action items.
            padding: EdgeInsets.only(
              right:
                  IOSNativeTabBar.enabled &&
                      (IOSNativeTabBar.safeArea.value?.right ?? 0) >= 72
                  ? 0
                  : padding,
            ),
            child: MiniScaffold(
              body: Column(
                children: [
                  _buildTabBar(),
                  Expanded(child: _buildTabBody(false)),
                ],
              ),
            ),
          ),
        ),
      ],
    );
    return child;
  }

  Widget _buildBody() {
    double padding = max(maxWidth / 2 - Grid.smallCardWidth, 0);
    Widget child;
    if (isPortrait) {
      child = _buildPortrait(padding);
    } else {
      child = _buildHorizontal(padding);
    }
    return fabAnimWrapper(child: child);
  }

  Widget _buildBottom() {
    if (!controller.showDynActionBar) {
      return fabButton;
    }

    final primary = theme.colorScheme.primary;
    final outline = theme.colorScheme.outline;
    final btnStyle = TextButton.styleFrom(
      tapTargetSize: .padded,
      padding: const EdgeInsets.symmetric(horizontal: 15),
      foregroundColor: outline,
    );

    Widget textIconButton({
      required IconData icon,
      required String text,
      required DynamicStat? stat,
      required ValueChanged<Color> onPressed,
      IconData? activatedIcon,
    }) {
      final bool status;
      final String count;
      if (stat != null) {
        status = stat.status ?? false;
        count = stat.count != null ? NumUtils.numFormat(stat.count) : text;
      } else {
        status = false;
        count = text;
      }
      final color = status ? primary : outline;
      final child = Icon(status ? activatedIcon : icon, size: 16, color: color);
      return TextButton.icon(
        icon: child,
        style: btnStyle,
        onPressed: () => onPressed(child.color!),
        label: Text(count, style: TextStyle(color: color)),
      );
    }

    final dynItem = controller.dynItem;
    final moduleStat = dynItem.modules.moduleStat;
    return Padding(
      padding: .only(left: padding.left, right: padding.right),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Padding(
            padding: const EdgeInsets.only(
              right: kFloatingActionButtonMargin,
              bottom: kFloatingActionButtonMargin,
            ),
            child: replyButton,
          ),
          Container(
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              border: Border(
                top: BorderSide(
                  color: theme.colorScheme.outline.withValues(alpha: 0.08),
                ),
              ),
            ),
            padding: EdgeInsets.only(bottom: padding.bottom),
            child: Row(
              children: [
                Expanded(
                  child: Builder(
                    builder: (btnContext) {
                      final forward = moduleStat?.forward;
                      return textIconButton(
                        icon: FontAwesomeIcons.shareFromSquare,
                        text: '转发',
                        stat: forward,
                        onPressed: (_) => showModalBottomSheet(
                          context: context,
                          isScrollControlled: true,
                          useSafeArea: true,
                          builder: (context) => RepostPanel(
                            item: dynItem,
                            onSuccess: () {
                              if (forward != null) {
                                int count = forward.count ?? 0;
                                forward.count = count + 1;
                                if (btnContext.mounted) {
                                  (btnContext as Element).markNeedsBuild();
                                }
                              }
                            },
                            replyInfo: (
                              oid: controller.oid,
                              replyType: controller.replyType,
                            ),
                            mentionItem:
                                dynItem.modules.moduleAuthor?.mentionItem,
                          ),
                        ),
                      );
                    },
                  ),
                ),
                Expanded(
                  child: textIconButton(
                    icon: CustomIcons.share_node,
                    text: '分享',
                    stat: null,
                    onPressed: (_) => ShareUtils.shareText(
                      '${HttpString.opusBaseUrl}/${controller.dynItem.idStr}',
                    ),
                  ),
                ),
                Expanded(
                  child: textIconButton(
                    icon: FontAwesomeIcons.comment,
                    text: '评论',
                    stat: moduleStat?.comment,
                    onPressed: _jumpToComment,
                  ),
                ),
                Expanded(
                  child: Builder(
                    builder: (context) {
                      return textIconButton(
                        icon: FontAwesomeIcons.thumbsUp,
                        activatedIcon: FontAwesomeIcons.solidThumbsUp,
                        text: '点赞',
                        stat: moduleStat?.like,
                        onPressed: (iconColor) => RequestUtils.onLikeDynamic(
                          dynItem,
                          iconColor == primary,
                          () {
                            if (context.mounted) {
                              (context as Element).markNeedsBuild();
                            }
                          },
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget buildReplyHeader([bool isPortrait = true]) {
    final secondary = theme.colorScheme.secondary;
    final child = Padding(
      padding: const .fromLTRB(12, 2.5, 6, 2.5),
      child: Obx(() {
        final sortType = controller.sortType.value;
        return Row(
          mainAxisAlignment: .spaceBetween,
          children: [
            Text(sortType.desc),
            TextButton.icon(
              style: Style.buttonStyle,
              onPressed: controller.queryBySort,
              icon: Icon(Icons.sort, size: 16, color: secondary),
              label: Text(
                sortType.descShort,
                style: TextStyle(fontSize: 13, color: secondary),
              ),
            ),
          ],
        );
      }),
    );
    return SliverFloatingHeaderWidget(
      backgroundColor: theme.colorScheme.surface,
      child: child,
    );
  }

  void _jumpToComment([_]) {
    tabController.animateTo(DynType.reply.index);
    if (isPortrait) {
      for (final position in _pageScroll.positions) {
        position.jumpTo(position.maxScrollExtent);
      }
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        for (final position in _horizontalReplyScroll.positions) {
          position.jumpTo(position.minScrollExtent);
        }
      });
    }
  }
}
