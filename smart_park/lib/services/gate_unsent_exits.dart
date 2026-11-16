import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'error_reporter.dart';

/// An exit recorded while there was no connection: saved on this device and
/// still waiting to reach the server, or refused by it once it got there.
@immutable
class UnsentExit {
  const UnsentExit({
    required this.transactionId,
    required this.exitLogId,
    required this.plate,
    required this.leftAt,
    this.walkIn = false,
    this.failed = false,
  });

  factory UnsentExit.fromJson(Map<String, dynamic> json) => UnsentExit(
    transactionId: (json['transactionId'] as String?) ?? '',
    exitLogId: (json['exitLogId'] as String?) ?? '',
    plate: (json['plate'] as String?) ?? '',
    leftAt: DateTime.fromMillisecondsSinceEpoch(
      (json['leftAt'] as num?)?.toInt() ?? 0,
    ),
    walkIn: json['walkIn'] == true,
    failed: json['failed'] == true,
  );

  final String transactionId;

  /// The exit log the write would create; it names this one attempt.
  final String exitLogId;
  final String plate;
  final DateTime leftAt;
  final bool walkIn;

  /// The server refused it, so the vehicle still shows as inside. Staff
  /// must record the exit again.
  final bool failed;

  UnsentExit asFailed() => UnsentExit(
    transactionId: transactionId,
    exitLogId: exitLogId,
    plate: plate,
    leftAt: leftAt,
    walkIn: walkIn,
    failed: true,
  );

  Map<String, dynamic> toJson() => <String, dynamic>{
    'transactionId': transactionId,
    'exitLogId': exitLogId,
    'plate': plate,
    'leftAt': leftAt.millisecondsSinceEpoch,
    'walkIn': walkIn,
    'failed': failed,
  };
}

/// The exits this device recorded offline that are not on the server yet,
/// so staff are told when one never makes it instead of the vehicle quietly
/// staying "inside". Kept on the device when given a [storageKey], so the
/// list survives the app being closed while still offline.
class GateUnsentExits extends ChangeNotifier {
  GateUnsentExits({this.storageKey});

  /// Where the list is kept between runs; null keeps it in memory only.
  final String? storageKey;

  final List<UnsentExit> _items = <UnsentExit>[];

  /// Attempts whose write this run of the app is still watching.
  final Set<String> _watched = <String>{};

  List<UnsentExit> get waiting =>
      _items.where((UnsentExit e) => !e.failed).toList();
  List<UnsentExit> get failed =>
      _items.where((UnsentExit e) => e.failed).toList();
  bool get isEmpty => _items.isEmpty;

  /// Reads the list kept from an earlier run.
  Future<void> load() async {
    final String? key = storageKey;
    if (key == null) return;
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final dynamic stored = jsonDecode(prefs.getString(key) ?? '[]');
      if (stored is! List) return;
      for (final dynamic item in stored) {
        if (item is! Map) continue;
        final UnsentExit exit = UnsentExit.fromJson(
          item.map<String, dynamic>(
            (dynamic k, dynamic v) => MapEntry<String, dynamic>('$k', v),
          ),
        );
        if (_items.every((UnsentExit e) => e.exitLogId != exit.exitLogId)) {
          _items.add(exit);
        }
      }
      notifyListeners();
    } catch (error, stack) {
      reportError(error, stack, reason: 'Loading unsent exits failed');
    }
  }

  /// Follows [write], an exit Firestore queued for when the connection is
  /// back: dropped from the list once the server has it, marked failed if
  /// the server refuses it.
  void track(UnsentExit exit, Future<void> write) {
    _items.removeWhere((UnsentExit e) => e.exitLogId == exit.exitLogId);
    _items.add(exit);
    _watched.add(exit.exitLogId);
    _changed();
    unawaited(
      write.then<void>(
        (_) => _settle(exit.exitLogId, sent: true),
        onError: (Object _) => _settle(exit.exitLogId, sent: false),
      ),
    );
  }

  /// The exit of [transactionId] is on the server now (recorded again with a
  /// connection), so nothing about it is left to chase.
  void resolve(String transactionId) {
    final int before = _items.length;
    _items.removeWhere((UnsentExit e) => e.transactionId == transactionId);
    if (_items.length != before) _changed();
  }

  /// Staff cleared a failed exit from the list without recording it again.
  void dismiss(UnsentExit exit) {
    _items.removeWhere((UnsentExit e) => e.exitLogId == exit.exitLogId);
    _changed();
  }

  /// Settles exits left waiting by an earlier run of the app, whose writes
  /// nothing is watching any more: once Firestore has sent everything it
  /// had queued, the ticket on the server says whether each one arrived.
  /// [allSent] completes when nothing is queued any more (by default,
  /// Firestore's own wait).
  Future<void> recheck(
    FirebaseFirestore db, {
    Future<void> Function()? allSent,
  }) async {
    final List<UnsentExit> stale = waiting
        .where((UnsentExit e) => !_watched.contains(e.exitLogId))
        .toList();
    if (stale.isEmpty) return;
    try {
      await (allSent ?? db.waitForPendingWrites)();
      for (final UnsentExit exit in stale) {
        final DocumentSnapshot<Map<String, dynamic>> ticket = await db
            .collection('transactions')
            .doc(exit.transactionId)
            .get(const GetOptions(source: Source.server));
        _settle(
          exit.exitLogId,
          sent: ticket.data()?['exitLogId'] == exit.exitLogId,
        );
      }
    } catch (error, stack) {
      // Still offline or unreadable: they stay listed as waiting.
      reportError(error, stack, reason: 'Rechecking unsent exits failed');
    }
  }

  void _settle(String exitLogId, {required bool sent}) {
    final int index = _items.indexWhere(
      (UnsentExit e) => e.exitLogId == exitLogId,
    );
    _watched.remove(exitLogId);
    if (index < 0) return;
    if (sent) {
      _items.removeAt(index);
    } else {
      _items[index] = _items[index].asFailed();
    }
    _changed();
  }

  void _changed() {
    notifyListeners();
    unawaited(_save());
  }

  Future<void> _save() async {
    final String? key = storageKey;
    if (key == null) return;
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        key,
        jsonEncode(_items.map((UnsentExit e) => e.toJson()).toList()),
      );
    } catch (error, stack) {
      reportError(error, stack, reason: 'Saving unsent exits failed');
    }
  }
}
