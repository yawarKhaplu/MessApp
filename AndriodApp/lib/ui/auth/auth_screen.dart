import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers.dart';
import '../../services/auth_service.dart';
import '../../services/mess_cloud_service.dart';
import '../mess/members_screen.dart';
import '../theme.dart';
import '../widgets/app_widgets.dart';

/// Shown before anyone signs in.
///
/// The owner simply signs in first and claims the mess. Everyone after that
/// has to be added by the owner, so this screen deliberately has no "register"
/// option: joining is not self-service.
class SignInScreen extends ConsumerStatefulWidget {
  const SignInScreen({super.key});

  @override
  ConsumerState<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends ConsumerState<SignInScreen> {
  bool _busy = false;

  Future<void> _signIn() async {
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);

    try {
      await ref.read(authServiceProvider).signInWithGoogle();
    } on AuthException catch (e) {
      // Errors are surfaced as text rather than a dialog, because this is the
      // first screen a new user ever sees and a setup problem here should not
      // look like a crash.
      messenger.showSnackBar(
        SnackBar(
          content: Text(e.message),
          duration: const Duration(seconds: 6),
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [AppTheme.primary, AppTheme.primaryDark],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 84,
                    height: 84,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: const Icon(Icons.home_rounded,
                        color: Colors.white, size: 42),
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'MessAppDev',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 30,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Cook, spend and collect together',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.85),
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 40),
                  SizedBox(
                    width: double.infinity,
                    height: 54,
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: AppTheme.primaryDark,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      onPressed: _busy ? null : _signIn,
                      child: _busy
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                color: AppTheme.primaryDark,
                              ),
                            )
                          : const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.g_mobiledata, size: 26),
                                SizedBox(width: 10),
                                Text(
                                  'Continue with Google',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                    ),
                  ),
                  const SizedBox(height: 22),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.group_outlined,
                            color: Colors.white70, size: 18),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'First to sign in becomes the mess owner. '
                            'After that, the owner adds everyone else by '
                            'email — there is no open sign-up.',
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.9),
                              fontSize: 12.5,
                              height: 1.4,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Shows who is signed in, for verifying the login works.
class AccountCard extends ConsumerWidget {
  const AccountCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider).valueOrNull;
    if (user == null) return const SizedBox.shrink();
    final mess = ref.watch(activeMessProvider).valueOrNull;
    final role = ref.watch(myRoleProvider);

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: AppTheme.primary.withOpacity(0.12),
                backgroundImage: user.photoUrl != null
                    ? NetworkImage(user.photoUrl!)
                    : null,
                child: user.photoUrl != null
                    ? null
                    : Text(
                        (user.displayName ?? user.email).isNotEmpty
                            ? (user.displayName ?? user.email)[0].toUpperCase()
                            : '?',
                        style: const TextStyle(
                          color: AppTheme.primary,
                          fontWeight: FontWeight.w700,
                          fontSize: 18,
                        ),
                      ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      user.displayName ?? 'Signed in',
                      style: Theme.of(context).textTheme.titleSmall,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      user.email,
                      style: Theme.of(context).textTheme.bodySmall,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),

          // Which mess and what role, so the gate's decision is visible on
          // screen rather than only discoverable by testing.
          if (mess != null) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (role != null)
                  _Badge(
                    label: role == MessRole.owner ? 'Owner' : 'Member',
                    color: role == MessRole.owner
                        ? AppTheme.primary
                        : AppTheme.success,
                  ),
                _Badge(label: mess.name, color: AppTheme.secondary),
              ],
            ),
          ],

          const SizedBox(height: 4),
          Row(
            children: [
              const Icon(Icons.tag, size: 13, color: AppTheme.textSecondary),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  'UID ${user.uid}',
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(fontSize: 10.5),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              IconButton(
                tooltip: 'Manage mess members',
                icon: const Icon(Icons.groups_outlined, size: 19),
                color: AppTheme.textSecondary,
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const MembersScreen(),
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Sign out',
                icon: const Icon(Icons.logout, size: 20),
                color: AppTheme.textSecondary,
                onPressed: () async {
                  await ref.read(authServiceProvider).signOut();
                  // Clear the open mess too, otherwise the next person to sign
                  // in on this device would be dropped straight into the
                  // previous account's mess.
                  ref.read(activeMessIdProvider.notifier).state = null;
                  ref.invalidate(activeMessProvider);
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Small pill showing a label, used for role and mess name.
class _Badge extends StatelessWidget {
  const _Badge({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}