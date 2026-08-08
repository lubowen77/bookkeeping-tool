import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zhangben/app/app_controller.dart';
import 'package:zhangben/app/zhangben_app.dart';
import 'package:zhangben/data/database/app_database.dart';
import 'package:zhangben/data/repositories/ledger_repository.dart';

void main() {
  testWidgets('首页显示原型四栏与适老记账表单', (tester) async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    final controller = AppController(LedgerRepository(database));
    await controller.initialize();
    addTearDown(controller.dispose);

    await tester.pumpWidget(ZhangbenApp(controller: controller));
    await tester.pumpAndSettle();

    expect(find.text('记一笔'), findsNWidgets(2));
    expect(find.text('流水'), findsOneWidget);
    expect(find.text('客户'), findsOneWidget);
    expect(find.text('我的'), findsOneWidget);
    expect(find.text('谁的账'), findsOneWidget);
    expect(find.text('什么业务'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const Key('amount-display')),
      400,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('多少钱'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const Key('save-entry')),
      500,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.byKey(const Key('save-entry')), findsOneWidget);
  });

  testWidgets('320dp 窄屏特大字号下业务按钮仍不小于 48dp', (tester) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final database = AppDatabase.forTesting(NativeDatabase.memory());
    final repository = LedgerRepository(database);
    await repository.setSetting('font_size', 'huge');
    final controller = AppController(repository);
    await controller.initialize();
    addTearDown(controller.dispose);

    await tester.pumpWidget(ZhangbenApp(controller: controller));
    await tester.pumpAndSettle();

    final button = find.byKey(const ValueKey('business-button-送货'));
    expect(button, findsOneWidget);
    expect(tester.getSize(button).height, greaterThanOrEqualTo(48));
    expect(tester.takeException(), isNull);
  });

  testWidgets('系统语言为英文时仍强制中文组件且日期选择器只用日历', (tester) async {
    tester.binding.platformDispatcher.localeTestValue = const Locale(
      'en',
      'US',
    );
    addTearDown(tester.binding.platformDispatcher.clearLocaleTestValue);
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    final controller = AppController(LedgerRepository(database));
    await controller.initialize();
    addTearDown(controller.dispose);

    await tester.pumpWidget(ZhangbenApp(controller: controller));
    await tester.pumpAndSettle();

    final pageContext = tester.element(find.byKey(const Key('record-page')));
    expect(Localizations.localeOf(pageContext), const Locale('zh', 'CN'));
    final material = MaterialLocalizations.of(pageContext);
    expect(material.copyButtonLabel, '复制');
    expect(material.pasteButtonLabel, '粘贴');
    expect(material.formatMonthYear(DateTime(2026, 8, 8)), contains('2026年'));

    await tester.tap(find.text('选日子'));
    await tester.pumpAndSettle();
    expect(find.byType(DatePickerDialog), findsOneWidget);
    expect(find.text('选这笔账是哪一天的'), findsOneWidget);
    expect(find.byIcon(Icons.edit_outlined), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
