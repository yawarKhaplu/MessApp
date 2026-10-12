import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../data/models.dart';
import '../providers.dart';
import '../services/collection_cloud_service.dart';
import '../services/mess_cloud_service.dart';
import '../ui/theme.dart';
import '../ui/widgets/app_widgets.dart';
import 'widgets/pick_date.dart';
import 'widgets/text_input_dialog.dart';

/// Member detail (PRD 6.4): payments history, add payment, monthly share.
///
/// Read-only for anyone who is not the owner. The owner records what was
/// collected and sets each member's share; members see the figures but cannot
/// change them, so the numbers a person is shown cannot be altered by the person
/// being shown them to.
class MemberDetailScreen extends ConsumerStatefulWidget {
  /// The person's display name, and the roster address their collection is
  /// stored under.
  ///
  /// Both are passed directly rather than a whole member record, because the
  /// figures now come from the shared roster. Passing a local member row would
  /// reintroduce the second source of truth this screen no longer needs.
  final String name;
  final String? email;
  final DateTime month;

  const MemberDetailScreen({
    super.key,
    required this.name,
    required this.email,
    required this.month,
  });

  @override
  ConsumerState<MemberDetailScreen> createState() =>
      _MemberDetailScreenState();
}

class _MemberDetailScreenState extends ConsumerState<MemberDetailScreen> {
  late String _month;
  MemberCollection? _collection;
  bool _loading = true;

  /// The roster address for this person, normalised. A field rather than a local
  /// so the write paths below can use it; a member row with no email simply has
  /// no collection to record against.
  String get _email => (widget.email ?? '').trim().toLowerCase();

  double get _amountDue => _collection?.amountDue ?? 0;
  double get _paid => _collection?.paid ?? 0;
  List<CloudPayment> get _payments => _collection?.payments ?? const [];

  @override
  void initState() {
    super.initState();
    _month = monthKey(widget.month);
    _load();
  }

  Future<void> _load() async {
    final mess = ref.read(activeMessProvider).valueOrNull;
    if (mess == null || _email.isEmpty) {
      if (mounted) setState(() => _loading = false);
      return;
    }

    // Read from Firestore, so this screen shows the same figures as everyone
    // else rather than whatever happens to be in this device's database.
    final collection = await ref
        .read(messCloudServiceProvider)
        .collectionFor(mess.id, _email, _month);

    if (!mounted) return;
    setState(() {
      _collection = collection;
      _loading = false;
    });
  }

  /// Refreshes both this screen and the Collection tab behind it.
  void _refreshShared(String month) {
    ref.invalidate(sharedCollectionsProvider(month));
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
            ? '${widget.name} still owes ${money.format(remaining)} '
                'this month — change it if they are paying something else.'
            : '${widget.name} has nothing outstanding this month.',
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

    // Written to Firestore, so the payment is the same for everyone in the mess
    // and only the owner can record it — enforced by the rules, not just here.
    final mess = ref.read(activeMessProvider).valueOrNull;
    if (mess == null) return;

    try {
      await ref.read(messCloudServiceProvider).addCollectionPayment(
            messId: mess.id,
            email: _email,
            month: _month,
            amount: amount,
            date: monthKey(date),
          );
    } on CloudMessage catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.text)));
      }
      return;
    }

    _refreshShared(_month);
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
    if (value == null || !mounted) return;

    final amount = double.tryParse(value.replaceAll(',', '')) ?? 0;
    final mess = ref.read(activeMessProvider).valueOrNull;
    if (mess == null) return;

    try {
      await ref.read(messCloudServiceProvider).setMonthlyShare(
            messId: mess.id,
            email: _email,
            month: _month,
            amount: amount,
          );
    } on CloudMessage catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.text)));
      return;
    }

    _refreshShared(_month);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final money =
        NumberFormat.currency(symbol: 'PKR ', decimalDigits: 0);
    final remaining = _amountDue - _paid;

    // Collections are the owner's record to keep. Read from the membership
    // document rather than cached, so it is correct on first open.
    final isOwner =
        ref.watch(activeMessProvider).valueOrNull?.isOwner ?? false;

    return Scaffold(
      appBar: AppBar(title: Text(widget.name)),
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
                      // Only the owner records collections. A member sees the
                      // figures and nothing else — no way to set a share or log
                      // a payment against themselves.
                      if (isOwner) ...[
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: _setShare,
                                icon: const Icon(Icons.edit, size: 18),
                                label: const Text('Set share'),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Colors.white,
                                  side:
                                      const BorderSide(color: Colors.white54),
                                  shape: RoundedRectangleBorder(
                                      borderRadius:
                                          BorderRadius.circular(14)),
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
                                      borderRadius:
                                          BorderRadius.circular(14)),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ] else
                        // Said plainly, so a missing button does not read as a
                        // bug or as their account being broken.
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 11),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.10),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Row(
                            children: [
                              Icon(Icons.lock_outline,
                                  size: 16, color: Colors.white70),
                              SizedBox(width: 9),
                              Expanded(
                                child: Text(
                                  'Only the mess owner records collections and '
                                  'payments. You can see what is owed.',
                                  style: TextStyle(
                                    fontSize: 12,
                                    height: 1.35,
                                    color: Colors.white70,
                                  ),
                                ),
                              ),
                            ],
                          ),
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
                                  Text(
                                    p.date == null
                                        ? 'no date'
                                        : DateFormat.yMMMEd().format(p.date!),
                                    style:
                                        Theme.of(context).textTheme.bodySmall,
                                  ),
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
