import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../services/last_ticket_store.dart';
import '../../services/parking_pricing.dart' show formatParkingHours;
import '../../theme/app_theme.dart';
import '../../widgets/smartpark_ui.dart';
import '../../widgets/sp_max_brightness.dart'
    show SpMaxBrightness, kTicketQrEyeStyle, kTicketQrModuleStyle;
import '../../widgets/sp_vehicle_type.dart';

/// One ticket's QR, full screen at full brightness, from "Show my ticket".
/// Works with no signal from the copy saved on this phone ([offline]): the
/// QR is drawn here from the ticket id, and staff check it at the gate.
class SavedTicketPage extends StatelessWidget {
  const SavedTicketPage({
    super.key,
    required this.ticket,
    this.offline = false,
  });

  final SavedTicket ticket;
  final bool offline;

  @override
  Widget build(BuildContext context) {
    final TextStyle muted = TextStyle(fontSize: 13, color: AppTheme.textMuted);
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.surface,
        title: Text(ticket.isPass ? 'Temporary QR' : 'My ticket'),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                children: <Widget>[
                  if (offline)
                    Container(
                      width: double.infinity,
                      margin: const EdgeInsets.only(bottom: 16),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppTheme.surfaceAlt,
                        borderRadius: BorderRadius.circular(AppTheme.radius),
                        border: Border.all(color: spCardBorder),
                      ),
                      child: Row(
                        children: <Widget>[
                          Icon(Icons.cloud_off_rounded, color: spInsideColor),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Offline: showing your saved ticket.'
                              '${ticket.isPass ? ' Paying it still needs mobile data.' : ''}',
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                color: AppTheme.textDark,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  Text(
                    ticket.facilityName.isEmpty
                        ? 'Parking ticket'
                        : ticket.facilityName,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.textDark,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    ticket.isPass
                        ? 'Show at the gate, then pay on your phone'
                        : ticket.parked
                        ? 'Show this QR at the exit'
                        : 'Show this QR at the entrance',
                    style: muted,
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    // Always white: scanners need a light border.
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
                      border: Border.all(color: spCardBorder),
                    ),
                    child: SpMaxBrightness(
                      child: QrImageView(
                        data: ticket.qr,
                        size: 240,
                        backgroundColor: Colors.white,
                        eyeStyle: kTicketQrEyeStyle,
                        dataModuleStyle: kTicketQrModuleStyle,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  SpPlateBadge(plate: ticket.plate),
                  const SizedBox(height: 8),
                  SpVehicleTypeBadge(vehicleType: ticket.vehicleType),
                  if (!ticket.isPass) ...<Widget>[
                    const SizedBox(height: 12),
                    Text(
                      '${formatParkingHours(ticket.hoursLeft)} left'
                      '${offline ? ' as of ${spFormatClockTime(ticket.savedAt)}${spSameDate(ticket.savedAt, DateTime.now()) ? '' : ', ${spFormatDate(ticket.savedAt)}'}' : ''}',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textDark,
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  Text('Ticket #${ticket.id}', style: muted),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
