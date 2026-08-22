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

  testWidgets('记账成功显示页内撤回条，撤回后恢复含备注的表单', (tester) async {
    final (controller, repository) = await pumpApp(tester);
    final customer = await repository.addCustomer(name: '张老三');
    controller.setRecordCustomer(customer);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('business-button-送货')));
    final amountField = find.descendant(
      of: find.byKey(const Key('amount-display')),
      matching: find.byType(TextField),
    );
    await tester.enterText(amountField, '350');
    await tester.scrollUntilVisible(
      find.byKey(const Key('entry-note')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.enterText(find.byKey(const Key('entry-note')), '纸箱 20 个');
    await tester.scrollUntilVisible(
      find.byKey(const Key('save-entry')),
      400,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.byKey(const Key('save-entry')));
    await tester.pumpAndSettle();

    expect(await repository.entriesForCustomer(customer.id), hasLength(1));
    final doneBar = find.byKey(const Key('record-done-bar'));
    expect(doneBar, findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);
    expect(find.byType(SnackBarAction), findsNothing);
    expect(
      find.descendant(of: doneBar, matching: find.text('纸箱 20 个')),
      findsOneWidget,
    );
    expect(
      tester.getBottomLeft(doneBar).dy,
      lessThanOrEqualTo(tester.getTopLeft(find.byType(NavigationBar)).dy),
      reason: '撤回条出现后应自动滚到完整可见',
    );

    await tester.tap(
      find.descendant(
        of: doneBar,
        matching: find.widgetWithText(OutlinedButton, '撤回'),
      ),
    );
    await tester.pumpAndSettle();

    expect(await repository.entriesForCustomer(customer.id), isEmpty);
    expect(controller.recordCustomer?.id, customer.id);
    expect(tester.widget<TextField>(amountField).controller?.text, '350');
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('entry-note')))
          .controller
          ?.text,
      '纸箱 20 个',
    );
    expect(find.text('已撤回，这笔没记'), findsOneWidget);
  });

  testWidgets('记账撤回条在页内操作或切换页签后消失', (tester) async {
    final (controller, repository) = await pumpApp(tester);
    final customer = await repository.addCustomer(name: '张老三');

    Future<void> saveOne(String amount) async {
      controller.setRecordCustomer(customer);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('business-button-送货')));
      final amountField = find.descendant(
        of: find.byKey(const Key('amount-display')),
        matching: find.byType(TextField),
      );
      await tester.enterText(amountField, amount);
      await tester.scrollUntilVisible(
        find.byKey(const Key('save-entry')),
        400,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.byKey(const Key('save-entry')));
      await tester.pumpAndSettle();
    }

    await saveOne('10');
    expect(find.byKey(const Key('record-done-bar')), findsOneWidget);
    await tester.tap(find.byKey(const Key('save-entry')));
    await tester.pump();
    expect(find.byKey(const Key('record-done-bar')), findsNothing);

    await tester.pump(const Duration(seconds: 3));
    await saveOne('20');
    expect(find.byKey(const Key('record-done-bar')), findsOneWidget);
    await tester.tap(find.byIcon(Icons.calendar_month_outlined));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.edit_note_outlined));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('record-done-bar')), findsNothing);
  });

  testWidgets('抹零结清的页内撤回会删两笔并恢复收款表单', (tester) async {
    final (_, repository) = await pumpApp(tester);
    final customer = await repository.addCustomer(name: '王二叔');
    await repository.addEntry(
      customerId: customer.id,
      kind: EntryKind.debt,
      business: '送货',
      amountCents: 10000,
      bizDate: '2026-08-08',
    );

    await tester.tap(find.byIcon(Icons.groups_outlined));
    await tester.pumpAndSettle();
    await tester.tap(find.text('王二叔'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('settle-customer')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('settlement-amount')), '90');
    await tester.pump();
    await tester.tap(find.byType(Checkbox));
    await tester.pump();
    final noteField = find.byKey(const Key('settlement-note'));
    await tester.ensureVisible(noteField);
    await tester.enterText(noteField, '微信转的');
    await tester.ensureVisible(find.byKey(const Key('confirm-settlement')));
    await tester.tap(find.byKey(const Key('confirm-settlement')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '确认收款'));
    await tester.pumpAndSettle();

    expect(await repository.balanceCentsForCustomer(customer.id), 0);
    expect(await repository.entriesForCustomer(customer.id), hasLength(3));
    final doneBar = find.byKey(const Key('settlement-done-bar'));
    expect(doneBar, findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);
    expect(find.byType(SnackBarAction), findsNothing);
    expect(
      find.descendant(of: doneBar, matching: find.text('微信转的')),
      findsOneWidget,
    );
    await tester.tap(
      find.descendant(
        of: doneBar,
        matching: find.widgetWithText(OutlinedButton, '撤回'),
      ),
    );
    await tester.pumpAndSettle();

    expect(await repository.balanceCentsForCustomer(customer.id), 10000);
    expect(await repository.entriesForCustomer(customer.id), hasLength(1));
    expect(find.byKey(const Key('settlement-amount')), findsOneWidget);
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('settlement-amount')))
          .controller
          ?.text,
      '90',
    );
    expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, isTrue);
    expect(tester.widget<TextField>(noteField).controller?.text, '微信转的');
    expect(find.text('已撤回这次收款'), findsOneWidget);
  });

  testWidgets('再次点收款时收起上一次的页内撤回条', (tester) async {
    final (_, repository) = await pumpApp(tester);
    final customer = await repository.addCustomer(name: '李桂芳');
    await repository.addEntry(
      customerId: customer.id,
      kind: EntryKind.debt,
      business: '材料',
      amountCents: 10000,
      bizDate: '2026-08-08',
    );

    await tester.tap(find.byIcon(Icons.groups_outlined));
    await tester.pumpAndSettle();
    await tester.tap(find.text('李桂芳'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('settle-customer')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('settlement-amount')), '50');
    await tester.ensureVisible(find.byKey(const Key('confirm-settlement')));
    await tester.tap(find.byKey(const Key('confirm-settlement')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '确认收款'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('settlement-done-bar')), findsOneWidget);
    await tester.tap(find.byKey(const Key('settle-customer')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('settlement-done-bar')), findsNothing);
    expect(find.byKey(const Key('settlement-amount')), findsOneWidget);
  });
}
