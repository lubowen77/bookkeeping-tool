import 'dart:io';

import 'package:archive/archive.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:zhangben/data/database/app_database.dart';
import 'package:zhangben/data/photos/day_photo_service.dart';
import 'package:zhangben/data/repositories/ledger_repository.dart';

final class _FakeImagePicker extends ImagePicker {
  _FakeImagePicker(this.file);

  final File file;

  @override
  Future<XFile?> pickImage({
    required ImageSource source,
    double? maxWidth,
    double? maxHeight,
    int? imageQuality,
    CameraDevice preferredCameraDevice = CameraDevice.rear,
    bool requestFullMetadata = true,
  }) async => XFile(file.path);
}

void main() {
  late AppDatabase db;
  late LedgerRepository repository;
  late Directory temporary;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repository = LedgerRepository(db);
    temporary = await Directory.systemTemp.createTemp('zhangben-photos-');
  });

  tearDown(() async {
    await db.close();
    await temporary.delete(recursive: true);
  });

  test('相机照片压缩到长边 1600、质量 80 并按日期挂账', () async {
    final original = img.Image(width: 2400, height: 1200);
    final source = File('${temporary.path}/camera.jpg');
    await source.writeAsBytes(img.encodeJpg(original, quality: 95));
    final service = DayPhotoService(
      repository,
      picker: _FakeImagePicker(source),
      documentsDirectoryProvider: () async => temporary,
    );

    final row = await service.captureForDate('2026-08-08');
    expect(row, isNotNull);
    expect(row!.bizDate, '2026-08-08');
    final saved = img.decodeJpg(await File(row.filePath).readAsBytes());
    expect(saved, isNotNull);
    expect(saved!.width, 1600);
    expect(saved.height, 800);
    expect(await repository.dayPhotosForDate('2026-08-08'), hasLength(1));
  });

  test('照片 ZIP 只包含有效照片和清单，不嵌入账目备份', () async {
    final activeFile = File('${temporary.path}/active.jpg');
    final deletedFile = File('${temporary.path}/deleted.jpg');
    await activeFile.writeAsBytes([1, 2, 3]);
    await deletedFile.writeAsBytes([4, 5, 6]);
    await repository.addDayPhoto(
      bizDate: '2026-08-08',
      filePath: activeFile.path,
    );
    final deleted = await repository.addDayPhoto(
      bizDate: '2026-08-07',
      filePath: deletedFile.path,
    );
    await repository.softDeleteDayPhoto(deleted.id);
    final service = DayPhotoService(
      repository,
      documentsDirectoryProvider: () async => temporary,
    );

    final zip = await service.exportPhotoZip(
      clock: () => DateTime(2026, 8, 8, 21, 30),
    );
    final archive = ZipDecoder().decodeBytes(await zip.readAsBytes());
    final names = archive.files.map((file) => file.name).toList();
    expect(names, contains('day_photos/2026-08-08/active.jpg'));
    expect(names, contains('照片清单.json'));
    expect(names.any((name) => name.contains('deleted.jpg')), isFalse);
    expect(names.any((name) => name.endsWith('.jzb')), isFalse);
  });
}
