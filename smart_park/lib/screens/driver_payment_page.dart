import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme/app_theme.dart';

enum DriverPaymentMethod { card, gcash, maya, shopeepay, qrph }

extension DriverPaymentMethodDetails on DriverPaymentMethod {
  String get label => switch (this) {
    DriverPaymentMethod.card => 'Card',
    DriverPaymentMethod.gcash => 'GCash',
    DriverPaymentMethod.maya => 'Maya',
    DriverPaymentMethod.shopeepay => 'ShopeePay',
    DriverPaymentMethod.qrph => 'QR Ph',
  };

  String get apiType => switch (this) {
    DriverPaymentMethod.card => 'card',
    DriverPaymentMethod.gcash => 'gcash',
    DriverPaymentMethod.maya => 'paymaya',
    DriverPaymentMethod.shopeepay => 'shopeepay',
    DriverPaymentMethod.qrph => 'qrph',
  };

  IconData get icon => switch (this) {
    DriverPaymentMethod.card => Icons.credit_card_rounded,
    DriverPaymentMethod.gcash => Icons.account_balance_wallet_rounded,
    DriverPaymentMethod.maya => Icons.wallet_rounded,
    DriverPaymentMethod.shopeepay => Icons.shopping_bag_rounded,
    DriverPaymentMethod.qrph => Icons.qr_code_rounded,
  };

  String get testGuidance => switch (this) {
    DriverPaymentMethod.card =>
      'Use a PayMongo test card to complete the checkout.',
    DriverPaymentMethod.gcash ||
    DriverPaymentMethod.maya ||
    DriverPaymentMethod.shopeepay =>
      'Use the PayMongo test page to authorize or fail this e-wallet payment.',
    DriverPaymentMethod.qrph =>
      'Use the PayMongo test URL to simulate the QR Ph payment result.',
  };
}

class DriverPaymentSelection {
  const DriverPaymentSelection({
    required this.vehicleType,
    required this.plan,
    required this.method,
  });

  final String vehicleType;
  final String plan;
  final DriverPaymentMethod method;
}

class DriverPaymentPage extends StatefulWidget {
  const DriverPaymentPage({
    super.key,
    required this.establishmentName,
    required this.ratesByType,
    required this.vehicleTypes,
    required this.packageRates,
    required this.isPayMongoConfigured,
  });

  final String establishmentName;
  final Map<String, dynamic> ratesByType;
  final List<String> vehicleTypes;
  final Map<String, dynamic> packageRates;
  final bool isPayMongoConfigured;

  @override
  State<DriverPaymentPage> createState() => _DriverPaymentPageState();
}

class _DriverPaymentPageState extends State<DriverPaymentPage> {
  late String _vehicleType;
  String _plan = 'hourly';
  DriverPaymentMethod _method = DriverPaymentMethod.card;

  @override
  void initState() {
    super.initState();
    _vehicleType = widget.vehicleTypes.isNotEmpty
        ? widget.vehicleTypes.first
        : widget.ratesByType.keys.first;
  }

  double get _amount {
    final dynamic vehicleValue = widget.ratesByType[_vehicleType];
    final Map<String, dynamic> vehicleRates = _asMap(vehicleValue);
    final dynamic rate = _plan == 'hourly'
        ? vehicleValue
        : vehicleRates[_plan] ?? widget.packageRates[_plan];
    return _parseAmount(rate);
  }

  Map<String, dynamic> _asMap(dynamic value) {
    if (value is Map) {
      return value.map<String, dynamic>(
        (dynamic key, dynamic item) =>
            MapEntry<String, dynamic>(key.toString(), item),
      );
    }
    return <String, dynamic>{};
  }

  double _parseAmount(dynamic value) {
    if (value is num) {
      return value.toDouble();
    }
    final String text = (value as String?)?.trim() ?? '';
    final Match? match = RegExp(r'([0-9]+(?:\.[0-9]+)?)').firstMatch(text);
    return double.tryParse(match?.group(1) ?? '') ?? 0;
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool isAmountAvailable = _amount > 0;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        title: const Text('Payment'),
      ),
      body: SafeArea(
        top: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 120),
              children: [
                Text(
                  'Complete your parking payment',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    color: AppTheme.textDark,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  widget.establishmentName,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: const Color(0xFF626978),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 18),
                _section(
                  title: 'Parking details',
                  child: Column(
                    children: [
                      _selectionRow(
                        label: 'Vehicle type',
                        value: _vehicleType,
                        values: widget.vehicleTypes.isNotEmpty
                            ? widget.vehicleTypes
                            : widget.ratesByType.keys.toList(),
                        onChanged: (String value) {
                          setState(() => _vehicleType = value);
                        },
                      ),
                      const SizedBox(height: 16),
                      _selectionRow(
                        label: 'Parking plan',
                        value: _plan,
                        values: const <String>[
                          'hourly',
                          'daily',
                          'weekly',
                          'monthly',
                        ],
                        onChanged: (String value) {
                          setState(() => _plan = value);
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                _section(
                  title: 'Payment method',
                  child: RadioGroup<DriverPaymentMethod>(
                    groupValue: _method,
                    onChanged: (DriverPaymentMethod? value) {
                      if (value != null) {
                        setState(() => _method = value);
                      }
                    },
                    child: Column(
                      children: DriverPaymentMethod.values.map((method) {
                        final bool selected = method == _method;
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: InkWell(
                            onTap: () => setState(() => _method = method),
                            borderRadius: BorderRadius.circular(8),
                            child: Ink(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: selected
                                    ? const Color(0xFFFFF5D6)
                                    : const Color(0xFFF9FAFC),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: selected
                                      ? const Color(0xFFE3B329)
                                      : const Color(0xFFE1E5EC),
                                  width: selected ? 1.5 : 1,
                                ),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    method.icon,
                                    color: const Color(0xFF363D4B),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      method.label,
                                      style: const TextStyle(
                                        color: AppTheme.textDark,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                  Radio<DriverPaymentMethod>(
                                    value: method,
                                    activeColor: const Color(0xFFC49100),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                _PaymentSummary(
                  vehicleType: _vehicleType,
                  plan: _plan,
                  amount: _amount,
                ),
                const SizedBox(height: 12),
                _TestNotice(
                  message: widget.isPayMongoConfigured
                      ? _method.testGuidance
                      : 'PayMongo test keys are not configured. Add the required dart-defines before testing payments.',
                ),
              ],
            ),
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(16, 10, 16, 16),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: FilledButton.icon(
            onPressed: widget.isPayMongoConfigured && isAmountAvailable
                ? () {
                    Navigator.of(context).pop(
                      DriverPaymentSelection(
                        vehicleType: _vehicleType,
                        plan: _plan,
                        method: _method,
                      ),
                    );
                  }
                : null,
            style: FilledButton.styleFrom(
              backgroundColor: AppTheme.accent,
              foregroundColor: const Color(0xFF252A34),
              minimumSize: const Size.fromHeight(54),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            icon: const Icon(Icons.lock_outline_rounded),
            label: Text(
              isAmountAvailable ? 'Continue to checkout' : 'Rate unavailable',
            ),
          ),
        ),
      ),
    );
  }

  Widget _selectionRow({
    required String label,
    required String value,
    required List<String> values,
    required ValueChanged<String> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Color(0xFF4C5361),
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          initialValue: value,
          isExpanded: true,
          decoration: const InputDecoration(
            contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.all(Radius.circular(8)),
              borderSide: BorderSide(color: Color(0xFFE1E5EC)),
            ),
          ),
          items: values
              .map(
                (item) => DropdownMenuItem<String>(
                  value: item,
                  child: Text(_titleCase(item)),
                ),
              )
              .toList(),
          onChanged: (String? selection) {
            if (selection != null) {
              onChanged(selection);
            }
          },
        ),
      ],
    );
  }

  String _titleCase(String value) =>
      '${value[0].toUpperCase()}${value.substring(1)}';

  Widget _section({required String title, required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE1E5EC)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: AppTheme.textDark,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

class _PaymentSummary extends StatelessWidget {
  const _PaymentSummary({
    required this.vehicleType,
    required this.plan,
    required this.amount,
  });

  final String vehicleType;
  final String plan;
  final double amount;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF252C38),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          const Icon(Icons.receipt_long_rounded, color: Color(0xFFF7D45D)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${vehicleType[0].toUpperCase()}${vehicleType.substring(1)} | ${plan[0].toUpperCase()}${plan.substring(1)}',
                  style: const TextStyle(color: Color(0xFFD6DCE5)),
                ),
                const SizedBox(height: 3),
                const Text(
                  'Parking charge',
                  style: TextStyle(color: Color(0xFFABB4C2), fontSize: 12),
                ),
              ],
            ),
          ),
          Text(
            amount > 0 ? 'PHP ${amount.toStringAsFixed(2)}' : 'Not set',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _TestNotice extends StatelessWidget {
  const _TestNotice({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF4F6FA),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFDCE3ED)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline_rounded, color: Color(0xFF4B6584)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: Color(0xFF4C5C70),
                fontSize: 12,
                height: 1.45,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class PaymentCheckoutPage extends StatefulWidget {
  const PaymentCheckoutPage({
    super.key,
    required this.establishmentName,
    required this.amount,
    required this.method,
    required this.checkoutUrl,
  });

  final String establishmentName;
  final double amount;
  final DriverPaymentMethod method;
  final String checkoutUrl;

  @override
  State<PaymentCheckoutPage> createState() => _PaymentCheckoutPageState();
}

class _PaymentCheckoutPageState extends State<PaymentCheckoutPage> {
  bool _openingCheckout = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _openCheckout();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        automaticallyImplyLeading: false,
        title: const Text('Payment in progress'),
        actions: [
          IconButton(
            tooltip: 'Close',
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close_rounded),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
              children: [
                Container(
                  width: 56,
                  height: 56,
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(
                    color: Color(0xFFFFF2BE),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.lock_outline_rounded,
                    color: Color(0xFF2F3744),
                    size: 30,
                  ),
                ),
                const SizedBox(height: 14),
                const Text(
                  'Complete your secure payment',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AppTheme.textDark,
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  widget.establishmentName,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Color(0xFF687181)),
                ),
                const SizedBox(height: 20),
                _checkoutCard(),
                const SizedBox(height: 14),
                _TestNotice(message: widget.method.testGuidance),
              ],
            ),
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: FilledButton.icon(
            onPressed: _openingCheckout ? null : _openCheckout,
            style: FilledButton.styleFrom(
              backgroundColor: AppTheme.accent,
              foregroundColor: const Color(0xFF252A34),
              minimumSize: const Size.fromHeight(54),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            icon: _openingCheckout
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.open_in_new_rounded),
            label: Text(
              _openingCheckout
                  ? 'Opening secure checkout...'
                  : 'Open PayMongo checkout',
            ),
          ),
        ),
      ),
    );
  }

  Widget _checkoutCard() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE1E5EC)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _detail(
                  'Amount due',
                  'PHP ${widget.amount.toStringAsFixed(2)}',
                ),
              ),
              Expanded(child: _detail('Method', widget.method.label)),
            ],
          ),
          const Divider(height: 28),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFE2E6ED)),
            ),
            child: const Text(
              'PayMongo opens a hosted checkout where you enter card or wallet test details. Your parking ticket is issued only after the payment is confirmed.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Color(0xFF697384),
                fontSize: 12,
                height: 1.4,
              ),
            ),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: _copyCheckoutUrl,
            icon: const Icon(Icons.content_copy_rounded, size: 18),
            label: const Text('Copy checkout link'),
          ),
        ],
      ),
    );
  }

  Widget _detail(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(color: Color(0xFF737E8E), fontSize: 12),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            color: AppTheme.textDark,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }

  Future<void> _openCheckout() async {
    if (_openingCheckout) {
      return;
    }
    setState(() {
      _openingCheckout = true;
    });
    final Uri uri = Uri.parse(widget.checkoutUrl);
    final bool launched = await launchUrl(
      uri,
      mode: LaunchMode.externalApplication,
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _openingCheckout = false;
    });
    if (!launched) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to open PayMongo checkout.')),
      );
    }
  }

  Future<void> _copyCheckoutUrl() async {
    await Clipboard.setData(ClipboardData(text: widget.checkoutUrl));
  }
}
