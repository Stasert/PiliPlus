import 'dart:async';

import 'package:PiliPlus/common/widgets/dialog/dialog.dart';
import 'package:PiliPlus/common/widgets/flutter/list_tile.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:PiliPlus/utils/storage_key.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:material_ui/material_ui.dart' hide ListTile;

class SetSwitchItem extends StatefulWidget {
  final String title;
  final String? subtitle;
  final String setKey;
  final bool defaultVal;
  final bool enabled;
  final ValueChanged<bool>? onChanged;

  /// Asked before the new value is saved; returning false keeps the old one.
  final Future<bool> Function(BuildContext context, bool value)? confirmChange;

  /// While this other boolean setting is on, the switch shows on and is
  /// disabled (its own value is not changed).
  final String? lockedOnBy;

  /// When set, the switch shows off and is disabled (its own value is not
  /// changed), and this text replaces the subtitle to say why.
  final String? lockedOffReason;
  final bool needReboot;
  final Widget? leading;
  final void Function(BuildContext context)? onTap;
  final EdgeInsetsGeometry? contentPadding;
  final TextStyle? titleStyle;
  final bool isSplit;

  const SetSwitchItem({
    super.key,
    required this.title,
    this.subtitle,
    required this.setKey,
    this.defaultVal = false,
    this.enabled = true,
    this.onChanged,
    this.confirmChange,
    this.lockedOnBy,
    this.lockedOffReason,
    this.needReboot = false,
    this.leading,
    this.onTap,
    this.contentPadding,
    this.titleStyle,
    this.isSplit = false,
  });

  @override
  State<SetSwitchItem> createState() => _SetSwitchItemState();
}

class _SetSwitchItemState extends State<SetSwitchItem> {
  late bool val;

  void _setVal() {
    val = GStorage.setting.get(widget.setKey, defaultValue: widget.defaultVal);
  }

  @override
  void didUpdateWidget(SetSwitchItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.setKey != widget.setKey) {
      _setVal();
    }
  }

  StreamSubscription? _lockSubscription;

  bool get _locked => switch (widget.lockedOnBy) {
    final key? => GStorage.setting.get(key, defaultValue: false) == true,
    null => false,
  };

  @override
  void initState() {
    super.initState();
    _setVal();
    if (widget.lockedOnBy case final key?) {
      _lockSubscription = GStorage.setting.watch(key: key).listen((_) {
        _setVal();
        if (mounted) setState(() {});
      });
    }
  }

  @override
  void dispose() {
    _lockSubscription?.cancel();
    super.dispose();
  }

  Future<void> switchChange([bool? value]) async {
    val = value ?? !val;

    if (val && widget.setKey == SettingBoxKey.badCertificateCallback) {
      val = await showConfirmDialog(
        context: context,
        title: const Text('确定禁用 SSL 证书验证？'),
        content: const Text('禁用容易受到中间人攻击'),
      );
      if (!val) return;
    }

    if (widget.confirmChange case final confirm?) {
      if (!mounted) return;
      if (!await confirm(context, val)) {
        val = !val;
        return;
      }
    }

    await GStorage.setting.put(widget.setKey, val);

    widget.onChanged?.call(val);
    if (widget.needReboot) SmartDialog.showToast('重启生效');
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lockedOff = !widget.enabled || widget.lockedOffReason != null;
    final locked = _locked || lockedOff;
    final subtitle = widget.lockedOffReason ?? widget.subtitle;
    final titleStyle =
        widget.titleStyle ??
        theme.textTheme.titleMedium!.copyWith(
          color: locked || (widget.onTap != null && !val)
              ? theme.colorScheme.outline
              : null,
        );
    final subTitleStyle = theme.textTheme.labelMedium!.copyWith(
      color: locked
          ? theme.colorScheme.outline.withValues(alpha: 0.6)
          : theme.colorScheme.outline,
    );

    final switchBtn = Transform.scale(
      scale: 0.8,
      alignment: .centerRight,
      child: Switch(
        value: !lockedOff && (locked || val),
        onChanged: locked ? null : switchChange,
      ),
    );

    Widget child(Widget? trailing) => ListTile(
      contentPadding: widget.contentPadding,
      enabled: !locked && (widget.onTap == null || val),
      onTap: locked
          ? null
          : widget.onTap == null
          ? switchChange
          : () => widget.onTap!(context),
      title: Text(widget.title, style: titleStyle),
      subtitle: subtitle != null ? Text(subtitle, style: subTitleStyle) : null,
      leading: widget.leading,
      trailing: trailing,
    );

    if (widget.isSplit) {
      return Row(
        children: [
          Expanded(child: child(null)),
          SizedBox(
            height: 25,
            child: VerticalDivider(
              width: 1,
              color: theme.colorScheme.outline.withValues(alpha: .3),
            ),
          ),
          Padding(padding: const .only(left: 4, right: 24), child: switchBtn),
        ],
      );
    }

    return child(switchBtn);
  }
}
