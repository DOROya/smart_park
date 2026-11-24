import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// The signed-in user's own profile, which every role can read: a cheap
/// document for asking Firestore whether the server is reachable.
DocumentReference<Map<String, dynamic>>? _ownProfile() {
  final String? uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return null;
  return FirebaseFirestore.instance.collection('users').doc(uid);
}

/// Asks the server directly (not the cache). A request also makes Firestore
/// retry a dropped connection now instead of after its back-off.
Future<bool> spCanReachServer() async {
  final DocumentReference<Map<String, dynamic>>? ref = _ownProfile();
  if (ref == null) return false;
  try {
    await ref
        .get(const GetOptions(source: Source.server))
        .timeout(const Duration(seconds: 8));
    return true;
  } catch (_) {
    return false;
  }
}

/// Pull down to refresh around a list. Screens here are live (Firestore
/// streams), so there is nothing to re-fetch: the pull checks the server,
/// reconnects a dropped connection, and says so when the phone is offline.
class SpPullToRefresh extends StatelessWidget {
  const SpPullToRefresh({super.key, required this.child});

  /// A vertical scroll view (or a widget whose first scroll view is one).
  final Widget child;

  Future<void> _refresh(BuildContext context) async {
    final ScaffoldMessengerState? messenger = ScaffoldMessenger.maybeOf(
      context,
    );
    final Stopwatch watch = Stopwatch()..start();
    final bool online = await spCanReachServer();
    // Long enough to see the spinner, so the pull feels like it did something.
    const Duration least = Duration(milliseconds: 600);
    if (watch.elapsed < least) {
      await Future<void>.delayed(least - watch.elapsed);
    }
    messenger?.hideCurrentSnackBar();
    messenger?.showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 2),
        content: Text(
          online
              ? 'Up to date.'
              : 'No connection. Showing what was last loaded.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      color: AppTheme.onAccent,
      backgroundColor: AppTheme.accent,
      onRefresh: () => _refresh(context),
      child: child,
    );
  }
}

/// A strip saying the screen is offline and its numbers may be old. Shown
/// only after Firestore has served from the cache for a few seconds, so a
/// slow first connection or a short blip does not flash it.
class SpConnectionBanner extends StatefulWidget {
  const SpConnectionBanner({super.key});

  @override
  State<SpConnectionBanner> createState() => _SpConnectionBannerState();
}

class _SpConnectionBannerState extends State<SpConnectionBanner> {
  static const Duration _delay = Duration(seconds: 4);

  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _sub;
  Timer? _timer;
  bool _offline = false;
  bool _retrying = false;

  @override
  void initState() {
    super.initState();
    _sub = _ownProfile()
        ?.snapshots(includeMetadataChanges: true)
        .listen(
          (DocumentSnapshot<Map<String, dynamic>> snap) =>
              _onCacheState(snap.metadata.isFromCache),
          onError: (Object _) {},
        );
  }

  void _onCacheState(bool fromCache) {
    if (!fromCache) {
      _timer?.cancel();
      _timer = null;
      if (_offline && mounted) setState(() => _offline = false);
      return;
    }
    if (_offline || _timer != null) return;
    _timer = Timer(_delay, () {
      _timer = null;
      if (mounted) setState(() => _offline = true);
    });
  }

  Future<void> _retry() async {
    setState(() => _retrying = true);
    final bool online = await spCanReachServer();
    if (!mounted) return;
    setState(() {
      _retrying = false;
      // The listener also clears it; this is just quicker.
      if (online) _offline = false;
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSize(
      duration: const Duration(milliseconds: 200),
      alignment: Alignment.topCenter,
      child: !_offline
          ? const SizedBox(width: double.infinity)
          : Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Container(
                padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
                decoration: BoxDecoration(
                  color: AppTheme.warningSoft,
                  borderRadius: BorderRadius.circular(AppTheme.radius),
                  border: Border.all(
                    color: AppTheme.warning.withValues(alpha: 0.35),
                  ),
                ),
                child: Row(
                  children: <Widget>[
                    Icon(
                      Icons.cloud_off_rounded,
                      size: 18,
                      color: AppTheme.warning,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'No connection. Numbers may be out of date until '
                        'you are back online.',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.textDark,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: _retrying ? null : _retry,
                      child: _retrying
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Retry'),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}
