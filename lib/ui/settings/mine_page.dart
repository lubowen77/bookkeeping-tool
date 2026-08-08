import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/app_controller.dart';
import '../../app/app_theme.dart';
import '../../data/database/app_database.dart';
import '../../domain/ledger_models.dart';
import '../backup/backup_card.dart';
import '../widgets/common.dart';
import 'business_settings_page.dart';
import 'initial_setup_page.dart';
import 'trash_page.dart';

final class MinePage extends StatelessWidget {
  const MinePage({super.key});

  Future<void> _open(BuildContext context, Widget page) async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(builder: (_) => page),
    );
    if (context.mounted) context.read<AppController>().dataChanged();
  }

  Future<void> _editShopName(BuildContext context) async {
    final app = context.read<AppController>();
    final current = await app.repository.getSetting('shop_name') ?? '';
    if (!context.mounted) return;
    var draft = current;
    final value = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('账单上的店家称呼'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('可不填。填了会显示在发给客户的账单顶部。'),
            const SizedBox(height: 8),
            TextFormField(
              key: const Key('shop-name-input'),
              initialValue: current,
              autofocus: true,
              style: const TextStyle(fontSize: 20),
              decoration: const InputDecoration(hintText: '比如：老王批发部'),
              onChanged: (value) => draft = value,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, ''),
            child: const Text('清空，不显示'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, draft.trim()),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (value == null || !context.mounted) return;
    await app.repository.setSetting('shop_name', value);
    if (!context.mounted) return;
    app.dataChanged();
    showLedgerSnack(
      context,
      value.isEmpty ? '账单将不显示店家称呼' : '账单店家称呼已设为「$value」',
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AppController>();
    return ColoredBox(
      color: AppColors.paper,
      child: Column(
        key: const Key('mine-page'),
        children: [
          const PageHeader(title: '我的'),
          Expanded(
            child: FutureBuilder<LedgerStats>(
              key: ValueKey(controller.revision),
              future: controller.repository.activeStats(),
              builder: (context, snapshot) {
                final stats = snapshot.data;
                return ListView(
                  padding: const EdgeInsets.only(bottom: 24),
                  children: [
                    const BackupCard(),
                    LedgerCard(
                      child: Column(
                        children: [
                          _MineLink(
                            key: const Key('open-initial-setup'),
                            title: '期初建档（录旧账）',
                            subtitle:
                                '把纸账本上每个人现在的欠款录进来 · 已录 ${stats?.customerCount ?? '—'} 人',
                            icon: Icons.playlist_add_outlined,
                            onTap: () =>
                                _open(context, const InitialSetupPage()),
                          ),
                          const Divider(height: 1),
                          FutureBuilder<List<BusinessRow>>(
                            future: controller.repository.activeBusinesses(),
                            builder: (context, businessSnapshot) {
                              final businesses =
                                  businessSnapshot.data ??
                                  const <BusinessRow>[];
                              final preview = businesses
                                  .take(4)
                                  .map((item) => item.name)
                                  .join('、');
                              return _MineLink(
                                key: const Key('open-business-settings'),
                                title: '业务字典',
                                subtitle: businesses.isEmpty
                                    ? '还没有业务'
                                    : '$preview 等 ${businesses.length} 项',
                                icon: Icons.grid_view_outlined,
                                onTap: () => _open(
                                  context,
                                  const BusinessSettingsPage(),
                                ),
                              );
                            },
                          ),
                          const Divider(height: 1),
                          FutureBuilder<String?>(
                            future: controller.repository.getSetting(
                              'shop_name',
                            ),
                            builder: (context, shopSnapshot) => _MineLink(
                              key: const Key('edit-shop-name'),
                              title: '账单店家称呼',
                              subtitle: (shopSnapshot.data ?? '').isEmpty
                                  ? '默认不显示'
                                  : shopSnapshot.data!,
                              icon: Icons.storefront_outlined,
                              onTap: () => _editShopName(context),
                            ),
                          ),
                          const Divider(height: 1),
                          _FontSizeSetting(value: controller.fontSize),
                          const Divider(height: 1),
                          _MineLink(
                            key: const Key('open-trash'),
                            title: '回收站',
                            subtitle: '删掉的账、客户、业务和照片都可以找回',
                            icon: Icons.restore_from_trash_outlined,
                            onTap: () => _open(context, const TrashPage()),
                          ),
                        ],
                      ),
                    ),
                    LedgerCard(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 15,
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(
                              Icons.info_outline,
                              color: AppColors.greenInk,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    '关于',
                                    style: TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '记账本 v1.5.1 · ${stats?.customerCount ?? '—'} 位客户 · ${stats?.entryCount ?? '—'} 笔账',
                                    key: const Key('about-stats'),
                                    style: Theme.of(
                                      context,
                                    ).textTheme.bodySmall,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.fromLTRB(30, 6, 30, 8),
                      child: Text(
                        '数据只存在这台手机里，不上传任何网络',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 18,
                          color: AppColors.disabled,
                          height: 1.5,
                        ),
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

final class _MineLink extends StatelessWidget {
  const _MineLink({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 72),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Icon(icon, color: AppColors.greenInk),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.chevron_right, color: AppColors.disabled),
            ],
          ),
        ),
      ),
    );
  }
}

final class _FontSizeSetting extends StatelessWidget {
  const _FontSizeSetting({required this.value});

  final AppFontSize value;

  @override
  Widget build(BuildContext context) {
    final controller = context.read<AppController>();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 13, 16, 15),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.format_size, color: AppColors.greenInk),
              SizedBox(width: 12),
              Text(
                '字体大小',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            key: const Key('font-size-selector'),
            children: [
              for (final option in AppFontSize.values)
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(
                      right: option == AppFontSize.extraLarge ? 0 : 7,
                    ),
                    child: _FontChoice(
                      option: option,
                      selected: value == option,
                      onPressed: () async {
                        await controller.setFontSize(option);
                        if (context.mounted) {
                          showLedgerSnack(context, '字体已调整，每一页都会变大');
                        }
                      },
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

final class _FontChoice extends StatelessWidget {
  const _FontChoice({
    required this.option,
    required this.selected,
    required this.onPressed,
  });

  final AppFontSize option;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final label = switch (option) {
      AppFontSize.standard => '标准',
      AppFontSize.large => '大',
      AppFontSize.extraLarge => '特大',
    };
    return Semantics(
      selected: selected,
      button: true,
      label: '$label字体',
      child: Material(
        color: selected ? AppColors.green : AppColors.card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: const BorderSide(color: AppColors.line, width: 1.5),
        ),
        child: InkWell(
          key: ValueKey('font-${option.storageValue}'),
          onTap: onPressed,
          borderRadius: BorderRadius.circular(10),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 52),
            child: Center(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: selected ? Colors.white : AppColors.muted,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
