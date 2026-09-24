import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' show LatLng;
import 'package:url_launcher/url_launcher.dart';

import 'driver_payment_page.dart';
import 'driver_vehicle_selection_page.dart';
import 'driver_in_app_checkout_page.dart';
import 'driver_paid_ticket_page.dart';
import '../services/parking_checkout_service.dart';
import '../theme/app_theme.dart';
import '../widgets/smartpark_ui.dart';
import 'driver/services/driver_establishment_service.dart';
import '../services/operating_hours.dart';

part 'establishment_detail/rate_display.dart';

class EstablishmentDetailPage extends StatefulWidget {
  const EstablishmentDetailPage({super.key, required this.establishmentId});

  final String establishmentId;

  @override
  State<EstablishmentDetailPage> createState() =>
      _EstablishmentDetailPageState();
}

class _EstablishmentDetailPageState extends State<EstablishmentDetailPage>
    with SpStreamCache<EstablishmentDetailPage> {
  final ParkingCheckoutService _checkoutService = ParkingCheckoutService();

  late final DocumentReference<Map<String, dynamic>> _establishmentRef;
  late final DocumentReference<Map<String, dynamic>> _establishmentDetailsRef;
  bool _generatingTicket = false;
  int _photoIndex = 0;

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

  void _showSnackBar(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _openInMaps(Map<String, dynamic> data) async {
    final LatLng? point = DriverEstablishmentService.extractLatLng(data);
    final String query = point == null
        ? Uri.encodeComponent(_readText(data['address'], fallback: ''))
        : '${point.latitude},${point.longitude}';
    if (query.isEmpty) {
      _showSnackBar('No location available for this establishment.');
      return;
    }
    final Uri uri = Uri.parse(
      'https://www.google.com/maps/search/?api=1&query=$query',
    );
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      _showSnackBar('Unable to open maps.');
    }
  }

  /// Lowest base rate across vehicle types, e.g. "P50", or null.
  String? _lowestBaseRate(Map<String, dynamic> data, List<String> keys) {
    double? lowest;
    String? label;
    for (final String key in keys) {
      final String amount = _getQuickRateData(data, key).hourlyAmount;
      final double? value = double.tryParse(
        amount.replaceAll(RegExp(r'[^0-9.]'), ''),
      );
      if (value != null && value > 0 && (lowest == null || value < lowest)) {
        lowest = value;
        label = amount;
      }
    }
    return label;
  }

  List<String> _rateVehicleKeys(Map<String, dynamic> data) {
    final Map<String, dynamic> slotCounts = _asStringMap(data['slotCounts']);
    final Map<String, dynamic> ratesByType = _asStringMap(data['ratesByType']);
    final Map<String, dynamic> rates = _asStringMap(data['rates']);
    if (_vehicleKeys(slotCounts).isNotEmpty) return _vehicleKeys(slotCounts);
    if (ratesByType.isNotEmpty) return ratesByType.keys.toList();
    if (rates.isNotEmpty) return rates.keys.toList();
    return <String>['car', 'motorcycle'];
  }

  Widget _photoPlaceholder(IconData icon) => Container(
    color: const Color(0xFFE9EDF3),
    alignment: Alignment.center,
    child: Icon(icon, size: 54, color: const Color(0xFF737A88)),
  );

  /// Rounded photo header (swipeable when there are several photos) with
  /// the name, address, open status and rating overlaid.
  Widget _buildTopSummary(Map<String, dynamic> data) {
    final String name = _readText(
      data['name'],
      fallback: 'Parking Establishment',
    );
    final String address = _readText(data['address']);
    final double rating = ((data['rating'] as num?) ?? 0).toDouble();
    final bool openNow = DriverEstablishmentService.isOpenNow(data);
    final List<String> photoUrls = _extractPhotoUrls(data);

    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: SizedBox(
        height: 200,
        width: double.infinity,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (photoUrls.isEmpty)
              _photoPlaceholder(Icons.local_parking_rounded)
            else if (photoUrls.length == 1)
              Image.network(
                photoUrls.first,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) =>
                    _photoPlaceholder(Icons.local_parking_rounded),
              )
            else
              PageView.builder(
                itemCount: photoUrls.length,
                onPageChanged: (int index) =>
                    setState(() => _photoIndex = index),
                itemBuilder: (BuildContext context, int index) => Image.network(
                  photoUrls[index],
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) =>
                      _photoPlaceholder(Icons.broken_image_rounded),
                ),
              ),
            const IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: <Color>[Color(0x00000000), Color(0xD9000000)],
                    stops: <double>[0.35, 1],
                  ),
                ),
              ),
            ),
            Positioned(
              top: 12,
              left: 12,
              child: IgnorePointer(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.circle,
                        size: 9,
                        color: openNow ? spEntryColor : spDeniedColor,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        openNow ? 'Open now' : 'Closed',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: openNow ? spEntryColor : spDeniedColor,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              left: 16,
              right: 16,
              bottom: 14,
              child: IgnorePointer(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
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
                        if (rating > 0) ...[
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
                      ],
                    ),
                    if (photoUrls.length > 1) ...[
                      const SizedBox(height: 10),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          for (int i = 0; i < photoUrls.length; i++)
                            AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              margin: const EdgeInsets.symmetric(horizontal: 3),
                              width: i == _photoIndex ? 18 : 7,
                              height: 7,
                              decoration: BoxDecoration(
                                color: i == _photoIndex
                                    ? Colors.white
                                    : const Color(0x99FFFFFF),
                                borderRadius: BorderRadius.circular(999),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHoursRow(Map<String, dynamic> data) {
    final OperatingHours hours = OperatingHours.parse(data);
    final bool open = hours.isOpenAt(DateTime.now());
    final String detail = !hours.isSet || hours.allDay
        ? ''
        : open
        ? 'Closes at ${OperatingHours.format12h(hours.closeMinutes!)}'
        : 'Opens at ${OperatingHours.format12h(hours.openMinutes!)}';
    return Row(
      children: [
        const Icon(Icons.schedule_rounded, size: 18, color: AppTheme.textMuted),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                hours.isSet ? hours.label : _readText(data['operatingHours']),
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textDark,
                ),
              ),
              if (detail.isNotEmpty)
                Text(
                  detail,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppTheme.textMuted,
                  ),
                ),
            ],
          ),
        ),
        if (hours.isSet)
          SpChip(
            label: open ? 'Open now' : 'Closed',
            color: open ? spEntryColor : spDeniedColor,
          ),
      ],
    );
  }

  Widget _buildInfoCard(Map<String, dynamic> data) {
    return SpSectionCard(
      icon: Icons.info_outline_rounded,
      title: 'Location & Hours',
      child: Column(
        children: [
          _buildHoursRow(data),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 10),
            child: Divider(height: 1, color: Color(0xFFEDEFF3)),
          ),
          Row(
            children: [
              const Icon(
                Icons.location_on_outlined,
                size: 18,
                color: AppTheme.textMuted,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _readText(data['address']),
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppTheme.textDark,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: () => _openInMaps(data),
                icon: const Icon(Icons.directions_rounded, size: 18),
                label: const Text('Directions'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: spExitColor,
                  side: const BorderSide(color: spCardBorder),
                  visualDensity: VisualDensity.compact,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCapacityTiles(Map<String, dynamic> data) {
    final Map<String, dynamic> slotCounts = _asStringMap(data['slotCounts']);
    final List<String> keys = _vehicleKeys(slotCounts);
    if (keys.isEmpty) {
      return const SizedBox.shrink();
    }
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: SpOccupancy.watch(widget.establishmentId),
      builder:
          (
            BuildContext context,
            AsyncSnapshot<DocumentSnapshot<Map<String, dynamic>>> snapshot,
          ) {
            final SpOccupancy? live = SpOccupancy.fromDoc(snapshot.data);
            final List<Widget> tiles = <Widget>[
              for (final String key in keys)
                () {
                  final int capacity = _vehicleCount(slotCounts, key);
                  final int free = live == null
                      ? capacity
                      : (capacity - live.of(key)).clamp(0, capacity);
                  return SpStatTile(
                    icon: _vehicleIcon(key),
                    color: key == 'motorcycle' ? spEntryColor : spExitColor,
                    label: '${_vehicleLabel(key)} slots',
                    caption: live == null
                        ? 'Total capacity'
                        : 'Available of $capacity',
                    value: '$free',
                  );
                }(),
            ];
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (int i = 0; i < tiles.length; i++) ...[
                  if (i > 0) const SizedBox(width: 10),
                  Expanded(child: tiles[i]),
                ],
              ],
            );
          },
    );
  }

  Widget _rateRow(String label, String value, {bool strong = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(fontSize: 13, color: AppTheme.textMuted),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: strong ? 18 : 14,
              fontWeight: FontWeight.w800,
              color: AppTheme.textDark,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRatesCard(Map<String, dynamic> data, String key) {
    final _QuickRateData quick = _getQuickRateData(data, key);
    final Map<String, _RateDetailCell> grid = <String, _RateDetailCell>{
      for (final _RateDetailCell cell in _getRateGridCells(data, key))
        cell.label: cell,
    };
    final String succeedingHour = (quick.succeedingHourText ?? '')
        .replaceAll(' succeeding', '')
        .replaceFirst('+', '');
    String gridValue(String label) {
      final String amount = grid[label]?.amount ?? '';
      return amount.isEmpty || amount == '₱0' ? '' : amount;
    }

    final List<Widget> rows = <Widget>[
      _rateRow(
        'Base rate · first $spBaseStayLabel',
        quick.hourlyAmount == 'N/A'
            ? 'Not set'
            : quick.hourlyAmount.replaceFirst('P', '₱'),
        strong: true,
      ),
      if (succeedingHour.isNotEmpty)
        _rateRow('Each succeeding hour', succeedingHour.replaceFirst('P', '₱')),
      if (gridValue('DAILY').isNotEmpty) _rateRow('Daily', gridValue('DAILY')),
      if (gridValue('WEEKLY').isNotEmpty)
        _rateRow('Weekly', gridValue('WEEKLY')),
      if (gridValue('MONTHLY').isNotEmpty)
        _rateRow('Monthly', gridValue('MONTHLY')),
    ];

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: SpSectionCard(
        icon: _vehicleIcon(key),
        title: _vehicleLabel(key),
        child: Column(
          children: [
            for (int i = 0; i < rows.length; i++) ...[
              if (i > 0) const Divider(height: 1, color: Color(0xFFEDEFF3)),
              rows[i],
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildMorePhotos(Map<String, dynamic> data) {
    final List<String> photoUrls = _extractPhotoUrls(data);
    if (photoUrls.length < 2) {
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SpSectionLabel('Photos'),
        const SizedBox(height: 10),
        SizedBox(
          height: 110,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: photoUrls.length,
            separatorBuilder: (_, _) => const SizedBox(width: 10),
            itemBuilder: (BuildContext context, int index) {
              return GestureDetector(
                onTap: () => _showPhoto(photoUrls[index]),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: Image.network(
                    photoUrls[index],
                    width: 150,
                    height: 110,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => Container(
                      width: 150,
                      height: 110,
                      color: const Color(0xFFF1F3F7),
                      child: const Icon(
                        Icons.broken_image_rounded,
                        color: AppTheme.textMuted,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  void _showPhoto(String url) {
    showDialog<void>(
      context: context,
      builder: (BuildContext viewerContext) {
        return Dialog(
          backgroundColor: Colors.black,
          insetPadding: const EdgeInsets.all(12),
          child: Stack(
            children: [
              InteractiveViewer(
                maxScale: 5,
                child: Center(child: Image.network(url, fit: BoxFit.contain)),
              ),
              Positioned(
                top: 4,
                right: 4,
                child: IconButton(
                  onPressed: () => Navigator.of(viewerContext).pop(),
                  icon: const Icon(Icons.close_rounded, color: Colors.white),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildOverviewTab(Map<String, dynamic> data) {
    return ListView(
      padding: const EdgeInsets.only(top: 12, bottom: 16),
      children: [
        _buildCapacityTiles(data),
        const SizedBox(height: 12),
        _buildInfoCard(data),
        const SizedBox(height: 16),
        _buildMorePhotos(data),
      ],
    );
  }

  Widget _buildRatesTab(Map<String, dynamic> data) {
    return ListView(
      padding: const EdgeInsets.only(top: 12, bottom: 16),
      children: [
        for (final String key in _rateVehicleKeys(data))
          _buildRatesCard(data, key),
      ],
    );
  }

  Widget _buildPolicyTab(Map<String, dynamic> data) {
    final String policies = _readText(data['policies'], fallback: '');
    return ListView(
      padding: const EdgeInsets.only(top: 12, bottom: 16),
      children: [
        SpSectionCard(
          icon: Icons.shield_outlined,
          title: 'Parking Policy',
          subtitle: 'Please read before parking.',
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFF6F7FA),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              policies.isEmpty ? 'No policy details available yet.' : policies,
              style: const TextStyle(
                fontSize: 13.5,
                height: 1.5,
                color: AppTheme.textDark,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBody(Map<String, dynamic> data) {
    return DefaultTabController(
      length: 3,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        child: Column(
          children: [
            _buildTopSummary(data),
            const SizedBox(height: 12),
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: spCardBorder),
              ),
              child: const TabBar(
                labelColor: AppTheme.textDark,
                unselectedLabelColor: AppTheme.textMuted,
                indicatorColor: AppTheme.accent,
                indicatorWeight: 3,
                indicatorSize: TabBarIndicatorSize.tab,
                dividerColor: Colors.transparent,
                labelStyle: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                ),
                tabs: [
                  Tab(text: 'Overview'),
                  Tab(text: 'Rates'),
                  Tab(text: 'Policy'),
                ],
              ),
            ),
            Expanded(
              child: TabBarView(
                children: [
                  _buildOverviewTab(data),
                  _buildRatesTab(data),
                  _buildPolicyTab(data),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomBar(Map<String, dynamic> data) {
    final String? fromRate = _lowestBaseRate(data, _rateVehicleKeys(data));
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: spCardBorder)),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            if (fromRate != null) ...[
              Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'From · first $spBaseStayLabel',
                    style: TextStyle(fontSize: 11, color: AppTheme.textMuted),
                  ),
                  Text(
                    fromRate.replaceFirst('P', '₱'),
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.textDark,
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 16),
            ],
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _generatingTicket
                    ? null
                    : () => _openVehicleSelection(data),
                icon: _generatingTicket
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.local_parking_rounded),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.accent,
                  foregroundColor: const Color(0xFF22252C),
                  elevation: 0,
                  minimumSize: const Size.fromHeight(50),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                label: Text(
                  _generatingTicket ? 'Preparing checkout...' : 'Park Here',
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
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
          isPayMongoConfigured: true,
          onProcessPayment:
              ({
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
      if (amount <= 0) {
        _showSnackBar('Selected package has no valid amount configured.');
        return false;
      }

      // The server prices the package from the establishment's own rates
      // and opens the PayMongo checkout; the app never sees the secret key.
      final ParkingCheckout checkout = await _checkoutService.createCheckout(
        establishmentId: widget.establishmentId,
        vehicleType: vehicleType,
        plateNumber: plateNumber,
        plan: plan,
        duration: duration,
        paymentMethod: paymentMethod.apiType,
      );

      if (!mounted) {
        return false;
      }

      await Navigator.of(context).push<dynamic>(
        MaterialPageRoute<dynamic>(
          builder: (_) => DriverInAppCheckoutPage(
            establishmentName: checkout.establishmentName,
            checkoutUrl: checkout.checkoutUrl,
            checkPaid: () async => (await _checkoutService.confirmCheckout(
              checkout.checkoutId,
            )).isPaid,
          ),
        ),
      );

      if (!mounted) {
        return false;
      }

      // Whatever the web view reported, only the server's answer counts.
      final ParkingCheckoutStatus status = await _checkoutService.pollUntilPaid(
        checkout.checkoutId,
      );
      if (!status.isPaid || status.qrCode == null) {
        _showSnackBar(
          'Payment was not confirmed. If you completed payment, your ticket '
          'will appear in your tickets within a few minutes.',
        );
        return false;
      }

      if (!mounted) {
        return true;
      }

      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => DriverPaidTicketPage(
            establishmentName: status.establishmentName,
            amount: status.amount,
            qrData: status.qrCode!,
          ),
        ),
      );

      return true;
    } on FirebaseFunctionsException catch (error) {
      _showSnackBar(error.message ?? 'Failed to process payment.');
      return false;
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
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: cachedStream('establishment', _establishmentRef.snapshots),
      builder:
          (
            BuildContext context,
            AsyncSnapshot<DocumentSnapshot<Map<String, dynamic>>> snapshot,
          ) {
            return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              stream: cachedStream(
                'details',
                _establishmentDetailsRef.snapshots,
              ),
              builder:
                  (
                    BuildContext context,
                    AsyncSnapshot<DocumentSnapshot<Map<String, dynamic>>>
                    detailsSnapshot,
                  ) {
                    Widget message(Widget child) => Scaffold(
                      backgroundColor: AppTheme.background,
                      appBar: AppBar(
                        backgroundColor: Colors.white,
                        title: const Text('Parking Details'),
                      ),
                      body: Center(child: child),
                    );

                    if (snapshot.connectionState == ConnectionState.waiting ||
                        detailsSnapshot.connectionState ==
                            ConnectionState.waiting) {
                      return message(const CircularProgressIndicator());
                    }
                    if (snapshot.hasError || detailsSnapshot.hasError) {
                      return message(
                        const Text(
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
                      return message(
                        const Text(
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

                    return Scaffold(
                      backgroundColor: AppTheme.background,
                      appBar: AppBar(
                        backgroundColor: Colors.white,
                        surfaceTintColor: Colors.white,
                        title: const Text('Parking Details'),
                      ),
                      body: _buildBody(data),
                      bottomNavigationBar: _buildBottomBar(data),
                    );
                  },
            );
          },
    );
  }
}
