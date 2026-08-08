import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/backup/backup_coordinator.dart';
import '../data/backup/backup_service.dart';
import '../data/database/app_database.dart';
import '../data/photos/day_photo_service.dart';
import '../data/repositories/ledger_repository.dart';

enum AppFontSize {
  standard('std', 1),
  large('big', 1.15),
  extraLarge('huge', 1.3);

  const AppFontSize(this.storageValue, this.scale);

  final String storageValue;
  final double scale;

  static AppFontSize fromStorage(String? value) => values.firstWhere(
    (item) => item.storageValue == value,
    orElse: () => standard,
  );
}

final class AppController extends ChangeNotifier {
  AppController(
    this.repository, {
    BackupCoordinator? backupCoordinator,
    DayPhotoService? dayPhotoService,
  }) : backup =
           backupCoordinator ?? BackupCoordinator(BackupService(repository.db)),
       photos = dayPhotoService ?? DayPhotoService(repository);

  final LedgerRepository repository;
  final BackupCoordinator backup;
  final DayPhotoService photos;
  int tabIndex = 0;
  int revision = 0;
  AppFontSize fontSize = AppFontSize.standard;
  CustomerRow? recordCustomer;

  Future<void> initialize() async {
    fontSize = AppFontSize.standard;
    fontSize = AppFontSize.fromStorage(
      await repository.getSetting('font_size'),
    );
  }

  Future<void> reloadAfterImport() async {
    recordCustomer = null;
    await initialize();
    dataChanged();
  }

  void selectTab(int index) {
    tabIndex = index;
    notifyListeners();
  }

  void prepareDebtFor(CustomerRow customer) {
    recordCustomer = customer;
    tabIndex = 0;
    notifyListeners();
  }

  void setRecordCustomer(CustomerRow? customer) {
    recordCustomer = customer;
    notifyListeners();
  }

  void dataChanged() {
    revision++;
    notifyListeners();
  }

  Future<void> setFontSize(AppFontSize value) async {
    fontSize = value;
    await repository.setSetting('font_size', value.storageValue);
    notifyListeners();
  }

  @override
  void dispose() {
    unawaited(backup.dispose());
    repository.db.close();
    super.dispose();
  }
}
