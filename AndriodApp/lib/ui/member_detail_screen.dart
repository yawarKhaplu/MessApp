import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../data/models.dart';
import '../providers.dart';
import '../ui/theme.dart';
import '../ui/widgets/app_widgets.dart';
import 'widgets/pick_date.dart';
import 'widgets/text_input_dialog.dart';

/// Member detail (PRD 6.4): payments history, add payment,
/// monthly share for the selected month.
class MemberDetailScreen extends ConsumerStatefulWidget {
  final Member member;
  final DateTime month;

  const MemberDetailScreen({super.key, required this.member, required this.month});

  @override
  ConsumerState<MemberDetailScreen> createState() =>
      _MemberDetailScreenState();
}

class _MemberDetailScreenState extends ConsumerState<MemberDetailScreen> {
  late String _month;
  int? _collectionId;
  double _amountDue = 0;
  double _paid = 0;
  List<Payment> _payments = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _month = monthKey(widget.month);
    _load();
  }

  Future<void> _load() async {
    final repo = ref.read(repositoryProvider);
    final collection = await repo.getCollection(widget.member.id!, _month);
    final payments = await repo.getPayments(collection.id!);
    if (!mounted) return;
    setState(() {
      _collectionId = collection.id;
      _amountDue = collection.amountDue;
      _paid = payments.fold<double>(0, (s, p) => s + p.amount);
      _payments = payments;
      _loading = false;
    });
  }

  double get _remaining {
    final v = _amountDue - _paid;
    return v > 0 ? v : 0;
  }

  Future<void> _addPayment() async {
    final money = NumberFormat.currency(symbol: 'PKR ', decimalDigits: 0);
    final remaining = _remaining;

    // Pre-fill what this member still owes, so the usual case is one tap.
    // The field stays editable for a custom or part payment.
    final quicks = <double>[];
    if (remaining > 0) {
      quicks.add(remaining);
      final half = remaining / 2;
      if (half >= 1) quicks.add(half);
    }

    final value = await showDialog<String>(
      context: context,
      builder: (_) => TextInputDialog(
        title: 'Add payment',
        hint: 'Amount paid',
        numeric: true,
        confirmLabel: 'Add',
        initialValue: remaining > 0 ? remaining.toStringAsFixed(0) : '',
        subtitle: remaining > 0
            ? '${widget.member.name} still owes ${money.format(remaining)} '
                'this month — change it if they are paying something else.'
            : '${widget.member.name} has nothing outstanding this month.',
        quickAmounts: quicks,
      ),
    );
    if (value == null) return;
    final amount = double.tryParse(value.replaceAll(',', ''));
    if (amount == null || amount <= 0) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Enter a valid amount')));
      }
      return;
    }

    // Let the user pick the payment date (defaults to today).
    DateTime date = DateTime.now();
    if (mounted) {
      final picked = await pickClampedDate(
        context,
        initialDate: date,
        firstDate: DateTime(2020),
        lastDate: DateTime.now(),
      );
      if (picked != null) date = picked;
    }

    await ref.read(repositoryProvider).addPayment(
          collectionId: _collectionId!,
          amount: amount,
          date: date,
        );
    await refreshTotals(ref);
    ref.invalidate(monthCollectionsProvider);
    await _load();
  }

  Future<void> _setShare() async {
    final value = await showDialog<String>(
      context: context,
      builder: (_) => TextInputDialog(
        title: 'Monthly share',
        hint: 'e.g. 2000',
        initialValue: _amountDue.toStringAsFixed(0),
        numeric: true,
      ),
    );
    if (value != null) {
      final amount = double.tryParse(value.replaceAll(',', '')) ?? 0;
      await ref
          .read(repositoryProvider)
          .setMonthlyShare(widget.member.id!, _month, amount);
      ref.invalidate(monthCollectionsProvider);
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final money =
        NumberFormat.currency(symbol: 'PKR ', decimalDigits: 0);
    final remaining = _amountDue - _paid;

    return Scaffold(
      appBar: AppBar(title: Text(widget.member.name)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // Summary card
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [AppTheme.secondary, Color(0xFF00695C)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                        color: AppTheme.secondary.withOpacity(0.3),
                        blurRadius: 20,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      Text(
                        DateFormat('MMMM yyyy').format(widget.month),
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.85),
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          _col('Share', money.format(_amountDue), Colors.white),
                          _col('Paid', money.format(_paid), Colors.white),
                          _col(
                            'Remaining',
                            money.format(remaining),
                            remaining > 0 ? Colors.white70 : Colors.white,
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _setShare,
                              icon: const Icon(Icons.edit, size: 18),
                              label: const Text('Set share'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.white,
                                side: const BorderSide(color: Colors.white54),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14)),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: FilledButton.icon(
                              onPressed: _addPayment,
                              icon: const Icon(Icons.add, size: 18),
                              label: const Text('Add payment'),
                              style: FilledButton.styleFrom(
                                backgroundColor: Colors.white,
                                foregroundColor: AppTheme.secondary,
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14)),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                const SectionHeader(
                    title: 'Payment history', icon: Icons.receipt_long),
                const SizedBox(height: 8),
                if (_payments.isEmpty)
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text('No payments recorded yet.'),
                    ),
                  )
                else
                  for (final p in _payments)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: AppCard(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          children: [
                            Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: AppTheme.success.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(Icons.payment_outlined,
                                  color: AppTheme.success, size: 20),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(money.format(p.amount),
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                          fontSize: 15)),
                                  const SizedBox(height: 2),
                                  Text(DateFormat.yMMMEd().format(p.date),
                                      style:
                                          Theme.of(context).textTheme.bodySmall),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
              ],
            ),
    );
  }

  Widget _col(String label, String value, Color color) => Column(
        children: [
          Text(label,
              style: TextStyle(
                  color: color.withOpacity(0.8), fontSize: 12)),
          const SizedBox(height: 4),
          Text(value,
              style: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: color,
                  fontSize: 16)),
        ],
      );
}
