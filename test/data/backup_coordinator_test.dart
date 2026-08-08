import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zhangben/data/backup/backup_coordinator.dart';
import 'package:zhangben/data/backup/backup_service.dart';
import 'package:zhangben/data/database/app_database.dart';
import 'package:zhangben/data/repositories/ledger_repository.dart';
import 'package:zhangben/domain/ledger_models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('连续生成 65 份私有备份时只保留最近 60 份', () async {
    const platform = MethodChannel('zhangben/platform');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(platform, (call) async {
          if (call.method == 'ensurePublicBackupPermission') return true;
          if (call.method == 'writePublicBackup') return 'content://backup';
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(platform, null),
    );
    final temporary = await Directory.systemTemp.createTemp(
      'zhangben-backup-retention-',
    );
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    addTearDown(() => temporary.delete(recursive: true));
    final repository = LedgerRepository(database);
    final customer = await repository.addCustomer(name: '备份保留测试');
    await repository.addEntry(
      customerId: customer.id,
      kind: EntryKind.debt,
      business: '送货',
      amountCents: 100,
      bizDate: '2026-08-08',
    );
    var exportIndex = 0;
    final base = DateTime(2026, 8, 8, 2);
    final service = BackupService(
      database,
      clock: () => base.add(Duration(minutes: exportIndex++)),
    );
    final coordinator = BackupCoordinator(
      service,
      clock: () => base,
      documentsDirectoryProvider: () async => temporary,
    );
    addTearDown(coordinator.dispose);

    for (var index = 0; index < 65; index++) {
      final archive = await service.exportDatabase(fileNamePrefix: '保留测试');
      await coordinator.persistArchive(archive);
    }

    final files = Directory('${temporary.path}/backups')
        .listSync()
        .whereType<File>()
        .where((file) => file.path.endsWith('.jzb'))
        .toList();
    expect(files, hasLength(60));
    expect(files.every((file) => file.lengthSync() > 0), isTrue);
  });
}
