import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../data/models.dart';
import '../providers.dart';
import 'theme.dart';
import 'widgets/app_widgets.dart';

/// Lets the user decide who takes the next bari.
///
/// The list is the cooking order: whoever is on top of the list cooks today,
/// the one below cooks the next day, and so on. Drag to reorder, or use the
/// star to hand the bari to somebody further down.
class RotationOrderScreen extends ConsumerStatefulWidget {
  const RotationOrderScreen({super.key});

  @override
  ConsumerState<RotationOrderScreen> createState() =>
      _RotationOrderScreenState();
}

class _RotationOrderScreenState extends ConsumerState<RotationOrderScreen> {
  List<Member> _order = [];
  bool _loading = true;
  DateTime? _lastCooked;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final repo = ref.read(repositoryProvider);
    final order = await repo.getRotationOrder();
    final last = await repo.getLastRecordedCook();
    if (!mounted) return;
    setState(() {
      _order = order;
      _lastCooked = last?.date;
      _loading = false;
    });
  }

  Future<void> _save() async {
    await ref
        .read(repositoryProvider)
        .setRotationOrder(_order.map((m) => m.id!).toList());
    await refreshTotals(ref);
  }

  void _move(int oldIndex, int newIndex) {
    setState(() {
      if (newIndex > oldIndex) newIndex -= 1;
      final m = _order.removeAt(oldIndex);
      _order.insert(newIndex, m);
    });
    _save();
  }

  Future<void> _giveBari(Member m) async {
    await ref.read(repositoryProvider).setBari(DateTime.now(), m);
    await refreshTotals(ref);
    if (!mounted) return;
    // Move them to the top so the list matches who cooks today.
    setState(() {
      _order.removeWhere((x) => x.id == m.id);
      _order.insert(0, m);
    });
    await _save();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${m.name} has the bari today')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Cooking order')),
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
                                'Drag to change who cooks next. The top of the '
                                'list has today\'s bari.',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (_lastCooked != null)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                        child: Text(
                          'Last cooked: ${DateFormat('d MMM yyyy').format(_lastCooked!)}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    Expanded(
                      child: ReorderableListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                        itemCount: _order.length,
                        onReorder: _move,
                        buildDefaultDragHandles: false,
                        itemBuilder: (context, i) {
                          final m = _order[i];
                          return Padding(
                            key: ValueKey(m.id),
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
                                          m.name,
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
                                  if (i != 0)
                                    IconButton(
                                      tooltip: 'Give today\'s bari',
                                      icon: const Icon(Icons.star_outline,
                                          size: 20),
                                      onPressed: () => _giveBari(m),
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
    );
  }
}