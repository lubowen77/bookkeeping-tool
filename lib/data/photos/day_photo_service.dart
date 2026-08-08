import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/local_time.dart';
import '../database/app_database.dart';
import '../repositories/ledger_repository.dart';

typedef DirectoryProvider = Future<Directory> Function();

final class DayPhotoService {
  DayPhotoService(
    this.repository, {
    ImagePicker? picker,
    DirectoryProvider? documentsDirectoryProvider,
  }) : _picker = picker ?? ImagePicker(),
       _documentsDirectoryProvider =
           documentsDirectoryProvider ?? getApplicationDocumentsDirectory;

  final LedgerRepository repository;
  final ImagePicker _picker;
  final DirectoryProvider _documentsDirectoryProvider;

  /// 打开系统相机，压缩后写入 App 私有目录并挂到指定业务日期。
  Future<DayPhotoRow?> captureForDate(String bizDate) async {
    final picked = await _picker.pickImage(source: ImageSource.camera);
    if (picked == null) return null;
    final sourceBytes = await picked.readAsBytes();
    final decoded = img.decodeImage(sourceBytes);
    if (decoded == null) throw const FormatException('这张照片无法读取');

    final longest = decoded.width > decoded.height
        ? decoded.width
        : decoded.height;
    final resized = longest <= 1600
        ? decoded
        : decoded.width >= decoded.height
        ? img.copyResize(decoded, width: 1600)
        : img.copyResize(decoded, height: 1600);
    final encoded = img.encodeJpg(resized, quality: 80);
    final documents = await _documentsDirectoryProvider();
    final directory = Directory('${documents.path}/day_photos/$bizDate');
    await directory.create(recursive: true);
    final now = DateTime.now();
    final stamp = now.microsecondsSinceEpoch;
    final file = File('${directory.path}/paper-$stamp.jpg');
    await file.writeAsBytes(encoded, flush: true);
    try {
      return await repository.addDayPhoto(
        bizDate: bizDate,
        filePath: file.path,
      );
    } catch (_) {
      if (await file.exists()) await file.delete();
      rethrow;
    }
  }

  /// 照片轨的唯一导出入口。不调用 .jzb 逻辑，也不包含账目 JSON。
  Future<File> exportPhotoZip({DateTime Function()? clock}) async {
    final rows = await repository.activeDayPhotos();
    final manifest = <Map<String, Object?>>[];
    final now = (clock ?? DateTime.now)();
    final documents = await _documentsDirectoryProvider();
    final directory = Directory('${documents.path}/exports');
    await directory.create(recursive: true);
    final file = File('${directory.path}/记账照片-换机用-${_timestamp(now)}.zip');
    final encoder = ZipFileEncoder();
    var encoderOpen = false;
    encoder.create(file.path);
    encoderOpen = true;
    try {
      for (final row in rows) {
        final photoFile = File(row.filePath);
        if (!await photoFile.exists()) continue;
        final name = row.filePath.split(Platform.pathSeparator).last;
        final archivePath = 'day_photos/${row.bizDate}/$name';
        // ZipFileEncoder 直接从文件流写入目标 ZIP，不把全部照片同时
        // 堆在内存里，旧安卓导出大量照片时也不会出现多份字节副本。
        await encoder.addFile(photoFile, archivePath);
        manifest.add({
          'biz_date': row.bizDate,
          'file': archivePath,
          'created_at': row.createdAt,
        });
      }
      final manifestBytes = utf8.encode(
        const JsonEncoder.withIndent('  ').convert({
          'app': 'zhangben',
          'exported_at': localIsoTimestamp(now),
          'photo_count': manifest.length,
          'photos': manifest,
        }),
      );
      encoder.addArchiveFile(
        ArchiveFile('照片清单.json', manifestBytes.length, manifestBytes),
      );
      await encoder.close();
      encoderOpen = false;
      return file;
    } catch (_) {
      if (encoderOpen) {
        try {
          await encoder.close();
        } catch (_) {
          // 保留最初的异常。
        }
      }
      if (await file.exists()) await file.delete();
      rethrow;
    }
  }

  static String _timestamp(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}'
      '${value.month.toString().padLeft(2, '0')}'
      '${value.day.toString().padLeft(2, '0')}-'
      '${value.hour.toString().padLeft(2, '0')}'
      '${value.minute.toString().padLeft(2, '0')}';
}
