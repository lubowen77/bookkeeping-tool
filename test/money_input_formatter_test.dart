import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zhangben/ui/widgets/money_input_formatter.dart';

void main() {
  const formatter = MoneyInputFormatter();

  TextEditingValue edit(String text) => TextEditingValue(
    text: text,
    selection: TextSelection.collapsed(offset: text.length),
  );

  test('金额输入只接受数字、一个小数点与最多两位小数', () {
    expect(
      formatter.formatEditUpdate(edit('12.3'), edit('12.34')).text,
      '12.34',
    );
    expect(
      formatter.formatEditUpdate(edit('12.34'), edit('12.345')).text,
      '12.34',
    );
    expect(
      formatter.formatEditUpdate(edit('12.3'), edit('12a.3')).text,
      '12.3',
    );
    expect(
      formatter.formatEditUpdate(edit('12.3'), edit('12..3')).text,
      '12.3',
    );
  });

  test('兼容中文数字键盘逗号小数点并限制整数位数', () {
    expect(formatter.formatEditUpdate(edit(''), edit(',5')).text, '0.5');
    expect(
      formatter.formatEditUpdate(edit('1234567'), edit('12345678')).text,
      '1234567',
    );
  });
}
