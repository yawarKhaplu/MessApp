import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../main.dart' show HomeShell;
import '../../providers.dart';
import '../../services/mess_cloud_service.dart';
import '../theme.dart';
import '../widgets/app_widgets.dart';
import 'member_home_screen.dart';

/// Decides what a signed-in person sees next.
///
///   already in a mess            -> straight into the app
///   approved, no mess yet        -> create one
///   neither                      -> request access
class MessGate extends ConsumerStatefulWidget {
  const MessGate({super.key});

  @override
  ConsumerState<MessGate> createState() => _MessGateState();
}

class _MessGateState extends ConsumerState<MessGate> {
  void _retry() => ref.invalidate(activeMessProvider);

  @override
  Widget build(BuildContext context) {
    final active = ref.watch(activeMessProvider);

    // Has a mess: go straight in. Checked before the loading and error cases so
    // a brief reload never flashes the wrong screen at an existing member.
    final mess = active.valueOrNull;
    if (mess != null) {
      // Recorded so the rest of the app can identify the open mess. Only set
      // once the read has landed, and guarded so a rebuild cannot fight the
      // value that was already established.
      if (ref.read(activeMessIdProvider) != mess.id) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            ref.read(activeMessIdProvider.notifier).state = mess.id;
          }
        });
      }
      // The owner gets the full app. A member gets only their mess, its people
      // and sign-out, because the expense data still lives on the owner's
      // device and showing it here would present one person's figures as shared.
      return mess.isOwner ? const HomeShell() : const MemberHomeScreen();
    }

    return active.when(
      loading: () => const _Busy(),
      // The mess is resolved BEFORE approval is ever consulted: an account that
      // already belongs to a mess must never be offered the create screen.
      error: (e, _) => _MessageScreen(
        icon: Icons.cloud_off_outlined,
        title: 'Could not load your mess',
        body: '$e',
        actionLabel: 'Try again',
        onAction: _retry,
      ),
      data: (_) => const _ApprovalOrCreate(),
    );
  }
}

/// Guards the "you have no mess, create one" conclusion against a membership
/// record that is merely late or missing.
///
/// The membership document is the fast path, but it was introduced after the
/// first messes were created. An existing owner whose record is absent would
/// otherwise be told to create a second mess — the exact wrong answer, and one
/// the rules would then refuse anyway. This re-checks the profile, which was
/// written at creation time and always exists for a real owner, so the create
/// screen is only ever shown to someone who has genuinely not created one.
class _ApprovalOrCreate extends ConsumerStatefulWidget {
  const _ApprovalOrCreate();

  @override
  ConsumerState<_ApprovalOrCreate> createState() => _ApprovalOrCreateState();
}

class _ApprovalOrCreateState extends ConsumerState<_ApprovalOrCreate> {
  late Future<bool> _approved;

  @override
  void initState() {
    super.initState();
    _approved = ref.read(messCloudServiceProvider).isApprovedCreator();
  }

  void _retry() {
    setState(() {
      _approved = ref.read(messCloudServiceProvider).isApprovedCreator();
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _approved,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const _Busy();
        }
        if (snap.hasError) {
          return _MessageScreen(
            icon: Icons.cloud_off_outlined,
            title: 'Could not check your access',
            body: '${snap.error}',
            actionLabel: 'Try again',
            onAction: _retry,
          );
        }
        // Only reached when resolveMess has already established that this account
        // has no mess. It checks the profile, then asks Firestore directly, so a
        // missing or stale record cannot wrongly route an owner here.
        return snap.data == true
            ? const _CreateMessScreen()
            : const _RequestAccessScreen();
      },
    );
  }
}

class _Busy extends StatelessWidget {
  const _Busy();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: CircularProgressIndicator(color: AppTheme.primary),
      ),
    );
  }
}

/// For an approved creator with no mess yet.
class _CreateMessScreen extends ConsumerStatefulWidget {
  const _CreateMessScreen();

  @override
  ConsumerState<_CreateMessScreen> createState() => _CreateMessScreenState();
}

class _CreateMessScreenState extends ConsumerState<_CreateMessScreen> {
  final _name = TextEditingController();
  final _location = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _location.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    if (_name.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Give the mess a name.')),
      );
      return;
    }
    setState(() => _busy = true);
    final cloud = ref.read(messCloudServiceProvider);
    final messenger = ScaffoldMessenger.of(context);

    try {
      final mess = await cloud.createMess(
        name: _name.text,
        location: _location.text,
      );
      if (!mounted) return;
      // MessGate watches this and re-reads, so creating a mess lands on Home
      // rather than leaving them on this screen.
      ref.invalidate(activeMessProvider);

      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'Created. Join code ${mess.joinCode} — give it to your mess.',
          ),
          duration: const Duration(seconds: 6),
        ),
      );
    } on CloudMessage catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.text)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Create your mess')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppTheme.success.withOpacity(0.1),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                const Icon(Icons.verified_user,
                    color: AppTheme.success, size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Your account is approved. You will be the owner of this '
                    'mess, and you decide who else joins.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          TextField(
            controller: _name,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Mess name',
              hintText: 'Bari #3, Street 5',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _location,
            decoration: const InputDecoration(
              labelText: 'Location (optional)',
              hintText: 'Lahore',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 28),
          SizedBox(
            height: 52,
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.primary,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              onPressed: _busy ? null : _create,
              child: _busy
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.4,
                        color: Colors.white,
                      ),
                    )
                  : const Text('Create mess and become owner'),
            ),
          ),
        ],
      ),
    );
  }
}

/// For anyone signed in who is neither a member nor an approved creator.
///
/// Two clear routes out, because "contact us" on its own leaves the user
/// guessing. There is no way past this screen: it is the app's home while no
/// mess is open, and the only action offered is signing out.
class _RequestAccessScreen extends ConsumerWidget {
  const _RequestAccessScreen();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider).valueOrNull;

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 32, 20, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 76,
                  height: 76,
                  decoration: BoxDecoration(
                    color: AppTheme.accent.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(22),
                  ),
                  child: const Icon(Icons.lock_outline,
                      color: AppTheme.accent, size: 36),
                ),
              ),
              const SizedBox(height: 20),
              Center(
                child: Text(
                  "You're not in a mess yet",
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
              ),
              const SizedBox(height: 8),
              Center(
                child: Text(
                  'MessApp opens only for people in a mess. Pick one of the '
                  'two ways in.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
              const SizedBox(height: 26),

              if (user != null) ...[
                _RouteCard(
                  icon: Icons.storefront_outlined,
                  iconColor: AppTheme.primary,
                  title: 'Want to run your own mess?',
                  body: 'Get creator approval and start a mess for your own '
                      'group. People elsewhere use their own separate mess '
                      'and never see yours.',
                  actionLabel: 'I have approval',
                  onTap: () => _explainCreator(context),
                ),
                const SizedBox(height: 14),
                _RouteCard(
                  icon: Icons.group_add_outlined,
                  iconColor: AppTheme.secondary,
                  title: 'Joining someone else\'s mess?',
                  body: 'Ask the owner of that mess to add you. They enter '
                      'your email once and you get in on your next sign-in.',
                  actionLabel: 'Copy my email',
                  onTap: () async {
                    await Clipboard.setData(ClipboardData(text: user.email));
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                            'Copied ${user.email}. Send it to your mess owner.'),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 22),
                Center(
                  child: TextButton.icon(
                    onPressed: () async {
                      await ref.read(authServiceProvider).signOut();
                      // Clearing the id and re-reading stops the previous
                      // account's mess from lingering on screen.
                      ref.read(activeMessIdProvider.notifier).state = null;
                      ref.invalidate(activeMessProvider);
                    },
                    icon: const Icon(Icons.logout, size: 18),
                    label: const Text('Sign out'),
                  ),
                ),
              ] else
                const Center(child: CircularProgressIndicator()),
            ],
          ),
        ),
      ),
    );
  }

  /// Spells out how creator approval actually happens, so "I have approval"
  /// is not a dead end.
  void _explainCreator(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(22, 0, 22, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('How creator approval works',
                style: Theme.of(ctx).textTheme.titleLarge),
            const SizedBox(height: 12),
            Text(
              'MessApp is invite-only. To run your own mess:\n\n'
              '1. Contact the people behind the app.\n'
              '2. They approve your account.\n'
              '3. Reopen the app and create your mess.\n\n'
              'One account runs one mess. People at other addresses create '
              'their own and never see yours.',
              style: Theme.of(ctx).textTheme.bodyMedium?.copyWith(height: 1.5),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Got it'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RouteCard extends StatelessWidget {
  const _RouteCard({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.body,
    required this.actionLabel,
    required this.onTap,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String body;
  final String actionLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: iconColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(icon, color: iconColor, size: 21),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(body, style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: onTap,
              child: Text(actionLabel),
            ),
          ),
        ],
      ),
    );
  }
}

class _MessageScreen extends StatelessWidget {
  const _MessageScreen({
    required this.icon,
    required this.title,
    required this.body,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String body;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 44, color: AppTheme.textSecondary),
              const SizedBox(height: 18),
              Text(title, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 10),
              Text(
                body,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              if (actionLabel != null) ...[
                const SizedBox(height: 24),
                FilledButton(onPressed: onAction, child: Text(actionLabel!)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}