import 'package:drift/drift.dart';

import '../../core/local_time.dart';
import '../../core/pinyin.dart';
import '../../domain/ledger_models.dart';
import '../database/app_database.dart';

final class LedgerRepository {
  LedgerRepository(this.db, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final AppDatabase db;
  final DateTime Function() _clock;

  Future<CustomerRow> addCustomer({
    required String name,
    String note = '',
  }) async {
    final normalizedName = name.trim();
    if (normalizedName.isEmpty) {
      throw const FormatException('客户姓名不能为空');
    }
    final normalizedNote = note.trim();
    final pinyin = PinyinIndex.fromName(normalizedName);
    final id = await db
        .into(db.customers)
        .insert(
          CustomersCompanion.insert(
            name: normalizedName,
            note: Value(normalizedNote),
            pinyinFull: Value(pinyin.full),
            pinyinAbbr: Value(pinyin.abbr),
            createdAt: localIsoTimestamp(_clock()),
          ),
        );
    return getCustomer(id);
  }

  Future<CustomerRow?> getCustomerOrNull(
    int id, {
    bool includeDeleted = false,
  }) {
    final query = db.select(db.customers)..where((row) => row.id.equals(id));
    if (!includeDeleted) {
      query.where((row) => row.deletedAt.isNull());
    }
    return query.getSingleOrNull();
  }

  Future<CustomerRow> getCustomer(int id, {bool includeDeleted = false}) async {
    final customer = await getCustomerOrNull(
      id,
      includeDeleted: includeDeleted,
    );
    if (customer == null) {
      throw StateError('找不到客户：$id');
    }
    return customer;
  }

  Future<List<CustomerRow>> findActiveCustomersWithExactName(String name) {
    final normalized = name.trim();
    return (db.select(db.customers)
          ..where((row) => row.name.equals(normalized) & row.deletedAt.isNull())
          ..orderBy([(row) => OrderingTerm.asc(row.id)]))
        .get();
  }

  Future<List<CustomerRow>> searchActiveCustomers(String text) {
    final normalized = text.trim().toLowerCase();
    final query = db.select(db.customers)
      ..where((row) => row.deletedAt.isNull());
    if (normalized.isNotEmpty) {
      query.where(
        (row) =>
            row.name.contains(normalized) |
            row.pinyinFull.contains(normalized) |
            row.pinyinAbbr.contains(normalized),
      );
    }
    query.orderBy([
      (row) => OrderingTerm.asc(row.pinyinFull),
      (row) => OrderingTerm.asc(row.name),
      (row) => OrderingTerm.asc(row.id),
    ]);
    return query.get();
  }

  Future<List<CustomerWithBalance>> customersWithBalances({
    String search = '',
    bool onlyOwing = false,
    CustomerSort sort = CustomerSort.balance,
    int? limit,
    bool recentFirst = false,
  }) async {
    final normalized = search.trim().toLowerCase();
    final variables = <Variable<Object>>[];
    var searchSql = '';
    if (normalized.isNotEmpty) {
      searchSql = '''
        AND (c.name LIKE ? OR c.pinyin_full LIKE ? OR c.pinyin_abbr LIKE ?)
      ''';
      final pattern = '%$normalized%';
      variables.addAll([
        Variable.withString(pattern),
        Variable.withString(pattern),
        Variable.withString(pattern),
      ]);
    }
    final havingConditions = <String>[
      if (onlyOwing) 'balance_cents > 0',
      if (recentFirst) 'last_deal_at IS NOT NULL',
    ];
    final havingSql = havingConditions.isEmpty
        ? ''
        : 'HAVING ${havingConditions.join(' AND ')}';
    final orderSql = recentFirst
        ? 'ORDER BY last_deal_at DESC, c.pinyin_full ASC, c.id ASC'
        : sort == CustomerSort.balance
        ? 'ORDER BY balance_cents DESC, c.pinyin_full ASC, c.id ASC'
        : 'ORDER BY c.pinyin_full ASC, c.name ASC, c.id ASC';
    final limitSql = limit == null ? '' : 'LIMIT $limit';
    final rows = await db
        .customSelect(
          '''
      SELECT c.id, c.name, c.note, c.pinyin_full, c.pinyin_abbr,
             c.created_at, c.deleted_at,
             COALESCE(SUM(CASE e.kind
               WHEN 'initial' THEN e.amount_cents
               WHEN 'debt' THEN e.amount_cents
               WHEN 'payment' THEN -e.amount_cents
               WHEN 'discount' THEN -e.amount_cents
               ELSE 0 END), 0) AS balance_cents,
             MAX(e.created_at) AS last_deal_at
      FROM customers c
      LEFT JOIN entries e ON e.customer_id = c.id AND e.deleted_at IS NULL
      WHERE c.deleted_at IS NULL
      $searchSql
      GROUP BY c.id
      $havingSql
      $orderSql
      $limitSql
      ''',
          variables: variables,
          readsFrom: {db.customers, db.ledgerEntries},
        )
        .get();
    return rows
        .map((row) {
          final customer = CustomerRow(
            id: row.read<int>('id'),
            name: row.read<String>('name'),
            note: row.read<String>('note'),
            pinyinFull: row.read<String>('pinyin_full'),
            pinyinAbbr: row.read<String>('pinyin_abbr'),
            createdAt: row.read<String>('created_at'),
            deletedAt: row.readNullable<String>('deleted_at'),
          );
          return CustomerWithBalance(
            customer: customer,
            balanceCents: row.read<int>('balance_cents'),
          );
        })
        .toList(growable: false);
  }

  Future<void> updateCustomer({
    required int customerId,
    required String name,
    String note = '',
  }) async {
    await _requireActiveCustomer(customerId);
    final normalizedName = name.trim();
    if (normalizedName.isEmpty) {
      throw const FormatException('客户姓名不能为空');
    }
    final pinyin = PinyinIndex.fromName(normalizedName);
    await (db.update(
      db.customers,
    )..where((row) => row.id.equals(customerId))).write(
      CustomersCompanion(
        name: Value(normalizedName),
        note: Value(note.trim()),
        pinyinFull: Value(pinyin.full),
        pinyinAbbr: Value(pinyin.abbr),
      ),
    );
  }

  Future<LedgerEntryRow> addEntry({
    required int customerId,
    required EntryKind kind,
    required int amountCents,
    required String bizDate,
    String business = '',
    String note = '',
  }) async {
    await _requireActiveCustomer(customerId);
    if (amountCents < 0 || (amountCents == 0 && kind != EntryKind.initial)) {
      throw const FormatException('除零元期初外，金额必须大于 0');
    }
    final normalizedBusiness = business.trim();
    if (kind == EntryKind.debt && normalizedBusiness.isEmpty) {
      throw const FormatException('记账必须填写业务');
    }
    _validateBusinessDate(bizDate);

    return db.transaction(() async {
      final now = localIsoTimestamp(_clock());
      final id = await db
          .into(db.ledgerEntries)
          .insert(
            LedgerEntriesCompanion.insert(
              customerId: customerId,
              kind: kind.storageValue,
              business: Value(normalizedBusiness),
              amountCents: amountCents,
              bizDate: bizDate,
              note: Value(note.trim()),
              createdAt: now,
              updatedAt: now,
            ),
          );
      if (kind == EntryKind.debt) {
        await _recordBusinessUse(normalizedBusiness, usedAt: now);
      }
      return getEntry(id);
    });
  }

  Future<LedgerEntryRow?> getEntryOrNull(
    int id, {
    bool includeDeleted = false,
  }) {
    final query = db.select(db.ledgerEntries)
      ..where((row) => row.id.equals(id));
    if (!includeDeleted) {
      query.where((row) => row.deletedAt.isNull());
    }
    return query.getSingleOrNull();
  }

  Future<LedgerEntryRow> getEntry(int id, {bool includeDeleted = false}) async {
    final entry = await getEntryOrNull(id, includeDeleted: includeDeleted);
    if (entry == null) {
      throw StateError('找不到流水：$id');
    }
    return entry;
  }

  Future<List<LedgerEntryRow>> entriesForCustomer(
    int customerId, {
    bool includeDeleted = false,
  }) {
    final query = db.select(db.ledgerEntries)
      ..where((row) => row.customerId.equals(customerId));
    if (!includeDeleted) {
      query.where((row) => row.deletedAt.isNull());
    }
    query.orderBy([
      (row) => OrderingTerm.desc(row.bizDate),
      (row) => OrderingTerm.desc(row.createdAt),
      (row) => OrderingTerm.desc(row.id),
    ]);
    return query.get();
  }

  Future<List<LedgerEntryRow>> entriesForDate(String bizDate) {
    _validateBusinessDate(bizDate);
    return (db.select(db.ledgerEntries)
          ..where((row) => row.bizDate.equals(bizDate) & row.deletedAt.isNull())
          ..orderBy([
            (row) => OrderingTerm.desc(row.createdAt),
            (row) => OrderingTerm.desc(row.id),
          ]))
        .get();
  }

  Future<List<EntryWithCustomer>> entriesWithCustomersForDate(
    String bizDate,
  ) async {
    _validateBusinessDate(bizDate);
    final query =
        db.select(db.ledgerEntries).join([
            innerJoin(
              db.customers,
              db.customers.id.equalsExp(db.ledgerEntries.customerId),
            ),
          ])
          ..where(
            db.ledgerEntries.bizDate.equals(bizDate) &
                db.ledgerEntries.deletedAt.isNull() &
                db.customers.deletedAt.isNull(),
          )
          ..orderBy([
            OrderingTerm.desc(db.ledgerEntries.createdAt),
            OrderingTerm.desc(db.ledgerEntries.id),
          ]);
    final rows = await query.get();
    return rows
        .map(
          (row) => EntryWithCustomer(
            entry: row.readTable(db.ledgerEntries),
            customer: row.readTable(db.customers),
          ),
        )
        .toList(growable: false);
  }

  Future<int> balanceCentsForCustomer(int customerId) async {
    final result = await db
        .customSelect(
          '''
      SELECT COALESCE(SUM(
        CASE kind
          WHEN 'initial' THEN amount_cents
          WHEN 'debt' THEN amount_cents
          WHEN 'payment' THEN -amount_cents
          WHEN 'discount' THEN -amount_cents
          ELSE 0
        END
      ), 0) AS balance_cents
      FROM entries
      WHERE customer_id = ? AND deleted_at IS NULL
      ''',
          variables: [Variable.withInt(customerId)],
          readsFrom: {db.ledgerEntries},
        )
        .getSingle();
    return result.read<int>('balance_cents');
  }

  Future<void> updateEntry({
    required int entryId,
    required int customerId,
    required EntryKind kind,
    required int amountCents,
    required String bizDate,
    String business = '',
    String note = '',
  }) async {
    final previous = await getEntry(entryId);
    await _requireActiveCustomer(customerId);
    if (amountCents < 0 || (amountCents == 0 && kind != EntryKind.initial)) {
      throw const FormatException('除零元期初外，金额必须大于 0');
    }
    final normalizedBusiness = business.trim();
    if (kind == EntryKind.debt && normalizedBusiness.isEmpty) {
      throw const FormatException('记账必须填写业务');
    }
    _validateBusinessDate(bizDate);

    await db.transaction(() async {
      final now = localIsoTimestamp(_clock());
      await (db.update(
        db.ledgerEntries,
      )..where((row) => row.id.equals(entryId))).write(
        LedgerEntriesCompanion(
          customerId: Value(customerId),
          kind: Value(kind.storageValue),
          business: Value(normalizedBusiness),
          amountCents: Value(amountCents),
          bizDate: Value(bizDate),
          note: Value(note.trim()),
          updatedAt: Value(now),
        ),
      );
      if (kind == EntryKind.debt) {
        if (previous.kind != EntryKind.debt.storageValue ||
            previous.business != normalizedBusiness) {
          await _recordBusinessUse(normalizedBusiness, usedAt: now);
        } else {
          await _ensureBusinessExists(normalizedBusiness);
        }
      }
    });
  }

  /// 撤销一次操作产生的所有流水。仍遵守“删除即软删除”，
  /// 所以数据可从回收站找回，同时批量操作保持原子性。
  Future<int> softDeleteEntries(Iterable<int> entryIds) {
    final ids = entryIds.toSet().toList(growable: false);
    if (ids.isEmpty) return Future.value(0);
    return db.transaction(() async {
      final timestamp = localIsoTimestamp(_clock());
      var changed = 0;
      for (final id in ids) {
        changed +=
            await (db.update(db.ledgerEntries)
                  ..where((row) => row.id.equals(id) & row.deletedAt.isNull()))
                .write(
                  LedgerEntriesCompanion(
                    deletedAt: Value(timestamp),
                    updatedAt: Value(timestamp),
                  ),
                );
      }
      return changed;
    });
  }

  Future<bool> softDeleteEntry(int entryId) async {
    final entry = await getEntryOrNull(entryId);
    if (entry == null) return false;
    final timestamp = localIsoTimestamp(_clock());
    final changed =
        await (db.update(
          db.ledgerEntries,
        )..where((row) => row.id.equals(entryId))).write(
          LedgerEntriesCompanion(
            deletedAt: Value(timestamp),
            updatedAt: Value(timestamp),
          ),
        );
    return changed == 1;
  }

  Future<bool> restoreEntry(int entryId) async {
    final entry = await getEntryOrNull(entryId, includeDeleted: true);
    if (entry == null || entry.deletedAt == null) return false;
    final customer = await getCustomer(entry.customerId, includeDeleted: true);
    if (customer.deletedAt != null) {
      throw StateError('请先恢复客户，再恢复这笔账');
    }
    final changed =
        await (db.update(
          db.ledgerEntries,
        )..where((row) => row.id.equals(entryId))).write(
          LedgerEntriesCompanion(
            deletedAt: const Value(null),
            updatedAt: Value(localIsoTimestamp(_clock())),
          ),
        );
    return changed == 1;
  }

  Future<bool> softDeleteCustomer(int customerId) {
    return db.transaction(() async {
      final customer = await getCustomerOrNull(customerId);
      if (customer == null) return false;
      var markerTime = _clock();
      var timestamp = localIsoTimestamp(markerTime);
      final deletedCount = db.ledgerEntries.id.count();
      while (await (db.selectOnly(db.ledgerEntries)
                ..addColumns([deletedCount])
                ..where(db.ledgerEntries.deletedAt.equals(timestamp)))
              .map((row) => row.read(deletedCount) ?? 0)
              .getSingle() >
          0) {
        markerTime = markerTime.add(const Duration(microseconds: 1));
        timestamp = localIsoTimestamp(markerTime);
      }
      await (db.update(db.ledgerEntries)..where(
            (row) => row.customerId.equals(customerId) & row.deletedAt.isNull(),
          ))
          .write(
            LedgerEntriesCompanion(
              deletedAt: Value(timestamp),
              updatedAt: Value(timestamp),
            ),
          );
      await (db.update(db.customers)..where((row) => row.id.equals(customerId)))
          .write(CustomersCompanion(deletedAt: Value(timestamp)));
      return true;
    });
  }

  Future<bool> restoreCustomer(int customerId) {
    return db.transaction(() async {
      final customer = await getCustomerOrNull(
        customerId,
        includeDeleted: true,
      );
      final deletionMarker = customer?.deletedAt;
      if (customer == null || deletionMarker == null) return false;

      await (db.update(db.ledgerEntries)..where(
            (row) =>
                row.customerId.equals(customerId) &
                row.deletedAt.equals(deletionMarker),
          ))
          .write(
            LedgerEntriesCompanion(
              deletedAt: const Value(null),
              updatedAt: Value(localIsoTimestamp(_clock())),
            ),
          );
      await (db.update(db.customers)..where((row) => row.id.equals(customerId)))
          .write(const CustomersCompanion(deletedAt: Value(null)));
      return true;
    });
  }

  Future<InitialCustomerResult> addInitialCustomer({
    required String name,
    String note = '',
    required int currentDebtCents,
    String? bizDate,
  }) {
    if (currentDebtCents < 0) {
      throw const FormatException('期初欠款不能小于 0');
    }
    return db.transaction(() async {
      final customer = await addCustomer(name: name, note: note);
      final entry = await addEntry(
        customerId: customer.id,
        kind: EntryKind.initial,
        amountCents: currentDebtCents,
        bizDate: bizDate ?? businessDateOf(_clock()),
        note: '期初建档',
      );
      return InitialCustomerResult(
        customer: customer,
        initialEntryId: entry.id,
      );
    });
  }

  Future<SettlementResult> settle({
    required int customerId,
    required int paymentCents,
    required bool writeOffRemaining,
    String? bizDate,
  }) {
    if (paymentCents <= 0) {
      throw const FormatException('实收金额必须大于 0');
    }
    return db.transaction(() async {
      await _requireActiveCustomer(customerId);
      final balanceBefore = await balanceCentsForCustomer(customerId);
      if (balanceBefore <= 0) {
        throw StateError('这位客户现在没有欠款，不能继续收款');
      }
      final remaining = balanceBefore - paymentCents;
      if (writeOffRemaining && remaining <= 0) {
        throw StateError('只有实收小于欠款时才能抹零');
      }

      final date = bizDate ?? businessDateOf(_clock());
      final payment = await addEntry(
        customerId: customerId,
        kind: EntryKind.payment,
        amountCents: paymentCents,
        bizDate: date,
      );
      int? discountEntryId;
      if (writeOffRemaining) {
        final discount = await addEntry(
          customerId: customerId,
          kind: EntryKind.discount,
          amountCents: remaining,
          bizDate: date,
        );
        discountEntryId = discount.id;
      }

      final balanceAfter = await balanceCentsForCustomer(customerId);
      return SettlementResult(
        paymentEntryId: payment.id,
        paymentCents: paymentCents,
        discountEntryId: discountEntryId,
        balanceBeforeCents: balanceBefore,
        balanceAfterCents: balanceAfter,
      );
    });
  }

  Future<String?> getSetting(String key) async {
    final row = await (db.select(
      db.appSettings,
    )..where((row) => row.key.equals(key))).getSingleOrNull();
    return row?.value;
  }

  Future<void> setSetting(String key, String value) {
    return db
        .into(db.appSettings)
        .insertOnConflictUpdate(
          AppSettingsCompanion.insert(key: key, value: value),
        );
  }

  Future<List<BusinessRow>> activeBusinesses({String search = '', int? limit}) {
    final normalized = search.trim().toLowerCase();
    final query = db.select(db.businesses)
      ..where((row) => row.deletedAt.isNull());
    if (normalized.isNotEmpty) {
      query.where(
        (row) =>
            row.name.contains(normalized) |
            row.pinyinFull.contains(normalized) |
            row.pinyinAbbr.contains(normalized),
      );
    }
    query.orderBy([
      (row) => OrderingTerm.desc(row.useCount),
      (row) => OrderingTerm.desc(row.lastUsed),
      (row) => OrderingTerm.asc(row.pinyinFull),
      (row) => OrderingTerm.asc(row.id),
    ]);
    if (limit != null) query.limit(limit);
    return query.get();
  }

  Future<List<BusinessRow>> findActiveBusinessesWithExactName(String name) {
    final normalized = name.trim();
    return (db.select(db.businesses)
          ..where((row) => row.name.equals(normalized) & row.deletedAt.isNull())
          ..orderBy([(row) => OrderingTerm.asc(row.id)]))
        .get();
  }

  Future<BusinessRow> addBusiness(String name) async {
    final normalized = name.trim();
    if (normalized.isEmpty) throw const FormatException('业务名不能为空');
    if ((await findActiveBusinessesWithExactName(normalized)).isNotEmpty) {
      throw StateError('已经有这个业务了，直接选就行');
    }
    final pinyin = PinyinIndex.fromName(normalized);
    final id = await db
        .into(db.businesses)
        .insert(
          BusinessesCompanion.insert(
            name: normalized,
            pinyinFull: Value(pinyin.full),
            pinyinAbbr: Value(pinyin.abbr),
            createdAt: localIsoTimestamp(_clock()),
          ),
        );
    return (db.select(
      db.businesses,
    )..where((row) => row.id.equals(id))).getSingle();
  }

  Future<void> renameBusiness(int businessId, String name) async {
    final normalized = name.trim();
    if (normalized.isEmpty) throw const FormatException('业务名不能为空');
    final duplicates = (await findActiveBusinessesWithExactName(
      normalized,
    )).where((row) => row.id != businessId);
    if (duplicates.isNotEmpty) throw StateError('已经有这个业务了');
    final pinyin = PinyinIndex.fromName(normalized);
    final changed =
        await (db.update(db.businesses)..where(
              (row) => row.id.equals(businessId) & row.deletedAt.isNull(),
            ))
            .write(
              BusinessesCompanion(
                name: Value(normalized),
                pinyinFull: Value(pinyin.full),
                pinyinAbbr: Value(pinyin.abbr),
              ),
            );
    if (changed != 1) throw StateError('找不到这个业务');
    // 故意不改 entries.business：历史流水是当时名称的快照。
  }

  Future<bool> softDeleteBusiness(int businessId) async {
    final changed =
        await (db.update(db.businesses)..where(
              (row) => row.id.equals(businessId) & row.deletedAt.isNull(),
            ))
            .write(
              BusinessesCompanion(
                deletedAt: Value(localIsoTimestamp(_clock())),
              ),
            );
    return changed == 1;
  }

  Future<bool> restoreBusiness(int businessId) async {
    final row = await (db.select(
      db.businesses,
    )..where((item) => item.id.equals(businessId))).getSingleOrNull();
    if (row == null || row.deletedAt == null) return false;
    if ((await findActiveBusinessesWithExactName(row.name)).isNotEmpty) {
      throw StateError('已有同名业务，请先改名再找回');
    }
    final changed =
        await (db.update(db.businesses)
              ..where((item) => item.id.equals(businessId)))
            .write(const BusinessesCompanion(deletedAt: Value(null)));
    return changed == 1;
  }

  Future<List<BusinessRow>> deletedBusinesses() {
    return (db.select(db.businesses)
          ..where((row) => row.deletedAt.isNotNull())
          ..orderBy([
            (row) => OrderingTerm.desc(row.deletedAt),
            (row) => OrderingTerm.desc(row.id),
          ]))
        .get();
  }

  Future<DayPhotoRow> addDayPhoto({
    required String bizDate,
    required String filePath,
  }) async {
    _validateBusinessDate(bizDate);
    if (filePath.trim().isEmpty) throw const FormatException('照片路径不能为空');
    final id = await db
        .into(db.dayPhotos)
        .insert(
          DayPhotosCompanion.insert(
            bizDate: bizDate,
            filePath: filePath,
            createdAt: localIsoTimestamp(_clock()),
          ),
        );
    return (db.select(
      db.dayPhotos,
    )..where((row) => row.id.equals(id))).getSingle();
  }

  Future<List<DayPhotoRow>> dayPhotosForDate(String bizDate) {
    _validateBusinessDate(bizDate);
    return (db.select(db.dayPhotos)
          ..where((row) => row.bizDate.equals(bizDate) & row.deletedAt.isNull())
          ..orderBy([(row) => OrderingTerm.asc(row.id)]))
        .get();
  }

  Future<List<DayPhotoRow>> activeDayPhotos() {
    return (db.select(db.dayPhotos)
          ..where((row) => row.deletedAt.isNull())
          ..orderBy([
            (row) => OrderingTerm.asc(row.bizDate),
            (row) => OrderingTerm.asc(row.id),
          ]))
        .get();
  }

  Future<List<DayPhotoRow>> deletedDayPhotos() {
    return (db.select(db.dayPhotos)
          ..where((row) => row.deletedAt.isNotNull())
          ..orderBy([
            (row) => OrderingTerm.desc(row.deletedAt),
            (row) => OrderingTerm.desc(row.id),
          ]))
        .get();
  }

  Future<bool> softDeleteDayPhoto(int photoId) async {
    final changed =
        await (db.update(db.dayPhotos)
              ..where((row) => row.id.equals(photoId) & row.deletedAt.isNull()))
            .write(
              DayPhotosCompanion(deletedAt: Value(localIsoTimestamp(_clock()))),
            );
    return changed == 1;
  }

  Future<bool> restoreDayPhoto(int photoId) async {
    final changed =
        await (db.update(db.dayPhotos)..where(
              (row) => row.id.equals(photoId) & row.deletedAt.isNotNull(),
            ))
            .write(const DayPhotosCompanion(deletedAt: Value(null)));
    return changed == 1;
  }

  Future<LedgerStats> activeStats() async {
    final row = await db
        .customSelect(
          '''
      SELECT
        (SELECT COUNT(*) FROM customers WHERE deleted_at IS NULL)
          AS customer_count,
        (SELECT COUNT(*) FROM entries WHERE deleted_at IS NULL)
          AS entry_count
      ''',
          readsFrom: {db.customers, db.ledgerEntries},
        )
        .getSingle();
    return LedgerStats(
      customerCount: row.read<int>('customer_count'),
      entryCount: row.read<int>('entry_count'),
    );
  }

  Future<List<DeletedCustomerSummary>> deletedCustomers() async {
    final rows = await db
        .customSelect(
          '''
      SELECT c.id, c.name, c.note, c.pinyin_full, c.pinyin_abbr,
             c.created_at, c.deleted_at,
             COUNT(e.id) AS cascaded_entry_count
      FROM customers c
      LEFT JOIN entries e
        ON e.customer_id = c.id AND e.deleted_at = c.deleted_at
      WHERE c.deleted_at IS NOT NULL
      GROUP BY c.id
      ORDER BY c.deleted_at DESC, c.id DESC
      ''',
          readsFrom: {db.customers, db.ledgerEntries},
        )
        .get();
    return rows
        .map(
          (row) => DeletedCustomerSummary(
            customer: CustomerRow(
              id: row.read<int>('id'),
              name: row.read<String>('name'),
              note: row.read<String>('note'),
              pinyinFull: row.read<String>('pinyin_full'),
              pinyinAbbr: row.read<String>('pinyin_abbr'),
              createdAt: row.read<String>('created_at'),
              deletedAt: row.readNullable<String>('deleted_at'),
            ),
            cascadedEntryCount: row.read<int>('cascaded_entry_count'),
          ),
        )
        .toList(growable: false);
  }

  Future<List<DeletedEntryWithCustomer>> deletedEntries() async {
    final query =
        db.select(db.ledgerEntries).join([
            innerJoin(
              db.customers,
              db.customers.id.equalsExp(db.ledgerEntries.customerId),
            ),
          ])
          ..where(
            db.ledgerEntries.deletedAt.isNotNull() &
                db.customers.deletedAt.isNull(),
          )
          ..orderBy([
            OrderingTerm.desc(db.ledgerEntries.deletedAt),
            OrderingTerm.desc(db.ledgerEntries.id),
          ]);
    final rows = await query.get();
    return rows
        .map(
          (row) => DeletedEntryWithCustomer(
            entry: row.readTable(db.ledgerEntries),
            customer: row.readTable(db.customers),
          ),
        )
        .toList(growable: false);
  }

  Future<void> _ensureBusinessExists(String name) async {
    if ((await findActiveBusinessesWithExactName(name)).isNotEmpty) return;
    await addBusiness(name);
  }

  Future<void> _recordBusinessUse(String name, {required String usedAt}) async {
    final existing = await findActiveBusinessesWithExactName(name);
    if (existing.isEmpty) {
      final pinyin = PinyinIndex.fromName(name);
      await db
          .into(db.businesses)
          .insert(
            BusinessesCompanion.insert(
              name: name,
              pinyinFull: Value(pinyin.full),
              pinyinAbbr: Value(pinyin.abbr),
              useCount: const Value(1),
              lastUsed: Value(usedAt),
              createdAt: usedAt,
            ),
          );
      return;
    }
    final row = existing.first;
    await (db.update(
      db.businesses,
    )..where((item) => item.id.equals(row.id))).write(
      BusinessesCompanion(
        useCount: Value(row.useCount + 1),
        lastUsed: Value(usedAt),
      ),
    );
  }

  Future<CustomerRow> _requireActiveCustomer(int customerId) async {
    final customer = await getCustomerOrNull(customerId);
    if (customer == null) {
      throw StateError('客户不存在或已在回收站：$customerId');
    }
    return customer;
  }

  static void _validateBusinessDate(String value) {
    final match = RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value);
    final parsed = DateTime.tryParse(value);
    if (!match || parsed == null || businessDateOf(parsed) != value) {
      throw FormatException('业务日期格式不正确：$value');
    }
  }
}
