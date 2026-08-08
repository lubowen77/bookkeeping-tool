/// 返回业务日期，格式固定为 YYYY-MM-DD。
String businessDateOf(DateTime value) {
  final local = value.toLocal();
  return '${local.year.toString().padLeft(4, '0')}-'
      '${local.month.toString().padLeft(2, '0')}-'
      '${local.day.toString().padLeft(2, '0')}';
}

String chineseDateWithWeekday(DateTime value) {
  const weekdays = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
  final local = value.toLocal();
  return '${local.year}年${local.month}月${local.day}日 '
      '${weekdays[local.weekday - 1]}';
}

/// 生成带本地时区偏移的 ISO8601 时间，保留微秒以区分连续删除操作。
String localIsoTimestamp([DateTime? value]) {
  final local = (value ?? DateTime.now()).toLocal();
  final offset = local.timeZoneOffset;
  final sign = offset.isNegative ? '-' : '+';
  final absoluteMinutes = offset.inMinutes.abs();
  final offsetHours = absoluteMinutes ~/ 60;
  final offsetMinutes = absoluteMinutes % 60;
  final fraction = local.microsecond == 0
      ? ''
      : '.${local.microsecond.toString().padLeft(6, '0')}';

  return '${local.year.toString().padLeft(4, '0')}-'
      '${local.month.toString().padLeft(2, '0')}-'
      '${local.day.toString().padLeft(2, '0')}T'
      '${local.hour.toString().padLeft(2, '0')}:'
      '${local.minute.toString().padLeft(2, '0')}:'
      '${local.second.toString().padLeft(2, '0')}$fraction'
      '$sign${offsetHours.toString().padLeft(2, '0')}:'
      '${offsetMinutes.toString().padLeft(2, '0')}';
}
