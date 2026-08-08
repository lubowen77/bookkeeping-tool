/// 金额工具。数据库中的金额一律使用“分”的整数表示。
abstract final class Money {
  static final RegExp _inputPattern = RegExp(r'^\d+(?:\.\d{0,2})?$');

  /// 将用户输入的元金额转为分，不经过浮点数。
  ///
  /// 合法示例：`12`、`12.3`、`12.30`。空字符串、负数、超过两位小数
  /// 或零金额均返回 null；若 [allowZero] 为 true，则允许零金额。
  static int? tryParseCents(String input, {bool allowZero = false}) {
    final normalized = input.trim();
    if (normalized.isEmpty || !_inputPattern.hasMatch(normalized)) {
      return null;
    }

    final parts = normalized.split('.');
    final yuan = int.tryParse(parts.first);
    if (yuan == null) return null;

    final fractionText = parts.length == 1 ? '' : parts[1];
    final fraction = switch (fractionText.length) {
      0 => 0,
      1 => int.parse(fractionText) * 10,
      _ => int.parse(fractionText),
    };
    final cents = yuan * 100 + fraction;
    if (cents == 0 && !allowZero) return null;
    return cents;
  }

  /// 按账本口径显示金额：整元不带小数，非整元最多两位小数。
  static String formatCents(int cents, {bool useGrouping = true}) {
    final negative = cents < 0;
    final absolute = cents.abs();
    final yuan = absolute ~/ 100;
    final fraction = absolute % 100;
    final yuanText = useGrouping ? _groupThousands(yuan) : '$yuan';

    final decimalText = switch (fraction) {
      0 => '',
      _ when fraction % 10 == 0 => '.${fraction ~/ 10}',
      _ => '.${fraction.toString().padLeft(2, '0')}',
    };
    return '${negative ? '-' : ''}$yuanText$decimalText';
  }

  static String _groupThousands(int value) {
    final source = '$value';
    final buffer = StringBuffer();
    for (var index = 0; index < source.length; index++) {
      if (index > 0 && (source.length - index) % 3 == 0) {
        buffer.write(',');
      }
      buffer.write(source[index]);
    }
    return buffer.toString();
  }
}
