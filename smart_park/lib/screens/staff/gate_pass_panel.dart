import 'dart:async';

import 'package:flutter/material.dart';

import '../../services/error_reporter.dart';
import '../../services/gate_scan_service.dart';
import '../../services/parking_checkout_service.dart';
import '../../services/parking_receipt.dart' show ParkingReceipt;
import '../../theme/app_theme.dart';
import '../../utils/friendly_error.dart';
import '../../widgets/sp_ticket_cost.dart';
import '../../widgets/sp_vehicle_type.dart';

/// A scanned temporary QR: nothing is paid yet. Staff check for space,
/// then either start the payment on the driver's phone or turn them away.
/// Once the driver pays, [onPaid] admits the new ticket.
class GatePassPanel extends StatefulWidget {
  const GatePassPanel({
    super.key,
    required this.result,
    required this.passService,
    required this.onPaid,
    required this.onTurnAway,
  });

  final GateScanResult result;
  final GatePassService passService;
  final Future<void> Function(String transactionId) onPaid;
  final Future<void> Function() onTurnAway;

  @override
  State<GatePassPanel> createState() => _GatePassPanelState();
}

class _GatePassPanelState extends State<GatePassPanel> {
  static const Duration _pollInterval = Duration(seconds: 3);

  late bool _paying = widget.result.pass!.status == 'pending';
  bool _busy = false;
  String? _note;
  Timer? _poll;
  bool _checking = false;
  DateTime _payingSince = DateTime.now();

  /// `confirm` until the driver taps Confirm, then `approve`.
  String _stage = '';

  GatePass get _pass => widget.result.pass!;

  @override
  void initState() {
    super.initState();
    if (_paying) _startPolling();
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  void _startPolling() {
    _poll?.cancel();
    _payingSince = DateTime.now();
    _poll = Timer.periodic(_pollInterval, (_) => _check());
  }

  Future<void> _check() async {
    if (_checking) return;
    _checking = true;
    try {
      final ({String status, String stage}) progress = await widget.passService
          .checkPayment(_pass.checkoutId);
      final String status = progress.status;
      if (!mounted) return;
      _stage = progress.stage;
      if (status == 'paid') {
        _poll?.cancel();
        await widget.onPaid(_pass.checkoutId);
      } else if (status != 'pending') {
        _poll?.cancel();
        setState(() {
          _paying = false;
          _note = status == 'timed_out'
              ? 'The payment timed out. Nothing was charged.'
              : 'The payment was stopped. Nothing was charged.';
        });
      } else if (mounted) {
        setState(() {}); // Ticks the waiting time.
      }
    } catch (error) {
      // Keep polling through a dropped request; the server also times out.
      debugPrint('Gate payment check failed: $error');
    } finally {
      _checking = false;
    }
  }

  Future<void> _start() async {
    setState(() {
      _busy = true;
      _note = null;
    });
    try {
      await widget.passService.startPayment(_pass.checkoutId);
      if (!mounted) return;
      setState(() => _paying = true);
      _startPolling();
    } catch (error, stack) {
      reportError(error, stack, reason: 'Start gate payment');
      if (mounted) {
        setState(
          () => _note = friendlyError(
            error,
            fallback: 'Could not start the payment. Try again.',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _cancelPayment() async {
    setState(() => _busy = true);
    try {
      final String status = await widget.passService.cancelPayment(
        _pass.checkoutId,
      );
      _poll?.cancel();
      if (!mounted) return;
      if (status == 'paid') {
        await widget.onPaid(_pass.checkoutId);
        return;
      }
      setState(() {
        _paying = false;
        _note = 'Payment stopped. Nothing was charged.';
      });
    } catch (error) {
      if (mounted) {
        setState(
          () => _note = friendlyError(
            error,
            fallback: 'Could not stop the payment. Try again.',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _turnAway() async {
    setState(() => _busy = true);
    try {
      // Tell the driver first; the gate log below is what must not fail.
      try {
        await widget.passService.turnAway(_pass.checkoutId);
      } catch (error, stack) {
        reportError(error, stack, reason: 'Tell driver of turn away');
      }
      await widget.onTurnAway();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ParkingReceipt t = ParkingReceipt(
      transactionId: _pass.checkoutId,
      facilityName: '',
      amountCentavos: (_pass.amount * 100).round(),
      vehicleType: _pass.vehicleType,
      plan: _pass.plan.toLowerCase(),
      duration: _pass.duration,
    );
    final Duration waited = DateTime.now().difference(_payingSince);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.accentSoft,
        borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
        border: Border.all(color: AppTheme.accent),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(Icons.qr_code_2_rounded, color: AppTheme.accentText),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _paying ? 'Waiting for payment' : 'Temporary QR: not paid',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                    color: AppTheme.textDark,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SpVehicleTypeBadge(vehicleType: _pass.vehicleType, large: true),
          const SizedBox(height: 8),
          Text(
            widget.result.vehiclePlate,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              letterSpacing: 1,
              color: AppTheme.textDark,
            ),
          ),
          const SizedBox(height: 10),
          SpTicketCost(
            ticket: t,
            amountLabel: _paying ? 'PAYING NOW' : 'TO COLLECT',
            amountNote: _methodNote(_pass.paymentMethod),
          ),
          const SizedBox(height: 10),
          if (_paying)
            Text(
              '${gatePaymentStageText(_stage, _pass.paymentMethod)} '
              '(${waited.inMinutes}:${waited.inSeconds.remainder(60).toString().padLeft(2, '0')}). '
              'The gate admits them automatically once paid.',
              style: const TextStyle(height: 1.35),
            )
          else ...<Widget>[
            _step(
              Icons.check_circle_outline_rounded,
              AppTheme.success,
              'There is a free '
              '${spVehicleTypeLabel(spVehicleTypeKey(_pass.vehicleType)).toLowerCase()} '
              'slot',
              _pass.directPay
                  ? 'Tap Take payment. The driver gets a prompt and only '
                        'taps Confirm, since their payment details are saved. '
                        'They are let in as soon as it goes through.'
                  : 'Tap Take payment. The driver pays on their phone, and '
                        'they are let in as soon as it goes through.',
            ),
            const SizedBox(height: 8),
            _step(
              Icons.do_not_disturb_on_outlined,
              AppTheme.danger,
              'The lot is full, or the driver has no mobile data',
              'Tap Turn away. Nothing is charged, and their temporary QR '
                  'still works for a later visit. A driver without data can '
                  'park as a walk-in and pay you in cash instead.',
            ),
          ],
          if (_note != null) ...<Widget>[
            const SizedBox(height: 8),
            Text(
              _note!,
              style: TextStyle(
                color: AppTheme.warning,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
          const SizedBox(height: 12),
          if (_paying)
            Row(
              children: <Widget>[
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const Spacer(),
                TextButton(
                  onPressed: _busy ? null : _cancelPayment,
                  style: TextButton.styleFrom(foregroundColor: AppTheme.danger),
                  child: const Text('Stop payment'),
                ),
              ],
            )
          else
            Row(
              children: <Widget>[
                Expanded(
                  child: OutlinedButton(
                    onPressed: _busy ? null : _turnAway,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.danger,
                      minimumSize: const Size.fromHeight(46),
                    ),
                    // One line on narrow phones (the Y9 and STK-L22).
                    child: const FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text('Turn away', maxLines: 1),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(
                    onPressed: _busy ? null : _start,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppTheme.accent,
                      foregroundColor: AppTheme.onAccent,
                      minimumSize: const Size.fromHeight(46),
                    ),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        _busy ? 'Opening...' : 'Take payment',
                        maxLines: 1,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

/// One decision for staff: the condition in bold, what to tap below it.
Widget _step(IconData icon, Color color, String when, String action) {
  return Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: <Widget>[
      Icon(icon, size: 20, color: color),
      const SizedBox(width: 8),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              when,
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: AppTheme.textDark,
              ),
            ),
            Text(action, style: const TextStyle(height: 1.3)),
          ],
        ),
      ),
    ],
  );
}

/// What staff tell a waiting driver, from the server's payment stage:
/// "check your phone" while they haven't confirmed, "almost there" once
/// they are approving it.
String gatePaymentStageText(String stage, String apiType) => switch (stage) {
  'confirm' =>
    'Driver notified. Waiting for them to tap Confirm on their phone',
  'approve' =>
    'Driver is approving the payment${switch (apiType) {
      'gcash' => ' in GCash',
      'paymaya' => ' in Maya',
      'card' => ' (their bank may send an OTP)',
      _ => '',
    }}',
  _ => 'Waiting for the driver to pay on their phone',
};

/// "Pay with GCash" for the method the driver picked.
String _methodNote(String apiType) => switch (apiType) {
  'card' => 'Pay with card',
  'gcash' => 'Pay with GCash',
  'paymaya' => 'Pay with Maya',
  'qrph' => 'Pay with QR Ph',
  _ => 'Online payment',
};
