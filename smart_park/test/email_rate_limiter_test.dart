import 'package:flutter_test/flutter_test.dart';
import 'package:smart_park/services/email_rate_limiter.dart';

void main() {
  test('a fresh address may send right away', () {
    expect(
      EmailRateLimiter.remaining('verify', 'fresh@example.com'),
      Duration.zero,
    );
  });

  test('a send starts the cooldown for that address and action only', () {
    EmailRateLimiter.recordSend('verify', 'a@example.com');

    final Duration wait = EmailRateLimiter.remaining('verify', 'a@example.com');
    expect(wait, greaterThan(const Duration(seconds: 55)));
    expect(wait, lessThanOrEqualTo(EmailRateLimiter.cooldown));

    expect(
      EmailRateLimiter.remaining('verify', 'b@example.com'),
      Duration.zero,
    );
    expect(
      EmailRateLimiter.remaining('password-reset', 'a@example.com'),
      Duration.zero,
    );
  });

  test('addresses are matched case-insensitively', () {
    EmailRateLimiter.recordSend('password-reset', 'Case@Example.com ');
    expect(
      EmailRateLimiter.remaining('password-reset', 'case@example.com'),
      greaterThan(Duration.zero),
    );
  });

  test('the hourly cap outlasts the cooldown', () {
    for (int i = 0; i < EmailRateLimiter.maxPerWindow; i++) {
      EmailRateLimiter.recordSend('verify', 'spam@example.com');
    }
    expect(
      EmailRateLimiter.remaining('verify', 'spam@example.com'),
      greaterThan(const Duration(minutes: 59)),
    );
  });

  test('describe rounds up to seconds, then minutes', () {
    expect(EmailRateLimiter.describe(const Duration(seconds: 45)), '45s');
    expect(
      EmailRateLimiter.describe(const Duration(milliseconds: 44100)),
      '45s',
    );
    expect(EmailRateLimiter.describe(const Duration(minutes: 11)), '11 min');
    expect(
      EmailRateLimiter.describe(const Duration(minutes: 11, seconds: 1)),
      '12 min',
    );
  });
}
