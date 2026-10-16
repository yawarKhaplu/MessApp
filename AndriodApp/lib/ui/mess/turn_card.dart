import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers.dart';
import '../../services/mess_cloud_service.dart';
import '../theme.dart';
import '../widgets/app_widgets.dart';

/// Whose turn it is to cook.
///
/// Everyone in the mess sees this, and they all see the same thing: the
/// schedule is derived from the mess document rather than stored per person, so
/// there is nothing to keep in sync. Only the owner can change the anchor.
class TurnCard extends ConsumerWidget {
  const TurnCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final turn = ref.watch(messTurnProvider);
    final mess = ref.watch(activeMessProvider).valueOrNull;
    if (mess == null) return const SizedBox.shrink();

    if (!turn.hasMembers) {
      return AppCard(
        padding: const EdgeInsets.all(18),
        child: Text(
          'Nobody is in this mess yet, so there is no turn to show.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      );
    }

    final today = turn.today!;

    return AppCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.restaurant_menu, size: 18, color: AppTheme.primary),
              const SizedBox(width: 8),
              Text('Cooking turn',
                  style: Theme.of(context).textTheme.titleSmall),
              const Spacer(),
              if (mess.isOwner)
                TextButton(
                  onPressed: () => _pickAnchor(context, ref, mess, turn),
                  child: const Text('Change'),
                ),
            ],
          ),
          const SizedBox(height: 14),

          // Whose turn today. Highlighted when it is the signed-in person, so
          // they know at a glance that today is theirs.
          Row(
            children: [
              CircleAvatar(
                radius: 21,
                backgroundColor: (turn.isToday(_me(ref) ?? today)
                        ? AppTheme.primary
                        : AppTheme.secondary)
                    .withOpacity(0.15),
                child: Text(
                  (today.name ?? today.email).isNotEmpty
                      ? (today.name ?? today.email)[0].toUpperCase()
                      : '?',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: turn.isToday(_me(ref) ?? today)
                        ? AppTheme.primary
                        : AppTheme.secondary,
                  ),
                ),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      turn.isToday(_me(ref) ?? today)
                          ? 'Today is your turn'
                          : 'Today: ${today.name ?? today.email}',
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Position ${turn.positionInRound} of ${turn.roundLength}'
                      '${turn.next == null ? '' : ' · next: ${turn.next!.name ?? turn.next!.email}'}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ],
          ),

          if (!turn.isManual) ...[
            const SizedBox(height: 10),
            Text(
              'Following the mess order. The owner can set a bari by hand.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],

          const SizedBox(height: 16),
          const Divider(height: 1),
          const SizedBox(height: 12),

          Text('Coming up',
              style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          // Only the days that matter. A full week is noise on a phone.
          for (final entry in turn.upcoming.take(4))
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: [
                  SizedBox(
                    width: 74,
                    child: Text(
                      entry.date == turn.upcoming.first.date
                          ? 'Today'
                          : _dayLabel(entry.date),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      entry.member.name ?? entry.member.email,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  /// The signed-in person as a roster entry, for the "is this you" highlight.
  MessMember? _me(WidgetRef ref) {
    final email = ref.watch(currentUserProvider).valueOrNull?.email;
    if (email == null) return null;
    final lower = email.toLowerCase();
    for (final m in ref.watch(messMembersProvider)) {
      if (m.email.toLowerCase() == lower) return m;
    }
    return null;
  }

  static String _dayLabel(DateTime d) {
    const names = [
      'Monday', 'Tuesday', 'Wednesday', 'Thursday',
      'Friday', 'Saturday', 'Sunday',
    ];
    return names[d.weekday - 1];
  }

  /// Owner-only: choose who has the bari from today.
  ///
  /// Setting the anchor to today with a chosen person means the cycle is
  /// recomputed from that point, so nobody has to walk through the schedule
  /// telling people where to start.
  Future<void> _pickAnchor(
    BuildContext context,
    WidgetRef ref,
    Mess mess,
    MessTurn turn,
  ) async {
    final chosen = await showModalBottomSheet<MessMember>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(0, 0, 0, 12),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 0, 22, 8),
              child: Text('Who has the bari today?',
                  style: Theme.of(ctx).textTheme.titleLarge),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 0, 22, 12),
              child: Text(
                'They cook today, then the turn moves on to the next person in '
                'the order.',
                style: Theme.of(ctx).textTheme.bodySmall,
              ),
            ),
            for (final m in turn.order)
              ListTile(
                leading: CircleAvatar(
                  child: Text(
                    (m.displayName).isNotEmpty
                        ? (m.displayName)[0].toUpperCase()
                        : '?',
                  ),
                ),
                title: Text(m.displayName),
                subtitle: m.hasSignedIn ? null : const Text('Not signed in yet'),
                onTap: () => Navigator.pop(ctx, m),
              ),
          ],
        ),
      ),
    );
    if (chosen == null || !context.mounted) return;

    try {
      await ref.read(messCloudServiceProvider).setTurn(
            messId: mess.id,
            anchorDate: DateTime.now(),
            anchorEmail: chosen.email,
            order: turn.order.map((m) => m.email).toList(),
          );
      // The anchor is stored on the mess document, so re-read it.
      ref.invalidate(activeMessProvider);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${chosen.name ?? chosen.email} has the bari today.'),
        ),
      );
    } on CloudMessage catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.text)),
      );
    }
  }
}