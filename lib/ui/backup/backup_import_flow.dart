import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/app_controller.dart';
import '../../app/app_theme.dart';
import '../../data/backup/backup_coordinator.dart';
import '../../data/backup/backup_models.dart';
import '../widgets/common.dart';

Future<bool> runBackupImportFlow(
  BuildContext context,
  PickedBackup picked,
) async {
  final controller = context.read<AppController>();
  final BackupDocument document;
  try {
    document = controller.backup.validate(picked);
  } on BackupValidationException catch (error) {
    if (!context.mounted) return false;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('这个备份不能导入'),
        content: Text(error.message),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('我知道了'),
          ),
        ],
      ),
    );
    return false;
  } catch (error) {
    if (!context.mounted) return false;
    await _showImportError(context, '读取备份失败：$error');
    return false;
  }

  if (!context.mounted) return false;
  final counts = document.counts;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('从这个备份恢复？'),
      content: Text(
        '${document.summary.displayText}。\n\n导入会完全替换手机里现在的账本。导入前会先自动保存一份「导入前备份」，防止手滑覆盖。',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text('先不导入'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: AppColors.red),
          onPressed: () => Navigator.pop(dialogContext, true),
          child: Text('导入 ${counts.customers} 人、${counts.entries} 笔账'),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return false;

  try {
    final result = await controller.backup.importReplacing(picked);
    await controller.reloadAfterImport();
    if (!context.mounted) return true;
    showLedgerSnack(context, '恢复完成：${result.imported.displayText}');
    return true;
  } catch (error) {
    if (!context.mounted) return false;
    await _showImportError(context, '没有导入：$error');
    return false;
  }
}

Future<void> _showImportError(BuildContext context, String message) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('恢复没有完成'),
      content: Text(message),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('我知道了'),
        ),
      ],
    ),
  );
}
