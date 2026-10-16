/// Monthly collection data shared across the mess.
///
/// Lives in Firestore rather than the local database so that whoever records a
/// payment and whoever is shown the figure are looking at the same numbers.
library;

/// One month's collection for one member: the share due and what was paid
/// against it.
class MemberCollection {
  final String email;
  final String month;

  /// The owner's set monthly share. Zero means none has been set.
  final double amountDue;

  /// Newest first, which is how the history is shown.
  final List<CloudPayment> payments;

  const MemberCollection({
    required this.email,
    required this.month,
    required this.amountDue,
    this.payments = const [],
  });

  double get paid => payments.fold(0.0, (sum, p) => sum + p.amount);

  double get remaining => amountDue - paid;

  /// True once the share is set and nothing is outstanding.
  bool get isSettled => amountDue > 0 && remaining <= 0;

  /// True when the owner has not set a share yet, which is different from a
  /// share of zero and must not be shown as "paid".
  bool get hasNoShare => amountDue <= 0;
}

/// One payment recorded against a member's month.
class CloudPayment {
  final String id;
  final double amount;

  /// Parsed from the stored `yyyy-MM-dd`. Null when the stored value is missing
  /// or malformed, so one bad row cannot stop the history from being shown.
  final DateTime? date;

  /// Who recorded it. Kept so a mess can see who is keeping the books.
  final String? recordedBy;

  const CloudPayment({
    required this.id,
    required this.amount,
    required this.date,
    this.recordedBy,
  });
}

/// Key for a member's collection document.
///
/// Email is the identifier every member already shares. A Firebase uid is not,
/// because it does not exist until that person signs in — which is the same
/// reason the mess roster is keyed by email.
String collectionDocId(String email, String month) =>
    '${email.trim().toLowerCase()}__$month';