import 'package:flutter/services.dart';

/// 所有金额输入的统一规则：最多 7 位整数、1 个小数点和 2 位小数。
final class MoneyInputFormatter extends TextInputFormatter {
  const MoneyInputFormatter({this.maxIntegerDigits = 7});

  final int maxIntegerDigits;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    var text = newValue.text.replaceAll(',', '.');
    if (text.startsWith('.')) text = '0$text';
    final valid = RegExp(
      '^\\d{0,$maxIntegerDigits}(?:\\.\\d{0,2})?\$',
    ).hasMatch(text);
    if (!valid) return oldValue;
    final delta = text.length - newValue.text.length;
    final base = (newValue.selection.baseOffset + delta).clamp(0, text.length);
    final extent = (newValue.selection.extentOffset + delta).clamp(
      0,
      text.length,
    );
    return newValue.copyWith(
      text: text,
      selection: TextSelection(baseOffset: base, extentOffset: extent),
      composing: TextRange.empty,
    );
  }
}
