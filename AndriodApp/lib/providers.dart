import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'data/models.dart';
import 'data/repository.dart';
import 'services/auth_service.dart';
import 'services/collection_cloud_service.dart';
import 'services/expense_cloud_service.dart';
import 'services/mess_cloud_service.dart';
import 'services/other_expense_cloud_service.dart';
import 'services/report_cloud_service.dart';
import 'services/menu_cloud_service.dart';
import 'services/notifications.dart';

// ---------- Singletons ----------

final repositoryProvider = Provider<MessRepository>((ref) => MessRepository());

final notificationServiceProvider =
    Provider<NotificationService>((ref) => NotificationService.instance);

/// Google sign-in. Identity only for now: no expense data leaves the device.
/// Shared data is a separate step, so this establishes WHO, not WHAT.
final authServiceProvider = Provider<AuthService>((ref) => AuthService());

/// Membership layer: which mess this person belongs to and what they may do.
/// Expense data still lives in the local SQLite database.
final messCloudServiceProvider = Provider<MessCloudService>(
  (ref) => MessCloudService(),
);

/// The mess the signed-in person belongs to, or null when they have none.
///
/// A FutureProvider because membership is now a single document read rather than
/// a query. Bumped by [activeMessIdProvider] so a sign-out or a fresh sign-in
/// re-reads it under the new account.
final activeMessProvider = FutureProvider<Mess?>((ref) async {
  ref.watch(activeMessIdProvider);
  ref.watch(currentUserProvider);
  final user = ref.watch(currentUserProvider).valueOrNull;
  if (user == null) return null;
  return ref.watch(messCloudServiceProvider).resolveMess(user.uid);
});

/// Which mess is currently open. Null until one is chosen or created.
///
/// Doubles as a generation counter: setting it forces the membership read above
/// to run again, which is how a sign-out stops showing the last account's mess.
final activeMessIdProvider = StateProvider<String?>((ref) => null);

/// People in the open mess.
///
/// Taken from the mess document itself, so members see everyone rather than an
/// empty list. Named to avoid clashing with the local SQLite membersProvider,
/// which is a different list for a different purpose.
final messMembersProvider = Provider<List<MessMember>>((ref) {
  return ref.watch(activeMessProvider).valueOrNull?.members ?? const [];
});

/// Whose turn it is to cook, for everyone in the mess.
///
/// Derived from the roster, so every member computes the same answer from the
/// same document and no one has to be told.
final messTurnProvider = Provider<MessTurn>((ref) {
  return ref.watch(activeMessProvider).valueOrNull?.turn ?? const MessTurn.empty();
});

/// Role of the signed-in person in the open mess, or null when no mess is
/// open yet.
final myRoleProvider = Provider<MessRole?>((ref) {
  final mess = ref.watch(activeMessProvider).valueOrNull;
  if (mess == null) return null;
  return mess.isOwner ? MessRole.owner : MessRole.member;
});

/// Whoever is signed in right now, or null when signed out.
final currentUserProvider = StreamProvider<AppUser?>(
  (ref) => ref.watch(authServiceProvider).authStateChanges,
);

// ---------- Settings ----------

class SettingsNotifier extends AsyncNotifier<AppSettings> {
  @override
  Future<AppSettings> build() async {
    final settings = await ref.read(repositoryProvider).getSettings();
    // Apply the reminder schedule in the background.
    final svc = ref.read(notificationServiceProvider);
    svc.applySettings(
      enabled: settings.reminderEnabled,
      timeHHmm: settings.reminderTime,
    );
    return settings;
  }

  Future<void> updateSettings(AppSettings settings) async {
    await ref.read(repositoryProvider).updateSettings(settings);
    await ref.read(notificationServiceProvider).applySettings(
          enabled: settings.reminderEnabled,
          timeHHmm: settings.reminderTime,
        );
    state = AsyncData(settings);
  }
}

final settingsProvider =
    AsyncNotifierProvider<SettingsNotifier, AppSettings>(SettingsNotifier.new);

// ---------- Menus ----------

/// The shared menu catalogue, read from Firestore.
///
/// Everyone in the mess cooks from the same menus. Menus are edited one at a
/// time and are small, so the whole catalogue is held in memory and rewritten on
/// each change rather than read item by item.
class MenusNotifier extends AsyncNotifier<MenuCatalogue> {
  MessCloudService get _cloud => ref.read(messCloudServiceProvider);

  /// The open mess. Menus belong to it, so there is nothing to show without one.
  String get _messId =>
      ref.read(activeMessProvider).valueOrNull?.id ?? '';

  @override
  Future<MenuCatalogue> build() async {
    final mess = await ref.watch(activeMessProvider.future);
    if (mess == null) return const MenuCatalogue.empty();
    return ref.watch(messCloudServiceProvider).menus(mess.id);
  }

  /// Re-reads after a write, so what is on screen is what was actually saved.
  Future<void> _reload() async {
    if (_messId.isEmpty) {
      state = AsyncData(const MenuCatalogue.empty());
      return;
    }
    state = AsyncData(await _cloud.menus(_messId));
  }

  Future<void> add(String name) async {
    await _cloud.addMenu(_messId, name, existing: state.valueOrNull?.menus);
    await _reload();
  }

  Future<void> rename(String menuId, String name) async {
    await _cloud.renameMenu(
        _messId, state.valueOrNull?.menus ?? const [], menuId, name);
    await _reload();
  }

  Future<void> delete(String menuId) async {
    await _cloud.deleteMenu(
        _messId, state.valueOrNull?.menus ?? const [], menuId);
    await _reload();
  }

  Future<void> addItem(String menuId, String name, double price) async {
    await _cloud.addMenuItem(
      _messId,
      state.valueOrNull?.menus ?? const [],
      menuId,
      name: name,
      defaultPrice: price,
    );
    await _reload();
  }

  Future<void> updateItem(String menuId, String itemId, String name,
      double price) async {
    await _cloud.updateMenuItem(
      _messId,
      state.valueOrNull?.menus ?? const [],
      menuId,
      itemId,
      name: name,
      defaultPrice: price,
    );
    await _reload();
  }

  Future<void> deleteItem(String menuId, String itemId) async {
    await _cloud.deleteMenuItem(
        _messId, state.valueOrNull?.menus ?? const [], menuId, itemId);
    await _reload();
  }

  Future<void> reorderItems(String menuId, List<String> itemIds) async {
    await _cloud.reorderMenuItems(
        _messId, state.valueOrNull?.menus ?? const [], menuId, itemIds);
    await _reload();
  }
}

final menusProvider =
    AsyncNotifierProvider<MenusNotifier, MenuCatalogue>(MenusNotifier.new);

/// Item count per menu, derived from the catalogue already in memory.
final menuItemCountsProvider = Provider<Map<String, int>>((ref) {
  return ref.watch(menusProvider).valueOrNull?.itemCounts ?? const {};
});

// ---------- Collections (shared) ----------

/// Monthly collections for every member, read from Firestore.
///
/// Keyed by member email so this lines up with the shared roster. Re-read when
/// the month or the mess changes; anything that writes a payment invalidates it,
/// so both people always see the same figures.
final sharedCollectionsProvider =
    FutureProvider.autoDispose.family<Map<String, MemberCollection>, String>(
        (ref, month) async {
  // Watched so a new member or a removed one is reflected immediately.
  final mess = await ref.watch(activeMessProvider.future);
  if (mess == null) return const {};

  return ref
      .read(messCloudServiceProvider)
      .collectionsFor(mess.id, month, mess.members);
});

/// Who may change collection figures. Read from the membership document, never
/// assumed from the UI.
final canRecordCollectionsProvider = Provider<bool>((ref) {
  return ref.watch(activeMessProvider).valueOrNull?.isOwner ?? false;
});

/// Who may record an expense for today's cook.
///
/// The owner can always record one. Anyone else can only do so on the day the
/// turn says it is theirs, so the person who cooked is the one entering what was
/// cooked, and nobody can quietly log meals on each other's behalf.
///
/// False while the mess is still loading, so the button never flashes into view
/// before the answer is known.
final canRecordTodaysCookProvider = Provider<bool>((ref) {
  final mess = ref.watch(activeMessProvider).valueOrNull;
  if (mess == null) return false;

  return mayRecordExpense(
    mess: mess,
    email: ref.watch(currentUserProvider).valueOrNull?.email,
    cookEmail: mess.turn.today?.email ?? '',
    date: dayKey(DateTime.now()),
  );
});

// ---------- Expenses (shared) ----------

/// Expenses for one month, read from Firestore.
///
/// Invalidated whenever anything is written, so the owner who records a meal and
/// the member reading it see the same figures without pulling to refresh.
final sharedExpensesProvider =
    FutureProvider.autoDispose.family<List<CloudExpense>, String>((ref, month) async {
  final mess = await ref.watch(activeMessProvider.future);
  if (mess == null) return const [];
  return ref.read(messCloudServiceProvider).expenses(mess.id, month);
});

/// Today's entries, newest first.
final todayExpensesProvider = Provider<List<CloudExpense>>((ref) {
  // Read the month the provider partitions on, then keep only today. Returning
  // the whole month here would make every "today" figure in the app a month
  // figure, and the name would be lying about it.
  final today = dayKey(DateTime.now());
  final monthEntries = ref
          .watch(sharedExpensesProvider(monthKey(DateTime.now())))
          .valueOrNull ??
      const <CloudExpense>[];

  return monthEntries.where((e) => e.date == today).toList();
});

/// Today's spending, for the budget figures on Home.
final todayExpenseTotalProvider = Provider<double>((ref) {
  // A day, not a month: comparing against a month key would sum the whole month
  // and report it as today's spending.
  final today = dayKey(DateTime.now());
  final all = ref.watch(sharedExpensesProvider(monthKey(DateTime.now())))
      .valueOrNull ??
      const <CloudExpense>[];
  return totalBetween(all, today, today).total;
});

/// Records a meal. Owner, or the member whose turn it is.
///
/// The turn is checked again here, and not only where the button is hidden.
/// A hidden button is a courtesy: the screen can still be reached by a restored
/// navigation stack, or left open from yesterday with today's date already
/// filled in. Re-checking at the point of writing means the rule holds however
/// the screen was arrived at, instead of only along the path the UI offers.
Future<String> saveExpense({
  required WidgetRef ref,
  required String date,
  required String menuName,
  required String cookEmail,
  required List<CloudExpenseItem> items,
}) async {
  final mess = ref.read(activeMessProvider).valueOrNull;
  if (mess == null) {
    throw const CloudMessage('No mess is open yet.');
  }

  final email = ref.read(currentUserProvider).valueOrNull?.email;

  // Checked at the point of writing, not only where the button is hidden. A
  // hidden button is a courtesy: the screen can still be reached by a restored
  // navigation stack, or left open from yesterday with today's date already
  // filled in. Re-checking here means the rule holds however the screen was
  // arrived at, instead of only along the path the UI offers.
  final refusal = recordRefusal(
    mess: mess,
    email: email,
    cookEmail: cookEmail,
    date: date,
  );
  if (refusal != null) {
    final cook = mess.turn.today?.name;
    throw CloudMessage(switch (refusal) {
      RecordRefusal.notSignedIn => 'Sign in again to record a meal.',
      RecordRefusal.notTheirCook =>
        'You can only record a meal for your own cooking turn.',
      RecordRefusal.notTheirTurn => cook == null
          ? 'It is not your turn today.'
          : 'It is not your turn today — $cook is cooking.',
    });
  }

  final id = await ref.read(messCloudServiceProvider).addExpense(
        messId: mess.id,
        date: date,
        menuName: menuName,
        cookEmail: cookEmail,
        items: items,
        roster: mess.members,
      );

  // Written to a month the entry may not fall in, so both are cleared rather
  // than leaving a stale copy behind on whichever one the app was showing.
  ref.invalidate(sharedExpensesProvider(monthOf(date)));
  ref.invalidate(sharedExpensesProvider(monthKey(DateTime.now())));

  // Reports are read across several tabs at once. Invalidated as a whole rather
  // than per tab, so a figure on one tab cannot contradict the tab beside it.
  ref.invalidate(reportBundleProvider);
  return id;
}

// ---------- Reports ----------

/// Everything the reports read, fetched once and shared by every tab.
///
/// One bundle rather than a question per figure: Firestore cannot be asked for an
/// aggregate under these rules, so the grouping happens in Dart. Every tab works
/// from the same bundle, which is what stops the daily list, the trend and the
/// month forecast disagreeing about the same day.
final reportBundleProvider = FutureProvider.autoDispose<ReportBundle>((ref) async {
  final mess = await ref.watch(activeMessProvider.future);
  if (mess == null) return const ReportBundle.empty();

  return ref.read(messCloudServiceProvider).reportBundle(mess.id);
});

// ---------- Other expenses (shared) ----------

/// Other expenses for one month, read from Firestore.
///
/// Owner-only writes, so every member reads the whole month and the same list is
/// returned for all of them. Invalidated on any write so the owner who records
/// one sees it without pulling to refresh.
final otherExpensesProvider =
    FutureProvider.autoDispose.family<List<CloudOtherExpense>, String>(
        (ref, month) async {
  final mess = await ref.watch(activeMessProvider.future);
  if (mess == null) return const [];
  return ref.read(messCloudServiceProvider).otherExpenses(mess.id, month);
});

/// Other expense categories with their allowances, from the mess document.
final otherCategoriesProvider =
    FutureProvider.autoDispose.family<List<CloudOtherCategory>, String>(
        (ref, messId) async {
  if (messId.isEmpty) return const [];
  return ref.read(messCloudServiceProvider).otherCategories(messId);
});

/// Categories with what has been spent against each one this month.
///
/// The spend is worked out from the entries rather than read from a stored
/// running total, so the figure can never drift away from the records it came
/// from — a category that looks unspent while the entries say otherwise would
/// quietly overstate what is left.
final categoryBudgetsProvider =
    FutureProvider.autoDispose.family<List<CloudCategoryBudget>, DateTime>(
        (ref, month) async {
  final mess = await ref.watch(activeMessProvider.future);
  if (mess == null) return const [];

  final key = monthKey(month);
  final bounds = monthBounds(key);
  final service = ref.read(messCloudServiceProvider);

  final categories = await service.otherCategories(mess.id);
  final expenses = await service.otherExpenses(mess.id, key);

  return [
    for (final c in categories)
      CloudCategoryBudget(
        c,
        spentInCategory(expenses, c.name, bounds.from, bounds.to),
      ),
  ];
});

/// Records or updates an other expense. Owner only.
Future<void> saveOtherExpense({
  required WidgetRef ref,
  required String date,
  required String category,
  required double amount,
  String? note,
  String? title,
  String? id,
}) async {
  final mess = ref.read(activeMessProvider).valueOrNull;
  if (mess == null) throw const CloudMessage('No mess is open yet.');

  // Checked here rather than only where the button is drawn: a hidden button is
  // a courtesy, and this screen can still be reached by a restored navigation
  // stack. The rules refuse the write either way, so this is agreeing with the
  // server rather than substituting for it.
  if (!mess.isOwner) {
    throw const CloudMessage('Only the owner can add other expenses.');
  }

  await ref.read(messCloudServiceProvider).addOtherExpense(
        messId: mess.id,
        date: date,
        category: category,
        amount: amount,
        note: note,
        title: title,
        id: id,
      );

  ref.invalidate(otherExpensesProvider(monthOf(date)));
  ref.invalidate(categoryBudgetsProvider(DateTime.parse(date)));
  ref.invalidate(reportBundleProvider);
  ref.invalidate(activeMessProvider);
}

/// Removes an other expense. Owner only.
Future<void> deleteOtherExpense({
  required WidgetRef ref,
  required String month,
  required String id,
}) async {
  final mess = ref.read(activeMessProvider).valueOrNull;
  if (mess == null) throw const CloudMessage('No mess is open yet.');

  if (!mess.isOwner) {
    throw const CloudMessage('Only the owner can remove other expenses.');
  }

  await ref
      .read(messCloudServiceProvider)
      .deleteOtherExpense(messId: mess.id, month: month, id: id);

  ref.invalidate(otherExpensesProvider(month));
  ref.invalidate(reportBundleProvider);
  ref.invalidate(activeMessProvider);
}

// ---------- Members ----------

class MembersNotifier extends AsyncNotifier<List<Member>> {
  /// Mirrors the shared roster into the local table before reading it.
  ///
  /// Firestore decides who is in the mess. This table holds the money recorded
  /// against each person, so it is synced from the roster on every load instead
  /// of being a second, independent list of names. That is what makes the
  /// Collection tab show the same people as the rest of the app.
  @override
  Future<List<Member>> build() async {
    final repo = ref.read(repositoryProvider);

    final mess = await ref.watch(activeMessProvider.future);
    if (mess == null) return repo.getMembers();

    return repo.syncRoster([
      for (final m in mess.members) (email: m.email, name: m.name),
    ]);
  }

  Future<void> add(String name) async {
    await ref.read(repositoryProvider).addMember(name);
    state = AsyncData(await ref.read(repositoryProvider).getMembers());
  }

  Future<void> rename(int id, String name) async {
    await ref.read(repositoryProvider).renameMember(id, name);
    state = AsyncData(await ref.read(repositoryProvider).getMembers());
  }

  Future<void> delete(int id) async {
    await ref.read(repositoryProvider).deleteMember(id);
    state = AsyncData(await ref.read(repositoryProvider).getMembers());
  }
}

final membersProvider =
    AsyncNotifierProvider<MembersNotifier, List<Member>>(MembersNotifier.new);

// ---------- Wallet & today ----------

/// Today's spending, meals and other expenses together, from Firestore.
///
/// Meals and other expenses are read from different places, so adding them here
/// is what keeps "today's total" meaning the same thing as the daily report.
final todaySpendProvider = Provider<double>((ref) {
  final bundle = ref.watch(reportBundleProvider).valueOrNull;
  if (bundle == null) return 0;
  return bundle.dayTotal(dayKey(DateTime.now()));
});

/// The daily allowance and where today sits against it.
///
/// The fixed rate comes from device settings, which stay local deliberately — a
/// reminder time or a currency is not something the whole mess should see.
final todayBudgetProvider =
    FutureProvider.autoDispose<TodayBudget>((ref) async {
  final bundle =
      await ref.watch(reportBundleProvider.future);
  final settings = await ref.read(repositoryProvider).getSettings();

  return bundle.todayBudget(
    DateTime.now(),
    fixedDailyBudget: settings.dailyBudget,
  );
});

/// Bumped whenever the cooking rotation changes, so Home/Settings rebuild.
final rotationTickProvider = StateProvider<int>((ref) => 0);

/// Bumped after ANY data change. Screens that query the database inside a
/// FutureBuilder watch this so they re-run their query instead of showing a
/// stale list.
final dataVersionProvider = StateProvider<int>((ref) => 0);

/// Today's cooking turn and the days ahead.
final rotationProvider = FutureProvider.autoDispose<CookRotation>((ref) {
  ref.watch(rotationTickProvider);
  ref.watch(membersProvider);
  return ref.read(repositoryProvider).getCookRotation();
});

/// Call after every write: money, totals, rotation and every report refresh.
Future<void> refreshTotals(WidgetRef ref) async {
  ref.read(rotationTickProvider.notifier).state++;
  ref.read(dataVersionProvider.notifier).state++;

  // The bundle is the single source for every money figure now, so refreshing it
  // refreshes the wallet, today's total, the daily allowance and all six report
  // tabs at once. Invalidating them one by one is how two tabs end up showing
  // different numbers for the same day.
  ref.invalidate(reportBundleProvider);
  ref.invalidate(todayBudgetProvider);
  ref.invalidate(dailyTotalsProvider);
  ref.invalidate(monthOutlookProvider);
  ref.invalidate(rotationProvider);
}

// ---------- Collection (monthly) ----------

/// Currently selected month (first day of the month).
final selectedMonthProvider = StateProvider<DateTime>(
    (ref) => DateTime(DateTime.now().year, DateTime.now().month));

final monthCollectionsProvider =
    FutureProvider.autoDispose<List<Map<String, Object?>>>((ref) async {
  final month = ref.watch(selectedMonthProvider);
  final key = monthKey(month);
  return ref.read(repositoryProvider).getMonthCollections(key);
});

// ---------- Reports ----------

/// Report range: [from, to] inclusive.
final reportRangeProvider = StateProvider<({DateTime from, DateTime to})>(
  (ref) {
    final now = DateTime.now();
    return (from: DateTime(now.year, now.month, 1), to: now);
  },
);

final dailyTotalsProvider =
    FutureProvider.autoDispose<List<DayRow>>((ref) async {
  final range = ref.watch(reportRangeProvider);
  final bundle = await ref.watch(reportBundleProvider.future);
  return bundle.dailyTotals(dayKey(range.from), dayKey(range.to));
});

/// The month outlook for a given month, read from the shared bundle.
///
/// Shaped as the existing [MonthOutlook] so the card does not have to be
/// rewritten; the figures behind it now come from Firestore rather than SQLite,
/// which is the part that mattered.
final monthOutlookProvider =
    FutureProvider.autoDispose.family<MonthOutlook, DateTime>((ref, month) async {
  final bundle = await ref.watch(reportBundleProvider.future);
  final f = bundle.monthFigures(monthKey(month), DateTime.now());

  return MonthOutlook(
    // The card holds the month as a DateTime on the first of the month, while the
    // bundle keys it as text. Parsed back so the card needs no rewrite; the month
    // is only ever used as a label and a key here, never as a day.
    month: DateTime.parse('${f.month}-01'),
    target: f.target,
    collected: f.collected,
    spent: f.spent,
    daysElapsed: f.daysElapsed,
    daysRemaining: f.daysRemaining,
    daysInMonth: f.daysInMonth,
    memberCount: f.memberCount,
    committed: f.committed,
    projectedAtFixedRate: f.projectedAtFixedRate,
    foodSpent: f.foodSpent,
    otherSpent: f.otherSpent,
    expectedOther: f.expectedOther,
    stillDue: f.collections.stillDue,
    credit: f.collections.credit,
  );
});

final menuWiseProvider =
    FutureProvider.autoDispose<List<ReportRow>>((ref) async {
  final range = ref.watch(reportRangeProvider);
  final bundle = await ref.watch(reportBundleProvider.future);
  return bundle.byMenu(dayKey(range.from), dayKey(range.to));
});

final itemWiseProvider =
    FutureProvider.autoDispose<List<ReportRow>>((ref) async {
  final range = ref.watch(reportRangeProvider);
  final bundle = await ref.watch(reportBundleProvider.future);
  return bundle.byItem(dayKey(range.from), dayKey(range.to));
});
