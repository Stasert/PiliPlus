import 'package:PiliPlus/models/common/dynamic/dynamic_badge_mode.dart';
import 'package:PiliPlus/utils/ios/native_tab_tools.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  List<NativeTabTool> tools({
    bool loggedIn = true,
    bool? hasAccount,
    String? unread,
    DynamicBadgeMode badgeMode = .number,
    String face = '',
  }) => nativeTabTools(
    loggedIn: loggedIn,
    hasAccount: hasAccount ?? loggedIn,
    unread: unread,
    badgeMode: badgeMode,
    face: face,
  );

  test('从上到下是头像，然后是搜索和私信一组', () {
    final list = tools();
    expect(list.map((e) => e.id), ['mine', 'search', 'notifications']);
    expect(list.map((e) => e.group), ['account', 'actions', 'actions']);
    expect(list.last.symbol, 'envelope');
    expect(list.first.title, '切换账号', reason: '已登录时点头像弹出账号切换');
  });

  test('未登录时没有私信，头像是人形图标，点了去登录', () {
    final list = tools(loggedIn: false, unread: '5', face: 'https://a/b.jpg');
    expect(list.map((e) => e.id), ['mine', 'search']);
    expect(list.first.image, isNull);
    expect(list.first.title, '点击登录');
  });

  test('选了匿名时仍存有账号：没有私信，头像是人形图标，点了弹出账号切换', () {
    final list = tools(
      loggedIn: false,
      hasAccount: true,
      unread: '5',
      face: 'https://a/b.jpg',
    );
    expect(list.map((e) => e.id), ['mine', 'search']);
    expect(list.first.image, isNull);
    expect(list.first.title, '切换账号', reason: '能切回原来的账号');
  });

  test('登录后头像用 https 的小图', () {
    expect(
      tools(face: 'http://i0.hdslb.com/bfs/face/a.jpg').first.image,
      'https://i0.hdslb.com/bfs/face/a.jpg@120w_120h.webp',
    );
    expect(tools().first.image, isNull, reason: '没有头像地址时用图标');
  });

  test('私信角标跟随消息角标设置，没有未读时不显示', () {
    String? badge(DynamicBadgeMode mode, [String? unread = '99+']) =>
        tools(unread: unread, badgeMode: mode).last.badge;
    expect(badge(.number), '99+');
    expect(badge(.point), '', reason: '空字符串显示为红点');
    expect(badge(.hidden), isNull);
    expect(badge(.number, null), isNull);
  });

  test('发给原生层的数据不带空字段', () {
    expect(tools(loggedIn: false)[1].toMap(), {
      'id': 'search',
      'group': 'actions',
      'title': '搜索',
      'symbol': 'magnifyingglass',
    });
  });
}
