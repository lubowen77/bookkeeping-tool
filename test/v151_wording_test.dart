import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zhangben/app/app_controller.dart';
import 'package:zhangben/app/zhangben_app.dart';
import 'package:zhangben/core/local_time.dart';
import 'package:zhangben/data/database/app_database.dart';
import 'package:zhangben/data/repositories/ledger_repository.dart';
import 'package:zhangben/domain/ledger_models.dart';

void main() {
  testWidgets('v1.5.1 界面措辞与 debt 存储值保持一致', (tester) async {
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final database = AppDatabase.forTesting(NativeDatabase.memory());
    final repository = LedgerRepository(database);
    final customer = await repository.addCustomer(name: '张老三');
    final debt = await repository.addEntry(
      customerId: customer.id,
      kind: EntryKind.debt,
      business: '送货',
      amountCents: 35000,
      bizDate: businessDateOf(DateTime.now()),
    );
    await repository.addEntry(
      customerId: customer.id,
      kind: EntryKind.payment,
      amountCents: 5000,
      bizDate: businessDateOf(DateTime.now()),
    );
    expect(debt.kind, 'debt');

    final controller = AppController(repository);
    await controller.initialize();
    addTearDown(controller.dispose);
    await tester.pumpWidget(ZhangbenApp(controller: controller));
    await tester.pumpAndSettle();

    expect(tester.widget<MaterialApp>(find.byType(MaterialApp)).title, '记账本');

    await tester.tap(find.byIcon(Icons.calendar_month_outlined));
    await tester.pumpAndSettle();
    expect(find.text('记了 ¥350 · 收了 ¥50'), findsOneWidget);
    expect(find.text('记'), findsOneWidget);
    expect(find.textContaining('\u8d4a'), findsNothing);

    await tester.tap(find.byIcon(Icons.groups_outlined));
    await tester.pumpAndSettle();
    await tester.tap(find.text('张老三'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(OutlinedButton, '记一笔账'), findsOneWidget);
    expect(find.text('送货'), findsOneWidget);
    expect(find.textContaining('\u8d4a'), findsNothing);
  });
}
