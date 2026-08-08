import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/app_controller.dart';
import '../../app/app_theme.dart';
import '../../core/money.dart';
import '../../data/database/app_database.dart';
import '../customer/customer_picker_page.dart';
import '../widgets/common.dart';
import '../widgets/money_input_formatter.dart';

final class InitialSetupPage extends StatefulWidget {
  const InitialSetupPage({super.key});

  @override
  State<InitialSetupPage> createState() => _InitialSetupPageState();
}

class _InitialSetupPageState extends State<InitialSetupPage> {
  final _name = TextEditingController();
  final _note = TextEditingController();
  final _amount = TextEditingController();
  final _nameFocus = FocusNode();
  var _savedCount = 0;
  var _saving = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadCount());
  }

  Future<void> _loadCount() async {
    final stats = await context.read<AppController>().repository.activeStats();
    if (mounted) setState(() => _savedCount = stats.customerCount);
  }

  Future<bool> _confirmDuplicate(String name, List<CustomerRow> same) async {
    if (same.isEmpty) return true;
    final repository = context.read<AppController>().repository;
    final lines = await Future.wait(
      same.map((customer) async {
        final balance = await repository.balanceCentsForCustomer(customer.id);
        final note = customer.note.isEmpty ? '没写备注' : customer.note;
        final balanceText = balance > 0
            ? '欠 ${MoneyText.short(balance)}'
            : balance < 0
            ? '多付 ${MoneyText.short(-balance)}'
            : '已结清';
        return '${customer.name}（$note）· $balanceText';
      }),
    );
    if (!mounted) return false;
    return await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('已经有同名客户'),
            content: Text(
              '账本里已有 ${same.length} 位「$name」：\n\n${lines.join('\n')}\n\n如果确实是另一人，建议在备注里写清区别。',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('是同一个人'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('是另一人，再建'),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _save() async {
    if (_saving) return;
    final name = _name.text.trim();
    if (name.isEmpty) {
      showLedgerSnack(context, '名字还没写');
      _nameFocus.requestFocus();
      return;
    }
    final cents = Money.tryParseCents(_amount.text, allowZero: true);
    if (cents == null) {
      showLedgerSnack(context, '请填正确的现在欠款，没欠请填 0');
      return;
    }

    setState(() => _saving = true);
    final repository = context.read<AppController>().repository;
    try {
      final same = await repository.findActiveCustomersWithExactName(name);
      final shouldCreate = await _confirmDuplicate(name, same);
      if (!shouldCreate || !mounted) return;
      await repository.addInitialCustomer(
        name: name,
        note: _note.text,
        currentDebtCents: cents,
      );
      if (!mounted) return;
      context.read<AppController>().dataChanged();
      setState(() => _savedCount++);
      _name.clear();
      _note.clear();
      _amount.clear();
      _nameFocus.requestFocus();
      final amountText = cents == 0 ? '' : ' 欠 ¥${Money.formatCents(cents)}';
      showLedgerSnack(context, '录好了：$name$amountText · 下一位');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _note.dispose();
    _amount.dispose();
    _nameFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.paper,
        toolbarHeight: 64,
        leadingWidth: 144,
        leading: TextButton.icon(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.chevron_left),
          label: const Text('先退出'),
        ),
        title: const Text('期初建档'),
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 24),
          children: [
            Center(
              child: Text.rich(
                TextSpan(
                  style: const TextStyle(fontSize: 18, color: AppColors.muted),
                  children: [
                    const TextSpan(text: '照着旧账本，一人一录 · 已录 '),
                    TextSpan(
                      text: '$_savedCount',
                      style: const TextStyle(
                        fontSize: 24,
                        color: AppColors.greenInk,
                        fontWeight: FontWeight.w700,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                    const TextSpan(text: ' 人'),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 18),
            const Text('怎么称呼', style: TextStyle(color: AppColors.muted)),
            const SizedBox(height: 5),
            TextField(
              key: const Key('setup-name'),
              controller: _name,
              focusNode: _nameFocus,
              autofocus: true,
              textInputAction: TextInputAction.next,
              style: const TextStyle(fontSize: 20),
              decoration: const InputDecoration(hintText: '比如：赵满仓'),
            ),
            const SizedBox(height: 14),
            const Text('备注（防重名，可不填）', style: TextStyle(color: AppColors.muted)),
            const SizedBox(height: 5),
            TextField(
              key: const Key('setup-note'),
              controller: _note,
              textInputAction: TextInputAction.next,
              style: const TextStyle(fontSize: 20),
              decoration: const InputDecoration(hintText: '比如：赵庄'),
            ),
            const SizedBox(height: 14),
            const Text(
              '现在欠多少钱（没欠填 0）',
              style: TextStyle(color: AppColors.muted),
            ),
            const SizedBox(height: 5),
            TextField(
              key: const Key('setup-amount'),
              controller: _amount,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: [const MoneyInputFormatter()],
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _save(),
              style: const TextStyle(
                fontSize: 22,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
              decoration: const InputDecoration(
                prefixText: '¥ ',
                hintText: '比如：1350',
              ),
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              key: const Key('save-initial-customer'),
              onPressed: _saving ? null : _save,
              icon: const Icon(Icons.save_outlined),
              label: Text(_saving ? '正在存…' : '存好，录下一位'),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(18, 18, 18, 0),
              child: Text(
                '只录现在欠的总数就行，以前一笔笔的旧账留在纸本上备查。',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 18,
                  height: 1.5,
                  color: AppColors.disabled,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
