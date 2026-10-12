import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'data/models.dart';
import 'data/repository.dart';
import 'services/auth_service.dart';
import 'services/collection_cloud_service.dart';
import 'services/expense_cloud_service.dart';
import 'services/mess_cloud_service.dart';
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

  if (mess.isOwner) return true;

  final email = ref.watch(currentUserProvider).valueOrNull?.email;
  if (email == null || email.trim().isEmpty) return false;

  return mess.turn.isTodayFor(email);
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
  final month = monthKey(DateTime.now());
  return ref.watch(sharedExpensesProvider(month)).valueOrNull ??
      const <CloudExpense>[];
});

/// Today's spending, for the budget figures on Home.
final todayExpenseTotalProvider = Provider<double>((ref) {
  final today = monthKey(DateTime.now());
  final all = ref.watch(sharedExpensesProvider(monthKey(DateTime.now())))
      .valueOrNull ??
      const <CloudExpense>[];
  return totalBetween(all, today, today).total;
});

/// Records a meal. Owner, or the member whose turn it is.
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
  return id;
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

/// Wallet balance. Call `refresh()` after any money movement.
final walletProvider = StateProvider<double>((ref) => 0.0);

final todayTotalProvider = StateProvider<double>((ref) => 0.0);

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
  final repo = ref.read(repositoryProvider);
  ref.read(walletProvider.notifier).state = await repo.getWalletBalance();
  ref.read(todayTotalProvider.notifier).state =
      await repo.getDayTotal(DateTime.now());
  ref.read(rotationTickProvider.notifier).state++;
  ref.read(dataVersionProvider.notifier).state++;

  ref.invalidate(dailyTotalsProvider);
  ref.invalidate(menuWiseProvider);
  ref.invalidate(itemWiseProvider);
  ref.invalidate(monthCollectionsProvider);
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

final dailyTotalsProvider = FutureProvider.autoDispose<
    List<Map<String, Object?>>>((ref) async {
  final range = ref.watch(reportRangeProvider);
  return ref
      .read(repositoryProvider)
      .getDailyTotals(range.from, range.to);
});

final menuWiseProvider = FutureProvider.autoDispose<
    List<Map<String, Object?>>>((ref) async {
  final range = ref.watch(reportRangeProvider);
  return ref
      .read(repositoryProvider)
      .getMenuWiseTotals(range.from, range.to);
});

final itemWiseProvider = FutureProvider.autoDispose<
    List<Map<String, Object?>>>((ref) async {
  final range = ref.watch(reportRangeProvider);
  return ref
      .read(repositoryProvider)
      .getItemWiseTotals(range.from, range.to);
});
