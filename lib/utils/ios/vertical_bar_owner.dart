import 'package:flutter/foundation.dart';

/// 决定竖状态栏（iPhone Duo）是否隐藏。隐藏是全局状态，原生层以最后一次
/// 调用为准，所以只让当前在最上层、要隐藏它的页面（视频页）来写：
///
/// - 页面到了最上层时 [claim]，成为拥有者并隐藏竖状态栏；
/// - 页面被弹出或被盖住时 [release]，只有它仍是拥有者时才恢复显示。
///
/// [release] 推迟到这一帧之后再判断：从视频 B 返回视频 A 时，A 的
/// didPopNext 和 B 的 didPop 谁先执行都不影响结果；从视频 A 打开视频 B 时，
/// B 在下一帧里 [claim]，竖状态栏不会先显示再隐藏。离开最后一个视频页、
/// 回到别的页面时没有页面再 [claim]，竖状态栏恢复显示。
class VerticalBarOwner {
  VerticalBarOwner({required this.onChanged, required this.schedule});

  /// 把是否隐藏发给原生层
  final ValueChanged<bool> onChanged;

  /// 在这一帧之后执行回调
  final void Function(VoidCallback callback) schedule;

  Object? _owner;

  /// 每次 [claim] 加一，用来认出 [release] 之后同一个页面又 [claim] 过
  int _claims = 0;

  Object? get owner => _owner;

  void claim(Object page) {
    _owner = page;
    _claims++;
    onChanged(true);
  }

  void release(Object page) {
    if (!identical(_owner, page)) return;
    final claims = _claims;
    schedule(() {
      if (identical(_owner, page) && _claims == claims) {
        _owner = null;
        onChanged(false);
      }
    });
  }
}
