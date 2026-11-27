import 'dart:convert';

import '../utils/staff_credentials.dart';
import 'smartpark_ui.dart';
import 'sp_vehicle_type.dart';

// Turns the raw parts of an audit entry (Firestore field paths, and values
// the Cloud Function stored as JSON text) into words for people.
// Works on old entries too, since nothing about the stored data changes.

/// Facility, staff and report fields, as the app's forms name them.
const Map<String, String> _fieldLabels = <String, String>{
  'name': 'Name',
  'address': 'Address',
  'contactNumber': 'Contact number',
  'location': 'Map pin',
  'operatingHours': 'Operating hours',
  'open24Hours': 'Open 24 hours',
  'openTime': 'Opening time',
  'closeTime': 'Closing time',
  'availability': 'Availability',
  'policies': 'Policies',
  'rates': 'Rates',
  'ratesByType': 'Rates',
  'pricing': 'Rates',
  'slotCounts': 'Slots',
  'gracePeriodMinutes': 'Grace period',
  'allowLongTermRates': 'Weekly and monthly rates',
  'status': 'Status',
  'rejectionReason': 'Reason for rejection',
  'restrictionReason': 'Reason for restriction',
  'complianceNotice': 'Notice',
  'photoUrls': 'Photos',
  'businessDocumentUrls': 'Business documents',
  'businessDocumentsUpdatedAt': 'Documents updated',
  'closedUntil': 'Closed until',
  'closedReason': 'Reason for closing',
  'closedAt': 'Closed on',
  'ownerFirstName': 'Owner first name',
  'ownerLastName': 'Owner last name',
  'ownerEmail': 'Owner email',
  'firstName': 'First name',
  'lastName': 'Last name',
  'email': 'Email',
  'username': 'Username',
  'role': 'Role',
  'active': 'Active',
  'isActive': 'Active',
  'reasons': 'Reasons',
  'message': 'Message',
  'note': 'Note',
  'adminNote': 'Admin note',
  'contestMessage': 'Driver\'s reply',
  'decision': 'Decision',
  'decisionReason': 'Reason for decision',
  'dueAt': 'Due by',
  'issuedAt': 'Given on',
  'overtimeStatus': 'Overtime',
  'amountCentavos': 'Amount',
  'owedCentavosAfter': 'Still owed after',
  'files': 'Files deleted',
  'amount': 'Total',
  'walkInAmount': 'Walk-in cash',
  'overtimeAmount': 'Overtime fees',
  'logCount': 'Gate records',
  'staffName': 'Staff member',
  'passwordResetAt': 'Password reset',
  'deactivatedAt': 'Deactivated on',
  'endedAt': 'Shift ended',
  'adminLevel': 'Admin level',
  '...': 'Other fields',
};

/// The parts of a vehicle's rate, as the owner's form names them.
const Map<String, String> _ratePartLabels = <String, String>{
  'initial': 'base rate',
  'hourly': 'base rate',
  'succeedingHour': 'rate per extra hour',
  'succeedingDaily': 'daily rate',
  'daily': 'daily rate',
  'weekly': 'weekly rate',
  'monthly': 'monthly rate',
  'overtime': 'overtime rate',
  'overtimeRate': 'overtime rate',
};

/// Bookkeeping fields: ids, and copies of something shown elsewhere.
const Set<String> _hiddenFields = <String>{
  'establishmentID',
  'establishmentId',
  'reviewedAt',
  'reviewedBy',
  'resubmittedAt',
  'issuedBy',
  'closedBy',
  'latitude',
  'longitude',
  'slots', // an old copy of slotCounts, always zero
  'receivedAt', // the entry's own time, shown in its header
};

/// Field names that hold an account or document id, which means nothing to
/// people: ownerId, staffId, facilityId, establishmentID, and the "...By"
/// fields (closedBy, receivedBy, reviewedBy, endedBy) that hold a uid.
final RegExp _idField = RegExp(r'(Id|ID|Uid|By)$');

/// A bare Firebase uid or document id, e.g. "3028hHByKZbq6nbw3wnO0tD7f253".
final RegExp _idValue = RegExp(r'^[A-Za-z0-9]{20,36}$');

/// Fields read in this order when an entry has several (a cash handover:
/// who, the total, then what it is made of).
const List<String> _fieldOrder = <String>[
  'name',
  'staffName',
  'role',
  'adminLevel',
  'status',
  'active',
  'amount',
  'walkInAmount',
  'overtimeAmount',
  'logCount',
];

/// When the first field changed, the others only repeat it.
const Map<String, List<String>> _covers = <String, List<String>>{
  'operatingHours': <String>['open24Hours', 'openTime', 'closeTime'],
  'location': <String>['latitude', 'longitude'],
  'rates': <String>['pricing', 'ratesByType'],
  'ratesByType': <String>['pricing'],
};

/// "plateNumber" -> "Plate number".
String _humanize(String key) {
  final String spaced = key
      .replaceAll('_', ' ')
      .replaceAllMapped(
        RegExp(r'(?<=[a-z0-9])([A-Z])'),
        (Match m) => ' ${m[1]!.toLowerCase()}',
      )
      .trim();
  if (spaced.isEmpty) return key;
  return '${spaced[0].toUpperCase()}${spaced.substring(1)}';
}

String _lowerFirst(String text) =>
    text.isEmpty ? text : '${text[0].toLowerCase()}${text.substring(1)}';

String _capitalize(String text) =>
    text.isEmpty ? text : '${text[0].toUpperCase()}${text.substring(1)}';

/// The label of one field path, e.g. "rates.car.initial" -> "Car base rate",
/// "slotCounts.motorcycle" -> "Motorcycle slots",
/// "complianceNotice.dueAt" -> "Notice due by".
/// Labels the server already made readable ("Car daily rate") stay as is.
String spAuditFieldLabel(String path) {
  if (path.contains(' ')) return path;
  final List<String> parts = path.split('.');
  final String top = parts.first;

  if ((top == 'rates' || top == 'ratesByType') && parts.length >= 2) {
    final String vehicle = spVehicleTypeLabel(parts[1]);
    if (parts.length == 2) return '$vehicle rates';
    final String part = parts[2];
    return '$vehicle ${_ratePartLabels[part] ?? _lowerFirst(_humanize(part))}';
  }
  if ((top == 'slotCounts' || top == 'slots') && parts.length == 2) {
    return '${spVehicleTypeLabel(parts[1])} slots';
  }

  final String head = _fieldLabels[top] ?? _humanize(top);
  if (parts.length == 1) return head;
  final String rest = parts
      .skip(1)
      .map((String p) => _lowerFirst(_fieldLabels[p] ?? _humanize(p)))
      .join(' ');
  return '$head $rest';
}

bool _isHidden(String path) {
  final String first = path.split('.').first;
  final String last = path.split('.').last;
  return _hiddenFields.contains(first) ||
      _hiddenFields.contains(last) ||
      first == 'userId' ||
      _idField.hasMatch(first) ||
      _idField.hasMatch(last);
}

/// A value nobody can read: an id, or a staff member's sign-in address
/// (staff only ever see their username).
bool _isUnreadableValue(Object? value) {
  if (value is! String) return false;
  final String text = value.trim();
  return _idValue.hasMatch(text) || isStaffAuthEmail(text);
}

/// A change as the server stores it: {from, to}.
bool _isFromTo(Object? value) =>
    value is Map && (value.containsKey('from') || value.containsKey('to'));

/// Whether a stored change has nothing worth showing: both sides empty, or
/// only ids.
bool _isEmptyChange(String field, Object? value) {
  if (!_isFromTo(value)) {
    return _isUnreadableValue(value) ||
        spAuditValueText(value, field: field) == 'none';
  }
  value as Map<dynamic, dynamic>;
  final Object? from = value['from'];
  final Object? to = value['to'];
  final bool fromEmpty =
      _isUnreadableValue(from) ||
      spAuditValueText(from, field: field) == 'none';
  final bool toEmpty =
      _isUnreadableValue(to) || spAuditValueText(to, field: field) == 'none';
  return fromEmpty && toEmpty;
}

/// The changes worth showing, labelled, in their stored order: hides ids and
/// bookkeeping, empty changes ("none" to "none"), and fields that only
/// repeat another change (the opening time when the operating hours line
/// already says it).
List<MapEntry<String, Object?>> spAuditVisibleChanges(
  Map<String, dynamic> changes,
) {
  final Set<String> tops = changes.keys
      .map((String k) => k.split('.').first)
      .toSet();
  final Set<String> repeated = <String>{
    for (final String field in tops) ...?_covers[field],
  };
  final List<MapEntry<String, Object?>> shown = <MapEntry<String, Object?>>[
    for (final MapEntry<String, dynamic> e in changes.entries)
      if (!_isHidden(e.key) &&
          !repeated.contains(e.key.split('.').first) &&
          e.key != '...' &&
          !_isEmptyChange(e.key, e.value))
        MapEntry<String, Object?>(e.key, e.value),
  ];
  // Firestore keeps map keys in no set order: put the usual reading order
  // first (who, then the money), and the rest as stored.
  int rank(String key) {
    final int at = _fieldOrder.indexOf(key.split('.').first);
    return at < 0 ? _fieldOrder.length : at;
  }

  // Stable: fields of equal rank keep their stored order.
  final List<int> index = List<int>.generate(shown.length, (int i) => i)
    ..sort((int a, int b) {
      final int byRank = rank(shown[a].key).compareTo(rank(shown[b].key));
      return byRank != 0 ? byRank : a.compareTo(b);
    });
  final List<MapEntry<String, Object?>> ordered = <MapEntry<String, Object?>>[
    for (final int i in index) shown[i],
  ];
  return ordered;
}

final RegExp _isoDate = RegExp(r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}');
final RegExp _clock24 = RegExp(r'^([01]?\d|2[0-3]):([0-5]\d)$');
final RegExp _geo = RegExp(r'^(-?\d+\.\d+),\s*(-?\d+\.\d+)$');

String _peso(num amount) =>
    'PHP ${amount == amount.roundToDouble() ? amount.toInt() : amount.toStringAsFixed(2)}';

/// Cash amounts read like the rest of the app's money: "PHP 30.00".
String _cash(num amount) => 'PHP ${amount.toStringAsFixed(2)}';

bool _isCashField(String last) =>
    last.toLowerCase().endsWith('amount') && !last.endsWith('Centavos');

/// Role and admin-level values as the app names them.
const Map<String, String> _roleNames = <String, String>{
  'super': 'Super admin',
  'admin': 'Admin',
  'supervisor': 'Supervisor',
  'staff': 'Staff',
  'driver': 'Driver',
  'owner': 'Parking owner',
  'parking_owner': 'Parking owner',
  'parkingowner': 'Parking owner',
};

bool _isRateField(String field) {
  final String top = field.split('.').first;
  return top == 'rates' ||
      top == 'ratesByType' ||
      _ratePartLabels.containsKey(field.split('.').last);
}

/// A stored value in words, for the field at [field] (a path such as
/// "rates.car.initial", or "" when unknown).
String spAuditValueText(Object? value, {String field = ''}) {
  final String last = field.split('.').last;
  if (value == null) return 'none';
  if (value is bool) return value ? 'Yes' : 'No';

  if (value is num) {
    if (last == 'amountCentavos' || last.endsWith('Centavos')) {
      return _peso(value / 100);
    }
    if (_isCashField(last)) return _cash(value);
    if (last == 'gracePeriodMinutes') {
      return value == 1 ? '1 minute' : '$value minutes';
    }
    if (_isRateField(field)) return _peso(value);
    return '$value';
  }

  if (value is String) {
    final String text = value.trim();
    if (text.isEmpty) return 'none';
    // Ends in "..." when the server cut a long value short.
    if ((text.startsWith('{') &&
            (text.endsWith('}') || text.endsWith('...'))) ||
        (text.startsWith('[') &&
            (text.endsWith(']') || text.endsWith('...')))) {
      try {
        return spAuditValueText(jsonDecode(text), field: field);
      } on FormatException {
        // Cut short at 300 characters by the server: show the readable part.
        return _stripJson(text);
      }
    }
    if (_isoDate.hasMatch(text)) {
      final DateTime? at = spParseDateTime(text)?.toLocal();
      if (at != null) return '${spFormatDate(at)}, ${spFormatClockTime(at)}';
    }
    final Match? clock = _clock24.firstMatch(text);
    if (clock != null && (last == 'openTime' || last == 'closeTime')) {
      final DateTime t = DateTime(
        2000,
        1,
        1,
        int.parse(clock[1]!),
        int.parse(clock[2]!),
      );
      return spFormatClockTime(t);
    }
    final Match? geo = _geo.firstMatch(text);
    if (geo != null) {
      return '${double.parse(geo[1]!).toStringAsFixed(5)}, '
          '${double.parse(geo[2]!).toStringAsFixed(5)}';
    }
    if (_isRateField(field) && num.tryParse(text) != null) {
      return _peso(num.parse(text));
    }
    if (last == 'role' || last == 'adminLevel') {
      return _roleNames[text.toLowerCase().replaceAll(' ', '_')] ??
          _capitalize(text);
    }
    if (_isCashField(last) && num.tryParse(text) != null) {
      return _cash(num.parse(text));
    }
    if (last == 'status' || last == 'overtimeStatus') {
      return _capitalize(text.replaceAll('_', ' '));
    }
    if (text.startsWith('http://') || text.startsWith('https://')) {
      return '1 file';
    }
    return text;
  }

  if (value is List) {
    if (value.isEmpty) return 'none';
    if (value.every((Object? v) => v is String && v.startsWith('http'))) {
      final String noun = last.toLowerCase().contains('photo')
          ? 'photo'
          : 'file';
      return value.length == 1 ? '1 $noun' : '${value.length} ${noun}s';
    }
    return value
        .map((Object? v) => spAuditValueText(v, field: field))
        .join(', ');
  }

  if (value is Map) {
    final List<String> parts = <String>[];
    for (final MapEntry<dynamic, dynamic> e in value.entries) {
      final String key = '${e.key}';
      final String path = field.isEmpty ? key : '$field.$key';
      if (_isHidden(path)) continue;
      final String shown = spAuditValueText(e.value, field: path);
      if (shown == 'none') continue;
      final String top = path.split('.').first;
      final bool vehicleMap =
          top == 'rates' || top == 'ratesByType' || top.startsWith('slot');
      final String label = vehicleMap
          ? _capitalize(_shortLabel(path))
          : (_fieldLabels[key] ?? _humanize(key));
      parts.add(e.value is Map ? '$label ($shown)' : '$label: $shown');
    }
    return parts.isEmpty ? 'none' : parts.join(', ');
  }

  return '$value';
}

/// Inside a rates or slots map, the vehicle is already named by the parent:
/// "rates.car.initial" -> "base rate", "slotCounts.car" -> "car".
String _shortLabel(String path) {
  final List<String> parts = path.split('.');
  if (parts.first.startsWith('rates') && parts.length >= 3) {
    return _ratePartLabels[parts[2]] ?? _humanize(parts[2]);
  }
  if (parts.length == 2) return spVehicleTypeLabel(parts[1]);
  return _humanize(parts.last);
}

/// Last resort for JSON cut off mid-way: drop the brackets and quotes.
String _stripJson(String text) => text
    .replaceAll(RegExp(r'[{}\[\]"]'), '')
    .replaceAll(':', ': ')
    .replaceAll(',', ', ')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

/// "PHP 250  →  PHP 251"; the new value alone when there was none before
/// (something just created); "Nov 28, 3:50 PM  →  removed" when it was
/// cleared; or the value alone when the change is not a from/to pair.
String spAuditChangeText(String field, Object? value) {
  if (!_isFromTo(value)) return spAuditValueText(value, field: field);
  value as Map<dynamic, dynamic>;
  if (field == '...') return 'More fields changed';
  final String from = spAuditValueText(value['from'], field: field);
  final String to = spAuditValueText(value['to'], field: field);
  if (from == 'none') return to;
  if (to == 'none') return '$from  →  removed';
  return '$from  →  $to';
}

/// Actions whose summary ends in a list of raw field names, e.g.
/// "Edited facility details (slotCounts, gracePeriodMinutes)".
const Set<String> _fieldListActions = <String>{
  'facility.details_updated',
  'facility.updated',
  'facility.rates_changed',
  'staff.updated',
  'driver.warning_updated',
};

/// The entry's headline, with a trailing list of field names put in words:
/// "Edited facility details: slots and grace period".
String spAuditSummaryText(String action, String summary) {
  // Entries made before the server chose "a" or "an": "Made X a admin".
  final String text = summary.trim().replaceAll(
    RegExp(r'\ba admin\b'),
    'an admin',
  );
  if (text.isEmpty) return _humanize(action.replaceAll('.', ' '));
  if (!_fieldListActions.contains(action)) return text;
  final Match? m = RegExp(r'^(.*?)\s*\(([\w.,\s]+)\)$').firstMatch(text);
  if (m == null) return text;
  final List<String> fields = m[2]!
      .split(',')
      .map((String f) => f.trim())
      .where((String f) => f.isNotEmpty)
      .toList();
  final Set<String> covered = <String>{
    for (final String f in fields) ...?_covers[f],
  };
  final List<String> labels = <String>[];
  for (final String f in fields) {
    if (_isHidden(f) || covered.contains(f)) continue;
    final String label = _lowerFirst(spAuditFieldLabel(f));
    if (!labels.contains(label)) labels.add(label);
  }
  if (labels.isEmpty) return m[1]!;
  final String list = labels.length == 1
      ? labels.first
      : '${labels.sublist(0, labels.length - 1).join(', ')} and ${labels.last}';
  return '${m[1]}: $list';
}

/// One detail line of an entry, split so the old and new values can be
/// styled apart.
class SpAuditLine {
  const SpAuditLine({
    required this.label,
    required this.value,
    this.before,
    this.cleared = false,
  });

  final String label;

  /// The value now (or, when [cleared], the value that was removed).
  final String value;

  /// The value it replaced; null when there was none.
  final String? before;

  /// The field was emptied: [value] is what it used to hold.
  final bool cleared;
}

/// Fields that only restate an entry's headline, per action.
const Map<String, Set<String>> _restatedByAction = <String, Set<String>>{
  'staff.deactivated': <String>{'active'},
  'staff.reactivated': <String>{'active', 'deactivatedAt'},
  // "Closed the facility until Nov 28, 3:50 PM" / "Reopened the facility".
  'facility.closed_temporarily': <String>{'closedUntil'},
  'facility.reopened': <String>{'closedUntil', 'closedReason'},
};

/// Times that are just the entry's own time ("Deactivated on" when the
/// entry is the deactivation), or a closure's start once it is over.
const Set<String> _alwaysRestated = <String>{'closedAt'};

bool _sameMoment(Object? raw, DateTime? at) {
  if (at == null || raw is! String || !_isoDate.hasMatch(raw.trim())) {
    return false;
  }
  final DateTime? value = spParseDateTime(raw.trim());
  return value != null &&
      value.toUtc().difference(at.toUtc()).inMinutes.abs() <= 2;
}

/// The detail lines of an entry with action [action] made at [at]: the
/// visible changes, minus lines that only repeat the headline or the time.
List<SpAuditLine> spAuditLines(
  Map<String, dynamic> changes, {
  String action = '',
  DateTime? at,
}) {
  final Set<String> restated = <String>{
    ..._alwaysRestated,
    ...?_restatedByAction[action],
  };
  final List<SpAuditLine> lines = <SpAuditLine>[];
  for (final MapEntry<String, Object?> e in spAuditVisibleChanges(changes)) {
    final String top = e.key.split('.').first;
    if (restated.contains(top)) continue;
    final String label = spAuditFieldLabel(e.key);
    final Object? raw = e.value;
    if (!_isFromTo(raw)) {
      if (_sameMoment(raw, at)) continue;
      lines.add(
        SpAuditLine(
          label: label,
          value: spAuditValueText(raw, field: e.key),
        ),
      );
      continue;
    }
    raw as Map<dynamic, dynamic>;
    final Object? fromRaw = raw['from'];
    final Object? toRaw = raw['to'];
    final String from = spAuditValueText(fromRaw, field: e.key);
    final String to = spAuditValueText(toRaw, field: e.key);
    if (from == 'none') {
      if (_sameMoment(toRaw, at)) continue;
      lines.add(SpAuditLine(label: label, value: to));
    } else if (to == 'none') {
      lines.add(SpAuditLine(label: label, value: from, cleared: true));
    } else {
      lines.add(SpAuditLine(label: label, value: to, before: from));
    }
  }
  return lines;
}
