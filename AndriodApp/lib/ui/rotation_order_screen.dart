import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers.dart';
import '../services/mess_cloud_service.dart';
import 'theme.dart';
import 'widgets/app_widgets.dart';

/// Lets the owner decide who takes the next bari.
///
/// The order is the shared cooking order: whoever is on top cooks today, the one
/// below cooks the next day. It reads from the mess document rather than the
/// local database, so the whole mess sees the same order and reordering it
/// changes it for everyone. Owner only.
class RotationOrderScreen extends ConsumerStatefulWidget {
  const RotationOrderScreen({super.key});

  @override
  ConsumerState<RotationOrderScreen> createState() =>
      _RotationOrderScreenState();
}

class _RotationOrderScreenState extends ConsumerState<RotationOrderScreen> {
  /// The order being edited. Starts from the shared one and diverges locally
  /// until saved, so a drag does not fire a write per pixel of movement.
  List<MessMember> _order = [];
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    final turn = ref.read(messTurnProvider);
    if (!mounted) return;
    setState(() {
      _order = List<MessMember>.from(turn.order);
      _loading = false;
    });
  }

  /// Writes the new order and the anchor to the mess document.
  Future<void> _save({String? anchorEmail}) async {
    final mess = ref.read(activeMessProvider).valueOrNull;
    if (mess == null || _order.isEmpty) return;

    setState(() => _saving = true);
    try {
      await ref.read(messCloudServiceProvider).setTurn(
            messId: mess.id,
            // Re-anchoring to today keeps whoever is on top as today's cook, so
            // reordering the list does not silently move the turn backwards.
            anchorDate: DateTime.now(),
            anchorEmail: anchorEmail ?? _order.first.email,
            order: _order.map((m) => m.email).toList(),
          );
      ref.invalidate(activeMessProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cooking order saved for the whole mess')),
      );
    } on CloudMessage catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.text)),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _move(int oldIndex, int newIndex) {
    setState(() {
      if (newIndex > oldIndex) newIndex -= 1;
      final m = _order.removeAt(oldIndex);
      _order.insert(newIndex, m);
    });
    _save();
  }

  Future<void> _giveBari(MessMember m) async {
    // Move them to the top so the list matches who cooks today, then anchor on
    // them rather than on whoever happens to be first.
    setState(() {
      _order.removeWhere((x) => x.email.toLowerCase() == m.email.toLowerCase());
      _order.insert(0, m);
    });
    await _save(anchorEmail: m.email);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${m.name ?? m.email} has the bari today')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final mess = ref.watch(activeMessProvider).valueOrNull;
    final isOwner = mess?.isOwner ?? false;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Cooking order'),
        actions: [
          if (_saving)
            const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _order.isEmpty
              ? const Center(child: Text('Add members first'))
              : Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                      child: AppCard(
                        child: Row(
                          children: [
                            const Icon(Icons.lightbulb_outline,
                                color: AppTheme.accent, size: 20),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                isOwner
                                    ? 'Drag to change who cooks next. The top of '
                                        'the list has today\'s bari.'
                                    : 'This is the cooking order for the mess. '
                                        'Only the owner can change it.',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Expanded(
                      child: ReorderableListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                        itemCount: _order.length,
                        // Reordering is an owner action; a member sees the order
                        // as a read-only schedule.
                        onReorder: isOwner ? _move : (_, __) {},
                        buildDefaultDragHandles: false,
                        itemBuilder: (context, i) {
                          final m = _order[i];
                          return Padding(
                            key: ValueKey(m.email),
                            padding: const EdgeInsets.only(bottom: 10),
                            child: AppCard(
                              padding: const EdgeInsets.all(12),
                              child: Row(
                                children: [
                                  Container(
                                    width: 34,
                                    height: 34,
                                    alignment: Alignment.center,
                                    decoration: BoxDecoration(
                                      color: i == 0
                                          ? AppTheme.secondary
                                          : AppTheme.primary.withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(11),
                                    ),
                                    child: i == 0
                                        ? const Icon(Icons.restaurant,
                                            color: Colors.white, size: 18)
                                        : Text(
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
                                          m.name ?? m.email,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                              fontWeight: FontWeight.w700),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          i == 0
                                              ? "Today's bari"
                                              : 'Cooks in $i ${i == 1 ? 'day' : 'days'}',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: i == 0
                                                ? AppTheme.secondary
                                                : AppTheme.textSecondary,
                                            fontWeight: i == 0
                                                ? FontWeight.w700
                                                : FontWeight.w500,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (i != 0 && isOwner)
                                    IconButton(
                                      tooltip: 'Give today\'s bari',
                                      icon: const Icon(Icons.star_outline,
                                          size: 20),
                                      onPressed: () => _giveBari(m),
                                    ),
                                  if (isOwner)
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
    );
  }
}