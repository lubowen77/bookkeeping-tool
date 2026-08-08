import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zhangben/app/app_controller.dart';
import 'package:zhangben/app/zhangben_app.dart';
import 'package:zhangben/data/database/app_database.dart';
import 'package:zhangben/data/repositories/ledger_repository.dart';
import 'package:zhangben/domain/ledger_models.dart';

void main() {
  Future<(AppController, LedgerRepository)> pumpApp(WidgetTester tester) async {
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1;
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    final repository = LedgerRepository(database);
    final controller = AppController(repository);
    await controller.initialize();
    addTearDown(controller.dispose);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(ZhangbenApp(controller: controller));
    await tester.pumpAndSettle();
    return (controller, repository);
  }

  Future<void> openMine(WidgetTester tester) async {
    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('mine-page')), findsOneWidget);
  }

  testWidgets('我的页可管理业务字典和持久化全局特大字', (tester) async {
    final (controller, repository) = await pumpApp(tester);
    await openMine(tester);

    await tester.tap(find.byKey(const ValueKey('font-huge')));
    await tester.pump();
    expect(controller.fontSize, AppFontSize.extraLarge);
    expect(await repository.getSetting('font_size'), 'huge');
    expect(tester.takeException(), isNull);

    await tester.tap(find.byKey(const Key('open-business-settings')));
    await tester.pumpAndSettle();
    expect(find.text('业务字典'), findsOneWidget);
    await tester.tap(find.byKey(const Key('add-business')).last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('business-name-input')), '维修');
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pumpAndSettle();

    expect(
      (await repository.activeBusinesses()).map((item) => item.name),
      contains('维修'),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('期初模式可连续录 20 人不退出表单', (tester) async {
    final (_, repository) = await pumpApp(tester);
    await openMine(tester);
    await tester.tap(find.byKey(const Key('open-initial-setup')));
    await tester.pumpAndSettle();

    for (var index = 1; index <= 20; index++) {
      await tester.enterText(find.byKey(const Key('setup-name')), '期初客户$index');
      await tester.enterText(find.byKey(const Key('setup-amount')), '0');
      await tester.tap(find.byKey(const Key('save-initial-customer')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('setup-name')), findsOneWidget);
    }

    final stats = await repository.activeStats();
    expect(stats.customerCount, 20);
    expect(stats.entryCount, 20);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is RichText && widget.text.toPlainText().contains('已录 20 人'),
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('回收站找回流水后余额恢复', (tester) async {
    final (controller, repository) = await pumpApp(tester);
    final customer = await repository.addCustomer(name: '刘婶');
    final entry = await repository.addEntry(
      customerId: customer.id,
      kind: EntryKind.debt,
      business: '材料',
      amountCents: 35000,
      bizDate: '2026-08-08',
    );
    await repository.softDeleteEntry(entry.id);
    controller.dataChanged();

    await openMine(tester);
    await tester.drag(find.byType(ListView).last, const Offset(0, -420));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('open-trash')));
    await tester.pumpAndSettle();
    expect(find.text('刘婶 · 记账 · 材料'), findsOneWidget);
    await tester.tap(find.widgetWithText(OutlinedButton, '找回'));
    await tester.pumpAndSettle();

    expect(await repository.balanceCentsForCustomer(customer.id), 35000);
    expect(find.text('回收站是空的'), findsOneWidget);
  });
}
