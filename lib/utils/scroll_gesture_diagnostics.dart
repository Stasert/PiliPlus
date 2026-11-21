import 'dart:collection';
import 'dart:convert';

import 'package:PiliPlus/build_config.dart';
import 'package:flutter/gestures.dart'
    show PointerPanZoomStartEvent, PointerPanZoomEndEvent;
import 'package:flutter/widgets.dart';

/// A bounded trace of gesture ownership, without touch coordinates or content.
/// Recovery only releases a drag/hold after every tracked pointer has ended.
class ScrollGestureDiagnostics with WidgetsBindingObserver {
  ScrollGestureDiagnostics();

  static final instance = ScrollGestureDiagnostics();
  static const recordLimit = 192;
  static const positionLimit = 32;

  final _clock = Stopwatch()..start();
  final _records = Queue<Map<String, Object?>>();
  final _pointers = <int>{};
  final _positions = <_ObservedScroll>[];
  WidgetsBinding? _binding;
  String Function()? routeName;
  int _generation = 0;
  int _sequence = 0;
  int _recoveryTicket = 0;
  int _recoveries = 0;
  bool _recovering = false;

  void attach(WidgetsBinding binding) {
    if (identical(_binding, binding)) return;
    detach();
    _binding = binding;
    binding.pointerRouter.addGlobalRoute(_onPointer);
    binding.addObserver(this);
  }

  void detach() {
    _binding?.pointerRouter.removeGlobalRoute(_onPointer);
    _binding?.removeObserver(this);
    _binding = null;
    _pointers.clear();
    _positions.clear();
    _generation++;
    _recoveryTicket++;
  }

  String get _route => (routeName?.call() ?? '').split('?').first;

  void _record(String event, [Map<String, Object?> fields = const {}]) {
    _records.add({
      'sequence': ++_sequence,
      'time': DateTime.now().toIso8601String(),
      'elapsedMs': _clock.elapsedMilliseconds,
      'event': event,
      'route': _route,
      'activePointers': _pointers.toList(),
      ...fields,
    });
    while (_records.length > recordLimit) {
      _records.removeFirst();
    }
  }

  void _onPointer(PointerEvent event) {
    if (event is PointerDownEvent || event is PointerPanZoomStartEvent) {
      _pointers.add(event.pointer);
      _generation++;
      _record('pointer.down', {'pointer': event.pointer, 'view': event.viewId});
    } else if (event is PointerUpEvent ||
        event is PointerCancelEvent ||
        event is PointerPanZoomEndEvent) {
      _pointers.remove(event.pointer);
      _record(event is PointerCancelEvent ? 'pointer.cancel' : 'pointer.up', {
        'pointer': event.pointer,
        'view': event.viewId,
      });
      if (_pointers.isEmpty) _scheduleRecovery();
    }
  }

  void observePosition(ScrollPosition position) {
    if (axisDirectionToAxis(position.axisDirection) != Axis.vertical) return;
    _positions.removeWhere((entry) => entry.position.target == null);
    if (_positions.any((entry) => identical(entry.position.target, position))) {
      return;
    }
    _positions.add(_ObservedScroll(position));
    if (_positions.length > positionLimit) _positions.removeAt(0);
  }

  bool onScrollNotification(ScrollNotification notification) {
    if (notification.metrics.axis != Axis.vertical) return false;
    final context = notification.context;
    final position = context == null
        ? null
        : Scrollable.maybeOf(context)?.position;
    if (position == null) return false;
    observePosition(position);
    final entry = _positions.firstWhere(
      (e) => identical(e.position.target, position),
    );
    final isBoundary =
        notification is ScrollStartNotification ||
        notification is ScrollEndNotification;
    if (isBoundary || _clock.elapsedMilliseconds - entry.lastSample >= 250) {
      entry.lastSample = _clock.elapsedMilliseconds;
      _record(
        notification is ScrollStartNotification
            ? 'scroll.start'
            : notification is ScrollEndNotification
            ? 'scroll.end'
            : 'scroll.update',
        _scrollFields(position),
      );
    }
    return false;
  }

  // The patched SDK's activity is the authoritative drag/hold state. Keep
  // this read isolated; recovery uses the public goBallistic API.
  // ignore: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member
  ScrollActivity? _activityOf(ScrollPosition position) => position.activity;

  Map<String, Object?> _scrollFields(ScrollPosition position) {
    final activity = _activityOf(position);
    return {
      'scroll': identityHashCode(position),
      'offset': position.hasPixels ? position.pixels : null,
      'viewport': position.hasViewportDimension
          ? position.viewportDimension
          : null,
      'activity': switch (activity) {
        DragScrollActivity() => 'drag',
        HoldScrollActivity() => 'hold',
        BallisticScrollActivity() => 'ballistic',
        DrivenScrollActivity() => 'driven',
        IdleScrollActivity() => 'idle',
        _ => 'other',
      },
      'velocity': activity?.velocity,
    };
  }

  void _scheduleRecovery() {
    final binding = _binding;
    if (binding == null || _pointers.isNotEmpty) return;
    final generation = _generation;
    final ticket = ++_recoveryTicket;
    binding.addPostFrameCallback((_) {
      if (_binding != binding ||
          ticket != _recoveryTicket ||
          generation != _generation ||
          _pointers.isNotEmpty ||
          _recovering) {
        return;
      }
      _recovering = true;
      try {
        for (final entry in _positions.toList()) {
          final position = entry.position.target;
          if (position is! ScrollPositionWithSingleContext ||
              position.context.notificationContext?.mounted != true ||
              !position.hasPixels ||
              !position.hasContentDimensions) {
            continue;
          }
          // Do not interrupt inertia, programmatic scrolling, or a held finger.
          final activity = _activityOf(position);
          if (activity is! DragScrollActivity &&
              activity is! HoldScrollActivity) {
            continue;
          }
          _record('scroll.recover', _scrollFields(position));
          _recoveries++;
          position.goBallistic(0);
        }
      } finally {
        _recovering = false;
      }
    });
    binding.ensureVisualUpdate();
  }

  /// Used on backgrounding, or explicitly from the diagnostic menu. Never on a
  /// timer: a legitimate long press must retain ownership for as long as needed.
  void restoreScrolling({String reason = 'manual'}) {
    _record('restore.requested', {'reason': reason});
    for (final pointer in _pointers.toList()) {
      _binding?.cancelPointer(pointer);
    }
    _scheduleRecovery();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _record('lifecycle', {'state': state.name});
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      restoreScrolling(reason: state.name);
    } else if (state == AppLifecycleState.resumed) {
      _scheduleRecovery();
    }
  }

  String exportReport() {
    _record('diagnostics.copy');
    return const JsonEncoder.withIndent('  ').convert({
      'build': BuildConfig.commitHash,
      'version': BuildConfig.versionName,
      'buildNumber': BuildConfig.versionCode,
      'buildTimeUnix': BuildConfig.buildTime,
      'copiedAt': DateTime.now().toIso8601String(),
      'utcOffsetMinutes': DateTime.now().timeZoneOffset.inMinutes,
      'activePointers': _pointers.toList(),
      'recoveries': _recoveries,
      'scrolls': [
        for (final e in _positions)
          if (e.position.target case final p?) _scrollFields(p),
      ],
      'events': _records.toList(),
    });
  }
}

class _ObservedScroll {
  _ObservedScroll(ScrollPosition position) : position = WeakReference(position);
  final WeakReference<ScrollPosition> position;
  int lastSample = -250;
}

class ScrollGestureScope extends StatelessWidget {
  const ScrollGestureScope({super.key, required this.child, this.diagnostics});
  final Widget child;
  final ScrollGestureDiagnostics? diagnostics;

  @override
  Widget build(BuildContext context) {
    final monitor = diagnostics ?? ScrollGestureDiagnostics.instance;
    return NotificationListener<ScrollMetricsNotification>(
      onNotification: (notification) {
        final position = Scrollable.maybeOf(notification.context)?.position;
        if (position != null) monitor.observePosition(position);
        return false;
      },
      child: NotificationListener<ScrollNotification>(
        onNotification: monitor.onScrollNotification,
        child: child,
      ),
    );
  }
}
