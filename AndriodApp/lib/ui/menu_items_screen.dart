import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../data/models.dart';
import '../providers.dart';
import '../services/menu_cloud_service.dart';
import '../ui/theme.dart';
import '../ui/widgets/app_widgets.dart';
import 'widgets/item_dialog.dart';

/// Manages the items that belong to one menu.
///
/// Anything saved here is stored against the menu, so it shows up every time
/// this menu is picked while adding a daily entry.
class MenuItemsScreen extends ConsumerStatefulWidget {
  final CloudMenu menu;

  const MenuItemsScreen({super.key, required this.menu});

  @override
  ConsumerState<MenuItemsScreen> createState() => _MenuItemsScreenState();
}

class _MenuItemsScreenState extends ConsumerState<MenuItemsScreen> {
  @override
  void initState() {
    super.initState();
  }

  /// The live catalogue, so an item saved here is the one everyone else sees.
  List<CloudMenuItem> get _items =>
      ref.watch(menusProvider).valueOrNull?.byId(widget.menu.id)?.items ??
      const [];

  MenusNotifier get _menus => ref.read(menusProvider.notifier);

  Future<void> _afterChange() async {
    ref.invalidate(menusProvider);
  }

  Future<void> _addItem() async {
    final suggestions = _suggestions();
    final result = await showDialog<({String name, double price})>(
      context: context,
      builder: (_) => ItemDialog(
        title: 'Add item',
        confirmLabel: 'Add item',
        suggestions: suggestions,
        existingNames: _items.map((i) => i.name.toLowerCase()).toSet(),
      ),
    );
    if (result == null || !mounted) return;

    await _menus.addItem(widget.menu.id, result.name, result.price);
    await _afterChange();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('"${result.name}" added to ${widget.menu.name}')),
    );
  }

  /// Items used in other menus, offered as one-tap suggestions.
  ///
  /// Taken from the catalogue already in memory, so this cannot be out of step
  /// with what the rest of the screen is showing.
  List<ItemSuggestion> _suggestions() {
    final catalogue = ref.read(menusProvider).valueOrNull;
    if (catalogue == null) return const [];

    final byName = <String, List<String>>{};
    final price = <String, double>{};
    for (final menu in catalogue.menus) {
      if (menu.id == widget.menu.id) continue;
      for (final item in menu.items) {
        final key = item.name.trim().toLowerCase();
        if (key.isEmpty) continue;
        byName.putIfAbsent(key, () => []).add(menu.name);
        final seen = price[key] ?? 0;
        if (item.defaultPrice > seen) price[key] = item.defaultPrice;
      }
    }

    final keys = byName.keys.toList()..sort();
    return [
      for (final key in keys)
        ItemSuggestion(
          key,
          byName[key]!.join(', '),
          price[key] ?? 0,
        ),
    ];
  }

  Future<void> _editItem(CloudMenuItem item) async {
    final result = await showDialog<({String name, double price})>(
      context: context,
      builder: (_) => ItemDialog(
        title: 'Edit item',
        confirmLabel: 'Save',
        initialName: item.name,
        initialPrice: item.defaultPrice,
        suggestions: _suggestions(),
        existingNames: _items
            .where((i) => i.id != item.id)
            .map((i) => i.name.toLowerCase())
            .toSet(),
      ),
    );
    if (result == null || !mounted) return;

    await _menus.updateItem(
        widget.menu.id, item.id, result.name, result.price);
    await _afterChange();
  }

  Future<void> _deleteItem(CloudMenuItem item) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Remove "${item.name}"?'),
        content: const Text(
            'This removes the item from this menu. Past expenses keep it.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Remove')),
        ],
      ),
    );
    if (ok != true) return;
    await _menus.deleteItem(widget.menu.id, item.id);
    await _afterChange();
  }

  void _reorder(int oldIndex, int newIndex) {
    setState(() {
      if (newIndex > oldIndex) newIndex -= 1;
      final m = _items.removeAt(oldIndex);
      _items.insert(newIndex, m);
    });
    _afterChange();
  }

  @override
  Widget build(BuildContext context) {
    final money = NumberFormat.currency(symbol: 'PKR ', decimalDigits: 0);

    return Scaffold(
      appBar: AppBar(title: Text('${widget.menu.name} items')),
      body: _items.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.playlist_add,
                            size: 64, color: AppTheme.textSecondary),
                        const SizedBox(height: 16),
                        Text(
                          'No items in ${widget.menu.name} yet',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Add the things this menu needs. They will appear '
                          'automatically every time you pick ${widget.menu.name}.',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                )
              : Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                      child: AppCard(
                        child: Row(
                          children: [
                            const Icon(Icons.info_outline,
                                color: AppTheme.secondary, size: 20),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'These ${_items.length} '
                                '${_items.length == 1 ? 'item shows' : 'items show'} '
                                'automatically whenever ${widget.menu.name} is '
                                'selected. Drag to reorder.',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Expanded(
                      child: ReorderableListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                        itemCount: _items.length,
                        onReorder: _reorder,
                        buildDefaultDragHandles: false,
                        itemBuilder: (context, i) {
                          final item = _items[i];
                          return Padding(
                            key: ValueKey(item.id),
                            padding: const EdgeInsets.only(bottom: 10),
                            child: AppCard(
                              padding: const EdgeInsets.all(12),
                              onTap: () => _editItem(item),
                              child: Row(
                                children: [
                                  Container(
                                    width: 36,
                                    height: 36,
                                    alignment: Alignment.center,
                                    decoration: BoxDecoration(
                                      color:
                                          AppTheme.primary.withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(11),
                                    ),
                                    child: Text(
                                      '${i + 1}',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w800,
                                        color: AppTheme.primary,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          item.name,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                              fontWeight: FontWeight.w700),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          item.defaultPrice > 0
                                              ? 'Usual price ${money.format(item.defaultPrice)}'
                                              : 'Tap to set a usual price',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: AppTheme.textSecondary
                                                .withOpacity(0.95),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete_outline,
                                        size: 20),
                                    tooltip: 'Remove item',
                                    onPressed: () => _deleteItem(item),
                                  ),
                                  ReorderableDragStartListener(
                                    index: i,
                                    child: const Padding(
                                      padding: EdgeInsets.all(8),
                                      child: Icon(Icons.drag_handle,
                                          color: AppTheme.textSecondary),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addItem,
        icon: const Icon(Icons.add),
        label: const Text('Add item'),
      ),
    );
  }
}
