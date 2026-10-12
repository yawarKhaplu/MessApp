import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../data/models.dart';
import '../data/repository.dart';
import '../providers.dart';
import '../services/expense_cloud_service.dart';
import '../services/mess_cloud_service.dart';
import '../services/menu_cloud_service.dart';
import '../ui/theme.dart';
import '../ui/widgets/app_widgets.dart';
import 'widgets/item_dialog.dart';
import 'widgets/member_picker_sheet.dart';
import 'widgets/pick_date.dart';
import 'widgets/text_input_dialog.dart';

/// Daily entry flow (PRD 5.3): pick date & menu, edit item prices,
/// remove unused items, add one-off items, save.
class MenuEntryScreen extends ConsumerStatefulWidget {
  final CloudMenu? menu;
  const MenuEntryScreen({super.key, this.menu});

  @override
  ConsumerState<MenuEntryScreen> createState() => _MenuEntryScreenState();
}

class _MenuEntryScreenState extends ConsumerState<MenuEntryScreen> {
  DateTime _date = DateTime.now();
  CloudMenu? _menu;
  Member? _member;

  /// Menu items come from the shared catalogue, so everyone enters against the
  /// same list.
  List<CloudMenuItem> _items = [];

  /// Keyed by the item's id from the catalogue.
  final Map<String, TextEditingController> _priceControllers = {};
  final Map<String, TextEditingController> _qtyControllers = {};

  /// The grand total the user types in; used to split across items.
  final TextEditingController _totalCtrl = TextEditingController();
  final FocusNode _totalFocus = FocusNode();

  /// How the last entry for this menu split its total across items.
  SplitHints? _hints;

  /// Bumped whenever a price/qty changes so the totals rebuild live.
  final ValueNotifier<int> _tick = ValueNotifier<int>(0);

  bool _loading = true;
  bool _splitting = false;

  @override
  void initState() {
    super.initState();
    _totalCtrl.addListener(_onItemsChanged);
    _totalFocus.addListener(() => setState(() {}));
    _menu = widget.menu;
    _load();
  }

  void _onItemsChanged() {
    if (mounted) _tick.value++;
  }

  void _bind(CloudMenuItem item) {
    _priceControllers[item.id]?.addListener(_onItemsChanged);
    _qtyControllers[item.id]?.addListener(_onItemsChanged);
  }

  void _unbind(CloudMenuItem item) {
    _priceControllers[item.id]?.removeListener(_onItemsChanged);
    _qtyControllers[item.id]?.removeListener(_onItemsChanged);
  }

  @override
  void dispose() {
    _totalCtrl.dispose();
    _totalFocus.dispose();
    _tick.dispose();
    _clearControllers();
    super.dispose();
  }

  /// Whose turn it is to cook / who paid (PRD 5.3 / member tracking).
  Future<void> _pickMember() async {
    final repo = ref.read(repositoryProvider);
    final rotation = await repo.getCookRotation();
    final members = rotation.hasMembers
        ? rotation.members
        : await ref.read(membersProvider.future);
    if (!mounted) return;
    if (members.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Add members first in the Collection tab')),
      );
      return;
    }

    final result = await showMemberPickerSheet(
      context,
      members: members,
      current: _member,
      turnIndex:
          rotation.hasMembers ? rotation.positionInRound - 1 : null,
      subtitle: rotation.followsHistory
          ? 'Based on who cooked last'
          : 'Who takes the next turn',
    );
    // null means the sheet was dismissed — keep whatever was set.
    if (result == null || !mounted) return;
    setState(() {
      _member =
          identical(result, kUnassignedMember) ? null : result as Member;
    });
  }

  /// Clear the assignment without opening the picker.
  void _clearMember() {
    setState(() => _member = null);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Bari set to unassigned')),
    );
  }

  Future<void> _load() async {
    final repo = ref.read(repositoryProvider);
    if (_menu != null) {
      // Items from the shared catalogue; split history still comes from the
      // local expense records until those move to Firestore.
      _items = _catalogueItems(_menu!.id);
      for (final item in _items) {
        _priceCtrl(item);
        _qtyCtrl(item);
        _bind(item);
      }
      _hints = await repo.getSplitHints(_menu!.name);
    }
    // Default: whoever is on cooking turn for the selected date.
    _member = await repo.getCookOfTheDay(_date);
    if (!mounted) return;
    setState(() => _loading = false);
  }

  /// Items for a menu, read from the catalogue already loaded.
  List<CloudMenuItem> _catalogueItems(String menuId) =>
      ref.read(menusProvider).valueOrNull?.byId(menuId)?.items ?? const [];

  /// Creates a menu and immediately selects it, so a brand new menu can be
  /// used without leaving this screen.
  Future<void> _createMenuThenUse() async {
    final name = await showDialog<String>(
      context: context,
      builder: (_) => const TextInputDialog(
        title: 'New menu',
        hint: 'e.g. Biryani',
        confirmLabel: 'Create',
      ),
    );
    if (name == null || name.trim().isEmpty) return;
    await ref.read(menusProvider.notifier).add(name.trim());
    if (!mounted) return;

    final menus = ref.read(menusProvider).valueOrNull?.menus ?? const [];
    if (menus.isEmpty) return;
    final created = menus.firstWhere(
      (m) => m.name.toLowerCase() == name.trim().toLowerCase(),
      orElse: () => menus.last,
    );
    ref.invalidate(menusProvider);
    await _selectMenu(created);
  }

  /// Switches the form to [picked] and loads its items and split history.
  Future<void> _selectMenu(CloudMenu picked) async {
    setState(() {
      _menu = picked;
      _loading = true;
      _hints = null;
    });
    _clearControllers();
    final repo = ref.read(repositoryProvider);
    _items = _catalogueItems(picked.id);
    _hints = await repo.getSplitHints(picked.name);
    for (final item in _items) {
      _priceCtrl(item);
      _qtyCtrl(item);
      _bind(item);
    }
    if (!mounted) return;
    setState(() => _loading = false);
  }

  /// Opens the menu chooser as a bottom sheet showing each menu with how many
  /// items it carries, so it is obvious which one will fill the form.
  Future<void> _pickMenu() async {
    // From the shared catalogue, so the menu a member picks is the same one the
    // owner sees.
    final catalogue = ref.read(menusProvider).valueOrNull;
    final menus = catalogue?.menus ?? const <CloudMenu>[];
    final counts = catalogue?.itemCounts ?? const <String, int>{};
    if (!mounted) return;

    final picked = await showModalBottomSheet<CloudMenu>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.62,
        minChildSize: 0.4,
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
                      colors: [AppTheme.primary, AppTheme.primaryDark],
                    ),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(Icons.restaurant_menu,
                      color: Colors.white, size: 22),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Choose a menu',
                          style: Theme.of(ctx).textTheme.titleLarge),
                      const SizedBox(height: 2),
                      Text(
                        'Its items load in automatically',
                        style: Theme.of(ctx).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            for (final m in menus)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _MenuChoiceTile(
                  menu: m,
                  itemCount: counts[m.id] ?? 0,
                  selected: m.id == _menu?.id,
                  onTap: () => Navigator.pop(ctx, m),
                ),
              ),
            const SizedBox(height: 4),
            OutlinedButton.icon(
              onPressed: () {
                Navigator.pop(ctx);
                _createMenuThenUse();
              },
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Create a new menu'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
              ),
            ),
          ],
        ),
      ),
    );

    if (picked != null) {
      await _selectMenu(picked);
    }
  }

  Future<void> _pickDate() async {
    final picked = await pickClampedDate(
      context,
      initialDate: _date,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      // Changing the date also moves the default cook to that day's turn.
      final cook = await ref.read(repositoryProvider).getCookOfTheDay(picked);
      if (!mounted) return;
      setState(() {
        _date = picked;
        _member = cook;
      });
    }
  }

  void _clearControllers() {
    for (final c in _priceControllers.values) {
      c.removeListener(_onItemsChanged);
      c.dispose();
    }
    for (final c in _qtyControllers.values) {
      c.removeListener(_onItemsChanged);
      c.dispose();
    }
    _priceControllers.clear();
    _qtyControllers.clear();
  }

  TextEditingController _priceCtrl(CloudMenuItem item) =>
      _priceControllers.putIfAbsent(
          item.id,
          () => TextEditingController(
              text: item.defaultPrice > 0
                  ? item.defaultPrice.toStringAsFixed(0)
                  : ''));

  TextEditingController _qtyCtrl(CloudMenuItem item) =>
      _qtyControllers.putIfAbsent(
          item.id, () => TextEditingController(text: '1'));

  double _parsePrice(TextEditingController c) =>
      double.tryParse(c.text.replaceAll(',', '')) ?? 0;

  double _parseQty(TextEditingController c) =>
      double.tryParse(c.text) ?? 1;

  Future<void> _addOneOffItem() async {
    final repo = ref.read(repositoryProvider);
    final suggestions = await _entrySuggestions();
    if (!mounted) return;

    final result = await showDialog<({String name, double price})>(
      context: context,
      builder: (_) => ItemDialog(
        title: 'Add item',
        confirmLabel: 'Add',
        suggestions: suggestions,
        existingNames:
            _items.map((i) => i.name.toLowerCase()).toSet(),
        suggestionsLabel: 'Used before',
      ),
    );
    if (result == null) return;
    final name = result.name;
    final price = result.price.toStringAsFixed(0);

    // A one-off item is not saved to the menu, so it needs an id that cannot
    // collide with a real catalogue item. Prefixed so it is obvious in the
    // controller maps and never mistaken for a stored id.
    const oneOffId = 'tmp';

    setState(() {
      _items.add(CloudMenuItem(
        id: oneOffId,
        name: name.trim(),
        defaultPrice: double.tryParse(price) ?? 0,
        // Sorted to the end so a one-off never displaces a real item.
        order: 1000,
      ));
      final added = _items.last;
      _priceControllers[added.id] =
          TextEditingController(text: price.trim());
      _qtyControllers[added.id] = TextEditingController(text: '1');
      _bind(added);
    });

    // Offer to make it a permanent part of this menu — without blocking the
    // flow with a second dialog.
    if (_menu == null) return;
    final itemName = name.trim();
    final amount = double.tryParse(price) ?? 0;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('"$itemName" added'),
          duration: const Duration(seconds: 5),
          action: SnackBarAction(
            label: 'Save to menu',
            onPressed: () async {
              await ref
                  .read(menusProvider.notifier)
                  .addItem(_menu!.id, itemName, amount);
              ref.invalidate(menusProvider);
              _hints = await repo.getSplitHints(_menu!.name);
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('"$itemName" saved to ${_menu!.name}')),
              );
            },
          ),
        ),
      );
  }

  /// Items already used elsewhere: from other menus and from past expenses.
  ///
  /// Suggestions are a convenience only — if either lookup fails we still let
  /// the item be added, just without shortcuts.
  Future<List<ItemSuggestion>> _entrySuggestions() async {
    final repo = ref.read(repositoryProvider);
    final out = <String, ItemSuggestion>{};

    if (_menu != null) {
      try {
        final rows = await repo.getItemSuggestions(_menu!.name);
        for (final r in rows) {
          final name = ((r['name'] as String?) ?? '').trim();
          if (name.isEmpty) continue;
          final menus = (r['menus'] as String? ?? '')
              .split(',')
              .map((m) => m.trim())
              .where((m) => m.isNotEmpty)
              .join(', ');
          out[name.toLowerCase()] = ItemSuggestion(
            name,
            menus.isEmpty ? 'in another menu' : 'in $menus',
            (r['last_price'] as num?)?.toDouble() ?? 0,
          );
        }
      } catch (_) {
        // Leave the other-menu suggestions out; adding still works.
      }
    }

    // Anything ever entered in an expense, even if it is not on a menu.
    try {
      final history = await repo.getItemHistory();
      for (final r in history) {
        final name = ((r['item_name'] as String?) ?? '').trim();
        if (name.isEmpty) continue;
        out.putIfAbsent(
          name.toLowerCase(),
          () => ItemSuggestion(
            name,
            'used in a past entry',
            (r['price'] as num?)?.toDouble() ?? 0,
          ),
        );
      }
    } catch (_) {
      // History unavailable; suggestions are optional.
    }

    return out.values.toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  }

  void _removeItem(CloudMenuItem item) {
    setState(() {
      _items.removeWhere((i) => i.id == item.id);
      _unbind(item);
      _priceControllers.remove(item.id)?.dispose();
      _qtyControllers.remove(item.id)?.dispose();
    });
    _onItemsChanged();
  }

  double get _total => _items.fold(0, (s, i) {
        final priceCtrl = _priceControllers[i.id!];
        final qtyCtrl = _qtyControllers[i.id!];
        if (priceCtrl == null || qtyCtrl == null) return s;
        return s + _parsePrice(priceCtrl) * _parseQty(qtyCtrl);
      });

  double get _enteredTotal =>
      double.tryParse(_totalCtrl.text.replaceAll(',', '')) ?? 0;

  /// True when the items add up to something other than the typed total.
  bool get _mismatch =>
      _enteredTotal > 0 && (_enteredTotal - _total).abs() >= 1;

  /// Divides [amount] across the item fields.
  ///
  /// Uses the split learned from previous entries of this menu so the numbers
  /// land close to what actually worked before. Items the history has never
  /// seen share whatever is left over. Rounding leftovers are folded into the
  /// biggest item, so the items always add up to exactly [amount].
  Future<void> _applySplit({bool announce = true}) async {
    final amount = _enteredTotal;
    if (_items.isEmpty) {
      if (announce) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('This menu has no items to split into')),
        );
      }
      return;
    }
    if (amount <= 0) {
      if (announce) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Enter the total amount first')),
        );
      }
      return;
    }

    setState(() => _splitting = true);

    // Make sure we're splitting with fresh history.
    var hints = _hints;
    if (_menu != null) {
      hints = await ref.read(repositoryProvider).getSplitHints(_menu!.id!);
    }

    final shares = hints?.shares ?? const <String, double>{};

    // Weight each item by its historical share. Items the history has never
    // seen (newly added ones) borrow the average share, so they still get a
    // sensible slice instead of being left at zero.
    final weights = <double>[];
    var known = 0.0;
    for (final item in _items) {
      final s = shares[item.name.trim().toLowerCase()] ?? 0.0;
      weights.add(s);
      known += s;
    }
    final knownCount = weights.where((w) => w > 0).length;
    if (knownCount == 0) {
      // No usable history — split evenly.
      for (int i = 0; i < weights.length; i++) {
        weights[i] = 1;
      }
    } else {
      final avgKnown = known / knownCount;
      for (int i = 0; i < weights.length; i++) {
        if (weights[i] <= 0) weights[i] = avgKnown;
      }
    }

    // Raw amounts, then round and fix the remainder so the sum is exact.
    final wsum = weights.fold<double>(0, (s, w) => s + w);
    final raw = weights.map((w) => amount * (w / wsum)).toList();
    final rounded = raw.map((v) => v.roundToDouble()).toList();
    var diff = amount - rounded.fold<double>(0, (s, v) => s + v);
    if (diff != 0) {
      var biggest = 0;
      for (int i = 1; i < rounded.length; i++) {
        if (rounded[i] > rounded[biggest]) biggest = i;
      }
      rounded[biggest] += diff;
      if (rounded[biggest] < 0) rounded[biggest] = 0;
    }

    for (int i = 0; i < _items.length; i++) {
      final item = _items[i];
      final qty = _parseQty(_qtyControllers[item.id]!);
      final divisor = qty > 0 ? qty : 1;
      // Round to 2dp so price x qty still lands on the exact amount.
      _priceControllers[item.id]!.text =
          (rounded[i] / divisor).toStringAsFixed(2);
    }

    _totalFocus.unfocus();
    if (!mounted) return;
    setState(() {
      _splitting = false;
      _hints = hints;
    });
    if (announce) {
      final how = (hints?.isExact ?? false)
          ? 'split like your last ${_menu?.name ?? 'entry'}'
          : (hints == null || hints.shares.isEmpty)
              ? 'split evenly'
              : 'split from your usual amounts';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${_items.length} items $how')),
      );
    }
  }

  Future<void> _save() async {
    if (_menu == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Choose a menu first')));
      return;
    }
    final entries = <ExpenseItem>[];
    for (final item in _items) {
      final price = _parsePrice(_priceControllers[item.id!]!);
      final qty = _parseQty(_qtyControllers[item.id!]!);
      entries.add(ExpenseItem(
        expenseId: 0,
        itemName: item.name,
        quantity: qty,
        price: price,
      ));
    }
    if (entries.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Nothing to save')));
      return;
    }

    // Written to Firestore so the whole mess sees it, not just this phone.
        //
        // The cook is the person whose turn it is, resolved from the shared
        // schedule. Falling back to the signed-in account matters: the owner may
        // record on anyone's behalf, and a member opening this screen is by
        // definition the person on turn.
        final cook = _cookEmailForToday() ??
            (ref.read(currentUserProvider).valueOrNull?.email ?? '');

        try {
          await saveExpense(
            ref: ref,
            date: monthKey(_date),
            menuName: _menu?.name ?? 'Entry',
            cookEmail: cook,
            items: [
              for (var i = 0; i < entries.length; i++)
                CloudExpenseItem(
                  id: newExpenseItemId(),
                  name: entries[i].itemName,
                  quantity: entries[i].quantity,
                  price: entries[i].price,
                ),
            ],
          );
        } on CloudMessage catch (e) {
          if (!mounted) return;
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(e.text)));
          return;
        }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Saved ${DateFormat.yMMMEd().format(_date)}')),
    );
    Navigator.pop(context, true);
  }

  /// Who is on turn for the day being entered, by email.
  ///
  /// Read from the shared schedule rather than the local rotation, so the meal is
  /// attributed to whoever the mess agrees is cooking.
  String? _cookEmailForToday() {
    final mess = ref.read(activeMessProvider).valueOrNull;
    final cook = mess?.turn.today;
    return cook?.email.trim().toLowerCase();
  }

  @override
  Widget build(BuildContext context) {
    final money = NumberFormat.currency(symbol: 'PKR ', decimalDigits: 0);

    return Scaffold(
      appBar: AppBar(
        title: const Text("Today's entry"),
        actions: [
          TextButton(
            onPressed: _save,
            child: const Text('SAVE',
                style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              children: [
                // Date picker
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
                      child: const Icon(Icons.calendar_today_outlined,
                          color: AppTheme.primary, size: 22),
                    ),
                    title: Text(DateFormat.yMMMEd().format(_date),
                        style: Theme.of(context).textTheme.titleMedium),
                    subtitle: const Text('Tap to change date'),
                    trailing: const Icon(Icons.edit_calendar, size: 20),
                    onTap: _pickDate,
                  ),
                ),
                const SizedBox(height: 12),

                // Menu picker
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
                      child: const Icon(Icons.restaurant_menu_outlined,
                          color: AppTheme.secondary, size: 22),
                    ),
                    title: Text(_menu?.name ?? 'Select a menu',
                        style: Theme.of(context).textTheme.titleMedium),
                    subtitle: const Text('Tap to change'),
                    trailing: const Icon(Icons.expand_more, size: 20),
                    onTap: _pickMenu,
                  ),
                ),
                const SizedBox(height: 10),

                // Whose turn / who is paying
                AppCard(
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: AppTheme.accent.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.person_outline,
                          color: AppTheme.accent, size: 22),
                    ),
                    title: Text(_member?.name ?? 'Who is cooking / paying?',
                        style: Theme.of(context).textTheme.titleMedium),
                    subtitle: Text(_member == null
                        ? 'Optional · tap to assign'
                        : 'Tap to change'),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_member != null)
                          IconButton(
                            icon: const Icon(Icons.person_off_outlined,
                                size: 20, color: AppTheme.textSecondary),
                            tooltip: 'Set to unassigned',
                            onPressed: _clearMember,
                          ),
                        const Icon(Icons.expand_more, size: 20),
                      ],
                    ),
                    onTap: _pickMember,
                  ),
                ),
                const SizedBox(height: 16),

                if (_menu != null) ...[
                  // ---- Total amount + auto split ----
                  AppCard(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: AppTheme.success.withOpacity(0.12),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Icon(Icons.payments_outlined,
                                  color: AppTheme.success, size: 20),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Total amount',
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleMedium),
                                  const SizedBox(height: 2),
                                  Text(
                                    _hintLine(),
                                    style: Theme.of(context).textTheme.bodySmall,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            Expanded(
                              child: ValueListenableBuilder<int>(
                                valueListenable: _tick,
                                builder: (context, _, __) => TextField(
                                  controller: _totalCtrl,
                                  focusNode: _totalFocus,
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                          decimal: true),
                                  textInputAction: TextInputAction.done,
                                  onSubmitted: (_) => _applySplit(),
                                  style: const TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.w800,
                                  ),
                                  decoration: InputDecoration(
                                    prefixText: 'PKR ',
                                    isDense: true,
                                    contentPadding: const EdgeInsets.symmetric(
                                        horizontal: 14, vertical: 16),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                    suffixIcon: _total > 0
                                        ? IconButton(
                                            tooltip: 'Use items total',
                                            icon: const Icon(Icons.sync,
                                                size: 20),
                                            onPressed: () => _totalCtrl.text =
                                                _total.toStringAsFixed(0),
                                          )
                                        : null,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            SizedBox(
                              height: 52,
                              child: FilledButton.icon(
                                onPressed:
                                    _splitting ? null : () => _applySplit(),
                                icon: _splitting
                                    ? const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                            strokeWidth: 2),
                                      )
                                    : const Icon(Icons.auto_awesome, size: 20),
                                label: const Text('Split'),
                                style: FilledButton.styleFrom(
                                  backgroundColor: AppTheme.primary,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 18),
                                  textStyle: const TextStyle(
                                      fontWeight: FontWeight.w700),
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (_mismatch) ...[
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              const Icon(Icons.info_outline,
                                  size: 15, color: AppTheme.accent),
                              const SizedBox(width: 6),
                              Expanded(
                                child: ValueListenableBuilder<int>(
                                  valueListenable: _tick,
                                  builder: (context, _, __) => Text(
                                    'Items add up to '
                                    '${money.format(_total)} — tap Split to match '
                                    '${money.format(_enteredTotal)}',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: AppTheme.accent,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  SectionHeader(
                    title: 'Items',
                    icon: Icons.list_alt,
                    action: TextButton.icon(
                      onPressed: _addOneOffItem,
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('Add item'),
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (_items.isEmpty)
                    EmptyItemsHint(
                      menuName: _menu?.name ?? 'This menu',
                      onPressed: _addOneOffItem,
                    )
                  else ...[
                    for (final item in _items)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: AppCard(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          children: [
                            Expanded(
                              flex: 3,
                              child: ValueListenableBuilder<int>(
                                valueListenable: _tick,
                                builder: (context, _, __) {
                                  final pc = _priceControllers[item.id];
                                  final qc = _qtyControllers[item.id];
                                  final q =
                                      double.tryParse(qc?.text ?? '') ?? 0;
                                  final p =
                                      double.tryParse(pc?.text ?? '') ?? 0;
                                  return Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Text(
                                        item.name,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                            fontWeight: FontWeight.w700),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        '${q.toStringAsFixed(q % 1 == 0 ? 0 : 1)} × ${money.format(p)} = ${money.format(q * p)}',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: AppTheme.textSecondary
                                              .withOpacity(0.95),
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  );
                                },
                              ),
                            ),
                            SizedBox(
                              width: 60,
                              child: TextField(
                                controller: _qtyCtrl(item),
                                textAlign: TextAlign.center,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                        decimal: true),
                                decoration: const InputDecoration(
                                  labelText: 'Qty',
                                  isDense: true,
                                  contentPadding: EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 12),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            SizedBox(
                              width: 90,
                              child: TextField(
                                controller: _priceCtrl(item),
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                        decimal: true),
                                decoration: const InputDecoration(
                                  labelText: 'Price',
                                  isDense: true,
                                  contentPadding: EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 12),
                                ),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.close, size: 20),
                              tooltip: 'Remove item',
                              onPressed: () => _removeItem(item),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
                  ],
                  const SizedBox(height: 4),
                  if (_items.isNotEmpty) ...[
                    AddItemButton(
                      onPressed: _addOneOffItem,
                      hint: 'Saved with this entry only unless you '
                          'save it to the menu',
                    ),
                    const SizedBox(height: 8),
                  ],
                ],
            ),
      bottomNavigationBar: _menu != null
          ? _EntryBottomBar(
              tick: _tick,
              total: _total,
              money: money,
              itemCount: _items.length,
              onSave: _save,
            )
          : null,
    );
  }

  /// Explains where the split numbers come from.
  String _hintLine() {
    if (_items.isEmpty) return 'This menu has no items';
    final h = _hints;
    if (h == null || h.shares.isEmpty) {
      return 'Type the total, then Split divides it evenly';
    }
    if (h.isExact && h.learnedFrom != null) {
      return 'Split follows your last ${_menu?.name ?? 'entry'} '
          '(${DateFormat('d MMM').format(h.learnedFrom!)})';
    }
    return 'Split follows your usual ${_menu?.name ?? ''} amounts';
  }
}

/// Sticky bottom bar: live total + Save (never covers the content).
class _EntryBottomBar extends StatelessWidget {
  final ValueNotifier<int> tick;
  final double total;
  final NumberFormat money;
  final int itemCount;
  final VoidCallback onSave;

  const _EntryBottomBar({
    required this.tick,
    required this.total,
    required this.money,
    required this.itemCount,
    required this.onSave,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
      decoration: BoxDecoration(
        color: Colors.white,
        border: const Border(top: BorderSide(color: AppTheme.divider)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 14,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Expanded(
              child: ValueListenableBuilder<int>(
                valueListenable: tick,
                builder: (context, _, __) => Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Total ($itemCount ${itemCount == 1 ? 'item' : 'items'})',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppTheme.textSecondary.withOpacity(0.95),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        money.format(total),
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.primary,
                          letterSpacing: -0.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 14),
            GradientButton(
              label: 'Save expense',
              icon: Icons.save,
              expanded: false,
              onPressed: onSave,
            ),
          ],
        ),
      ),
    );
  }
}

/// One row in the menu chooser: name, kind, and how many items it holds.
class _MenuChoiceTile extends StatelessWidget {
  final CloudMenu menu;
  final int itemCount;
  final bool selected;
  final VoidCallback onTap;

  const _MenuChoiceTile({
    required this.menu,
    required this.itemCount,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
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
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: menu.isDefault
                        ? [AppTheme.primary, AppTheme.primaryDark]
                        : [
                            AppTheme.secondary,
                            AppTheme.secondary.withOpacity(0.75)
                          ],
                  ),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  menu.isDefault ? Icons.restaurant : Icons.restaurant_outlined,
                  color: Colors.white,
                  size: 23,
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
                            menu.name,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 16,
                            ),
                          ),
                        ),
                        if (selected) ...[
                          const SizedBox(width: 8),
                          const Icon(Icons.check_circle,
                              size: 17, color: AppTheme.primary),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        AppBadge(
                          label: menu.isDefault ? 'Default' : 'Custom',
                          color: menu.isDefault
                              ? AppTheme.primary
                              : AppTheme.secondary,
                        ),
                        const SizedBox(width: 6),
                        AppBadge(
                          label: itemCount == 1 ? '1 item' : '$itemCount items',
                          color: itemCount == 0
                              ? AppTheme.textSecondary
                              : AppTheme.success,
                          icon: Icons.list_alt,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Icon(
                itemCount == 0
                    ? Icons.warning_amber_rounded
                    : Icons.chevron_right,
                size: 20,
                color: itemCount == 0
                    ? AppTheme.accent
                    : AppTheme.textSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
