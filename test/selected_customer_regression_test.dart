import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zhangben/app/app_controller.dart';
import 'package:zhangben/app/zhangben_app.dart';
import 'package:zhangben/data/database/app_database.dart';
import 'package:zhangben/data/repositories/ledger_repository.dart';

void main() {
  Future<(AppController, LedgerRepository)> pumpApp(WidgetTester tester) async {
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    final repository = LedgerRepository(database);
    final controller = AppController(repository);
    await controller.initialize();
    addTearDown(controller.dispose);
    await tester.pumpWidget(ZhangbenApp(controller: controller));
    await tester.pumpAndSettle();
    return (controller, repository);
  }

  test('恢复备份后重载会清空记账页选中客户', () async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    final repository = LedgerRepository(database);
    final controller = AppController(repository);
    addTearDown(controller.dispose);
    await controller.initialize();
    controller.setRecordCustomer(await repository.addCustomer(name: '旧客户'));

    await controller.reloadAfterImport();

    expect(controller.recordCustomer, isNull);
  });

  testWidgets('删除当前选中客户后记账页恢复未选状态', (tester) async {
    final (controller, repository) = await pumpApp(tester);
    final customer = await repository.addCustomer(name: '待删除客户');
    controller.setRecordCustomer(customer);
    controller.selectTab(2);
    controller.dataChanged();
    await tester.pumpAndSettle();

    await tester.tap(find.text('待删除客户'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('更多'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除客户'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除「待删除客户」'));
    await tester.pumpAndSettle();

    expect(controller.recordCustomer, isNull);
    controller.selectTab(0);
    await tester.pumpAndSettle();
    expect(find.text('点这里选客户'), findsOneWidget);
  });

  testWidgets('备份替换造成客户 id 撞车时保存被拦截', (tester) async {
    final (controller, repository) = await pumpApp(tester);
    final staleCustomer = await repository.addCustomer(name: '备份前客户');
    controller.setRecordCustomer(staleCustomer);

    await repository.db.customStatement('DELETE FROM customers');
    await repository.db.customStatement(
      "DELETE FROM sqlite_sequence WHERE name = 'customers'",
    );
    final importedCustomer = await repository.addCustomer(name: '备份内另一客户');
    expect(importedCustomer.id, staleCustomer.id, reason: '必须真实构造 id 撞车');

    await tester.tap(find.byKey(const ValueKey('business-button-送货')));
    final amountField = find.descendant(
      of: find.byKey(const Key('amount-display')),
      matching: find.byType(TextField),
    );
    await tester.enterText(amountField, '100');
    await tester.scrollUntilVisible(
      find.byKey(const Key('save-entry')),
      400,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.byKey(const Key('save-entry')));
    await tester.pumpAndSettle();

    expect(find.text('客户已变动，请重新选一次'), findsOneWidget);
    expect(controller.recordCustomer, isNull);
    expect(await repository.entriesForCustomer(importedCustomer.id), isEmpty);
  });
}
