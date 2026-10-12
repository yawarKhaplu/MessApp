/// The shared menu catalogue: what the mess cooks and what goes into it.
///
/// In Firestore rather than the local database, so everyone in the mess works
/// from the same menus instead of each phone keeping its own.
library;

/// One menu, and the items in it.
///
/// [items] are carried on the menu rather than fetched separately. That means one
/// read returns the whole catalogue, which matters because Firestore rules cannot
/// authorise a query that has to check membership by reading another document —
/// every read here is a single document read by full path instead.
class CloudMenu {
  final String id;
  final String name;

  /// Seeded by the app on first run, as a starting point rather than something
  /// the user chose.
  final bool isDefault;

  /// Sort position, so the list does not reshuffle between reads.
  final int order;

  final List<CloudMenuItem> items;

  const CloudMenu({
    required this.id,
    required this.name,
    this.isDefault = false,
    this.order = 0,
    this.items = const [],
  });

  /// Builds a menu from its stored form.
  factory CloudMenu.fromEntry(String id, Map<dynamic, dynamic> data) {
    final rawItems =
        Map<dynamic, dynamic>.from((data['items'] as Map?) ?? const {});
    final items = <CloudMenuItem>[];
    for (final entry in rawItems.entries) {
      final value = entry.value;
      if (value is Map) {
        items.add(CloudMenuItem.fromEntry(
          '${entry.key}',
          Map<dynamic, dynamic>.from(value),
        ));
      }
    }
    items.sort(CloudMenuItem.compare);

    return CloudMenu(
      id: id,
      name: '${data['name'] ?? ''}',
      isDefault: data['isDefault'] == true,
      order: (data['order'] as num?)?.toInt() ?? 0,
      items: items,
    );
  }

  Map<String, Object?> toEntry() => {
        'name': name,
        'isDefault': isDefault,
        'order': order,
        'items': {for (final i in items) i.id: i.toEntry()},
      };

  CloudMenu copyWith({String? name, List<CloudMenuItem>? items}) => CloudMenu(
        id: id,
        name: name ?? this.name,
        isDefault: isDefault,
        order: order,
        items: items ?? this.items,
      );

  /// Builds a menu from a fixed set of items, used for the starter menus.
  factory CloudMenu.withItems(
    String id,
    String name, {
    bool isDefault = false,
    int order = 0,
    required List<CloudMenuItem> items,
  }) =>
      CloudMenu(id: id, name: name, isDefault: isDefault, order: order, items: items);
}

/// One ingredient or dish inside a menu.
class CloudMenuItem {
  final String id;
  final String name;

  /// A typical price, used as a starting suggestion. Not the price actually
  /// paid, which lives on the expense.
  final double defaultPrice;

  final int order;

  const CloudMenuItem({
    required this.id,
    required this.name,
    this.defaultPrice = 0,
    this.order = 0,
  });

  factory CloudMenuItem.fromEntry(String id, Map<dynamic, dynamic> data) =>
      CloudMenuItem(
        id: id,
        name: '${data['name'] ?? ''}',
        defaultPrice: (data['defaultPrice'] as num?)?.toDouble() ?? 0,
        order: (data['order'] as num?)?.toInt() ?? 0,
      );

  Map<String, Object?> toEntry() => {
        'name': name,
        'defaultPrice': defaultPrice,
        'order': order,
      };

  CloudMenuItem copyWith({String? name, double? defaultPrice}) => CloudMenuItem(
        id: id,
        name: name ?? this.name,
        defaultPrice: defaultPrice ?? this.defaultPrice,
        order: order,
      );

  /// Explicit order first, then alphabetically so the list is stable.
  static int compare(CloudMenuItem a, CloudMenuItem b) {
    final byOrder = a.order.compareTo(b.order);
    if (byOrder != 0) return byOrder;
    return a.name.toLowerCase().compareTo(b.name.toLowerCase());
  }
}

/// The whole catalogue, parsed from the mess document.
class MenuCatalogue {
  final List<CloudMenu> menus;

  const MenuCatalogue(this.menus);

  const MenuCatalogue.empty() : menus = const [];

  bool get isEmpty => menus.isEmpty;

  /// How many items each menu holds, so the menu list can show counts without a
  /// second read per menu.
  Map<String, int> get itemCounts =>
      {for (final m in menus) m.id: m.items.length};

  CloudMenu? byId(String id) {
    for (final m in menus) {
      if (m.id == id) return m;
    }
    return null;
  }
}

/// Orders menus the way they are shown.
///
/// Applied after every edit, not only when reading. Without it a reordered menu
/// would keep the order the list happened to be built in, so a drag would appear
/// to work and then silently revert on the next read.
int compareMenus(CloudMenu a, CloudMenu b) {
  final byOrder = a.order.compareTo(b.order);
  if (byOrder != 0) return byOrder;
  return a.name.toLowerCase().compareTo(b.name.toLowerCase());
}

/// Returns the menus in display order. Does not modify the input.
List<CloudMenu> sortMenus(List<CloudMenu> menus) =>
    [...menus]..sort(compareMenus);

/// Menu ids are generated rather than auto-incremented, because there is no
/// autoincrement in Firestore and the id has to be stable across devices.
///
/// A counter is mixed into the timestamp as well, so two ids created in the same
/// microsecond still differ. Saving both under one key would silently drop one
/// of them.
int _idCounter = 0;

String newMenuId() => 'm${DateTime.now().microsecondsSinceEpoch}'
    '${(_idCounter++).toString().padLeft(3, '0')}';

String newMenuItemId() => 'i${DateTime.now().microsecondsSinceEpoch}'
    '${(_idCounter++).toString().padLeft(3, '0')}';

/// Seed menus for a brand-new mess, so it is not an empty screen.
///
/// Marked as defaults so the UI can offer them without the mess having to type
/// them in first. Nothing is written anywhere until the owner saves.
List<CloudMenu> starterMenus() {
  CloudMenuItem item(String id, String name, double price) =>
      CloudMenuItem(id: id, name: name, defaultPrice: price);

  return [
    CloudMenu.withItems(
      'pulao',
      'Pulao',
      isDefault: true,
      order: 0,
      items: [
        item('p_rice', 'Rice', 0),
        item('p_masala', 'Masala', 0),
        item('p_tomato', 'Tomato', 0),
        item('p_onion', 'Onion', 0),
      ],
    ),
    CloudMenu.withItems(
      'karahi',
      'Karahi',
      isDefault: true,
      order: 1,
      items: [
        item('k_mutton', 'Mutton', 0),
        item('k_tomato', 'Tomato', 0),
        item('k_onion', 'Onion', 0),
        item('k_masala', 'Masala', 0),
        item('k_ginger', 'Ginger', 0),
      ],
    ),
  ];
}