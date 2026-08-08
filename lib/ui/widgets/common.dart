import 'package:flutter/material.dart';

import '../../app/app_theme.dart';
import '../../core/money.dart';

void showLedgerSnack(
  BuildContext context,
  String message, {
  String? actionLabel,
  VoidCallback? onAction,
  Duration duration = const Duration(milliseconds: 2600),
}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message),
        duration: duration,
        action: actionLabel == null || onAction == null
            ? null
            : SnackBarAction(label: actionLabel, onPressed: onAction),
      ),
    );
}

final class PageHeader extends StatelessWidget {
  const PageHeader({super.key, required this.title, this.subtitle});

  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Text(title, style: Theme.of(context).textTheme.titleLarge),
          ),
          if (subtitle != null)
            Text(
              subtitle!,
              style: Theme.of(context).textTheme.bodySmall,
              textAlign: TextAlign.right,
            ),
        ],
      ),
    );
  }
}

final class LedgerCard extends StatelessWidget {
  const LedgerCard({super.key, required this.child, this.margin});

  final Widget child;
  final EdgeInsets? margin;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: margin ?? const EdgeInsets.fromLTRB(13, 0, 13, 12),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }
}

final class FieldLabel extends StatelessWidget {
  const FieldLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 3),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 18,
          color: AppColors.muted,
          letterSpacing: 1,
        ),
      ),
    );
  }
}

final class BalanceText extends StatelessWidget {
  const BalanceText(this.cents, {super.key, this.showCurrency = false});

  final int cents;
  final bool showCurrency;

  @override
  Widget build(BuildContext context) {
    final (text, color) = cents > 0
        ? (
            '欠 ${showCurrency ? '¥' : ''}${Money.formatCents(cents)}',
            AppColors.red,
          )
        : cents < 0
        ? (
            '多付 ${showCurrency ? '¥' : ''}${Money.formatCents(-cents)}',
            AppColors.greenInk,
          )
        : ('已结清', AppColors.disabled);
    return Text(
      text,
      textAlign: TextAlign.right,
      style: TextStyle(
        fontSize: cents == 0 ? 18 : 22,
        fontWeight: cents == 0 ? FontWeight.w500 : FontWeight.w700,
        color: color,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );
  }
}

final class EmptyHint extends StatelessWidget {
  const EmptyHint(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 42, horizontal: 18),
      child: Center(
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 18, color: AppColors.disabled),
        ),
      ),
    );
  }
}
