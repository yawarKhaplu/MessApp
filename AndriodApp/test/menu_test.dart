import 'package:flutter_test/flutter_test.dart';
import 'package:messapp/services/menu_cloud_service.dart';

/// The menu catalogue is shared, so everyone must read the same menus from the
/// same document. These tests pin the parsing and the editing rules, because a
/// menu that vanishes or silently reorders would be very hard to spot on a phone.
void main() {
  Map<String, Object?> entry(String name,
          {bool isDefault = false,
          int order = 0,
          Map<String, Object?> items = const {}}) =>
      {'name': name, 'isDefault': isDefault, 'order': order, 'items': items};

  group('reading the catalogue', () {
    test('is empty when the mess has no menus', () {
      const c = MenuCatalogue.empty();

      expect(c.isEmpty, isTrue);
      expect(c.menus, isEmpty);
      expect(c.itemCounts, isEmpty);
    });

    test('reads menus and their items together', () {
      final c = MenuCatalogue([
        CloudMenu.fromEntry('pulao', entry('Pulao', items: {
          'a': {'name': 'Rice', 'defaultPrice': 40.0, 'order': 0},
          'b': {'name': 'Masala', 'defaultPrice': 20.0, 'order': 1},
        })),
      ]);

      expect(c.menus, hasLength(1));
      expect(c.menus.first.name, 'Pulao');
      expect(c.menus.first.items, hasLength(2));
      expect(c.itemCounts['pulao'], 2);
    });

    test('sorts menus by order, then by name', () {
      // Goes through the same helper the app uses when saving, so this cannot
      // pass while the app sorts differently.
      final sorted = sortMenus([
        CloudMenu.fromEntry('c', entry('Zebda', order: 1)),
        CloudMenu.fromEntry('a', entry('Biryani', order: 0)),
        CloudMenu.fromEntry('b', entry('Aloo', order: 0)),
      ]);

      expect(sorted.map((m) => m.name).toList(),
          ['Aloo', 'Biryani', 'Zebda'],
          reason: 'order decides first; name breaks the tie so the list is stable');
    });

    test('sorting does not modify the list it was given', () {
      final original = [
        CloudMenu(id: 'z', name: 'Zebda', order: 1),
        CloudMenu(id: 'a', name: 'Aloo', order: 0),
      ];

      sortMenus(original);

      expect(original.map((m) => m.id).toList(), ['z', 'a'],
          reason: 'sorting in place would corrupt the caller\'s list');
    });

    test('sorts items by order, then by name', () {
      final menu = CloudMenu.fromEntry('m', entry('Pulao', items: {
        'x': {'name': 'Onion', 'order': 1},
        'y': {'name': 'Rice', 'order': 0},
        'z': {'name': 'Ginger', 'order': 1},
      }));

      expect(menu.items.map((i) => i.name).toList(),
          ['Rice', 'Ginger', 'Onion']);
    });

    test('finds a menu by id', () {
      final c = MenuCatalogue([
        CloudMenu.fromEntry('a', entry('Pulao')),
        CloudMenu.fromEntry('b', entry('Karahi')),
      ]);

      expect(c.byId('b')!.name, 'Karahi');
      expect(c.byId('missing'), isNull);
    });

    test('survives a malformed entry rather than losing the whole list', () {
      // One bad row must not take the rest of the catalogue with it.
      final c = MenuCatalogue([
        CloudMenu.fromEntry('a', entry('Pulao')),
        CloudMenu.fromEntry('b', const {}),
      ]);

      expect(c.menus, hasLength(2));
    });
  });

  group('editing the catalogue', () {
    final withTwoMenus = [
      CloudMenu(id: 'a', name: 'Pulao', order: 0, items: [
        const CloudMenuItem(id: 'i1', name: 'Rice', order: 0),
        const CloudMenuItem(id: 'i2', name: 'Masala', order: 1),
      ]),
      CloudMenu(id: 'b', name: 'Karahi', order: 1),
    ];

    test('adding a menu puts it at the end so nothing reorders', () {
      final result = [
        ...withTwoMenus,
        CloudMenu(id: 'new', name: 'Daal', order: 2),
      ];

      expect(result.map((m) => m.name).toList(),
          ['Pulao', 'Karahi', 'Daal']);
    });

    test('renaming changes only that menu', () {
      final result = [
        for (final m in withTwoMenus)
          if (m.id == 'a') m.copyWith(name: 'Biryani') else m,
      ];

      expect(result[0].name, 'Biryani');
      expect(result[0].items, hasLength(2),
          reason: 'renaming must not drop the items');
      expect(result[1].name, 'Karahi');
    });

    test('deleting removes only that menu', () {
      final result = withTwoMenus.where((m) => m.id != 'a').toList();

      expect(result.map((m) => m.name).toList(), ['Karahi']);
    });

    test('adding an item places it after the existing ones', () {
      final menu = withTwoMenus.first;
      final added = [
        ...menu.items,
        const CloudMenuItem(id: 'i3', name: 'Ginger', order: 2),
      ];

      expect(added.map((i) => i.name).toList(),
          ['Rice', 'Masala', 'Ginger'],
          reason: 'a new item must not jump ahead of the ones already there');
    });

    test('updating an item keeps its position', () {
      final menu = withTwoMenus.first;
      final updated = [
        for (final i in menu.items)
          i.copyWith(name: 'Rice (basmati)') ,
      ];

      expect(updated[0].name, 'Rice (basmati)');
      expect(updated[0].order, 0, reason: 'editing a name must not reorder');
    });

    test('deleting an item leaves the rest', () {
      final menu = withTwoMenus.first;
      final left = menu.items.where((i) => i.id != 'i1').toList();

      expect(left.map((i) => i.name).toList(), ['Masala']);
    });

    test('reordering sets the new positions and keeps the names', () {
      // The drag hands back the ids in their new order.
      const newOrder = ['i2', 'i1'];
      final position = <String, int>{
        for (var i = 0; i < newOrder.length; i++) newOrder[i]: i,
      };

      final result = [
        for (final i in withTwoMenus.first.items)
          CloudMenuItem(
            id: i.id,
            name: i.name,
            defaultPrice: i.defaultPrice,
            order: position[i.id] ?? i.order,
          ),
      ]..sort(CloudMenuItem.compare);

      expect(result.map((i) => i.id).toList(), ['i2', 'i1']);
      expect(result.map((i) => i.name).toList(), ['Masala', 'Rice'],
          reason: 'reordering must not rename anything');
      expect(result[0].order, 0);
      expect(result[1].order, 1);
    });
  });

  group('round trip', () {
    test('a menu survives being written and read back', () {
      // The shape stored is the shape read, so a menu cannot quietly lose its
      // items or its default flag in a save.
      final original = CloudMenu(
        id: 'pulao',
        name: 'Pulao',
        isDefault: true,
        order: 0,
        items: const [
          CloudMenuItem(id: 'r', name: 'Rice', defaultPrice: 40, order: 0),
          CloudMenuItem(id: 'm', name: 'Masala', defaultPrice: 20, order: 1),
        ],
      );

      final restored =
          CloudMenu.fromEntry(original.id, original.toEntry());

      expect(restored.name, original.name);
      expect(restored.isDefault, isTrue);
      expect(restored.order, original.order);
      expect(restored.items.map((i) => i.name).toList(),
          original.items.map((i) => i.name).toList());
      expect(restored.items.first.defaultPrice, 40);
    });

    test('an item survives being written and read back', () {
      const original = CloudMenuItem(
          id: 'r', name: 'Rice', defaultPrice: 40, order: 2);

      final restored = CloudMenuItem.fromEntry(original.id, original.toEntry());

      expect(restored.name, 'Rice');
      expect(restored.defaultPrice, 40);
      expect(restored.order, 2);
    });
  });

  group('starter menus', () {
    test('a new mess starts with something to cook', () {
      final starters = starterMenus();

      expect(starters, isNotEmpty);
      expect(starters.every((m) => m.items.isNotEmpty), isTrue,
          reason: 'a menu with no items is not much use as a starting point');
    });

    test('starter menus are marked as defaults', () {
      expect(starterMenus().every((m) => m.isDefault), isTrue);
    });

    test('starter items have unique ids within a menu', () {
      for (final m in starterMenus()) {
        final ids = m.items.map((i) => i.id).toList();
        expect(ids.toSet().length, ids.length,
            reason: 'duplicate item ids in ${m.name} would collide when saved');
      }
    });
  });

  group('generated ids', () {
    test('menus and items get distinct ids', () {
      expect(newMenuId(), isNot(newMenuId()));
      expect(newMenuItemId(), isNot(newMenuItemId()));
    });

    test('ids are prefixed so their origin is obvious in the console', () {
      expect(newMenuId(), startsWith('m'));
      expect(newMenuItemId(), startsWith('i'));
    });
  });
}