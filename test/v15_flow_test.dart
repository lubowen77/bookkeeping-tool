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

  testWidgets('记一笔后的撤销会软删流水并恢复原表单', (tester) async {
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
      find.byKey(const Key('save-entry')),
      400,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.byKey(const Key('save-entry')));
    await tester.pump(const Duration(milliseconds: 500));

    expect(await repository.entriesForCustomer(customer.id), hasLength(1));
    expect(find.text('撤销'), findsOneWidget);
    tester.widget<SnackBarAction>(find.byType(SnackBarAction)).onPressed();
    await tester.pumpAndSettle();

    expect(await repository.entriesForCustomer(customer.id), isEmpty);
    expect(controller.recordCustomer?.id, customer.id);
    expect(tester.widget<TextField>(amountField).controller?.text, '350');
    expect(find.text('已撤销，这笔没记'), findsOneWidget);
  });

  testWidgets('抹零结清撤销会同时撤回两笔并恢复收款表单', (tester) async {
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
    await tester.tap(find.byKey(const Key('confirm-settlement')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '确认收款'));
    await tester.pump(const Duration(milliseconds: 500));

    expect(await repository.balanceCentsForCustomer(customer.id), 0);
    expect(await repository.entriesForCustomer(customer.id), hasLength(3));
    expect(find.text('撤销'), findsOneWidget);
    tester.widget<SnackBarAction>(find.byType(SnackBarAction)).onPressed();
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
  });
}
