import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/app_controller.dart';
import '../../app/app_theme.dart';
import '../../core/local_time.dart';
import '../../core/money.dart';
import '../../data/database/app_database.dart';
import '../../domain/ledger_models.dart';
import '../business/business_picker_page.dart';
import '../customer/customer_picker_page.dart';
import '../widgets/common.dart';
import '../widgets/money_input_formatter.dart';

final class TodayPage extends StatefulWidget {
  const TodayPage({super.key});

  @override
  State<TodayPage> createState() => _TodayPageState();
}

class _TodayPageState extends State<TodayPage> {
  late DateTime _date;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _date = DateTime(now.year, now.month, now.day);
  }

  DateTime get _today {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  String _label(DateTime date) {
    if (_sameDay(date, _today)) return '今天';
    if (_sameDay(date, _today.subtract(const Duration(days: 1)))) return '昨天';
    return chineseDateWithWeekday(date);
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      helpText: '查看哪一天的流水',
      cancelText: '先不选',
      confirmText: '查看这天',
      initialEntryMode: DatePickerEntryMode.calendarOnly,
    );
    if (picked != null && mounted) setState(() => _date = picked);
  }

  Future<void> _entryMenu(EntryWithCustomer item) async {
    final action = await showEntryEditor(context, item);
    if (!mounted || action == null) return;
    if (action == EntryEditAction.saved) {
      context.read<AppController>().dataChanged();
      showLedgerSnack(context, '这笔账已经改好了');
      return;
    }
    final entry = item.entry;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('删掉这笔账？'),
        content: Text(
          '要删掉「${item.customer.name} ${_kindBusiness(entry)} ¥${Money.formatCents(entry.amountCents)}」吗？\n\n删后会进回收站，还能找回。',
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
              '删掉 ${item.customer.name} ${_kindBusiness(entry)} ¥${Money.formatCents(entry.amountCents)}',
            ),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await context.read<AppController>().repository.softDeleteEntry(entry.id);
      if (!mounted) return;
      context.read<AppController>().dataChanged();
      showLedgerSnack(
        context,
        '已删掉：${item.customer.name} ¥${Money.formatCents(entry.amountCents)}（回收站可找回）',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AppController>();
    final revision = controller.revision;
    return ColoredBox(
      color: AppColors.paper,
      child: Column(
        key: const Key('today-page'),
        children: [
          const PageHeader(title: '流水', subtitle: '点某一笔可以改、删'),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                TextButton.icon(
                  onPressed: () => setState(
                    () => _date = _date.subtract(const Duration(days: 1)),
                  ),
                  icon: const Icon(Icons.arrow_back),
                  label: const Text('前一天'),
                ),
                OutlinedButton.icon(
                  onPressed: _pickDate,
                  icon: const Icon(Icons.calendar_month_outlined),
                  label: Text(_label(_date)),
                ),
                TextButton.icon(
                  onPressed: () => setState(
                    () => _date = _date.add(const Duration(days: 1)),
                  ),
                  icon: const Icon(Icons.arrow_forward),
                  label: const Text('后一天'),
                ),
              ],
            ),
          ),
          Expanded(
            child: FutureBuilder<List<EntryWithCustomer>>(
              key: ValueKey('${businessDateOf(_date)}-$revision'),
              future: controller.repository.entriesWithCustomersForDate(
                businessDateOf(_date),
              ),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final entries = snapshot.data!;
                if (entries.isEmpty) {
                  return ListView(
                    padding: const EdgeInsets.only(bottom: 12),
                    children: [
                      EmptyHint('${_label(_date)}还没记账'),
                      _DayPhotoSection(
                        bizDate: businessDateOf(_date),
                        dateLabel: _label(_date),
                      ),
                    ],
                  );
                }
                var debtCents = 0;
                var paymentCents = 0;
                for (final item in entries) {
                  final kind = EntryKind.fromStorage(item.entry.kind);
                  if (kind == EntryKind.debt) {
                    debtCents += item.entry.amountCents;
                  } else if (kind == EntryKind.payment) {
                    paymentCents += item.entry.amountCents;
                  }
                }
                return ListView(
                  padding: const EdgeInsets.only(bottom: 12),
                  children: [
                    LedgerCard(
                      child: Column(
                        children: [
                          for (var i = 0; i < entries.length; i++) ...[
                            _EntryRow(
                              item: entries[i],
                              onTap: () => _entryMenu(entries[i]),
                            ),
                            if (i < entries.length - 1)
                              const Divider(height: 1),
                          ],
                          const Divider(height: 1),
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 13,
                            ),
                            child: Row(
                              children: [
                                Text(
                                  '共 ${entries.length} 笔',
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                                const Spacer(),
                                Flexible(
                                  child: Text(
                                    '记了 ¥${Money.formatCents(debtCents)} · 收了 ¥${Money.formatCents(paymentCents)}',
                                    textAlign: TextAlign.right,
                                    style: const TextStyle(
                                      fontSize: 18,
                                      color: AppColors.muted,
                                      fontFeatures: [
                                        FontFeature.tabularFigures(),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    _DayPhotoSection(
                      bizDate: businessDateOf(_date),
                      dateLabel: _label(_date),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

final class _DayPhotoSection extends StatelessWidget {
  const _DayPhotoSection({required this.bizDate, required this.dateLabel});

  final String bizDate;
  final String dateLabel;

  Future<void> _capture(BuildContext context) async {
    try {
      final controller = context.read<AppController>();
      final photo = await controller.photos.captureForDate(bizDate);
      if (photo == null || !context.mounted) return;
      controller.dataChanged();
      showLedgerSnack(context, '拍好了，已挂在$dateLabel名下');
    } catch (error) {
      if (context.mounted) showLedgerSnack(context, '照片没存好：$error');
    }
  }

  Future<void> _view(BuildContext context, DayPhotoRow photo) async {
    final delete = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => _PhotoViewerPage(photo: photo, dateLabel: dateLabel),
      ),
    );
    if (delete != true || !context.mounted) return;
    await context.read<AppController>().repository.softDeleteDayPhoto(photo.id);
    if (!context.mounted) return;
    context.read<AppController>().dataChanged();
    showLedgerSnack(context, '已删掉这张照片（回收站可找回）');
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AppController>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(17, 5, 17, 8),
          child: Text(
            '当天的纸本照片（留痕备查）',
            style: TextStyle(fontSize: 18, color: AppColors.muted),
          ),
        ),
        SizedBox(
          height: 128,
          child: FutureBuilder<List<DayPhotoRow>>(
            key: ValueKey('photos-$bizDate-${controller.revision}'),
            future: controller.repository.dayPhotosForDate(bizDate),
            builder: (context, snapshot) {
              final photos = snapshot.data ?? const <DayPhotoRow>[];
              return ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                itemCount: photos.length + 1,
                separatorBuilder: (_, _) => const SizedBox(width: 10),
                itemBuilder: (context, index) {
                  if (index == photos.length) {
                    return OutlinedButton(
                      key: const Key('take-day-photo'),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(86, 112),
                        side: const BorderSide(
                          color: AppColors.disabled,
                          style: BorderStyle.solid,
                        ),
                        padding: const EdgeInsets.all(8),
                      ),
                      onPressed: () => _capture(context),
                      child: const Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.photo_camera_outlined),
                          SizedBox(height: 5),
                          Text('拍一张'),
                        ],
                      ),
                    );
                  }
                  final photo = photos[index];
                  final file = File(photo.filePath);
                  return InkWell(
                    key: ValueKey('day-photo-${photo.id}'),
                    onTap: () => _view(context, photo),
                    borderRadius: BorderRadius.circular(7),
                    child: Container(
                      width: 86,
                      clipBehavior: Clip.antiAlias,
                      decoration: BoxDecoration(
                        color: AppColors.card,
                        border: Border.all(color: AppColors.line),
                        borderRadius: BorderRadius.circular(7),
                      ),
                      child: Image.file(
                        file,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => const Center(
                          child: Icon(
                            Icons.broken_image_outlined,
                            color: AppColors.disabled,
                          ),
                        ),
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

final class _PhotoViewerPage extends StatelessWidget {
  const _PhotoViewerPage({required this.photo, required this.dateLabel});

  final DayPhotoRow photo;
  final String dateLabel;

  Future<void> _delete(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('删掉这张纸本照片？'),
        content: Text('$dateLabel的照片会进回收站，以后还能找回。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('先不删'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.red),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('删掉这张照片'),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text('$dateLabel的纸本照片'),
        actions: [
          TextButton.icon(
            onPressed: () => _delete(context),
            icon: const Icon(Icons.delete_outline, color: Colors.white),
            label: const Text('删除', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
      body: Center(
        child: InteractiveViewer(
          minScale: 0.8,
          maxScale: 5,
          child: Image.file(
            File(photo.filePath),
            errorBuilder: (_, _, _) => const Text(
              '照片文件已不在手机上',
              style: TextStyle(color: Colors.white, fontSize: 20),
            ),
          ),
        ),
      ),
    );
  }
}

String _kindLabel(EntryKind kind) => switch (kind) {
  EntryKind.initial => '期初旧账',
  EntryKind.debt => '记账',
  EntryKind.payment => '收款',
  EntryKind.discount => '抹零',
};

String _kindBusiness(LedgerEntryRow entry) {
  final kind = EntryKind.fromStorage(entry.kind);
  return kind == EntryKind.debt ? entry.business : _kindLabel(kind);
}

final class _EntryRow extends StatelessWidget {
  const _EntryRow({required this.item, required this.onTap});

  final EntryWithCustomer item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final entry = item.entry;
    final kind = EntryKind.fromStorage(entry.kind);
    final positive = kind.addsToBalance;
    return InkWell(
      key: ValueKey('today-entry-${entry.id}'),
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 70),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            children: [
              _KindStamp(kind),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.customer.name,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      '${_kindBusiness(entry)}${entry.note.isEmpty ? '' : ' · ${entry.note}'}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
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
      ),
    );
  }
}

final class _KindStamp extends StatelessWidget {
  const _KindStamp(this.kind);

  final EntryKind kind;

  @override
  Widget build(BuildContext context) {
    final (text, background, foreground) = switch (kind) {
      EntryKind.initial => ('初', AppColors.lineSoft, AppColors.muted),
      EntryKind.debt => ('记', AppColors.redBackground, AppColors.red),
      EntryKind.payment => ('收', AppColors.greenBackground, AppColors.greenInk),
      EntryKind.discount => (
        '抹',
        AppColors.amberBackground,
        AppColors.amberInk,
      ),
    };
    return Container(
      width: 38,
      height: 38,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: foreground,
        ),
      ),
    );
  }
}

enum EntryEditAction { saved, delete }

Future<EntryEditAction?> showEntryEditor(
  BuildContext context,
  EntryWithCustomer item,
) {
  return showModalBottomSheet<EntryEditAction>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: AppColors.card,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => EditEntrySheet(item: item),
  );
}

final class EditEntrySheet extends StatefulWidget {
  const EditEntrySheet({super.key, required this.item});

  final EntryWithCustomer item;

  @override
  State<EditEntrySheet> createState() => _EditEntrySheetState();
}

class _EditEntrySheetState extends State<EditEntrySheet> {
  late CustomerRow _customer;
  late DateTime _date;
  late TextEditingController _amount;
  late TextEditingController _business;
  late TextEditingController _note;
  bool _saving = false;

  LedgerEntryRow get _entry => widget.item.entry;
  EntryKind get _kind => EntryKind.fromStorage(_entry.kind);

  @override
  void initState() {
    super.initState();
    _customer = widget.item.customer;
    _date = DateTime.parse(_entry.bizDate);
    _amount = TextEditingController(
      text: Money.formatCents(_entry.amountCents),
    );
    _business = TextEditingController(text: _entry.business);
    _note = TextEditingController(text: _entry.note);
  }

  @override
  void dispose() {
    _amount.dispose();
    _business.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _pickCustomer() async {
    final customer = await Navigator.push<CustomerRow>(
      context,
      MaterialPageRoute(builder: (_) => const CustomerPickerPage()),
    );
    if (customer != null && mounted) setState(() => _customer = customer);
  }

  Future<void> _pickDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      helpText: '改成哪一天的账',
      cancelText: '先不改',
      confirmText: '改成这天',
      initialEntryMode: DatePickerEntryMode.calendarOnly,
    );
    if (date != null && mounted) setState(() => _date = date);
  }

  Future<void> _save() async {
    final cents = Money.tryParseCents(
      _amount.text,
      allowZero: _kind == EntryKind.initial,
    );
    if (cents == null) {
      showLedgerSnack(context, '请输入正确金额');
      return;
    }
    if (_kind == EntryKind.debt && _business.text.trim().isEmpty) {
      showLedgerSnack(context, '记账的业务还没写');
      return;
    }
    setState(() => _saving = true);
    await context.read<AppController>().repository.updateEntry(
      entryId: _entry.id,
      customerId: _customer.id,
      kind: _kind,
      amountCents: cents,
      bizDate: businessDateOf(_date),
      business: _business.text,
      note: _note.text,
    );
    if (mounted) Navigator.pop(context, EntryEditAction.saved);
  }

  Future<void> _pickBusiness() async {
    final business = await Navigator.push<BusinessRow>(
      context,
      MaterialPageRoute(builder: (_) => const BusinessPickerPage()),
    );
    if (business != null && mounted) {
      setState(() => _business.text = business.name);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        12,
        16,
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
                    '改这笔${_kindLabel(_kind)}',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('收起'),
                ),
              ],
            ),
            const SizedBox(height: 10),
            const Text('客户'),
            const SizedBox(height: 5),
            OutlinedButton.icon(
              onPressed: _pickCustomer,
              icon: const Icon(Icons.person_outline),
              label: Text(
                '${_customer.name}${_customer.note.isEmpty ? '' : '（${_customer.note}）'}',
              ),
            ),
            const SizedBox(height: 12),
            const Text('金额'),
            const SizedBox(height: 5),
            TextField(
              controller: _amount,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: [const MoneyInputFormatter()],
              style: const TextStyle(
                fontSize: 24,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
              decoration: const InputDecoration(prefixText: '¥ '),
            ),
            if (_kind == EntryKind.debt) ...[
              const SizedBox(height: 12),
              const Text('业务'),
              const SizedBox(height: 5),
              OutlinedButton.icon(
                onPressed: _pickBusiness,
                icon: const Icon(Icons.grid_view_outlined),
                label: Text(_business.text.isEmpty ? '从业务字典选' : _business.text),
              ),
            ],
            const SizedBox(height: 12),
            const Text('日期'),
            const SizedBox(height: 5),
            OutlinedButton.icon(
              onPressed: _pickDate,
              icon: const Icon(Icons.calendar_month_outlined),
              label: Text(chineseDateWithWeekday(_date)),
            ),
            const SizedBox(height: 12),
            const Text('备注（可不填）'),
            const SizedBox(height: 5),
            TextField(
              key: const Key('edit-entry-note'),
              controller: _note,
              maxLength: 50,
              maxLines: 1,
              decoration: const InputDecoration(
                hintText: '比如：纸箱 20 个',
                counterText: '',
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: Text(_saving ? '正在保存…' : '保存修改'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.red,
                side: const BorderSide(color: AppColors.red, width: 1.5),
              ),
              onPressed: () => Navigator.pop(context, EntryEditAction.delete),
              icon: const Icon(Icons.delete_outline),
              label: const Text('删除这笔'),
            ),
          ],
        ),
      ),
    );
  }
}
