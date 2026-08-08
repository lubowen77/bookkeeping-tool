import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/app_controller.dart';
import '../../app/app_theme.dart';
import '../../data/database/app_database.dart';
import '../../domain/ledger_models.dart';
import '../widgets/common.dart';

Future<CustomerRow?> showCreateCustomerFlow(BuildContext context) async {
  final draft = await showDialog<_CustomerDraft>(
    context: context,
    builder: (_) => const _NewCustomerDialog(),
  );
  if (draft == null || !context.mounted) return null;

  final controller = context.read<AppController>();
  final same = await controller.repository.findActiveCustomersWithExactName(
    draft.name,
  );
  if (!context.mounted) return null;
  if (same.isNotEmpty) {
    final rows = await Future.wait(
      same.map((customer) async {
        final balance = await controller.repository.balanceCentsForCustomer(
          customer.id,
        );
        final suffix = customer.note.isEmpty ? '没写备注' : customer.note;
        return '${customer.name}（$suffix）· ${balance > 0
            ? '欠'
            : balance < 0
            ? '多付'
            : '已结清'} ${balance == 0 ? '' : MoneyText.short(balance.abs())}';
      }),
    );
    if (!context.mounted) return null;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('已经有同名客户'),
        content: Text(
          '账本里已有 ${same.length} 位「${draft.name}」：\n\n${rows.join('\n')}\n\n如果确实是另一人，建议在备注里写清区别。',
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
    );
    if (confirmed != true || !context.mounted) return null;
  }

  final customer = await controller.repository.addCustomer(
    name: draft.name,
    note: draft.note,
  );
  controller.dataChanged();
  if (context.mounted) showLedgerSnack(context, '新客户「${customer.name}」建好了');
  return customer;
}

abstract final class MoneyText {
  static String short(int cents) {
    final whole = cents ~/ 100;
    final fraction = cents % 100;
    if (fraction == 0) return '¥$whole';
    return '¥$whole.${fraction.toString().padLeft(2, '0')}';
  }
}

final class CustomerPickerPage extends StatefulWidget {
  const CustomerPickerPage({super.key});

  @override
  State<CustomerPickerPage> createState() => _CustomerPickerPageState();
}

class _CustomerPickerPageState extends State<CustomerPickerPage> {
  static const _indexLetters = <String>[
    'A',
    'B',
    'C',
    'D',
    'E',
    'F',
    'G',
    'H',
    'I',
    'J',
    'K',
    'L',
    'M',
    'N',
    'O',
    'P',
    'Q',
    'R',
    'S',
    'T',
    'U',
    'V',
    'W',
    'X',
    'Y',
    'Z',
  ];

  final _search = TextEditingController();
  final _listController = ScrollController();
  final _groupKeys = <String, GlobalKey>{
    for (final letter in _indexLetters) letter: GlobalKey(),
    '#': GlobalKey(),
  };
  Map<String, List<CustomerWithBalance>> _visibleGroups = const {};
  int _visibleRecentCount = 0;
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    _listController.dispose();
    super.dispose();
  }

  Future<_PickerData> _load() async {
    final repository = context.read<AppController>().repository;
    final allFuture = repository.customersWithBalances(
      search: _query,
      sort: CustomerSort.pinyin,
    );
    final recentFuture = _query.isEmpty
        ? repository.customersWithBalances(recentFirst: true, limit: 8)
        : Future.value(const <CustomerWithBalance>[]);
    final results = await Future.wait([recentFuture, allFuture]);
    return _PickerData(recent: results[0], all: results[1]);
  }

  Map<String, List<CustomerWithBalance>> _groupCustomers(
    List<CustomerWithBalance> customers,
  ) {
    final groups = <String, List<CustomerWithBalance>>{};
    for (final item in customers) {
      final pinyin = item.customer.pinyinFull.trim();
      final first = pinyin.isEmpty ? '#' : pinyin.substring(0, 1).toUpperCase();
      final letter = _indexLetters.contains(first) ? first : '#';
      groups.putIfAbsent(letter, () => []).add(item);
    }
    return groups;
  }

  Future<void> _jumpToGroup(String letter) async {
    final groupContext = _groupKeys[letter]?.currentContext;
    if (groupContext != null) {
      await Scrollable.ensureVisible(
        groupContext,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOut,
        alignment: 0.04,
      );
      return;
    }

    // ListView 会懒加载远处分组；先利用本页固定行高定位，
    // 待目标组进入渲染区后再做一次精确对齐。
    final scale = context.read<AppController>().fontSize.scale;
    var offset = 0.0;
    if (_query.isEmpty && _visibleRecentCount > 0) {
      offset +=
          _SectionLabel.extent(scale) +
          _CustomerCard.extentFor(_visibleRecentCount, scale);
    }
    offset += _SectionLabel.extent(scale);
    for (final candidate in [..._indexLetters, '#']) {
      final customers = _visibleGroups[candidate];
      if (customers == null) continue;
      if (candidate == letter) break;
      offset +=
          _GroupLabel.extent(scale) +
          _CustomerCard.extentFor(customers.length, scale);
    }
    if (!_listController.hasClients) return;
    await _listController.animateTo(
      offset.clamp(0, _listController.position.maxScrollExtent),
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOut,
    );
    if (!mounted) return;
    final renderedContext = _groupKeys[letter]?.currentContext;
    if (renderedContext != null && renderedContext.mounted) {
      await Scrollable.ensureVisible(
        renderedContext,
        duration: const Duration(milliseconds: 120),
        alignment: 0.04,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    context.watch<AppController>().revision;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.paper,
        title: const Text('选客户'),
        leadingWidth: 128,
        leading: TextButton.icon(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.chevron_left),
          label: const Text('返回'),
        ),
        actions: [
          TextButton.icon(
            onPressed: () async {
              final customer = await showCreateCustomerFlow(context);
              if (customer != null && context.mounted) {
                Navigator.pop(context, customer);
              }
            },
            icon: const Icon(Icons.person_add_alt_1),
            label: const Text('新客户'),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 6, 14, 10),
            child: TextField(
              controller: _search,
              autofocus: false,
              style: const TextStyle(fontSize: 20),
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                labelText: '找人',
                hintText: '名字 / 拼音 / 首字母，如 zls',
              ),
              onChanged: (value) => setState(() => _query = value.trim()),
            ),
          ),
          Expanded(
            child: FutureBuilder<_PickerData>(
              future: _load(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final data = snapshot.data!;
                if (data.all.isEmpty) {
                  return const EmptyHint('没找到，点右上角「新客户」');
                }
                final groups = _groupCustomers(data.all);
                _visibleGroups = groups;
                _visibleRecentCount = data.recent.length;
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: ListView(
                        key: const Key('customer-picker-list'),
                        controller: _listController,
                        children: [
                          if (_query.isEmpty && data.recent.isNotEmpty) ...[
                            const _SectionLabel('最近打交道的'),
                            _CustomerCard(
                              key: const Key('recent-customers'),
                              customers: data.recent,
                            ),
                          ],
                          _SectionLabel(_query.isEmpty ? '全部客户' : '搜索结果'),
                          for (final letter in [..._indexLetters, '#'])
                            if (groups[letter] case final customers?) ...[
                              _GroupLabel(
                                key: _groupKeys[letter],
                                letter: letter,
                              ),
                              _CustomerCard(
                                key: ValueKey('customer-group-card-$letter'),
                                customers: customers,
                              ),
                            ],
                          const SizedBox(height: 18),
                        ],
                      ),
                    ),
                    _AlphabetIndex(
                      availableLetters: groups.keys.toSet(),
                      onLetterTap: _jumpToGroup,
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

final class _PickerData {
  const _PickerData({required this.recent, required this.all});

  final List<CustomerWithBalance> recent;
  final List<CustomerWithBalance> all;
}

final class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  static double extent(double scale) => 40 * scale;

  final String text;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: extent(context.read<AppController>().fontSize.scale),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 6),
        child: Text(
          text,
          style: const TextStyle(fontSize: 18, color: AppColors.muted),
        ),
      ),
    );
  }
}

final class _GroupLabel extends StatelessWidget {
  const _GroupLabel({super.key, required this.letter});

  static double extent(double scale) => 40 * scale;

  final String letter;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      header: true,
      child: SizedBox(
        height: extent(context.read<AppController>().fontSize.scale),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 5),
          child: Text(
            letter,
            key: ValueKey('customer-group-$letter'),
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: AppColors.greenInk,
            ),
          ),
        ),
      ),
    );
  }
}

final class _CustomerCard extends StatelessWidget {
  const _CustomerCard({super.key, required this.customers});

  static double extentFor(int customerCount, double scale) =>
      customerCount * _CustomerRow.extent(scale) + (customerCount - 1) + 12;

  final List<CustomerWithBalance> customers;

  @override
  Widget build(BuildContext context) {
    return LedgerCard(
      child: Column(
        children: [
          for (var i = 0; i < customers.length; i++) ...[
            _CustomerRow(
              item: customers[i],
              onTap: () => Navigator.pop(context, customers[i].customer),
            ),
            if (i < customers.length - 1) const Divider(height: 1),
          ],
        ],
      ),
    );
  }
}

final class _AlphabetIndex extends StatelessWidget {
  const _AlphabetIndex({
    required this.availableLetters,
    required this.onLetterTap,
  });

  final Set<String> availableLetters;
  final ValueChanged<String> onLetterTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      // 左边框占 1dp，外层留 49dp 以保证字母的实际点击区为 48dp。
      width: 49,
      decoration: const BoxDecoration(
        color: AppColors.card,
        border: Border(left: BorderSide(color: AppColors.line)),
      ),
      child: ListView(
        key: const Key('customer-alphabet-index'),
        padding: EdgeInsets.zero,
        children: [
          for (final letter in _CustomerPickerPageState._indexLetters)
            SizedBox(
              key: ValueKey('customer-index-$letter'),
              width: 48,
              height: 48,
              child: InkWell(
                onTap: availableLetters.contains(letter)
                    ? () => onLetterTap(letter)
                    : null,
                child: Center(
                  child: Text(
                    letter,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: availableLetters.contains(letter)
                          ? AppColors.greenInk
                          : AppColors.disabled,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

final class _CustomerRow extends StatelessWidget {
  const _CustomerRow({required this.item, required this.onTap});

  static double extent(double scale) => 72 * scale;

  final CustomerWithBalance item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final customer = item.customer;
    return InkWell(
      onTap: onTap,
      child: SizedBox(
        height: extent(context.read<AppController>().fontSize.scale),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      customer.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (customer.note.isNotEmpty)
                      Text(
                        customer.note,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              BalanceText(item.balanceCents),
            ],
          ),
        ),
      ),
    );
  }
}

final class _CustomerDraft {
  const _CustomerDraft(this.name, this.note);

  final String name;
  final String note;
}

final class _NewCustomerDialog extends StatefulWidget {
  const _NewCustomerDialog();

  @override
  State<_NewCustomerDialog> createState() => _NewCustomerDialogState();
}

class _NewCustomerDialogState extends State<_NewCustomerDialog> {
  final _name = TextEditingController();
  final _note = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('新客户'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('怎么称呼（照账本上写）'),
            const SizedBox(height: 6),
            TextField(
              controller: _name,
              autofocus: true,
              style: const TextStyle(fontSize: 20),
              decoration: InputDecoration(
                hintText: '比如：张老三',
                errorText: _error,
              ),
            ),
            const SizedBox(height: 14),
            const Text('备注（哪里的人 / 干什么的，防重名）'),
            const SizedBox(height: 6),
            TextField(
              controller: _note,
              style: const TextStyle(fontSize: 20),
              decoration: const InputDecoration(hintText: '比如：东村，可不填'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('不建了'),
        ),
        FilledButton(
          onPressed: () {
            final name = _name.text.trim();
            if (name.isEmpty) {
              setState(() => _error = '名字还没写');
              return;
            }
            Navigator.pop(context, _CustomerDraft(name, _note.text.trim()));
          },
          child: const Text('建 好'),
        ),
      ],
    );
  }
}
