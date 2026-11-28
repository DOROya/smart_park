import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;
import 'package:flutter/foundation.dart';
import 'package:quick_actions/quick_actions.dart';

import '../widgets/smartpark_ui.dart' show spParseDateTime;
import 'last_ticket_store.dart';
import 'parking_pricing.dart' show ticketHoursLeft;

/// Long-press the SmartPark icon: "Show my ticket" for drivers, "Open
/// scanner" for gate staff and supervisors. Owners and admins get none.
const String kShowTicketShortcut = 'show_ticket';
const String kOpenScannerShortcut = 'open_scanner';

/// The shortcut tapped and not handled yet. Home screens listen and clear it.
final ValueNotifier<String?> pendingShortcut = ValueNotifier<String?>(null);

class AppShortcuts {
  static const QuickActions _actions = QuickActions();
  static bool _ready = false;

  /// Once, when the app starts. A cold start from a shortcut arrives here.
  static void init() {
    if (_ready) return;
    _ready = true;
    try {
      _actions.initialize((String type) => pendingShortcut.value = type);
    } catch (_) {
      // Not on this platform.
    }
  }

  /// After sign-in, for the account's [role].
  static Future<void> setForRole(String role) async {
    final String r = role.trim().toLowerCase();
    try {
      if (r == 'driver') {
        await _actions.setShortcutItems(const <ShortcutItem>[
          ShortcutItem(
            type: kShowTicketShortcut,
            localizedTitle: 'Show my ticket',
          ),
        ]);
      } else if (r == 'staff' || r == 'supervisor') {
        await _actions.setShortcutItems(const <ShortcutItem>[
          ShortcutItem(
            type: kOpenScannerShortcut,
            localizedTitle: 'Open scanner',
          ),
        ]);
      } else {
        await _actions.clearShortcutItems();
      }
    } catch (_) {
      // Shortcuts are a convenience; never fail a sign-in over them.
    }
  }

  /// On sign-out.
  static Future<void> clear() async {
    pendingShortcut.value = null;
    try {
      await _actions.clearShortcutItems();
    } catch (_) {
      // Nothing to do.
    }
  }
}

/// Which of the driver's tickets "Show my ticket" opens, in order:
/// a ticket checked in now; else the newest paid ticket with hours left
/// whose facility is not pulled ([facilityPulled]);
/// else the newest unused temporary QR; else null (the Tickets tab).
/// [tickets] and [passes] are (id, data) pairs; [createdAt] reads a date.
({String kind, String id, Map<String, dynamic> data})? pickShortcutTicket({
  required List<(String, Map<String, dynamic>)> tickets,
  required List<(String, Map<String, dynamic>)> passes,
  required DateTime? Function(Map<String, dynamic> data) createdAt,
  DateTime? now,
  bool Function(Map<String, dynamic> ticket)? facilityPulled,
}) {
  final DateTime at = now ?? DateTime.now();
  final DateTime epoch = DateTime.fromMillisecondsSinceEpoch(0);
  int newestFirst(
    (String, Map<String, dynamic>) a,
    (String, Map<String, dynamic>) b,
  ) => (createdAt(b.$2) ?? epoch).compareTo(createdAt(a.$2) ?? epoch);

  bool paid(Map<String, dynamic> t) =>
      ((t['status'] as String?) ?? '').toLowerCase() == 'paid';
  bool parked(Map<String, dynamic> t) => <String>{
    'checked_in',
    'inside',
  }.contains(((t['entryStatus'] as String?) ?? '').toLowerCase());

  final List<(String, Map<String, dynamic>)> usable =
      tickets
          .where(
            ((String, Map<String, dynamic>) t) =>
                paid(t.$2) &&
                (parked(t.$2) ||
                    (ticketHoursLeft(t.$2) > 0 &&
                        !(facilityPulled?.call(t.$2) ?? false))),
          )
          .toList()
        ..sort(newestFirst);
  for (final (String id, Map<String, dynamic> data) in usable) {
    if (parked(data)) return (kind: 'ticket', id: id, data: data);
  }
  if (usable.isNotEmpty) {
    return (kind: 'ticket', id: usable.first.$1, data: usable.first.$2);
  }
  final List<(String, Map<String, dynamic>)> open = passes.where((
    (String, Map<String, dynamic>) p,
  ) {
    final String status = (p.$2['status'] as String?) ?? '';
    if (status == 'pending') return true;
    final Object? raw = p.$2['expiresAt'];
    final DateTime? expires = raw is Timestamp
        ? raw.toDate()
        : raw is DateTime
        ? raw
        : null;
    return status == 'awaiting_gate' &&
        (expires == null || at.isBefore(expires));
  }).toList()..sort(newestFirst);
  if (open.isEmpty) return null;
  return (kind: 'pass', id: open.first.$1, data: open.first.$2);
}

/// The QR a ticket shows. Tickets saved before the QR string was stored
/// get a scanner-compatible payload rebuilt from the ticket (the gate needs
/// JSON with at least the transaction id, never a bare id).
String ticketQrPayload(String id, Map<String, dynamic> data) {
  final String stored = ((data['qrCode'] as String?) ?? '').trim();
  if (stored.isNotEmpty) return stored;
  final DateTime? issuedAt =
      spParseDateTime(data['createdAt']) ??
      spParseDateTime(data['createdAtClient']);
  return jsonEncode(<String, dynamic>{
    'transactionId': id,
    'driverId': (data['driverId'] as String?) ?? '',
    'establishmentId':
        (data['establishmentId'] as String?) ??
        (data['establishmentID'] as String?) ??
        '',
    'vehicleType': (data['vehicleType'] as String?) ?? '',
    'vehiclePlate': (data['vehiclePlate'] as String?) ?? '',
    'plan': (data['plan'] as String?) ?? '',
    'duration': (data['duration'] as num?)?.toInt() ?? 0,
    'generatedAt': (issuedAt ?? DateTime.now()).toIso8601String(),
  });
}

/// [data] (a ticket, or a temporary QR when [kind] is "pass") as saved on
/// this phone for offline use.
SavedTicket savedTicketFrom(String kind, String id, Map<String, dynamic> data) {
  final String entry = ((data['entryStatus'] as String?) ?? '').toLowerCase();
  return SavedTicket(
    id: id,
    kind: kind,
    qr: kind == 'pass'
        ? ((data['qrCode'] as String?) ?? '').trim()
        : ticketQrPayload(id, data),
    plate: ((data['vehiclePlate'] as String?) ?? '').trim(),
    vehicleType: ((data['vehicleType'] as String?) ?? '').trim(),
    facilityName: ((data['establishmentName'] as String?) ?? '').trim(),
    hoursLeft: kind == 'pass' ? 0 : ticketHoursLeft(data),
    savedAt: DateTime.now(),
    parked: entry == 'checked_in' || entry == 'inside',
  );
}
