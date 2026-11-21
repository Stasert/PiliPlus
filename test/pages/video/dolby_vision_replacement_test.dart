import 'package:PiliPlus/pages/video/controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  int? run(List<int> qualities) =>
      VideoDetailController.profile5Replacement(qualities);

  test('HDR 真彩 replaces Dolby Vision profile 5 when there is one', () {
    expect(run([126, 125, 120, 116, 80]), 125);
    expect(run([129, 126, 125, 80]), 125);
  });

  test('otherwise the best quality that is not HDR', () {
    expect(run([126, 120, 116, 80, 64]), 120);
    expect(run([126, 80, 116, 64]), 116);
    // HDR Vivid is HDR too; 8K is not.
    expect(run([129, 127, 126, 120]), 127);
    expect(run([129, 126, 80]), 80);
  });

  test('nothing to play instead without another quality', () {
    expect(run([126]), isNull);
    expect(run([129, 126]), isNull);
    expect(run([]), isNull);
  });
}
