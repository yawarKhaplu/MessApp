import 'package:sqflite/sqflite.dart';

import 'db.dart';
import 'models.dart';

/// Repository: all database access for MessApp.
/// How a menu's total was split across its items last time, learned from
  /// past entries.
class SplitHints {
  /// Item name -> fraction of the total (values sum to 1).
  final Map<String, double> shares;

  /// When those proportions were learned, for display.
  final DateTime? learnedFrom;

  /// True when these come from a single real entry rather than an average.
  final bool isExact;

  const SplitHints(this.shares, this.learnedFrom, {this.isExact = false});

  static const SplitHints empty = SplitHints({}, null);
}

class MessRepository {
  final AppDb _db = AppDb.instance;

  Future<Database> get _database => _db.db;

  // ---------- Menus ----------

  Future<List<Menu>> getMenus() async {
    final rows = await (await _database).query('menus', orderBy: 'name COLLATE NOCASE');
    return rows.map(Menu.fromMap).toList();
  }

  Future<int> addMenu(String name) async {
    return (await _database).insert('menus', {'name': name, 'is_default': 0});
  }

  Future<void> renameMenu(int id, String name) async {
    await (await _database)
        .update('menus', {'name': name}, where: 'id = ?', whereArgs: [id]);
  }

  Future<void> deleteMenu(int id) async {
    final d = await _database;
    await d.delete('menus', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<MenuItem>> getMenuItems(int menuId) async {
    final rows = await (await _database).query('menu_items',
        where: 'menu_id = ?',
        whereArgs: [menuId],
        orderBy: 'sort_order ASC, id ASC');
    return rows.map(MenuItem.fromMap).toList();
  }

  /// How many items each menu holds, so the menu list can show counts.
  Future<Map<int, int>> getMenuItemCounts() async {
    final rows = await (await _database).rawQuery('''
      SELECT menu_id, COUNT(*) AS c FROM menu_items GROUP BY menu_id
    ''');
    final counts = <int, int>{};
    for (final r in rows) {
      final id = r['menu_id'] as int?;
      if (id == null) continue;
      counts[id] = (r['c'] as num?)?.toInt() ?? 0;
    }
    return counts;
  }

  /// Items that belong to other menus, so they can be reused instead of
/// retyped. Returns the name, the menus it appears in and a typical price.
Future<List<Map<String, Object?>>> getItemSuggestions(
    int excludeMenuId) async {
  return (await _database).rawQuery('''
    SELECT i.item_name AS name,
           GROUP_CONCAT(DISTINCT m.name) AS menus,
           MAX(i.default_price) AS last_price
    FROM menu_items i
    JOIN menus m ON m.id = i.menu_id
    WHERE i.menu_id != ?
    GROUP BY i.item_name COLLATE NOCASE
    ORDER BY i.item_name COLLATE NOCASE
  ''', [excludeMenuId]);
}

Future<int> addMenuItem(int menuId, String name, double defaultPrice) async {
    return (await _database).insert(
        'menu_items', {'menu_id': menuId, 'name': name, 'default_price': defaultPrice});
  }

  Future<void> updateMenuItem(int id, String name, double defaultPrice) async {
    await (await _database).update(
      'menu_items',
      {'name': name, 'default_price': defaultPrice},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Reorder items within a menu.
  Future<void> reorderMenuItems(List<int> ids) async {
    final d = await _database;
    for (int i = 0; i < ids.length; i++) {
      await d.update('menu_items', {'sort_order': i},
          where: 'id = ?', whereArgs: [ids[i]]);
    }
  }

  Future<void> deleteMenuItem(int id) async {
    await (await _database)
        .delete('menu_items', where: 'id = ?', whereArgs: [id]);
  }

  /// Distinct item names ever used, with their last price (for fast entry).
  Future<List<Map<String, Object?>>> getItemHistory() async {
    return (await _database).rawQuery('''
      SELECT item_name, price FROM expense_items
      WHERE id IN (SELECT MAX(id) FROM expense_items GROUP BY item_name)
      ORDER BY item_name COLLATE NOCASE
    ''');
  }

  // ---------- Expenses (menu entries) ----------

  /// Saves an expense with its items. Returns the new expense id.
  Future<int> addExpense({
    required DateTime date,
    required int menuId,
    required List<ExpenseItem> items,
    int? memberId,
  }) async {
    final d = await _database;
    final total = items.fold<double>(0, (s, i) => s + i.lineTotal);
    final expenseId = await d.insert('expenses', {
      'date': dayKey(date),
      'menu_id': menuId,
      'member_id': memberId,
      'total': total,
    });
    for (final item in items) {
      await d.insert('expense_items', {
        'expense_id': expenseId,
        'item_name': item.itemName,
        'quantity': item.quantity,
        'price': item.price,
      });
    }
    return expenseId;
  }

  Future<void> deleteExpense(int id) async {
    final d = await _database;
    await d.delete('expense_items', where: 'expense_id = ?', whereArgs: [id]);
    await d.delete('expenses', where: 'id = ?', whereArgs: [id]);
  }

  /// Updates an existing expense's items, total and/or assigned member.
  Future<void> updateExpense({
    required int id,
    required List<ExpenseItem> items,
    int? memberId,
  }) async {
    final d = await _database;
    final total = items.fold<double>(0, (s, i) => s + i.lineTotal);
    await d.delete('expense_items', where: 'expense_id = ?', whereArgs: [id]);
    for (final item in items) {
      await d.insert('expense_items', {
        'expense_id': id,
        'item_name': item.itemName,
        'quantity': item.quantity,
        'price': item.price,
      });
    }
    await d.update('expenses', {'total': total, 'member_id': memberId},
        where: 'id = ?', whereArgs: [id]);
  }

  /// Moves an existing expense to a different date.
  Future<void> updateExpenseDate(int id, DateTime date) async {
    await (await _database).update('expenses', {'date': dayKey(date)},
        where: 'id = ?', whereArgs: [id]);
  }

  Future<List<Expense>> getExpenses({DateTime? from, DateTime? to}) async {
    final d = await _database;
    final where = StringBuffer('1=1');
    final args = <Object?>[];
    if (from != null) {
      where.write(' AND date >= ?');
      args.add(dayKey(from));
    }
    if (to != null) {
      where.write(' AND date <= ?');
      args.add(dayKey(to));
    }
    final rows = await d.query('expenses',
        where: where.toString(),
        whereArgs: args,
        orderBy: 'date DESC, id DESC');
    return rows.map(Expense.fromMap).toList();
  }

  Future<List<ExpenseItem>> getExpenseItems(int expenseId) async {
    final rows = await (await _database)
        .query('expense_items', where: 'expense_id = ?', whereArgs: [expenseId]);
    return rows.map(ExpenseItem.fromMap).toList();
  }

  /// Expenses for a single day, with menu name.
  Future<List<Map<String, Object?>>> getDayExpenses(DateTime day) async {
    return (await _database).rawQuery('''
      SELECT e.id, e.date, e.total, e.menu_id, e.member_id,
             m.name AS menu_name, mem.name AS member_name
      FROM expenses e
      LEFT JOIN menus m ON m.id = e.menu_id
      LEFT JOIN members mem ON mem.id = e.member_id
      WHERE e.date = ?
      ORDER BY e.id DESC
    ''', [dayKey(day)]);
  }

  /// Cooking-duty rotation for a given day.
  ///
  /// The cycle is anchored on a date + member index that the user controls
  ///
  /// The cycle is anchored on a date + member index that the user controls
  /// (see [setBari]). From that anchor the turn advances one member per day,
  /// so with N members each person cooks once and comes back around after
  /// the other N-1 have taken their turn.
  Future<CookRotation> getCookRotation([DateTime? day]) async {
    final members = await getRotationOrder();
    if (members.isEmpty) return const CookRotation.empty();

    final d = _dateOnly(day ?? DateTime.now());
    final anchor = await _effectiveAnchor(members);

    final n = members.length;
    // Days elapsed since the anchor (negative when looking at past dates).
    final elapsed = d.difference(anchor.date).inDays;
    var idx = (anchor.index + elapsed) % n;
    if (idx < 0) idx += n;

    const lookahead = 7;
    final upcoming = <CookTurn>[];
    for (int i = 0; i < lookahead; i++) {
      var k = (idx + i) % n;
      if (k < 0) k += n;
      upcoming.add(CookTurn(d.add(Duration(days: i)), members[k]));
    }

    // What was genuinely recorded for today, if anything.
    RecordedCook? recorded;
    final today = _dateOnly(DateTime.now());
    if (d.year == today.year && d.month == today.month && d.day == today.day) {
      recorded = await getRecordedCook(d);
    }

    return CookRotation(
      members: members,
      cook: members[idx],
      next: members[(idx + 1) % n],
      positionInRound: idx + 1,
      roundLength: n,
      anchorDate: anchor.date,
      upcoming: upcoming,
      followsHistory: !anchor.manual,
      recordedCook: recorded,
    );
  }

  /// Who actually cooked on [day], according to saved entries.
  Future<RecordedCook?> getRecordedCook(DateTime day) async {
    final rows = await (await _database).rawQuery('''
      SELECT e.date, e.member_id FROM expenses e
      WHERE e.date = ? AND e.member_id IS NOT NULL
      ORDER BY e.id DESC LIMIT 1
    ''', [dayKey(day)]);
    if (rows.isEmpty) return null;
    final memberId = rows.first['member_id'] as int?;
    if (memberId == null) return null;
    final member = await getMemberById(memberId);
    if (member == null) return null;
    return RecordedCook(DateTime.parse(rows.first['date'] as String), member);
  }

  /// The most recent day on which somebody actually cooked.
  Future<RecordedCook?> getLastRecordedCook() async {
    final rows = await (await _database).rawQuery('''
      SELECT e.date, e.member_id FROM expenses e
      WHERE e.member_id IS NOT NULL
      ORDER BY e.date DESC, e.id DESC LIMIT 1
    ''');
    if (rows.isEmpty) return null;
    final memberId = rows.first['member_id'] as int?;
    if (memberId == null) return null;
    final member = await getMemberById(memberId);
    if (member == null) return null;
    return RecordedCook(DateTime.parse(rows.first['date'] as String), member);
  }

  Future<Member?> getMemberById(int id) async {
    final rows =
        await (await _database).query('members', where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return null;
    return Member.fromMap(rows.first);
  }

  /// The members in the order the user wants them to take turns.
  ///
  /// New members are appended automatically, so the order never breaks when
  /// somebody joins or leaves.
  Future<List<Member>> getRotationOrder() async {
    final members = await getMembers();
    if (members.isEmpty) return const [];

    final stored = await _readRotation();
    final ids = <int>[];
    for (final part in stored.memberOrder.split(',')) {
      final id = int.tryParse(part.trim());
      if (id != null && ids.indexOf(id) < 0) ids.add(id);
    }

    final ordered = <Member>[];
    for (final id in ids) {
      for (final m in members) {
        if (m.id == id) {
          ordered.add(m);
          break;
        }
      }
    }
    for (final m in members) {
      if (!ordered.any((o) => o.id == m.id)) ordered.add(m);
    }
    return ordered;
  }

  /// Save the cooking order (list of member ids).
  Future<void> setRotationOrder(List<int> memberIds) async {
    final stored = await _readRotation();
    await _writeRotation(
      date: stored.anchorDate,
      index: stored.index,
      order: memberIds.join(','),
      manual: stored.manual,
    );
  }

  /// The stored rotation anchor: the day and member position it starts from.
  Future<({DateTime date, int index})> getRotationAnchor() async {
    final members = await getRotationOrder();
    final a = await _effectiveAnchor(members);
    return (date: a.date, index: a.index);
  }

  /// Where the cycle starts right now.
  ///
  /// Until the user takes over, this follows the real cooking history: the
  /// person who cooked last anchors the cycle and today's turn is whoever
  /// comes after them. Once they pick a bari themselves the choice sticks.
  Future<({DateTime date, int index, bool manual})> _effectiveAnchor(
      List<Member> members) async {
    final stored = await _readRotation();
    var date = stored.anchorDate;
    var index = stored.index;

    if (!stored.manual) {
      final last = await getLastRecordedCook();
      if (last != null) {
        date = _dateOnly(last.date);
        for (int i = 0; i < members.length; i++) {
          if (members[i].id == last.member.id) {
            index = i;
            break;
          }
        }
      }
    }
    if (members.isNotEmpty) {
      index %= members.length;
      if (index < 0) index += members.length;
    }
    return (date: date, index: index, manual: stored.manual);
  }

  /// Move the bari: [member] takes cooking duty on [day].
  ///
  /// This re-anchors the whole cycle, so the days after it keep rotating in
  /// the usual order — the change stays put instead of snapping back.
  Future<void> setBari(DateTime day, Member member) async {
    final members = await getRotationOrder();
    var idx = 0;
    for (int i = 0; i < members.length; i++) {
      if (members[i].id == member.id) {
        idx = i;
        break;
      }
    }
    final stored = await _readRotation();
    await _writeRotation(
      date: _dateOnly(day),
      index: idx,
      order: stored.memberOrder,
      manual: true,
    );
  }

  /// Start the rotation over from today with the first member.
  Future<void> resetRotation() async {
    final stored = await _readRotation();
    await _writeRotation(
      date: _dateOnly(DateTime.now()),
      index: 0,
      order: stored.memberOrder,
      manual: true,
    );
  }

  /// Let the rotation go back to following real cooking history.
  Future<void> followHistoryAgain() async {
    final stored = await _readRotation();
    await _writeRotation(
      date: _dateOnly(DateTime.now()),
      index: stored.index,
      order: stored.memberOrder,
      manual: false,
    );
  }

  Future<({DateTime anchorDate, int index, String memberOrder, bool manual})>
      _readRotation() async {
    final rows = await (await _database)
        .query('rotation', where: 'id = 1', limit: 1);
    if (rows.isEmpty) {
      final today = _dateOnly(DateTime.now());
      await _writeRotation(date: today, index: 0, order: '', manual: false);
      return (
        anchorDate: today,
        index: 0,
        memberOrder: '',
        manual: false
      );
    }
    final r = rows.first;
    return (
      anchorDate: _dateOnly(DateTime.parse(r['anchor_date'] as String)),
      index: (r['anchor_index'] as int?) ?? 0,
      memberOrder: (r['member_order'] as String?) ?? '',
      manual: ((r['manual'] as int?) ?? 0) == 1,
    );
  }

  Future<void> _writeRotation({
    required DateTime date,
    required int index,
    required String order,
    required bool manual,
  }) async {
    await (await _database).insert(
      'rotation',
      {
        'id': 1,
        'anchor_date': dayKey(date),
        'anchor_index': index,
        'member_order': order,
        'manual': manual ? 1 : 0,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  static DateTime _dateOnly(DateTime d) =>
      DateTime(d.year, d.month, d.day);

  /// Who is recorded as cooking a given expense, read straight from the entry.
  Future<Member?> getExpenseMember(int expenseId) async {
    final rows = await (await _database).query('expenses',
        columns: ['member_id'], where: 'id = ?', whereArgs: [expenseId]);
    if (rows.isEmpty) return null;
    final id = rows.first['member_id'] as int?;
    if (id == null) return null;
    return getMemberById(id);
  }

  /// Who is on cooking duty for a given day.
  ///
  /// Returns null when no members exist.
  Future<Member?> getCookOfTheDay([DateTime? day]) async =>
      (await getCookRotation(day)).cook;

  // ---------- Auto-split from history ----------

  /// Works out how a menu's total was divided between its items last time,
  /// so a new entry can be filled in by typing just the total.
  ///
  /// Prefers the most recent entry for that menu (an exact repeat of what
  /// worked before); falls back to averaging every past entry, and finally to
  /// [SplitHints.empty] when nothing has been recorded yet.
  Future<SplitHints> getSplitHints(int menuId) async {
    final d = await _database;

    // 1. Most recent entry for this menu -> exact proportions.
    final latest = await d.rawQuery('''
      SELECT e.id, e.date FROM expenses e
      WHERE e.menu_id = ? AND e.total > 0
      ORDER BY e.date DESC, e.id DESC LIMIT 1
    ''', [menuId]);

    if (latest.isNotEmpty) {
      final expenseId = latest.first['id'] as int?;
      final rows = await d.rawQuery('''
        SELECT item_name, SUM(price * quantity) AS amount
        FROM expense_items WHERE expense_id = ?
        GROUP BY item_name COLLATE NOCASE
      ''', [expenseId]);
      final shares = _normalise(rows);
      if (shares.isNotEmpty) {
        return SplitHints(
          shares,
          DateTime.parse(latest.first['date'] as String),
          isExact: true,
        );
      }
    }

    // 2. Otherwise average every entry ever made for this menu.
    final avg = await d.rawQuery('''
      SELECT i.item_name AS item_name, AVG(i.price * i.quantity) AS amount
      FROM expense_items i JOIN expenses e ON e.id = i.expense_id
      WHERE e.menu_id = ?
      GROUP BY i.item_name COLLATE NOCASE
    ''', [menuId]);
    final shares = _normalise(avg);
    if (shares.isEmpty) return SplitHints.empty;
    return SplitHints(shares, null);
  }

  /// Turns raw amount rows into fractions of the whole, keyed by lower-cased
  /// item name so they can be matched case-insensitively.
  Map<String, double> _normalise(List<Map<String, Object?>> rows) {
    final amounts = <String, double>{};
    var sum = 0.0;
    for (final r in rows) {
      final name = r['item_name'] as String?;
      final amount = (r['amount'] as num?)?.toDouble() ?? 0.0;
      if (name == null || amount <= 0) continue;
      final key = name.trim().toLowerCase();
      final running = (amounts[key] ?? 0.0) + amount;
      amounts[key] = running;
      sum += running;
    }
    if (sum <= 0) return {};
    return amounts.map((k, v) => MapEntry(k, v / sum));
  }

  /// Per-member spend on menu expenses over a range (report tab).
  Future<List<Map<String, Object?>>> getMemberWiseTotals(
      DateTime from, DateTime to) async {
    return (await _database).rawQuery('''
      SELECT COALESCE(mem.name, 'Unassigned') AS name,
             COALESCE(SUM(e.total), 0) AS total,
             COUNT(e.id) AS entries
      FROM expenses e
      LEFT JOIN members mem ON mem.id = e.member_id
      WHERE e.date BETWEEN ? AND ?
      GROUP BY e.member_id
      ORDER BY total DESC
    ''', [dayKey(from), dayKey(to)]);
  }

  /// Today's budget summary: budget, spent, remaining.
  ///
  /// Budget logic:
  ///  1. If a manual daily budget is set in Settings, use it.
  ///  2. Otherwise auto-derive: this month's total collection target
  ///     (sum of member shares) divided by the number of days in the month.
  ///  3. If no shares are set, fall back to 0 (no budget shown).
  Future<Map<String, double>> getTodayBudget() async {
    final now = DateTime.now();
    final settings = await getSettings();

    final monthStart = dayKey(DateTime(now.year, now.month, 1));
    final todayKey = dayKey(now);
    final daysInMonth = DateTime(now.year, now.month + 1, 0).day;
    // Days AFTER today. On 11 October a 31-day month leaves 20 (the 12th to
    // the 31st); today is deliberately excluded here and added back when the
    // frozen daily cap below is worked out.
    final daysLeft = daysInMonth - now.day;

    // What the mess has committed to collecting this month.
    final targetRows = await (await _database).rawQuery('''
      SELECT COALESCE(SUM(amount_due), 0) AS target
      FROM collections WHERE month = ?
    ''', [monthKey(now)]);
    final monthlyTarget =
        (targetRows.first['target'] as num?)?.toDouble() ?? 0;

    double budget = settings.dailyBudget;
    if (budget <= 0 && monthlyTarget > 0) {
      // Auto: monthly target / days in month.
      budget = monthlyTarget / daysInMonth;
    }

    // Month to date covers food AND other expenses, because the budget does.
    final monthRows = await (await _database).rawQuery('''
      SELECT (SELECT COALESCE(SUM(total),0) FROM expenses
              WHERE date BETWEEN ? AND ?) +
             (SELECT COALESCE(SUM(amount),0) FROM other_expenses
              WHERE date BETWEEN ? AND ?) AS s
    ''', [monthStart, todayKey, monthStart, todayKey]);
    final monthSpent = (monthRows.first['s'] as num?)?.toDouble() ?? 0;

    final spent = await getDayTotal(now);

    final basis = monthlyTarget > 0 ? monthlyTarget : budget * daysInMonth;
    final left = basis - monthSpent;

    // Spend from BEFORE today only.
    //
    // Using month-to-date here would let today's own spending lower the bar
    // that today's spending is then measured against. That is what made the
    // figure on screen differ from the threshold actually being enforced.
    final beforeRows = await (await _database).rawQuery('''
      SELECT (SELECT COALESCE(SUM(total),0) FROM expenses
              WHERE date >= ? AND date < ?) +
             (SELECT COALESCE(SUM(amount),0) FROM other_expenses
              WHERE date >= ? AND date < ?) AS s
    ''', [monthStart, todayKey, monthStart, todayKey]);
    final monthSpentBefore =
        (beforeRows.first['s'] as num?)?.toDouble() ?? 0;

    // Today's share of whatever was left when the day began, spread across
    // today plus the days that follow it. Frozen for the whole day, so what is
    // shown is exactly what is enforced.
    final daysFromDayStart = daysLeft + 1;
    final capToday = (daysFromDayStart > 0 && basis > monthSpentBefore)
        ? (basis - monthSpentBefore) / daysFromDayStart
        : 0.0;

    // Live pace for the month-level cards, which are meant to move.
    final safe = daysLeft > 0 && left > 0 ? left / daysLeft : 0.0;

    return {
      'budget': budget,
      'spent': spent,
      'remaining': budget - spent,
      'capToday': capToday,
      'capLeft': capToday - spent,
      'safeToSpend': safe,
      'daysLeft': daysLeft.toDouble(),
      'hasTarget': basis > 0 ? 1 : 0,
      'monthLeft': left,
    };
  }

  // ---------- Other expenses ----------

  Future<int> addOtherExpense({
    required DateTime date,
    required String category,
    required double amount,
  }) async {
    return (await _database).insert(
        'other_expenses', {'date': dayKey(date), 'category': category, 'amount': amount});
  }

  /// Corrects an existing other-expense record.
  Future<void> updateOtherExpense({
    required int id,
    required DateTime date,
    required String category,
    required double amount,
  }) async {
    await (await _database).update(
      'other_expenses',
      {'date': dayKey(date), 'category': category, 'amount': amount},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> deleteOtherExpense(int id) async {
    await (await _database)
        .delete('other_expenses', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<OtherExpense>> getOtherExpenses({DateTime? from, DateTime? to}) async {
    final d = await _database;
    final where = StringBuffer('1=1');
    final args = <Object?>[];
    if (from != null) {
      where.write(' AND date >= ?');
      args.add(dayKey(from));
    }
    if (to != null) {
      where.write(' AND date <= ?');
      args.add(dayKey(to));
    }
    final rows = await d.query('other_expenses',
        where: where.toString(), whereArgs: args, orderBy: 'date DESC, id DESC');
    return rows.map(OtherExpense.fromMap).toList();
  }

  Future<List<String>> getOtherCategories() async {
    final rows =
        await (await _database).query('other_categories', orderBy: 'name COLLATE NOCASE');
    return rows.map((r) => r['name'] as String).toList();
  }

  Future<void> addOtherCategory(String name) async {
    final d = await _database;
    await d.insert('other_categories', {'name': name});
  }

  /// How many expense records are filed under a category.
  Future<int> getCategoryUsage(String category) async {
    final rows = await (await _database).rawQuery(
        'SELECT COUNT(*) AS c FROM other_expenses WHERE category = ?',
        [category]);
    return (rows.first['c'] as num?)?.toInt() ?? 0;
  }

  /// Renames a category everywhere — including on past expense records — so
  /// the history stays consistent with the new name.
  Future<void> renameOtherCategory(String oldName, String newName) async {
    final d = await _database;
    await d.update('other_categories', {'name': newName},
        where: 'name = ?', whereArgs: [oldName]);
    await d.update('other_expenses', {'category': newName},
        where: 'category = ?', whereArgs: [oldName]);
  }

  /// Removes a category. When [keepRecords] is true the old expenses are
  /// re-filed under "Other" instead of being destroyed.
  Future<void> deleteOtherCategory(String name,
      {bool keepRecords = false}) async {
    final d = await _database;
    await d.delete('other_categories', where: 'name = ?', whereArgs: [name]);
    if (keepRecords) {
      await d.update('other_expenses', {'category': 'Other'},
          where: 'category = ?', whereArgs: [name]);
    } else {
      await d
          .delete('other_expenses', where: 'category = ?', whereArgs: [name]);
    }
  }

  /// Sets (or clears, with 0) a category's monthly allowance.
  Future<void> setCategoryBudget(String name, double amount) async {
    await (await _database).update(
      'other_categories',
      {'monthly_budget': amount},
      where: 'name = ?',
      whereArgs: [name],
    );
  }

  /// Every category with its allowance and what has been spent this month.
  Future<List<CategoryBudget>> getCategoryBudgets(DateTime month) async {
    final d = await _database;
    final first = DateTime(month.year, month.month, 1);
    final last = DateTime(month.year, month.month + 1, 0);

    final rows = await d.rawQuery('''
      SELECT c.name AS name,
             c.monthly_budget AS budget,
             (SELECT COALESCE(SUM(o.amount),0) FROM other_expenses o
              WHERE o.category = c.name AND o.date BETWEEN ? AND ?) AS spent
      FROM other_categories c
      ORDER BY (c.monthly_budget > 0) DESC, c.name COLLATE NOCASE
    ''', [dayKey(first), dayKey(last)]);

    return rows
        .map((r) => CategoryBudget(
              (r['name'] as String?) ?? '',
              (r['budget'] as num?)?.toDouble() ?? 0,
              (r['spent'] as num?)?.toDouble() ?? 0,
            ))
        .toList();
  }

  // ---------- Members & collection ----------

  Future<List<Member>> getMembers() async {
    final rows =
        await (await _database).query('members', orderBy: 'name COLLATE NOCASE');
    return rows.map(Member.fromMap).toList();
  }

  Future<int> addMember(String name) async {
    return (await _database).insert('members', {'name': name});
  }

  Future<void> renameMember(int id, String name) async {
    await (await _database)
        .update('members', {'name': name}, where: 'id = ?', whereArgs: [id]);
  }

  Future<void> deleteMember(int id) async {
    await (await _database)
        .delete('members', where: 'id = ?', whereArgs: [id]);
  }

  /// Gets (or creates) the collection row for a member and month.
  Future<Collection> getCollection(int memberId, String month) async {
    final d = await _database;
    final rows = await d.query('collections',
        where: 'member_id = ? AND month = ?', whereArgs: [memberId, month]);
    if (rows.isNotEmpty) return Collection.fromMap(rows.first);
    final id = await d
        .insert('collections', {'member_id': memberId, 'month': month, 'amount_due': 0});
    return Collection(id: id, memberId: memberId, month: month);
  }

  Future<void> setMonthlyShare(int memberId, String month, double amount) async {
    final c = await getCollection(memberId, month);
    await (await _database).update('collections', {'amount_due': amount},
        where: 'id = ?', whereArgs: [c.id]);
  }

  /// Collections for a month with paid totals and member names.
  Future<List<Map<String, Object?>>> getMonthCollections(String month) async {
    return (await _database).rawQuery('''
      SELECT c.id, c.member_id, m.name AS member_name, c.month, c.amount_due,
             COALESCE(SUM(p.amount), 0) AS paid
      FROM collections c
      JOIN members m ON m.id = c.member_id
      LEFT JOIN payments p ON p.collection_id = c.id
      WHERE c.month = ?
      GROUP BY c.id
      ORDER BY m.name COLLATE NOCASE
    ''', [month]);
  }

  Future<List<Payment>> getPayments(int collectionId) async {
    final rows = await (await _database).query('payments',
        where: 'collection_id = ?',
        whereArgs: [collectionId],
        orderBy: 'date DESC, id DESC');
    return rows.map(Payment.fromMap).toList();
  }

  Future<int> addPayment({
    required int collectionId,
    required double amount,
    required DateTime date,
  }) async {
    return (await _database).insert('payments',
        {'collection_id': collectionId, 'amount': amount, 'date': dayKey(date)});
  }

  // ---------- Totals & reports ----------

  /// Wallet = total payments - total menu expenses - total other expenses.
  Future<double> getWalletBalance() async {
    final d = await _database;
    final payments = await d.rawQuery('SELECT COALESCE(SUM(amount),0) AS s FROM payments');
    final expenses = await d.rawQuery('SELECT COALESCE(SUM(total),0) AS s FROM expenses');
    final other =
        await d.rawQuery('SELECT COALESCE(SUM(amount),0) AS s FROM other_expenses');
    final p = (payments.first['s'] as num?)?.toDouble() ?? 0;
    final e = (expenses.first['s'] as num?)?.toDouble() ?? 0;
    final o = (other.first['s'] as num?)?.toDouble() ?? 0;
    return p - e - o;
  }

  Future<double> getDayTotal(DateTime day) async {
    final rows = await (await _database).rawQuery('''
      SELECT (SELECT COALESCE(SUM(total),0) FROM expenses WHERE date = ?) +
             (SELECT COALESCE(SUM(amount),0) FROM other_expenses WHERE date = ?) AS s
    ''', [dayKey(day), dayKey(day)]);
    return (rows.first['s'] as num?)?.toDouble() ?? 0;
  }

  /// Where the month is heading: collected vs spent, and the month-end
  /// projection if spending simply continues at the current average.
  Future<MonthOutlook> getMonthOutlook(DateTime month) async {
    final d = await _database;
    final key = monthKey(month);
    final first = DateTime(month.year, month.month, 1);
    final last = DateTime(month.year, month.month + 1, 0);
    final daysInMonth = last.day;
    final today = DateTime.now();

    final isCurrent = today.year == month.year && today.month == month.month;
    final isPast = !isCurrent &&
        (today.year > month.year ||
            (today.year == month.year && today.month > month.month));
    final daysElapsed = isCurrent ? today.day : (isPast ? daysInMonth : 0);
    final daysRemaining = daysInMonth - daysElapsed;

    // Collection is worked out PER MEMBER and floored at zero, so an
    // overpayment by one person never reduces what the others still owe.
    const collectionSql = '''
      SELECT COALESCE(SUM(due), 0) AS target,
             COALESCE(SUM(paid), 0) AS collected,
             COALESCE(SUM(CASE WHEN due > paid THEN due - paid ELSE 0 END), 0)
               AS still_due,
             COALESCE(SUM(CASE WHEN paid > due THEN paid - due ELSE 0 END), 0)
               AS credit
      FROM (
        SELECT c.amount_due AS due,
               COALESCE((SELECT SUM(p.amount) FROM payments p
                         WHERE p.collection_id = c.id), 0) AS paid
        FROM collections c
        WHERE c.month = ?
      )
    ''';
    final collectionRows = await d.rawQuery(collectionSql, [key]);
    final cr = collectionRows.first;
    final spentRows = await d.rawQuery('''
      SELECT (SELECT COALESCE(SUM(total),0) FROM expenses WHERE date BETWEEN ? AND ?) +
             (SELECT COALESCE(SUM(amount),0) FROM other_expenses WHERE date BETWEEN ? AND ?) AS s
    ''', [dayKey(first), dayKey(last), dayKey(first), dayKey(last)]);
    final memberRows =
        await d.rawQuery('SELECT COUNT(*) AS c FROM members');

    // Allowance that is set but not yet spent still has to be paid out.
    final spentByCat = await d.rawQuery('''
      SELECT COALESCE(SUM(o.amount),0) AS s FROM other_expenses o
      WHERE o.category IN (SELECT name FROM other_categories WHERE monthly_budget > 0)
        AND o.date BETWEEN ? AND ?
''', [dayKey(first), dayKey(last)]);
    final allowanceRows = await d.rawQuery(
        'SELECT COALESCE(SUM(monthly_budget),0) AS s FROM other_categories WHERE monthly_budget > 0');

    final allowance = (allowanceRows.first['s'] as num?)?.toDouble() ?? 0.0;
    final used = (spentByCat.first['s'] as num?)?.toDouble() ?? 0.0;
    final committed = allowance > used ? allowance - used : 0.0;

    // The run-rate is measured across everything. Other expenses are added once
    // via their allowance, so a single large payment cannot skew the average
    // for the rest of the month.
    final foodRows = await d.rawQuery(
        'SELECT COALESCE(SUM(total),0) AS s FROM expenses WHERE date BETWEEN ? AND ?',
        [dayKey(first), dayKey(last)]);
    final otherRows = await d.rawQuery(
        'SELECT COALESCE(SUM(amount),0) AS s FROM other_expenses WHERE date BETWEEN ? AND ?',
        [dayKey(first), dayKey(last)]);

    return MonthOutlook(
      month: month,
      target: (cr['target'] as num?)?.toDouble() ?? 0.0,
      collected: (cr['collected'] as num?)?.toDouble() ?? 0.0,
      stillDue: (cr['still_due'] as num?)?.toDouble() ?? 0.0,
      credit: (cr['credit'] as num?)?.toDouble() ?? 0.0,
      spent: (spentRows.first['s'] as num?)?.toDouble() ?? 0.0,
      foodSpent: (foodRows.first['s'] as num?)?.toDouble() ?? 0.0,
      otherSpent: (otherRows.first['s'] as num?)?.toDouble() ?? 0.0,
      daysElapsed: daysElapsed,
      daysRemaining: daysRemaining,
      daysInMonth: daysInMonth,
      memberCount: (memberRows.first['c'] as num?)?.toInt() ?? 0,
      committed: committed,
      expectedOther: allowance,
    );
  }

  Future<double> getTotalCollected({DateTime? from, DateTime? to}) async {
    final d = await _database;
    final w = StringBuffer('1=1');
    final args = <Object?>[];
    if (from != null) {
      w.write(' AND date >= ?');
      args.add(dayKey(from));
    }
    if (to != null) {
      w.write(' AND date <= ?');
      args.add(dayKey(to));
    }
    final rows = await d.rawQuery(
        'SELECT COALESCE(SUM(amount),0) AS s FROM payments WHERE $w', args);
    return (rows.first['s'] as num?)?.toDouble() ?? 0;
  }

  /// Daily totals over a range: date -> total (menu + other).
  Future<List<Map<String, Object?>>> getDailyTotals(DateTime from, DateTime to) async {
    return (await _database).rawQuery('''
      SELECT date, SUM(s) AS total FROM (
        SELECT date, total AS s FROM expenses WHERE date BETWEEN ? AND ?
        UNION ALL
        SELECT date, amount AS s FROM other_expenses WHERE date BETWEEN ? AND ?
      ) GROUP BY date ORDER BY date DESC
    ''', [dayKey(from), dayKey(to), dayKey(from), dayKey(to)]);
  }

  /// Daily totals split into menu food and other expenses.
///
/// Kept apart on purpose: a single rent payment would otherwise dwarf a whole
/// month of food and make the daily pattern impossible to read.
Future<List<Map<String, Object?>>> getDailySplit(DateTime from, DateTime to) async {
  return (await _database).rawQuery('''
    SELECT date, SUM(food) AS food, SUM(other) AS other FROM (
      SELECT date, total AS food, 0 AS other
        FROM expenses WHERE date BETWEEN ? AND ?
      UNION ALL
      SELECT date, 0 AS food, amount AS other
        FROM other_expenses WHERE date BETWEEN ? AND ?
    ) GROUP BY date ORDER BY date ASC
  ''', [dayKey(from), dayKey(to), dayKey(from), dayKey(to)]);
}

  /// Menu-wise totals over a range.
  Future<List<Map<String, Object?>>> getMenuWiseTotals(DateTime from, DateTime to) async {
    return (await _database).rawQuery('''
      SELECT m.name AS name, COALESCE(SUM(e.total),0) AS total
      FROM expenses e JOIN menus m ON m.id = e.menu_id
      WHERE e.date BETWEEN ? AND ?
      GROUP BY m.id ORDER BY total DESC
    ''', [dayKey(from), dayKey(to)]);
  }

  /// Item-wise totals over a range.
  Future<List<Map<String, Object?>>> getItemWiseTotals(DateTime from, DateTime to) async {
    return (await _database).rawQuery('''
      SELECT i.item_name AS name, COALESCE(SUM(i.quantity * i.price),0) AS total
      FROM expense_items i JOIN expenses e ON e.id = i.expense_id
      WHERE e.date BETWEEN ? AND ?
      GROUP BY i.item_name ORDER BY total DESC
    ''', [dayKey(from), dayKey(to)]);
  }

  // ---------- Settings ----------

  Future<AppSettings> getSettings() async {
    final db = await _database;
    var rows = await db.query('settings', where: 'id = 1');
    if (rows.isEmpty) {
      // Self-heal: "Clear all data" removes this row, and without it every
      // write below would silently do nothing.
      await db.insert('settings', {'id': 1},
          conflictAlgorithm: ConflictAlgorithm.ignore);
      rows = await db.query('settings', where: 'id = 1');
    }
    return AppSettings.fromMap(rows.first);
  }

  /// Upsert, never a bare UPDATE: an UPDATE against a missing row matches zero
  /// rows and reports success, so the setting would appear to save and then
  /// revert to its default on the next launch.
  Future<void> updateSettings(AppSettings settings) async {
    await (await _database).insert(
      'settings',
      {'id': 1, ...settings.toMap()},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Wipes ALL data (including default seed data) for testing.
  Future<void> clearAllData() async {
    final d = await _database;
    await d.delete('expense_items');
    await d.delete('expenses');
    await d.delete('payments');
    await d.delete('collections');
    await d.delete('other_expenses');
    await d.delete('other_categories');
    await d.delete('menu_items');
    await d.delete('menus');
    await d.delete('members');
    await d.delete('settings');
    await d.delete('rotation');
    await _writeRotation(
      date: _dateOnly(DateTime.now()),
      index: 0,
      order: '',
      manual: false,
    );
  }
}
