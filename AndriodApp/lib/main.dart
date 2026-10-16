import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'services/notifications.dart';
import 'services/cloud_diagnostics.dart';
import 'providers.dart';
import 'ui/auth/auth_screen.dart';
import 'ui/home_screen.dart';
import 'ui/mess/mess_gate.dart';
import 'ui/menu_entry_screen.dart';
import 'ui/menus_screen.dart';
import 'ui/collection_screen.dart';
import 'ui/reports_screen.dart';
import 'ui/settings_screen.dart';
import 'ui/theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize local notifications early so the reminder can be scheduled.
  // The permission prompt is NOT requested here: Android ignores a
  // permission request made before the activity window exists, which is why
  // the dialog never appeared on a fresh install.
  await NotificationService.instance.init();

  // Firebase must be initialised before any auth call. On Android it reads
  // android/app/google-services.json through the native plugin, so no generated
  // options file is needed. Deliberately outside try/catch: if it throws the app
  // cannot authenticate, and continuing would only fail confusingly later.
  await diagnoseCloudOperation(
    'firebase.initialize',
    () => Firebase.initializeApp(),
  );

  runApp(const ProviderScope(child: MessApp()));
}

class MessApp extends ConsumerWidget {
  const MessApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp(
      title: 'MessAppDev',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      // Nothing opens until someone is signed in AND belongs to a mess. The
      // existing local data is untouched by signing out, so the app can never
      // lock anyone out of it.
      home: const _AuthGate(),
    );
  }
}

/// Decides between the sign-in screen and the app itself.
class _AuthGate extends ConsumerWidget {
  const _AuthGate();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);

    return user.when(
      // Firebase restores the previous session on start-up; a brief splash
      // beats flashing the sign-in button at someone who is already signed in.
      loading: () => const _SplashScreen(),
      data: (account) => account == null
          ? const SignInScreen()
          // Signed in, but possibly no mess yet. MessGate decides between
          // creating one and asking for approval.
          : const MessGate(),
      error: (_, __) => const SignInScreen(),
    );
  }
}

class _SplashScreen extends StatelessWidget {
  const _SplashScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: CircularProgressIndicator(color: AppTheme.primary)),
    );
  }
}

/// Bottom-navigation shell: Home, Menus, Collection, Reports, Settings.
class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  int _index = 0;

  static const _pages = [
    HomeScreen(),
    MenusScreen(),
    CollectionScreen(),
    ReportsScreen(),
    SettingsScreen(),
  ];

  @override
  void initState() {
    super.initState();
    // Asked after the first frame, when the activity window is really up.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _openNotificationDestination();
      _askForNotifications();
    });
    // Taps that arrive while the app is already open.
    _taps = NotificationService.instance.onTap.listen((_) {
      if (mounted) _openNotificationDestination();
    });
  }

  StreamSubscription<String?>? _taps;

  @override
  void dispose() {
    _taps?.cancel();
    super.dispose();
  }

  /// A tapped notification should land on the entry screen, not on Home with
  /// the "What did you cook today?" prompt still waiting to be pressed.
  Future<void> _openNotificationDestination() async {
    final destination = NotificationService.instance.takePendingDestination();
    if (destination != kDestinationAddEntry || !mounted) return;

    await Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const MenuEntryScreen()));
  }

  /// Prompts once, and only when notifications are actually blocked.
  Future<void> _askForNotifications() async {
    final service = NotificationService.instance;
    if (await service.notificationsEnabled() ?? true) return;
    if (!mounted) return;

    final granted = await service.requestPermission();
    if (!granted || !mounted) return;

    // Permission arriving after startup means the schedule may predate it,
    // so re-apply to be sure the reminder is armed.
    final settings = ref.read(settingsProvider).valueOrNull;
    await service.applySettings(
      enabled: settings?.reminderEnabled ?? true,
      timeHHmm: settings?.reminderTime ?? '21:00',
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _index, children: _pages),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: AppTheme.surface,
          border: Border(
            top: BorderSide(color: AppTheme.divider.withOpacity(0.5)),
          ),
        ),
        child: NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: (i) => setState(() => _index = i),
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.home_outlined),
              selectedIcon: Icon(Icons.home),
              label: 'Home',
            ),
            NavigationDestination(
              icon: Icon(Icons.restaurant_menu_outlined),
              selectedIcon: Icon(Icons.restaurant_menu),
              label: 'Menus',
            ),
            NavigationDestination(
              icon: Icon(Icons.payments_outlined),
              selectedIcon: Icon(Icons.payments),
              label: 'Collection',
            ),
            NavigationDestination(
              icon: Icon(Icons.assessment_outlined),
              selectedIcon: Icon(Icons.assessment),
              label: 'Reports',
            ),
            NavigationDestination(
              icon: Icon(Icons.settings_outlined),
              selectedIcon: Icon(Icons.settings),
              label: 'Settings',
            ),
          ],
        ),
      ),
    );
  }
}
