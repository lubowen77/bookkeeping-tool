import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/local_time.dart';
import '../database/app_database.dart';
import 'backup_models.dart';
import 'backup_service.dart';

final class WrittenBackup {
  const WrittenBackup({
    required this.archive,
    required this.privateFile,
    required this.publicLocation,
  });

  final BackupArchive archive;
  final File privateFile;
  final String? publicLocation;
}

final class PickedBackup {
  const PickedBackup({required this.name, required this.contents});

  final String name;
  final String contents;
}

typedef BackupDirectoryProvider = Future<Directory> Function();

final class BackupCoordinator {
  BackupCoordinator(
    this.service, {
    DateTime Function()? clock,
    BackupDirectoryProvider? documentsDirectoryProvider,
  }) : _clock = clock ?? DateTime.now,
       _documentsDirectoryProvider =
           documentsDirectoryProvider ?? getApplicationDocumentsDirectory;

  static const _platform = MethodChannel('zhangben/platform');
  static const _lastBackupKey = 'last_backup_at';
  static const _lastBackupPrivatePathKey = 'last_backup_private_path';

  final BackupService service;
  final DateTime Function() _clock;
  final BackupDirectoryProvider _documentsDirectoryProvider;
  final _incomingUris = StreamController<String>.broadcast();
  String? _initialUri;

  Stream<String> get incomingUris => _incomingUris.stream;

  Future<void> initializeIntentHandling() async {
    _platform.setMethodCallHandler((call) async {
      if (call.method == 'backupUri' && call.arguments is String) {
        _incomingUris.add(call.arguments as String);
      }
    });
    final initial = await _platform.invokeMethod<String>('getInitialBackupUri');
    if (initial != null && initial.isNotEmpty) _initialUri = initial;
  }

  String? takeInitialUri() {
    final value = _initialUri;
    _initialUri = null;
    return value;
  }

  Future<WrittenBackup?> runDailyBackupIfNeeded() async {
    final lastText = await _setting(_lastBackupKey);
    final last = lastText == null
        ? null
        : DateTime.tryParse(lastText)?.toLocal();
    final now = _clock().toLocal();
    if (last != null && businessDateOf(last) == businessDateOf(now)) {
      return null;
    }
    return createBackup();
  }

  Future<WrittenBackup> createBackup({String fileNamePrefix = '记账备份'}) async {
    final archive = await service.exportDatabase(
      fileNamePrefix: fileNamePrefix,
    );
    return persistArchive(archive);
  }

  Future<WrittenBackup> persistArchive(BackupArchive archive) async {
    final privateFile = await _writePrivate(archive);
    String? publicLocation;
    final allowed = await _platform.invokeMethod<bool>(
      'ensurePublicBackupPermission',
    );
    if (allowed == true) {
      publicLocation = await _platform.invokeMethod<String>(
        'writePublicBackup',
        {'fileName': archive.fileName, 'contents': archive.contents},
      );
    }
    if (publicLocation == null) {
      throw FileSystemException(
        '私人目录已备份，但未能写入 Download/记账备份',
        privateFile.path,
      );
    }
    await _setSetting(_lastBackupKey, localIsoTimestamp(_clock()));
    await _setSetting(_lastBackupPrivatePathKey, privateFile.path);
    return WrittenBackup(
      archive: archive,
      privateFile: privateFile,
      publicLocation: publicLocation,
    );
  }

  Future<void> shareLatest() async {
    final written = await createBackup();
    await _platform.invokeMethod<void>('shareBackup', {
      'uri': written.publicLocation,
      'summary': '记账本备份：${written.archive.document.summary.displayText}',
    });
  }

  Future<void> shareFile(
    File file, {
    required String mimeType,
    required String title,
    String? text,
  }) async {
    await _platform.invokeMethod<void>('shareFile', {
      'path': file.path,
      'mimeType': mimeType,
      'title': title,
      'text': ?text,
    });
  }

  Future<bool> scheduleWeeklyReminder({
    int dayOfWeek = 7,
    int hour = 20,
    int minute = 0,
  }) async {
    if (!Platform.isAndroid) return false;
    return await _platform.invokeMethod<bool>('scheduleWeeklyBackupReminder', {
          'enabled': true,
          'dayOfWeek': dayOfWeek,
          'hour': hour,
          'minute': minute,
        }) ??
        false;
  }

  Future<PickedBackup?> pickBackupFile() async {
    final picked = await _platform.invokeMapMethod<String, dynamic>(
      'pickBackupFile',
    );
    if (picked == null) return null;
    final bytes = picked['contents'];
    if (bytes is! Uint8List) {
      throw const FileSystemException('无法读取选中的备份文件');
    }
    return PickedBackup(
      name: picked['name'] as String? ?? '选中的备份.jzb',
      contents: utf8.decode(bytes, allowMalformed: false),
    );
  }

  Future<PickedBackup> readIncomingUri(String uri) async {
    final bytes = await _platform.invokeMethod<Uint8List>('readUri', {
      'uri': uri,
    });
    if (bytes == null) {
      throw const FileSystemException('无法读取打开的备份文件');
    }
    final segments = Uri.tryParse(uri)?.pathSegments ?? const <String>[];
    return PickedBackup(
      name: segments.isEmpty ? '收到的备份.jzb' : segments.last,
      contents: utf8.decode(bytes, allowMalformed: false),
    );
  }

  BackupDocument validate(PickedBackup picked) {
    return service.parseAndValidate(picked.contents);
  }

  Future<BackupImportResult> importReplacing(PickedBackup picked) async {
    WrittenBackup? preImport;
    final result = await service.importReplacing(
      picked.contents,
      writePreImportBackup: (archive) async {
        preImport = await persistArchive(archive);
      },
    );
    // 完整替换会覆盖 settings，因此在导入成功后恢复刚生成的
    // “导入前备份”状态，避免上次备份时间倒退。
    if (preImport != null) {
      await _setSetting(_lastBackupKey, localIsoTimestamp(_clock()));
      await _setSetting(_lastBackupPrivatePathKey, preImport!.privateFile.path);
    }
    return result;
  }

  Future<DateTime?> lastSuccessfulBackup() async {
    final value = await _setting(_lastBackupKey);
    return value == null ? null : DateTime.tryParse(value)?.toLocal();
  }

  Future<bool> isBackupOverdue() async {
    final last = await lastSuccessfulBackup();
    if (last == null) return true;
    return _clock().difference(last) > const Duration(days: 3);
  }

  Future<File> _writePrivate(BackupArchive archive) async {
    final documents = await _documentsDirectoryProvider();
    final directory = Directory('${documents.path}/backups');
    await directory.create(recursive: true);
    final file = File('${directory.path}/${archive.fileName}');
    await file.writeAsString(archive.contents, encoding: utf8, flush: true);
    final backups = directory
        .listSync()
        .whereType<File>()
        .where((item) => item.path.toLowerCase().endsWith('.jzb'))
        .toList();
    backups.sort(
      (a, b) => b.statSync().modified.compareTo(a.statSync().modified),
    );
    for (final old in backups.skip(60)) {
      await old.delete();
    }
    return file;
  }

  Future<String?> _setting(String key) async {
    final row = await (service.db.select(
      service.db.appSettings,
    )..where((row) => row.key.equals(key))).getSingleOrNull();
    return row?.value;
  }

  Future<void> _setSetting(String key, String value) {
    return service.db
        .into(service.db.appSettings)
        .insertOnConflictUpdate(
          AppSettingsCompanion.insert(key: key, value: value),
        );
  }

  Future<void> dispose() => _incomingUris.close();
}
