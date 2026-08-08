import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/app_controller.dart';
import '../../app/app_theme.dart';
import '../../data/database/app_database.dart';
import '../widgets/common.dart';

final class BusinessSettingsPage extends StatefulWidget {
  const BusinessSettingsPage({super.key});

  @override
  State<BusinessSettingsPage> createState() => _BusinessSettingsPageState();
}

class _BusinessSettingsPageState extends State<BusinessSettingsPage> {
  final _search = TextEditingController();
  var _revision = 0;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _refresh() {
    context.read<AppController>().dataChanged();
    setState(() => _revision++);
  }

  Future<String?> _askName({required String title, String initial = ''}) async {
    var draft = initial;
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: TextFormField(
          key: const Key('business-name-input'),
          initialValue: initial,
          autofocus: true,
          style: const TextStyle(fontSize: 20),
          decoration: const InputDecoration(hintText: '比如：包装'),
          onChanged: (value) => draft = value,
          onFieldSubmitted: (value) {
            if (value.trim().isNotEmpty) {
              Navigator.pop(dialogContext, value.trim());
            }
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('先不'),
          ),
          FilledButton(
            onPressed: () {
              final value = draft.trim();
              if (value.isNotEmpty) Navigator.pop(dialogContext, value);
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
    return result;
  }

  Future<void> _add() async {
    final name = await _askName(title: '新业务');
    if (name == null || !mounted) return;
    try {
      await context.read<AppController>().repository.addBusiness(name);
      if (!mounted) return;
      _refresh();
      showLedgerSnack(context, '新业务「$name」建好了');
    } catch (error) {
      if (mounted) showLedgerSnack(context, error.toString());
    }
  }

  Future<void> _rename(BusinessRow item) async {
    final name = await _askName(title: '改业务名', initial: item.name);
    if (name == null || name == item.name || !mounted) return;
    try {
      await context.read<AppController>().repository.renameBusiness(
        item.id,
        name,
      );
      if (!mounted) return;
      _refresh();
      showLedgerSnack(context, '已改成「$name」，历史账仍保留原名');
    } catch (error) {
      if (mounted) showLedgerSnack(context, error.toString());
    }
  }

  Future<void> _delete(BusinessRow item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('删掉业务「${item.name}」？'),
        content: const Text('它会进回收站，可以找回。历史流水上的业务名不会改变。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('先不删'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.red),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text('删掉「${item.name}」'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await context.read<AppController>().repository.softDeleteBusiness(item.id);
    if (!mounted) return;
    _refresh();
    showLedgerSnack(context, '「${item.name}」已放进回收站');
  }

  @override
  Widget build(BuildContext context) {
    final repository = context.read<AppController>().repository;
    return Scaffold(
      backgroundColor: AppColors.paper,
      appBar: AppBar(
        backgroundColor: AppColors.paper,
        toolbarHeight: 64,
        leadingWidth: 128,
        leading: TextButton.icon(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.chevron_left),
          label: const Text('返回'),
        ),
        title: const Text('业务字典'),
        actions: [
          TextButton.icon(
            key: const Key('add-business'),
            onPressed: _add,
            icon: const Icon(Icons.add),
            label: const Text('新业务'),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 4, 14, 10),
            child: TextField(
              controller: _search,
              style: const TextStyle(fontSize: 20),
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: '找业务：名称 / 拼音 / 首字母',
              ),
              onChanged: (_) => setState(() => _revision++),
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              '使用越多的业务会自动排到记账页前面。改名、删除都不会改动历史账。',
              style: TextStyle(fontSize: 18, color: AppColors.muted),
            ),
          ),
          Expanded(
            child: FutureBuilder<List<BusinessRow>>(
              key: ValueKey('$_revision-${_search.text}'),
              future: repository.activeBusinesses(search: _search.text),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final items = snapshot.data!;
                if (items.isEmpty) return const EmptyHint('还没有业务');
                return ListView.separated(
                  padding: const EdgeInsets.only(bottom: 24),
                  itemCount: items.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final item = items[index];
                    return ListTile(
                      key: ValueKey('business-${item.id}'),
                      minTileHeight: 72,
                      title: Text(
                        item.name,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      subtitle: Text('用过 ${item.useCount} 次'),
                      trailing: Wrap(
                        spacing: 4,
                        children: [
                          TextButton(
                            onPressed: () => _rename(item),
                            child: const Text('改名'),
                          ),
                          TextButton(
                            style: TextButton.styleFrom(
                              foregroundColor: AppColors.red,
                            ),
                            onPressed: () => _delete(item),
                            child: const Text('删除'),
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
