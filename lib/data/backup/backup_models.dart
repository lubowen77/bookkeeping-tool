import 'dart:convert';

enum BackupValidationCode {
  invalidJson,
  invalidApp,
  unsupportedSchema,
  newerSchema,
  invalidStructure,
  checksumMismatch,
  countsMismatch,
}

final class BackupValidationException implements FormatException {
  const BackupValidationException(this.code, this.message);

  final BackupValidationCode code;

  @override
  final String message;

  @override
  int? get offset => null;

  @override
  Object? get source => null;

  @override
  String toString() => message;
}

final class BackupCounts {
  const BackupCounts({required this.customers, required this.entries});

  final int customers;
  final int entries;

  Map<String, Object?> toJson() => {'customers': customers, 'entries': entries};
}

final class BackupSummary {
  const BackupSummary({required this.counts, required this.exportedAt});

  final BackupCounts counts;
  final DateTime exportedAt;

  String get displayText {
    final local = exportedAt.toLocal();
    return '${counts.customers} 位客户、${counts.entries} 笔账，'
        '备份于 ${local.month} 月 ${local.day} 日';
  }
}

final class BackupCustomer {
  const BackupCustomer({
    required this.id,
    required this.name,
    required this.note,
    required this.pinyinFull,
    required this.pinyinAbbr,
    required this.createdAt,
    required this.deletedAt,
  });

  final int id;
  final String name;
  final String note;
  final String pinyinFull;
  final String pinyinAbbr;
  final String createdAt;
  final String? deletedAt;

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'note': note,
    'pinyin_full': pinyinFull,
    'pinyin_abbr': pinyinAbbr,
    'created_at': createdAt,
    'deleted_at': deletedAt,
  };
}

final class BackupEntry {
  const BackupEntry({
    required this.id,
    required this.customerId,
    required this.kind,
    required this.business,
    required this.amountCents,
    required this.bizDate,
    required this.note,
    required this.createdAt,
    required this.updatedAt,
    required this.deletedAt,
  });

  final int id;
  final int customerId;
  final String kind;
  final String business;
  final int amountCents;
  final String bizDate;
  final String note;
  final String createdAt;
  final String updatedAt;
  final String? deletedAt;

  Map<String, Object?> toJson() => {
    'id': id,
    'customer_id': customerId,
    'kind': kind,
    'business': business,
    'amount_cents': amountCents,
    'biz_date': bizDate,
    'note': note,
    'created_at': createdAt,
    'updated_at': updatedAt,
    'deleted_at': deletedAt,
  };
}

final class BackupDayPhoto {
  const BackupDayPhoto({
    required this.id,
    required this.bizDate,
    required this.filePath,
    required this.createdAt,
    required this.deletedAt,
  });

  final int id;
  final String bizDate;
  final String filePath;
  final String createdAt;
  final String? deletedAt;

  Map<String, Object?> toJson() => {
    'id': id,
    'biz_date': bizDate,
    'file_path': filePath,
    'created_at': createdAt,
    'deleted_at': deletedAt,
  };
}

final class BackupBusiness {
  const BackupBusiness({
    required this.id,
    required this.name,
    required this.pinyinFull,
    required this.pinyinAbbr,
    required this.useCount,
    required this.lastUsed,
    required this.createdAt,
    required this.deletedAt,
  });

  final int id;
  final String name;
  final String pinyinFull;
  final String pinyinAbbr;
  final int useCount;
  final String? lastUsed;
  final String createdAt;
  final String? deletedAt;

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'pinyin_full': pinyinFull,
    'pinyin_abbr': pinyinAbbr,
    'use_count': useCount,
    'last_used': lastUsed,
    'created_at': createdAt,
    'deleted_at': deletedAt,
  };
}

final class BackupPayload {
  BackupPayload({
    required List<BackupCustomer> customers,
    required List<BackupEntry> entries,
    required Map<String, String> settings,
    required List<BackupDayPhoto> dayPhotos,
    required List<BackupBusiness> businesses,
  }) : customers = List.unmodifiable(customers),
       entries = List.unmodifiable(entries),
       settings = Map.unmodifiable(settings),
       dayPhotos = List.unmodifiable(dayPhotos),
       businesses = List.unmodifiable(businesses);

  final List<BackupCustomer> customers;
  final List<BackupEntry> entries;
  final Map<String, String> settings;
  final List<BackupDayPhoto> dayPhotos;
  final List<BackupBusiness> businesses;

  Map<String, Object?> toJson() => {
    'customers': customers.map((row) => row.toJson()).toList(growable: false),
    'entries': entries.map((row) => row.toJson()).toList(growable: false),
    'settings': settings,
    'day_photos': dayPhotos.map((row) => row.toJson()).toList(growable: false),
    'businesses': businesses.map((row) => row.toJson()).toList(growable: false),
  };
}

final class BackupDocument {
  const BackupDocument({
    required this.schemaVersion,
    required this.exportedAtText,
    required this.exportedAt,
    required this.counts,
    required this.checksum,
    required this.data,
  });

  final int schemaVersion;
  final String exportedAtText;
  final DateTime exportedAt;
  final BackupCounts counts;
  final String checksum;
  final BackupPayload data;

  BackupSummary get summary =>
      BackupSummary(counts: counts, exportedAt: exportedAt);

  Map<String, Object?> toJson() => {
    'app': 'zhangben',
    'schema_version': schemaVersion,
    'exported_at': exportedAtText,
    'counts': counts.toJson(),
    'checksum': checksum,
    'data': data.toJson(),
  };
}

final class BackupArchive {
  const BackupArchive({
    required this.fileName,
    required this.contents,
    required this.document,
  });

  final String fileName;
  final String contents;
  final BackupDocument document;

  List<int> get utf8Bytes => utf8.encode(contents);
}

final class BackupImportResult {
  const BackupImportResult({
    required this.imported,
    required this.preImportBackup,
  });

  final BackupSummary imported;
  final BackupArchive preImportBackup;
}

typedef PreImportBackupWriter = Future<void> Function(BackupArchive backup);
