import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../data/models.dart';
import '../providers.dart';
import '../services/mess_cloud_service.dart';
import '../services/notifications.dart';
import '../ui/theme.dart';
import '../ui/widgets/app_widgets.dart';
import 'rotation_order_screen.dart';
import 'auth/auth_screen.dart';
import 'widgets/text_input_dialog.dart';

/// Settings (PRD 6.7): reminder time, reminder toggle, currency, app info.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  Future<void> _pickReminderTime(BuildContext context, WidgetRef ref) async {
    final settings = ref.read(settingsProvider).valueOrNull;
    if (settings == null) return;
    final parts = settings.reminderTime.split(':');
    final initial = TimeOfDay(
      hour: int.tryParse(parts[0]) ?? 21,
      minute: int.tryParse(parts[1]) ?? 0,
    );
    final picked =
        await showTimePicker(context: context, initialTime: initial);
    if (picked == null) return;
    final time =
        '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
    await ref.read(settingsProvider.notifier).updateSettings(
          settings.copyWith(reminderTime: time),
        );
  }

  /// Fires a notification immediately so the user can confirm the channel
  /// and permission work, instead of waiting for the scheduled time.
  Future<void> _sendTest(BuildContext context, WidgetRef ref) async {
    final service = ref.read(notificationServiceProvider);
    final granted = await service.notificationsEnabled() ?? false;
    if (!granted) await service.requestPermission();
    await service.showTestNotification();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content:
            Text('Test notification sent. Check your notification shade.'),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settingsAsync = ref.watch(settingsProvider);
    final money = NumberFormat.currency(symbol: 'PKR ', decimalDigits: 0);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: settingsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (settings) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const SectionHeader(title: 'Account', icon: Icons.person_outline),
            const SizedBox(height: 8),
            const AccountCard(),
            const SizedBox(height: 24),

            const SectionHeader(title: 'Reminder', icon: Icons.notifications_outlined),
            const SizedBox(height: 8),
            AppCard(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: SwitchListTile(
                title: const Text('Daily reminder'),
                subtitle: const Text('Reminds you to add today\'s mess expense'),
                value: settings.reminderEnabled,
                onChanged: (v) => ref
                    .read(settingsProvider.notifier)
                    .updateSettings(settings.copyWith(reminderEnabled: v)),
                secondary: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.notifications_active,
                      color: AppTheme.primary, size: 22),
                ),
              ),
            ),
            const SizedBox(height: 10),
            AppCard(
              onTap: () => _pickReminderTime(context, ref),
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: AppTheme.accent.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.schedule, color: AppTheme.accent, size: 22),
                ),
                title: const Text('Reminder time'),
                subtitle: Text(_formatTime(settings.reminderTime)),
                trailing: const Icon(Icons.chevron_right, size: 20),
              ),
            ),
            const SizedBox(height: 10),
            _PermissionCard(onTest: () => _sendTest(context, ref)),
            const SizedBox(height: 24),

            const SectionHeader(title: 'Preferences', icon: Icons.tune),
            const SizedBox(height: 8),
            AppCard(
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: AppTheme.secondary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.payments_outlined,
                      color: AppTheme.secondary, size: 22),
                ),
                title: const Text('Currency'),
                subtitle: const Text('Used across the app'),
                trailing: Text(
                  settings.currency,
                  style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: AppTheme.secondary),
                ),
              ),
            ),
            const SizedBox(height: 24),

            const SectionHeader(title: 'Budget', icon: Icons.pie_chart_outline),
            const SizedBox(height: 8),
            AppCard(
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.savings_outlined,
                      color: AppTheme.primary, size: 22),
                ),
                title: const Text('Daily budget'),
                subtitle: Text(settings.dailyBudget > 0
                    ? money.format(settings.dailyBudget)
                    : 'Auto: monthly share ÷ days in month'),
                trailing: const Icon(Icons.chevron_right, size: 20),
                onTap: () => _setDailyBudget(context, ref, settings),
              ),
            ),
            const SizedBox(height: 24),

            const SectionHeader(title: 'Cooking rotation', icon: Icons.rotate_right),
            const SizedBox(height: 8),
            const _RotationCard(),
            const SizedBox(height: 10),
            AppCard(
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: AppTheme.secondary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.low_priority,
                      color: AppTheme.secondary, size: 22),
                ),
                title: const Text('Cooking order'),
                subtitle: const Text('Decide who cooks next — drag to reorder'),
                trailing: const Icon(Icons.chevron_right, size: 20),
                onTap: () async {
                  await Navigator.of(context).push(
                    MaterialPageRoute(
                        builder: (_) => const RotationOrderScreen()),
                  );
                  ref.invalidate(rotationProvider);
                },
              ),
            ),
            const SizedBox(height: 24),

            const SectionHeader(title: 'About', icon: Icons.info_outline),
            const SizedBox(height: 8),
            const AppCard(
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.home_rounded, color: AppTheme.primary, size: 28),
                title: Text('MessAppDev'),
                subtitle: Text('Version 1.0.0 · All data stays on this phone'),
              ),
            ),
            const SizedBox(height: 24),

            // Danger zone
            const SectionHeader(title: 'Danger zone', icon: Icons.warning_amber_rounded),
            const SizedBox(height: 8),
            AppCard(
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: AppTheme.error.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.delete_forever, color: AppTheme.error, size: 22),
                ),
                title: const Text('Clear all data'),
                subtitle: const Text('Wipes everything including default menus and categories'),
                trailing: const Icon(Icons.chevron_right, size: 20),
                onTap: () => _confirmClearData(context, ref),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _setDailyBudget(
      BuildContext context, WidgetRef ref, AppSettings settings) async {
    final value = await showDialog<String>(
      context: context,
      builder: (ctx) => TextInputDialog(
        title: 'Daily budget',
        hint: '0 = auto from monthly share',
        initialValue: settings.dailyBudget > 0
            ? settings.dailyBudget.toStringAsFixed(0)
            : '',
        numeric: true,
        confirmLabel: 'Save',
      ),
    );
    if (value == null) return;
    final amount = double.tryParse(value.replaceAll(',', '')) ?? 0;
    await ref
        .read(settingsProvider.notifier)
        .updateSettings(settings.copyWith(dailyBudget: amount));
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(amount > 0
              ? 'Daily budget set to ${amount.toStringAsFixed(0)}'
              : 'Daily budget will be derived automatically'),
        ),
      );
    }
  }

  Future<void> _confirmClearData(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear all data?'),
        content: const Text(
            'This will permanently delete ALL data including menus, expenses, members, payments and settings. This cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Clear everything')),
        ],
      ),
    );
    if (ok != true) return;

    await ref.read(repositoryProvider).clearAllData();

    // Invalidate all providers so the UI refreshes.
    ref.invalidate(menusProvider);
    ref.invalidate(membersProvider);
    ref.invalidate(monthCollectionsProvider);
    ref.invalidate(dailyTotalsProvider);
    ref.invalidate(menuWiseProvider);
    ref.invalidate(itemWiseProvider);
    ref.invalidate(reportRangeProvider);
    await refreshTotals(ref);

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('All data cleared')),
      );
    }
  }

  String _formatTime(String hhmm) {
    final parts = hhmm.split(':');
    final hour = int.tryParse(parts[0]) ?? 0;
    final minute = int.tryParse(parts[1]) ?? 0;
    final period = hour >= 12 ? 'PM' : 'AM';
    final h12 = hour % 12 == 0 ? 12 : hour % 12;
    return '${h12.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')} $period';
  }
}

/// Shows whether notifications are actually allowed, and offers a way to fix
  /// it. A reminder that cannot be delivered looks identical to one that was
  /// never scheduled, so this makes the difference visible.
  class _PermissionCard extends StatefulWidget {
  const _PermissionCard({required this.onTest});

  final VoidCallback onTest;

  @override
  State<_PermissionCard> createState() => _PermissionCardState();
}

class _PermissionCardState extends State<_PermissionCard> {
  bool? _allowed;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _check());
  }

  Future<void> _check() async {
    final allowed =
        await NotificationService.instance.notificationsEnabled();
    if (mounted) setState(() => _allowed = allowed);
  }

  @override
  Widget build(BuildContext context) {
    final allowed = _allowed;
    final blocked = allowed == false;

    return AppCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                blocked
                    ? Icons.notifications_off_outlined
                    : Icons.notifications_active_outlined,
                color: blocked ? AppTheme.error : AppTheme.success,
                size: 20,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  allowed == null
                      ? 'Checking notification access…'
                      : blocked
                          ? 'Notifications are blocked'
                          : 'Notifications are allowed',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            blocked
                ? 'MessAppDev cannot remind you until notifications are turned '
                    'on for this app.'
                : 'The daily reminder will arrive even when MessAppDev is closed.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () async {
                    await NotificationService.instance.requestPermission();
                    await _check();
                  },
                  icon: const Icon(Icons.verified_user_outlined, size: 18),
                  label: Text(blocked ? 'Allow' : 'Re-check'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  onPressed: widget.onTest,
                  icon: const Icon(Icons.send_outlined, size: 18),
                  label: const Text('Test'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Lets the owner control the cooking rotation.
///
/// Reads the shared turn from the mess document rather than the local database,
/// so the schedule is the same for everyone in the mess and only the owner can
/// change it. Members see the schedule without any controls.
class _RotationCard extends ConsumerWidget {
  const _RotationCard();

  Future<void> _pickBari(
      BuildContext context, WidgetRef ref, MessTurn turn) async {
    final mess = ref.read(activeMessProvider).valueOrNull;
    if (mess == null) return;

    final picked = await showDialog<MessMember>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Who has the bari today?'),
        children: [
          for (final m in turn.order)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, m),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    Icon(Icons.person_outline,
                        size: 18, color: AppTheme.primary),
                    const SizedBox(width: 10),
                    Expanded(child: Text(m.name ?? m.email)),
                    if (m.email.toLowerCase() ==
                        turn.today?.email.toLowerCase())
                      const AppBadge(
                        label: 'ON TURN',
                        color: AppTheme.secondary,
                        icon: Icons.bolt,
                      ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
    if (picked == null || !context.mounted) return;

    try {
      await ref.read(messCloudServiceProvider).setTurn(
            messId: mess.id,
            anchorDate: DateTime.now(),
            anchorEmail: picked.email,
            order: turn.order.map((m) => m.email).toList(),
          );
      // The anchor lives on the mess document, so re-read it.
      ref.invalidate(activeMessProvider);
      await refreshTotals(ref);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('${picked.name ?? picked.email} has the bari today')),
      );
    } on CloudMessage catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.text)),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mess = ref.watch(activeMessProvider).valueOrNull;
    final turn = ref.watch(messTurnProvider);

    if (mess == null || !turn.hasMembers || turn.today == null) {
      return const AppCard(
        child: ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(Icons.group_outlined, color: AppTheme.textSecondary),
          title: Text('Cooking rotation'),
          subtitle: Text('Add members to start the cooking rotation'),
        ),
      );
    }

    final who = turn.today!.name ?? turn.today!.email;
    final firstName = who.trim().split(' ').first;
    final again = turn.roundLength - 1;

    return Column(
      children: [
        AppCard(
          onTap: mess.isOwner ? () => _pickBari(context, ref, turn) : null,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [AppTheme.secondary, Color(0xFF00695C)],
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.rotate_right,
                        color: Colors.white, size: 22),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text("Today's bari",
                            style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 2),
                        Text(
                          '$who · turn ${turn.positionInRound} of '
                          '${turn.roundLength}'
                          '${mess.isOwner ? ' · tap to change' : ''}',
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  if (mess.isOwner) const Icon(Icons.chevron_right, size: 20),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                'Everyone cooks once, then it comes back around — '
                '$firstName cooks again in $again '
                '${again == 1 ? 'day' : 'days'}.',
                style: TextStyle(
                  fontSize: 12,
                  color: AppTheme.textSecondary.withOpacity(0.95),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Coming up', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 2),
              Text(
                'Shared with everyone in this mess',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              for (int i = 0; i < turn.upcoming.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 62,
                        child: Text(
                          i == 0
                              ? 'Today'
                              : DateFormat('EEE d MMM')
                                  .format(turn.upcoming[i].date),
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: i == 0
                                ? AppTheme.secondary
                                : AppTheme.textSecondary,
                          ),
                        ),
                      ),
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color:
                              i == 0 ? AppTheme.secondary : AppTheme.divider,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          turn.upcoming[i].member.name ??
                              turn.upcoming[i].member.email,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontWeight:
                                i == 0 ? FontWeight.w800 : FontWeight.w600,
                            color: i == 0
                                ? AppTheme.secondary
                                : AppTheme.textPrimary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
