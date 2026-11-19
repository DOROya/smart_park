import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/saved_payment.dart';
import '../../theme/app_theme.dart';
import '../../widgets/sp_vehicle_type.dart';
import 'driver_payment_page.dart';

class DriverCheckoutPaymentSelection {
  const DriverCheckoutPaymentSelection({
    required this.method,
    this.saved = SavedPaymentDetails.none,
  });

  final DriverPaymentMethod method;
  final SavedPaymentDetails saved;
}

/// Wallets paid from a saved mobile number.
bool _isWallet(DriverPaymentMethod m) =>
    m == DriverPaymentMethod.gcash || m == DriverPaymentMethod.maya;

class DriverCheckoutPaymentPage extends StatefulWidget {
  const DriverCheckoutPaymentPage({
    super.key,
    required this.establishmentName,
    required this.vehicleLabel,
    required this.plan,
    required this.duration,
    required this.amount,
    required this.isPayMongoConfigured,
    this.onProcessPayment,
  });

  final String establishmentName;
  final String vehicleLabel;
  final String plan;
  final int duration;
  final double amount;
  final bool isPayMongoConfigured;
  final Future<bool> Function(
    DriverPaymentMethod method,
    SavedPaymentDetails saved,
  )?
  onProcessPayment;

  @override
  State<DriverCheckoutPaymentPage> createState() =>
      _DriverCheckoutPaymentPageState();
}

class _DriverCheckoutPaymentPageState extends State<DriverCheckoutPaymentPage> {
  DriverPaymentMethod _selectedMethod = DriverPaymentMethod.card;
  bool _isProcessing = false;

  // Entered now so that at the gate the driver only confirms.
  final TextEditingController _phone = TextEditingController();
  final TextEditingController _cardNumber = TextEditingController();
  final TextEditingController _cardExpiry = TextEditingController();
  final TextEditingController _cardCvc = TextEditingController();
  final TextEditingController _cardName = TextEditingController();
  String? _detailsError;

  @override
  void dispose() {
    _phone.dispose();
    _cardNumber.dispose();
    _cardExpiry.dispose();
    _cardCvc.dispose();
    _cardName.dispose();
    super.dispose();
  }

  String _amountText(double amount) {
    return amount % 1 == 0
        ? 'P${amount.toStringAsFixed(0)}'
        : 'P${amount.toStringAsFixed(2)}';
  }

  bool get _savesCard =>
      _selectedMethod == DriverPaymentMethod.card && canSaveCards;

  /// Checks the entered details and saves a card with PayMongo. Null (with
  /// [_detailsError] set) when something needs fixing.
  Future<SavedPaymentDetails?> _collectDetails() async {
    if (_isWallet(_selectedMethod)) {
      final String? phone = normalizePhMobile(_phone.text);
      if (phone == null) {
        setState(
          () => _detailsError =
              'Enter your ${_selectedMethod.label} number, e.g. 0917 123 4567.',
        );
        return null;
      }
      return SavedPaymentDetails(phone: phone);
    }
    if (!_savesCard) return SavedPaymentDetails.none;

    final ({int month, int year})? expiry = parseCardExpiry(_cardExpiry.text);
    final String? problem = !isValidCardNumber(_cardNumber.text)
        ? 'Check the card number.'
        : expiry == null
        ? 'Enter the expiry as MM/YY.'
        : !isValidCvc(_cardCvc.text)
        ? 'Enter the 3 or 4 digit CVC.'
        : _cardName.text.trim().isEmpty
        ? 'Enter the name on the card.'
        : null;
    if (problem != null) {
      setState(() => _detailsError = problem);
      return null;
    }
    String email = '';
    try {
      email = FirebaseAuth.instance.currentUser?.email ?? '';
    } catch (_) {
      // Not signed in (tests); PayMongo doesn't need it.
    }
    try {
      final String token = await savePayMongoCard(
        number: _cardNumber.text,
        expMonth: expiry!.month,
        expYear: expiry.year,
        cvc: _cardCvc.text,
        name: _cardName.text,
        email: email,
      );
      return SavedPaymentDetails(cardPaymentMethodId: token);
    } on CardSaveException catch (error) {
      if (mounted) setState(() => _detailsError = error.message);
      return null;
    }
  }

  Future<void> _handlePay() async {
    if (_isProcessing) return;
    setState(() {
      _isProcessing = true;
      _detailsError = null;
    });
    try {
      final SavedPaymentDetails? saved = await _collectDetails();
      if (saved == null || !mounted) return;
      if (widget.onProcessPayment != null) {
        final bool success = await widget.onProcessPayment!(
          _selectedMethod,
          saved,
        );
        if (success && mounted) {
          Navigator.of(context).pop(true);
        }
      } else {
        Navigator.of(context).pop(
          DriverCheckoutPaymentSelection(method: _selectedMethod, saved: saved),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
      }
    }
  }

  /// The details for the picked method, saved with the QR.
  Widget _detailsSection() {
    final List<Widget> fields;
    final String note;
    if (_isWallet(_selectedMethod)) {
      fields = <Widget>[
        _field(
          controller: _phone,
          label: '${_selectedMethod.label} mobile number',
          hint: '0917 123 4567',
          keyboard: TextInputType.phone,
          formatters: <TextInputFormatter>[
            FilteringTextInputFormatter.allow(RegExp(r'[0-9+\s-]')),
            LengthLimitingTextInputFormatter(16),
          ],
        ),
      ];
      note =
          'At the gate you only tap Confirm, then approve it in '
          '${_selectedMethod.label}.';
    } else if (_savesCard) {
      fields = <Widget>[
        _field(
          controller: _cardNumber,
          label: 'Card number',
          hint: '4343 4343 4343 4345',
          keyboard: TextInputType.number,
          formatters: <TextInputFormatter>[
            FilteringTextInputFormatter.allow(RegExp(r'[0-9 ]')),
            LengthLimitingTextInputFormatter(23),
          ],
          autofill: const <String>[AutofillHints.creditCardNumber],
        ),
        Row(
          children: <Widget>[
            Expanded(
              child: _field(
                controller: _cardExpiry,
                label: 'Expiry',
                hint: 'MM/YY',
                keyboard: TextInputType.datetime,
                formatters: <TextInputFormatter>[
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9/]')),
                  LengthLimitingTextInputFormatter(7),
                ],
                autofill: const <String>[
                  AutofillHints.creditCardExpirationDate,
                ],
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _field(
                controller: _cardCvc,
                label: 'CVC',
                hint: '123',
                keyboard: TextInputType.number,
                obscure: true,
                formatters: <TextInputFormatter>[
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(4),
                ],
                autofill: const <String>[AutofillHints.creditCardSecurityCode],
              ),
            ),
          ],
        ),
        _field(
          controller: _cardName,
          label: 'Name on card',
          hint: 'Juan Dela Cruz',
          keyboard: TextInputType.name,
          autofill: const <String>[AutofillHints.creditCardName],
        ),
      ];
      note =
          'Your card is saved with PayMongo, not SmartPark, and is not '
          'charged now. At the gate you only tap Confirm (your bank may '
          'send an OTP).';
    } else if (_selectedMethod == DriverPaymentMethod.card) {
      fields = const <Widget>[];
      note = 'You enter your card on the payment page at the gate.';
    } else {
      fields = const <Widget>[];
      note =
          'Nothing to enter now. At the gate you pay by scanning a QR Ph '
          'code with your banking or e-wallet app.';
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const SizedBox(height: 8),
        Text(
          'Payment Details',
          style: TextStyle(
            color: AppTheme.textDark,
            fontSize: 15,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 10),
        if (fields.isNotEmpty)
          AutofillGroup(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                for (final Widget f in fields)
                  Padding(padding: const EdgeInsets.only(bottom: 10), child: f),
              ],
            ),
          ),
        if (_detailsError != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              _detailsError!,
              style: TextStyle(
                color: AppTheme.danger,
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        Text(
          note,
          style: TextStyle(
            color: AppTheme.textSecondary,
            fontSize: 12,
            height: 1.35,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _field({
    required TextEditingController controller,
    required String label,
    required String hint,
    required TextInputType keyboard,
    List<TextInputFormatter> formatters = const <TextInputFormatter>[],
    Iterable<String>? autofill,
    bool obscure = false,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboard,
      inputFormatters: formatters,
      autofillHints: autofill,
      obscureText: obscure,
      enabled: !_isProcessing,
      onChanged: (_) {
        if (_detailsError != null) setState(() => _detailsError = null);
      },
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        isDense: true,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final List<DriverPaymentMethod> methods = <DriverPaymentMethod>[
      DriverPaymentMethod.card,
      DriverPaymentMethod.gcash,
      DriverPaymentMethod.maya,
      DriverPaymentMethod.qrph,
    ];

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.surface,
        surfaceTintColor: AppTheme.surface,
        titleSpacing: 8,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Payment Method',
              style: TextStyle(
                color: AppTheme.textDark,
                fontSize: 17,
                fontWeight: FontWeight.w800,
              ),
            ),
            Text(
              widget.establishmentName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: AppTheme.textMuted,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 18),
              color: AppTheme.accentSoft,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Step 3 of 3',
                    style: TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: const [
                      _StepDot(complete: true),
                      _StepLine(),
                      _StepDot(complete: true),
                      _StepLine(),
                      _StepDot(selected: true),
                    ],
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppTheme.accentSoft,
                        borderRadius: BorderRadius.circular(AppTheme.radius),
                        border: Border.all(color: const Color(0xFFF0D67A)),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Pay at the Gate',
                                  style: TextStyle(
                                    color: AppTheme.textSecondary,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '${widget.vehicleLabel} · ${widget.plan}',
                                  style: TextStyle(
                                    color: AppTheme.textDark,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Text(
                            _amountText(widget.amount),
                            style: TextStyle(
                              color: AppTheme.textDark,
                              fontSize: 26,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.info_outline_rounded,
                          size: 16,
                          color: AppTheme.textSecondary,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            spTicketSharingRule(widget.vehicleLabel),
                            style: TextStyle(
                              color: AppTheme.textSecondary,
                              fontSize: 12,
                              height: 1.35,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.verified_user_outlined,
                          size: 16,
                          color: AppTheme.textSecondary,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'You are not charged now. You get a temporary QR '
                            '(valid 3 days). At the gate, once staff confirm '
                            'there is space, you tap Confirm to pay '
                            '${_amountText(widget.amount)}. You will need '
                            'mobile data there.',
                            style: TextStyle(
                              color: AppTheme.textSecondary,
                              fontSize: 12,
                              height: 1.35,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 22),
                    Text(
                      'Choose Payment Method',
                      style: TextStyle(
                        color: AppTheme.textDark,
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 10),
                    ...methods.map((DriverPaymentMethod method) {
                      final bool isSelected = method == _selectedMethod;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: InkWell(
                          onTap: _isProcessing
                              ? null
                              : () {
                                  setState(() {
                                    _selectedMethod = method;
                                    _detailsError = null;
                                  });
                                },
                          borderRadius: BorderRadius.circular(AppTheme.radius),
                          child: Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? AppTheme.accentSoft
                                  : AppTheme.surface,
                              borderRadius: BorderRadius.circular(
                                AppTheme.radius,
                              ),
                              border: Border.all(
                                color: isSelected
                                    ? AppTheme.accent
                                    : AppTheme.border,
                                width: isSelected ? 1.6 : 1,
                              ),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 40,
                                  height: 40,
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    color: AppTheme.surfaceAlt,
                                    borderRadius: BorderRadius.circular(
                                      AppTheme.radiusSmall,
                                    ),
                                  ),
                                  child: Icon(
                                    method.icon,
                                    color: AppTheme.textDark,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        method.label,
                                        style: TextStyle(
                                          color: AppTheme.textDark,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        method == DriverPaymentMethod.card
                                            ? 'Credit or debit card'
                                            : (method ==
                                                      DriverPaymentMethod.qrph
                                                  ? 'Pay using any QR Ph app'
                                                  : 'Pay with ${method.label}'),
                                        style: TextStyle(
                                          color: AppTheme.textMuted,
                                          fontSize: 11,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Icon(
                                  isSelected
                                      ? Icons.radio_button_checked_rounded
                                      : Icons.radio_button_off_rounded,
                                  color: isSelected
                                      ? AppTheme.accentText
                                      : AppTheme.borderStrong,
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    }),
                    _detailsSection(),
                    if (!widget.isPayMongoConfigured)
                      Padding(
                        padding: EdgeInsets.only(top: 4),
                        child: Text(
                          'Payments are unavailable until PayMongo test keys are configured.',
                          style: TextStyle(
                            color: AppTheme.warning,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            SafeArea(
              top: false,
              minimum: const EdgeInsets.fromLTRB(16, 10, 16, 14),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: (widget.isPayMongoConfigured && !_isProcessing)
                      ? _handlePay
                      : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.accent,
                    foregroundColor: AppTheme.onAccent,
                    disabledBackgroundColor: AppTheme.border,
                    disabledForegroundColor: AppTheme.textMuted,
                    minimumSize: const Size.fromHeight(50),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppTheme.radius),
                    ),
                  ),
                  child: _isProcessing
                      ? SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppTheme.onAccent,
                          ),
                        )
                      : Text(
                          'Get Temporary QR',
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StepDot extends StatelessWidget {
  const _StepDot({this.selected = false, this.complete = false});

  final bool selected;
  final bool complete;

  @override
  Widget build(BuildContext context) {
    final bool emphasized = selected || complete;
    return Container(
      width: 24,
      height: 24,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: emphasized ? AppTheme.textDark : AppTheme.accentLight,
        shape: BoxShape.circle,
      ),
      child: complete
          ? Icon(Icons.check_rounded, color: AppTheme.onInk, size: 15)
          : Text(
              '3',
              style: TextStyle(
                color: AppTheme.onInk,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
    );
  }
}

class _StepLine extends StatelessWidget {
  const _StepLine();

  @override
  Widget build(BuildContext context) {
    return const Expanded(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 8),
        child: Divider(color: AppTheme.accent, thickness: 2),
      ),
    );
  }
}
