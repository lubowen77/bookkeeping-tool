import 'package:flutter_test/flutter_test.dart';
import 'package:zhangben/core/money.dart';

void main() {
  group('Money.tryParseCents', () {
    test('只用整数运算解析元、角、分', () {
      expect(Money.tryParseCents('12'), 1200);
      expect(Money.tryParseCents('12.3'), 1230);
      expect(Money.tryParseCents('12.30'), 1230);
      expect(Money.tryParseCents('0.01'), 1);
      expect(Money.tryParseCents(' 350 '), 35000);
    });

    test('拒绝零、负数和超过两位小数', () {
      expect(Money.tryParseCents('0'), isNull);
      expect(Money.tryParseCents('0', allowZero: true), 0);
      expect(Money.tryParseCents('-1'), isNull);
      expect(Money.tryParseCents('1.234'), isNull);
      expect(Money.tryParseCents('abc'), isNull);
      expect(Money.tryParseCents(''), isNull);
    });
  });

  test('整元不显示小数，非整元最多两位', () {
    expect(Money.formatCents(35000), '350');
    expect(Money.formatCents(123450), '1,234.5');
    expect(Money.formatCents(123456), '1,234.56');
    expect(Money.formatCents(-500), '-5');
  });
}
