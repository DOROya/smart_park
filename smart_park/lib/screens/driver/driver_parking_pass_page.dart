import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../services/error_reporter.dart';
import '../../services/parking_checkout_service.dart';
import '../../services/parking_receipt.dart';
import '../../theme/app_theme.dart';
import '../../utils/friendly_error.dart';
import '../../widgets/smartpark_ui.dart' show spPeso;
import '../../widgets/sp_max_brightness.dart';
import '../../widgets/sp_save_qr_button.dart';
import '../../widgets/sp_ticket_cost.dart';
import '../../widgets/sp_vehicle_type.dart';
import 'driver_in_app_checkout_page.dart';
import 'driver_paid_ticket_page.dart';
import 'driver_payment_page.dart'
    show DriverPaymentMethod, DriverPaymentMethodDetails;

/// A temporary QR: shown at the gate, paid on this phone only once staff
/// confirm there is space. Staff starting the payment opens the checkout
/// here automatically, and a confirmed payment turns it into the ticket.
class DriverParkingPassPage extends StatefulWidget {
  const DriverParkingPassPage({super.key, required this.checkoutId});

  final String checkoutId;

  @override
  State<DriverParkingPassPage> createState() => _DriverParkingPassPageState();
}

class _DriverParkingPassPageState extends State<DriverParkingPassPage> {
  final ParkingCheckoutService _checkoutService = ParkingCheckoutService();
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _sub;

  Map<String, dynamic>? _data;
  bool _loaded = false;
  bool _cancelling = false;
  bool _confirming = false;

  /// The checkout page on top of this one, so it can be closed if staff
  /// stop the payment.
  Route<dynamic>? _checkoutRoute;
  String? _openedSessionId;
  bool _showingTicket = false;

  @override
  void initState() {
    super.initState();
    _sub = FirebaseFirestore.instance
        .collection('parking_checkouts')
        .doc(widget.checkoutId)
        .snapshots()
        .listen(
          _onSnapshot,
          onError: (Object error, StackTrace stack) {
            reportError(error, stack, reason: 'Temporary QR stream');
            if (mounted) setState(() => _loaded = true);
          },
        );
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  void _onSnapshot(DocumentSnapshot<Map<String, dynamic>> snap) {
    if (!mounted) return;
    final Map<String, dynamic>? data = snap.data();
    setState(() {
      _data = data;
      _loaded = true;
    });
    final String status = (data?['status'] as String?) ?? '';
    final Object? paymongo = data?['paymongo'];
    // A checkout session, or the payment intent opened by Confirm.
    final String sessionId = paymongo is Map
        ? ((paymongo['sessionId'] as String?) ??
              (paymongo['intentId'] as String?) ??
              '')
        : '';
    final String url = paymongo is Map
        ? ((paymongo['checkoutUrl'] as String?) ?? '')
        : '';

    if (status == 'paid') {
      _closeCheckout();
      unawaited(_showTicket(data!));
    } else if (status == 'pending' && url.isNotEmpty) {
      if (sessionId != _openedSessionId) {
        _openedSessionId = sessionId;
        unawaited(_openCheckout(url));
      }
    } else {
      // Staff stopped the payment, or it timed out.
      _closeCheckout();
    }
  }

  void _closeCheckout() {
    final Route<dynamic>? route = _checkoutRoute;
    _checkoutRoute = null;
    if (route != null && route.isActive) {
      Navigator.of(context).removeRoute(route);
    }
  }

  Future<void> _openCheckout(String url) async {
    final Route<dynamic> route = MaterialPageRoute<dynamic>(
      builder: (_) => DriverInAppCheckoutPage(
        establishmentName: _text('establishmentName'),
        checkoutUrl: url,
        checkPaid: () async =>
            (await _checkoutService.confirmCheckout(widget.checkoutId)).isPaid,
      ),
    );
    _checkoutRoute = route;
    await Navigator.of(context).push<dynamic>(route);
    if (identical(_checkoutRoute, route)) _checkoutRoute = null;
    if (!mounted || _showingTicket) return;
    setState(() {}); // Shows "Open payment screen" again.
    // The stream usually reports paid first; this covers a slow one.
    try {
      final ParkingCheckoutStatus status = await _checkoutService.pollUntilPaid(
        widget.checkoutId,
        maxAttempts: 3,
      );
      if (status.isPaid && mounted && _data != null) {
        await _showTicket(<String, dynamic>{..._data!, 'status': 'paid'});
      }
    } catch (_) {
      // The stream will still catch the payment.
    }
  }

  Future<void> _showTicket(Map<String, dynamic> data) async {
    if (_showingTicket || !mounted) return;
    _showingTicket = true;
    final ParkingReceipt receipt = _receipt(data, paid: true);
    // Pushed, not a replacement: whoever opened this page is waiting on it.
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => DriverPaidTicketPage(
          establishmentName: receipt.facilityName,
          amount: receipt.amountCentavos / 100,
          qrData: (data['qrCode'] as String?) ?? '',
          vehicleType: receipt.vehicleType,
          receipt: receipt,
        ),
      ),
    );
    if (mounted) Navigator.of(context).pop();
  }

  /// The Confirm tap: pays with the details saved on the QR. The approval
  /// page opens from the stream as soon as the server records it.
  Future<void> _confirmPayment() async {
    if (_confirming) return;
    setState(() => _confirming = true);
    try {
      // The server saves the approval page on the QR, and the stream opens
      // it (once, keyed by the payment's id).
      await _checkoutService.confirmGatePayment(widget.checkoutId);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            friendlyError(
              error,
              fallback: 'Could not open the payment. Try again.',
            ),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _confirming = false);
    }
  }

  String _text(String key) => ((_data?[key] as String?) ?? '').trim();

  ParkingReceipt _receipt(Map<String, dynamic> data, {bool paid = false}) {
    String text(String key) => ((data[key] as String?) ?? '').trim();
    return ParkingReceipt(
      transactionId: (data['transactionId'] as String?) ?? widget.checkoutId,
      facilityName: text('establishmentName'),
      amountCentavos: (((data['amount'] as num?) ?? 0) * 100).round(),
      paidAt: paid ? DateTime.now() : null,
      paymentMethod: text('paymentMethod'),
      vehicleType: text('vehicleType'),
      plate: text('vehiclePlate'),
      plan: text('plan').toLowerCase(),
      duration: ((data['duration'] as num?) ?? 0).toInt(),
    );
  }

  DateTime? get _expiresAt {
    final Object? value = _data?['expiresAt'];
    return value is Timestamp ? value.toDate() : null;
  }

  Future<void> _cancel() async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('Cancel this temporary QR?'),
        content: const Text(
          'You have not been charged. You can make a new one any time.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: AppTheme.danger),
            child: const Text('Cancel QR'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _cancelling = true);
    try {
      await _checkoutService.cancelPass(widget.checkoutId);
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            friendlyError(error, fallback: 'Could not cancel. Try again.'),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _cancelling = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.surface,
        surfaceTintColor: AppTheme.surface,
        title: const Text('Temporary QR'),
      ),
      body: SafeArea(
        top: false,
        child: !_loaded
            ? const Center(child: CircularProgressIndicator())
            : Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 520),
                    child: _body(),
                  ),
                ),
              ),
      ),
    );
  }

  Widget _body() {
    final Map<String, dynamic>? data = _data;
    final String status = (data?['status'] as String?) ?? '';
    final DateTime? expiresAt = _expiresAt;
    final bool expired =
        status == 'expired' ||
        (status == 'awaiting_gate' &&
            expiresAt != null &&
            !DateTime.now().isBefore(expiresAt));
    if (data == null || expired || status == 'cancelled') {
      return _message(
        icon: Icons.timer_off_outlined,
        title: status == 'cancelled'
            ? 'Temporary QR cancelled'
            : 'Temporary QR expired',
        body:
            'You were not charged. Make a new one from the parking page '
            'when you are ready.',
      );
    }
    if (status == 'paid') {
      return _message(
        icon: Icons.check_circle_rounded,
        title: 'Paid',
        body: 'Opening your ticket...',
      );
    }

    final ParkingReceipt receipt = _receipt(data);
    final String qrData = (data['qrCode'] as String?) ?? '';
    final bool paying = status == 'pending';
    final String method = _methodLabel(receipt.paymentMethod);
    final String saved = savedPaymentLabel(method, data['payer']);
    // Staff confirmed space and the details are saved: one tap to pay.
    final bool awaitingConfirm =
        paying &&
        data['gatePaymentMode'] == 'direct' &&
        _checkoutUrl(data).isEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          receipt.facilityName,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: AppTheme.textDark,
            fontSize: 18,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
            border: Border.all(color: AppTheme.border),
          ),
          child: Column(
            children: <Widget>[
              SpMaxBrightness(
                child: QrImageView(
                  data: qrData,
                  size: 210,
                  backgroundColor: Colors.white,
                  eyeStyle: kTicketQrEyeStyle,
                  dataModuleStyle: kTicketQrModuleStyle,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                receipt.plate,
                style: TextStyle(
                  color: AppTheme.textDark,
                  fontSize: 20,
                  letterSpacing: 1.2,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              SpVehicleTypeBadge(vehicleType: receipt.vehicleType, large: true),
              const SizedBox(height: 14),
              SpTicketCost(
                ticket: receipt,
                amountLabel: 'DUE AT THE GATE',
                amountNote: saved.isNotEmpty
                    ? 'Pay with $saved'
                    : method.isEmpty
                    ? ''
                    : 'Pay with $method',
              ),
              if (expiresAt != null) ...<Widget>[
                const SizedBox(height: 10),
                Text(
                  'Valid until ${_dateTime(expiresAt)}',
                  style: TextStyle(color: AppTheme.textMuted, fontSize: 12),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 14),
        if (awaitingConfirm) ...<Widget>[
          _note(
            Icons.check_circle_outline_rounded,
            'Staff confirmed there is space. Tap Confirm to pay'
            '${saved.isEmpty ? '' : ' with $saved'}.',
          ),
          const SizedBox(height: 10),
          FilledButton.icon(
            onPressed: _confirming ? null : _confirmPayment,
            style: FilledButton.styleFrom(
              backgroundColor: AppTheme.accent,
              foregroundColor: AppTheme.onAccent,
              minimumSize: const Size.fromHeight(54),
            ),
            icon: _confirming
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.lock_outline_rounded),
            label: Text(
              _confirming
                  ? 'Opening payment...'
                  : 'Confirm ${spPeso(receipt.amountCentavos / 100)}',
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ] else if (paying) ...<Widget>[
          _note(
            Icons.payments_outlined,
            data['gatePaymentMode'] == 'direct'
                ? 'Approve the payment to enter. This closes by itself once '
                      'it is paid.'
                : 'Staff started your payment. The payment screen opens '
                      'here; finish it to enter.',
            busy: true,
          ),
          if (_checkoutUrl(data).isNotEmpty && _checkoutRoute == null)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: OutlinedButton.icon(
                onPressed: () => _openCheckout(_checkoutUrl(data)),
                icon: const Icon(Icons.open_in_new_rounded),
                label: const Text('Open payment screen'),
              ),
            ),
        ] else ...<Widget>[
          _note(
            Icons.info_outline_rounded,
            data['directPay'] == true
                ? 'You have not been charged. Show this QR at the gate. Once '
                      'staff confirm there is space, you just tap Confirm on '
                      'this phone.'
                : 'You have not been charged. Show this QR at the gate. Once '
                      'staff confirm there is space, you pay on this phone.',
          ),
          const SizedBox(height: 8),
          _note(
            Icons.signal_cellular_alt_rounded,
            'You need mobile data at the gate to pay. Without it, you can '
            'still park as a regular walk-in.',
          ),
        ],
        const SizedBox(height: 16),
        SpSaveQrButton(
          prominent: true,
          qrData: qrData,
          ticket: receipt,
          payAtGateUntil: expiresAt,
        ),
        if (!paying) ...<Widget>[
          const SizedBox(height: 8),
          TextButton(
            onPressed: _cancelling ? null : _cancel,
            style: TextButton.styleFrom(foregroundColor: AppTheme.danger),
            child: Text(_cancelling ? 'Cancelling...' : 'Cancel temporary QR'),
          ),
        ],
      ],
    );
  }

  Widget _note(IconData icon, String text, {bool busy = false}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        busy
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Icon(icon, size: 16, color: AppTheme.textSecondary),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 12.5,
              height: 1.35,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }

  Widget _message({
    required IconData icon,
    required String title,
    required String body,
  }) {
    return Column(
      children: <Widget>[
        const SizedBox(height: 40),
        Icon(icon, size: 44, color: AppTheme.textMuted),
        const SizedBox(height: 12),
        Text(
          title,
          style: TextStyle(
            color: AppTheme.textDark,
            fontSize: 18,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          body,
          textAlign: TextAlign.center,
          style: TextStyle(color: AppTheme.textMuted),
        ),
      ],
    );
  }
}

String _checkoutUrl(Map<String, dynamic> data) {
  final Object? paymongo = data['paymongo'];
  return paymongo is Map ? ((paymongo['checkoutUrl'] as String?) ?? '') : '';
}

/// "GCash 0917 ••• 4567" or "Card •••• 4242" from a pass's saved `payer`;
/// '' when nothing was saved.
String savedPaymentLabel(String methodLabel, Object? payer) {
  if (payer is! Map) return '';
  final String phone = (payer['phone'] as String?) ?? '';
  if (phone.length == 13 && phone.startsWith('+63')) {
    final String local = '0${phone.substring(3)}';
    return '$methodLabel ${local.substring(0, 4)} ••• ${local.substring(7)}';
  }
  final String last4 = (payer['cardLast4'] as String?) ?? '';
  if (last4.isNotEmpty) return 'Card •••• $last4';
  return '';
}

String _methodLabel(String apiType) {
  for (final DriverPaymentMethod m in DriverPaymentMethod.values) {
    if (m.apiType == apiType) return m.label;
  }
  return '';
}

String _dateTime(DateTime d) {
  const List<String> months = <String>[
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  final int h = d.hour % 12 == 0 ? 12 : d.hour % 12;
  final String m = d.minute.toString().padLeft(2, '0');
  return '${months[d.month - 1]} ${d.day}, $h:$m ${d.hour < 12 ? 'AM' : 'PM'}';
}
