import 'dart:convert';

import 'package:http/http.dart' as http;

/// Payment methods PayMongo is allowed to offer at checkout for SmartPark.
const List<String> kSupportedSplitPaymentMethods = <String>[
  'card',
  'gcash',
  'paymaya',
  'qrph',
];

/// Breakdown of a single split-payment transaction, all amounts in centavos.
///
/// PayMongo deducts its own processing fee (variable per payment method -
/// e.g. higher for card, lower for QR Ph) directly from the gross amount
/// during settlement, before the funds ever reach SmartPark's balance.
/// That processor fee is entirely separate from - and never reduces -
/// SmartPark's fixed [platformFeeCentavos] cut. The [destinationAccountId]
/// (parking owner's sub-account) simply receives whatever remains once both
/// the estimated processor fee and the platform fee are set aside.
class SplitPaymentBreakdown {
  const SplitPaymentBreakdown({
    required this.grossAmountCentavos,
    required this.platformFeeCentavos,
    required this.estimatedProcessorFeeCentavos,
    required this.destinationAccountId,
  });

  final int grossAmountCentavos;
  final int platformFeeCentavos;
  final int estimatedProcessorFeeCentavos;
  final String destinationAccountId;

  /// Amount the parking owner receives after PayMongo's processor fee and
  /// SmartPark's platform fee are both taken out of the original gross.
  int get netToOwnerCentavos =>
      grossAmountCentavos - platformFeeCentavos - estimatedProcessorFeeCentavos;

  Map<String, dynamic> toMap() => <String, dynamic>{
    'grossAmountCentavos': grossAmountCentavos,
    'platformFeeCentavos': platformFeeCentavos,
    'estimatedProcessorFeeCentavos': estimatedProcessorFeeCentavos,
    'netToOwnerCentavos': netToOwnerCentavos,
    'destinationAccountId': destinationAccountId,
  };
}

/// Rough processor-fee estimate per payment method, used only for
/// reconciliation/display - PayMongo's actual settlement report is the
/// source of truth for the real deducted amount.
int estimateProcessorFeeCentavos({
  required int grossAmountCentavos,
  required String paymentMethodApiType,
}) {
  final double rate = switch (paymentMethodApiType) {
    'card' => 0.035, // ~3.5% + fixed fee (fixed fee omitted from estimate)
    'gcash' || 'paymaya' => 0.02, // ~2.0% for e-wallets
    'qrph' => 0.0134, // ~1.34% for QR Ph
    _ => 0.02,
  };
  return (grossAmountCentavos * rate).round();
}

/// Builds the exact JSON request body for a PayMongo checkout session that
/// carries SmartPark's automated split: a fixed [platformFeeCentavos] cut
/// for the platform, and the remainder routed to the parking owner's
/// [destinationAccountId] sub-account. Kept as a plain payload builder (not
/// tied to an HTTP call) so it can be reused, previewed, or unit-tested
/// independently of the network layer.
Map<String, dynamic> buildSplitPaymentCheckoutPayload({
  required int amountInCentavos,
  required String description,
  required String destinationAccountId,
  String? remarks,
  List<String>? paymentMethodTypes,
  Map<String, dynamic>? metadata,
  double platformFeeRate = 0.05,
}) {
  if (amountInCentavos <= 0) {
    throw ArgumentError.value(
      amountInCentavos,
      'amountInCentavos',
      'Amount should be greater than zero.',
    );
  }
  if (destinationAccountId.trim().isEmpty) {
    throw ArgumentError.value(
      destinationAccountId,
      'destinationAccountId',
      'A destination account (parking owner sub-account) is required.',
    );
  }

  final List<String> requestedMethods = paymentMethodTypes == null
      ? kSupportedSplitPaymentMethods
      : paymentMethodTypes
            .where(kSupportedSplitPaymentMethods.contains)
            .toSet()
            .toList();

  // 5% of the gross transaction, always computed from the original total -
  // PayMongo's own processing fee is settled separately and never erodes it.
  final int platformFeeCentavos = (amountInCentavos * platformFeeRate).round();

  return <String, dynamic>{
    'data': <String, dynamic>{
      'attributes': <String, dynamic>{
        'description': description,
        'currency': 'PHP',
        'line_items': <Map<String, dynamic>>[
          <String, dynamic>{
            'amount': amountInCentavos,
            'currency': 'PHP',
            'description': remarks ?? description,
            'name': description,
            'quantity': 1,
          },
        ],
        'payment_method_types': requestedMethods.isEmpty
            ? kSupportedSplitPaymentMethods
            : requestedMethods,
        'show_line_items': true,
        'success_url': 'https://smartpark.app/payment-success',
        'cancel_url': 'https://smartpark.app/payment-cancel',
        // SmartPark-specific split instructions consumed by our own backend
        // reconciliation job (and mirrored into metadata for auditability).
        'platform_fee': platformFeeCentavos,
        'destination_account': destinationAccountId,
        'metadata': <String, dynamic>{
          ...?metadata,
          'platform_fee': platformFeeCentavos,
          'destination_account': destinationAccountId,
        },
      },
    },
  };
}

class PayMongoCheckoutLink {
  const PayMongoCheckoutLink({
    required this.id,
    required this.checkoutUrl,
    required this.referenceNumber,
    required this.status,
    this.redirectUrl,
    this.testUrl,
    required this.rawResponse,
  });

  final String id;
  final String checkoutUrl;
  final String referenceNumber;
  final String status;
  final String? redirectUrl;
  final String? testUrl;
  final Map<String, dynamic> rawResponse;

  bool get isPaid {
    if (status.toLowerCase() == 'paid') {
      return true;
    }
    final dynamic data = rawResponse['data'];
    if (data is Map) {
      final dynamic attributes = data['attributes'];
      if (attributes is Map) {
        final String attrStatus = (attributes['status'] as String?)?.toLowerCase() ?? '';
        if (attrStatus == 'paid') {
          return true;
        }
        final dynamic payments = attributes['payments'];
        if (payments is List && payments.isNotEmpty) {
          for (final dynamic p in payments) {
            if (p is Map) {
              final dynamic pAttr = p['attributes'];
              if (pAttr is Map) {
                final String pStatus = (pAttr['status'] as String?)?.toLowerCase() ?? '';
                if (pStatus == 'paid') {
                  return true;
                }
              }
            }
          }
        }
      }
    }
    return false;
  }
}

class PayMongoTestService {
  const PayMongoTestService({
    required this.secretKey,
    required this.publicKey,
    this.baseUrl = 'https://api.paymongo.com/v1',
  });

  const PayMongoTestService.fromEnvironment()
    : secretKey = const String.fromEnvironment('PAYMONGO_SECRET_KEY'),
      publicKey = const String.fromEnvironment('PAYMONGO_PUBLIC_KEY'),
      baseUrl = 'https://api.paymongo.com/v1';

  final String secretKey;
  final String publicKey;
  final String baseUrl;

  bool get isConfigured => secretKey.trim().isNotEmpty && publicKey.trim().isNotEmpty;

  Future<PayMongoCheckoutLink> createCheckoutLink({
    required int amountInCentavos,
    required String description,
    String? remarks,
    List<String>? paymentMethodTypes,
    Map<String, dynamic>? metadata,
  }) async {
    if (!isConfigured) {
      throw StateError(
        'PayMongo test keys are missing. Provide PAYMONGO_SECRET_KEY and PAYMONGO_PUBLIC_KEY via --dart-define.',
      );
    }

    if (amountInCentavos <= 0) {
      throw ArgumentError.value(amountInCentavos, 'amountInCentavos', 'Amount should be greater than zero.');
    }

    final Uri endpoint = Uri.parse('$baseUrl/checkout_sessions');
    final String authToken = base64Encode(utf8.encode('${secretKey.trim()}:'));
    const List<String> supportedPaymentMethods = <String>[
      'card',
      'gcash',
      'paymaya',
      'qrph',
    ];
    final List<String> requestedMethods = paymentMethodTypes == null
        ? supportedPaymentMethods
        : paymentMethodTypes
              .where(supportedPaymentMethods.contains)
              .toSet()
              .toList();

    final Map<String, dynamic> body = <String, dynamic>{
      'data': <String, dynamic>{
        'attributes': <String, dynamic>{
          'description': description,
          'line_items': <Map<String, dynamic>>[
            <String, dynamic>{
              'amount': amountInCentavos,
              'currency': 'PHP',
              'description': remarks ?? description,
              'name': description,
              'quantity': 1,
            },
          ],
          'payment_method_types': requestedMethods.isEmpty
              ? supportedPaymentMethods
              : requestedMethods,
          'show_line_items': true,
          'success_url': 'https://smartpark.app/payment-success',
          'cancel_url': 'https://smartpark.app/payment-cancel',
          if (metadata != null && metadata.isNotEmpty) 'metadata': metadata,
        },
      },
    };

    final http.Response response = await http.post(
      endpoint,
      headers: <String, String>{
        'accept': 'application/json',
        'content-type': 'application/json',
        'authorization': 'Basic $authToken',
      },
      body: jsonEncode(body),
    );

    final Map<String, dynamic> decoded =
        (jsonDecode(response.body) as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};

    if (response.statusCode < 200 || response.statusCode >= 300) {
      final dynamic errors = decoded['errors'];
      final String message = errors is List && errors.isNotEmpty
          ? (errors.first['detail']?.toString() ?? 'PayMongo request failed.')
          : 'PayMongo request failed with status ${response.statusCode}.';
      throw StateError(message);
    }

    final Map<String, dynamic> data =
        (decoded['data'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};
    final Map<String, dynamic> attributes =
        (data['attributes'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};

    final String id = (data['id'] as String?) ?? '';
    final String checkoutUrl = (attributes['checkout_url'] as String?) ?? '';
    final String referenceNumber = (attributes['reference_number'] as String?) ?? '';
    final String status = (attributes['status'] as String?) ?? 'unknown';
    final String? redirectUrl = _readStringPath(attributes, <String>[
      'next_action',
      'redirect',
      'url',
    ]);
    final String? testUrl = _readStringPath(attributes, <String>[
      'next_action',
      'redirect',
      'test_url',
    ]);

    if (id.isEmpty || checkoutUrl.isEmpty) {
      throw StateError('PayMongo response is missing required checkout session fields.');
    }

    return PayMongoCheckoutLink(
      id: id,
      checkoutUrl: checkoutUrl,
      referenceNumber: referenceNumber,
      status: status,
      redirectUrl: redirectUrl,
      testUrl: testUrl,
      rawResponse: decoded,
    );
  }

  /// Creates a checkout session using [buildSplitPaymentCheckoutPayload], so
  /// SmartPark's platform fee and the parking owner's destination account
  /// are attached to the session up front.
  Future<PayMongoCheckoutLink> createSplitCheckoutLink({
    required int amountInCentavos,
    required String description,
    required String destinationAccountId,
    String? remarks,
    List<String>? paymentMethodTypes,
    Map<String, dynamic>? metadata,
    double platformFeeRate = 0.05,
  }) async {
    if (!isConfigured) {
      throw StateError(
        'PayMongo test keys are missing. Provide PAYMONGO_SECRET_KEY and PAYMONGO_PUBLIC_KEY via --dart-define.',
      );
    }

    final Map<String, dynamic> body = buildSplitPaymentCheckoutPayload(
      amountInCentavos: amountInCentavos,
      description: description,
      destinationAccountId: destinationAccountId,
      remarks: remarks,
      paymentMethodTypes: paymentMethodTypes,
      metadata: metadata,
      platformFeeRate: platformFeeRate,
    );

    return _postCheckoutSession(body);
  }

  Future<PayMongoCheckoutLink> _postCheckoutSession(
    Map<String, dynamic> body,
  ) async {
    final Uri endpoint = Uri.parse('$baseUrl/checkout_sessions');
    final String authToken = base64Encode(utf8.encode('${secretKey.trim()}:'));

    final http.Response response = await http.post(
      endpoint,
      headers: <String, String>{
        'accept': 'application/json',
        'content-type': 'application/json',
        'authorization': 'Basic $authToken',
      },
      body: jsonEncode(body),
    );

    final Map<String, dynamic> decoded =
        (jsonDecode(response.body) as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};

    if (response.statusCode < 200 || response.statusCode >= 300) {
      final dynamic errors = decoded['errors'];
      final String message = errors is List && errors.isNotEmpty
          ? (errors.first['detail']?.toString() ?? 'PayMongo request failed.')
          : 'PayMongo request failed with status ${response.statusCode}.';
      throw StateError(message);
    }

    final Map<String, dynamic> data =
        (decoded['data'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};
    final Map<String, dynamic> attributes =
        (data['attributes'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};

    final String id = (data['id'] as String?) ?? '';
    final String checkoutUrl = (attributes['checkout_url'] as String?) ?? '';
    final String referenceNumber = (attributes['reference_number'] as String?) ?? '';
    final String status = (attributes['status'] as String?) ?? 'unknown';
    final String? redirectUrl = _readStringPath(attributes, <String>[
      'next_action',
      'redirect',
      'url',
    ]);
    final String? testUrl = _readStringPath(attributes, <String>[
      'next_action',
      'redirect',
      'test_url',
    ]);

    if (id.isEmpty || checkoutUrl.isEmpty) {
      throw StateError('PayMongo response is missing required checkout session fields.');
    }

    return PayMongoCheckoutLink(
      id: id,
      checkoutUrl: checkoutUrl,
      referenceNumber: referenceNumber,
      status: status,
      redirectUrl: redirectUrl,
      testUrl: testUrl,
      rawResponse: decoded,
    );
  }

  Future<PayMongoCheckoutLink> getCheckoutLink(String checkoutLinkId) async {
    if (!isConfigured) {
      throw StateError(
        'PayMongo test keys are missing. Provide PAYMONGO_SECRET_KEY and PAYMONGO_PUBLIC_KEY via --dart-define.',
      );
    }

    final Uri endpoint = Uri.parse('$baseUrl/checkout_sessions/$checkoutLinkId');
    final String authToken = base64Encode(utf8.encode('${secretKey.trim()}:'));
    final http.Response response = await http.get(
      endpoint,
      headers: <String, String>{
        'accept': 'application/json',
        'authorization': 'Basic $authToken',
      },
    );
    final Map<String, dynamic> decoded =
        (jsonDecode(response.body) as Map?)?.cast<String, dynamic>() ??
        <String, dynamic>{};

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError(
        'Unable to retrieve PayMongo checkout status (${response.statusCode}).',
      );
    }

    final Map<String, dynamic> data =
        (decoded['data'] as Map?)?.cast<String, dynamic>() ??
        <String, dynamic>{};
    final Map<String, dynamic> attributes =
        (data['attributes'] as Map?)?.cast<String, dynamic>() ??
        <String, dynamic>{};
    final String id = (data['id'] as String?) ?? checkoutLinkId;
    final String checkoutUrl = (attributes['checkout_url'] as String?) ?? '';

    if (checkoutUrl.isEmpty) {
      throw StateError('PayMongo response is missing a checkout URL.');
    }

    return PayMongoCheckoutLink(
      id: id,
      checkoutUrl: checkoutUrl,
      referenceNumber: (attributes['reference_number'] as String?) ?? '',
      status: (attributes['status'] as String?) ?? 'unknown',
      redirectUrl: _readStringPath(attributes, <String>[
        'next_action',
        'redirect',
        'url',
      ]),
      testUrl: _readStringPath(attributes, <String>[
        'next_action',
        'redirect',
        'test_url',
      ]),
      rawResponse: decoded,
    );
  }

  Future<PayMongoCheckoutLink> pollCheckoutLink(
    String checkoutLinkId, {
    Duration interval = const Duration(milliseconds: 1500),
    int maxAttempts = 8,
  }) async {
    PayMongoCheckoutLink link = await getCheckoutLink(checkoutLinkId);
    if (link.isPaid) {
      return link;
    }

    for (int i = 0; i < maxAttempts; i++) {
      await Future<void>.delayed(interval);
      try {
        link = await getCheckoutLink(checkoutLinkId);
        if (link.isPaid) {
          return link;
        }
      } catch (_) {
        // Ignore transient poll errors during retry loop
      }
    }
    return link;
  }

  String? _readStringPath(Map<String, dynamic> source, List<String> path) {
    dynamic cursor = source;
    for (final String key in path) {
      if (cursor is! Map || !cursor.containsKey(key)) {
        return null;
      }
      cursor = cursor[key];
    }
    final String text = (cursor as String?)?.trim() ?? '';
    return text.isEmpty ? null : text;
  }
}
