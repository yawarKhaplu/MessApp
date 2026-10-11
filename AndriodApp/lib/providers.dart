import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'data/models.dart';
import 'data/repository.dart';
import 'services/notifications.dart';

// ---------- Singletons ----------

final repositoryProvider = Provider<MessRepository>((ref) => MessRepository());

final notificationServiceProvider =
    Provider<NotificationService>((ref) => NotificationService.instance);

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

class MenusNotifier extends AsyncNotifier<List<Menu>> {
  @override
  Future<List<Menu>> build() => ref.read(repositoryProvider).getMenus();

  Future<void> add(String name) async {
    await ref.read(repositoryProvider).addMenu(name);
    state = AsyncData(await ref.read(repositoryProvider).getMenus());
  }

  Future<void> rename(int id, String name) async {
    await ref.read(repositoryProvider).renameMenu(id, name);
    state = AsyncData(await ref.read(repositoryProvider).getMenus());
  }

  Future<void> delete(int id) async {
    await ref.read(repositoryProvider).deleteMenu(id);
    state = AsyncData(await ref.read(repositoryProvider).getMenus());
  }
}

final menusProvider =
    AsyncNotifierProvider<MenusNotifier, List<Menu>>(MenusNotifier.new);

/// Item count per menu, so the menu list can show what each one contains.
final menuItemCountsProvider =
    FutureProvider.autoDispose<Map<int, int>>((ref) async {
  ref.watch(dataVersionProvider);
  ref.watch(menusProvider);
  return ref.read(repositoryProvider).getMenuItemCounts();
});

// ---------- Members ----------

class MembersNotifier extends AsyncNotifier<List<Member>> {
  @override
  Future<List<Member>> build() => ref.read(repositoryProvider).getMembers();

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
