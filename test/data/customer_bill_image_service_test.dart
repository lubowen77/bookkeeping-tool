import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zhangben/data/billing/customer_bill_image_service.dart';
import 'package:zhangben/data/database/app_database.dart';
import 'package:zhangben/data/repositories/ledger_repository.dart';
import 'package:zhangben/domain/ledger_models.dart';

void main() {
  late AppDatabase db;
  late LedgerRepository repository;
  final now = DateTime(2026, 8, 8, 14, 5);

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repository = LedgerRepository(db, clock: () => now);
  });

  tearDown(() => db.close());

  test('只保留该客户有效流水，当前结清时保留最近完整周期', () async {
    final customer = await repository.addCustomer(name: '张老三');
    final other = await repository.addCustomer(name: '李桂芳');

    await repository.addEntry(
      customerId: customer.id,
      kind: EntryKind.debt,
      business: '旧周期',
      amountCents: 10000,
      bizDate: '2026-07-01',
    );
    await repository.addEntry(
      customerId: customer.id,
      kind: EntryKind.payment,
      amountCents: 10000,
      bizDate: '2026-07-02',
    );
    final debt = await repository.addEntry(
      customerId: customer.id,
      kind: EntryKind.debt,
      business: '送货',
      amountCents: 50000,
      bizDate: '2026-08-01',
    );
    final payment = await repository.addEntry(
      customerId: customer.id,
      kind: EntryKind.payment,
      amountCents: 30000,
      bizDate: '2026-08-02',
    );
    final discount = await repository.addEntry(
      customerId: customer.id,
      kind: EntryKind.discount,
      amountCents: 20000,
      bizDate: '2026-08-02',
    );
    await repository.addEntry(
      customerId: other.id,
      kind: EntryKind.debt,
      business: '不能泄露',
      amountCents: 999900,
      bizDate: '2026-08-01',
    );
    final deleted = await repository.addEntry(
      customerId: customer.id,
      kind: EntryKind.debt,
      business: '已删除',
      amountCents: 888800,
      bizDate: '2026-08-03',
    );
    await repository.softDeleteEntry(deleted.id);

    final mixedEntries = (await db.select(db.ledgerEntries).get()).reversed;
    final statement = CustomerBillStatement.build(
      customer: customer,
      effectiveEntries: mixedEntries,
      generatedAt: now,
    );

    expect(statement.balanceCents, 0);
    expect(statement.entries.map((entry) => entry.id), [
      debt.id,
      payment.id,
      discount.id,
    ]);
    expect(
      statement.entries.every((entry) => entry.customerId == customer.id),
      isTrue,
    );
    expect(statement.entries.every((entry) => entry.deletedAt == null), isTrue);
  });

  test('未结清时只取最后归零点之后的流水', () async {
    final customer = await repository.addCustomer(name: '王建国');
    await repository.addEntry(
      customerId: customer.id,
      kind: EntryKind.debt,
      business: '已结周期',
      amountCents: 10000,
      bizDate: '2026-07-01',
    );
    await repository.addEntry(
      customerId: customer.id,
      kind: EntryKind.payment,
      amountCents: 10000,
      bizDate: '2026-07-02',
    );
    final current = await repository.addEntry(
      customerId: customer.id,
      kind: EntryKind.debt,
      business: '本周期',
      amountCents: 35000,
      bizDate: '2026-08-08',
    );

    final statement = CustomerBillStatement.build(
      customer: customer,
      effectiveEntries: await repository.entriesForCustomer(customer.id),
      generatedAt: now,
    );

    expect(statement.balanceCents, 35000);
    expect(statement.entries.map((entry) => entry.id), [current.id]);
  });

  test('生成 750px 清晰 PNG，四类流水与店家称呼可传入', () async {
    final output = await Directory.systemTemp.createTemp('zhangben-bill-test-');
    addTearDown(() => output.delete(recursive: true));

    final customer = await repository.addCustomer(name: '刘婶', note: '东村');
    await repository.addEntry(
      customerId: customer.id,
      kind: EntryKind.initial,
      amountCents: 10000,
      bizDate: '2026-08-01',
    );
    await repository.addEntry(
      customerId: customer.id,
      kind: EntryKind.debt,
      business: '材料',
      amountCents: 5000,
      bizDate: '2026-08-02',
    );
    await repository.addEntry(
      customerId: customer.id,
      kind: EntryKind.payment,
      amountCents: 12000,
      bizDate: '2026-08-03',
    );
    await repository.addEntry(
      customerId: customer.id,
      kind: EntryKind.discount,
      amountCents: 3000,
      bizDate: '2026-08-03',
    );

    final service = CustomerBillImageService(
      db,
      clock: () => now,
      outputDirectoryProvider: () async => output,
    );
    final result = await service.generate(
      customer: customer,
      effectiveEntries: await repository.entriesForCustomer(customer.id),
      shopName: '老王批发部',
    );
    final bytes = await result.file.readAsBytes();
    final png = ByteData.sublistView(bytes);

    expect(bytes.take(8), [137, 80, 78, 71, 13, 10, 26, 10]);
    expect(png.getUint32(16), CustomerBillImageService.logicalWidth);
    expect(png.getUint32(20), result.height);
    expect(result.entryCount, 4);
    expect(result.balanceCents, 0);
    expect(result.generatedAt, now);
    expect(result.file.path, endsWith('.png'));
    expect(await result.file.length(), greaterThan(1000));
  });

  test('账单备注开关同时控制文字与明细行高', () async {
    final output = await Directory.systemTemp.createTemp(
      'zhangben-bill-note-test-',
    );
    addTearDown(() => output.delete(recursive: true));

    final customer = await repository.addCustomer(name: '张老三');
    final entry = await repository.addEntry(
      customerId: customer.id,
      kind: EntryKind.debt,
      business: '送货',
      amountCents: 35000,
      bizDate: '2026-08-08',
      note: '纸箱 20 个',
    );
    final service = CustomerBillImageService(
      db,
      clock: () => now,
      outputDirectoryProvider: () async => output,
    );

    final withNote = await service.generate(
      customer: customer,
      showNotes: true,
    );
    final withoutNote = await service.generate(
      customer: customer,
      showNotes: false,
    );
    await repository.updateEntry(
      entryId: entry.id,
      customerId: customer.id,
      kind: EntryKind.debt,
      business: '送货',
      amountCents: 35000,
      bizDate: '2026-08-08',
      note: '',
    );
    final emptyNote = await service.generate(
      customer: customer,
      showNotes: true,
    );

    expect(withNote.height, greaterThan(withoutNote.height));
    expect(emptyNote.height, withoutNote.height);
    expect(
      await withoutNote.file.readAsBytes(),
      orderedEquals(await emptyNote.file.readAsBytes()),
      reason: '关闭备注后输出应与源流水没有备注时完全一致',
    );
  });
}
