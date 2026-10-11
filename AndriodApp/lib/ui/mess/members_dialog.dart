import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers.dart';
import '../../services/mess_cloud_service.dart';
import '../theme.dart';

/// Bottom sheet for adding a person to the mess by email.
///
/// A seat is created under the email address, because the person's Firebase uid
/// is unknown until they sign in. When they do, they are matched on that same
/// email and the seat is claimed with their real uid.
Future<void> showAddMemberDialog(
  BuildContext context,
  WidgetRef ref,
  String messId,
) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => Padding(
      padding: EdgeInsets.only(
        left: 22,
        right: 22,
        bottom: MediaQuery.viewInsetsOf(context).bottom + 26,
      ),
      child: _AddMemberSheet(messId: messId),
    ),
  );
}

class _AddMemberSheet extends ConsumerStatefulWidget {
  const _AddMemberSheet({required this.messId});

  final String messId;

  @override
  ConsumerState<_AddMemberSheet> createState() => _AddMemberSheetState();
}

class _AddMemberSheetState extends ConsumerState<_AddMemberSheet> {
  final _controller = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    final email = _controller.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a valid email address.')),
      );
      return;
    }

    setState(() => _busy = true);
    try {
      await ref.read(messCloudServiceProvider).addMember(
            messId: widget.messId,
            email: email,
          );
      // The roster is stored on the mess document, so re-read it to show the
      // new seat straight away.
      ref.invalidate(activeMessProvider);
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Added $email to the mess.')),
      );
    } on CloudMessage catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.text)),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Add by email',
            style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        Text(
          'They get a seat in this mess immediately, and sign in whenever '
          'they are ready.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 18),
        TextField(
          controller: _controller,
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.done,
          autocorrect: false,
          onSubmitted: (_) => _add(),
          decoration: InputDecoration(
            labelText: 'Email address',
            hintText: 'roommate@gmail.com',
            prefixIcon: const Icon(Icons.alternate_email, size: 20),
            filled: true,
            fillColor: AppTheme.surface,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: AppTheme.divider),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: AppTheme.divider),
            ),
          ),
        ),
        const SizedBox(height: 18),
        SizedBox(
          width: double.infinity,
          height: 50,
          child: FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppTheme.primary,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(13),
              ),
            ),
            onPressed: _busy ? null : _add,
            child: _busy
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2.4, color: Colors.white),
                  )
                : const Text('Add to mess'),
          ),
        ),
      ],
    );
  }
}
