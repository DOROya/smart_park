import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';

import '../../../services/error_reporter.dart';
import '../../../services/parking_checkout_service.dart';
import '../../../services/parking_pricing.dart';
import '../../../theme/app_theme.dart';
import '../../../utils/friendly_error.dart';
import '../../../utils/sp_haptics.dart';
import '../../../widgets/smartpark_ui.dart';
import '../driver_in_app_checkout_page.dart';

/// Most hours bought at once (the server allows the same).
const int kMaxExtraHours = 12;

/// Smallest online payment, in pesos (PayMongo's minimum).
const double kMinExtraHoursPayment = 20;

/// Fewest hours that reach the PHP 20 online minimum at [rate].
int minExtraHours(double rate) => rate <= 0
    ? 1
    : (kMinExtraHoursPayment / rate).ceil().clamp(1, kMaxExtraHours);

/// Whether a ticket can get extra hours: the driver's paid SmartPark
/// ticket (not a walk-in).
bool canAddTicketHours(Map<String, dynamic> ticket) =>
    ticket['status'] == 'paid' && ticket['source'] != 'walk_in';

/// How extra hours are paid: straight to the wallet when the ticket's
/// temporary QR saved a number ([savedNumber]), else PayMongo's page.
String extraHoursPaymentNote(String paymentMethod, {bool savedNumber = true}) =>
    switch (paymentMethod) {
      'gcash' when savedNumber =>
        'Pays with your saved GCash number. You approve it in GCash.',
      'paymaya' when savedNumber =>
        'Pays with your saved Maya number. You approve it in Maya.',
      'card' => "Pays by card on PayMongo's secure page.",
      _ => "Pays on PayMongo's secure page.",
    };

/// Buys more hours on [ticketId], so the driver's paid time doesn't run out
/// (or overtime stops). Nothing is charged until they tap Confirm.
Future<void> showAddHoursSheet(
  BuildContext context, {
  required String ticketId,
  required Map<String, dynamic> ticket,
}) async {
  final String facilityId = ((ticket['establishmentId'] as String?) ?? '')
      .trim();
  Map<String, dynamic>? rates;
  bool savedNumber = false;
  try {
    // Tickets from before saved details pay on PayMongo's page instead.
    final String passId = ((ticket['checkoutId'] as String?) ?? '').trim();
    if (passId.isNotEmpty) {
      final Object? payer =
          (await FirebaseFirestore.instance
                  .collection('parking_checkouts')
                  .doc(passId)
                  .get())
              .data()?['payer'];
      savedNumber = payer is Map && ((payer['phone'] as String?) ?? '') != '';
    }
  } catch (error, stack) {
    reportError(error, stack, reason: 'Extra hours saved details');
  }
  try {
    final DocumentSnapshot<Map<String, dynamic>> details =
        await FirebaseFirestore.instance
            .collection('establishment_details')
            .doc(facilityId.isEmpty ? '-' : facilityId)
            .get();
    final Object? r = details.data()?['ratesByType'];
    if (r is Map) rates = Map<String, dynamic>.from(r);
  } catch (error, stack) {
    reportError(error, stack, reason: 'Extra hours rate');
  }
  final double? rate = ticketOvertimeRate(
    ticket,
    rates,
    ((ticket['vehicleType'] as String?) ?? 'car').trim(),
  );
  if (!context.mounted) return;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _AddHoursSheet(
      ticketId: ticketId,
      ticket: ticket,
      rate: rate,
      savedNumber: savedNumber,
    ),
  );
}

class _AddHoursSheet extends StatefulWidget {
  const _AddHoursSheet({
    required this.ticketId,
    required this.ticket,
    required this.rate,
    this.savedNumber = false,
  });

  final String ticketId;
  final Map<String, dynamic> ticket;
  final double? rate;

  /// The ticket's QR saved a wallet number, so the wallet opens directly.
  final bool savedNumber;

  @override
  State<_AddHoursSheet> createState() => _AddHoursSheetState();
}

class _AddHoursSheetState extends State<_AddHoursSheet> {
  final ParkingCheckoutService _service = ParkingCheckoutService();
  late int _hours = widget.rate == null ? 1 : minExtraHours(widget.rate!);
  bool _busy = false;

  double get _price => (widget.rate ?? 0) * _hours;

  Future<void> _confirm() async {
    setState(() => _busy = true);
    final NavigatorState navigator = Navigator.of(context);
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    final int hours = _hours;
    try {
      final ({String checkoutId, String status, String redirectUrl}) opened =
          await _service.addHours(ticketId: widget.ticketId, hours: hours);
      bool paid = opened.status == 'paid';
      bool approved = false;
      if (!paid && opened.redirectUrl.isNotEmpty && mounted) {
        final Object? result = await navigator.push<Object?>(
          MaterialPageRoute<Object?>(
            builder: (_) => DriverInAppCheckoutPage(
              establishmentName:
                  (widget.ticket['establishmentName'] as String?) ?? '',
              checkoutUrl: opened.redirectUrl,
              checkPaid: () async =>
                  (await _service.confirmCheckout(opened.checkoutId)).isPaid,
            ),
          ),
        );
        approved = result == true;
      }
      if (!paid) {
        // The hours are added only when the server confirms the payment
        // with PayMongo. PayMongo's success page can close the payment
        // screen first, so always ask; otherwise the hours wait for the
        // 15-minute background check.
        try {
          paid = (await _service.pollUntilPaid(
            opened.checkoutId,
            maxAttempts: approved ? 8 : 3,
          )).isPaid;
        } catch (error, stack) {
          // Paid or not, the background check still adds the hours.
          reportError(error, stack, reason: 'Confirm extra hours');
        }
      }
      if (paid) spHapticSuccess();
      if (mounted) navigator.pop();
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            paid
                ? '${formatParkingHours(hours)} added to your ticket.'
                : 'Not paid yet. If you approved it, the hours appear on '
                      'your ticket in a moment.',
          ),
        ),
      );
    } on FirebaseFunctionsException catch (error) {
      if (mounted) setState(() => _busy = false);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            friendlyError(error, fallback: 'Could not add hours. Try again.'),
          ),
        ),
      );
    } catch (error, stack) {
      reportError(error, stack, reason: 'Add ticket hours');
      if (mounted) setState(() => _busy = false);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            friendlyError(error, fallback: 'Could not add hours. Try again.'),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final double? rate = widget.rate;
    final String facility =
        ((widget.ticket['establishmentName'] as String?) ?? '').trim();
    final int least = rate == null ? 1 : minExtraHours(rate);
    final int left = ticketHoursLeft(widget.ticket);
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          0,
          20,
          20 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              'Add hours',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: AppTheme.textDark,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${facility.isEmpty ? 'This ticket' : facility} · '
              '${formatParkingHours(left)} left now',
              style: TextStyle(color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 16),
            if (rate == null)
              Text(
                'This facility doesn\'t sell extra hours in the app. Any '
                'overtime is paid at the exit.',
                style: TextStyle(color: AppTheme.textSecondary, height: 1.35),
              )
            else ...<Widget>[
              Row(
                children: <Widget>[
                  IconButton.filledTonal(
                    tooltip: 'Fewer hours',
                    onPressed: _busy || _hours <= least
                        ? null
                        : () => setState(() => _hours--),
                    icon: const Icon(Icons.remove_rounded),
                  ),
                  Expanded(
                    child: Column(
                      children: <Widget>[
                        Text(
                          formatParkingHours(_hours),
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            color: AppTheme.textDark,
                          ),
                        ),
                        Text(
                          '${spPeso(rate)} per hour',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppTheme.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton.filledTonal(
                    tooltip: 'More hours',
                    onPressed: _busy || _hours >= kMaxExtraHours
                        ? null
                        : () => setState(() => _hours++),
                    icon: const Icon(Icons.add_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                extraHoursPaymentNote(
                  (widget.ticket['paymentMethod'] as String?) ?? '',
                  savedNumber: widget.savedNumber,
                ),
                style: TextStyle(
                  fontSize: 12,
                  color: AppTheme.textSecondary,
                  height: 1.35,
                ),
              ),
              if (least > 1)
                Text(
                  'Online payments start at ${spPeso(kMinExtraHoursPayment)}.',
                  style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
                ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _busy ? null : _confirm,
                style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.accent,
                  foregroundColor: AppTheme.onAccent,
                  minimumSize: const Size.fromHeight(52),
                ),
                icon: _busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.lock_outline_rounded),
                label: Text(
                  _busy ? 'Opening payment...' : 'Confirm ${spPeso(_price)}',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
