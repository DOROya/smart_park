import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'driver_payment_page.dart';
import 'driver_vehicle_selection_page.dart';
import 'driver_in_app_checkout_page.dart';
import 'driver_paid_ticket_page.dart';
import '../services/paymongo_test_service.dart';
import '../theme/app_theme.dart';

class EstablishmentDetailPage extends StatefulWidget {
  const EstablishmentDetailPage({super.key, required this.establishmentId});

  final String establishmentId;

  @override
  State<EstablishmentDetailPage> createState() =>
      _EstablishmentDetailPageState();
}

class _EstablishmentDetailPageState extends State<EstablishmentDetailPage> {
  static const PayMongoTestService _payMongoService =
      PayMongoTestService.fromEnvironment();

  late final DocumentReference<Map<String, dynamic>> _establishmentRef;
  late final DocumentReference<Map<String, dynamic>> _establishmentDetailsRef;
  bool _generatingTicket = false;

  @override
  void initState() {
    super.initState();
    _establishmentRef = FirebaseFirestore.instance
        .collection('establishments')
        .doc(widget.establishmentId);
    _establishmentDetailsRef = FirebaseFirestore.instance
        .collection('establishment_details')
        .doc(widget.establishmentId);
  }

  Map<String, dynamic> _asStringMap(dynamic value) {
    if (value is Map) {
      return value.map<String, dynamic>(
        (dynamic key, dynamic item) =>
            MapEntry<String, dynamic>(key.toString(), item),
      );
    }
    return <String, dynamic>{};
  }

  String _readText(dynamic value, {String fallback = 'Not provided'}) {
    final String text = (value as String?)?.trim() ?? '';
    return text.isEmpty ? fallback : text;
  }

  List<String> _vehicleKeys(Map<String, dynamic> slotCounts) {
    return slotCounts.entries
        .where((MapEntry<String, dynamic> entry) => entry.value is num)
        .map((MapEntry<String, dynamic> entry) => entry.key)
        .toList();
  }

  List<String> _extractPhotoUrls(Map<String, dynamic> data) {
    final List<String> urls = <String>[];

    void addDynamic(dynamic val) {
      if (val == null) return;
      if (val is String && val.trim().isNotEmpty) {
        urls.add(val.trim());
      } else if (val is List) {
        for (final dynamic item in val) {
          if (item is String && item.trim().isNotEmpty) {
            urls.add(item.trim());
          }
        }
      }
    }

    addDynamic(data['photoUrls']);
    addDynamic(data['photoUrl']);
    addDynamic(data['photos']);
    addDynamic(data['images']);
    addDynamic(data['imageUrls']);
    addDynamic(data['imageUrl']);

    return urls.toSet().toList();
  }

  String _vehicleLabel(String key) {
    return switch (key) {
      'car' => 'Car / SUV',
      'motorcycle' => 'Motorcycle',
      _ => '${key[0].toUpperCase()}${key.substring(1)}',
    };
  }

  IconData _vehicleIcon(String key) {
    return switch (key) {
      'car' => Icons.directions_car_rounded,
      'motorcycle' => Icons.two_wheeler_rounded,
      _ => Icons.local_parking_rounded,
    };
  }

  int _vehicleCount(Map<String, dynamic> values, String key) {
    final num? direct = values[key] as num?;
    if (direct != null) {
      return direct.toInt();
    }
    return 0;
  }

  Future<Map<String, dynamic>> _loadDriverProfile(String driverId) async {
    final DocumentSnapshot<Map<String, dynamic>> snapshot =
        await FirebaseFirestore.instance
            .collection('users')
            .doc(driverId)
            .get();
    return snapshot.data() ?? <String, dynamic>{};
  }

  void _showSnackBar(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Widget _buildTopSummary(Map<String, dynamic> data) {
    final String name = _readText(
      data['name'],
      fallback: 'Parking Establishment',
    );
    final String address = _readText(data['address']);
    final double rating = ((data['rating'] as num?) ?? 0).toDouble();
    final List<String> photoUrls = _extractPhotoUrls(data);

    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: SizedBox(
        height: 208,
        width: double.infinity,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (photoUrls.isNotEmpty)
              Image.network(
                photoUrls.first,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => Container(
                  color: const Color(0xFFE9EDF3),
                  alignment: Alignment.center,
                  child: const Icon(
                    Icons.local_parking_rounded,
                    size: 54,
                    color: Color(0xFF737A88),
                  ),
                ),
              )
            else
              Container(
                color: const Color(0xFFE9EDF3),
                alignment: Alignment.center,
                child: const Icon(
                  Icons.local_parking_rounded,
                  size: 54,
                  color: Color(0xFF737A88),
                ),
              ),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: <Color>[Color(0x00000000), Color(0xD9000000)],
                ),
              ),
            ),
            Positioned(
              left: 16,
              right: 16,
              bottom: 15,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          address,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xFFE8EAF0),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xEFFFFFFF),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.star_rounded,
                          color: Color(0xFFF3AF00),
                          size: 17,
                        ),
                        const SizedBox(width: 3),
                        Text(
                          rating.toStringAsFixed(1),
                          style: const TextStyle(
                            color: AppTheme.textDark,
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHorizontalOverviewCards(Map<String, dynamic> data) {
    final Map<String, dynamic> slotCounts = _asStringMap(data['slotCounts']);
    final Map<String, dynamic> activeSlots = _asStringMap(data['slots']);
    final List<String> vehicleKeys = _vehicleKeys(slotCounts);

    final List<Widget> cardItems = <Widget>[];

    for (final String key in vehicleKeys) {
      cardItems.add(
        _OverviewStatusCard(
          icon: _vehicleIcon(key),
          label: _vehicleLabel(key),
          value:
              '${_vehicleCount(activeSlots, key)}/${_vehicleCount(slotCounts, key)}',
        ),
      );
    }

    cardItems.add(
      _OverviewStatusCard(
        icon: Icons.schedule_rounded,
        label: 'Hours',
        value: _readText(data['operatingHours'], fallback: '--'),
      ),
    );

    return Row(
      children: [
        for (int i = 0; i < cardItems.length; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          Expanded(child: cardItems[i]),
        ],
      ],
    );
  }

  Widget _buildQuickRatesSection(Map<String, dynamic> data) {
    final Map<String, dynamic> slotCounts = _asStringMap(data['slotCounts']);
    final Map<String, dynamic> ratesByType = _asStringMap(data['ratesByType']);
    final Map<String, dynamic> rates = _asStringMap(data['rates']);
    final List<String> vehicleKeys = _vehicleKeys(slotCounts).isNotEmpty
        ? _vehicleKeys(slotCounts)
        : (ratesByType.isNotEmpty
            ? ratesByType.keys.toList()
            : (rates.isNotEmpty ? rates.keys.toList() : <String>['car', 'motorcycle']));

    final List<Widget> rateCards = <Widget>[];

    for (final String key in vehicleKeys) {
      final _QuickRateData rateData = _getQuickRateData(data, key);

      rateCards.add(
        _QuickRateCard(
          icon: _vehicleIcon(key),
          label: _vehicleLabel(key),
          hourlyAmount: rateData.hourlyAmount,
          hourlyUnit: rateData.hourlyUnit,
          succeedingHourText: rateData.succeedingHourText,
          dailyText: rateData.dailyText,
        ),
      );
    }

    if (rateCards.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'QUICK RATES',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.8,
            color: AppTheme.textDark,
          ),
        ),
        const SizedBox(height: 10),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (int i = 0; i < rateCards.length; i++) ...[
              if (i > 0) const SizedBox(width: 10),
              Expanded(child: rateCards[i]),
            ],
          ],
        ),
      ],
    );
  }

  Widget _buildPhotoGallery(Map<String, dynamic> data) {
    final List<String> photoUrls = _extractPhotoUrls(data).skip(1).toList();

    if (photoUrls.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'More Facility Photos',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            color: AppTheme.textDark,
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 160,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: photoUrls.length,
            separatorBuilder: (BuildContext context, int index) =>
                const SizedBox(width: 10),
            itemBuilder: (BuildContext context, int index) {
              return ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Image.network(
                  photoUrls[index],
                  width: 220,
                  height: 160,
                  fit: BoxFit.cover,
                  loadingBuilder: (context, child, progress) {
                    if (progress == null) {
                      return child;
                    }
                    return Container(
                      width: 220,
                      height: 160,
                      color: const Color(0xFFF5F6F9),
                      child: const Center(
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    );
                  },
                  errorBuilder: (context, error, stackTrace) {
                    return Container(
                      width: 220,
                      height: 160,
                      color: const Color(0xFFF5F6F9),
                      alignment: Alignment.center,
                      child: const Icon(
                        Icons.broken_image_rounded,
                        color: AppTheme.textMuted,
                      ),
                    );
                  },
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildOverviewTab(Map<String, dynamic> data) {
    final List<String> photoUrls = _extractPhotoUrls(data).skip(1).toList();

    return ListView(
      padding: const EdgeInsets.only(top: 16, bottom: 24),
      children: [
        _buildHorizontalOverviewCards(data),
        const SizedBox(height: 16),
        _buildQuickRatesSection(data),
        if (photoUrls.isNotEmpty) ...[
          const SizedBox(height: 16),
          _buildPhotoGallery(data),
        ],
      ],
    );
  }

  Widget _buildRateCell(_RateDetailCell item) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            item.label.toUpperCase(),
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
              color: AppTheme.textMuted,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            item.amount,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w900,
              color: AppTheme.textDark,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            item.unit,
            style: const TextStyle(
              fontSize: 11,
              color: AppTheme.textMuted,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRateGrid(List<_RateDetailCell> cells) {
    if (cells.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Text(
          'No rate details configured.',
          style: TextStyle(color: AppTheme.textMuted),
        ),
      );
    }

    final List<Widget> rows = <Widget>[];

    for (int i = 0; i < cells.length; i += 2) {
      final _RateDetailCell cell1 = cells[i];
      final _RateDetailCell? cell2 =
          (i + 1 < cells.length) ? cells[i + 1] : null;

      if (i > 0) {
        rows.add(const Divider(height: 1, color: Color(0xFFE2E5EC)));
      }

      rows.add(
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: _buildRateCell(cell1)),
              const VerticalDivider(
                width: 1,
                thickness: 1,
                color: Color(0xFFE2E5EC),
              ),
              Expanded(
                child: cell2 != null
                    ? _buildRateCell(cell2)
                    : const SizedBox.shrink(),
              ),
            ],
          ),
        ),
      );
    }

    return Column(children: rows);
  }

  Widget _buildRatesTab(Map<String, dynamic> data) {
    final Map<String, dynamic> ratesByType = _asStringMap(data['ratesByType']);
    final Map<String, dynamic> slotCounts = _asStringMap(data['slotCounts']);
    final Map<String, dynamic> activeSlots = _asStringMap(data['slots']);

    final List<String> vehicleKeys = _vehicleKeys(slotCounts).isNotEmpty
        ? _vehicleKeys(slotCounts)
        : (ratesByType.isNotEmpty
            ? ratesByType.keys.toList()
            : <String>['motorcycle', 'car']);

    return ListView(
      padding: const EdgeInsets.only(top: 16, bottom: 24),
      children: [
        const Text(
          'Rates vary by vehicle type. Packages (Daily/Weekly/Monthly) are offered at a discounted rate and are subject to slot availability.',
          style: TextStyle(
            fontSize: 12,
            color: AppTheme.textMuted,
            height: 1.35,
          ),
        ),
        const SizedBox(height: 16),
        ...vehicleKeys.map((String key) {
          final List<_RateDetailCell> cells = _getRateGridCells(data, key);
          final int capacity = _vehicleCount(slotCounts, key);
          final int occupied = _vehicleCount(activeSlots, key);
          final int slotsLeft =
              (capacity - occupied).clamp(0, capacity > 0 ? capacity : 999);

          return Container(
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFE2E5EC)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                  child: Row(
                    children: [
                      Icon(_vehicleIcon(key), size: 20, color: AppTheme.textDark),
                      const SizedBox(width: 8),
                      Text(
                        _vehicleLabel(key),
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.textDark,
                        ),
                      ),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFF4CF),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          '$slotsLeft slots left',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF8C6200),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1, color: Color(0xFFE2E5EC)),
                _buildRateGrid(cells),
              ],
            ),
          );
        }),
      ],
    );
  }

  Widget _buildPolicyTab(Map<String, dynamic> data) {
    final String policyContent = _readText(
      data['policies'],
      fallback: 'No policy details available yet.',
    );

    return ListView(
      padding: const EdgeInsets.only(top: 16, bottom: 24),
      children: [
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFFE2E5EC)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF2F5FB),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.shield_outlined,
                      color: AppTheme.textDark,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      Text(
                        'Parking Policy',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.textDark,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Please read before parking',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppTheme.textMuted,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFF4F7FC),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Container(
                        width: 4,
                        decoration: BoxDecoration(
                          color: const Color(0xFF1E60D4),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Text(
                          policyContent,
                          style: const TextStyle(
                            fontSize: 13.5,
                            height: 1.5,
                            color: Color(0xFF2C313E),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _openVehicleSelection(Map<String, dynamic> establishment) async {
    final Map<String, dynamic> slotCounts = _asStringMap(
      establishment['slotCounts'],
    );
    final Map<String, dynamic> activeSlots = _asStringMap(
      establishment['slots'],
    );
    final Map<String, dynamic> ratesByType = _asStringMap(
      establishment['ratesByType'],
    );
    final Map<String, dynamic> packageRates = _asStringMap(
      establishment['packageRates'] ?? establishment['packages'],
    );
    final List<DriverVehicleOption> vehicleOptions = _vehicleKeys(slotCounts)
        .map((String key) {
          final _QuickRateData rateData = _getQuickRateData(establishment, key);
          return DriverVehicleOption(
            key: key,
            label: _vehicleLabel(key),
            icon: _vehicleIcon(key),
            activeCount: _vehicleCount(activeSlots, key),
            capacity: _vehicleCount(slotCounts, key),
            rate: '${rateData.hourlyAmount}${rateData.hourlyUnit}',
          );
        })
        .toList();

    if (vehicleOptions.isEmpty) {
      _showSnackBar('This establishment has no configured vehicle types.');
      return;
    }

    final dynamic selectionResult = await Navigator.of(context).push<dynamic>(
      MaterialPageRoute<dynamic>(
        builder: (_) => DriverVehicleSelectionPage(
          establishmentName: _readText(
            establishment['name'],
            fallback: 'Parking Establishment',
          ),
          vehicleOptions: vehicleOptions,
          ratesByType: ratesByType,
          packageRates: packageRates,
          isPayMongoConfigured: _payMongoService.isConfigured,
          onProcessPayment: ({
            required String vehicleType,
            required String plateNumber,
            required String plan,
            required int duration,
            required double amount,
            required DriverPaymentMethod paymentMethod,
          }) {
            return _processParkingPayment(
              establishment: establishment,
              vehicleType: vehicleType,
              plateNumber: plateNumber,
              plan: plan,
              duration: duration,
              amount: amount,
              paymentMethod: paymentMethod,
            );
          },
        ),
      ),
    );

    if (selectionResult is DriverVehicleSelection) {
      await _createParkingTransaction(establishment, selectionResult);
    }
  }

  Future<bool> _processParkingPayment({
    required Map<String, dynamic> establishment,
    required String vehicleType,
    required String plateNumber,
    required String plan,
    required int duration,
    required double amount,
    required DriverPaymentMethod paymentMethod,
  }) async {
    if (_generatingTicket) {
      return false;
    }

    final String? driverId = FirebaseAuth.instance.currentUser?.uid;
    if (driverId == null) {
      _showSnackBar('No logged-in driver found.');
      return false;
    }

    setState(() {
      _generatingTicket = true;
    });

    try {
      final Map<String, dynamic> driverProfile = await _loadDriverProfile(
        driverId,
      );
      final Map<String, dynamic> slotCounts = _asStringMap(
        establishment['slotCounts'],
      );

      if (amount <= 0) {
        _showSnackBar('Selected package has no valid amount configured.');
        return false;
      }

      final int amountInCentavos = (amount * 100).round();
      final String destinationAccountId =
          _readText(establishment['ownerId'], fallback: widget.establishmentId);
      final int platformFeeCentavos = (amountInCentavos * 0.05).round();
      final int estimatedProcessorFeeCentavos = estimateProcessorFeeCentavos(
        grossAmountCentavos: amountInCentavos,
        paymentMethodApiType: paymentMethod.apiType,
      );
      final SplitPaymentBreakdown splitBreakdown = SplitPaymentBreakdown(
        grossAmountCentavos: amountInCentavos,
        platformFeeCentavos: platformFeeCentavos,
        estimatedProcessorFeeCentavos: estimatedProcessorFeeCentavos,
        destinationAccountId: destinationAccountId,
      );

      final PayMongoCheckoutLink checkoutLink =
          await _payMongoService.createSplitCheckoutLink(
        amountInCentavos: amountInCentavos,
        description:
            'SmartPark ${_readText(establishment['name'], fallback: 'Parking')} - ${plan.toUpperCase()} ${vehicleType.toUpperCase()}',
        destinationAccountId: destinationAccountId,
        remarks: 'SmartPark test checkout',
        paymentMethodTypes: <String>[paymentMethod.apiType],
        metadata: <String, dynamic>{
          'driverId': driverId,
          'establishmentId': widget.establishmentId,
          'vehicleType': vehicleType,
          'plan': plan,
          'duration': duration,
          'amount': amount,
          'selectedPaymentMethod': paymentMethod.apiType,
        },
      );

      final DocumentReference<Map<String, dynamic>> transactionRef =
          FirebaseFirestore.instance.collection('transactions').doc();

      final String qrData = jsonEncode(<String, dynamic>{
        'transactionId': transactionRef.id,
        'driverId': driverId,
        'establishmentId': widget.establishmentId,
        'vehicleType': vehicleType,
        'plan': plan,
        'duration': duration,
        'vehiclePlate': plateNumber,
        'generatedAt': DateTime.now().toIso8601String(),
      });

      // Ticket-facing payload - deliberately excludes commission/fee
      // breakdown, which now lives only in the `payment_splits` collection.
      final Map<String, dynamic> payload = <String, dynamic>{
        'driverId': driverId,
        'driverName':
            '${(driverProfile['firstName'] as String?) ?? ''} ${(driverProfile['lastName'] as String?) ?? ''}'
                .trim(),
        'driverEmail': (driverProfile['email'] as String?) ?? '',
        'establishmentId': widget.establishmentId,
        'establishmentName': _readText(
          establishment['name'],
          fallback: 'Parking Establishment',
        ),
        'amount': amount,
        // Stored at the document root as well so gate staff can fall back to a
        // manual plate lookup when a QR code cannot be read by the camera.
        'vehiclePlate': plateNumber,
        'qrCode': qrData,
        'status': 'pending_payment',
        'entryStatus': 'not_checked_in',
        'paymentStatus': 'paymongo_link_created',
        'paymentMethod': paymentMethod.apiType,
        'paymongo': <String, dynamic>{
          'linkId': checkoutLink.id,
          'checkoutUrl': checkoutLink.checkoutUrl,
          'referenceNumber': checkoutLink.referenceNumber,
          'status': checkoutLink.status,
          'redirectUrl': checkoutLink.redirectUrl,
          'testUrl': checkoutLink.testUrl,
          'publicKeyUsed': _payMongoService.publicKey,
          'createdAtClient': DateTime.now().toIso8601String(),
        },
        'vehicleType': vehicleType,
        'plan': plan,
        'slotSnapshot': slotCounts,
        'createdAtClient': Timestamp.now(),
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      };

      final DocumentReference<Map<String, dynamic>> paymentRef =
          FirebaseFirestore.instance.collection('payments').doc();
      final DocumentReference<Map<String, dynamic>> paymentSplitRef =
          FirebaseFirestore.instance.collection('payment_splits').doc();

      if (!mounted) {
        return false;
      }

      final dynamic checkoutResult = await Navigator.of(context).push<dynamic>(
        MaterialPageRoute<dynamic>(
          builder: (_) => DriverInAppCheckoutPage(
            establishmentName: _readText(
              establishment['name'],
              fallback: 'Parking Establishment',
            ),
            checkoutUrl: checkoutLink.checkoutUrl,
            checkoutLinkId: checkoutLink.id,
            payMongoService: _payMongoService,
          ),
        ),
      );

      if (!mounted) {
        return false;
      }

      final PayMongoCheckoutLink refreshedLink =
          await _payMongoService.pollCheckoutLink(checkoutLink.id, maxAttempts: 6);
      final bool isPaid = checkoutResult == true || refreshedLink.isPaid;
      if (!isPaid) {
        _showSnackBar(
          'Payment was not confirmed. If you completed payment, check your active tickets or try again.',
        );
        return false;
      }

      final WriteBatch confirmationBatch = FirebaseFirestore.instance.batch();
      confirmationBatch.set(transactionRef, <String, dynamic>{
        ...payload,
        'status': 'paid',
        'paymentStatus': 'paid',
        'paymongo.status': refreshedLink.status,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      confirmationBatch.set(paymentRef, <String, dynamic>{
        'transactionId': transactionRef.id,
        'driverId': driverId,
        'establishmentId': widget.establishmentId,
        'amount': amount,
        'status': 'paid',
        'paymentProvider': 'paymongo_test',
        'paymongo': <String, dynamic>{
          'linkId': checkoutLink.id,
          'checkoutUrl': checkoutLink.checkoutUrl,
          'referenceNumber': checkoutLink.referenceNumber,
          'status': refreshedLink.status,
          'redirectUrl': checkoutLink.redirectUrl,
          'testUrl': checkoutLink.testUrl,
        },
        'createdAt': FieldValue.serverTimestamp(),
        'paymongo.status': refreshedLink.status,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      // Finance/commission ledger - only the parking owner's finance section
      // and admin reporting read from this collection, never ticket history.
      confirmationBatch.set(paymentSplitRef, <String, dynamic>{
        'transactionId': transactionRef.id,
        'paymentId': paymentRef.id,
        'establishmentId': widget.establishmentId,
        'driverId': driverId,
        ...splitBreakdown.toMap(),
        'paymentMethod': paymentMethod.apiType,
        'status': 'paid',
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      await confirmationBatch.commit();

      if (!mounted) {
        return true;
      }

      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => DriverPaidTicketPage(
            establishmentName: _readText(
              establishment['name'],
              fallback: 'Parking Establishment',
            ),
            amount: amount,
            qrData: qrData,
          ),
        ),
      );

      return true;
    } catch (error) {
      _showSnackBar('Failed to process payment: $error');
      return false;
    } finally {
      if (mounted) {
        setState(() {
          _generatingTicket = false;
        });
      }
    }
  }

  Future<void> _createParkingTransaction(
    Map<String, dynamic> establishment,
    DriverVehicleSelection selection,
  ) async {
    await _processParkingPayment(
      establishment: establishment,
      vehicleType: selection.vehicleType,
      plateNumber: selection.plateNumber,
      plan: selection.plan,
      duration: selection.duration,
      amount: selection.amount,
      paymentMethod: selection.paymentMethod,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        title: const Text('Establishment Details'),
      ),
      body: DefaultTabController(
        length: 3,
        child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: _establishmentRef.snapshots(),
          builder:
              (
                BuildContext context,
                AsyncSnapshot<DocumentSnapshot<Map<String, dynamic>>> snapshot,
              ) {
                return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                  stream: _establishmentDetailsRef.snapshots(),
                  builder:
                      (
                        BuildContext context,
                        AsyncSnapshot<DocumentSnapshot<Map<String, dynamic>>>
                        detailsSnapshot,
                      ) {
                        if (snapshot.connectionState ==
                                ConnectionState.waiting ||
                            detailsSnapshot.connectionState ==
                                ConnectionState.waiting) {
                          return const Center(
                            child: CircularProgressIndicator(),
                          );
                        }

                        if (snapshot.hasError || detailsSnapshot.hasError) {
                          return const Center(
                            child: Text(
                              'Unable to load establishment details.',
                              style: TextStyle(color: AppTheme.textMuted),
                            ),
                          );
                        }

                        final Map<String, dynamic> baseData =
                            snapshot.data?.data() ?? <String, dynamic>{};
                        final Map<String, dynamic> detailsData =
                            detailsSnapshot.data?.data() ?? <String, dynamic>{};

                        if (baseData.isEmpty && detailsData.isEmpty) {
                          return const Center(
                            child: Text(
                              'Establishment not found.',
                              style: TextStyle(color: AppTheme.textMuted),
                            ),
                          );
                        }

                        final Map<String, dynamic> data = <String, dynamic>{
                          ...baseData,
                          ...detailsData,
                          'establishmentID': widget.establishmentId,
                        };

                        return Padding(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                          child: Column(
                            children: [
                              _buildTopSummary(data),
                              const SizedBox(height: 14),
                              Container(
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: const Color(0xFFE2E5EC),
                                  ),
                                ),
                                child: const TabBar(
                                  labelColor: AppTheme.textDark,
                                  unselectedLabelColor: AppTheme.textMuted,
                                  indicatorColor: AppTheme.accent,
                                  indicatorWeight: 3,
                                  indicatorSize: TabBarIndicatorSize.tab,
                                  labelStyle: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w800,
                                  ),
                                  tabs: [
                                    Tab(text: 'Overview'),
                                    Tab(text: 'Rates'),
                                    Tab(text: 'Policy'),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 4),
                              Expanded(
                                child: TabBarView(
                                  children: [
                                    _buildOverviewTab(data),
                                    _buildRatesTab(data),
                                    _buildPolicyTab(data),
                                  ],
                                ),
                              ),
                              SafeArea(
                                top: false,
                                child: Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.fromLTRB(
                                    12,
                                    8,
                                    12,
                                    0,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(
                                      color: const Color(0xFFE2E5EC),
                                    ),
                                  ),
                                  child: ElevatedButton.icon(
                                    onPressed: _generatingTicket
                                        ? null
                                        : () => _openVehicleSelection(data),
                                    icon: _generatingTicket
                                        ? const SizedBox(
                                            width: 18,
                                            height: 18,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              color: Colors.white,
                                            ),
                                          )
                                        : const Icon(
                                            Icons.local_parking_rounded,
                                          ),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: AppTheme.accent,
                                      foregroundColor: const Color(0xFF22252C),
                                      elevation: 0,
                                      minimumSize: const Size.fromHeight(48),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                    ),
                                    label: Text(
                                      _generatingTicket
                                          ? 'Preparing checkout...'
                                          : 'Park Here',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                );
              },
        ),
      ),
    );
  }
}

class _OverviewStatusCard extends StatelessWidget {
  const _OverviewStatusCard({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E5EC)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: const Color(0xFF2D333F)),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  label.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textMuted,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: AppTheme.textDark,
            ),
          ),
        ],
      ),
    );
  }
}

String _formatGridAmount(dynamic val) {
  if (val == null) return '';
  String text = val.toString().trim();
  if (text.isEmpty || text.toLowerCase() == 'not provided') return '';

  final num? n = num.tryParse(text);
  if (n != null) {
    final String numStr =
        (n % 1 == 0) ? n.toInt().toString() : n.toStringAsFixed(0);
    return '₱$numStr';
  }

  text = text
      .replaceAll(
        RegExp(
          r'/hr|/hour|per hour|/day|per day|/week|per week|/month|per month',
          caseSensitive: false,
        ),
        '',
      )
      .trim();

  if (text.toUpperCase().startsWith('PHP')) {
    text = '₱${text.substring(3).trim()}';
  } else if (text.toUpperCase().startsWith('P')) {
    text = '₱${text.substring(1).trim()}';
  } else if (!text.startsWith('₱')) {
    text = '₱$text';
  }

  return text;
}

class _RateDetailCell {
  const _RateDetailCell({
    required this.label,
    required this.amount,
    required this.unit,
  });

  final String label;
  final String amount;
  final String unit;
}

dynamic _extractRateValue(
  Map<String, dynamic> data,
  Map<String, dynamic> vMap,
  String vehicleKey,
  List<String> fieldKeys,
) {
  for (final String k in fieldKeys) {
    if (vMap.containsKey(k) && vMap[k] != null) {
      final String val = vMap[k].toString().trim();
      if (val.isNotEmpty) return val;
    }
  }

  final Map<String, dynamic> packageRates = _asStringMap(
    data['packageRates'] ?? data['packages'] ?? data['packagePricing'],
  );

  for (final Map<String, dynamic> source in <Map<String, dynamic>>[data, packageRates]) {
    for (final String fieldKey in fieldKeys) {
      if (source.containsKey(fieldKey)) {
        final dynamic topVal = source[fieldKey];
        if (topVal is Map) {
          final Map<String, dynamic> topMap = _asStringMap(topVal);
          final dynamic vehicleVal = topMap[vehicleKey] ??
              (vehicleKey == 'motorcycle' ? topMap['motor'] : null);
          if (vehicleVal != null && vehicleVal.toString().trim().isNotEmpty) {
            return vehicleVal;
          }
        } else if (topVal != null && topVal.toString().trim().isNotEmpty) {
          return topVal;
        }
      }
    }
  }

  return null;
}

List<_RateDetailCell> _getRateGridCells(
  Map<String, dynamic> data,
  String vehicleKey,
) {
  final Map<String, dynamic> ratesByType = _asStringMap(data['ratesByType']);
  final Map<String, dynamic> rates = _asStringMap(data['rates']);

  dynamic rawVehicleValue = ratesByType[vehicleKey] ?? rates[vehicleKey];
  Map<String, dynamic> vMap =
      rawVehicleValue is Map
          ? _asStringMap(rawVehicleValue)
          : <String, dynamic>{};

  dynamic rawInitial =
      vMap['initial'] ??
      vMap['rates'] ??
      vMap['hourly'] ??
      vMap['firstHours'] ??
      rawVehicleValue;

  dynamic rawDaily = _extractRateValue(
    data,
    vMap,
    vehicleKey,
    <String>[
      'succeedingDaily',
      'SucceedingDaily',
      'succeeding_daily',
      'daily',
      'ratesByDaily',
    ],
  );

  dynamic rawWeekly = _extractRateValue(
    data,
    vMap,
    vehicleKey,
    <String>[
      'succeedingWeekly',
      'SucceedingWeekly',
      'succeeding_weekly',
      'weekly',
      'SucceedingWeeklyRates',
      'succeedingWeeklyRates',
    ],
  );

  dynamic rawMonthly = _extractRateValue(
    data,
    vMap,
    vehicleKey,
    <String>[
      'succeedingMonthly',
      'SucceedingMonthly',
      'succeeding_monthly',
      'monthly',
      'SucceedingMonthlyRates',
      'succeedingMonthlyRates',
    ],
  );

  final List<_RateDetailCell> cells = <_RateDetailCell>[];

  // 1. HOURLY
  final String hourlyAmt = _formatGridAmount(rawInitial);
  cells.add(
    _RateDetailCell(
      label: 'HOURLY',
      amount: hourlyAmt.isNotEmpty ? hourlyAmt : '₱0',
      unit: 'per hour',
    ),
  );

  // 2. DAILY
  final String dailyAmt = _formatGridAmount(rawDaily);
  cells.add(
    _RateDetailCell(
      label: 'DAILY',
      amount: dailyAmt.isNotEmpty ? dailyAmt : '₱0',
      unit: 'per day',
    ),
  );

  // 3. WEEKLY (Only displayed if explicitly provided by establishment)
  final String weeklyAmt = _formatGridAmount(rawWeekly);
  if (weeklyAmt.isNotEmpty && weeklyAmt != '₱0') {
    cells.add(
      _RateDetailCell(
        label: 'WEEKLY',
        amount: weeklyAmt,
        unit: 'per week',
      ),
    );
  }

  // 4. MONTHLY (Only displayed if explicitly provided by establishment)
  final String monthlyAmt = _formatGridAmount(rawMonthly);
  if (monthlyAmt.isNotEmpty && monthlyAmt != '₱0') {
    cells.add(
      _RateDetailCell(
        label: 'MONTHLY',
        amount: monthlyAmt,
        unit: 'per month',
      ),
    );
  }

  return cells;
}

class _QuickRateData {
  const _QuickRateData({
    required this.hourlyAmount,
    required this.hourlyUnit,
    this.succeedingHourText,
    this.dailyText,
  });

  final String hourlyAmount;
  final String hourlyUnit;
  final String? succeedingHourText;
  final String? dailyText;
}

_QuickRateData _getQuickRateData(Map<String, dynamic> data, String vehicleKey) {
  final Map<String, dynamic> ratesByType = _asStringMap(data['ratesByType']);
  final Map<String, dynamic> rates = _asStringMap(data['rates']);

  final Map<String, dynamic> initialRates = _asStringMap(
    data['initialRates'] ?? data['ratesByInitial'] ?? data['ratesByHour'],
  );
  final Map<String, dynamic> succeedingHourRates = _asStringMap(
    data['succeedingHour'] ??
        data['succeedingHourRates'] ??
        data['ratesBySucceedingHour'],
  );
  final Map<String, dynamic> succeedingDailyRates = _asStringMap(
    data['succeedingDaily'] ??
        data['succeedingDailyRates'] ??
        data['ratesBySucceedingDaily'] ??
        data['ratesByDaily'],
  );

  dynamic rawVehicleValue = ratesByType[vehicleKey] ?? rates[vehicleKey];

  dynamic rawInitial;
  dynamic rawSucceedingHour;
  dynamic rawSucceedingDaily;

  if (rawVehicleValue is Map) {
    final Map<String, dynamic> vMap = _asStringMap(rawVehicleValue);
    rawInitial = vMap['initial'] ?? vMap['rates'] ?? vMap['hourly'] ?? vMap['firstHours'];
    rawSucceedingHour =
        vMap['succeedingHour'] ?? vMap['succeeding_hour'] ?? vMap['succeeding'];
    rawSucceedingDaily =
        vMap['succeedingDaily'] ?? vMap['succeeding_daily'] ?? vMap['daily'];
  } else {
    rawInitial = rawVehicleValue;
  }

  rawInitial ??= initialRates[vehicleKey] ?? rates[vehicleKey];
  rawSucceedingHour ??= succeedingHourRates[vehicleKey];
  rawSucceedingDaily ??= succeedingDailyRates[vehicleKey];

  final String initialAmt = _formatQuickAmount(rawInitial);
  final String succHourAmt = _formatQuickAmount(rawSucceedingHour);
  final String succDailyAmt = _formatQuickAmount(rawSucceedingDaily);

  return _QuickRateData(
    hourlyAmount: initialAmt.isEmpty ? 'N/A' : initialAmt,
    hourlyUnit: initialAmt.isEmpty ? '' : '/hr',
    succeedingHourText: succHourAmt.isNotEmpty ? '+$succHourAmt/hr succeeding' : null,
    dailyText: succDailyAmt.isNotEmpty ? '$succDailyAmt/day' : null,
  );
}

Map<String, dynamic> _asStringMap(dynamic value) {
  if (value is Map) {
    return value.map<String, dynamic>(
      (dynamic key, dynamic item) =>
          MapEntry<String, dynamic>(key.toString(), item),
    );
  }
  return <String, dynamic>{};
}

String _formatQuickAmount(dynamic val) {
  if (val == null) return '';
  String text = val.toString().trim();
  if (text.isEmpty || text.toLowerCase() == 'not provided') return '';

  final num? n = num.tryParse(text);
  if (n != null) {
    final String numStr =
        (n % 1 == 0) ? n.toInt().toString() : n.toStringAsFixed(2);
    return 'P$numStr';
  }

  text = text
      .replaceAll(RegExp(r'/hr|/hour|per hour', caseSensitive: false), '')
      .trim();

  if (text.toUpperCase().startsWith('PHP')) {
    text = 'P${text.substring(3).trim()}';
  } else if (text.startsWith('₱')) {
    text = 'P${text.substring(1).trim()}';
  } else if (!text.toUpperCase().startsWith('P') &&
      RegExp(r'^\d').hasMatch(text)) {
    text = 'P$text';
  }

  return text;
}

class _QuickRateCard extends StatelessWidget {
  const _QuickRateCard({
    required this.icon,
    required this.label,
    required this.hourlyAmount,
    required this.hourlyUnit,
    this.succeedingHourText,
    this.dailyText,
  });

  final IconData icon;
  final String label;
  final String hourlyAmount;
  final String hourlyUnit;
  final String? succeedingHourText;
  final String? dailyText;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E5EC)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: const Color(0xFF2D333F)),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  label.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.5,
                    color: AppTheme.textDark,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                hourlyAmount,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.textDark,
                ),
              ),
              if (hourlyUnit.isNotEmpty) ...[
                Text(
                  hourlyUnit,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppTheme.textMuted,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ],
          ),
          if (succeedingHourText != null && succeedingHourText!.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              succeedingHourText!,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: AppTheme.textMuted,
              ),
            ),
          ],
          if (dailyText != null && dailyText!.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              dailyText!,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppTheme.textDark,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
