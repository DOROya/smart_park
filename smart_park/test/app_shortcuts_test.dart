import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_park/services/app_shortcuts.dart';
import 'package:smart_park/services/last_ticket_store.dart';

void main() {
  final DateTime now = DateTime(2026, 11, 23, 12);
  DateTime? created(Map<String, dynamic> d) => d['at'] as DateTime?;

  Map<String, dynamic> ticket(int day, {String entry = 'not_checked_in'}) =>
      <String, dynamic>{
        'status': 'paid',
        'entryStatus': entry,
        'plan': 'daily',
        'duration': 1,
        'remainingHours': 10,
        'at': DateTime(2026, 11, day),
      };

  test('"Show my ticket" picks the ticket checked in now first', () {
    final ({String kind, String id, Map<String, dynamic> data})? pick =
        pickShortcutTicket(
          tickets: <(String, Map<String, dynamic>)>[
            ('newer', ticket(22)),
            ('parked', ticket(10, entry: 'checked_in')),
          ],
          passes: const <(String, Map<String, dynamic>)>[],
          createdAt: created,
          now: now,
        );
    expect(pick?.id, 'parked');
  });

  test('then the newest paid ticket with hours left, then a temporary QR', () {
    final Map<String, dynamic> usedUp = ticket(23)..['remainingHours'] = 0;
    expect(
      pickShortcutTicket(
        tickets: <(String, Map<String, dynamic>)>[
          ('old', ticket(1)),
          ('new', ticket(20)),
          ('usedUp', usedUp),
        ],
        passes: const <(String, Map<String, dynamic>)>[],
        createdAt: created,
        now: now,
      )?.id,
      'new',
    );
    final ({String kind, String id, Map<String, dynamic> data})? pass =
        pickShortcutTicket(
          tickets: <(String, Map<String, dynamic>)>[('usedUp', usedUp)],
          passes: <(String, Map<String, dynamic>)>[
            (
              'expired',
              <String, dynamic>{
                'status': 'awaiting_gate',
                'expiresAt': Timestamp.fromDate(
                  now.subtract(const Duration(hours: 1)),
                ),
                'at': DateTime(2026, 11, 22),
              },
            ),
            (
              'qr',
              <String, dynamic>{
                'status': 'awaiting_gate',
                'expiresAt': Timestamp.fromDate(
                  now.add(const Duration(days: 1)),
                ),
                'at': DateTime(2026, 11, 21),
              },
            ),
          ],
          createdAt: created,
          now: now,
        );
    expect(pass?.kind, 'pass');
    expect(pass?.id, 'qr');
    expect(
      pickShortcutTicket(
        tickets: const <(String, Map<String, dynamic>)>[],
        passes: const <(String, Map<String, dynamic>)>[],
        createdAt: created,
      ),
      isNull,
    );
  });

  test(
    'the saved ticket survives a restart and is cleared on sign-out',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final SavedTicket saved =
          savedTicketFrom('ticket', 't1', <String, dynamic>{
            ...ticket(22, entry: 'checked_in'),
            'vehiclePlate': 'ABC 123',
            'establishmentName': 'Lot A',
          });
      expect(saved.parked, isTrue);
      expect(saved.hoursLeft, 10);
      // A ticket without a stored QR still gets a scanner-compatible one.
      expect(saved.qr, contains('"transactionId":"t1"'));
      await LastTicketStore.save(saved);
      final SavedTicket? loaded = await LastTicketStore.load();
      expect(loaded?.id, 't1');
      expect(loaded?.facilityName, 'Lot A');
      await LastTicketStore.clear();
      expect(await LastTicketStore.load(), isNull);
    },
  );
}
