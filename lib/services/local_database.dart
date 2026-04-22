import 'dart:io';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path/path.dart';

class LocalDatabase {
  static final LocalDatabase instance = LocalDatabase._init();
  static Database? _database;

  LocalDatabase._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('pos_offline.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    // Initialize FFI for Desktop/Testing
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }

    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    return await openDatabase(
      path,
      version: 11,
      onCreate: _createDB,
      onUpgrade: _onUpgrade,
      onConfigure: _onConfigure,
    );
  }

  Future _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute(
        'ALTER TABLE categories ADD COLUMN is_synced INTEGER DEFAULT 0',
      );
      await db.execute(
        'ALTER TABLE users ADD COLUMN is_synced INTEGER DEFAULT 0',
      );
    }
    if (oldVersion < 3) {
      await db.execute(
        'ALTER TABLE balance ADD COLUMN is_synced INTEGER DEFAULT 0',
      );
    }
    if (oldVersion < 4) {
      // Migrate quantity columns etc.
    }
    if (oldVersion < 5) {
      await db.execute('ALTER TABLE products ADD COLUMN image_url TEXT');
    }
    if (oldVersion < 6) {
      await db.execute(
        'ALTER TABLE products ADD COLUMN base_unit_id INTEGER REFERENCES products(id)',
      );
      await db.execute(
        'ALTER TABLE products ADD COLUMN base_unit_conversion REAL DEFAULT 1.0',
      );
    }
    if (oldVersion < 7) {
      await db.execute('''
      CREATE TABLE cash_drawer_logs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        reason TEXT,
        amount REAL DEFAULT 0,
        type TEXT NOT NULL,
        user_id INTEGER,
        created_at TEXT DEFAULT CURRENT_TIMESTAMP,
        is_synced INTEGER DEFAULT 0,
        FOREIGN KEY (user_id) REFERENCES users (id)
      )
      ''');
    }
    if (oldVersion < 8) {
      await db.execute(
        'ALTER TABLE products ADD COLUMN is_card INTEGER DEFAULT 0',
      );
      await db.execute('''
      CREATE TABLE IF NOT EXISTS cards (
        id INTEGER PRIMARY KEY,
        name TEXT,
        product_id INTEGER,
        price INTEGER DEFAULT 0,
        spended_balance INTEGER DEFAULT 0,
        created_at TEXT,
        FOREIGN KEY (product_id) REFERENCES products (id)
      )
      ''');
    }
    if (oldVersion < 9) {
      // Add remote_id to sales for duplicate-upload prevention
      await db.execute('ALTER TABLE sales ADD COLUMN remote_id INTEGER');
    }
    if (oldVersion < 10) {
      // Collapse the `balance` table to a single row pinned at id=1.
      // Previously every cash-drawer change inserted a new row; we now treat
      // the balance as a single persistent variable.
      final rows = await db.query('balance', orderBy: 'id DESC');
      int latest = 0;
      int isSynced = 1;
      if (rows.isNotEmpty) {
        latest = (rows.first['currentBalance'] as int?) ?? 0;
        isSynced = (rows.first['is_synced'] as int?) ?? 1;
      }
      await db.delete('balance');
      await db.insert('balance', {
        'id': 1,
        'currentBalance': latest,
        'is_synced': isSynced,
      });
    }
    if (oldVersion < 11) {
      // Add a parallel card-balance column. Card sales deposit into this
      // variable so the owner can reconcile against the payment processor
      // without querying the sales table each time.
      await db.execute(
        'ALTER TABLE balance ADD COLUMN cardBalance INTEGER DEFAULT 0',
      );
    }
  }

  Future _onConfigure(Database db) async {
    // Add support for foreign keys
    await db.execute('PRAGMA foreign_keys = ON');
  }

  Future _createDB(Database db, int version) async {
    // 1. users
    await db.execute('''
    CREATE TABLE users (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL,
      role TEXT NOT NULL,
      created_at TEXT DEFAULT CURRENT_TIMESTAMP,
      password TEXT,
      is_synced INTEGER DEFAULT 0
    )
    ''');

    // 2. categories
    await db.execute('''
    CREATE TABLE categories (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL,
      is_synced INTEGER DEFAULT 0
    )
    ''');

    // 3. products
    await db.execute('''
    CREATE TABLE products (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL,
      barcode TEXT UNIQUE,
      price REAL NOT NULL,
      cost_price REAL,
      quantity REAL DEFAULT 0,
      category_id INTEGER,
      image_url TEXT,
      base_unit_id INTEGER,
      base_unit_conversion REAL DEFAULT 1.0,
      is_card INTEGER DEFAULT 0,
      created_at TEXT DEFAULT CURRENT_TIMESTAMP,
      is_synced INTEGER DEFAULT 0,
      FOREIGN KEY (category_id) REFERENCES categories (id),
      FOREIGN KEY (base_unit_id) REFERENCES products (id)
    )
    ''');

    // 4. balance — single-row variable pinned at id=1.
    //    currentBalance holds the cash drawer balance.
    //    cardBalance accumulates card-payment revenue so it can be
    //    reconciled with the external card processor statement.
    await db.execute('''
    CREATE TABLE balance (
      id INTEGER PRIMARY KEY,
      created_at TEXT DEFAULT CURRENT_TIMESTAMP,
      currentBalance INTEGER DEFAULT 0,
      cardBalance INTEGER DEFAULT 0,
      is_synced INTEGER DEFAULT 0
    )
    ''');
    await db.insert('balance', {
      'id': 1,
      'currentBalance': 0,
      'cardBalance': 0,
      'is_synced': 1,
    });

    // 5. sales
    await db.execute('''
    CREATE TABLE sales (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      total_price REAL NOT NULL,
      payment_type TEXT NOT NULL,
      created_at TEXT DEFAULT CURRENT_TIMESTAMP,
      user_id INTEGER,
      remote_id INTEGER,
      is_synced INTEGER DEFAULT 0,
      FOREIGN KEY (user_id) REFERENCES users (id)
    )
    ''');

    // 6. sale_items
    await db.execute('''
    CREATE TABLE sale_items (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      sale_id INTEGER NOT NULL,
      product_id INTEGER NOT NULL,
      quantity REAL NOT NULL,
      price REAL NOT NULL,
      FOREIGN KEY (sale_id) REFERENCES sales (id) ON DELETE CASCADE,
      FOREIGN KEY (product_id) REFERENCES products (id)
    )
    ''');

    // 7. sessions
    await db.execute('''
    CREATE TABLE sessions (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      user_id INTEGER NOT NULL,
      started_at TEXT DEFAULT CURRENT_TIMESTAMP,
      ended_at TEXT,
      is_active INTEGER DEFAULT 1,
      session_code TEXT,
      is_synced INTEGER DEFAULT 0,
      FOREIGN KEY (user_id) REFERENCES users (id)
    )
    ''');

    // 8. stock_movements
    await db.execute('''
    CREATE TABLE stock_movements (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      product_id INTEGER,
      change REAL,
      reason TEXT,
      created_at TEXT DEFAULT CURRENT_TIMESTAMP,
      is_synced INTEGER DEFAULT 0,
      FOREIGN KEY (product_id) REFERENCES products (id)
    )
    ''');

    // 9. cash_drawer_logs
    await db.execute('''
    CREATE TABLE cash_drawer_logs (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      reason TEXT,
      amount REAL DEFAULT 0,
      type TEXT NOT NULL,
      user_id INTEGER,
      created_at TEXT DEFAULT CURRENT_TIMESTAMP,
      is_synced INTEGER DEFAULT 0,
      FOREIGN KEY (user_id) REFERENCES users (id)
    )
    ''');

    // 10. cards (recharge cards)
    await db.execute('''
    CREATE TABLE cards (
      id INTEGER PRIMARY KEY,
      name TEXT,
      product_id INTEGER,
      price INTEGER DEFAULT 0,
      spended_balance INTEGER DEFAULT 0,
      created_at TEXT,
      FOREIGN KEY (product_id) REFERENCES products (id)
    )
    ''');
  }
}
