import 'package:lpinyin/lpinyin.dart';

final class PinyinText {
  const PinyinText({required this.full, required this.abbr});

  final String full;
  final String abbr;
}

/// 离线生成检索用全拼和首字母。
abstract final class PinyinIndex {
  // lpinyin 对单字默认取第一个读音。这里先覆盖容易读错的常见姓氏，
  // 再交给离线词库处理姓名剩余部分。
  static const Map<String, String> _surnameOverrides = {
    '单': 'shan',
    '仇': 'qiu',
    '区': 'ou',
    '查': 'zha',
    '曾': 'zeng',
    '解': 'xie',
    '朴': 'piao',
    '缪': 'miao',
    '翟': 'zhai',
    '盖': 'ge',
    '折': 'she',
    '乐': 'yue',
    '员': 'yun',
    '种': 'chong',
    '秘': 'bi',
    '冼': 'xian',
  };

  static PinyinText fromName(String name) {
    final normalized = name.trim();
    if (normalized.isEmpty) {
      return const PinyinText(full: '', abbr: '');
    }

    final first = normalized.substring(0, 1);
    final override = _surnameOverrides[first];
    if (override == null) {
      return PinyinText(
        full: PinyinHelper.getPinyin(normalized, separator: '').toLowerCase(),
        abbr: PinyinHelper.getShortPinyin(normalized).toLowerCase(),
      );
    }

    final remainder = normalized.substring(1);
    final remainderFull = PinyinHelper.getPinyin(
      remainder,
      separator: '',
    ).toLowerCase();
    final remainderAbbr = PinyinHelper.getShortPinyin(remainder).toLowerCase();
    return PinyinText(
      full: '$override$remainderFull',
      abbr: '${override[0]}$remainderAbbr',
    );
  }
}
