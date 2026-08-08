import '../data/database/app_database.dart';

enum EntryKind {
  initial,
  debt,
  payment,
  discount;

  String get storageValue => name;

  bool get addsToBalance => this == initial || this == debt;

  static EntryKind fromStorage(String value) => EntryKind.values.firstWhere(
    (kind) => kind.storageValue == value,
    orElse: () => throw FormatException('未知流水类型：$value'),
  );
}

final class CustomerWithBalance {
  const CustomerWithBalance({
    required this.customer,
    required this.balanceCents,
  });

  final CustomerRow customer;
  final int balanceCents;
}

enum CustomerSort { balance, pinyin }

final class EntryWithCustomer {
  const EntryWithCustomer({required this.entry, required this.customer});

  final LedgerEntryRow entry;
  final CustomerRow customer;
}

final class SettlementResult {
  const SettlementResult({
    required this.paymentEntryId,
    required this.paymentCents,
    required this.discountEntryId,
    required this.balanceBeforeCents,
    required this.balanceAfterCents,
  });

  final int paymentEntryId;
  final int paymentCents;
  final int? discountEntryId;
  final int balanceBeforeCents;
  final int balanceAfterCents;

  bool get isSettled => balanceAfterCents == 0;
  bool get isOverpaid => balanceAfterCents < 0;
}

final class InitialCustomerResult {
  const InitialCustomerResult({
    required this.customer,
    required this.initialEntryId,
  });

  final CustomerRow customer;
  final int? initialEntryId;
}

/// “关于”与期初建档进度所需的有效数据统计。
final class LedgerStats {
  const LedgerStats({required this.customerCount, required this.entryCount});

  final int customerCount;
  final int entryCount;
}

/// 回收站中的客户及其随客户删除的流水数。
final class DeletedCustomerSummary {
  const DeletedCustomerSummary({
    required this.customer,
    required this.cascadedEntryCount,
  });

  final CustomerRow customer;
  final int cascadedEntryCount;
}

/// 回收站中的单笔流水。所属客户必须仍然有效。
final class DeletedEntryWithCustomer {
  const DeletedEntryWithCustomer({required this.entry, required this.customer});

  final LedgerEntryRow entry;
  final CustomerRow customer;
}
