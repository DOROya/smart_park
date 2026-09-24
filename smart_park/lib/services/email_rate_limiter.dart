/// Client-side throttle for Firebase Auth emails (verification and password
/// reset), keyed by action + address so each email gets its own budget.
///
/// Each key allows one send per [cooldown] and at most [maxPerWindow] sends
/// per [window]. State is kept for the app's lifetime, so leaving and
/// reopening a screen does not reset it. Firebase still enforces its own
/// server-side limit (`too-many-requests`) on top of this.
class EmailRateLimiter {
  EmailRateLimiter._();

  static const Duration cooldown = Duration(seconds: 60);
  static const Duration window = Duration(hours: 1);
  static const int maxPerWindow = 5;

  static final Map<String, List<DateTime>> _sentAt = <String, List<DateTime>>{};

  static String _key(String action, String email) =>
      '$action:${email.trim().toLowerCase()}';

  static List<DateTime> _recent(String key, DateTime now) {
    final List<DateTime> sends = _sentAt.putIfAbsent(key, () => <DateTime>[]);
    sends.removeWhere((DateTime t) => now.difference(t) >= window);
    return sends;
  }

  /// How long until another email may be sent, or [Duration.zero] if now.
  static Duration remaining(String action, String email) {
    final DateTime now = DateTime.now();
    final List<DateTime> sends = _recent(_key(action, email), now);
    if (sends.isEmpty) return Duration.zero;

    Duration wait = cooldown - now.difference(sends.last);
    if (sends.length >= maxPerWindow) {
      final Duration windowWait = window - now.difference(sends.first);
      if (windowWait > wait) wait = windowWait;
    }
    return wait.isNegative ? Duration.zero : wait;
  }

  static void recordSend(String action, String email) {
    final DateTime now = DateTime.now();
    _recent(_key(action, email), now).add(now);
  }

  /// "45s" under a minute, otherwise "12 min".
  static String describe(Duration wait) {
    final int seconds =
        wait.inSeconds + (wait.inMilliseconds % 1000 > 0 ? 1 : 0);
    if (seconds < 60) return '${seconds}s';
    return '${(seconds / 60).ceil()} min';
  }

  static const String tooManyRequestsMessage =
      'Too many emails were requested. Please wait a few minutes and try again.';
}
