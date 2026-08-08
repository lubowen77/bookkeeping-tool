import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/app_controller.dart';
import '../../app/app_theme.dart';
import '../../core/money.dart';
import '../../data/database/app_database.dart';
import '../../domain/ledger_models.dart';
import '../widgets/common.dart';

typedef _TrashData = ({
  List<DeletedCustomerSummary> customers,
  List<DeletedEntryWithCustomer> entries,
  List<BusinessRow> businesses,
  List<DayPhotoRow> photos,
});

final class TrashPage extends StatelessWidget {
  const TrashPage({super.key});

  Future<_TrashData> _load(BuildContext context) async {
    final repository = context.read<AppController>().repository;
    final results = await Future.wait([
      repository.deletedCustomers(),
      repository.deletedEntries(),
      repository.deletedBusinesses(),
      repository.deletedDayPhotos(),
    ]);
    return (
      customers: results[0] as List<DeletedCustomerSummary>,
      entries: results[1] as List<DeletedEntryWithCustomer>,
      businesses: results[2] as List<BusinessRow>,
      photos: results[3] as List<DayPhotoRow>,
    );
  }

  Future<void> _restoreCustomer(
    BuildContext context,
    DeletedCustomerSummary item,
  ) async {
    final customer = item.customer;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('找回「${customer.name}」？'),
        content: Text(
          item.cascadedEntryCount == 0
              ? '会把这位客户放回客户列表。'
              : '会把这位客户和当时一起删掉的 ${item.cascadedEntryCount} 笔账都找回来。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('先不找'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text('找回「${customer.name}」'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    await context.read<AppController>().repository.restoreCustomer(customer.id);
    if (!context.mounted) return;
    context.read<AppController>().dataChanged();
    showLedgerSnack(context, '已找回「${customer.name}」');
  }

  Future<void> _restoreEntry(
    BuildContext context,
    DeletedEntryWithCustomer item,
  ) async {
    await context.read<AppController>().repository.restoreEntry(item.entry.id);
    if (!context.mounted) return;
    context.read<AppController>().dataChanged();
    showLedgerSnack(
      context,
      '找回了 ${item.customer.name} 的 ¥${Money.formatCents(item.entry.amountCents)}',
    );
  }

  Future<void> _restoreBusiness(BuildContext context, BusinessRow item) async {
    try {
      await context.read<AppController>().repository.restoreBusiness(item.id);
      if (!context.mounted) return;
      context.read<AppController>().dataChanged();
      showLedgerSnack(context, '已找回业务「${item.name}」');
    } catch (error) {
      if (context.mounted) showLedgerSnack(context, '没能找回：$error');
    }
  }

  Future<void> _restorePhoto(BuildContext context, DayPhotoRow item) async {
    final controller = context.read<AppController>();
    if (!await File(item.filePath).exists()) {
      if (context.mounted) showLedgerSnack(context, '照片文件已不在手机上，无法找回');
      return;
    }
    await controller.repository.restoreDayPhoto(item.id);
    if (!context.mounted) return;
    controller.dataChanged();
    showLedgerSnack(context, '已找回 ${item.bizDate} 的纸本照片');
  }

  @override
  Widget build(BuildContext context) {
    final revision = context.watch<AppController>().revision;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.paper,
        toolbarHeight: 64,
        leadingWidth: 128,
        leading: TextButton.icon(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.chevron_left),
          label: const Text('返回'),
        ),
        title: const Text('回收站'),
      ),
      body: FutureBuilder<_TrashData>(
        key: ValueKey(revision),
        future: _load(context),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final data = snapshot.data!;
          if (data.customers.isEmpty &&
              data.entries.isEmpty &&
              data.businesses.isEmpty &&
              data.photos.isEmpty) {
            return const EmptyHint('回收站是空的');
          }
          return ListView(
            padding: const EdgeInsets.only(top: 8, bottom: 24),
            children: [
              if (data.customers.isNotEmpty) ...[
                const _SectionTitle('删掉的客户'),
                LedgerCard(
                  child: Column(
                    children: [
                      for (
                        var index = 0;
                        index < data.customers.length;
                        index++
                      ) ...[
                        _DeletedCustomerRow(
                          item: data.customers[index],
                          onRestore: () =>
                              _restoreCustomer(context, data.customers[index]),
                        ),
                        if (index < data.customers.length - 1)
                          const Divider(height: 1),
                      ],
                    ],
                  ),
                ),
              ],
              if (data.entries.isNotEmpty) ...[
                const _SectionTitle('删掉的账'),
                LedgerCard(
                  child: Column(
                    children: [
                      for (
                        var index = 0;
                        index < data.entries.length;
                        index++
                      ) ...[
                        _DeletedEntryRow(
                          item: data.entries[index],
                          onRestore: () =>
                              _restoreEntry(context, data.entries[index]),
                        ),
                        if (index < data.entries.length - 1)
                          const Divider(height: 1),
                      ],
                    ],
                  ),
                ),
              ],
              if (data.businesses.isNotEmpty) ...[
                const _SectionTitle('删掉的业务'),
                LedgerCard(
                  child: Column(
                    children: [
                      for (
                        var index = 0;
                        index < data.businesses.length;
                        index++
                      ) ...[
                        _DeletedBusinessRow(
                          item: data.businesses[index],
                          onRestore: () =>
                              _restoreBusiness(context, data.businesses[index]),
                        ),
                        if (index < data.businesses.length - 1)
                          const Divider(height: 1),
                      ],
                    ],
                  ),
                ),
              ],
              if (data.photos.isNotEmpty) ...[
                const _SectionTitle('删掉的纸本照片'),
                LedgerCard(
                  child: Column(
                    children: [
                      for (
                        var index = 0;
                        index < data.photos.length;
                        index++
                      ) ...[
                        _DeletedPhotoRow(
                          item: data.photos[index],
                          onRestore: () =>
                              _restorePhoto(context, data.photos[index]),
                        ),
                        if (index < data.photos.length - 1)
                          const Divider(height: 1),
                      ],
                    ],
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

final class _DeletedBusinessRow extends StatelessWidget {
  const _DeletedBusinessRow({required this.item, required this.onRestore});

  final BusinessRow item;
  final VoidCallback onRestore;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      minTileHeight: 72,
      leading: const Icon(Icons.grid_off_outlined, color: AppColors.red),
      title: Text(
        item.name,
        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
      ),
      subtitle: Text('用过 ${item.useCount} 次 · 历史账不受影响'),
      trailing: OutlinedButton(onPressed: onRestore, child: const Text('找回')),
    );
  }
}

final class _DeletedPhotoRow extends StatelessWidget {
  const _DeletedPhotoRow({required this.item, required this.onRestore});

  final DayPhotoRow item;
  final VoidCallback onRestore;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      minTileHeight: 72,
      leading: SizedBox(
        width: 48,
        height: 56,
        child: Image.file(
          File(item.filePath),
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => const Icon(
            Icons.broken_image_outlined,
            color: AppColors.disabled,
          ),
        ),
      ),
      title: Text(
        '${item.bizDate} 的纸本照片',
        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
      ),
      trailing: OutlinedButton(onPressed: onRestore, child: const Text('找回')),
    );
  }
}

final class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 7),
      child: Text(text, style: Theme.of(context).textTheme.titleMedium),
    );
  }
}

final class _DeletedCustomerRow extends StatelessWidget {
  const _DeletedCustomerRow({required this.item, required this.onRestore});

  final DeletedCustomerSummary item;
  final VoidCallback onRestore;

  @override
  Widget build(BuildContext context) {
    final customer = item.customer;
    return Padding(
      padding: const EdgeInsets.fromLTRB(15, 12, 11, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 38,
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.redBackground,
              borderRadius: BorderRadius.circular(9),
            ),
            child: const Icon(Icons.person_off_outlined, color: AppColors.red),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  customer.name,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  '${customer.note.isEmpty ? '没写备注' : customer.note} · 同时删掉 ${item.cascadedEntryCount} 笔账',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          OutlinedButton.icon(
            onPressed: onRestore,
            icon: const Icon(Icons.restore, size: 20),
            label: const Text('找回客户'),
          ),
        ],
      ),
    );
  }
}

final class _DeletedEntryRow extends StatelessWidget {
  const _DeletedEntryRow({required this.item, required this.onRestore});

  final DeletedEntryWithCustomer item;
  final VoidCallback onRestore;

  @override
  Widget build(BuildContext context) {
    final kind = EntryKind.fromStorage(item.entry.kind);
    final label = switch (kind) {
      EntryKind.initial => '期初旧账',
      EntryKind.debt => '记账',
      EntryKind.payment => '收款',
      EntryKind.discount => '抹零',
    };
    final positive = kind.addsToBalance;
    final business = item.entry.business.isEmpty
        ? label
        : '$label · ${item.entry.business}';
    return Padding(
      padding: const EdgeInsets.fromLTRB(15, 12, 11, 12),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: positive
                  ? AppColors.redBackground
                  : AppColors.greenBackground,
              borderRadius: BorderRadius.circular(9),
            ),
            child: Text(
              switch (kind) {
                EntryKind.initial => '初',
                EntryKind.debt => '记',
                EntryKind.payment => '收',
                EntryKind.discount => '抹',
              },
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: positive ? AppColors.red : AppColors.greenInk,
              ),
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${item.customer.name} · $business',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  '${item.entry.bizDate} · ¥${Money.formatCents(item.entry.amountCents)}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          OutlinedButton.icon(
            onPressed: onRestore,
            icon: const Icon(Icons.restore, size: 20),
            label: const Text('找回'),
          ),
        ],
      ),
    );
  }
}
