import 'package:PiliPlus/utils/ios/native_navigation_batch.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'entry snapshot drains latest owners without replaying queued flush',
    () {
      final callbacks = <void Function()>[];
      final sent = <Map<String, Object>>[];
      final batch =
          NativeNavigationBatch(
              schedule: callbacks.add,
              onChanged: sent.add,
            )
            ..submit('page', {'owner': 1})
            ..submit('page', {'owner': 2})
            ..submit('comment', {'owner': 3, 'visible': true});
      expect(batch.takeChanges(), {
        'page': {'owner': 2},
        'comment': {'owner': 3, 'visible': true},
      });
      callbacks.removeAt(0)();
      expect(sent, isEmpty);
      batch.submit('page', {'owner': 4});
      callbacks.removeAt(0)();
      expect(sent.single, {
        'page': {'owner': 4},
      });
    },
  );
  test(
    'route and comment handoff publish once with the final frame owners',
    () {
      final callbacks = <void Function()>[];
      final sent = <Map<String, Object>>[];
      final NativeNavigationBatch batch =
          NativeNavigationBatch(
              schedule: callbacks.add,
              onChanged: sent.add,
            )
            ..submit('page', {'owner': 1, 'items': <Object>[]})
            ..submit('comment', {'owner': 2, 'visible': true});
      callbacks.removeAt(0)();
      batch
        ..submit('page', {'owner': 0, 'items': <Object>[]})
        ..submit('comment', {'owner': 0, 'visible': false})
        ..submit('page', {
          'owner': 3,
          'items': [
            {'id': 'home'},
          ],
        })
        ..submit('comment', {'owner': 4, 'visible': true});
      expect(callbacks, hasLength(1));
      callbacks.removeAt(0)();
      expect(sent, hasLength(2));
      expect(sent.last, {
        'page': {
          'owner': 3,
          'items': [
            {'id': 'home'},
          ],
        },
        'comment': {'owner': 4, 'visible': true},
      });
      batch
        ..submit('page', {
          'owner': 3,
          'items': [
            {'id': 'home'},
          ],
        })
        ..submit('comment', {'owner': 4, 'visible': true});
      callbacks.removeAt(0)();
      expect(sent, hasLength(2));
      batch.submit('comment', {'owner': 0, 'visible': false});
      callbacks.removeAt(0)();
      expect(sent.last, {
        'comment': {'owner': 0, 'visible': false},
      });
    },
  );
}
