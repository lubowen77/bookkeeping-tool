import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart' show OrderingTerm, Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zhangben/data/backup/backup_models.dart';
import 'package:zhangben/data/backup/backup_service.dart';
import 'package:zhangben/data/database/app_database.dart';

void main() {
  late AppDatabase db;
  late BackupService service;
  final now = DateTime(2026, 8, 7, 21, 30, 0, 0, 525);

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    service = BackupService(db, clock: () => now);
  });

  tearDown(() => db.close());

  test('导出包含账目数据与业务字典，照片只保留路径元数据', () async {
    await _seedCompleteDatabase(db);

    final archive = await service.exportDatabase();
    final root = jsonDecode(archive.contents) as Map<String, dynamic>;
    final data = root['data'] as Map<String, dynamic>;

    expect(root['app'], 'zhangben');
    expect(root['schema_version'], 1);
    expect(root['exported_at'], '2026-08-07T21:30:00+08:00');
    expect(root['counts'], {'customers': 2, 'entries': 2});
    expect(data.keys, [
      'customers',
      'entries',
      'settings',
      'day_photos',
      'businesses',
    ]);
    expect(data['customers'], hasLength(2));
    expect(data['entries'], hasLength(2));
    expect(data['settings'], {
      'font_scale': 'large',
      'last_backup': 'yesterday',
    });
    expect(data['day_photos'], hasLength(1));
    expect(data['businesses'], isNotEmpty);

    final expectedChecksum = sha256
        .convert(utf8.encode(jsonEncode(data)))
        .toString();
    expect(root['checksum'], expectedChecksum);
    expect(archive.fileName, '记账备份-20260807-2130.jzb');
    expect(utf8.decode(archive.utf8Bytes), archive.contents);

    final deletedCustomer =
        (data['customers'] as List<dynamic>)[1] as Map<String, dynamic>;
    final deletedEntry =
        (data['entries'] as List<dynamic>)[1] as Map<String, dynamic>;
    expect(deletedCustomer['deleted_at'], isNotNull);
    expect(deletedEntry['deleted_at'], isNotNull);
    expect(
      (data['day_photos'] as List<dynamic>).single['file_path'],
      '/private/day-20260807.jpg',
      reason: '仅保留照片路径元数据，不将照片本体写入 JSON',
    );
  });

  test('解析后给出客户数、流水数和备份日期摘要', () async {
    await _seedCompleteDatabase(db);
    final archive = await service.exportDatabase();

    final parsed = service.parseAndValidate(archive.contents);

    expect(parsed.counts.customers, 2);
    expect(parsed.counts.entries, 2);
    expect(parsed.summary.displayText, '2 位客户、2 笔账，备份于 8 月 7 日');
  });

  test('备份协议允许零元期初流水，但拒绝其他零元流水', () async {
    await db
        .into(db.customers)
        .insert(
          CustomersCompanion.insert(
            id: const Value(1),
            name: '零元期初客户',
            createdAt: '2026-08-07T20:00:00+08:00',
          ),
        );
    await db
        .into(db.ledgerEntries)
        .insert(
          LedgerEntriesCompanion.insert(
            id: const Value(1),
            customerId: 1,
            kind: 'initial',
            amountCents: 0,
            bizDate: '2026-08-07',
            note: const Value('期初建档'),
            createdAt: '2026-08-07T20:00:00+08:00',
            updatedAt: '2026-08-07T20:00:00+08:00',
          ),
        );

    final archive = await service.exportDatabase();
    expect(
      service
          .parseAndValidate(archive.contents)
          .data
          .entries
          .single
          .amountCents,
      0,
    );

    final root = jsonDecode(archive.contents) as Map<String, dynamic>;
    final data = root['data'] as Map<String, dynamic>;
    final entry =
        (data['entries'] as List<dynamic>).single as Map<String, dynamic>;
    entry['kind'] = 'debt';
    entry['business'] = '送货';
    root['checksum'] = BackupService.checksumForData(data);
    expect(
      () => service.parseAndValidate(jsonEncode(root)),
      throwsA(isA<BackupValidationException>()),
    );
  });

  test('任意篡改 data 内容都会被 checksum 拦截', () async {
    await _seedCompleteDatabase(db);
    final archive = await service.exportDatabase();
    final root = jsonDecode(archive.contents) as Map<String, dynamic>;
    final data = root['data'] as Map<String, dynamic>;
    final entries = data['entries'] as List<dynamic>;
    (entries.first as Map<String, dynamic>)['amount_cents'] = 999999;

    expect(
      () => service.parseAndValidate(jsonEncode(root)),
      throwsA(
        isA<BackupValidationException>().having(
          (error) => error.code,
          'code',
          BackupValidationCode.checksumMismatch,
        ),
      ),
    );
  });

  test('高于当前支持版本时明确拒绝并提示先升级 App', () async {
    await _seedCompleteDatabase(db);
    final archive = await service.exportDatabase();
    final root = jsonDecode(archive.contents) as Map<String, dynamic>;
    root['schema_version'] = 2;

    expect(
      () => service.parseAndValidate(jsonEncode(root)),
      throwsA(
        isA<BackupValidationException>()
            .having(
              (error) => error.code,
              'code',
              BackupValidationCode.newerSchema,
            )
            .having((error) => error.message, 'message', contains('先升级 App')),
      ),
    );
  });

  test('即使 checksum 合法，counts 不一致仍会拒绝', () async {
    await _seedCompleteDatabase(db);
    final archive = await service.exportDatabase();
    final root = jsonDecode(archive.contents) as Map<String, dynamic>;
    (root['counts'] as Map<String, dynamic>)['customers'] = 3;

    expect(
      () => service.parseAndValidate(jsonEncode(root)),
      throwsA(
        isA<BackupValidationException>().having(
          (error) => error.code,
          'code',
          BackupValidationCode.countsMismatch,
        ),
      ),
    );
  });

  test('导入前生成当前库预备份，确认后四表全量替换', () async {
    await _seedCompleteDatabase(db);
    final incomingArchive = await service.exportDatabase();

    await _clearDatabase(db);
    await db
        .into(db.customers)
        .insert(
          CustomersCompanion.insert(
            id: const Value(91),
            name: '当前本地客户',
            createdAt: '2026-08-08T07:00:00+08:00',
          ),
        );
    await db
        .into(db.appSettings)
        .insert(
          AppSettingsCompanion.insert(
            key: 'only_current',
            value: 'keep-in-pre',
          ),
        );

    BackupArchive? writtenPreImport;
    final result = await service.importReplacing(
      incomingArchive.contents,
      writePreImportBackup: (backup) async {
        writtenPreImport = backup;
      },
    );

    expect(writtenPreImport, isNotNull);
    expect(writtenPreImport!.fileName, '导入前备份-20260807-2130.jzb');
    final preImport = service.parseAndValidate(writtenPreImport!.contents);
    expect(preImport.data.customers.single.id, 91);
    expect(preImport.data.customers.single.name, '当前本地客户');
    expect(preImport.data.settings, {'only_current': 'keep-in-pre'});

    final customers = await (db.select(
      db.customers,
    )..orderBy([(row) => OrderingTerm.asc(row.id)])).get();
    final entries = await (db.select(
      db.ledgerEntries,
    )..orderBy([(row) => OrderingTerm.asc(row.id)])).get();
    final settings = await db.select(db.appSettings).get();
    final dayPhotos = await db.select(db.dayPhotos).get();
    expect(customers.map((row) => row.id), [7, 8]);
    expect(customers.map((row) => row.name), ['张老三', '回收站客户']);
    expect(entries.map((row) => row.id), [31, 32]);
    expect(settings.map((row) => row.key).toSet(), {
      'font_scale',
      'last_backup',
    });
    expect(dayPhotos.single.id, 51);
    expect(result.imported.displayText, '2 位客户、2 笔账，备份于 8 月 7 日');
  });

  test('导入前备份写入失败时，不会清空或覆盖当前库', () async {
    await _seedCompleteDatabase(db);
    final incomingArchive = await service.exportDatabase();

    await _clearDatabase(db);
    await db
        .into(db.customers)
        .insert(
          CustomersCompanion.insert(
            id: const Value(91),
            name: '不能丢的本地客户',
            createdAt: '2026-08-08T07:00:00+08:00',
          ),
        );

    await expectLater(
      service.importReplacing(
        incomingArchive.contents,
        writePreImportBackup: (_) async => throw StateError('磁盘已满'),
      ),
      throwsStateError,
    );
    final customers = await db.select(db.customers).get();
    expect(customers.single.id, 91);
    expect(customers.single.name, '不能丢的本地客户');
  });

  test('引用不存在客户的流水会在预备份和替换前被拦截', () async {
    await _seedCompleteDatabase(db);
    final archive = await service.exportDatabase();
    final root = jsonDecode(archive.contents) as Map<String, dynamic>;
    final data = root['data'] as Map<String, dynamic>;
    final entries = data['entries'] as List<dynamic>;
    (entries.first as Map<String, dynamic>)['customer_id'] = 123456;
    root['checksum'] = BackupService.checksumForData(data);
    var writerCalled = false;

    await expectLater(
      service.importReplacing(
        jsonEncode(root),
        writePreImportBackup: (_) async {
          writerCalled = true;
        },
      ),
      throwsA(
        isA<BackupValidationException>().having(
          (error) => error.code,
          'code',
          BackupValidationCode.invalidStructure,
        ),
      ),
    );
    expect(writerCalled, isFalse);
    expect(await db.select(db.customers).get(), hasLength(2));
  });

  test('旧 v1 备份没有 businesses 也能导入并从设置和历史流水补齐', () async {
    await _seedCompleteDatabase(db);
    final archive = await service.exportDatabase();
    final root = jsonDecode(archive.contents) as Map<String, dynamic>;
    final data = root['data'] as Map<String, dynamic>;
    data.remove('businesses');
    data['settings'] = <String, String>{
      ...(data['settings'] as Map<String, dynamic>).cast<String, String>(),
      'business_buttons': '["送货","运费"]',
    };
    root['checksum'] = BackupService.checksumForData(data);

    await service.importReplacing(
      jsonEncode(root),
      writePreImportBackup: (_) async {},
    );

    final businesses = await db.select(db.businesses).get();
    expect(businesses.map((row) => row.name).toSet(), {'送货', '运费'});
    expect(businesses.singleWhere((row) => row.name == '送货').useCount, 1);
  });
}

Future<void> _seedCompleteDatabase(AppDatabase db) async {
  const createdAt = '2026-08-07T20:00:00+08:00';
  const deletedAt = '2026-08-07T20:20:00+08:00';
  await db.batch((batch) {
    batch.insertAll(db.customers, [
      CustomersCompanion.insert(
        id: const Value(7),
        name: '张老三',
        note: const Value('东村'),
        pinyinFull: const Value('zhanglaosan'),
        pinyinAbbr: const Value('zls'),
        createdAt: createdAt,
      ),
      CustomersCompanion.insert(
        id: const Value(8),
        name: '回收站客户',
        note: const Value('已删除'),
        pinyinFull: const Value('huishouzhan'),
        pinyinAbbr: const Value('hsz'),
        createdAt: createdAt,
        deletedAt: const Value(deletedAt),
      ),
    ]);
    batch.insertAll(db.ledgerEntries, [
      LedgerEntriesCompanion.insert(
        id: const Value(31),
        customerId: 7,
        kind: 'debt',
        business: const Value('送货'),
        amountCents: 35000,
        bizDate: '2026-08-07',
        note: const Value('两箱'),
        createdAt: createdAt,
        updatedAt: createdAt,
      ),
      LedgerEntriesCompanion.insert(
        id: const Value(32),
        customerId: 8,
        kind: 'payment',
        amountCents: 10000,
        bizDate: '2026-08-07',
        createdAt: createdAt,
        updatedAt: deletedAt,
        deletedAt: const Value(deletedAt),
      ),
    ]);
    batch.insertAll(db.appSettings, [
      AppSettingsCompanion.insert(key: 'font_scale', value: 'large'),
      AppSettingsCompanion.insert(key: 'last_backup', value: 'yesterday'),
    ]);
    batch.insert(
      db.dayPhotos,
      DayPhotosCompanion.insert(
        id: const Value(51),
        bizDate: '2026-08-07',
        filePath: '/private/day-20260807.jpg',
        createdAt: createdAt,
      ),
    );
  });
}

Future<void> _clearDatabase(AppDatabase db) async {
  await db.delete(db.businesses).go();
  await db.delete(db.dayPhotos).go();
  await db.delete(db.appSettings).go();
  await db.delete(db.ledgerEntries).go();
  await db.delete(db.customers).go();
}
