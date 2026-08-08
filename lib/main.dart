import 'dart:async';

import 'package:flutter/material.dart';

import 'app/app_controller.dart';
import 'app/zhangben_app.dart';
import 'data/backup/backup_coordinator.dart';
import 'data/backup/backup_service.dart';
import 'data/database/app_database.dart';
import 'data/repositories/ledger_repository.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final database = AppDatabase();
  final backup = BackupCoordinator(BackupService(database));
  await backup.initializeIntentHandling();
  final controller = AppController(
    LedgerRepository(database),
    backupCoordinator: backup,
  );
  await controller.initialize();
  runApp(ZhangbenApp(controller: controller));
  unawaited(backup.scheduleWeeklyReminder().onError((_, _) => false));
  unawaited(
    backup
        .runDailyBackupIfNeeded()
        .then((_) => controller.dataChanged())
        .onError((_, _) => null),
  );
}
