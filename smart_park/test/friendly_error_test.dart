import 'dart:async';
import 'dart:io';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_park/utils/friendly_error.dart';

void main() {
  test('network failures read as offline', () {
    expect(
      friendlyError(const SocketException('x')),
      contains('No internet connection'),
    );
    expect(friendlyError(TimeoutException('x')), contains('too long'));
  });

  test('our Cloud Functions messages pass through, generic ones do not', () {
    expect(
      friendlyError(
        FirebaseFunctionsException(
          code: 'resource-exhausted',
          message: 'Too many emails were requested.',
        ),
      ),
      'Too many emails were requested.',
    );
    expect(
      friendlyError(
        FirebaseFunctionsException(code: 'internal', message: 'INTERNAL'),
        fallback: 'Payment failed.',
      ),
      'Payment failed.',
    );
    expect(
      friendlyError(
        FirebaseFunctionsException(code: 'not-found', message: 'NOT_FOUND'),
        fallback: 'Nope.',
      ),
      'Nope.',
    );
  });

  test('auth codes map to plain language', () {
    expect(
      friendlyError(FirebaseAuthException(code: 'invalid-credential')),
      'Incorrect email/username or password.',
    );
    expect(
      friendlyError(
        FirebaseAuthException(code: 'something-new'),
        fallback: 'F',
      ),
      'F',
    );
  });

  test('raw Firebase messages are never shown', () {
    final String message = friendlyError(
      FirebaseException(
        plugin: 'cloud_firestore',
        code: 'permission-denied',
        message: 'The caller does not have permission',
      ),
    );
    expect(message, "You don't have permission to do that.");
    expect(friendlyError(StateError('boom'), fallback: 'F'), 'F');
  });
}
