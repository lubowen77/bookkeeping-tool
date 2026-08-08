import 'package:flutter_test/flutter_test.dart';
import 'package:zhangben/core/pinyin.dart';

void main() {
  test('生成全拼与首字母索引', () {
    final value = PinyinIndex.fromName('张老三');
    expect(value.full, 'zhanglaosan');
    expect(value.abbr, 'zls');
  });

  test('常见多音姓氏优先使用姓氏读音', () {
    final value = PinyinIndex.fromName('单田芳');
    expect(value.full, 'shantianfang');
    expect(value.abbr, 'stf');
  });
}
