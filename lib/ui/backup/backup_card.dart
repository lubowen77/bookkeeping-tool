import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/app_controller.dart';
import '../../app/app_theme.dart';
import '../widgets/common.dart';
import 'backup_import_flow.dart';

final class BackupCard extends StatefulWidget {
  const BackupCard({super.key});

  @override
  State<BackupCard> createState() => _BackupCardState();
}

class _BackupCardState extends State<BackupCard> {
  bool _busy = false;

  Future<(DateTime?, bool)> _status() async {
    final backup = context.read<AppController>().backup;
    return (
      await backup.lastSuccessfulBackup(),
      await backup.isBackupOverdue(),
    );
  }

  String _lastText(DateTime? value) {
    if (value == null) return '还没有成功备份';
    final now = DateTime.now();
    final day =
        value.year == now.year &&
            value.month == now.month &&
            value.day == now.day
        ? '今天'
        : '${value.month}月${value.day}日';
    return '上次备份：$day ${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _share() async {
    setState(() => _busy = true);
    try {
      await context.read<AppController>().backup.shareLatest();
      if (!mounted) return;
      context.read<AppController>().dataChanged();
      showLedgerSnack(context, '最新备份已生成，请选择微信发给家人');
    } catch (error) {
      if (mounted) showLedgerSnack(context, '备份没发出：$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restore() async {
    setState(() => _busy = true);
    try {
      final picked = await context
          .read<AppController>()
          .backup
          .pickBackupFile();
      if (picked != null && mounted) await runBackupImportFlow(context, picked);
    } catch (error) {
      if (mounted) showLedgerSnack(context, '没有读到备份：$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _exportPhotos() async {
    setState(() => _busy = true);
    try {
      final controller = context.read<AppController>();
      final photos = await controller.repository.activeDayPhotos();
      if (photos.isEmpty) {
        if (mounted) showLedgerSnack(context, '还没有纸本照片可导出');
        return;
      }
      final file = await controller.photos.exportPhotoZip();
      await controller.backup.shareFile(
        file,
        mimeType: 'application/zip',
        title: '分享记账照片（仅换机时用）',
        text: '记账本纸本照片，与账目备份分开保存。',
      );
      if (mounted) showLedgerSnack(context, '照片已单独打包，请选择保存或发送');
    } catch (error) {
      if (mounted) showLedgerSnack(context, '照片没能打包：$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AppController>();
    return FutureBuilder<(DateTime?, bool)>(
      key: ValueKey(controller.revision),
      future: _status(),
      builder: (context, snapshot) {
        final last = snapshot.data?.$1;
        final overdue = snapshot.data?.$2 ?? false;
        return Column(
          children: [
            if (overdue)
              Container(
                margin: const EdgeInsets.fromLTRB(14, 0, 14, 10),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: AppColors.amberBackground,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Row(
                  children: [
                    Icon(
                      Icons.warning_amber_rounded,
                      color: AppColors.amberInk,
                    ),
                    SizedBox(width: 9),
                    Expanded(
                      child: Text(
                        '已经超过 3 天没备份成功了，建议现在备份一次。',
                        style: TextStyle(
                          fontSize: 18,
                          color: AppColors.amberInk,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            LedgerCard(
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.inventory_2_outlined,
                          color: AppColors.greenInk,
                        ),
                        const SizedBox(width: 11),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                '自动备份',
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              Text(
                                '${_lastText(last)}\n账目备份只含数据，不含照片',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 5,
                          ),
                          decoration: const BoxDecoration(
                            color: AppColors.greenBackground,
                            borderRadius: BorderRadius.all(Radius.circular(99)),
                          ),
                          child: const Text(
                            '已开启',
                            style: TextStyle(
                              fontSize: 18,
                              color: AppColors.greenInk,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        FilledButton.icon(
                          key: const Key('share-backup'),
                          onPressed: _busy ? null : _share,
                          icon: const Icon(Icons.share_outlined),
                          label: Text(_busy ? '请稍候…' : '发送备份给家人'),
                        ),
                        const SizedBox(height: 8),
                        OutlinedButton.icon(
                          key: const Key('restore-backup'),
                          onPressed: _busy ? null : _restore,
                          icon: const Icon(Icons.settings_backup_restore),
                          label: const Text('从备份恢复'),
                        ),
                        const SizedBox(height: 8),
                        OutlinedButton.icon(
                          key: const Key('export-photo-zip'),
                          onPressed: _busy ? null : _exportPhotos,
                          icon: const Icon(Icons.photo_library_outlined),
                          label: const Text('照片打包导出（仅换机时用）'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}
