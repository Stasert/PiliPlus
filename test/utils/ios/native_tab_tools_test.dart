import 'package:PiliPlus/models/common/dynamic/dynamic_badge_mode.dart';
import 'package:PiliPlus/utils/ios/native_tab_tools.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  List<NativeTabTool> tools({
    bool loggedIn = true,
    String? unread,
    DynamicBadgeMode badgeMode = .number,
  }) =>
      nativeTabTools(loggedIn: loggedIn, unread: unread, badgeMode: badgeMode);
  test('搜索和私信共用按钮组，不再包含头像', () {
    final list = tools();
    expect(list.map((e) => e.id), ['search', 'notifications']);
    expect(list.map((e) => e.group), ['actions', 'actions']);
    expect(list.every((e) => e.image == null), isTrue);
  });
  test('未登录仅显示搜索', () {
    expect(tools(loggedIn: false).map((e) => e.id), ['search']);
  });
  test('保留私信角标设置', () {
    expect(tools(unread: '99+').last.badge, '99+');
    expect(tools(unread: '3', badgeMode: .point).last.badge, '');
    expect(tools(unread: '3', badgeMode: .hidden).last.badge, isNull);
    expect(tools().last.badge, isNull);
  });
  test('搜索数据不带空字段', () {
    expect(tools(loggedIn: false).first.toMap(), {
      'id': 'search',
      'group': 'actions',
      'title': '搜索',
      'symbol': 'magnifyingglass',
    });
  });
}
