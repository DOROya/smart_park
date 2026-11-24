import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// The driver's last active ticket (or temporary QR), saved on this phone
/// when it is shown, so it opens with no signal: from the "Show my ticket"
/// shortcut or the no-internet screen. Staff still check it at the gate.
class SavedTicket {
  const SavedTicket({
    required this.id,
    required this.kind,
    required this.qr,
    required this.plate,
    required this.vehicleType,
    required this.facilityName,
    required this.hoursLeft,
    required this.savedAt,
    this.parked = false,
  });

  /// "ticket" (paid) or "pass" (a temporary QR, paid at the gate).
  final String kind;
  final String id;
  final String qr;
  final String plate;
  final String vehicleType;
  final String facilityName;

  /// Hours left when it was saved; shown "as of" [savedAt].
  final int hoursLeft;
  final DateTime savedAt;
  final bool parked;

  bool get isPass => kind == 'pass';

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'kind': kind,
    'qr': qr,
    'plate': plate,
    'vehicleType': vehicleType,
    'facilityName': facilityName,
    'hoursLeft': hoursLeft,
    'savedAt': savedAt.toIso8601String(),
    'parked': parked,
  };

  static SavedTicket? fromJson(Object? json) {
    if (json is! Map) return null;
    final String id = (json['id'] as String?) ?? '';
    final String qr = (json['qr'] as String?) ?? '';
    final DateTime? at = DateTime.tryParse((json['savedAt'] as String?) ?? '');
    if (id.isEmpty || qr.isEmpty || at == null) return null;
    return SavedTicket(
      id: id,
      kind: (json['kind'] as String?) == 'pass' ? 'pass' : 'ticket',
      qr: qr,
      plate: (json['plate'] as String?) ?? '',
      vehicleType: (json['vehicleType'] as String?) ?? '',
      facilityName: (json['facilityName'] as String?) ?? '',
      hoursLeft: (json['hoursLeft'] as num?)?.toInt() ?? 0,
      savedAt: at,
      parked: json['parked'] == true,
    );
  }

  /// The same ticket with the same details (only [savedAt] may differ).
  bool sameAs(SavedTicket other) =>
      id == other.id &&
      qr == other.qr &&
      plate == other.plate &&
      hoursLeft == other.hoursLeft &&
      parked == other.parked;
}

/// Per-phone storage for [SavedTicket]. Every call is best effort: storage
/// that can't be read or written never breaks a screen.
class LastTicketStore {
  static const String _key = 'last_active_ticket_v1';
  static SavedTicket? _lastSaved;

  static Future<SavedTicket?> load() async {
    try {
      final String? raw = (await SharedPreferences.getInstance()).getString(
        _key,
      );
      return raw == null ? null : SavedTicket.fromJson(jsonDecode(raw));
    } catch (_) {
      return null;
    }
  }

  /// Saves [ticket] unless the same one was just saved.
  static Future<void> save(SavedTicket ticket) async {
    if (_lastSaved?.sameAs(ticket) ?? false) return;
    _lastSaved = ticket;
    try {
      await (await SharedPreferences.getInstance()).setString(
        _key,
        jsonEncode(ticket.toJson()),
      );
    } catch (_) {
      // Not saved: the ticket still shows while online.
    }
  }

  /// On sign-out, and when no ticket is active any more.
  static Future<void> clear() async {
    _lastSaved = null;
    try {
      await (await SharedPreferences.getInstance()).remove(_key);
    } catch (_) {
      // Nothing to do.
    }
  }
}
