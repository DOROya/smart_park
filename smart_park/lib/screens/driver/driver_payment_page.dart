import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../theme/app_theme.dart';

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
        backgroundColor: AppTheme.surface,
        surfaceTintColor: AppTheme.surface,
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
                    color: AppTheme.textSecondary,
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
                            borderRadius: BorderRadius.circular(
                              AppTheme.radiusSmall,
                            ),
                            child: Ink(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: selected
                                    ? AppTheme.accentSoft
                                    : AppTheme.surfaceAlt,
                                borderRadius: BorderRadius.circular(
                                  AppTheme.radiusSmall,
                                ),
                                border: Border.all(
                                  color: selected
                                      ? AppTheme.accent
                                      : AppTheme.border,
                                  width: selected ? 1.5 : 1,
                                ),
                              ),
                              child: Row(
                                children: [
                                  Icon(method.icon, color: AppTheme.textDark),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      method.label,
                                      style: TextStyle(
                                        color: AppTheme.textDark,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                  Radio<DriverPaymentMethod>(
                                    value: method,
                                    activeColor: AppTheme.accentText,
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
              foregroundColor: AppTheme.onAccent,
              minimumSize: const Size.fromHeight(54),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
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
          style: TextStyle(
            color: AppTheme.textSecondary,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          initialValue: value,
          isExpanded: true,
          decoration: InputDecoration(
            contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.all(
                Radius.circular(AppTheme.radiusSmall),
              ),
              borderSide: BorderSide(color: AppTheme.border),
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
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
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
        color: AppTheme.ink,
        borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
      ),
      child: Row(
        children: [
          const Icon(Icons.receipt_long_rounded, color: AppTheme.accent),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${vehicleType[0].toUpperCase()}${vehicleType.substring(1)} | ${plan[0].toUpperCase()}${plan.substring(1)}',
                  style: TextStyle(
                    color: AppTheme.onInk.withValues(alpha: 0.85),
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  'Parking charge',
                  style: TextStyle(
                    color: AppTheme.onInk.withValues(alpha: 0.7),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          Text(
            amount > 0 ? 'PHP ${amount.toStringAsFixed(2)}' : 'Not set',
            style: TextStyle(
              color: AppTheme.onInk,
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
        color: AppTheme.surfaceAlt,
        borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline_rounded, color: AppTheme.textSecondary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: AppTheme.textSecondary,
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
        backgroundColor: AppTheme.surface,
        surfaceTintColor: AppTheme.surface,
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
                  decoration: BoxDecoration(
                    color: AppTheme.accentSoft,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.lock_outline_rounded,
                    color: AppTheme.textDark,
                    size: 30,
                  ),
                ),
                const SizedBox(height: 14),
                Text(
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
                  style: TextStyle(color: AppTheme.textMuted),
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
              foregroundColor: AppTheme.onAccent,
              minimumSize: const Size.fromHeight(54),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
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
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
        border: Border.all(color: AppTheme.border),
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
              borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
              border: Border.all(color: AppTheme.border),
            ),
            child: Text(
              'PayMongo opens a hosted checkout where you enter card or wallet test details. Your parking ticket is issued only after the payment is confirmed.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppTheme.textMuted,
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
        Text(label, style: TextStyle(color: AppTheme.textMuted, fontSize: 12)),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
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
