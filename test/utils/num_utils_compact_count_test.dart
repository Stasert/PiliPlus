import 'package:PiliPlus/utils/num_utils.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('一万以下原样显示', () {
    expect(NumUtils.compactCount(0), '0');
    expect(NumUtils.compactCount(-3), '0');
    expect(NumUtils.compactCount(9999), '9999');
  });

  test('万：一位小数，向下取整', () {
    expect(NumUtils.compactCount(10000), '1万');
    expect(NumUtils.compactCount(12999), '1.2万');
    expect(NumUtils.compactCount(99999), '9.9万');
    expect(NumUtils.compactCount(100000), '10万');
    expect(NumUtils.compactCount(129999), '12万');
    expect(NumUtils.compactCount(9999999), '999万');
  });

  test('一千万到一亿之间显示千万', () {
    expect(NumUtils.compactCount(10000000), '1千万');
    expect(NumUtils.compactCount(19999999), '1千万');
    expect(NumUtils.compactCount(99999999), '9千万');
  });

  test('亿：一位小数，向下取整，最多 999亿', () {
    expect(NumUtils.compactCount(100000000), '1亿');
    expect(NumUtils.compactCount(129999999), '1.2亿');
    expect(NumUtils.compactCount(1200000000), '12亿');
    expect(NumUtils.compactCount(99999999999), '999亿');
    expect(NumUtils.compactCount(100000000000), '999亿');
  });

  test('不超过 4 个字', () {
    for (var n = 1; n < 1000000000000; n = n * 3 + 7) {
      expect(
        NumUtils.compactCount(n).length,
        lessThanOrEqualTo(4),
        reason: '$n',
      );
    }
  });
}
