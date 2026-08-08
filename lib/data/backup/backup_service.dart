import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';

import '../../core/local_time.dart';
import '../database/app_database.dart';
import 'backup_models.dart';

final class BackupService {
  BackupService(this.db, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  static const int supportedSchemaVersion = 1;

  final AppDatabase db;
  final DateTime Function() _clock;

  Future<BackupArchive> exportDatabase({String fileNamePrefix = '记账备份'}) async {
    // 所有数据表必须来自同一个 SQLite 只读快照，避免备份期间恰好写账时
    // 导出跨时点的客户、流水或设置组合。
    final payload = await db.transaction(() async {
      final customers = await (db.select(
        db.customers,
      )..orderBy([(row) => OrderingTerm.asc(row.id)])).get();
      final entries = await (db.select(
        db.ledgerEntries,
      )..orderBy([(row) => OrderingTerm.asc(row.id)])).get();
      final settings = await (db.select(
        db.appSettings,
      )..orderBy([(row) => OrderingTerm.asc(row.key)])).get();
      final dayPhotos = await (db.select(
        db.dayPhotos,
      )..orderBy([(row) => OrderingTerm.asc(row.id)])).get();
      final businesses = await (db.select(
        db.businesses,
      )..orderBy([(row) => OrderingTerm.asc(row.id)])).get();

      return BackupPayload(
        customers: customers
            .map(
              (row) => BackupCustomer(
                id: row.id,
                name: row.name,
                note: row.note,
                pinyinFull: row.pinyinFull,
                pinyinAbbr: row.pinyinAbbr,
                createdAt: row.createdAt,
                deletedAt: row.deletedAt,
              ),
            )
            .toList(growable: false),
        entries: entries
            .map(
              (row) => BackupEntry(
                id: row.id,
                customerId: row.customerId,
                kind: row.kind,
                business: row.business,
                amountCents: row.amountCents,
                bizDate: row.bizDate,
                note: row.note,
                createdAt: row.createdAt,
                updatedAt: row.updatedAt,
                deletedAt: row.deletedAt,
              ),
            )
            .toList(growable: false),
        settings: {for (final row in settings) row.key: row.value},
        dayPhotos: dayPhotos
            .map(
              (row) => BackupDayPhoto(
                id: row.id,
                bizDate: row.bizDate,
                filePath: row.filePath,
                createdAt: row.createdAt,
                deletedAt: row.deletedAt,
              ),
            )
            .toList(growable: false),
        businesses: businesses
            .map(
              (row) => BackupBusiness(
                id: row.id,
                name: row.name,
                pinyinFull: row.pinyinFull,
                pinyinAbbr: row.pinyinAbbr,
                useCount: row.useCount,
                lastUsed: row.lastUsed,
                createdAt: row.createdAt,
                deletedAt: row.deletedAt,
              ),
            )
            .toList(growable: false),
      );
    });

    final now = _clock().toLocal();
    // 备份协议使用秒级 ISO8601；不把运行时微秒带进文件格式。
    final exportedAtText = localIsoTimestamp(now.copyWith(microsecond: 0));
    final checksum = checksumForData(payload.toJson());
    final document = BackupDocument(
      schemaVersion: supportedSchemaVersion,
      exportedAtText: exportedAtText,
      exportedAt: DateTime.parse(exportedAtText),
      counts: BackupCounts(
        customers: payload.customers.length,
        entries: payload.entries.length,
      ),
      checksum: checksum,
      data: payload,
    );
    return BackupArchive(
      fileName: '$fileNamePrefix-${_fileTimestamp(now)}.jzb',
      contents: jsonEncode(document.toJson()),
      document: document,
    );
  }

  BackupDocument parseAndValidate(String contents) {
    final Object? decoded;
    try {
      decoded = jsonDecode(contents);
    } on FormatException {
      throw const BackupValidationException(
        BackupValidationCode.invalidJson,
        '备份文件不是有效的 JSON',
      );
    }
    if (decoded is! Map<String, dynamic>) {
      throw _invalidStructure('备份文件顶层必须是对象');
    }

    final app = decoded['app'];
    if (app != 'zhangben') {
      throw const BackupValidationException(
        BackupValidationCode.invalidApp,
        '这不是“记账本”的备份文件',
      );
    }
    final schemaVersion = _requiredInt(
      decoded,
      'schema_version',
      'schema_version',
    );
    if (schemaVersion > supportedSchemaVersion) {
      throw const BackupValidationException(
        BackupValidationCode.newerSchema,
        '备份由更新版本生成，请先升级 App 再导入',
      );
    }
    if (schemaVersion != supportedSchemaVersion) {
      throw BackupValidationException(
        BackupValidationCode.unsupportedSchema,
        '不支持的备份版本：$schemaVersion',
      );
    }

    final exportedAtText = _requiredString(
      decoded,
      'exported_at',
      'exported_at',
    );
    final exportedAt = DateTime.tryParse(exportedAtText);
    if (exportedAt == null || !_isOffsetIsoTimestamp(exportedAtText)) {
      throw _invalidStructure('exported_at 格式不正确');
    }

    final countsJson = _requiredObject(decoded, 'counts', 'counts');
    final counts = BackupCounts(
      customers: _requiredNonNegativeInt(
        countsJson,
        'customers',
        'counts.customers',
      ),
      entries: _requiredNonNegativeInt(countsJson, 'entries', 'counts.entries'),
    );
    final checksum = _requiredString(
      decoded,
      'checksum',
      'checksum',
    ).toLowerCase();
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(checksum)) {
      throw _invalidStructure('checksum 格式不正确');
    }

    final dataJson = _requiredObject(decoded, 'data', 'data');
    final actualChecksum = checksumForData(dataJson);
    if (actualChecksum != checksum) {
      throw const BackupValidationException(
        BackupValidationCode.checksumMismatch,
        '备份文件已损坏或被修改，checksum 校验未通过',
      );
    }

    final payload = _parsePayload(dataJson);
    if (counts.customers != payload.customers.length ||
        counts.entries != payload.entries.length) {
      throw const BackupValidationException(
        BackupValidationCode.countsMismatch,
        '备份摘要数量与实际数据不一致',
      );
    }

    return BackupDocument(
      schemaVersion: schemaVersion,
      exportedAtText: exportedAtText,
      exportedAt: exportedAt,
      counts: counts,
      checksum: checksum,
      data: payload,
    );
  }

  Future<BackupImportResult> importReplacing(
    String contents, {
    required PreImportBackupWriter writePreImportBackup,
  }) async {
    final incoming = parseAndValidate(contents);

    final preImportBackup = await exportDatabase(fileNamePrefix: '导入前备份');
    await writePreImportBackup(preImportBackup);

    await db.transaction(() async {
      await db.delete(db.businesses).go();
      await db.delete(db.dayPhotos).go();
      await db.delete(db.appSettings).go();
      await db.delete(db.ledgerEntries).go();
      await db.delete(db.customers).go();

      for (final row in incoming.data.customers) {
        await db
            .into(db.customers)
            .insert(
              CustomersCompanion.insert(
                id: Value(row.id),
                name: row.name,
                note: Value(row.note),
                pinyinFull: Value(row.pinyinFull),
                pinyinAbbr: Value(row.pinyinAbbr),
                createdAt: row.createdAt,
                deletedAt: Value(row.deletedAt),
              ),
            );
      }
      for (final row in incoming.data.entries) {
        await db
            .into(db.ledgerEntries)
            .insert(
              LedgerEntriesCompanion.insert(
                id: Value(row.id),
                customerId: row.customerId,
                kind: row.kind,
                business: Value(row.business),
                amountCents: row.amountCents,
                bizDate: row.bizDate,
                note: Value(row.note),
                createdAt: row.createdAt,
                updatedAt: row.updatedAt,
                deletedAt: Value(row.deletedAt),
              ),
            );
      }
      for (final entry in incoming.data.settings.entries) {
        await db
            .into(db.appSettings)
            .insert(
              AppSettingsCompanion.insert(key: entry.key, value: entry.value),
            );
      }
      for (final row in incoming.data.dayPhotos) {
        await db
            .into(db.dayPhotos)
            .insert(
              DayPhotosCompanion.insert(
                id: Value(row.id),
                bizDate: row.bizDate,
                filePath: row.filePath,
                createdAt: row.createdAt,
                deletedAt: Value(row.deletedAt),
              ),
            );
      }
      for (final row in incoming.data.businesses) {
        await db
            .into(db.businesses)
            .insert(
              BusinessesCompanion.insert(
                id: Value(row.id),
                name: row.name,
                pinyinFull: Value(row.pinyinFull),
                pinyinAbbr: Value(row.pinyinAbbr),
                useCount: Value(row.useCount),
                lastUsed: Value(row.lastUsed),
                createdAt: row.createdAt,
                deletedAt: Value(row.deletedAt),
              ),
            );
      }
      if (incoming.data.businesses.isEmpty) {
        await db.ensureBusinessDictionarySeeded();
      }
    });

    return BackupImportResult(
      imported: incoming.summary,
      preImportBackup: preImportBackup,
    );
  }

  static String checksumForData(Map<String, Object?> data) {
    return sha256.convert(utf8.encode(jsonEncode(data))).toString();
  }

  static String _fileTimestamp(DateTime value) {
    return '${value.year.toString().padLeft(4, '0')}'
        '${value.month.toString().padLeft(2, '0')}'
        '${value.day.toString().padLeft(2, '0')}-'
        '${value.hour.toString().padLeft(2, '0')}'
        '${value.minute.toString().padLeft(2, '0')}';
  }

  static BackupPayload _parsePayload(Map<String, dynamic> data) {
    final customerItems = _requiredList(data, 'customers', 'data.customers');
    final entryItems = _requiredList(data, 'entries', 'data.entries');
    final settingsJson = _requiredObject(data, 'settings', 'data.settings');
    final dayPhotoItems = _requiredList(data, 'day_photos', 'data.day_photos');
    // v1 备份没有 businesses；v1.5 导入时从设置+历史流水补齐。
    final businessItems = data.containsKey('businesses')
        ? _requiredList(data, 'businesses', 'data.businesses')
        : const <dynamic>[];

    final customers = <BackupCustomer>[];
    final customerIds = <int>{};
    for (var index = 0; index < customerItems.length; index += 1) {
      final path = 'data.customers[$index]';
      final row = _asObject(customerItems[index], path);
      final id = _requiredPositiveInt(row, 'id', '$path.id');
      if (!customerIds.add(id)) {
        throw _invalidStructure('$path.id 重复：$id');
      }
      final name = _requiredString(row, 'name', '$path.name');
      if (name.trim().isEmpty) {
        throw _invalidStructure('$path.name 不能为空');
      }
      customers.add(
        BackupCustomer(
          id: id,
          name: name,
          note: _requiredString(row, 'note', '$path.note'),
          pinyinFull: _requiredString(row, 'pinyin_full', '$path.pinyin_full'),
          pinyinAbbr: _requiredString(row, 'pinyin_abbr', '$path.pinyin_abbr'),
          createdAt: _requiredTimestamp(row, 'created_at', '$path.created_at'),
          deletedAt: _nullableTimestamp(row, 'deleted_at', '$path.deleted_at'),
        ),
      );
    }

    final entries = <BackupEntry>[];
    final entryIds = <int>{};
    const kinds = {'initial', 'debt', 'payment', 'discount'};
    for (var index = 0; index < entryItems.length; index += 1) {
      final path = 'data.entries[$index]';
      final row = _asObject(entryItems[index], path);
      final id = _requiredPositiveInt(row, 'id', '$path.id');
      if (!entryIds.add(id)) {
        throw _invalidStructure('$path.id 重复：$id');
      }
      final customerId = _requiredPositiveInt(
        row,
        'customer_id',
        '$path.customer_id',
      );
      if (!customerIds.contains(customerId)) {
        throw _invalidStructure('$path.customer_id 引用了不存在的客户');
      }
      final kind = _requiredString(row, 'kind', '$path.kind');
      if (!kinds.contains(kind)) {
        throw _invalidStructure('$path.kind 不合法：$kind');
      }
      final business = _requiredString(row, 'business', '$path.business');
      if (kind == 'debt' && business.trim().isEmpty) {
        throw _invalidStructure('$path.business 记账业务不能为空');
      }
      final bizDate = _requiredString(row, 'biz_date', '$path.biz_date');
      if (!_isBusinessDate(bizDate)) {
        throw _invalidStructure('$path.biz_date 格式不正确');
      }
      final amountCents = _requiredNonNegativeInt(
        row,
        'amount_cents',
        '$path.amount_cents',
      );
      if (amountCents == 0 && kind != 'initial') {
        throw _invalidStructure('$path.amount_cents 只有期初流水可以为 0');
      }
      entries.add(
        BackupEntry(
          id: id,
          customerId: customerId,
          kind: kind,
          business: business,
          amountCents: amountCents,
          bizDate: bizDate,
          note: _requiredString(row, 'note', '$path.note'),
          createdAt: _requiredTimestamp(row, 'created_at', '$path.created_at'),
          updatedAt: _requiredTimestamp(row, 'updated_at', '$path.updated_at'),
          deletedAt: _nullableTimestamp(row, 'deleted_at', '$path.deleted_at'),
        ),
      );
    }

    final settings = <String, String>{};
    for (final entry in settingsJson.entries) {
      final value = entry.value;
      if (value is! String) {
        throw _invalidStructure('data.settings.${entry.key} 必须是字符串');
      }
      settings[entry.key] = value;
    }

    final dayPhotos = <BackupDayPhoto>[];
    final dayPhotoIds = <int>{};
    for (var index = 0; index < dayPhotoItems.length; index += 1) {
      final path = 'data.day_photos[$index]';
      final row = _asObject(dayPhotoItems[index], path);
      final id = _requiredPositiveInt(row, 'id', '$path.id');
      if (!dayPhotoIds.add(id)) {
        throw _invalidStructure('$path.id 重复：$id');
      }
      final bizDate = _requiredString(row, 'biz_date', '$path.biz_date');
      if (!_isBusinessDate(bizDate)) {
        throw _invalidStructure('$path.biz_date 格式不正确');
      }
      dayPhotos.add(
        BackupDayPhoto(
          id: id,
          bizDate: bizDate,
          filePath: _requiredString(row, 'file_path', '$path.file_path'),
          createdAt: _requiredTimestamp(row, 'created_at', '$path.created_at'),
          deletedAt: _nullableTimestamp(row, 'deleted_at', '$path.deleted_at'),
        ),
      );
    }

    final businesses = <BackupBusiness>[];
    final businessIds = <int>{};
    for (var index = 0; index < businessItems.length; index += 1) {
      final path = 'data.businesses[$index]';
      final row = _asObject(businessItems[index], path);
      final id = _requiredPositiveInt(row, 'id', '$path.id');
      if (!businessIds.add(id)) {
        throw _invalidStructure('$path.id 重复：$id');
      }
      final name = _requiredString(row, 'name', '$path.name');
      if (name.trim().isEmpty) throw _invalidStructure('$path.name 不能为空');
      final lastUsed = row['last_used'];
      if (lastUsed != null &&
          (lastUsed is! String || DateTime.tryParse(lastUsed) == null)) {
        throw _invalidStructure('$path.last_used 必须是 null 或有效时间');
      }
      businesses.add(
        BackupBusiness(
          id: id,
          name: name,
          pinyinFull: _requiredString(row, 'pinyin_full', '$path.pinyin_full'),
          pinyinAbbr: _requiredString(row, 'pinyin_abbr', '$path.pinyin_abbr'),
          useCount: _requiredNonNegativeInt(
            row,
            'use_count',
            '$path.use_count',
          ),
          lastUsed: lastUsed as String?,
          createdAt: _requiredTimestamp(row, 'created_at', '$path.created_at'),
          deletedAt: _nullableTimestamp(row, 'deleted_at', '$path.deleted_at'),
        ),
      );
    }

    return BackupPayload(
      customers: customers,
      entries: entries,
      settings: settings,
      dayPhotos: dayPhotos,
      businesses: businesses,
    );
  }

  static Map<String, dynamic> _requiredObject(
    Map<String, dynamic> parent,
    String key,
    String path,
  ) {
    return _asObject(parent[key], path);
  }

  static Map<String, dynamic> _asObject(Object? value, String path) {
    if (value is! Map<String, dynamic>) {
      throw _invalidStructure('$path 必须是对象');
    }
    return value;
  }

  static List<dynamic> _requiredList(
    Map<String, dynamic> parent,
    String key,
    String path,
  ) {
    final value = parent[key];
    if (value is! List<dynamic>) {
      throw _invalidStructure('$path 必须是数组');
    }
    return value;
  }

  static String _requiredString(
    Map<String, dynamic> parent,
    String key,
    String path,
  ) {
    final value = parent[key];
    if (value is! String) {
      throw _invalidStructure('$path 必须是字符串');
    }
    return value;
  }

  static int _requiredInt(
    Map<String, dynamic> parent,
    String key,
    String path,
  ) {
    final value = parent[key];
    if (value is! int) {
      throw _invalidStructure('$path 必须是整数');
    }
    return value;
  }

  static int _requiredPositiveInt(
    Map<String, dynamic> parent,
    String key,
    String path,
  ) {
    final value = _requiredInt(parent, key, path);
    if (value <= 0) {
      throw _invalidStructure('$path 必须大于 0');
    }
    return value;
  }

  static int _requiredNonNegativeInt(
    Map<String, dynamic> parent,
    String key,
    String path,
  ) {
    final value = _requiredInt(parent, key, path);
    if (value < 0) {
      throw _invalidStructure('$path 不能小于 0');
    }
    return value;
  }

  static String _requiredTimestamp(
    Map<String, dynamic> parent,
    String key,
    String path,
  ) {
    final value = _requiredString(parent, key, path);
    if (DateTime.tryParse(value) == null) {
      throw _invalidStructure('$path 时间格式不正确');
    }
    return value;
  }

  static String? _nullableTimestamp(
    Map<String, dynamic> parent,
    String key,
    String path,
  ) {
    final value = parent[key];
    if (value == null) return null;
    if (value is! String || DateTime.tryParse(value) == null) {
      throw _invalidStructure('$path 必须是 null 或有效时间');
    }
    return value;
  }

  static bool _isOffsetIsoTimestamp(String value) {
    return RegExp(
      r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:Z|[+-]\d{2}:\d{2})$',
    ).hasMatch(value);
  }

  static bool _isBusinessDate(String value) {
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) return false;
    final parsed = DateTime.tryParse(value);
    return parsed != null && businessDateOf(parsed) == value;
  }

  static BackupValidationException _invalidStructure(String message) {
    return BackupValidationException(
      BackupValidationCode.invalidStructure,
      '备份数据格式不正确：$message',
    );
  }
}
