import 'package:PiliPlus/models/common/dynamic/dynamic_badge_mode.dart';

/// 竖状态栏顶部（Wi-Fi 图标下面）的按钮，iPhone Duo 的一级页面显示；二级页面
/// 的同一位置显示返回键
class NativeTabTool {
  const NativeTabTool({
    required this.id,
    required this.group,
    required this.title,
    required this.symbol,
    this.badge,
    this.image,
  });

  final String id;

  /// 相邻且 [group] 相同的按钮在竖状态栏里合成一个组合按钮
  final String group;
  final String title;

  /// SF Symbols 图标名，[image] 加载出来之前也用它
  final String symbol;

  /// null 时不显示角标，空字符串时显示红点
  final String? badge;

  /// 显示为圆形的图片地址（头像）
  final String? image;

  Map<String, Object> toMap() => {
    'id': id,
    'group': group,
    'title': title,
    'symbol': symbol,
    'badge': ?badge,
    'image': ?image,
  };

  @override
  bool operator ==(Object other) =>
      other is NativeTabTool &&
      other.id == id &&
      other.group == group &&
      other.title == title &&
      other.symbol == symbol &&
      other.badge == badge &&
      other.image == image;

  @override
  int get hashCode => Object.hash(id, group, title, symbol, badge, image);

  @override
  String toString() =>
      'NativeTabTool($id, $group, $title, $symbol, $badge, $image)';
}

/// 一级页面仅保留搜索和私信，统一在同一个玻璃按钮组中。
/// 私信只在登录后显示，角标和首页消息设置保持一致；账号入口保留在「我的」。
List<NativeTabTool> nativeTabTools({
  required bool loggedIn,
  required String? unread,
  required DynamicBadgeMode badgeMode,
}) => [
  const NativeTabTool(
    id: 'search',
    group: 'actions',
    title: '搜索',
    symbol: 'magnifyingglass',
  ),
  if (loggedIn)
    NativeTabTool(
      id: 'notifications',
      group: 'actions',
      title: '私信',
      symbol: 'envelope',
      badge: unread == null || badgeMode == .hidden
          ? null
          : badgeMode == .number
          ? unread
          : '',
    ),
];
