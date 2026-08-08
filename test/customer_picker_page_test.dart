import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:zhangben/app/app_controller.dart';
import 'package:zhangben/app/app_theme.dart';
import 'package:zhangben/data/database/app_database.dart';
import 'package:zhangben/data/repositories/ledger_repository.dart';
import 'package:zhangben/domain/ledger_models.dart';
import 'package:zhangben/ui/customer/customer_picker_page.dart';

void main() {
  Future<AppController> pumpPicker(WidgetTester tester) async {
    var second = 0;
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    final repository = LedgerRepository(
      database,
      clock: () => DateTime(2026, 8, 8, 8, 0, second++),
    );
    const names = [
      '艾阿姨',
      '白师傅',
      '陈大姐',
      '邓老板',
      '方叔',
      '郭师傅',
      '何阿姨',
      '李老板',
      '马大哥',
      '张老三',
    ];
    for (var index = 0; index < names.length; index++) {
      final customer = await repository.addCustomer(name: names[index]);
      if (index < 9) {
        await repository.addEntry(
          customerId: customer.id,
          kind: EntryKind.debt,
          amountCents: 10000,
          business: '送货',
          bizDate: '2026-08-08',
        );
      }
    }
    final controller = AppController(repository);
    await controller.initialize();
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: controller,
        child: MaterialApp(
          theme: buildAppTheme(),
          home: const CustomerPickerPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return controller;
  }

  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  testWidgets('默认同页显示最近 8 人和拼音分组的全部客户', (tester) async {
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = await pumpPicker(tester);
    addTearDown(controller.dispose);

    expect(find.text('最近打交道的'), findsOneWidget);
    expect(find.text('全部客户'), findsOneWidget);
    final recentCard = find.byKey(const Key('recent-customers'));
    expect(
      find.descendant(of: recentCard, matching: find.byType(InkWell)),
      findsNWidgets(8),
    );
    expect(find.byKey(const ValueKey('customer-group-A')), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('customer-group-card-A')),
        matching: find.text('艾阿姨'),
      ),
      findsOneWidget,
    );

    final aTarget = find.byKey(const ValueKey('customer-index-A'));
    expect(tester.getSize(aTarget), const Size(48, 48));

    final index = find.byKey(const Key('customer-alphabet-index'));
    await tester.drag(index, const Offset(0, -1100));
    await tester.pumpAndSettle();
    final zTarget = find.byKey(const ValueKey('customer-index-Z'));
    expect(tester.getSize(zTarget), const Size(48, 48));
    await tester.tap(zTarget);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('customer-group-Z')), findsOneWidget);
    expect(find.text('张老三'), findsOneWidget);
  });

  testWidgets('搜索支持汉字、全拼和首字母', (tester) async {
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = await pumpPicker(tester);
    addTearDown(controller.dispose);

    final search = find.byType(TextField);
    for (final query in ['张老三', 'zhanglaosan', 'zls']) {
      await tester.enterText(search, query);
      await tester.pumpAndSettle();
      expect(find.text('搜索结果'), findsOneWidget);
      expect(find.text('最近打交道的'), findsNothing);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('customer-group-card-Z')),
          matching: find.text('张老三'),
        ),
        findsOneWidget,
      );
    }
  });

  testWidgets('选客户页保留直接新建客户入口', (tester) async {
    final controller = await pumpPicker(tester);
    addTearDown(controller.dispose);

    await tester.tap(find.text('新客户'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text('怎么称呼（照账本上写）'), findsOneWidget);
    expect(find.text('备注（哪里的人 / 干什么的，防重名）'), findsOneWidget);
  });
}
