import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:zhangben/data/database/app_database.dart';
import 'package:zhangben/data/repositories/ledger_repository.dart';

void main() {
  test('v1 覆盖升级到 v1.5 只新增业务字典，旧账与余额不变', () async {
    final temporary = await Directory.systemTemp.createTemp(
      'zhangben-v1-migration-',
    );
    final file = File('${temporary.path}/v1.sqlite');
    final v1 = sqlite3.open(file.path);
    addTearDown(() async {
      await temporary.delete(recursive: true);
    });

    v1.execute('''
      CREATE TABLE customers (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        note TEXT NOT NULL DEFAULT '',
        pinyin_full TEXT NOT NULL DEFAULT '',
        pinyin_abbr TEXT NOT NULL DEFAULT '',
        created_at TEXT NOT NULL,
        deleted_at TEXT
      )
    ''');
    v1.execute('''
      CREATE TABLE entries (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        customer_id INTEGER NOT NULL REFERENCES customers(id),
        kind TEXT NOT NULL,
        business TEXT NOT NULL DEFAULT '',
        amount_cents INTEGER NOT NULL,
        biz_date TEXT NOT NULL,
        note TEXT NOT NULL DEFAULT '',
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        deleted_at TEXT
      )
    ''');
    v1.execute(
      'CREATE TABLE settings (key TEXT PRIMARY KEY, value TEXT NOT NULL)',
    );
    v1.execute('''
      CREATE TABLE day_photos (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        biz_date TEXT NOT NULL,
        file_path TEXT NOT NULL,
        created_at TEXT NOT NULL,
        deleted_at TEXT
      )
    ''');
    v1.execute('''
      INSERT INTO customers
        (id,name,note,pinyin_full,pinyin_abbr,created_at,deleted_at)
      VALUES
        (1,'张老三','东村','zhanglaosan','zls','2026-08-01T10:00:00+08:00',NULL),
        (2,'李桂芳','','liguifang','lgf','2026-08-01T10:01:00+08:00',NULL)
    ''');
    v1.execute('''
      INSERT INTO entries
        (id,customer_id,kind,business,amount_cents,biz_date,note,created_at,updated_at,deleted_at)
      VALUES
        (1,1,'initial','',10000,'2026-08-01','','2026-08-01T10:00:00+08:00','2026-08-01T10:00:00+08:00',NULL),
        (2,1,'debt','送货',35000,'2026-08-02','','2026-08-02T20:00:00+08:00','2026-08-02T20:00:00+08:00',NULL),
        (3,1,'debt','送货',5000,'2026-08-03','','2026-08-03T20:00:00+08:00','2026-08-03T20:00:00+08:00',NULL),
        (4,1,'payment','',12000,'2026-08-04','','2026-08-04T20:00:00+08:00','2026-08-04T20:00:00+08:00',NULL),
        (5,2,'debt','包装',8000,'2026-08-04','','2026-08-04T21:00:00+08:00','2026-08-04T21:00:00+08:00',NULL)
    ''');
    v1.execute('''INSERT INTO settings (key,value) VALUES
         ('font_size','huge'),
         ('business_buttons','["送货","加工","运费"]')''');
    v1.execute('''
      INSERT INTO day_photos (id,biz_date,file_path,created_at,deleted_at)
      VALUES (1,'2026-08-04','/private/paper.jpg','2026-08-04T22:00:00+08:00',NULL)
    ''');
    v1.execute('PRAGMA user_version = 1');
    v1.close();

    final db = AppDatabase.forTesting(NativeDatabase(file));
    addTearDown(db.close);
    final repository = LedgerRepository(db);
    await db.customSelect('SELECT 1').getSingle();

    expect(db.schemaVersion, 2);
    expect((await db.select(db.customers).get()).map((row) => row.id), [1, 2]);
    expect((await db.select(db.ledgerEntries).get()).map((row) => row.id), [
      1,
      2,
      3,
      4,
      5,
    ]);
    expect(await repository.getSetting('font_size'), 'huge');
    expect(await db.select(db.dayPhotos).get(), hasLength(1));
    expect(await repository.balanceCentsForCustomer(1), 38000);
    expect(await repository.balanceCentsForCustomer(2), 8000);

    final businesses = await repository.activeBusinesses();
    expect(businesses.map((row) => row.name).toSet(), {'送货', '加工', '运费', '包装'});
    expect(businesses.singleWhere((row) => row.name == '送货').useCount, 2);
    expect(businesses.singleWhere((row) => row.name == '包装').useCount, 1);
    expect(businesses.singleWhere((row) => row.name == '加工').useCount, 0);
  });
}
