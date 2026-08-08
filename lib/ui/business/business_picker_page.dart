import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/app_controller.dart';
import '../../app/app_theme.dart';
import '../../data/database/app_database.dart';
import '../widgets/common.dart';

final class BusinessPickerPage extends StatefulWidget {
  const BusinessPickerPage({super.key});

  @override
  State<BusinessPickerPage> createState() => _BusinessPickerPageState();
}

class _BusinessPickerPageState extends State<BusinessPickerPage> {
  final _search = TextEditingController();
  var _revision = 0;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _newBusiness() async {
    var draft = '';
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('新业务'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('这个业务叫什么'),
            const SizedBox(height: 6),
            TextFormField(
              key: const Key('new-business-name'),
              autofocus: true,
              textInputAction: TextInputAction.done,
              style: const TextStyle(fontSize: 20),
              decoration: const InputDecoration(hintText: '比如：包装'),
              onChanged: (value) => draft = value,
              onFieldSubmitted: (value) {
                if (value.trim().isNotEmpty) {
                  Navigator.pop(dialogContext, value.trim());
                }
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('不建了'),
          ),
          FilledButton(
            key: const Key('confirm-new-business'),
            onPressed: () {
              final value = draft.trim();
              if (value.isNotEmpty) Navigator.pop(dialogContext, value);
            },
            child: const Text('建 好'),
          ),
        ],
      ),
    );
    if (name == null || !mounted) return;
    try {
      final repository = context.read<AppController>().repository;
      final business = await repository.addBusiness(name);
      if (!mounted) return;
      context.read<AppController>().dataChanged();
      Navigator.pop(context, business);
    } catch (error) {
      if (mounted) showLedgerSnack(context, error.toString());
    }
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
        title: const Text('选业务'),
        actions: [
          TextButton.icon(
            key: const Key('new-business'),
            onPressed: _newBusiness,
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
              key: const Key('business-search'),
              controller: _search,
              autofocus: true,
              style: const TextStyle(fontSize: 20),
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: '找业务：名称 / 拼音 / 首字母',
              ),
              onChanged: (_) => setState(() => _revision++),
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
                if (items.isEmpty) {
                  return const EmptyHint('没有这个业务，点右上角「＋ 新业务」');
                }
                return ListView.separated(
                  padding: const EdgeInsets.only(bottom: 20),
                  itemCount: items.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final item = items[index];
                    return ListTile(
                      key: ValueKey('pick-business-${item.id}'),
                      minTileHeight: 64,
                      title: Text(
                        item.name,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      subtitle: item.useCount == 0
                          ? null
                          : Text('用过 ${item.useCount} 次'),
                      trailing: const Icon(
                        Icons.chevron_right,
                        color: AppColors.disabled,
                      ),
                      onTap: () => Navigator.pop(context, item),
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
