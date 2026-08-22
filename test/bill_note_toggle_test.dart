import 'dart:async';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:zhangben/app/app_controller.dart';
import 'package:zhangben/app/app_theme.dart';
import 'package:zhangben/data/billing/customer_bill_image_service.dart';
import 'package:zhangben/data/database/app_database.dart';
import 'package:zhangben/data/repositories/ledger_repository.dart';
import 'package:zhangben/domain/ledger_models.dart';
import 'package:zhangben/ui/customer/customer_detail_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('账单备注开关默认开，关闭后即时重生成并在再次打开时沿用', (tester) async {
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final database = AppDatabase.forTesting(NativeDatabase.memory());
    final repository = LedgerRepository(
      database,
      clock: () => DateTime(2026, 8, 8, 14, 5),
    );
    final controller = AppController(repository);
    addTearDown(controller.dispose);
    final customer = await repository.addCustomer(name: '张老三');
    await repository.addEntry(
      customerId: customer.id,
      kind: EntryKind.debt,
      business: '送货',
      amountCents: 35000,
      bizDate: '2026-08-08',
      note: '纸箱 20 个',
    );
    final entries = await repository.entriesForCustomer(customer.id);
    final service = CustomerBillImageService(database);
    var generation = 0;
    final regeneratedFor = <bool>[];
    Completer<CustomerBillImageResult>? pendingGeneration;
    CustomerBillImageResult fakeResult() => CustomerBillImageResult(
      file: File('/tmp/zhangben-bill-toggle-${generation++}.png'),
      width: 750,
      height: 600,
      entryCount: 1,
      balanceCents: 35000,
      generatedAt: DateTime(2026, 8, 8, 14, 5),
    );
    Future<CustomerBillImageResult> regenerate(bool showNotes) {
      regeneratedFor.add(showNotes);
      pendingGeneration = Completer<CustomerBillImageResult>();
      return pendingGeneration!.future;
    }

    Future<void> pumpPreview() async {
      final showNotes = CustomerBillPreviewPage.showNotesFromSetting(
        await repository.getSetting('bill_show_note'),
      );
      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: controller,
          child: MaterialApp(
            theme: buildAppTheme(),
            home: CustomerBillPreviewPage(
              service: service,
              customer: customer,
              effectiveEntries: entries,
              shopName: null,
              initialResult: fakeResult(),
              initialShowNotes: showNotes,
              regenerator: regenerate,
            ),
          ),
        ),
      );
      await tester.pump();
    }

    expect(await repository.getSetting('bill_show_note'), isNull);
    await pumpPreview();
    const optionKey = Key('bill-show-note-option');
    final option = find.byKey(optionKey);
    expect(option, findsOneWidget);
    expect(find.text('账单上显示备注（会记住这次的选择）'), findsOneWidget);
    Checkbox checkbox() => tester.widget<Checkbox>(
      find.descendant(of: option, matching: find.byType(Checkbox)),
    );
    expect(checkbox().value, isTrue);

    await tester.tap(
      find.descendant(of: option, matching: find.byType(Checkbox)),
    );
    await tester.pump();
    expect(find.byKey(const Key('bill-regenerating')), findsOneWidget);
    pendingGeneration!.complete(fakeResult());
    await tester.pump();
    expect(find.byKey(const Key('bill-regenerating')), findsNothing);
    expect(checkbox().value, isFalse);
    expect(await repository.getSetting('bill_show_note'), '0');
    expect(regeneratedFor, [isFalse]);

    await tester.pumpWidget(const SizedBox.shrink());
    await pumpPreview();
    expect(checkbox().value, isFalse);
  });
}
