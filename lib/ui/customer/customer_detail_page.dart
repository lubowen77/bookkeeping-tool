import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../app/app_controller.dart';
import '../../app/app_theme.dart';
import '../../core/local_time.dart';
import '../../core/money.dart';
import '../../data/billing/customer_bill_image_service.dart';
import '../../data/database/app_database.dart';
import '../../domain/ledger_models.dart';
import '../today/today_page.dart';
import '../widgets/common.dart';
import '../widgets/money_input_formatter.dart';

final class CustomerDetailPage extends StatefulWidget {
  const CustomerDetailPage({super.key, required this.customerId});

  final int customerId;

  @override
  State<CustomerDetailPage> createState() => _CustomerDetailPageState();
}

class _CustomerDetailPageState extends State<CustomerDetailPage> {
  Future<_CustomerDetailData> _load() async {
    final repository = context.read<AppController>().repository;
    final customer = await repository.getCustomer(widget.customerId);
    final balance = await repository.balanceCentsForCustomer(widget.customerId);
    final entries = await repository.entriesForCustomer(widget.customerId);
    return _CustomerDetailData(customer, balance, entries);
  }

  Future<void> _editCustomer(CustomerRow customer) async {
    final name = TextEditingController(text: customer.name);
    final note = TextEditingController(text: customer.note);
    final draft = await showDialog<(String, String)>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('改「${customer.name}」的资料'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('怎么称呼'),
              const SizedBox(height: 5),
              TextField(
                controller: name,
                autofocus: true,
                style: const TextStyle(fontSize: 20),
              ),
              const SizedBox(height: 12),
              const Text('备注（防重名，可不填）'),
              const SizedBox(height: 5),
              TextField(controller: note, style: const TextStyle(fontSize: 20)),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('先不改'),
          ),
          FilledButton(
            onPressed: () {
              final newName = name.text.trim();
              if (newName.isNotEmpty) {
                Navigator.pop(dialogContext, (newName, note.text.trim()));
              }
            },
            child: const Text('保存资料'),
          ),
        ],
      ),
    );
    name.dispose();
    note.dispose();
    if (draft == null || !mounted) return;
    final repository = context.read<AppController>().repository;
    final duplicate = (await repository.findActiveCustomersWithExactName(
      draft.$1,
    )).where((item) => item.id != customer.id).toList();
    if (!mounted) return;
    if (duplicate.isNotEmpty) {
      final proceed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('会和已有客户重名'),
          content: Text(
            '已有 ${duplicate.length} 位「${draft.$1}」。确定这不是同一个人，并且要这样保存吗？',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('先检查一下'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('不是同一人，保存'),
            ),
          ],
        ),
      );
      if (proceed != true || !mounted) return;
    }
    await repository.updateCustomer(
      customerId: customer.id,
      name: draft.$1,
      note: draft.$2,
    );
    if (!mounted) return;
    context.read<AppController>().dataChanged();
    showLedgerSnack(context, '「${draft.$1}」的资料已经改好');
  }

  Future<void> _deleteCustomer(CustomerRow customer, int balanceCents) async {
    final balanceLine = balanceCents == 0
        ? '这位客户现在已经结清。'
        : balanceCents > 0
        ? '注意：「${customer.name}」还欠 ¥${Money.formatCents(balanceCents)}。'
        : '注意：「${customer.name}」现在多付 ¥${Money.formatCents(-balanceCents)}。';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(balanceCents == 0 ? '删除这位客户？' : '这位客户还有余额'),
        content: Text('$balanceLine\n\n删除客户会把名下全部流水一起放进回收站。以后仍可以从回收站找回。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('先不删'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.red),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(
              balanceCents == 0
                  ? '删除「${customer.name}」'
                  : '删除「${customer.name}」及全部流水',
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final controller = context.read<AppController>();
    await controller.repository.softDeleteCustomer(customer.id);
    if (!mounted) return;
    if (controller.recordCustomer?.id == customer.id) {
      controller.setRecordCustomer(null);
    }
    controller.dataChanged();
    showLedgerSnack(context, '已删除「${customer.name}」（回收站可找回）');
    Navigator.pop(context);
  }

  Future<void> _settle(
    CustomerRow customer,
    int balanceCents, {
    int? initialPaymentCents,
    bool initialWriteOff = false,
    String initialNote = '',
  }) async {
    final result = await showModalBottomSheet<SettlementResult>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: AppColors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _SettlementSheet(
        customer: customer,
        balanceCents: balanceCents,
        initialPaymentCents: initialPaymentCents,
        initialWriteOff: initialWriteOff,
        initialNote: initialNote,
      ),
    );
    if (result == null || !mounted) return;
    context.read<AppController>().dataChanged();
    final payment = Money.formatCents(result.paymentCents);
    if (result.isSettled) {
      showLedgerSnack(
        context,
        '「${customer.name}」这次已结清',
        duration: const Duration(seconds: 5),
        actionLabel: '撤销',
        onAction: () => unawaited(_undoSettlement(customer, result)),
      );
    } else if (result.isOverpaid) {
      showLedgerSnack(
        context,
        '已收「${customer.name}」¥$payment；现在多付 ¥${Money.formatCents(-result.balanceAfterCents)}',
        duration: const Duration(seconds: 5),
        actionLabel: '撤销',
        onAction: () => unawaited(_undoSettlement(customer, result)),
      );
    } else {
      showLedgerSnack(
        context,
        '已收「${customer.name}」¥$payment；还欠 ¥${Money.formatCents(result.balanceAfterCents)}',
        duration: const Duration(seconds: 5),
        actionLabel: '撤销',
        onAction: () => unawaited(_undoSettlement(customer, result)),
      );
    }
  }

  Future<void> _undoSettlement(
    CustomerRow customer,
    SettlementResult result,
  ) async {
    final controller = context.read<AppController>();
    await controller.repository.softDeleteEntries([
      result.paymentEntryId,
      if (result.discountEntryId != null) result.discountEntryId!,
    ]);
    if (!mounted) return;
    controller.dataChanged();
    showLedgerSnack(context, '已撤销这次收款');
    await _settle(
      customer,
      result.balanceBeforeCents,
      initialPaymentCents: result.paymentCents,
      initialWriteOff: result.discountEntryId != null,
      initialNote: result.paymentNote,
    );
  }

  Future<void> _editEntry(CustomerRow customer, LedgerEntryRow entry) async {
    final action = await showEntryEditor(
      context,
      EntryWithCustomer(entry: entry, customer: customer),
    );
    if (action == null || !mounted) return;
    if (action == EntryEditAction.saved) {
      context.read<AppController>().dataChanged();
      showLedgerSnack(context, '这笔账已经改好了');
      return;
    }
    final label = entry.business.isEmpty
        ? switch (EntryKind.fromStorage(entry.kind)) {
            EntryKind.initial => '期初旧账',
            EntryKind.debt => '记账',
            EntryKind.payment => '收款',
            EntryKind.discount => '抹零',
          }
        : entry.business;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('删掉这笔账？'),
        content: Text(
          '要删掉「${customer.name} $label ¥${Money.formatCents(entry.amountCents)}」吗？\n\n删后会进回收站，还能找回。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('先不删'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.red),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(
              '删掉 ${customer.name} $label ¥${Money.formatCents(entry.amountCents)}',
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await context.read<AppController>().repository.softDeleteEntry(entry.id);
    if (!mounted) return;
    context.read<AppController>().dataChanged();
    showLedgerSnack(context, '已删掉：${customer.name}（回收站可找回）');
  }

  Future<void> _sendBill(
    CustomerRow customer,
    List<LedgerEntryRow> entries,
  ) async {
    final controller = context.read<AppController>();
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
    try {
      final shopName = await controller.repository.getSetting('shop_name');
      final result = await CustomerBillImageService(controller.repository.db)
          .generate(
            customer: customer,
            effectiveEntries: entries,
            shopName: shopName,
          );
      if (!mounted) return;
      Navigator.pop(context);
      await Navigator.push<void>(
        context,
        MaterialPageRoute(
          builder: (_) =>
              _BillPreviewPage(result: result, customerName: customer.name),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      Navigator.pop(context);
      showLedgerSnack(context, '账单图片没生成：$error');
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AppController>();
    final revision = controller.revision;
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
        title: const Text('客户账页'),
      ),
      body: FutureBuilder<_CustomerDetailData>(
        key: ValueKey(revision),
        future: _load(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final data = snapshot.data!;
          return ListView.builder(
            padding: const EdgeInsets.only(bottom: 20),
            itemCount: data.entries.length + 1,
            itemBuilder: (context, index) {
              if (index == 0) {
                return _DetailHeader(
                  data: data,
                  onSettle: () => _settle(data.customer, data.balanceCents),
                  onDebt: () {
                    controller.prepareDebtFor(data.customer);
                    Navigator.popUntil(context, (route) => route.isFirst);
                  },
                  onBill: () => _sendBill(data.customer, data.entries),
                  onEdit: () => _editCustomer(data.customer),
                  onDelete: () =>
                      _deleteCustomer(data.customer, data.balanceCents),
                );
              }
              final entry = data.entries[index - 1];
              return _DetailEntryRow(
                entry: entry,
                onTap: () => _editEntry(data.customer, entry),
              );
            },
          );
        },
      ),
    );
  }
}

final class _CustomerDetailData {
  const _CustomerDetailData(this.customer, this.balanceCents, this.entries);

  final CustomerRow customer;
  final int balanceCents;
  final List<LedgerEntryRow> entries;
}

enum _CustomerMenu { edit, delete }

final class _DetailHeader extends StatelessWidget {
  const _DetailHeader({
    required this.data,
    required this.onSettle,
    required this.onDebt,
    required this.onBill,
    required this.onEdit,
    required this.onDelete,
  });

  final _CustomerDetailData data;
  final VoidCallback onSettle;
  final VoidCallback onDebt;
  final VoidCallback onBill;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final balance = data.balanceCents;
    final (label, amount, color) = balance > 0
        ? ('欠款', '¥${Money.formatCents(balance)}', AppColors.red)
        : balance < 0
        ? ('多付', '¥${Money.formatCents(-balance)}', AppColors.greenInk)
        : ('已结清', '没有欠账', AppColors.muted);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
          child: Row(
            children: [
              Expanded(
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: data.customer.name,
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (data.customer.note.isNotEmpty)
                        TextSpan(
                          text: '  ${data.customer.note}',
                          style: const TextStyle(
                            fontSize: 18,
                            color: AppColors.muted,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              PopupMenuButton<_CustomerMenu>(
                tooltip: '更多操作',
                onSelected: (value) {
                  if (value == _CustomerMenu.edit) onEdit();
                  if (value == _CustomerMenu.delete) onDelete();
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(
                    value: _CustomerMenu.edit,
                    child: Row(
                      children: [
                        Icon(Icons.edit_outlined),
                        SizedBox(width: 8),
                        Text('编辑客户资料'),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: _CustomerMenu.delete,
                    child: Row(
                      children: [
                        Icon(Icons.delete_outline, color: AppColors.red),
                        SizedBox(width: 8),
                        Text('删除客户', style: TextStyle(color: AppColors.red)),
                      ],
                    ),
                  ),
                ],
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    minHeight: 48,
                    minWidth: 82,
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.more_horiz),
                      SizedBox(width: 4),
                      Text('更多'),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Column(
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 18,
                  color: AppColors.muted,
                  letterSpacing: 2,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                amount,
                key: const Key('detail-balance'),
                style: TextStyle(
                  fontSize: 40,
                  fontWeight: FontWeight.w800,
                  color: color,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
          child: Row(
            children: [
              Expanded(
                flex: 3,
                child: FilledButton.icon(
                  key: const Key('settle-customer'),
                  onPressed: data.balanceCents > 0 ? onSettle : null,
                  icon: const Icon(Icons.payments_outlined),
                  label: const Text('收款'),
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                flex: 2,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 64),
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                  ),
                  onPressed: onDebt,
                  icon: const Icon(Icons.edit_note),
                  label: const Text('记一笔账'),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
          child: OutlinedButton.icon(
            key: const Key('send-customer-bill'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(double.infinity, 56),
            ),
            onPressed: onBill,
            icon: const Icon(Icons.image_outlined),
            label: const Text('发账单给他（微信图片）'),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(17, 5, 17, 7),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text('逐笔流水', style: Theme.of(context).textTheme.titleMedium),
          ),
        ),
        if (data.entries.isEmpty) const EmptyHint('还没有流水'),
      ],
    );
  }
}

final class _DetailEntryRow extends StatelessWidget {
  const _DetailEntryRow({required this.entry, required this.onTap});

  final LedgerEntryRow entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final kind = EntryKind.fromStorage(entry.kind);
    final positive = kind.addsToBalance;
    final label = switch (kind) {
      EntryKind.initial => '期初旧账',
      EntryKind.debt => '记账',
      EntryKind.payment => '收款',
      EntryKind.discount => '抹零',
    };
    final date = DateTime.parse(entry.bizDate);
    return InkWell(
      key: ValueKey('detail-entry-${entry.id}'),
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        margin: const EdgeInsets.fromLTRB(13, 0, 13, 8),
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 12),
        constraints: const BoxConstraints(minHeight: 68),
        decoration: BoxDecoration(
          color: AppColors.card,
          border: Border.all(color: AppColors.line),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    kind == EntryKind.debt ? entry.business : label,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    '${chineseDateWithWeekday(date)}${entry.note.isEmpty ? '' : ' · ${entry.note}'}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            Text(
              '${positive ? '+' : '−'}${Money.formatCents(entry.amountCents)}',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: positive ? AppColors.red : AppColors.greenInk,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

final class _BillPreviewPage extends StatelessWidget {
  const _BillPreviewPage({required this.result, required this.customerName});

  final CustomerBillImageResult result;
  final String customerName;

  Future<void> _share(BuildContext context) async {
    try {
      final controller = context.read<AppController>();
      await controller.backup.shareFile(
        result.file,
        mimeType: 'image/png',
        title: '发「$customerName」的欠款账单',
        text: '「$customerName」的欠款对账单，如有疑问请当面对账。',
      );
      if (context.mounted) showLedgerSnack(context, '请选择微信联系人发送');
    } catch (error) {
      if (context.mounted) showLedgerSnack(context, '账单没发出：$error');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.paper,
      appBar: AppBar(
        backgroundColor: AppColors.paper,
        leadingWidth: 128,
        leading: TextButton.icon(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.chevron_left),
          label: const Text('返回'),
        ),
        title: const Text('账单预览'),
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(14),
              child: Image.file(
                result.file,
                fit: BoxFit.fitWidth,
                errorBuilder: (_, _, _) => const EmptyHint('账单图片已不在'),
              ),
            ),
          ),
          SafeArea(
            top: false,
            minimum: const EdgeInsets.fromLTRB(14, 10, 14, 12),
            child: FilledButton.icon(
              key: const Key('share-customer-bill'),
              style: FilledButton.styleFrom(
                minimumSize: const Size(double.infinity, 58),
              ),
              onPressed: () => _share(context),
              icon: const Icon(Icons.share_outlined),
              label: const Text('存成图片，发微信给他'),
            ),
          ),
        ],
      ),
    );
  }
}

final class _SettlementSheet extends StatefulWidget {
  const _SettlementSheet({
    required this.customer,
    required this.balanceCents,
    this.initialPaymentCents,
    this.initialWriteOff = false,
    this.initialNote = '',
  });

  final CustomerRow customer;
  final int balanceCents;
  final int? initialPaymentCents;
  final bool initialWriteOff;
  final String initialNote;

  @override
  State<_SettlementSheet> createState() => _SettlementSheetState();
}

class _SettlementSheetState extends State<_SettlementSheet> {
  late final TextEditingController _amount;
  late final TextEditingController _note;
  late bool _writeOff;
  bool _saving = false;

  int? get _cents => Money.tryParseCents(_amount.text);
  int? get _remaining => _cents == null ? null : widget.balanceCents - _cents!;

  @override
  void initState() {
    super.initState();
    _amount = TextEditingController(
      text: widget.initialPaymentCents == null
          ? ''
          : Money.formatCents(widget.initialPaymentCents!),
    );
    _note = TextEditingController(text: widget.initialNote);
    _writeOff = widget.initialWriteOff;
  }

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final cents = _cents;
    if (cents == null) {
      showLedgerSnack(context, '还没输入实收金额');
      return;
    }
    final remaining = widget.balanceCents - cents;
    final writeOff = _writeOff && remaining > 0;
    final detail = writeOff
        ? '实收 ¥${Money.formatCents(cents)}，剩余 ¥${Money.formatCents(remaining)} 抹零，本次结清。'
        : '实收 ¥${Money.formatCents(cents)}。${remaining > 0
              ? '收后还欠 ¥${Money.formatCents(remaining)}。'
              : remaining < 0
              ? '收后会多付 ¥${Money.formatCents(-remaining)}。'
              : '收后正好结清。'}';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('确认收「${widget.customer.name}」的钱？'),
        content: Text(detail),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('再核对一下'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('确认收款'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _saving = true);
    final result = await context.read<AppController>().repository.settle(
      customerId: widget.customer.id,
      paymentCents: cents,
      writeOffRemaining: writeOff,
      note: _note.text,
    );
    if (mounted) Navigator.pop(context, result);
  }

  @override
  Widget build(BuildContext context) {
    final cents = _cents;
    final remaining = _remaining;
    final canWriteOff = cents != null && remaining != null && remaining > 0;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        14,
        10,
        14,
        MediaQuery.viewInsetsOf(context).bottom + 18,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '收「${widget.customer.name}」的钱',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('收起'),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Center(
              child: Text(
                widget.balanceCents > 0
                    ? '现在欠 ¥${Money.formatCents(widget.balanceCents)}'
                    : widget.balanceCents < 0
                    ? '现在已多付 ¥${Money.formatCents(-widget.balanceCents)}'
                    : '现在已经结清',
                style: TextStyle(
                  fontSize: 20,
                  color: widget.balanceCents > 0
                      ? AppColors.red
                      : AppColors.greenInk,
                  fontWeight: FontWeight.w600,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: TextField(
                key: const Key('settlement-amount'),
                controller: _amount,
                autofocus: widget.initialPaymentCents == null,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: const <TextInputFormatter>[
                  MoneyInputFormatter(),
                ],
                textAlign: TextAlign.right,
                style: const TextStyle(
                  fontSize: 38,
                  fontWeight: FontWeight.w800,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
                decoration: const InputDecoration(
                  prefixText: '收 ¥ ',
                  hintText: '0',
                ),
                onChanged: (_) => setState(() {
                  if (_remaining == null || _remaining! <= 0) {
                    _writeOff = false;
                  }
                }),
              ),
            ),
            Center(
              child: Text(
                remaining == null
                    ? '请输入实际收到的钱'
                    : remaining > 0
                    ? '收后还欠 ¥${Money.formatCents(remaining)}'
                    : remaining == 0
                    ? '收后正好结清'
                    : '收后多付 ¥${Money.formatCents(-remaining)}',
                style: TextStyle(
                  fontSize: 18,
                  color: remaining != null && remaining < 0
                      ? AppColors.greenInk
                      : AppColors.muted,
                ),
              ),
            ),
            if (canWriteOff)
              CheckboxListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                controlAffinity: ListTileControlAffinity.leading,
                value: _writeOff,
                onChanged: (value) =>
                    setState(() => _writeOff = value ?? false),
                title: Text(
                  '剩下的 ¥${Money.formatCents(remaining)} 不要了（抹零），本次结清',
                  style: const TextStyle(fontSize: 18),
                ),
              ),
            const SizedBox(height: 8),
            const Text('备注（可不填）'),
            const SizedBox(height: 5),
            TextField(
              key: const Key('settlement-note'),
              controller: _note,
              maxLength: 50,
              maxLines: 1,
              decoration: const InputDecoration(
                hintText: '比如：微信转的 / 现金',
                counterText: '',
              ),
            ),
            const SizedBox(height: 10),
            FilledButton(
              key: const Key('confirm-settlement'),
              onPressed: _saving ? null : _save,
              child: Text(_saving ? '正在收款…' : '收 好'),
            ),
          ],
        ),
      ),
    );
  }
}
