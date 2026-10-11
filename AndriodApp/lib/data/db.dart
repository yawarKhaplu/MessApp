import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

/// SQLite database for MessApp (PRD section 7 data model).
class AppDb {
  AppDb._();
  static final AppDb instance = AppDb._();

  Database? _db;

  Future<Database> get db async => _db ??= await _open();

  Future<Database> _open() async {
    final dir = await getDatabasesPath();
    final path = join(dir, 'messapp.db');
    final today = _todayKey();
    return openDatabase(
      path,
      version: 6,
      onUpgrade: (db, oldVersion, newVersion) async {
        // v2: track which member cooked/paid for each expense,
        // and allow a daily budget override in settings.
        if (oldVersion < 2) {
          await db.execute(
              'ALTER TABLE expenses ADD COLUMN member_id INTEGER');
          await db.execute('ALTER TABLE settings ADD COLUMN daily_budget REAL NOT NULL DEFAULT 0');
        }
        // v3: user-controlled cooking rotation, anchored on a date + member.
        if (oldVersion < 3) {
          await _createRotation(db, today);
        }
        // v4: let the user pick the cooking order, and let the rotation
        // follow real cooking history until they override it.
        if (oldVersion < 4) {
          await db.execute(
              "ALTER TABLE rotation ADD COLUMN member_order TEXT NOT NULL DEFAULT ''");
          await db.execute(
              'ALTER TABLE rotation ADD COLUMN manual INTEGER NOT NULL DEFAULT 0');
        }
        // v5: items keep their order inside a menu.
        if (oldVersion < 5) {
          await db.execute(
              'ALTER TABLE menu_items ADD COLUMN sort_order INTEGER NOT NULL DEFAULT 0');
        }
        // v6: recurring categories (rent, gas, cups…) get a monthly budget.
        if (oldVersion < 6) {
          await db.execute(
              'ALTER TABLE other_categories ADD COLUMN monthly_budget REAL NOT NULL DEFAULT 0');
        }
      },
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE menus (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            is_default INTEGER NOT NULL DEFAULT 0
          )
        ''');
        await db.execute('''
          CREATE TABLE menu_items (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            menu_id INTEGER NOT NULL REFERENCES menus(id) ON DELETE CASCADE,
            name TEXT NOT NULL,
            default_price REAL NOT NULL DEFAULT 0,
            sort_order INTEGER NOT NULL DEFAULT 0
          )
        ''');
        await db.execute('''
          CREATE TABLE expenses (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            date TEXT NOT NULL,
            menu_id INTEGER REFERENCES menus(id),
            member_id INTEGER REFERENCES members(id),
            total REAL NOT NULL DEFAULT 0
          )
        ''');
        await db.execute('''
          CREATE TABLE expense_items (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            expense_id INTEGER NOT NULL REFERENCES expenses(id) ON DELETE CASCADE,
            item_name TEXT NOT NULL,
            quantity REAL NOT NULL DEFAULT 1,
            price REAL NOT NULL DEFAULT 0
          )
        ''');
        await db.execute('''
          CREATE TABLE members (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE collections (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            member_id INTEGER NOT NULL REFERENCES members(id) ON DELETE CASCADE,
            month TEXT NOT NULL,
            amount_due REAL NOT NULL DEFAULT 0,
            UNIQUE(member_id, month)
          )
        ''');
        await db.execute('''
          CREATE TABLE payments (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            collection_id INTEGER NOT NULL REFERENCES collections(id) ON DELETE CASCADE,
            amount REAL NOT NULL,
            date TEXT NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE other_expenses (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            date TEXT NOT NULL,
            category TEXT NOT NULL,
            amount REAL NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE settings (
            id INTEGER PRIMARY KEY CHECK (id = 1),
            reminder_time TEXT NOT NULL DEFAULT '21:00',
            reminder_enabled INTEGER NOT NULL DEFAULT 1,
            currency TEXT NOT NULL DEFAULT 'PKR',
            daily_budget REAL NOT NULL DEFAULT 0
          )
        ''');

        await _seed(db);
      },
    );
  }

  /// Default data per PRD 5.2 / 5.3 / 5.7.
  Future<void> _seed(Database db) async {
    // Default menus with items.
    final pulao = await db.insert('menus', {'name': 'Pulao', 'is_default': 1});
    for (final item in ['Rice', 'Masala', 'Tomato', 'Onion']) {
      await db.insert('menu_items',
          {'menu_id': pulao, 'name': item, 'default_price': 0});
    }

    final karahi = await db.insert('menus', {'name': 'Karahi', 'is_default': 1});
    for (final item in ['Mutton', 'Tomato', 'Onion', 'Masala', 'Ginger']) {
      await db.insert('menu_items',
          {'menu_id': karahi, 'name': item, 'default_price': 0});
    }

    // Default other-expense categories are stored in a simple table too,
    // so users can extend them.
    await db.execute('''
      CREATE TABLE other_categories (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL UNIQUE,
        monthly_budget REAL NOT NULL DEFAULT 0
      )
    ''');
    for (final c in ['Gas', 'Electricity', 'Rent']) {
      await db.insert('other_categories', {'name': c});
    }

    // Default settings row.
    await db.insert('settings', {'id': 1});

    // Cooking rotation starts today with the first member.
    await _createRotation(db, _todayKey());
  }

  /// The single-row table holding the cooking-rotation anchor.
  ///
  /// [anchor_date] is a day on which [anchor_index] (a position in the
  /// member list) has the bari. Every following day simply advances one
  /// position, so the cycle is fully user-controlled and never drifts.
  ///
  /// [member_order] holds the rotation order as comma-separated member ids so
  /// the user can decide who comes after whom. [manual] flips to 1 once the
  /// user picks a bari themselves; until then the rotation follows whatever
  /// was actually cooked.
  static Future<void> _createRotation(Database db, String today) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS rotation (
        id INTEGER PRIMARY KEY CHECK (id = 1),
        anchor_date TEXT NOT NULL,
        anchor_index INTEGER NOT NULL DEFAULT 0,
        member_order TEXT NOT NULL DEFAULT '',
        manual INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await db.insert(
      'rotation',
      {
        'id': 1,
        'anchor_date': today,
        'anchor_index': 0,
        'member_order': '',
        'manual': 0,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  static String _todayKey() {
    final n = DateTime.now();
    return '${n.year.toString().padLeft(4, '0')}-'
        '${n.month.toString().padLeft(2, '0')}-'
        '${n.day.toString().padLeft(2, '0')}';
  }

  Future<void> close() async {
    final d = _db;
    if (d != null) {
      await d.close();
      _db = null;
    }
  }
}
