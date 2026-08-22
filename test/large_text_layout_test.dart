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
  testWidgets('特大字号覆盖全部主页、主流程和设置子页无溢出', (tester) async {
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final database = AppDatabase.forTesting(NativeDatabase.memory());
    final repository = LedgerRepository(database);
    final active = await repository.addCustomer(name: '大字号客户', note: '东村开货车的');
    final activeEntry = await repository.addEntry(
      customerId: active.id,
      kind: EntryKind.debt,
      business: '送货',
      amountCents: 12345,
      bizDate: businessDateOf(DateTime.now()),
    );
    final deletedEntry = await repository.addEntry(
      customerId: active.id,
      kind: EntryKind.debt,
      business: '材料',
      amountCents: 500,
      bizDate: businessDateOf(DateTime.now()),
    );
    await repository.softDeleteEntry(deletedEntry.id);
    final deletedCustomer = await repository.addCustomer(name: '已删客户');
    await repository.softDeleteCustomer(deletedCustomer.id);
    await repository.setSetting('font_size', 'huge');

    final controller = AppController(repository);
    await controller.initialize();
    addTearDown(controller.dispose);
    await tester.pumpWidget(ZhangbenApp(controller: controller));
    await tester.pumpAndSettle();

    Future<void> expectNoLayoutError() async {
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }

    // 记一笔 + 选客户。
    expect(find.byKey(const Key('record-page')), findsOneWidget);
    await expectNoLayoutError();
    await tester.tap(find.byKey(const Key('pick-customer')));
    await expectNoLayoutError();
    expect(find.text('最近打交道的'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, '新客户'));
    await expectNoLayoutError();
    expect(find.text('怎么称呼（照账本上写）'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, '不建了'));
    await expectNoLayoutError();
    await tester.tap(find.widgetWithText(TextButton, '返回'));
    await expectNoLayoutError();
    await tester.tap(find.byKey(const Key('business-button-more')));
    await expectNoLayoutError();
    expect(find.text('选业务'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, '返回'));
    await expectNoLayoutError();
    await tester.tap(find.text('选日子'));
    await expectNoLayoutError();
    await tester.tap(find.widgetWithText(TextButton, '先不选'));
    await expectNoLayoutError();
    controller.setRecordCustomer(active);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('business-button-送货')));
    final amountField = find.descendant(
      of: find.byKey(const Key('amount-display')),
      matching: find.byType(TextField),
    );
    await tester.enterText(amountField, '88');
    await tester.scrollUntilVisible(
      find.byKey(const Key('entry-note')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.enterText(
      find.byKey(const Key('entry-note')),
      '纸箱 20 个，下午送到东村仓库',
    );
    await tester.scrollUntilVisible(
      find.byKey(const Key('save-entry')),
      400,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.byKey(const Key('save-entry')));
    await expectNoLayoutError();
    final doneBar = find.byKey(const Key('record-done-bar'));
    expect(doneBar, findsOneWidget);
    expect(
      tester.getBottomLeft(doneBar).dy,
      lessThanOrEqualTo(tester.getTopLeft(find.byType(NavigationBar)).dy),
      reason: '特大字号下撤回条也应自动完整滚入可见区',
    );

    // 流水 + 编辑弹层。
    await tester.tap(find.byIcon(Icons.calendar_month_outlined));
    await expectNoLayoutError();
    expect(find.byKey(const Key('today-page')), findsOneWidget);
    await tester.tap(find.byKey(ValueKey('today-entry-${activeEntry.id}')));
    await expectNoLayoutError();
    expect(find.text('改这笔记账'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.widgetWithText(OutlinedButton, '删除这笔'),
      300,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.widgetWithText(OutlinedButton, '删除这笔'));
    await expectNoLayoutError();
    expect(find.text('删掉这笔账？'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, '先不删'));
    await expectNoLayoutError();

    // 客户列表 + 账页 + 收款弹层。
    await tester.tap(find.byIcon(Icons.groups_outlined));
    await expectNoLayoutError();
    await tester.tap(find.text('大字号客户'));
    await expectNoLayoutError();
    expect(find.byKey(const Key('detail-balance')), findsOneWidget);
    await tester.tap(find.byKey(const Key('settle-customer')));
    await expectNoLayoutError();
    expect(find.textContaining('现在欠'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, '收起'));
    await expectNoLayoutError();
    await tester.tap(find.widgetWithText(TextButton, '返回'));
    await expectNoLayoutError();

    // 我的 + 三个设置子页。
    await tester.tap(find.byIcon(Icons.settings_outlined));
    await expectNoLayoutError();
    expect(find.byKey(const Key('mine-page')), findsOneWidget);

    await tester.scrollUntilVisible(
      find.byKey(const Key('open-initial-setup')),
      300,
    );
    await tester.tap(find.byKey(const Key('open-initial-setup')));
    await expectNoLayoutError();
    expect(find.text('期初建档'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, '先退出'));
    await expectNoLayoutError();

    await tester.scrollUntilVisible(
      find.byKey(const Key('open-business-settings')),
      300,
    );
    await tester.tap(find.byKey(const Key('open-business-settings')));
    await expectNoLayoutError();
    expect(find.text('业务字典'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, '返回'));
    await expectNoLayoutError();

    final mineScroll = find.descendant(
      of: find.byKey(const Key('mine-page')),
      matching: find.byType(Scrollable),
    );
    await tester.scrollUntilVisible(
      find.byKey(const Key('open-trash')),
      300,
      scrollable: mineScroll,
    );
    await tester.drag(mineScroll, const Offset(0, -180));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('open-trash')));
    await expectNoLayoutError();
    expect(find.text('回收站'), findsOneWidget);
    expect(find.textContaining('已删客户'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, '返回'));
    await expectNoLayoutError();
  });
}
