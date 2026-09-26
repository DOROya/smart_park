import 'package:cloud_functions/cloud_functions.dart';

/// Sends verification and password-reset emails through Cloud Functions,
/// which deliver them from SmartPark's own Gmail account instead of
/// Firebase's built-in sender (whose template is locked and lands in spam).
class AuthEmailService {
  AuthEmailService({FirebaseFunctions? functions})
    : _functions =
          functions ?? FirebaseFunctions.instanceFor(region: 'asia-southeast1');

  final FirebaseFunctions _functions;

  /// Emails the signed-in user a verification link. Returns false if the
  /// address turned out to be verified already.
  Future<bool> sendVerificationEmail() async {
    final HttpsCallableResult<dynamic> result = await _functions
        .httpsCallable('sendVerificationEmail')
        .call<dynamic>();
    final Object? data = result.data;
    return !(data is Map && data['alreadyVerified'] == true);
  }

  /// Emails a password-reset link. Succeeds for unknown addresses too.
  Future<void> sendPasswordResetEmail(String email) async {
    await _functions.httpsCallable('sendPasswordResetEmail').call<dynamic>(
      <String, dynamic>{'email': email},
    );
  }

  /// True when the server refused because too many emails were requested.
  static bool isThrottled(FirebaseFunctionsException error) =>
      error.code == 'resource-exhausted';
}
