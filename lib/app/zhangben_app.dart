import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import '../ui/home_shell.dart';
import '../ui/backup/backup_import_flow.dart';
import '../ui/widgets/common.dart';
import 'app_controller.dart';
import 'app_theme.dart';

final class ZhangbenApp extends StatefulWidget {
  const ZhangbenApp({super.key, required this.controller});

  final AppController controller;

  @override
  State<ZhangbenApp> createState() => _ZhangbenAppState();
}

class _ZhangbenAppState extends State<ZhangbenApp> {
  final _navigatorKey = GlobalKey<NavigatorState>();
  StreamSubscription<String>? _incomingSubscription;

  @override
  void initState() {
    super.initState();
    _incomingSubscription = widget.controller.backup.incomingUris.listen(
      _handleIncomingBackup,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final initial = widget.controller.backup.takeInitialUri();
      if (initial != null) _handleIncomingBackup(initial);
    });
  }

  Future<void> _handleIncomingBackup(String uri) async {
    final context = _navigatorKey.currentContext;
    if (context == null) return;
    try {
      final picked = await widget.controller.backup.readIncomingUri(uri);
      if (context.mounted) await runBackupImportFlow(context, picked);
    } catch (error) {
      if (context.mounted) showLedgerSnack(context, '这个备份没能打开：$error');
    }
  }

  @override
  void dispose() {
    _incomingSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: widget.controller,
      child: Consumer<AppController>(
        builder: (context, state, _) => MaterialApp(
          navigatorKey: _navigatorKey,
          title: '记账本',
          debugShowCheckedModeBanner: false,
          theme: buildAppTheme(),
          darkTheme: buildAppTheme(),
          themeMode: ThemeMode.light,
          locale: const Locale('zh', 'CN'),
          supportedLocales: const [Locale('zh', 'CN')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          builder: (context, child) {
            final media = MediaQuery.of(context);
            return MediaQuery(
              data: media.copyWith(
                textScaler: TextScaler.linear(state.fontSize.scale),
              ),
              child: child!,
            );
          },
          home: const HomeShell(),
        ),
      ),
    );
  }
}
