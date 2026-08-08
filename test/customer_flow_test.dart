import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zhangben/app/app_controller.dart';
import 'package:zhangben/app/app_theme.dart';
import 'package:zhangben/app/zhangben_app.dart';
import 'package:zhangben/data/database/app_database.dart';
import 'package:zhangben/data/repositories/ledger_repository.dart';
import 'package:zhangben/domain/ledger_models.dart';

void main() {
  testWidgets('客户列表显示欠款/多付，详情可进入部分收款与抹零', (tester) async {
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final database = AppDatabase.forTesting(NativeDatabase.memory());
    final repository = LedgerRepository(database);
    final owing = await repository.addCustomer(name: '张老三', note: '东村');
    await repository.addEntry(
      customerId: owing.id,
      kind: EntryKind.debt,
      business: '送货',
      amountCents: 10000,
      bizDate: '2026-08-07',
    );
    final overpaid = await repository.addCustomer(name: '李桂芳');
    await repository.addEntry(
      customerId: overpaid.id,
      kind: EntryKind.debt,
      business: '拉货',
      amountCents: 10000,
      bizDate: '2026-08-07',
    );
    await repository.addEntry(
      customerId: overpaid.id,
      kind: EntryKind.payment,
      amountCents: 15000,
      bizDate: '2026-08-07',
    );
    final controller = AppController(repository);
    await controller.initialize();
    addTearDown(controller.dispose);

    await tester.pumpWidget(ZhangbenApp(controller: controller));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.groups_outlined));
    await tester.pumpAndSettle();

    expect(find.text('共 2 人'), findsOneWidget);
    expect(find.text('外面共欠着 ¥100'), findsOneWidget);
    expect(find.text('欠 ¥100'), findsOneWidget);
    final overpayText = tester.widget<Text>(find.text('多付 ¥50'));
    expect(overpayText.style?.color, AppColors.greenInk);

    await tester.tap(find.text('张老三'));
    await tester.pumpAndSettle();
    expect(find.text('¥100'), findsOneWidget);
    await tester.tap(find.byKey(const Key('settle-customer')));
    await tester.pumpAndSettle();
    expect(find.text('现在欠 ¥100'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('settlement-amount')), '50');
    await tester.pumpAndSettle();
    expect(find.text('收后还欠 ¥50'), findsOneWidget);
    expect(find.text('剩下的 ¥50 不要了（抹零），本次结清'), findsOneWidget);
  });

  testWidgets('删除有欠款客户时明示余额与全部流水后果', (tester) async {
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final database = AppDatabase.forTesting(NativeDatabase.memory());
    final repository = LedgerRepository(database);
    final customer = await repository.addCustomer(name: '刘大哥');
    await repository.addEntry(
      customerId: customer.id,
      kind: EntryKind.debt,
      business: '材料',
      amountCents: 35000,
      bizDate: '2026-08-07',
    );
    final controller = AppController(repository);
    await controller.initialize();
    addTearDown(controller.dispose);

    await tester.pumpWidget(ZhangbenApp(controller: controller));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.groups_outlined));
    await tester.pumpAndSettle();
    await tester.tap(find.text('刘大哥'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('更多'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除客户'));
    await tester.pumpAndSettle();

    expect(find.text('这位客户还有余额'), findsOneWidget);
    expect(find.textContaining('还欠 ¥350'), findsOneWidget);
    expect(find.textContaining('名下全部流水一起放进回收站'), findsOneWidget);
    expect(find.text('删除「刘大哥」及全部流水'), findsOneWidget);

    await tester.tap(find.text('先不删'));
    await tester.pumpAndSettle();
    expect(await repository.balanceCentsForCustomer(customer.id), 35000);
  });
}
