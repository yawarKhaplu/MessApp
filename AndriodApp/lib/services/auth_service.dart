import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

/// The signed-in person, reduced to what the app actually needs.
class AppUser {
  final String uid;
  final String email;
  final String? displayName;
  final String? photoUrl;

  const AppUser({
    required this.uid,
    required this.email,
    this.displayName,
    this.photoUrl,
  });

  factory AppUser.fromFirebase(User user) => AppUser(
        uid: user.uid,
        email: user.email ?? '',
        displayName: user.displayName,
        photoUrl: user.photoURL,
      );
}

/// Why a sign-in attempt failed, in terms the UI can explain.
enum AuthFailure {
  /// No network, or Firebase could not be reached.
  network,

  /// The user closed the account chooser or backed out.
  cancelled,

  /// Play Services missing, or no Google account on the device.
  noGoogleAccount,

  /// The OAuth client in google-services.json is missing or does not match
  /// this app's package name and signing certificate. Surfaces in the log as
  /// "status 10" / DEVELOPER_ERROR.
  configuration,

  unknown,
}

class AuthException implements Exception {
  final AuthFailure failure;
  final String? detail;
  const AuthException(this.failure, [this.detail]);

  String get message => switch (failure) {
        AuthFailure.network =>
          'Could not reach the internet. Check your connection and try again.',
        AuthFailure.cancelled => 'Sign-in cancelled.',
        AuthFailure.noGoogleAccount =>
          'No Google account found on this phone. Add one in Settings first.',
        AuthFailure.configuration =>
          'Sign-in is not configured correctly yet. This is a setup problem, '
              'not something you did wrong.',
        AuthFailure.unknown => 'Sign-in failed. Please try again.',
      };

  @override
  String toString() => 'AuthException($failure, $detail)';
}

/// Google sign-in wrapper.
///
/// Identity only. This establishes WHO is using the app; no expense data leaves
/// the device, because sharing data is a separate step.
class AuthService {
  AuthService({FirebaseAuth? auth}) : _auth = auth ?? FirebaseAuth.instance;

  final FirebaseAuth _auth;

  /// Current user, or null when signed out. Firebase keeps this across
  /// restarts, so a signed-in person opens straight into the mess rather than
  /// being asked to sign in again every launch.
  AppUser? get currentUser {
    final user = _auth.currentUser;
    return user == null ? null : AppUser.fromFirebase(user);
  }

  Stream<AppUser?> get authStateChanges => _auth.authStateChanges().map(
        (u) => u == null ? null : AppUser.fromFirebase(u),
      );

  Future<AppUser> signInWithGoogle() async {
    // v7 exposes a singleton rather than a constructor.
    final signIn = GoogleSignIn.instance;

    try {
      // Reads this app's configuration out of google-services.json. Must run
      // before authenticate().
      await signIn.initialize();
    } catch (e) {
      throw AuthException(AuthFailure.configuration, e.toString());
    }

    try {
      final account = await signIn.authenticate();

      // Every later step keys off the email: it is the allow-list lookup and
      // the document ID. A Google account without one cannot be identified, so
      // refuse it here rather than failing later with an unreadable error.
      if (account.email.trim().isEmpty) {
        throw const AuthException(AuthFailure.noGoogleAccount,
            'The selected Google account has no email address.');
      }

      final credential = GoogleAuthProvider.credential(
        idToken: account.authentication.idToken,
      );
      final result = await _auth.signInWithCredential(credential);
      final user = result.user;

      if (user == null) throw const AuthException(AuthFailure.unknown);
      return AppUser.fromFirebase(user);
    } on AuthException {
      rethrow;
    } on GoogleSignInException catch (e) {
      throw AuthException(_mapGoogleCode(e.code), e.description);
    } on FirebaseAuthException catch (e) {
      throw AuthException(_mapFirebaseCode(e.code), e.message);
    } catch (e) {
      throw AuthException(AuthFailure.unknown, e.toString());
    }
  }

  /// Signs out, guaranteeing the Firebase session ends.
///
/// In google_sign_in v7 the singleton throws if it has not been initialised on
/// this run. Letting that exception escape would skip the Firebase sign-out
/// entirely and leave the person apparently still signed in, so each step is
/// isolated and Firebase is always cleared.
Future<void> signOut() async {
    try {
      await GoogleSignIn.instance.signOut();
    } catch (_) {
      // Nothing to clear from Google on this run; Firebase still must sign out.
    }
    await _auth.signOut();
  }

  AuthFailure _mapGoogleCode(GoogleSignInExceptionCode code) => switch (code) {
        GoogleSignInExceptionCode.clientConfigurationError ||
        GoogleSignInExceptionCode.providerConfigurationError =>
          AuthFailure.configuration,
        GoogleSignInExceptionCode.canceled => AuthFailure.cancelled,
        _ => AuthFailure.unknown,
      };

  AuthFailure _mapFirebaseCode(String code) => switch (code) {
        'network-request-failed' => AuthFailure.network,
        'web-context-canceled' => AuthFailure.cancelled,
        _ => AuthFailure.unknown,
      };
}