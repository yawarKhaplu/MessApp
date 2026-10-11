import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models.dart';
import '../providers.dart';
import '../ui/theme.dart';
import '../ui/widgets/app_widgets.dart';
import 'menu_entry_screen.dart';
import 'menu_items_screen.dart';
import 'widgets/text_input_dialog.dart';

/// Menu list (PRD 5.2): default and custom menus, add / rename / delete.
class MenusScreen extends ConsumerStatefulWidget {
  const MenusScreen({super.key});

  @override
  ConsumerState<MenusScreen> createState() => _MenusScreenState();
}

class _MenusScreenState extends ConsumerState<MenusScreen> {
  Future<void> _addMenu() async {
    final name = await _promptName('Add menu', 'Menu name (e.g. Biryani)');
    if (name != null && name.trim().isNotEmpty) {
      await ref.read(menusProvider.notifier).add(name.trim());
    }
  }

  Future<void> _renameMenu(int id, String current) async {
    final name =
        await _promptName('Rename menu', 'Menu name', initial: current);
    if (name != null && name.trim().isNotEmpty) {
      await ref.read(menusProvider.notifier).rename(id, name.trim());
    }
  }

  Future<void> _deleteMenu(Menu menu) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete "${menu.name}"?'),
        content: const Text('Menu items are removed. Past expenses are kept.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (ok == true) {
      await ref.read(menusProvider.notifier).delete(menu.id!);
    }
  }

  Future<String?> _promptName(String title, String hint,
      {String initial = ''}) async {
    return showDialog<String>(
      context: context,
      builder: (_) => TextInputDialog(
        title: title,
        hint: hint,
        initialValue: initial,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final menusAsync = ref.watch(menusProvider);
    final counts = ref.watch(menuItemCountsProvider).valueOrNull ?? const <int, int>{};

    return Scaffold(
      appBar: AppBar(
        title: const Text('Menus'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_rounded),
            tooltip: 'Add menu',
            onPressed: _addMenu,
          ),
        ],
      ),
      body: menusAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (menus) {
          if (menus.isEmpty) {
            return const Center(child: Text('No menus yet. Tap + to add one.'));
          }
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: menus.length,
            itemBuilder: (context, i) {
              final menu = menus[i];
              final itemCount = counts[menu.id] ?? 0;
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: AppCard(
                  onTap: () async {
                    await Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => MenuItemsScreen(menu: menu),
                    ));
                    ref.invalidate(menuItemCountsProvider);
                  },
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 52,
                            height: 52,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: menu.isDefault
                                    ? [AppTheme.primary, AppTheme.primaryDark]
                                    : [
                                        AppTheme.secondary,
                                        AppTheme.secondary.withOpacity(0.7)
                                      ],
                              ),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Icon(
                              menu.isDefault
                                  ? Icons.restaurant
                                  : Icons.restaurant_outlined,
                              color: Colors.white,
                              size: 26,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(menu.name,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium),
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    AppBadge(
                                      label: menu.isDefault
                                          ? 'Default'
                                          : 'Custom',
                                      color: menu.isDefault
                                          ? AppTheme.primary
                                          : AppTheme.secondary,
                                    ),
                                    const SizedBox(width: 6),
                                    AppBadge(
                                      label: itemCount == 1
                                          ? '1 item'
                                          : '$itemCount items',
                                      color: itemCount == 0
                                          ? AppTheme.textSecondary
                                          : AppTheme.secondary,
                                      icon: Icons.list_alt,
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          PopupMenuButton<String>(
                            onSelected: (v) async {
                              if (v == 'rename') {
                                _renameMenu(menu.id!, menu.name);
                              } else if (v == 'delete') {
                                _deleteMenu(menu);
                              } else if (v == 'expense') {
                                await Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        MenuEntryScreen(menu: menu),
                                  ),
                                );
                              } else if (v == 'items') {
                                await Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        MenuItemsScreen(menu: menu),
                                  ),
                                );
                                ref.invalidate(menuItemCountsProvider);
                              }
                            },
                            itemBuilder: (_) => const [
                              PopupMenuItem(
                                  value: 'items',
                                  child: Text('Manage items')),
                              PopupMenuItem(
                                  value: 'expense',
                                  child: Text('Add expense from this menu')),
                              PopupMenuItem(
                                  value: 'rename', child: Text('Rename')),
                              PopupMenuItem(
                                  value: 'delete', child: Text('Delete')),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      const Divider(height: 1),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Icon(
                            itemCount == 0
                                ? Icons.playlist_add
                                : Icons.check_circle,
                            size: 16,
                            color: itemCount == 0
                                ? AppTheme.textSecondary
                                : AppTheme.success,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              itemCount == 0
                                  ? 'No items yet — tap to add them'
                                  : 'Tap to view or edit these items',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: itemCount == 0
                                    ? AppTheme.textSecondary
                                    : AppTheme.success,
                              ),
                            ),
                          ),
                          const Icon(Icons.chevron_right,
                              size: 18, color: AppTheme.textSecondary),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
