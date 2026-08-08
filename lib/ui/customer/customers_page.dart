import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/app_controller.dart';
import '../../app/app_theme.dart';
import '../../core/money.dart';
import '../../domain/ledger_models.dart';
import '../widgets/common.dart';
import 'customer_detail_page.dart';
import 'customer_picker_page.dart';

final class CustomersPage extends StatefulWidget {
  const CustomersPage({super.key});

  @override
  State<CustomersPage> createState() => _CustomersPageState();
}

class _CustomersPageState extends State<CustomersPage> {
  final _search = TextEditingController();
  final _scroll = ScrollController();
  String _query = '';
  bool _onlyOwing = false;
  CustomerSort _sort = CustomerSort.balance;

  @override
  void dispose() {
    _search.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<List<CustomerWithBalance>> _load() {
    return context.read<AppController>().repository.customersWithBalances(
      search: _query,
      onlyOwing: _onlyOwing,
      sort: _sort,
    );
  }

  Future<List<CustomerWithBalance>> _loadAll() {
    return context.read<AppController>().repository.customersWithBalances();
  }

  void _jumpTo(String letter, List<CustomerWithBalance> customers) {
    final index = customers.indexWhere((item) {
      final pinyin = item.customer.pinyinFull;
      return pinyin.isNotEmpty && pinyin[0].toUpperCase() == letter;
    });
    if (index < 0) return;
    final rowExtent = 77 * context.read<AppController>().fontSize.scale;
    _scroll.animateTo(
      index * rowExtent,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AppController>();
    final rowExtent = 77 * controller.fontSize.scale;
    final revision = controller.revision;
    return ColoredBox(
      color: AppColors.paper,
      child: Column(
        key: const Key('customers-page'),
        children: [
          FutureBuilder<List<CustomerWithBalance>>(
            key: ValueKey('customer-count-$revision'),
            future: _loadAll(),
            builder: (context, snapshot) => PageHeader(
              title: '客户',
              subtitle: snapshot.hasData
                  ? '共 ${snapshot.data!.length} 人'
                  : null,
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
            child: TextField(
              controller: _search,
              style: const TextStyle(fontSize: 20),
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: '找人：名字 / 拼音 / 首字母',
              ),
              onChanged: (value) => setState(() => _query = value.trim()),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ChoiceChip(
                  label: const Text('全部'),
                  selected: !_onlyOwing,
                  onSelected: (_) => setState(() => _onlyOwing = false),
                ),
                ChoiceChip(
                  label: const Text('有欠款的'),
                  selected: _onlyOwing,
                  onSelected: (_) => setState(() => _onlyOwing = true),
                ),
                ChoiceChip(
                  avatar: Icon(
                    _sort == CustomerSort.balance
                        ? Icons.south_outlined
                        : Icons.sort_by_alpha_outlined,
                    size: 20,
                  ),
                  label: Text(_sort == CustomerSort.balance ? '按欠款多少' : '按拼音'),
                  selected: true,
                  onSelected: (_) => setState(
                    () => _sort = _sort == CustomerSort.balance
                        ? CustomerSort.pinyin
                        : CustomerSort.balance,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: FutureBuilder<List<CustomerWithBalance>>(
              key: ValueKey('$_query-$_onlyOwing-$_sort-$revision'),
              future: _load(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final customers = snapshot.data!;
                final owingTotalCents = customers.fold<int>(
                  0,
                  (sum, item) => sum + math.max(item.balanceCents, 0),
                );
                return Stack(
                  children: [
                    if (customers.isEmpty)
                      const Positioned.fill(
                        child: Align(
                          alignment: Alignment.topCenter,
                          child: EmptyHint('没有找到符合条件的客户'),
                        ),
                      )
                    else
                      Align(
                        alignment: Alignment.topCenter,
                        child: Padding(
                          padding: EdgeInsets.fromLTRB(
                            13,
                            0,
                            _sort == CustomerSort.pinyin ? 59 : 13,
                            0,
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              SizedBox(
                                height: math.min(
                                  customers.length * rowExtent + 2,
                                  MediaQuery.sizeOf(context).height * 0.52,
                                ),
                                child: Card(
                                  clipBehavior: Clip.antiAlias,
                                  child: ListView.separated(
                                    controller: _scroll,
                                    itemCount: customers.length,
                                    separatorBuilder: (_, _) =>
                                        const Divider(height: 1),
                                    itemBuilder: (context, index) => SizedBox(
                                      height: rowExtent - 1,
                                      child: _CustomerListRow(
                                        item: customers[index],
                                        onTap: () async {
                                          await Navigator.push<void>(
                                            context,
                                            MaterialPageRoute(
                                              builder: (_) =>
                                                  CustomerDetailPage(
                                                    customerId: customers[index]
                                                        .customer
                                                        .id,
                                                  ),
                                            ),
                                          );
                                          if (mounted) {
                                            controller.dataChanged();
                                          }
                                        },
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.fromLTRB(8, 4, 8, 76),
                                child: Text(
                                  '外面共欠着 ¥${Money.formatCents(owingTotalCents)}',
                                  key: const Key('customers-total-owing'),
                                  textAlign: TextAlign.center,
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    if (_sort == CustomerSort.pinyin && customers.isNotEmpty)
                      Positioned(
                        top: 0,
                        right: 4,
                        bottom: 82,
                        width: 52,
                        child: Material(
                          color: AppColors.greenBackground,
                          borderRadius: BorderRadius.circular(14),
                          child: ListView(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            children: [
                              for (final code in List.generate(
                                26,
                                (i) => 65 + i,
                              ))
                                SizedBox(
                                  height: 48,
                                  child: TextButton(
                                    onPressed: () => _jumpTo(
                                      String.fromCharCode(code),
                                      customers,
                                    ),
                                    child: Text(
                                      String.fromCharCode(code),
                                      style: const TextStyle(fontSize: 18),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    Positioned(
                      right: 16,
                      bottom: 16,
                      child: FilledButton.icon(
                        key: const Key('add-customer'),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(154, 58),
                          shape: const StadiumBorder(),
                          elevation: 4,
                        ),
                        onPressed: () async {
                          final customer = await showCreateCustomerFlow(
                            context,
                          );
                          if (customer != null && mounted) setState(() {});
                        },
                        icon: const Icon(Icons.person_add_alt_1),
                        label: const Text('新客户'),
                      ),
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

final class _CustomerListRow extends StatelessWidget {
  const _CustomerListRow({required this.item, required this.onTap});

  final CustomerWithBalance item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final customer = item.customer;
    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 76),
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
              BalanceText(item.balanceCents, showCurrency: true),
            ],
          ),
        ),
      ),
    );
  }
}
