import 'package:flutter/material.dart';

import '../../data/models.dart';
import '../theme.dart';
import 'app_widgets.dart';

/// Returned when the user deliberately picks "nobody", as opposed to simply
/// dismissing the sheet.
const Object kUnassignedMember = _UnassignedMember();

class _UnassignedMember {
  const _UnassignedMember();
}

/// Shows a rich member picker as a bottom sheet.
///
/// [members] should be in cooking-rotation order so the sheet can say how soon
/// each person is due, and [turnIndex] is the position currently on turn (or
/// null when there is no rotation).
///
/// Returns a [Member], [kUnassignedMember], or null if the sheet was dismissed.
Future<Object?> showMemberPickerSheet(
  BuildContext context, {
  required List<Member> members,
  Member? current,
  int? turnIndex,
  bool allowUnassigned = true,
  String title = 'Who is cooking / paying?',
  String subtitle = 'Pick who cooked today',
}) {
  return showModalBottomSheet<Object>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: AppTheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (ctx) {
      final n = members.length;
      return DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        minChildSize: 0.35,
        maxChildSize: 0.9,
        builder: (ctx, scroll) => ListView(
          controller: scroll,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
          children: [
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [AppTheme.accent, Color(0xFFEF6C00)],
                    ),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(Icons.restaurant,
                      color: Colors.white, size: 22),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: Theme.of(ctx).textTheme.titleLarge),
                      const SizedBox(height: 2),
                      Text(subtitle,
                          style: Theme.of(ctx).textTheme.bodySmall),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            for (int i = 0; i < members.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _MemberTile(
                  member: members[i],
                  selected: current?.id == members[i].id,
                  onTurn: turnIndex != null && turnIndex == i,
                  dueIn: turnIndex == null ? null : _daysUntil(i, turnIndex, n),
                  onTap: () => Navigator.pop(ctx, members[i]),
                ),
              ),
            if (allowUnassigned) ...[
              const SizedBox(height: 6),
              Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => Navigator.pop(ctx, kUnassignedMember),
                  borderRadius: BorderRadius.circular(18),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 14),
                    decoration: BoxDecoration(
                      color: current == null
                          ? AppTheme.textSecondary.withOpacity(0.08)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: current == null
                            ? AppTheme.textSecondary.withOpacity(0.4)
                            : AppTheme.divider,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          current == null
                              ? Icons.person_off
                              : Icons.person_off_outlined,
                          size: 22,
                          color: AppTheme.textSecondary,
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Text(
                            'Nobody / unassigned',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                              color: current == null
                                  ? AppTheme.textSecondary
                                  : AppTheme.textPrimary,
                            ),
                          ),
                        ),
                        if (current == null)
                          const Icon(Icons.check_circle,
                              size: 19, color: AppTheme.textSecondary),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      );
    },
  );
}

/// How many days until this member is due, wrapping around the cycle.
int? _daysUntil(int index, int turnIndex, int length) {
  if (length <= 0) return null;
  var diff = index - turnIndex;
  if (diff < 0) diff += length;
  return diff;
}

/// One member row: avatar, name, rotation status and when they are due.
class _MemberTile extends StatelessWidget {
  final Member member;
  final bool selected;
  final bool onTurn;
  final int? dueIn;
  final VoidCallback onTap;

  const _MemberTile({
    required this.member,
    required this.selected,
    required this.onTurn,
    required this.dueIn,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final initial =
        member.name.trim().isEmpty ? '?' : member.name.trim()[0].toUpperCase();

    String? sub;
    if (onTurn) {
      sub = "On turn today";
    } else if (dueIn != null) {
      sub = dueIn == 1 ? 'Cooks tomorrow' : 'Cooks in $dueIn days';
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: selected
                ? AppTheme.primary.withOpacity(0.09)
                : Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: selected
                  ? AppTheme.primary.withOpacity(0.45)
                  : AppTheme.divider,
              width: selected ? 1.6 : 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: onTurn
                        ? [AppTheme.secondary, const Color(0xFF00695C)]
                        : [AppTheme.primary, AppTheme.primaryDark],
                  ),
                  shape: BoxShape.circle,
                ),
                child: Text(
                  initial,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 18,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            member.name,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                            ),
                          ),
                        ),
                        if (onTurn) ...[
                          const SizedBox(width: 8),
                          const AppBadge(
                            label: 'ON TURN',
                            color: AppTheme.secondary,
                            icon: Icons.bolt,
                          ),
                        ],
                      ],
                    ),
                    if (sub != null) ...[
                      const SizedBox(height: 3),
                      Text(
                        sub,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight:
                              onTurn ? FontWeight.w700 : FontWeight.w500,
                          color: onTurn
                              ? AppTheme.secondary
                              : AppTheme.textSecondary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (selected)
                const Icon(Icons.check_circle,
                    size: 20, color: AppTheme.primary),
            ],
          ),
        ),
      ),
    );
  }
}