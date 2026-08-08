import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zhangben/app/app_controller.dart';
import 'package:zhangben/app/zhangben_app.dart';
import 'package:zhangben/data/database/app_database.dart';
import 'package:zhangben/data/repositories/ledger_repository.dart';

void main() {
  testWidgets('500 客户和 2 万笔流水的客户页可流畅滚动与搜索', (tester) async {
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const timestamp = '2026-08-08T08:00:00+08:00';
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    // 用 SQLite 直接生成验收数据，避免测试进程同时在 Dart 堆中
    // 构造 2 万个 Companion 对象，从而使全量并行回归也可稳定执行。
    await database.customStatement('''
      WITH RECURSIVE seq(x) AS (
        SELECT 0
        UNION ALL
        SELECT x + 1 FROM seq WHERE x < 499
      )
      INSERT INTO customers (
        name, note, pinyin_full, pinyin_abbr, created_at, deleted_at
      )
      SELECT
        CASE WHEN x = 0 THEN '张老三' ELSE '客户' || x END,
        CASE WHEN x = 0 THEN '东村' ELSE '' END,
        CASE WHEN x = 0 THEN 'zhanglaosan' ELSE 'kehu' || x END,
        CASE WHEN x = 0 THEN 'zls' ELSE 'kh' || x END,
        '$timestamp',
        NULL
      FROM seq
    ''');
    await database.customStatement('''
      WITH RECURSIVE
      customer_seq(x) AS (
        SELECT 0
        UNION ALL
        SELECT x + 1 FROM customer_seq WHERE x < 499
      ),
      entry_seq(y) AS (
        SELECT 0
        UNION ALL
        SELECT y + 1 FROM entry_seq WHERE y < 39
      )
      INSERT INTO entries (
        customer_id, kind, business, amount_cents, biz_date,
        note, created_at, updated_at, deleted_at
      )
      SELECT
        x + 1, 'debt', '送货', 100, '2026-08-07',
        '', '$timestamp', '$timestamp', NULL
      FROM customer_seq CROSS JOIN entry_seq
    ''');
    final controller = AppController(LedgerRepository(database));
    await controller.initialize();
    addTearDown(controller.dispose);
    await tester.pumpWidget(ZhangbenApp(controller: controller));
    await tester.pumpAndSettle();

    final loadWatch = Stopwatch()..start();
    await tester.tap(find.byIcon(Icons.groups_outlined));
    await tester.pumpAndSettle();
    loadWatch.stop();

    expect(find.text('共 500 人'), findsOneWidget);
    expect(loadWatch.elapsed, lessThan(const Duration(seconds: 5)));

    final customerList = find.descendant(
      of: find.byKey(const Key('customers-page')),
      matching: find.byType(ListView),
    );
    expect(customerList, findsOneWidget);
    await tester.fling(customerList, const Offset(0, -600), 2000);
    await tester.pumpAndSettle();
    expect(tester.takeException(), null);

    final search = find.descendant(
      of: find.byKey(const Key('customers-page')),
      matching: find.byType(TextField),
    );
    for (final query in ['张老三', 'zhanglaosan', 'zls']) {
      await tester.enterText(search, query);
      await tester.pumpAndSettle();
      expect(
        find.descendant(of: customerList, matching: find.text('张老三')),
        findsOneWidget,
      );
      expect(find.text('欠 ¥40'), findsOneWidget);
      expect(tester.takeException(), null);
    }
  });
}
