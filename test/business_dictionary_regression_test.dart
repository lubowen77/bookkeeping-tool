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

  testWidgets('删除字典业务后，记账页「更多」格不得残留已删业务', (tester) async {
    final (controller, repository) = await pumpApp(tester);
    // 「修车」拼音排序在 5 个种子业务之后，不进快捷前 5，只能经「更多」选中
    final biz = await repository.addBusiness('修车');
    controller.dataChanged();
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('business-button-more')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('修车'));
    await tester.pumpAndSettle();

    final moreButton = find.byKey(const Key('business-button-more'));
    expect(
      find.descendant(of: moreButton, matching: find.text('修车')),
      findsOneWidget,
      reason: '选中长尾业务后应显示在「更多」格',
    );

    await repository.softDeleteBusiness(biz.id);
    controller.dataChanged();
    await tester.pumpAndSettle();

    expect(find.text('修车'), findsNothing, reason: '业务删除后不得在记账页任何位置残留');
    expect(
      find.descendant(of: moreButton, matching: find.text('更多…')),
      findsOneWidget,
      reason: '「更多」格应恢复默认文案',
    );
  });

  test('软删业务后只改历史流水金额不会复活该业务', () async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    final repository = LedgerRepository(database);
    addTearDown(database.close);
    final customer = await repository.addCustomer(name: '张师傅');
    final entry = await repository.addEntry(
      customerId: customer.id,
      kind: EntryKind.debt,
      business: '业务 X',
      amountCents: 10000,
      bizDate: '2026-08-08',
    );
    final business = (await repository.findActiveBusinessesWithExactName(
      '业务 X',
    )).single;
    await repository.softDeleteBusiness(business.id);

    await repository.updateEntry(
      entryId: entry.id,
      customerId: customer.id,
      kind: EntryKind.debt,
      business: '业务 X',
      amountCents: 20000,
      bizDate: entry.bizDate,
    );

    expect(await repository.findActiveBusinessesWithExactName('业务 X'), isEmpty);
    expect(
      (await repository.deletedBusinesses()).where(
        (item) => item.name == '业务 X',
      ),
      hasLength(1),
    );
    expect((await repository.getEntry(entry.id)).amountCents, 20000);
  });
}
