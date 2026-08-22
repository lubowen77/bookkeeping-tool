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
  Future<(AppController, LedgerRepository)> pumpApp(
    WidgetTester tester,
    Future<void> Function(LedgerRepository, AppController) seed,
  ) async {
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    final repository = LedgerRepository(database);
    final controller = AppController(repository);
    await controller.initialize();
    await seed(repository, controller);
    addTearDown(controller.dispose);
    await tester.pumpWidget(ZhangbenApp(controller: controller));
    await tester.pumpAndSettle();
    return (controller, repository);
  }

  testWidgets('记账备注在今天页与客户详情显示，空备注无分隔符', (tester) async {
    late CustomerRow customer;
    late LedgerEntryRow withoutNote;
    final (controller, repository) = await pumpApp(tester, (
      repository,
      controller,
    ) async {
      customer = await repository.addCustomer(name: '张老三');
      withoutNote = await repository.addEntry(
        customerId: customer.id,
        kind: EntryKind.debt,
        business: '材料',
        amountCents: 1200,
        bizDate: businessDateOf(DateTime.now()),
      );
      controller.setRecordCustomer(customer);
    });

    await tester.tap(find.byKey(const ValueKey('business-button-送货')));
    final amountField = find.descendant(
      of: find.byKey(const Key('amount-display')),
      matching: find.byType(TextField),
    );
    await tester.enterText(amountField, '350');
    await tester.scrollUntilVisible(
      find.byKey(const Key('entry-note')),
      350,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.enterText(find.byKey(const Key('entry-note')), '  纸箱 20 个  ');
    await tester.scrollUntilVisible(
      find.byKey(const Key('save-entry')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.byKey(const Key('save-entry')));
    await tester.pump(const Duration(milliseconds: 500));

    final entries = await repository.entriesForCustomer(customer.id);
    final withNote = entries.singleWhere((entry) => entry.note.isNotEmpty);
    expect(withNote.note, '纸箱 20 个');
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('entry-note')))
          .controller
          ?.text,
      isEmpty,
      reason: '记账成功后备注框应清空',
    );

    controller.selectTab(1);
    await tester.pumpAndSettle();
    final todayWithNote = find.byKey(ValueKey('today-entry-${withNote.id}'));
    final todayWithoutNote = find.byKey(
      ValueKey('today-entry-${withoutNote.id}'),
    );
    expect(
      find.descendant(of: todayWithNote, matching: find.text('送货 · 纸箱 20 个')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: todayWithoutNote, matching: find.text('材料')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: todayWithoutNote,
        matching: find.textContaining('材料 ·'),
      ),
      findsNothing,
    );

    controller.selectTab(2);
    await tester.pumpAndSettle();
    await tester.tap(find.text('张老三'));
    await tester.pumpAndSettle();
    final detailWithNote = find.byKey(ValueKey('detail-entry-${withNote.id}'));
    final detailWithoutNote = find.byKey(
      ValueKey('detail-entry-${withoutNote.id}'),
    );
    expect(
      find.descendant(
        of: detailWithNote,
        matching: find.textContaining(' · 纸箱 20 个'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: detailWithoutNote,
        matching: find.textContaining(' · '),
      ),
      findsNothing,
    );
  });

  testWidgets('四种流水都能在编辑弹层只修改备注', (tester) async {
    late List<LedgerEntryRow> originals;
    final (controller, repository) = await pumpApp(tester, (
      repository,
      _,
    ) async {
      final customer = await repository.addCustomer(name: '王二叔');
      final date = businessDateOf(DateTime.now());
      originals = [
        await repository.addEntry(
          customerId: customer.id,
          kind: EntryKind.initial,
          amountCents: 10000,
          bizDate: date,
        ),
        await repository.addEntry(
          customerId: customer.id,
          kind: EntryKind.debt,
          business: '送货',
          amountCents: 2000,
          bizDate: date,
        ),
        await repository.addEntry(
          customerId: customer.id,
          kind: EntryKind.payment,
          amountCents: 3000,
          bizDate: date,
        ),
        await repository.addEntry(
          customerId: customer.id,
          kind: EntryKind.discount,
          amountCents: 500,
          bizDate: date,
        ),
      ];
    });
    controller.selectTab(1);
    await tester.pumpAndSettle();

    for (final original in originals) {
      await tester.tap(find.byKey(ValueKey('today-entry-${original.id}')));
      await tester.pumpAndSettle();
      final noteField = find.byKey(const Key('edit-entry-note'));
      await tester.ensureVisible(noteField);
      await tester.enterText(noteField, '  备注-${original.kind}  ');
      final save = find.widgetWithText(FilledButton, '保存修改');
      await tester.ensureVisible(save);
      await tester.tap(save);
      await tester.pumpAndSettle();

      final updated = await repository.getEntry(original.id);
      expect(updated.customerId, original.customerId);
      expect(updated.kind, original.kind);
      expect(updated.business, original.business);
      expect(updated.amountCents, original.amountCents);
      expect(updated.bizDate, original.bizDate);
      expect(updated.note, '备注-${original.kind}');
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
    }
  });

  testWidgets('收款备注只写入 payment，同次 discount 保持为空', (tester) async {
    late CustomerRow customer;
    final (_, repository) = await pumpApp(tester, (repository, _) async {
      customer = await repository.addCustomer(name: '李桂芳');
      await repository.addEntry(
        customerId: customer.id,
        kind: EntryKind.debt,
        business: '送货',
        amountCents: 10000,
        bizDate: businessDateOf(DateTime.now()),
      );
    });

    await tester.tap(find.byIcon(Icons.groups_outlined));
    await tester.pumpAndSettle();
    await tester.tap(find.text('李桂芳'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('settle-customer')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('settlement-amount')), '90');
    await tester.pump();
    await tester.tap(find.byType(Checkbox));
    await tester.pump();
    final noteField = find.byKey(const Key('settlement-note'));
    await tester.ensureVisible(noteField);
    await tester.enterText(noteField, '  微信转的  ');
    final save = find.byKey(const Key('confirm-settlement'));
    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '确认收款'));
    await tester.pumpAndSettle();

    final entries = await repository.entriesForCustomer(customer.id);
    final payment = entries.singleWhere(
      (entry) => entry.kind == EntryKind.payment.storageValue,
    );
    final discount = entries.singleWhere(
      (entry) => entry.kind == EntryKind.discount.storageValue,
    );
    expect(payment.note, '微信转的');
    expect(discount.note, isEmpty);
    final paymentRow = find.byKey(ValueKey('detail-entry-${payment.id}'));
    final discountRow = find.byKey(ValueKey('detail-entry-${discount.id}'));
    await tester.scrollUntilVisible(
      paymentRow,
      250,
      scrollable: find.byType(Scrollable).last,
    );
    expect(
      find.descendant(of: paymentRow, matching: find.textContaining(' · 微信转的')),
      findsOneWidget,
    );
    await tester.scrollUntilVisible(
      discountRow,
      -200,
      scrollable: find.byType(Scrollable).last,
    );
    expect(discountRow, findsOneWidget);
    expect(
      find.descendant(of: discountRow, matching: find.textContaining(' · ')),
      findsNothing,
    );
  });
}
