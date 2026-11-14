import 'package:PiliPlus/models/common/dynamic/dynamic_badge_mode.dart';
import 'package:PiliPlus/utils/extension/string_ext.dart';

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

/// 从上到下：头像，然后是搜索和私信合在一起的一组。私信只在登录后显示，角标
/// 和首页顶部的消息按钮一致。头像只要本机存有账号就点了弹出账号切换，包括在
/// 账号切换里选了匿名（[hasAccount] 为 true、[loggedIn] 为 false）的时候，这样
/// 能切回原来的账号；一个账号都没有时点了去「我的」页面登录。没登录（含匿名）
/// 时头像显示为人形图标
List<NativeTabTool> nativeTabTools({
  required bool loggedIn,
  required bool hasAccount,
  required String? unread,
  required DynamicBadgeMode badgeMode,
  required String face,
}) => [
  NativeTabTool(
    id: 'mine',
    group: 'account',
    title: loggedIn || hasAccount ? '切换账号' : '点击登录',
    symbol: 'person.crop.circle',
    image: loggedIn && face.isNotEmpty
        ? '${face.http2https}@120w_120h.webp'
        : null,
  ),
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
