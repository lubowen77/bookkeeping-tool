import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zhangben/data/database/app_database.dart';
import 'package:zhangben/data/repositories/ledger_repository.dart';
import 'package:zhangben/domain/ledger_models.dart';

void main() {
  late AppDatabase db;
  late LedgerRepository repository;
  var now = DateTime(2026, 8, 7, 21, 30);

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repository = LedgerRepository(db, clock: () => now);
  });

  tearDown(() => db.close());

  test('schema 与规格表名、索引和金额约束一致', () async {
    // 触发数据库创建。
    await db.customSelect('SELECT 1').get();
    final objects = await db.customSelect('''
          SELECT type, name, sql
          FROM sqlite_master
          WHERE name IN (
            'customers', 'entries', 'settings', 'day_photos',
            'idx_entries_customer', 'idx_entries_date'
          )
          ORDER BY name
          ''').get();
    expect(objects.map((row) => row.read<String>('name')).toSet(), {
      'customers',
      'entries',
      'settings',
      'day_photos',
      'idx_entries_customer',
      'idx_entries_date',
    });
    final entriesSql = objects
        .singleWhere((row) => row.read<String>('name') == 'entries')
        .read<String>('sql');
    expect(entriesSql, contains('"amount_cents" > 0'));
    expect(entriesSql, contains("'initial', 'debt', 'payment', 'discount'"));
  });

  test('余额严格按四类未作废流水实时计算', () async {
    final customer = await repository.addCustomer(name: '张老三', note: '东村');
    await repository.addEntry(
      customerId: customer.id,
      kind: EntryKind.initial,
      amountCents: 10000,
      bizDate: '2026-08-01',
    );
    await repository.addEntry(
      customerId: customer.id,
      kind: EntryKind.debt,
      business: '送货',
      amountCents: 35000,
      bizDate: '2026-08-07',
    );
    await repository.addEntry(
      customerId: customer.id,
      kind: EntryKind.payment,
      amountCents: 12000,
      bizDate: '2026-08-07',
    );
    await repository.addEntry(
      customerId: customer.id,
      kind: EntryKind.discount,
      amountCents: 300,
      bizDate: '2026-08-07',
    );

    expect(await repository.balanceCentsForCustomer(customer.id), 32700);
  });

  test('部分还款保留欠款，抹零结清原子生成收款和抹零', () async {
    final customer = await repository.addInitialCustomer(
      name: '李桂芳',
      currentDebtCents: 100000,
    );

    final partial = await repository.settle(
      customerId: customer.customer.id,
      paymentCents: 30000,
      writeOffRemaining: false,
    );
    expect(partial.balanceBeforeCents, 100000);
    expect(partial.balanceAfterCents, 70000);
    expect(partial.discountEntryId, isNull);

    final cleared = await repository.settle(
      customerId: customer.customer.id,
      paymentCents: 65000,
      writeOffRemaining: true,
      note: '  微信转的  ',
    );
    expect(cleared.balanceBeforeCents, 70000);
    expect(cleared.balanceAfterCents, 0);
    expect(cleared.discountEntryId, isNotNull);

    final entries = await repository.entriesForCustomer(customer.customer.id);
    expect(entries.where((entry) => entry.kind == 'payment'), hasLength(2));
    expect(entries.where((entry) => entry.kind == 'discount'), hasLength(1));
    expect(
      entries.singleWhere((entry) => entry.kind == 'discount').amountCents,
      5000,
    );
    expect(
      entries
          .singleWhere(
            (entry) =>
                entry.kind == 'payment' && entry.id == cleared.paymentEntryId,
          )
          .note,
      '微信转的',
    );
    expect(
      entries.singleWhere((entry) => entry.kind == 'discount').note,
      isEmpty,
      reason: '同次抹零只在收款流水上保留备注',
    );
  });

  test('实收超过欠款后余额允许为负', () async {
    final customer = await repository.addInitialCustomer(
      name: '王建国',
      currentDebtCents: 10000,
    );
    final result = await repository.settle(
      customerId: customer.customer.id,
      paymentCents: 15000,
      writeOffRemaining: false,
    );
    expect(result.balanceAfterCents, -5000);
    expect(result.isOverpaid, isTrue);
  });

  test('删除流水后余额消失，恢复后余额还原', () async {
    final customer = await repository.addCustomer(name: '刘婶');
    final entry = await repository.addEntry(
      customerId: customer.id,
      kind: EntryKind.debt,
      business: '材料',
      amountCents: 35000,
      bizDate: '2026-08-07',
    );
    expect(await repository.balanceCentsForCustomer(customer.id), 35000);

    expect(await repository.softDeleteEntry(entry.id), isTrue);
    expect(await repository.balanceCentsForCustomer(customer.id), 0);

    expect(await repository.restoreEntry(entry.id), isTrue);
    expect(await repository.balanceCentsForCustomer(customer.id), 35000);
  });

  test('删除客户联动作废有效流水，恢复时不误恢复此前单独删除的流水', () async {
    final customer = await repository.addCustomer(name: '陈立冬');
    final deletedEarlier = await repository.addEntry(
      customerId: customer.id,
      kind: EntryKind.debt,
      business: '人工',
      amountCents: 10000,
      bizDate: '2026-08-06',
    );
    final active = await repository.addEntry(
      customerId: customer.id,
      kind: EntryKind.debt,
      business: '材料',
      amountCents: 20000,
      bizDate: '2026-08-07',
    );
    await repository.softDeleteEntry(deletedEarlier.id);
    now = DateTime(2026, 8, 8, 8);

    expect(await repository.softDeleteCustomer(customer.id), isTrue);
    expect(await repository.getCustomerOrNull(customer.id), isNull);
    expect(await repository.balanceCentsForCustomer(customer.id), 0);

    expect(await repository.restoreCustomer(customer.id), isTrue);
    expect(await repository.getEntryOrNull(deletedEarlier.id), isNull);
    expect(await repository.getEntryOrNull(active.id), isNotNull);
    expect(await repository.balanceCentsForCustomer(customer.id), 20000);
  });

  test('期初欠款为 0 时仍生成无流水备注的零金额流水', () async {
    final result = await repository.addInitialCustomer(
      name: '赵满仓',
      currentDebtCents: 0,
    );
    expect(result.initialEntryId, isNotNull);
    final entries = await repository.entriesForCustomer(result.customer.id);
    expect(entries, hasLength(1));
    expect(entries.single.kind, EntryKind.initial.storageValue);
    expect(entries.single.amountCents, 0);
    expect(entries.single.business, isEmpty);
    expect(entries.single.note, isEmpty);
    expect(await repository.balanceCentsForCustomer(result.customer.id), 0);

    await expectLater(
      repository.addEntry(
        customerId: result.customer.id,
        kind: EntryKind.debt,
        business: '送货',
        amountCents: 0,
        bizDate: '2026-08-08',
      ),
      throwsFormatException,
    );
  });

  test('同名客户可被发现但数据层允许确认后再建一位', () async {
    await repository.addCustomer(name: '张老三', note: '东村');
    expect(
      await repository.findActiveCustomersWithExactName('张老三'),
      hasLength(1),
    );
    await repository.addCustomer(name: '张老三', note: '西村');
    expect(
      await repository.findActiveCustomersWithExactName('张老三'),
      hasLength(2),
    );
  });

  test('汉字、全拼、首字母都能搜到同一客户', () async {
    final customer = await repository.addCustomer(name: '张老三', note: '东村');
    for (final query in ['张老三', 'zhanglaosan', 'zls']) {
      final results = await repository.searchActiveCustomers(query);
      expect(results.map((row) => row.id), contains(customer.id));
    }
  });

  test('编辑流水可改金额、业务、日期和客户，余额立即变化', () async {
    final first = await repository.addCustomer(name: '孙秀英');
    final second = await repository.addCustomer(name: '老周');
    final entry = await repository.addEntry(
      customerId: first.id,
      kind: EntryKind.debt,
      business: '送货',
      amountCents: 10000,
      bizDate: '2026-08-06',
    );

    await repository.updateEntry(
      entryId: entry.id,
      customerId: second.id,
      kind: EntryKind.debt,
      business: '拉货',
      amountCents: 25000,
      bizDate: '2026-08-07',
    );
    expect(await repository.balanceCentsForCustomer(first.id), 0);
    expect(await repository.balanceCentsForCustomer(second.id), 25000);
    final updated = await repository.getEntry(entry.id);
    expect(updated.business, '拉货');
    expect(updated.bizDate, '2026-08-07');
  });

  test('编辑只改流水备注时金额、业务、日期和客户不变', () async {
    final customer = await repository.addCustomer(name: '孙秀英');
    final entry = await repository.addEntry(
      customerId: customer.id,
      kind: EntryKind.debt,
      business: '送货',
      amountCents: 12345,
      bizDate: '2026-08-06',
      note: '原备注',
    );

    await repository.updateEntry(
      entryId: entry.id,
      customerId: entry.customerId,
      kind: EntryKind.debt,
      business: entry.business,
      amountCents: entry.amountCents,
      bizDate: entry.bizDate,
      note: '  新备注  ',
    );

    final updated = await repository.getEntry(entry.id);
    expect(updated.customerId, customer.id);
    expect(updated.kind, EntryKind.debt.storageValue);
    expect(updated.business, '送货');
    expect(updated.amountCents, 12345);
    expect(updated.bizDate, '2026-08-06');
    expect(updated.note, '新备注');
  });

  test('编辑收款金额、日期和所属客户后两边余额与日期视图都正确', () async {
    final first = await repository.addCustomer(name: '甲客户');
    final second = await repository.addCustomer(name: '乙客户');
    await repository.addEntry(
      customerId: first.id,
      kind: EntryKind.debt,
      business: '送货',
      amountCents: 30000,
      bizDate: '2026-08-06',
    );
    await repository.addEntry(
      customerId: second.id,
      kind: EntryKind.debt,
      business: '材料',
      amountCents: 20000,
      bizDate: '2026-08-06',
    );
    final payment = await repository.addEntry(
      customerId: first.id,
      kind: EntryKind.payment,
      amountCents: 5000,
      bizDate: '2026-08-07',
    );

    await repository.updateEntry(
      entryId: payment.id,
      customerId: second.id,
      kind: EntryKind.payment,
      amountCents: 8000,
      bizDate: '2026-08-08',
    );

    expect(await repository.balanceCentsForCustomer(first.id), 30000);
    expect(await repository.balanceCentsForCustomer(second.id), 12000);
    expect(await repository.entriesForDate('2026-08-07'), isEmpty);
    expect(
      (await repository.entriesForDate('2026-08-08')).single.id,
      payment.id,
    );
  });

  test('业务字典按使用次数排序，新业务自动入库并可拼音搜索', () async {
    final customer = await repository.addCustomer(name: '周师傅');
    for (var index = 0; index < 3; index++) {
      now = now.add(const Duration(minutes: 1));
      await repository.addEntry(
        customerId: customer.id,
        kind: EntryKind.debt,
        business: '维修',
        amountCents: 100,
        bizDate: '2026-08-07',
      );
    }

    final quick = await repository.activeBusinesses(limit: 5);
    expect(quick.first.name, '维修');
    expect(quick.first.useCount, 3);
    expect(
      (await repository.activeBusinesses(search: 'weixiu')).single.name,
      '维修',
    );
    expect((await repository.activeBusinesses(search: 'wx')).single.name, '维修');
  });

  test('业务改名和软删除不回溯改动历史流水快照', () async {
    final customer = await repository.addCustomer(name: '陈大哥');
    final entry = await repository.addEntry(
      customerId: customer.id,
      kind: EntryKind.debt,
      business: '包装',
      amountCents: 5000,
      bizDate: '2026-08-07',
    );
    final business = (await repository.findActiveBusinessesWithExactName(
      '包装',
    )).single;

    await repository.renameBusiness(business.id, '包装费');
    expect((await repository.getEntry(entry.id)).business, '包装');
    await repository.softDeleteBusiness(business.id);
    expect(await repository.findActiveBusinessesWithExactName('包装费'), isEmpty);
    expect((await repository.getEntry(entry.id)).business, '包装');
    expect(await repository.restoreBusiness(business.id), isTrue);
  });

  test('撤销抹零结清会原子撤回收款和抹零两笔', () async {
    final initial = await repository.addInitialCustomer(
      name: '王二叔',
      currentDebtCents: 10000,
    );
    final result = await repository.settle(
      customerId: initial.customer.id,
      paymentCents: 9000,
      writeOffRemaining: true,
    );
    expect(await repository.balanceCentsForCustomer(initial.customer.id), 0);

    expect(
      await repository.softDeleteEntries([
        result.paymentEntryId,
        result.discountEntryId!,
      ]),
      2,
    );
    expect(
      await repository.balanceCentsForCustomer(initial.customer.id),
      10000,
    );
  });

  test('500 客户和 2 万笔流水可一次聚合并快速搜索', () async {
    const timestamp = '2026-08-07T21:30:00+08:00';
    await db.batch((batch) {
      batch.insertAll(
        db.customers,
        List.generate(500, (index) {
          final isTarget = index == 0;
          return CustomersCompanion.insert(
            name: isTarget ? '张老三' : '客户$index',
            note: Value(isTarget ? '东村' : ''),
            pinyinFull: Value(isTarget ? 'zhanglaosan' : 'kehu$index'),
            pinyinAbbr: Value(isTarget ? 'zls' : 'kh$index'),
            createdAt: timestamp,
          );
        }),
      );
      batch.insertAll(
        db.ledgerEntries,
        List.generate(
          20000,
          (index) => LedgerEntriesCompanion.insert(
            customerId: index % 500 + 1,
            kind: 'debt',
            business: const Value('送货'),
            amountCents: 100,
            bizDate: '2026-08-07',
            createdAt: timestamp,
            updatedAt: timestamp,
          ),
        ),
      );
    });

    final stopwatch = Stopwatch()..start();
    final customers = await repository.customersWithBalances();
    final searched = await repository.customersWithBalances(search: 'zls');
    stopwatch.stop();

    expect(customers, hasLength(500));
    expect(
      customers.singleWhere((item) => item.customer.name == '张老三').balanceCents,
      4000,
    );
    expect(searched.single.customer.name, '张老三');
    expect(
      stopwatch.elapsed,
      lessThan(const Duration(seconds: 3)),
      reason: '目标数据量的聚合与搜索不应让页面出现明显等待',
    );
  });
}
