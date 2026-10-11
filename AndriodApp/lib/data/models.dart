// Data models for MessApp (PRD section 7).

class Menu {
  final int? id;
  final String name;
  final bool isDefault;

  const Menu({this.id, required this.name, this.isDefault = false});

  Map<String, Object?> toMap() =>
      {'id': id, 'name': name, 'is_default': isDefault ? 1 : 0};

  factory Menu.fromMap(Map<String, Object?> m) => Menu(
        id: m['id'] as int?,
        name: m['name'] as String,
        isDefault: (m['is_default'] as int? ?? 0) == 1,
      );
}

class MenuItem {
  final int? id;
  final int menuId;
  final String name;
  final double defaultPrice;

  const MenuItem({
    this.id,
    required this.menuId,
    required this.name,
    this.defaultPrice = 0,
  });

  Map<String, Object?> toMap() =>
      {'id': id, 'menu_id': menuId, 'name': name, 'default_price': defaultPrice};

  factory MenuItem.fromMap(Map<String, Object?> m) => MenuItem(
        id: m['id'] as int?,
        menuId: m['menu_id'] as int,
        name: m['name'] as String,
        defaultPrice: (m['default_price'] as num?)?.toDouble() ?? 0,
      );
}

class Expense {
  final int? id;
  final DateTime date;
  final int? menuId;
  final int? memberId;
  final double total;

  const Expense({
    this.id,
    required this.date,
    this.menuId,
    this.memberId,
    this.total = 0,
  });

  Map<String, Object?> toMap() => {
        'id': id,
        'date': _dateToIso(date),
        'menu_id': menuId,
        'member_id': memberId,
        'total': total,
      };

  factory Expense.fromMap(Map<String, Object?> m) => Expense(
        id: m['id'] as int?,
        date: DateTime.parse(m['date'] as String),
        menuId: m['menu_id'] as int?,
        memberId: m['member_id'] as int?,
        total: (m['total'] as num?)?.toDouble() ?? 0,
      );

  static String _dateToIso(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

class ExpenseItem {
  final int? id;
  final int expenseId;
  final String itemName;
  final double quantity;
  final double price;

  const ExpenseItem({
    this.id,
    required this.expenseId,
    required this.itemName,
    this.quantity = 1,
    this.price = 0,
  });

  Map<String, Object?> toMap() => {
        'id': id,
        'expense_id': expenseId,
        'item_name': itemName,
        'quantity': quantity,
        'price': price,
      };

  factory ExpenseItem.fromMap(Map<String, Object?> m) => ExpenseItem(
        id: m['id'] as int?,
        expenseId: m['expense_id'] as int,
        itemName: m['item_name'] as String,
        quantity: (m['quantity'] as num?)?.toDouble() ?? 1,
        price: (m['price'] as num?)?.toDouble() ?? 0,
      );

  double get lineTotal => quantity * price;
}

class Member {
  final int? id;
  final String name;

  const Member({this.id, required this.name});

  Map<String, Object?> toMap() => {'id': id, 'name': name};

  factory Member.fromMap(Map<String, Object?> m) =>
      Member(id: m['id'] as int?, name: m['name'] as String);
}

/// One member's monthly share for a given month (yyyy-MM).
class Collection {
  final int? id;
  final int memberId;
  final String month;
  final double amountDue;

  const Collection({
    this.id,
    required this.memberId,
    required this.month,
    this.amountDue = 0,
  });

  Map<String, Object?> toMap() =>
      {'id': id, 'member_id': memberId, 'month': month, 'amount_due': amountDue};

  factory Collection.fromMap(Map<String, Object?> m) => Collection(
        id: m['id'] as int?,
        memberId: m['member_id'] as int,
        month: m['month'] as String,
        amountDue: (m['amount_due'] as num?)?.toDouble() ?? 0,
      );
}

class Payment {
  final int? id;
  final int collectionId;
  final double amount;
  final DateTime date;

  const Payment({
    this.id,
    required this.collectionId,
    required this.amount,
    required this.date,
  });

  Map<String, Object?> toMap() => {
        'id': id,
        'collection_id': collectionId,
        'amount': amount,
        'date': Expense._dateToIso(date),
      };

  factory Payment.fromMap(Map<String, Object?> m) => Payment(
        id: m['id'] as int?,
        collectionId: m['collection_id'] as int,
        amount: (m['amount'] as num?)?.toDouble() ?? 0,
        date: DateTime.parse(m['date'] as String),
      );
}

class OtherExpense {
  final int? id;
  final DateTime date;
  final String category;
  final double amount;

  const OtherExpense({
    this.id,
    required this.date,
    required this.category,
    required this.amount,
  });

  Map<String, Object?> toMap() => {
        'id': id,
        'date': Expense._dateToIso(date),
        'category': category,
        'amount': amount,
      };

  factory OtherExpense.fromMap(Map<String, Object?> m) => OtherExpense(
        id: m['id'] as int?,
        date: DateTime.parse(m['date'] as String),
        category: m['category'] as String,
        amount: (m['amount'] as num?)?.toDouble() ?? 0,
      );
}

class AppSettings {
  final String reminderTime; // "HH:mm", 24-hour
  final bool reminderEnabled;
  final String currency;
  final double dailyBudget; // 0 = auto-derive from monthly share

  const AppSettings({
    this.reminderTime = '21:00',
    this.reminderEnabled = true,
    this.currency = 'PKR',
    this.dailyBudget = 0,
  });

  Map<String, Object?> toMap() => {
        'reminder_time': reminderTime,
        'reminder_enabled': reminderEnabled ? 1 : 0,
        'currency': currency,
        'daily_budget': dailyBudget,
      };

  factory AppSettings.fromMap(Map<String, Object?> m) => AppSettings(
        reminderTime: m['reminder_time'] as String? ?? '21:00',
        reminderEnabled: (m['reminder_enabled'] as int? ?? 1) == 1,
        currency: m['currency'] as String? ?? 'PKR',
        dailyBudget: (m['daily_budget'] as num?)?.toDouble() ?? 0,
      );

  AppSettings copyWith({
    String? reminderTime,
    bool? reminderEnabled,
    String? currency,
    double? dailyBudget,
  }) {
    return AppSettings(
      reminderTime: reminderTime ?? this.reminderTime,
      reminderEnabled: reminderEnabled ?? this.reminderEnabled,
      currency: currency ?? this.currency,
      dailyBudget: dailyBudget ?? this.dailyBudget,
    );
  }
}

/// Cooking-duty rotation.
///
/// The cycle is anchored to a real date + member (set from Settings), not to
/// calendar maths. From that anchor the turn simply advances one member per
/// day, so with N members each person cooks once and then comes back around
/// after the other N-1 members have taken their turn.
class CookRotation {
  /// All members, in rotation order.
  final List<Member> members;

  /// Whose turn it is on the requested day (null when there are no members).
  final Member? cook;

  /// Who cooks the following day.
  final Member? next;

  /// 1-based position of [cook] inside the current round.
  final int positionInRound;

  /// Number of members — how many days one full round takes.
  final int roundLength;

  /// The day the rotation was anchored on.
  final DateTime? anchorDate;

  /// Today plus the coming days, so the schedule can be previewed.
  final List<CookTurn> upcoming;

  /// True while the cycle is following real cooking history rather than a
  /// bari the user picked by hand.
  final bool followsHistory;

  /// Who actually cooked today, when an entry says so.
  final RecordedCook? recordedCook;

  const CookRotation({
    required this.members,
    required this.cook,
    required this.next,
    required this.positionInRound,
    required this.roundLength,
    required this.anchorDate,
    required this.upcoming,
    this.followsHistory = false,
    this.recordedCook,
  });

  const CookRotation.empty()
      : members = const [],
        cook = null,
        next = null,
        positionInRound = 0,
        roundLength = 0,
        anchorDate = null,
        upcoming = const [],
        followsHistory = false,
        recordedCook = null;

  /// True when somebody cooked today but it was not the planned cook.
  bool get recordedDiffersFromPlan {
    final r = recordedCook;
    return r != null && cook != null && r.member.id != cook!.id;
  }

  bool get hasMembers => members.isNotEmpty;

  /// The turn is only certain once every member is registered — then nobody
  /// can be skipped and the schedule is fully decided.
  bool get turnsAreSure => hasMembers;

  /// True when today starts a brand new round — everybody has now cooked and
  /// the cycle begins again.
  bool get roundJustCompleted => hasMembers && positionInRound == 1;

  /// How many days until [cook] gets the bari again: today is theirs, the
  /// other members take the days in between, so it comes back after
  /// roundLength - 1 further days.
  int get daysUntilNextTurn => roundLength - 1;
}

/// Who actually cooked on a day, read from saved expenses.
class RecordedCook {
  final DateTime date;
  final Member member;

  const RecordedCook(this.date, this.member);
}

/// One day of the cooking schedule.
class CookTurn {
  final DateTime date;
  final Member member;

  const CookTurn(this.date, this.member);
}

/// A recurring cost with a monthly allowance — rent, gas refill, cups.
///
/// Spending is compared against the allowance so the mess knows what is
/// already committed and what headroom is left this month.
class CategoryBudget {
  final String category;

  /// Money allowed per month. Zero means no allowance set.
  final double budget;

  /// Already spent against this category this month.
  final double spent;

  const CategoryBudget(this.category, this.budget, this.spent);

  double get remaining {
    final v = budget - spent;
    return v > 0 ? v : 0;
  }

  /// How much over the allowance, if it has been exceeded.
  double get over {
    final v = spent - budget;
    return v > 0 ? v : 0;
  }

  bool get hasBudget => budget > 0;

  bool get isOver => hasBudget && spent > budget;

  /// Share of the allowance used, 0..1, or null when no allowance is set.
  double? get usedFraction =>
      hasBudget ? (spent / budget).clamp(0.0, 1.0).toDouble() : null;

  /// Allowance still unspent — money still committed to this category even
  /// though it has not been paid out yet.
  double get committed => remaining;
}

/// Month-end forecast.
///
/// Answers the questions that matter mid-month: how much is still to be
/// collected, and if spending simply continues at the current rate, where
/// will the month actually land?
class MonthOutlook {
  final DateTime month;

  /// Total monthly shares set for the month.
  final double target;

  /// Payments received against this month's collections.
  final double collected;

  /// Everything spent this month (menus + other expenses).
  final double spent;

  /// Shares still not paid in, summed per member.
  ///
  /// Deliberately NOT target minus collected: someone paying extra must never
  /// make the app claim the others owe less than they really do.
  final double stillDue;

  /// Money paid in beyond each member's own share, summed per member.
  final double credit;

  final int daysElapsed;
  final int daysRemaining;
  final int daysInMonth;
  final int memberCount;

  /// Allowance set for recurring categories that has not been spent yet.
  /// Rent that is due but unpaid still has to be paid, so it counts towards
  /// the month even though no expense has been entered for it.
  final double committed;

  /// Month-end figure if the usual fixed daily rate is held for every day that
  /// remains. Differs from [projected], which follows the current average rate.
  final double projectedAtFixedRate;

  /// Menu (food) spending this month, kept apart from other expenses.
  final double foodSpent;

  /// Other expenses (gas, electricity, rent, cups) this month.
  final double otherSpent;

  /// Total of the recurring category allowances, i.e. the other expenses
  /// expected this month whether or not they have been paid out yet.
  final double expectedOther;

  const MonthOutlook({
    required this.month,
    required this.target,
    required this.collected,
    required this.spent,
    required this.daysElapsed,
    required this.daysRemaining,
    required this.daysInMonth,
    required this.memberCount,
    this.committed = 0,
    this.projectedAtFixedRate = 0,
    this.foodSpent = 0,
    this.otherSpent = 0,
    this.expectedOther = 0,
    this.stillDue = 0,
    this.credit = 0,
  });

  /// Shares still unpaid. Never negative, never netted against overpayments.
  double get toCollect => stillDue;

  /// Average spend per day so far.
  /// Average daily spend across EVERYTHING (food plus other expenses), which is
  /// what the monthly budget actually covers.
  double get avgPerDay => daysElapsed <= 0 ? 0 : spent / daysElapsed;

  /// What the month costs on the current run-rate.
  double get projectedFromDaily => avgPerDay * daysInMonth;

  /// The month-end figure: total run-rate plus other expenses budgeted but not
  /// paid out yet.
  double get projected => projectedFromDaily + committed;

  /// The everyday rate the mess has settled on: target spread over the month.
  double get fixedPerDay => daysInMonth <= 0 ? 0 : target / daysInMonth;

  /// Under the target, or over it, if that everyday rate is held from here on.
  /// Today's spending is already inside `spent`.
  double get savingAtFixedRate =>
      target - (spent + fixedPerDay * daysRemaining);

  /// Average daily FOOD spend, kept separate so large one-off expenses do not
  /// hide the day-to-day cooking pattern.
  double get avgFoodPerDay =>
      daysElapsed <= 0 ? 0 : foodSpent / daysElapsed;

  /// Other expenses already paid out this month.
  double get otherPaid => otherSpent;

  /// What will be in the fund once everyone has paid their share: the share
  /// target plus anything paid in extra.
  double get availableIfAllPay => collected + stillDue;

  /// Extra money needed BEYOND the monthly shares, because even with every
  /// share collected the projected cost is still higher.
  double get shortfall {
    final v = projected - availableIfAllPay;
    return v > 0 ? v : 0;
  }

  /// The shortfall split evenly between members.
  double get perMemberShortfall =>
      memberCount > 0 ? shortfall / memberCount : 0;

  /// Spare money if spending stays under what will be collected.
  double get surplus {
    final v = availableIfAllPay - projected;
    return v > 0 ? v : 0;
  }

  /// Money actually in hand right now: collected minus spent.
  double get balance => collected - spent;

  /// Of the target, how much is still unspent this month.
  double get budgetLeft {
    final v = target - spent;
    return v > 0 ? v : 0;
  }

  /// What may be spent per day for the rest of the month to land on target.
  double get allowedPerDay => daysRemaining <= 0 ? 0 : budgetLeft / daysRemaining;

  /// Spending already done versus a straight-line pace through the month.
  /// Positive means under pace (good), negative means over.
  double get paceDelta =>
      daysElapsed <= 0 ? 0 : (target / daysInMonth) * daysElapsed - spent;

  bool get hasTarget => target > 0;

  /// True when the current rate will overshoot what has been collected.
  bool get projectedShort => shortfall > 0;

  /// True when spending is running ahead of a straight-line pace.
  bool get overPace => paceDelta < 0;
}

/// Helper to build a yyyy-MM month key.
String monthKey(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}';

/// Helper to build a yyyy-MM-dd day key.
String dayKey(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
