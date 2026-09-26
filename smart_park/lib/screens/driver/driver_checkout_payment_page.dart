import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import 'driver_payment_page.dart';

class DriverCheckoutPaymentSelection {
  const DriverCheckoutPaymentSelection({required this.method});

  final DriverPaymentMethod method;
}

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
  final Future<bool> Function(DriverPaymentMethod method)? onProcessPayment;

  @override
  State<DriverCheckoutPaymentPage> createState() =>
      _DriverCheckoutPaymentPageState();
}

class _DriverCheckoutPaymentPageState extends State<DriverCheckoutPaymentPage> {
  DriverPaymentMethod _selectedMethod = DriverPaymentMethod.card;
  bool _isProcessing = false;

  String _amountText(double amount) {
    return amount % 1 == 0
        ? 'P${amount.toStringAsFixed(0)}'
        : 'P${amount.toStringAsFixed(2)}';
  }

  Future<void> _handlePay() async {
    if (_isProcessing) return;

    if (widget.onProcessPayment != null) {
      setState(() {
        _isProcessing = true;
      });
      try {
        final bool success = await widget.onProcessPayment!(_selectedMethod);
        if (success && mounted) {
          Navigator.of(context).pop(true);
        }
      } finally {
        if (mounted) {
          setState(() {
            _isProcessing = false;
          });
        }
      }
    } else {
      Navigator.of(
        context,
      ).pop(DriverCheckoutPaymentSelection(method: _selectedMethod));
    }
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
                                  'Amount to Pay',
                                  style: TextStyle(
                                    color: AppTheme.textSecondary,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '${widget.vehicleLabel} · ${widget.duration} ${widget.plan}',
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
                          onTap: () {
                            setState(() {
                              _selectedMethod = method;
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
                          'Pay ${_amountText(widget.amount)}',
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
