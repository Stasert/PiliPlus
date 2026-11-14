import 'package:PiliPlus/utils/extension/num_ext.dart';
import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;

abstract final class NumUtils {
  static final _numRegExp = RegExp(r'([\d\.]+)([千万亿])?');

  static int _getUnit(String? unit) {
    switch (unit) {
      case '千':
        return 1000;
      case '万':
        return 10000;
      case '亿':
        return 100000000;
      default:
        return 1;
    }
  }

  static int parseNum(String numberStr) {
    if (numberStr == '-') return 0;
    try {
      final match = _numRegExp.firstMatch(numberStr)!;
      var number = double.parse(match.group(1)!);
      number *= _getUnit(match.group(2));
      return number.toInt();
    } catch (e) {
      if (kDebugMode) debugPrint('parse failed: "$numberStr" : $e');
      return 0;
    }
  }

  static String numFormat(dynamic number) {
    if (number == null) {
      return '0';
    }
    if (number is String) {
      number = int.tryParse(number) ?? number;
      if (number is String) {
        return number;
      }
    }

    String format(first, second) {
      double result = ((number / first) as double).toPrecision(1);
      int intRes = result.toInt();
      if (result == intRes) {
        return '$intRes$second';
      } else {
        return '$result$second';
      }
    }

    if (number >= 100000000) {
      return format(100000000, '亿');
    } else if (number >= 10000) {
      return format(10000, '万');
    } else {
      return number.toString();
    }
  }

  /// 最多 4 个字的数量，放进窄按钮（iPhone Duo 竖状态栏）。一律向下取整，
  /// 不会显示得比实际多：9999、1.2万、12万、999万、1千万…9千万、1.2亿、
  /// 12亿、999亿，更大的也显示 999亿
  static String compactCount(int number) {
    if (number < 10000) return number < 0 ? '0' : '$number';
    String withUnit(int unit, String suffix) {
      final tenths = number * 10 ~/ unit;
      if (tenths >= 100) return '${tenths ~/ 10}$suffix';
      final decimal = tenths % 10;
      return decimal == 0
          ? '${tenths ~/ 10}$suffix'
          : '${tenths ~/ 10}.$decimal$suffix';
    }

    if (number < 10000000) return withUnit(10000, '万');
    if (number < 100000000) return '${number ~/ 10000000}千万';
    if (number < 100000000000) return withUnit(100000000, '亿');
    return '999亿';
  }

  static String formatPositiveDecimal(int number) {
    if (number < 1000) return number.toString();

    final numStr = number.toString();
    final length = numStr.length;
    final sb = StringBuffer();

    int firstLength = length % 3;
    if (firstLength == 0) firstLength = 3;

    sb.write(numStr.substring(0, firstLength));
    for (int i = firstLength; i < length; i += 3) {
      sb
        ..write(',')
        ..write(numStr.substring(i, i + 3));
    }

    return sb.toString();
  }
}
