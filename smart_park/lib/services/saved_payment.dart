import 'dart:convert';

import 'package:http/http.dart' as http;

/// Payment details entered with a temporary QR, so that at the gate the
/// driver only confirms. Nothing here charges anything.
///
/// A GCash or Maya number is sent to the server and kept on the QR. A card
/// goes from this phone straight to PayMongo, which returns a token
/// (`pm_...`); only that token and the last four digits are kept, never the
/// card number.

/// PayMongo's public key, from `--dart-define-from-file=paymongo.dev.json`
/// (or `--dart-define=PAYMONGO_PUBLIC_KEY=...`). Without it a card is
/// entered on PayMongo's page at the gate instead.
const String kPayMongoPublicKey = String.fromEnvironment('PAYMONGO_PUBLIC_KEY');

bool get canSaveCards => kPayMongoPublicKey.isNotEmpty;

/// What the driver saved: a wallet number, or a card token.
class SavedPaymentDetails {
  const SavedPaymentDetails({this.phone = '', this.cardPaymentMethodId = ''});

  static const SavedPaymentDetails none = SavedPaymentDetails();

  final String phone;
  final String cardPaymentMethodId;
}

/// "+639171234567" from "0917 123 4567", "9171234567", "+63 917-123-4567";
/// null if it isn't a Philippine mobile number. Mirrors the server's check.
String? normalizePhMobile(String raw) {
  final String digits = raw.replaceAll(RegExp(r'[\s\-().]'), '');
  final Match? m = RegExp(r'^(?:\+?63|0)?(9\d{9})$').firstMatch(digits);
  return m == null ? null : '+63${m.group(1)}';
}

/// "0917 123 4567" from a saved "+639171234567", for showing and editing;
/// '' for anything else.
String localPhMobile(String saved) {
  final String? n = normalizePhMobile(saved);
  if (n == null) return '';
  final String local = '0${n.substring(3)}';
  return '${local.substring(0, 4)} ${local.substring(4, 7)} ${local.substring(7)}';
}

/// Card number digits only.
String cardDigits(String raw) => raw.replaceAll(RegExp(r'\D'), '');

/// Luhn check, so a mistyped card number is caught before PayMongo.
bool isValidCardNumber(String raw) {
  final String digits = cardDigits(raw);
  if (digits.length < 13 || digits.length > 19) return false;
  int sum = 0;
  bool double = false;
  for (int i = digits.length - 1; i >= 0; i--) {
    int d = digits.codeUnitAt(i) - 48;
    if (double) {
      d *= 2;
      if (d > 9) d -= 9;
    }
    sum += d;
    double = !double;
  }
  return sum % 10 == 0;
}

/// (month, four-digit year) from "MM/YY" or "MM/YYYY", or null when it is
/// malformed or already past [now].
({int month, int year})? parseCardExpiry(String raw, {DateTime? now}) {
  final Match? m = RegExp(
    r'^\s*(\d{1,2})\s*/\s*(\d{2}|\d{4})\s*$',
  ).firstMatch(raw);
  if (m == null) return null;
  final int month = int.parse(m.group(1)!);
  int year = int.parse(m.group(2)!);
  if (year < 100) year += 2000;
  if (month < 1 || month > 12) return null;
  final DateTime today = now ?? DateTime.now();
  if (year < today.year || (year == today.year && month < today.month)) {
    return null;
  }
  return (month: month, year: year);
}

bool isValidCvc(String raw) => RegExp(r'^\d{3,4}$').hasMatch(raw.trim());

class CardSaveException implements Exception {
  const CardSaveException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Saves a card with PayMongo and returns its token. Nothing is charged.
Future<String> savePayMongoCard({
  required String number,
  required int expMonth,
  required int expYear,
  required String cvc,
  required String name,
  String email = '',
  http.Client? client,
}) async {
  if (!canSaveCards) {
    throw const CardSaveException('Cards can only be entered at the gate.');
  }
  final http.Client c = client ?? http.Client();
  try {
    final http.Response response = await c
        .post(
          Uri.parse('https://api.paymongo.com/v1/payment_methods'),
          headers: <String, String>{
            'accept': 'application/json',
            'content-type': 'application/json',
            'authorization':
                'Basic ${base64Encode(utf8.encode('$kPayMongoPublicKey:'))}',
          },
          body: jsonEncode(<String, dynamic>{
            'data': <String, dynamic>{
              'attributes': <String, dynamic>{
                'type': 'card',
                'details': <String, dynamic>{
                  'card_number': cardDigits(number),
                  'exp_month': expMonth,
                  'exp_year': expYear,
                  'cvc': cvc.trim(),
                },
                'billing': <String, dynamic>{
                  'name': name.trim(),
                  if (email.trim().isNotEmpty) 'email': email.trim(),
                },
              },
            },
          }),
        )
        .timeout(const Duration(seconds: 20));
    final Object? decoded = jsonDecode(response.body);
    final Map<dynamic, dynamic> body = decoded is Map ? decoded : const {};
    final Object? data = body['data'];
    final Object? id = data is Map ? data['id'] : null;
    if (response.statusCode >= 200 &&
        response.statusCode < 300 &&
        id is String) {
      return id;
    }
    final Object? errors = body['errors'];
    final Object? first = errors is List && errors.isNotEmpty
        ? errors.first
        : null;
    final Object? detail = first is Map ? first['detail'] : null;
    throw CardSaveException(
      detail is String && detail.isNotEmpty
          ? detail
          : 'Could not save this card. Check the details and try again.',
    );
  } on CardSaveException {
    rethrow;
  } catch (_) {
    throw const CardSaveException(
      'Could not reach PayMongo to save the card. Check your connection.',
    );
  } finally {
    if (client == null) c.close();
  }
}
