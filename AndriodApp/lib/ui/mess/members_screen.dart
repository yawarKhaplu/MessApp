import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers.dart';
import '../../services/mess_cloud_service.dart';
import '../theme.dart';
import '../widgets/app_widgets.dart';
import 'members_dialog.dart';

/// Who is in the mess, and (for the owner) how to let more people in.
class MembersScreen extends ConsumerWidget {
  const MembersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mess = ref.watch(activeMessProvider).valueOrNull;
    if (mess == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Mess')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final isOwner = mess.isOwner;

    return Scaffold(
      appBar: AppBar(title: Text(mess.name)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          MessSummaryCard(mess: mess),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: Text('People in this mess',
                    style: Theme.of(context).textTheme.titleMedium),
              ),
              if (isOwner)
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: () => showAddMemberDialog(context, ref, mess.id),
                  icon: const Icon(Icons.person_add_alt_1, size: 18),
                  label: const Text('Add'),
                ),
            ],
          ),
          const SizedBox(height: 10),
          const MemberListView(),
          const SizedBox(height: 24),
          if (isOwner) JoinCodeCard(code: mess.joinCode),
        ],
      ),
    );
  }
}

/// Name, location and join code for a mess. Public so the member-only screen
/// can show the same summary without duplicating it.
class MessSummaryCard extends StatelessWidget {
  const MessSummaryCard({required this.mess});

  final Mess mess;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: AppTheme.primary.withOpacity(0.1),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(Icons.storefront_outlined,
                color: AppTheme.primary, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(mess.name,
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                if (mess.location != null && mess.location!.isNotEmpty)
                  Text(mess.location!,
                      style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Everyone in the mess. Public so the member-only screen reuses it rather
/// than keeping a second copy that could drift out of step.
class MemberListView extends ConsumerWidget {
  const MemberListView();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // The roster arrives with the mess document itself, so every member sees
    // the full list rather than only the owner.
    final members = ref.watch(messMembersProvider);

    if (members.isEmpty) {
      return AppCard(
        padding: const EdgeInsets.all(20),
        child: Center(
          child: Text(
            'Nobody here yet. The owner can add people by email.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      );
    }

    return AppCard(
      child: Column(
        children: [
          for (var i = 0; i < members.length; i++) ...[
            if (i > 0) const Divider(height: 1),
            _MemberTile(member: members[i]),
          ],
        ],
      ),
    );
  }
}

class _MemberTile extends ConsumerWidget {
  const _MemberTile({required this.member});

  final MessMember member;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mess = ref.watch(activeMessProvider).valueOrNull;
    final isOwnerViewing = mess?.isOwner ?? false;
    // Compared lowercased on both sides: keys are stored normalised, so a
    // capitalised account would otherwise look like a different person and the
    // owner would be offered the option to remove themselves.
    final isSelf = member.email.toLowerCase() ==
        (ref.watch(currentUserProvider).valueOrNull?.email ?? '').toLowerCase();

    final pending = !member.hasSignedIn;

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: CircleAvatar(
        radius: 19,
        backgroundColor: AppTheme.secondary.withOpacity(0.12),
        child: Text(
          (member.name ?? member.email).isNotEmpty
              ? (member.name ?? member.email)[0].toUpperCase()
              : '?',
          style: const TextStyle(
              color: AppTheme.secondary, fontWeight: FontWeight.w600),
        ),
      ),
      title: Text(
        member.name ?? (pending ? 'Not signed in yet' : member.email),
        style: Theme.of(context).textTheme.titleSmall,
      ),
      subtitle: Text(
        member.email,
        style: Theme.of(context).textTheme.bodySmall,
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
            decoration: BoxDecoration(
              color: (member.role == MessRole.owner
                      ? AppTheme.primary
                      : AppTheme.success)
                  .withOpacity(0.12),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              member.role == MessRole.owner ? 'Owner' : 'Member',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: member.role == MessRole.owner
                    ? AppTheme.primary
                    : AppTheme.success,
              ),
            ),
          ),
          if (isOwnerViewing && member.role != MessRole.owner && !isSelf)
            IconButton(
              tooltip: 'Remove',
              icon: const Icon(Icons.close, size: 19),
              color: AppTheme.error,
              onPressed: () => _confirmRemove(context, ref, mess!.id, member),
            ),
        ],
      ),
    );
  }

  Future<void> _confirmRemove(
    BuildContext context,
    WidgetRef ref,
    String messId,
    MessMember member,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove from mess?'),
        content: Text(
          '${member.name ?? member.email} will no longer see this mess. '
          'They can be added again any time.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppTheme.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;

    try {
      final cloud = ref.read(messCloudServiceProvider);
      await cloud.removeMember(messId: messId, email: member.email);
      // The roster is part of the mess document, so re-read it to show the
      // change rather than waiting for a listener that no longer exists.
      ref.invalidate(activeMessProvider);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Removed ${member.name ?? member.email}'),
        ),
      );
    } on CloudMessage catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.text)),
      );
    }
  }
}

/// Join code, shown to the owner only. Public for reuse by the member screen's
/// shared layout.
class JoinCodeCard extends StatelessWidget {
  const JoinCodeCard({required this.code});

  final String code;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.key_outlined, size: 18, color: AppTheme.secondary),
              const SizedBox(width: 8),
              Text('Join code',
                  style: Theme.of(context).textTheme.titleSmall),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Share this with people who should join. They need it once, '
            'and you can add them here directly.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: AppTheme.surface,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppTheme.divider),
                  ),
                  child: Text(
                    code,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.5,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              IconButton(
                tooltip: 'Copy code',
                icon: const Icon(Icons.copy, size: 20),
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: code));
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Join code copied')),
                  );
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}
