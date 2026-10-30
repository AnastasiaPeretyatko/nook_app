import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:todo_app/settings/api_config.dart';

/// Asks Google, in the system's own account sheet on top of the app (no
/// browser), for an ID token proving who the user is. Null when the user
/// closed the sheet — cancelling is not a failure.
///
/// A provider so a test can answer without a phone: the real one needs Google
/// Play services. Used both to sign in and to confirm deleting a Google
/// account, where the server wants a **fresh** token.
final googleIdTokenProvider = Provider<Future<String?> Function()>(
  (ref) => fetchGoogleIdToken,
);

Future<void>? _initialised;

Future<String?> fetchGoogleIdToken() async {
  // `initialize` may be called only once per process.
  await (_initialised ??= GoogleSignIn.instance.initialize(
    serverClientId: googleServerClientId,
  ));
  try {
    final account = await GoogleSignIn.instance.authenticate();
    return account.authentication.idToken;
  } on GoogleSignInException catch (e) {
    // On Android a misconfigured app (wrong SHA-1 or package) comes back as
    // `canceled`, indistinguishable from the user closing the sheet — so the
    // details go to the log, where a developer can tell the two apart.
    debugPrint('Google sign-in: ${e.code} ${e.description}');
    if (e.code == GoogleSignInExceptionCode.canceled) return null;
    rethrow;
  }
}
