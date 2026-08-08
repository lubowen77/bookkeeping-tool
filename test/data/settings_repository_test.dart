import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zhangben/data/database/app_database.dart';
import 'package:zhangben/data/repositories/ledger_repository.dart';
import 'package:zhangben/domain/ledger_models.dart';

void main() {
  late AppDatabase db;
  late LedgerRepository repository;
  var now = DateTime(2026, 8, 8, 8);

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repository = LedgerRepository(db, clock: () => now);
  });

  tearDown(() => db.close());

  test('关于统计只包含未作废客户和流水', () async {
    final active = await repository.addInitialCustomer(
      name: '赵满仓',
      currentDebtCents: 0,
    );
    final deleted = await repository.addInitialCustomer(
      name: '孙秀英',
      currentDebtCents: 12000,
    );
    await repository.addEntry(
      customerId: active.customer.id,
      kind: EntryKind.debt,
      business: '送货',
      amountCents: 35000,
      bizDate: '2026-08-08',
    );
    await repository.softDeleteCustomer(deleted.customer.id);

    final stats = await repository.activeStats();
    expect(stats.customerCount, 1);
    expect(stats.entryCount, 2);
  });

  test('回收站分开展示删除客户和单独删除的流水', () async {
    final first = await repository.addCustomer(name: '张老三', note: '东村');
    final firstEntry = await repository.addEntry(
      customerId: first.id,
      kind: EntryKind.debt,
      business: '送货',
      amountCents: 35000,
      bizDate: '2026-08-08',
    );
    final second = await repository.addCustomer(name: '李桂芳');
    final secondEntry = await repository.addEntry(
      customerId: second.id,
      kind: EntryKind.payment,
      amountCents: 10000,
      bizDate: '2026-08-08',
    );

    await repository.softDeleteEntry(firstEntry.id);
    now = DateTime(2026, 8, 8, 9);
    await repository.softDeleteCustomer(second.id);

    final customers = await repository.deletedCustomers();
    expect(customers, hasLength(1));
    expect(customers.single.customer.id, second.id);
    expect(customers.single.cascadedEntryCount, 1);

    final entries = await repository.deletedEntries();
    expect(entries, hasLength(1));
    expect(entries.single.entry.id, firstEntry.id);
    expect(entries.single.customer.id, first.id);
    expect(
      entries.map((item) => item.entry.id),
      isNot(contains(secondEntry.id)),
    );

    await repository.restoreCustomer(second.id);
    await repository.restoreEntry(firstEntry.id);
    expect(await repository.deletedCustomers(), isEmpty);
    expect(await repository.deletedEntries(), isEmpty);
    expect((await repository.activeStats()).entryCount, 2);
  });
}
