import 'dart:async';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_park/screens/staff/unsent_exits_banner.dart';
import 'package:smart_park/services/gate_unsent_exits.dart';

UnsentExit exit(String id, {bool walkIn = false}) => UnsentExit(
  transactionId: 'ticket-$id',
  exitLogId: 'log-$id',
  plate: 'ABC $id',
  leftAt: DateTime(2026, 11, 16, 15, 42),
  walkIn: walkIn,
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  group('an exit recorded without a connection', () {
    test('waits, then drops off once the server has it', () async {
      final GateUnsentExits unsent = GateUnsentExits();
      final Completer<void> write = Completer<void>();
      unsent.track(exit('1'), write.future);
      expect(unsent.waiting.single.plate, 'ABC 1');
      expect(unsent.failed, isEmpty);

      write.complete();
      await pumpEventQueue();
      expect(unsent.isEmpty, isTrue);
    });

    test('is marked failed when the server refuses it', () async {
      final GateUnsentExits unsent = GateUnsentExits();
      final Completer<void> write = Completer<void>();
      unsent.track(exit('1'), write.future);
      write.completeError(StateError('permission-denied'));
      await pumpEventQueue();
      expect(unsent.waiting, isEmpty);
      expect(unsent.failed.single.transactionId, 'ticket-1');
    });

    test(
      'a failed exit clears when it is recorded again or dismissed',
      () async {
        final GateUnsentExits unsent = GateUnsentExits();
        for (final String id in <String>['1', '2']) {
          unsent.track(exit(id), Future<void>.error(StateError('refused')));
        }
        await pumpEventQueue();
        expect(unsent.failed, hasLength(2));

        unsent.resolve('ticket-1');
        expect(unsent.failed.single.plate, 'ABC 2');
        unsent.dismiss(unsent.failed.single);
        expect(unsent.isEmpty, isTrue);
      },
    );

    test('is still listed after the app is closed and opened', () async {
      final GateUnsentExits before = GateUnsentExits(storageKey: 'k');
      before.track(exit('1'), Completer<void>().future);
      before.track(exit('2'), Future<void>.error(StateError('refused')));
      await pumpEventQueue();

      final GateUnsentExits after = GateUnsentExits(storageKey: 'k');
      await after.load();
      expect(after.waiting.single.plate, 'ABC 1');
      expect(after.failed.single.plate, 'ABC 2');
      // Another staff account on the same phone keeps its own list.
      final GateUnsentExits other = GateUnsentExits(storageKey: 'other');
      await other.load();
      expect(other.isEmpty, isTrue);
    });

    test(
      'left over from an earlier run is settled against the server',
      () async {
        final FakeFirebaseFirestore db = FakeFirebaseFirestore();
        // Ticket 1's exit arrived; ticket 2 is still checked in.
        await db.collection('transactions').doc('ticket-1').set(
          <String, dynamic>{'entryStatus': 'checked_out', 'exitLogId': 'log-1'},
        );
        await db.collection('transactions').doc('ticket-2').set(
          <String, dynamic>{'entryStatus': 'checked_in'},
        );
        final GateUnsentExits before = GateUnsentExits(storageKey: 'k');
        before.track(exit('1'), Completer<void>().future);
        before.track(exit('2'), Completer<void>().future);
        await pumpEventQueue();

        final GateUnsentExits after = GateUnsentExits(storageKey: 'k');
        await after.load();
        // The fake database has no queue to wait on.
        await after.recheck(db, allSent: () async {});
        expect(after.waiting, isEmpty);
        expect(after.failed.single.transactionId, 'ticket-2');
      },
    );
  });

  group('the staff banner', () {
    Future<void> pump(WidgetTester tester, GateUnsentExits unsent) =>
        tester.pumpWidget(
          MaterialApp(
            home: Scaffold(body: UnsentExitsBanner(unsent: unsent)),
          ),
        );

    testWidgets('shows nothing when every exit is on the server', (
      WidgetTester tester,
    ) async {
      await pump(tester, GateUnsentExits());
      expect(find.byType(Text), findsNothing);
    });

    testWidgets('lists a refused exit until staff deal with it', (
      WidgetTester tester,
    ) async {
      final GateUnsentExits unsent = GateUnsentExits();
      await pump(tester, unsent);
      unsent.track(exit('1'), Completer<void>().future);
      unsent.track(
        exit('2', walkIn: true),
        Future<void>.error(StateError('refused')),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('1 exit waiting to be sent'), findsOneWidget);
      expect(find.text('1 exit was not saved'), findsOneWidget);
      expect(
        find.textContaining('ABC 2 (walk-in) · left 3:42 PM'),
        findsOneWidget,
      );

      await tester.tap(find.text('Dismiss'));
      await tester.pumpAndSettle();
      expect(find.text('1 exit was not saved'), findsNothing);
      expect(find.textContaining('waiting to be sent'), findsOneWidget);
    });
  });
}
