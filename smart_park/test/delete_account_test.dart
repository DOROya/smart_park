import 'package:flutter_test/flutter_test.dart';
import 'package:smart_park/widgets/sp_delete_account.dart';

void main() {
  group('what a driver gives up by deleting their account', () {
    test('adds up the hours left on paid tickets', () {
      final ({int hours, int tickets}) unused = spUnusedTicketHours(
        <Map<String, dynamic>>[
          // Never used: a full day.
          <String, dynamic>{'status': 'paid', 'plan': 'daily', 'duration': 1},
          // Used once, 5 hours left.
          <String, dynamic>{
            'status': 'paid',
            'plan': 'daily',
            'duration': 1,
            'entryStatus': 'checked_out',
            'remainingHours': 5,
          },
        ],
      );
      expect(unused.hours, 29);
      expect(unused.tickets, 2);
    });

    test('leaves out tickets with nothing left or never paid', () {
      final ({int hours, int tickets}) unused = spUnusedTicketHours(
        <Map<String, dynamic>>[
          <String, dynamic>{'status': 'paid', 'remainingHours': 0},
          // Checked out before tickets were reusable: used up.
          <String, dynamic>{'status': 'paid', 'entryStatus': 'checked_out'},
          <String, dynamic>{'status': 'pending', 'plan': 'weekly'},
          <String, dynamic>{'status': 'walk_in', 'source': 'walk_in'},
        ],
      );
      expect(unused.hours, 0);
      expect(unused.tickets, 0);
    });

    test('nothing to give up with no tickets', () {
      expect(spUnusedTicketHours(<Map<String, dynamic>>[]).hours, 0);
    });
  });
}
