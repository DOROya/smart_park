import 'dart:async';
import 'dart:io';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

const String _offline =
    'No internet connection. Check your connection and try again.';

/// Turns an exception into a message that's safe to show users.
///
/// Raw Firebase messages ("[cloud_firestore/permission-denied] The caller
/// does not have permission…") are for logs, not people. Cloud Functions
/// errors are the exception: our functions already throw readable
/// messages, so those are passed through unless they're generic.
String friendlyError(
  Object error, {
  String fallback = 'Something went wrong. Please try again.',
}) {
  if (error is SocketException) return _offline;
  if (error is TimeoutException) {
    return 'This is taking too long. Check your connection and try again.';
  }
  if (error is FirebaseFunctionsException) {
    return _functionsMessage(error) ?? fallback;
  }
  if (error is FirebaseAuthException) {
    return _authMessage(error.code) ?? fallback;
  }
  if (error is FirebaseException) {
    return _firebaseMessage(error.code) ?? fallback;
  }
  return fallback;
}

String? _functionsMessage(FirebaseFunctionsException error) {
  switch (error.code) {
    case 'unavailable':
      return error.message == null || error.message == 'UNAVAILABLE'
          ? _offline
          : error.message;
    case 'deadline-exceeded':
      return 'The server took too long to respond. Please try again.';
    case 'unauthenticated':
      return 'Your session has expired. Please sign in again.';
    case 'internal':
    case 'unknown':
      return null;
  }
  final String? message = error.message;
  if (message == null || message.isEmpty || message == message.toUpperCase()) {
    // Codes like "INTERNAL" or "NOT_FOUND" aren't meant for people.
    return null;
  }
  return message;
}

String? _authMessage(String code) {
  switch (code) {
    case 'invalid-credential':
    case 'wrong-password':
    case 'user-not-found':
    case 'invalid-email':
      return 'Incorrect email/username or password.';
    case 'user-disabled':
      return 'This account has been disabled. Contact SmartPark support.';
    case 'too-many-requests':
      return 'Too many attempts. Please wait a few minutes and try again.';
    case 'network-request-failed':
      return _offline;
    case 'email-already-in-use':
      return 'An account with this email already exists.';
    case 'weak-password':
      return 'That password is too weak. Try a longer one.';
    case 'requires-recent-login':
      return 'For security, please sign out and sign back in, then try again.';
  }
  return null;
}

String? _firebaseMessage(String code) {
  switch (code) {
    case 'permission-denied':
      return "You don't have permission to do that.";
    case 'unavailable':
      return _offline;
    case 'not-found':
      return 'That item no longer exists. It may have been removed.';
    case 'deadline-exceeded':
      return 'The server took too long to respond. Please try again.';
    case 'object-not-found':
      return 'That file could not be found.';
    case 'unauthorized':
      return "You don't have permission to upload that file.";
    case 'canceled':
      return 'The upload was cancelled.';
  }
  return null;
}
