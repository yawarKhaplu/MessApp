import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Roles a person can hold in a mess.
enum MessRole {
  owner,
  member;

  static MessRole parse(String? value) =>
      value == 'owner' ? MessRole.owner : MessRole.member;

  String get wire => name;
}

/// One person's place in a mess.
class MessMember {
  /// Empty until this person signs in for the first time. A Firebase uid cannot
  /// be known before that, which is why seats are keyed by email.
  final String uid;
  final String email;
  final String? name;
  final MessRole role;

  const MessMember({
    required this.uid,
    required this.email,
    this.name,
    this.role = MessRole.member,
  });

  bool get hasSignedIn => uid.isNotEmpty;

  /// Builds a seat from its entry in the mess document's members map. The map is
  /// keyed by the lowercased email, which is the same key used by the rules.
  factory MessMember.fromEntry(String email, Map<dynamic, dynamic> entry) {
    return MessMember(
      uid: (entry['uid'] as String?) ?? '',
      email: (entry['email'] as String?) ?? email,
      name: entry['name'] as String?,
      role: MessRole.parse(entry['role'] as String?),
    );
  }
}

/// A mess the signed-in person belongs to.
class Mess {
  final String id;
  final String name;
  final String ownerUid;
  final String joinCode;
  final String? location;

  /// This person's role, taken from their membership document. The membership
  /// collection is the single source of truth for roles, not the mess roster.
  final String myRole;

  /// Everyone in the mess, read straight off this document.
  ///
  /// The list lives on the mess rather than in a subcollection so that a single
  /// document read returns both the mess and its members.
  final List<MessMember> members;

  const Mess({
    required this.id,
    required this.name,
    required this.ownerUid,
    required this.joinCode,
    this.location,
    required this.myRole,
    this.members = const [],
  });

  factory Mess.fromDoc(
    DocumentSnapshot<Map<String, dynamic>> doc, {
    required String role,
  }) {
    final data = doc.data() ?? const <String, dynamic>{};
    final rawMembers =
        Map<dynamic, dynamic>.from((data['members'] as Map?) ?? const {});

    final people = <MessMember>[];
    for (final entry in rawMembers.entries) {
      final seat = entry.value;
      if (seat is Map) {
        people.add(MessMember.fromEntry(
          '${entry.key}',
          Map<dynamic, dynamic>.from(seat),
        ));
      }
    }
    // Owner first, then alphabetically, so the list never reshuffles as seats
    // are added.
    people.sort((a, b) {
      final byRole = b.role.index.compareTo(a.role.index);
      if (byRole != 0) return byRole;
      return a.email.compareTo(b.email);
    });

    return Mess(
      id: doc.id,
      name: (data['name'] as String?) ?? 'Mess',
      ownerUid: (data['ownerUid'] as String?) ?? '',
      joinCode: (data['joinCode'] as String?) ?? '',
      location: data['location'] as String?,
      myRole: role,
      members: people,
    );
  }

  bool get isOwner => myRole == MessRole.owner.wire;
}

class CloudMessage implements Exception {
  final String text;
  const CloudMessage(this.text);

  @override
  String toString() => text;
}

/// Talks to Firestore about messes, members and approval.
///
/// Expense and collection data still lives in the local SQLite database.
/// This is the membership layer only, which is what shared access needs first.
class MessCloudService {
  MessCloudService({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
  })  : _db = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _db;
  final FirebaseAuth _auth;

  // Top-level so the path is creators/<email>: one collection, one document.
  static const _creators = 'creators';
  static const _messes = 'messes';
  static const _memberships = 'memberships';

  /// The signed-in person's address, normalised.
  ///
  /// Google does not normalise the case of an address and Firebase returns the
  /// token email exactly as the account stores it, so seats keyed by the raw
  /// value would silently miss anyone whose account capitalises it. Keys are
  /// always lowercased, and the rules lowercase their side to match.
  String? get _myEmail {
    final raw = _user?.email?.trim() ?? '';
    return raw.isEmpty ? null : raw.toLowerCase();
  }

  User? get _user => _auth.currentUser;

  // ---- Approval gate ----

  /// True when the app owner has explicitly approved this email to create a
  /// mess. This is the gate that stops the open internet from creating messes.
  Future<bool> isApprovedCreator() async {
    final raw = _user?.email?.trim() ?? '';
    if (raw.isEmpty) {
      // Nothing can be looked up without an email, and an empty one would build
      // a malformed path. Treat it as "not approved" rather than crashing.
      // ignore: avoid_print
      print('MessApp: signed in but no email on the account '
          '(uid ${_user?.uid}); treating as not approved.');
      return false;
    }
    final email = _myEmail!;
    // ignore: avoid_print
    print('MessApp: checking approval for "$email"');

    try {
      // A direct read, not a query: the document id is known once the email is
      // known, so nothing has to be searched for and no rule has to be proven.
      final doc = await _db.collection(_creators).doc(email).get();
      return doc.exists && (doc.data()?['enabled'] as bool? ?? false);
    } on FirebaseException catch (e) {
      // A rules denial must not be read as "not approved" silently: the user
      // would see the wrong screen and have no idea why.
      throw CloudMessage(_friendly(e));
    } on ArgumentError catch (e) {
      throw CloudMessage('Could not check approval: ${e.message}');
    }
  }

  // ---- Membership ----

  /// This person's membership: the mess they belong to and their role in it.
  ///
  /// One document read, keyed by their own email. The email is the key because a
  /// Firebase uid does not exist until someone signs in, so it is the only
  /// identifier available when the owner invites them.
  Future<({String messId, String role})?> myMembership() async {
    final email = _myEmail;
    if (email == null) return null;

    final snap = await _db.collection(_memberships).doc(email).get();
    final messId = snap.data()?['messId'] as String?;
    if (messId == null || messId.isEmpty) return null;

    return (
      messId: messId,
      role: MessRole.parse(snap.data()?['role'] as String?).wire,
    );
  }

  /// The mess this person belongs to, or null when they have no membership.
  Future<Mess?> myMess() async {
    final membership = await myMembership();
    if (membership == null) return null;

    final doc = await _db.collection(_messes).doc(membership.messId).get();
    if (!doc.exists) return null;

    return Mess.fromDoc(doc, role: membership.role);
  }

  /// Finds the mess this person should open.
  ///
  /// The membership document answers both questions at once — which mess, and
  /// what role — so this is one read rather than a search. A creator with no
  /// membership gets null, which is what routes them to the create screen.
  Future<Mess?> resolveMess(String uid) async {
    try {
      return await myMess();
    } on FirebaseException catch (e) {
      // Turn the raw denial into something a person can read, rather than dying
      // on a bare "[cloud_firestore/permission-denied]".
      throw CloudMessage(_friendly(e));
    }
  }

  /// Whether this person already belongs to a mess, in either role.
  ///
  /// Used to keep a creator away from the create screen once they own one.
  Future<bool> hasMembership() async => await myMembership() != null;

  /// Creates a mess and returns it. The creator becomes owner and first member.
  ///
  /// The mess and the owner's profile are written in one batch, so the
  /// "one account, one mess" rule cannot be half-applied: either both land or
  /// neither does.
  Future<Mess> createMess({
    required String name,
    String? location,
  }) async {
    final uid = _user?.uid;
    final email = _myEmail;
    if (uid == null || email == null) {
      throw const CloudMessage('Sign in again before creating a mess.');
    }
    if (!await isApprovedCreator()) {
      throw const CloudMessage(
          'Your account is not approved to create a mess yet.');
    }
    // Refused here rather than only in the rules, so the person gets a sentence
    // explaining why instead of a bare denial. Being a member counts as
    // belonging to a mess: creating a second would leave them in two.
    if (await hasMembership()) {
      throw const CloudMessage(
          'You already belong to a mess. One account, one mess.');
    }

    final doc = _db.collection(_messes).doc();
    final code = _generateJoinCode();
    final trimmedName = name.trim();

    try {
      final batch = _db.batch();
      batch.set(doc, {
        'name': trimmedName,
        'location': location?.trim(),
        'ownerUid': uid,
        'ownerEmail': email,
        'joinCode': code,
        'createdAt': FieldValue.serverTimestamp(),
        // The roster lives on the mess document itself, so one read returns both
        // the mess and everyone in it. A separate subcollection would need its
        // own query, and a query cannot prove itself against these rules.
        'members': {
          email: {
            'email': email,
            'name': _user?.displayName,
            'role': MessRole.owner.wire,
            'uid': uid,
            'joinedAt': FieldValue.serverTimestamp(),
          },
        },
      });
      // The creator's own membership, in the same batch as the mess, so the mess can
      // never exist without an owner able to reach it.
      batch.set(_db.collection(_memberships).doc(email), {
        'email': email,
        'messId': doc.id,
        'role': MessRole.owner.wire,
        'createdAt': FieldValue.serverTimestamp(),
      });
      await batch.commit();
    } on FirebaseException catch (e) {
      if (e.code == 'permission-denied') {
        throw const CloudMessage(
          'Could not create the mess. Your account may not be approved to '
          'create one, or you may already run a mess.',
        );
      }
      throw CloudMessage(_friendly(e));
    }

    // Read back rather than rebuilding here, so the caller sees exactly what was
    // stored and the object cannot drift from the database.
    return Mess.fromDoc(
      await doc.get(),
      role: MessRole.owner.wire,
    );
  }

  // ---- Members ----

  /// Adds a person to a mess by email. Owner only.
  ///
  /// The seat is keyed by the lowercased email, which is also the key the rules
  /// use. A Firebase uid cannot be known before this person has signed in, so it
  /// is left empty and their membership record is what lets them in.
  Future<void> addMember({
    required String messId,
    required String email,
  }) async {
    final uid = _user?.uid;
    if (uid == null) throw const CloudMessage('Sign in again.');

    final clean = email.trim().toLowerCase();
    if (!clean.contains('@')) {
      throw const CloudMessage('That does not look like an email address.');
    }

    try {
      final ref = _db.collection(_messes).doc(messId);
      final snap = await ref.get();
      final existing =
          Map<dynamic, dynamic>.from((snap.data()?['members'] as Map?) ?? const {});

      if (existing.containsKey(clean)) {
        // Already listed. This is the case for anyone added before membership
        // records existed: they have a seat but no way in, because the app reads
        // the membership document to decide where to send them. Write the missing
        // record instead of refusing, which would leave them stuck permanently.
        final membership =
            await _db.collection(_memberships).doc(clean).get();
        if (membership.exists) {
          throw const CloudMessage('They are already in this mess.');
        }

        await _db.collection(_memberships).doc(clean).set({
          'email': clean,
          'messId': messId,
          'role': MessRole.member.wire,
          'createdAt': FieldValue.serverTimestamp(),
        });
        return;
      }

      // Roster entry and membership record together, so nobody can end up listed
      // in the mess with no way in, or able to get in without being listed.
      final batch = _db.batch();
      batch.set(ref, {
        'members': {
          clean: {
            'email': clean,
            'name': null,
            'role': MessRole.member.wire,
            'uid': null,
            'addedAt': FieldValue.serverTimestamp(),
          },
        },
      }, SetOptions(merge: true));
      batch.set(_db.collection(_memberships).doc(clean), {
        'email': clean,
        'messId': messId,
        'role': MessRole.member.wire,
        'createdAt': FieldValue.serverTimestamp(),
      });
      await batch.commit();
    } on FirebaseException catch (e) {
      throw CloudMessage(_friendly(e));
    }
  }

  /// Removes a person from a mess. Owner only.
  ///
  /// The membership record goes too. Leaving it behind would be the more
  /// dangerous half: they would keep passing `isMemberOf` in the rules and still
  /// be able to read the mess even though they are no longer listed in it.
  Future<void> removeMember({
    required String messId,
    required String email,
  }) async {
    final clean = email.trim().toLowerCase();

    try {
      final ref = _db.collection(_messes).doc(messId);
      final snap = await ref.get();
      final seats =
          Map<dynamic, dynamic>.from((snap.data()?['members'] as Map?) ?? const {});
      if (!seats.containsKey(clean)) {
        throw const CloudMessage('They are not in this mess.');
      }

      final batch = _db.batch();
      batch.set(ref, {
        'members': {clean: FieldValue.delete()},
      }, SetOptions(merge: true));
      batch.delete(_db.collection(_memberships).doc(clean));
      await batch.commit();
    } on FirebaseException catch (e) {
      throw CloudMessage(_friendly(e));
    }
  }

  // ---- Helpers ----

  /// Short, unambiguous code. Ambiguous characters (0/O, 1/I) are left out so
  /// it can be read aloud across a room without mistakes.
  String _generateJoinCode() {
    const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final random = Random.secure();
    return List.generate(6, (_) => alphabet[random.nextInt(alphabet.length)])
        .join();
  }

  String _friendly(FirebaseException e) {
    if (e.code == 'permission-denied') {
      // Nearly always means the published rules are older than the app, since
      // the app never asks for anything a member should not have.
      return 'MessApp could not read your mess. This usually means the app '
          'rules need updating in the Firebase console.';
    }
    if (e.code == 'unavailable' || e.code == 'deadline-exceeded') {
      return 'Could not reach the server. Check your connection.';
    }
    return e.message ?? 'Something went wrong. Please try again.';
  }
}