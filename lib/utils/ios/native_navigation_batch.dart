import 'package:collection/collection.dart';

/// Flush after all route, page and comment registrations for a frame finish.
/// Transient empty owners must never reach UIKit between two valid pages.
class NativeNavigationBatch {
  NativeNavigationBatch({required this.schedule, required this.onChanged});
  final void Function(void Function()) schedule;
  final void Function(Map<String, Object>) onChanged;
  final _latest = <String, Object>{};
  final _sent = <String, Object>{};
  bool _scheduled = false;
  static const _equality = DeepCollectionEquality();

  void submit(String key, Map<String, Object> value) {
    _latest[key] = value;
    if (_scheduled) return;
    _scheduled = true;
    schedule(() {
      _scheduled = false;
      final changes = takeChanges();
      if (changes.isNotEmpty) onChanged(changes);
    });
  }

  /// An entering route sends its initial commands with the transition start.
  /// The scheduled frame flush still handles later data, without replaying the
  /// initial snapshot or restoring an older page owner.
  Map<String, Object> takeChanges() {
    final changes = <String, Object>{};
    for (final entry in _latest.entries) {
      if (!_equality.equals(_sent[entry.key], entry.value)) {
        changes[entry.key] = entry.value;
        _sent[entry.key] = entry.value;
      }
    }
    return changes;
  }
}
