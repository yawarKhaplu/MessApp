import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers.dart';
import '../../services/mess_cloud_service.dart';
import '../theme.dart';
import '../widgets/app_widgets.dart';
import 'members_screen.dart';

/// What a member sees for now: which mess they are in, who else is in it, and a
/// way to sign out.
///
/// Deliberately read-only and deliberately short. The full expense app still
/// holds its data in this device's local database, so showing it to a member
/// would display one person's private figures as though they were shared — and
/// invite edits that nobody else would see. Until the data itself is shared,
/// this is the honest screen to show.
class MemberHomeScreen extends ConsumerWidget {
  const MemberHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mess = ref.watch(activeMessProvider).valueOrNull;

    if (mess == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('My mess'),
        // No back button and nothing to go back to: this is the app's home for
        // a member, not a page pushed onto a stack.
        automaticallyImplyLeading: false,
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(activeMessProvider),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            MessSummaryCard(mess: mess),
            const SizedBox(height: 8),
            _YourRole(mess: mess),
            const SizedBox(height: 22),
            Text('People in this mess',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 10),
            const MemberListView(),
            const SizedBox(height: 28),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: AppTheme.textSecondary,
                minimumSize: const Size.fromHeight(50),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(13),
                ),
              ),
              onPressed: () => _signOut(context, ref),
              icon: const Icon(Icons.logout, size: 18),
              label: const Text('Sign out'),
            ),
            const SizedBox(height: 8),
            Center(
              child: Text(
                'Signed in as ${ref.watch(currentUserProvider).valueOrNull?.email ?? ''}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _signOut(BuildContext context, WidgetRef ref) async {
    await ref.read(authServiceProvider).signOut();
    // Clear the open mess and re-read, so the next person to sign in on this
    // device is not dropped straight into the previous account's mess.
    ref.read(activeMessIdProvider.notifier).state = null;
    ref.invalidate(activeMessProvider);
  }
}

/// States plainly what this account may and may not do, so a member is never
/// left wondering why there are no expense tabs.
class _YourRole extends StatelessWidget {
  const _YourRole({required this.mess});

  final Mess mess;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline, color: AppTheme.secondary, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'You are a member of this mess. Expenses are still kept on the '
              'owner\'s device for now, so there is nothing for you to add or '
              'edit yet. You will see them here once that changes.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}