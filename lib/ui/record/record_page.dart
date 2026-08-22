import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

final class RecordPage extends StatefulWidget {
  const RecordPage({super.key});

  @override
  State<RecordPage> createState() => _RecordPageState();
}

class _RecordPageState extends State<RecordPage> {
  late DateTime _date;
  String? _business;
  final _amount = TextEditingController();
  final _note = TextEditingController();
  final _scroll = ScrollController();
  final _doneBarKey = GlobalKey();
  AppController? _controller;
  _RecordDone? _done;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _date = DateTime(now.year, now.month, now.day);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final controller = context.read<AppController>();
    if (!identical(_controller, controller)) {
      _controller?.removeListener(_handleControllerChange);
      _controller = controller..addListener(_handleControllerChange);
    }
  }

  @override
  void dispose() {
    _controller?.removeListener(_handleControllerChange);
    _scroll.dispose();
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  void _handleControllerChange() {
    if (_controller?.tabIndex != 0) _dismissDoneBar();
  }

  void _dismissDoneBar() {
    if (!mounted || _done == null) return;
    setState(() => _done = null);
  }

  void _showDoneBar(_RecordDone done) {
    setState(() => _done = done);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final doneContext = _doneBarKey.currentContext;
      if (!mounted || _done != done || doneContext == null) return;
      unawaited(_ensureDoneBarVisible(done, doneContext));
    });
  }

  Future<void> _ensureDoneBarVisible(
    _RecordDone done,
    BuildContext doneContext,
  ) async {
    await Scrollable.ensureVisible(
      doneContext,
      alignment: 1,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    );
    if (!mounted || _done != done || !_scroll.hasClients) return;
    await _scroll.animateTo(
      _scroll.position.maxScrollExtent,
      duration: const Duration(milliseconds: 120),
      curve: Curves.easeOut,
    );
  }

  DateTime get _today {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  String _dateText(DateTime value) {
    if (_isSameDay(value, _today)) return '今天';
    if (_isSameDay(value, _today.subtract(const Duration(days: 1)))) {
      return '昨天';
    }
    return chineseDateWithWeekday(value);
  }

  Future<({List<BusinessRow> top, bool selectedAlive})> _loadQuickBusinesses(
    AppController controller,
  ) async {
    final top = await controller.repository.activeBusinesses(limit: 5);
    final selected = _business;
    var selectedAlive = true;
    if (selected != null && !top.any((row) => row.name == selected)) {
      final matches = await controller.repository
          .findActiveBusinessesWithExactName(selected);
      selectedAlive = matches.isNotEmpty;
    }
    return (top: top, selectedAlive: selectedAlive);
  }

  Future<void> _pickCustomer() async {
    _dismissDoneBar();
    final customer = await Navigator.push<CustomerRow>(
      context,
      MaterialPageRoute(builder: (_) => const CustomerPickerPage()),
    );
    if (customer != null && mounted) {
      context.read<AppController>().setRecordCustomer(customer);
    }
  }

  Future<void> _chooseOtherBusiness() async {
    _dismissDoneBar();
    final result = await Navigator.push<BusinessRow>(
      context,
      MaterialPageRoute(builder: (_) => const BusinessPickerPage()),
    );
    if (result != null && mounted) setState(() => _business = result.name);
  }

  Future<void> _pickDate() async {
    _dismissDoneBar();
    final value = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      helpText: '选这笔账是哪一天的',
      cancelText: '先不选',
      confirmText: '选 好',
      initialEntryMode: DatePickerEntryMode.calendarOnly,
    );
    if (value != null && mounted) setState(() => _date = value);
  }

  Future<void> _save() async {
    _dismissDoneBar();
    final controller = context.read<AppController>();
    final customer = controller.recordCustomer;
    if (customer == null) {
      showLedgerSnack(context, '还没选客户——点最上面的「谁的账」');
      return;
    }
    if (_business == null || _business!.trim().isEmpty) {
      showLedgerSnack(context, '还没选业务');
      return;
    }
    final cents = Money.tryParseCents(_amount.text);
    if (cents == null) {
      showLedgerSnack(context, '还没输正确的金额');
      return;
    }
    setState(() => _saving = true);
    try {
      final activeCustomer = await controller.repository.getCustomerOrNull(
        customer.id,
      );
      if (activeCustomer == null || activeCustomer != customer) {
        controller.setRecordCustomer(null);
        if (mounted) showLedgerSnack(context, '客户已变动，请重新选一次');
        return;
      }
      final draftCustomer = activeCustomer;
      final draftBusiness = _business!;
      final draftAmount = _amount.text;
      final draftNote = _note.text.trim();
      final entry = await controller.repository.addEntry(
        customerId: activeCustomer.id,
        kind: EntryKind.debt,
        amountCents: cents,
        bizDate: businessDateOf(_date),
        business: _business!,
        note: draftNote,
      );
      if (!mounted) return;
      final dateSuffix = _isSameDay(_date, _today)
          ? ''
          : '（${_dateText(_date)}）';
      final done = _RecordDone(
        entryId: entry.id,
        customer: draftCustomer,
        business: draftBusiness,
        amount: draftAmount,
        amountCents: cents,
        note: draftNote,
        dateSuffix: dateSuffix,
      );
      controller.setRecordCustomer(null);
      controller.dataChanged();
      setState(() {
        _amount.clear();
        _note.clear();
      });
      _showDoneBar(done);
    } on StateError {
      controller.setRecordCustomer(null);
      if (mounted) showLedgerSnack(context, '客户已变动，请重新选一次');
    } catch (error) {
      if (mounted) showLedgerSnack(context, '没记上：$error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _undoDone() {
    final done = _done;
    if (done == null) return;
    setState(() => _done = null);
    unawaited(_undoEntry(done));
  }

  Future<void> _undoEntry(_RecordDone done) async {
    final controller = context.read<AppController>();
    await controller.repository.softDeleteEntries([done.entryId]);
    if (!mounted) return;
    controller.setRecordCustomer(done.customer);
    controller.dataChanged();
    setState(() {
      _business = done.business;
      _amount.text = done.amount;
      _amount.selection = TextSelection.collapsed(offset: done.amount.length);
      _note.text = done.note;
      _note.selection = TextSelection.collapsed(offset: done.note.length);
    });
    showLedgerSnack(context, '已撤回，这笔没记');
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AppController>();
    final customer = controller.recordCustomer;
    final now = DateTime.now();
    return ColoredBox(
      color: AppColors.paper,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: _dismissDoneBar,
        child: ListView(
          controller: _scroll,
          key: const Key('record-page'),
          padding: const EdgeInsets.only(bottom: 14),
          children: [
            PageHeader(title: '记一笔', subtitle: '${now.month}月${now.day}日'),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ChoiceChip(
                    label: const Text('今天'),
                    selected: _isSameDay(_date, _today),
                    onSelected: (_) => setState(() {
                      _done = null;
                      _date = _today;
                    }),
                  ),
                  ChoiceChip(
                    label: const Text('昨天'),
                    selected: _isSameDay(
                      _date,
                      _today.subtract(const Duration(days: 1)),
                    ),
                    onSelected: (_) => setState(() {
                      _done = null;
                      _date = _today.subtract(const Duration(days: 1));
                    }),
                  ),
                  ChoiceChip(
                    label: Text(
                      _isSameDay(_date, _today) ||
                              _isSameDay(
                                _date,
                                _today.subtract(const Duration(days: 1)),
                              )
                          ? '选日子'
                          : _dateText(_date),
                    ),
                    selected:
                        !_isSameDay(_date, _today) &&
                        !_isSameDay(
                          _date,
                          _today.subtract(const Duration(days: 1)),
                        ),
                    onSelected: (_) => _pickDate(),
                  ),
                ],
              ),
            ),
            LedgerCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const FieldLabel('谁的账'),
                  InkWell(
                    key: const Key('pick-customer'),
                    onTap: _pickCustomer,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: 58),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 10, 12),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                customer == null
                                    ? '点这里选客户'
                                    : '${customer.name}${customer.note.isEmpty ? '' : '（${customer.note}）'}',
                                style: TextStyle(
                                  fontSize: 21,
                                  fontWeight: customer == null
                                      ? FontWeight.w500
                                      : FontWeight.w600,
                                  color: customer == null
                                      ? AppColors.disabled
                                      : AppColors.ink,
                                ),
                              ),
                            ),
                            const Icon(
                              Icons.chevron_right,
                              color: AppColors.disabled,
                            ),
                            const Text(
                              '选择',
                              style: TextStyle(color: AppColors.muted),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            LedgerCard(
              child:
                  FutureBuilder<({List<BusinessRow> top, bool selectedAlive})>(
                    key: ValueKey('quick-businesses-${controller.revision}'),
                    future: _loadQuickBusinesses(controller),
                    builder: (context, snapshot) {
                      final businesses =
                          snapshot.data?.top ?? const <BusinessRow>[];
                      final selectedAlive =
                          snapshot.data?.selectedAlive ?? true;
                      final selected = _business;
                      if (selected != null &&
                          snapshot.hasData &&
                          !selectedAlive) {
                        // 字典里已删掉的业务不能留在选中态（§3.7 删除边界）
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (mounted && _business == selected) {
                            setState(() => _business = null);
                          }
                        });
                      }
                      final inTop = businesses.any(
                        (item) => item.name == selected,
                      );
                      final showPickedLabel =
                          selected != null && selectedAlive && !inTop;
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                            child: Row(
                              children: [
                                const Expanded(
                                  child: Text(
                                    '什么业务',
                                    style: TextStyle(
                                      fontSize: 18,
                                      color: AppColors.muted,
                                      letterSpacing: 1,
                                    ),
                                  ),
                                ),
                                if (showPickedLabel)
                                  _BusinessPickedLabel(
                                    key: const Key('business-picked-label'),
                                    business: selected,
                                    onTap: _chooseOtherBusiness,
                                  ),
                              ],
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(14, 7, 14, 14),
                            child: GridView.count(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              crossAxisCount: 3,
                              mainAxisSpacing: 8,
                              crossAxisSpacing: 8,
                              mainAxisExtent: 58,
                              children: [
                                for (final business in businesses)
                                  _BusinessButton(
                                    key: ValueKey(
                                      'business-button-${business.name}',
                                    ),
                                    text: business.name,
                                    selected: selected == business.name,
                                    onTap: () => setState(() {
                                      _done = null;
                                      _business = business.name;
                                    }),
                                  ),
                                _BusinessButton(
                                  key: const Key('business-button-more'),
                                  text: '更多…',
                                  selected: false,
                                  onTap: _chooseOtherBusiness,
                                ),
                              ],
                            ),
                          ),
                        ],
                      );
                    },
                  ),
            ),
            LedgerCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const FieldLabel('多少钱'),
                  Padding(
                    key: const Key('amount-display'),
                    padding: const EdgeInsets.fromLTRB(14, 4, 14, 12),
                    child: TextField(
                      controller: _amount,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      inputFormatters: const <TextInputFormatter>[
                        MoneyInputFormatter(),
                      ],
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                        fontSize: 38,
                        fontWeight: FontWeight.w700,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                      decoration: const InputDecoration(
                        prefixText: '¥ ',
                        hintText: '0',
                        helperText: '点一下，用手机键盘输数字',
                      ),
                      textInputAction: TextInputAction.done,
                      onTap: _dismissDoneBar,
                      onChanged: (_) => _dismissDoneBar(),
                      onSubmitted: (_) => _save(),
                    ),
                  ),
                ],
              ),
            ),
            LedgerCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const FieldLabel('备注（可不填，写具体是什么事）'),
                  TextField(
                    key: const Key('entry-note'),
                    controller: _note,
                    maxLength: 50,
                    maxLines: 1,
                    textInputAction: TextInputAction.done,
                    decoration: const InputDecoration(
                      hintText: '比如：纸箱 20 个 / 切 3 米板',
                      counterText: '',
                      filled: false,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      contentPadding: EdgeInsets.fromLTRB(16, 7, 16, 14),
                    ),
                    onTap: _dismissDoneBar,
                    onChanged: (_) => _dismissDoneBar(),
                    onSubmitted: (_) => _save(),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: FilledButton(
                key: const Key('save-entry'),
                onPressed: _saving ? null : _save,
                child: Text(_saving ? '正在记…' : '记 上'),
              ),
            ),
            if (_done case final done?)
              KeyedSubtree(
                key: _doneBarKey,
                child: DoneBar(
                  key: const Key('record-done-bar'),
                  leadingText: '已记上：',
                  emphasizedText:
                      '${done.customer.name} ${done.business} ¥${Money.formatCents(done.amountCents)}',
                  trailingText: done.dateSuffix,
                  note: done.note,
                  onUndo: _undoDone,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

final class _RecordDone {
  const _RecordDone({
    required this.entryId,
    required this.customer,
    required this.business,
    required this.amount,
    required this.amountCents,
    required this.note,
    required this.dateSuffix,
  });

  final int entryId;
  final CustomerRow customer;
  final String business;
  final String amount;
  final int amountCents;
  final String note;
  final String dateSuffix;
}

final class _BusinessPickedLabel extends StatelessWidget {
  const _BusinessPickedLabel({
    super.key,
    required this.business,
    required this.onTap,
  });

  final String business;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: MediaQuery.sizeOf(context).width * 0.58,
      ),
      child: Material(
        color: AppColors.greenBackground,
        shape: const StadiumBorder(
          side: BorderSide(color: AppColors.green, width: 1.5),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  '已选',
                  style: TextStyle(fontSize: 15, color: AppColors.greenInk),
                ),
                const SizedBox(width: 5),
                Flexible(
                  child: Text(
                    business,
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: AppColors.greenInk,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

final class _BusinessButton extends StatelessWidget {
  const _BusinessButton({
    super.key,
    required this.text,
    required this.selected,
    required this.onTap,
  });

  final String text;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppColors.greenBackground : AppColors.card,
      shape: RoundedRectangleBorder(
        side: BorderSide(
          color: selected ? AppColors.green : AppColors.line,
          width: 1.5,
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Center(
          child: Text(
            text,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 18,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              color: selected ? AppColors.greenInk : AppColors.ink,
            ),
          ),
        ),
      ),
    );
  }
}
