import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

import '../../core/local_time.dart';
import '../../core/pinyin.dart';

part 'app_database.g.dart';

@DataClassName('CustomerRow')
class Customers extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text()();
  TextColumn get note => text().withDefault(const Constant(''))();
  TextColumn get pinyinFull => text().withDefault(const Constant(''))();
  TextColumn get pinyinAbbr => text().withDefault(const Constant(''))();
  TextColumn get createdAt => text()();
  TextColumn get deletedAt => text().nullable()();
}

@DataClassName('LedgerEntryRow')
@TableIndex(name: 'idx_entries_customer', columns: {#customerId, #deletedAt})
@TableIndex(name: 'idx_entries_date', columns: {#bizDate, #deletedAt})
class LedgerEntries extends Table {
  @override
  String get tableName => 'entries';

  IntColumn get id => integer().autoIncrement()();
  IntColumn get customerId => integer().references(Customers, #id)();

  TextColumn get kind => text().check(
    // ignore: recursive_getters
    kind.isIn(const ['initial', 'debt', 'payment', 'discount']),
  )();

  TextColumn get business => text().withDefault(const Constant(''))();

  IntColumn get amountCents => integer().check(
    // ignore: recursive_getters
    amountCents.isBiggerThanValue(0) |
        // ignore: recursive_getters
        (kind.equals('initial') & amountCents.equals(0)),
  )();

  TextColumn get bizDate => text()();
  TextColumn get note => text().withDefault(const Constant(''))();
  TextColumn get createdAt => text()();
  TextColumn get updatedAt => text()();
  TextColumn get deletedAt => text().nullable()();
}

@DataClassName('SettingRow')
class AppSettings extends Table {
  @override
  String get tableName => 'settings';

  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column<Object>> get primaryKey => {key};
}

@DataClassName('DayPhotoRow')
class DayPhotos extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get bizDate => text()();
  TextColumn get filePath => text()();
  TextColumn get createdAt => text()();
  TextColumn get deletedAt => text().nullable()();
}

@DataClassName('BusinessRow')
@TableIndex(name: 'idx_businesses_active_name', columns: {#deletedAt, #name})
class Businesses extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text()();
  TextColumn get pinyinFull => text().withDefault(const Constant(''))();
  TextColumn get pinyinAbbr => text().withDefault(const Constant(''))();
  IntColumn get useCount => integer().withDefault(const Constant(0))();
  TextColumn get lastUsed => text().nullable()();
  TextColumn get createdAt => text()();
  TextColumn get deletedAt => text().nullable()();
}

@DriftDatabase(
  tables: [Customers, LedgerEntries, AppSettings, DayPhotos, Businesses],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(driftDatabase(name: 'zhangben'));

  AppDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => 3;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (migrator) async {
      await migrator.createAll();
      await _seedBusinessesFromV1();
    },
    onUpgrade: (migrator, from, to) async {
      if (from < 2) {
        await migrator.createTable(businesses);
        await _seedBusinessesFromV1();
      }
      if (from < 3) {
        await customStatement(
          "UPDATE entries SET note = '' "
          "WHERE kind = 'initial' AND note = '期初建档'",
        );
      }
    },
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );

  static const _v1DefaultBusinesses = ['送货', '拉货', '加工', '材料', '人工'];

  /// 导入旧 v1 备份后补齐业务字典。已有字典时幂等返回。
  Future<void> ensureBusinessDictionarySeeded() => _seedBusinessesFromV1();

  /// v1.5 业务字典的唯一初始化入口。既用于 1→2 schema 迁移，
  /// 也用于新库创建。只读 v1 设置和流水，不改写任何旧表。
  Future<void> _seedBusinessesFromV1() async {
    final existing = await customSelect(
      'SELECT COUNT(*) AS n FROM businesses',
    ).getSingle();
    if (existing.read<int>('n') > 0) return;

    final configured = <String>[];
    final setting = await customSelect(
      'SELECT value FROM settings WHERE key = ?',
      variables: [Variable.withString('business_buttons')],
    ).getSingleOrNull();
    if (setting != null) {
      try {
        final decoded = jsonDecode(setting.read<String>('value'));
        if (decoded is List<dynamic>) {
          configured.addAll(decoded.whereType<String>());
        }
      } on FormatException {
        // v1 设置损坏不影响账目升级，下方退回默认按钮。
      }
    }
    final cleanConfigured = configured
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toSet()
        .toList();
    if (cleanConfigured.isEmpty) cleanConfigured.addAll(_v1DefaultBusinesses);

    final history = await customSelect('''
      SELECT TRIM(business) AS name,
             COUNT(*) AS use_count,
             MAX(created_at) AS last_used
      FROM entries
      WHERE kind = 'debt' AND deleted_at IS NULL AND TRIM(business) <> ''
      GROUP BY TRIM(business)
      ORDER BY MIN(id)
    ''').get();
    final historyByName = <String, ({int count, String? lastUsed})>{
      for (final row in history)
        row.read<String>('name'): (
          count: row.read<int>('use_count'),
          lastUsed: row.readNullable<String>('last_used'),
        ),
    };
    final names = <String>{...cleanConfigured, ...historyByName.keys};
    final now = localIsoTimestamp(DateTime.now());
    await batch((batch) {
      for (final name in names) {
        final pinyin = PinyinIndex.fromName(name);
        final usage = historyByName[name];
        batch.insert(
          businesses,
          BusinessesCompanion.insert(
            name: name,
            pinyinFull: Value(pinyin.full),
            pinyinAbbr: Value(pinyin.abbr),
            useCount: Value(usage?.count ?? 0),
            lastUsed: Value(usage?.lastUsed),
            createdAt: now,
          ),
        );
      }
    });
  }
}
