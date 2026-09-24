import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../../theme/app_theme.dart';
import '../../../widgets/smartpark_ui.dart';
import '../services/driver_establishment_service.dart';
import '../../../services/operating_hours.dart';

class DriverHomeSection extends StatefulWidget {
  const DriverHomeSection({
    super.key,
    required this.currentPosition,
    required this.searchController,
    required this.searchQuery,
    required this.sortOption,
    required this.openNowOnly,
    required this.onSortChanged,
    required this.onOpenNowChanged,
    required this.onMapCreated,
    required this.onEstablishmentTap,
  });

  final Position? currentPosition;
  final TextEditingController searchController;
  final String searchQuery;
  final DriverSortOption sortOption;
  final bool openNowOnly;
  final ValueChanged<DriverSortOption> onSortChanged;
  final ValueChanged<bool> onOpenNowChanged;
  final ValueChanged<GoogleMapController> onMapCreated;
  final ValueChanged<String> onEstablishmentTap;

  @override
  State<DriverHomeSection> createState() => _DriverHomeSectionState();
}

class _DriverHomeSectionState extends State<DriverHomeSection>
    with SpStreamCache<DriverHomeSection> {
  static const List<double> _radiusOptionsKm = <double>[0.5, 1, 2, 3, 5];

  double _selectedRadiusKm = 1;

  String _formatKm(double km) => km.toStringAsFixed(km % 1 == 0 ? 0 : 1);

  double _distanceMeters(Map<String, dynamic> establishment) {
    return DriverEstablishmentService.distanceToUserMeters(
      establishment: establishment,
      currentPosition: widget.currentPosition,
    );
  }

  Widget _filterChip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
    IconData? icon,
  }) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        avatar: icon == null
            ? null
            : Icon(
                icon,
                size: 16,
                color: selected ? AppTheme.textDark : AppTheme.textMuted,
              ),
        label: Text(label),
        selected: selected,
        showCheckmark: false,
        onSelected: (_) => onTap(),
        selectedColor: AppTheme.accent,
        backgroundColor: Colors.white,
        side: BorderSide(color: selected ? AppTheme.accent : spCardBorder),
        labelStyle: TextStyle(
          fontWeight: FontWeight.w700,
          fontSize: 12,
          color: selected ? AppTheme.textDark : AppTheme.textMuted,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
        visualDensity: VisualDensity.compact,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: cachedStream(
        'approved_details',
        () => FirebaseFirestore.instance
            .collection('establishment_details')
            .where('status', isEqualTo: 'approved')
            .snapshots(),
      ),
      builder:
          (
            BuildContext context,
            AsyncSnapshot<QuerySnapshot<Map<String, dynamic>>> detailsSnapshot,
          ) {
            return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: cachedStream(
                'establishments',
                () => FirebaseFirestore.instance
                    .collection('establishments')
                    .snapshots(),
              ),
              builder:
                  (
                    BuildContext context,
                    AsyncSnapshot<QuerySnapshot<Map<String, dynamic>>> snapshot,
                  ) {
                    return _buildContent(
                      detailsSnapshot: detailsSnapshot,
                      snapshot: snapshot,
                    );
                  },
            );
          },
    );
  }

  Widget _buildContent({
    required AsyncSnapshot<QuerySnapshot<Map<String, dynamic>>> detailsSnapshot,
    required AsyncSnapshot<QuerySnapshot<Map<String, dynamic>>> snapshot,
  }) {
    final Map<String, Map<String, dynamic>> detailsById =
        <String, Map<String, dynamic>>{};
    for (final QueryDocumentSnapshot<Map<String, dynamic>> doc
        in detailsSnapshot.data?.docs ??
            <QueryDocumentSnapshot<Map<String, dynamic>>>[]) {
      final Map<String, dynamic> details = <String, dynamic>{
        ...doc.data(),
        'establishmentID': (doc.data()['establishmentID'] as String?) ?? doc.id,
      };
      detailsById[doc.id] = details;
      detailsById[details['establishmentID'] as String] = details;
    }

    final List<Map<String, dynamic>> mergedEstablishments =
        (snapshot.data?.docs ?? <QueryDocumentSnapshot<Map<String, dynamic>>>[])
            .map((QueryDocumentSnapshot<Map<String, dynamic>> doc) {
              final String storedId =
                  (doc.data()['establishmentID'] as String?) ?? doc.id;
              final Map<String, dynamic>? details =
                  detailsById[doc.id] ?? detailsById[storedId];
              if (details == null ||
                  ((details['status'] as String?) ?? '').toLowerCase() !=
                      'approved') {
                return null;
              }
              return <String, dynamic>{
                ...doc.data(),
                ...details,
                'establishmentID': storedId,
              };
            })
            .whereType<Map<String, dynamic>>()
            .toList();

    final List<Map<String, dynamic>> displayedDocs =
        DriverEstablishmentService.filterAndSort(
          establishments: mergedEstablishments,
          searchQuery: widget.searchQuery,
          openNowOnly: widget.openNowOnly,
          sortOption: widget.sortOption,
          currentPosition: widget.currentPosition,
        );
    if (widget.currentPosition != null) {
      displayedDocs.removeWhere(
        (Map<String, dynamic> establishment) =>
            _distanceMeters(establishment) > _selectedRadiusKm * 1000,
      );
      // Nearest first unless the driver picked another sort.
      if (widget.sortOption == DriverSortOption.none) {
        displayedDocs.sort(
          (Map<String, dynamic> a, Map<String, dynamic> b) =>
              _distanceMeters(a).compareTo(_distanceMeters(b)),
        );
      }
    }

    final Set<Marker> parkingMarkers = DriverEstablishmentService.buildMarkers(
      establishments: displayedDocs,
      onTap: widget.onEstablishmentTap,
    );
    final Set<Circle> circles =
        DriverEstablishmentService.buildUserLocationCircle(
          widget.currentPosition,
        );
    if (widget.currentPosition != null) {
      circles.add(
        Circle(
          circleId: const CircleId('selected_radius_coverage_alt'),
          center: LatLng(
            widget.currentPosition!.latitude,
            widget.currentPosition!.longitude,
          ),
          radius: _selectedRadiusKm * 1000,
          strokeWidth: 2,
          strokeColor: const Color(0xAA0F9D58),
          fillColor: const Color(0x220F9D58),
        ),
      );
    }

    final bool loading =
        snapshot.connectionState == ConnectionState.waiting ||
        detailsSnapshot.connectionState == ConnectionState.waiting;

    return Stack(
      children: [
        GoogleMap(
          initialCameraPosition: CameraPosition(
            target: widget.currentPosition == null
                ? DriverEstablishmentService.fallbackCenter
                : LatLng(
                    widget.currentPosition!.latitude,
                    widget.currentPosition!.longitude,
                  ),
            zoom: 14,
          ),
          myLocationEnabled: true,
          myLocationButtonEnabled: false,
          zoomControlsEnabled: false,
          markers: parkingMarkers,
          circles: circles,
          onMapCreated: widget.onMapCreated,
        ),
        Positioned(
          top: 16,
          left: 16,
          right: 16,
          child: Material(
            color: Colors.white,
            elevation: 4,
            shadowColor: const Color(0x33000000),
            borderRadius: BorderRadius.circular(16),
            child: TextField(
              controller: widget.searchController,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: 'Search parking by name or address',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: widget.searchQuery.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Clear search',
                        icon: const Icon(Icons.close_rounded),
                        onPressed: widget.searchController.clear,
                      ),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
              ),
            ),
          ),
        ),
        Positioned.fill(
          child: DraggableScrollableSheet(
            // Starts collapsed to just the handle + title so the map stays
            // clear; drag up for filters and the list.
            initialChildSize: 0.1,
            minChildSize: 0.1,
            maxChildSize: 0.85,
            snap: true,
            snapSizes: const <double>[0.1, 0.5, 0.85],
            builder: (BuildContext context, ScrollController scrollController) {
              return DecoratedBox(
                decoration: const BoxDecoration(
                  color: AppTheme.background,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                  boxShadow: [
                    BoxShadow(
                      color: Color(0x23000000),
                      blurRadius: 16,
                      offset: Offset(0, -4),
                    ),
                  ],
                ),
                child: CustomScrollView(
                  controller: scrollController,
                  slivers: [
                    SliverToBoxAdapter(
                      child: _buildSheetHeader(displayedDocs.length),
                    ),
                    if (snapshot.hasError || detailsSnapshot.hasError)
                      const SliverToBoxAdapter(
                        child: Padding(
                          padding: EdgeInsets.fromLTRB(16, 4, 16, 16),
                          child: SpEmptyState(
                            icon: Icons.error_outline_rounded,
                            message: 'Unable to load nearby parking right now.',
                          ),
                        ),
                      )
                    else if (loading)
                      const SliverToBoxAdapter(
                        child: Padding(
                          padding: EdgeInsets.all(24),
                          child: Center(child: CircularProgressIndicator()),
                        ),
                      )
                    else if (displayedDocs.isEmpty)
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                          child: SpEmptyState(
                            icon: Icons.search_off_rounded,
                            message: widget.openNowOnly
                                ? 'No open parking within ${_formatKm(_selectedRadiusKm)} km. '
                                      'Try a wider radius or turn off "Open now".'
                                : 'No parking found within ${_formatKm(_selectedRadiusKm)} km. '
                                      'Try a wider radius.',
                          ),
                        ),
                      )
                    else
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
                        sliver: SliverList(
                          delegate: SliverChildBuilderDelegate((
                            BuildContext context,
                            int index,
                          ) {
                            final Map<String, dynamic> doc =
                                displayedDocs[index];
                            final String establishmentId =
                                (doc['establishmentID'] as String?) ?? '';
                            return _DriverParkingCard(
                              data: doc,
                              distanceMeters: widget.currentPosition == null
                                  ? null
                                  : _distanceMeters(doc),
                              onTap: establishmentId.isEmpty
                                  ? null
                                  : () => widget.onEstablishmentTap(
                                      establishmentId,
                                    ),
                            );
                          }, childCount: displayedDocs.length),
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildSheetHeader(int count) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 42,
              height: 5,
              decoration: BoxDecoration(
                color: const Color(0xFFD1D5DE),
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),
          const SizedBox(height: 12),
          SpSectionLabel(
            'Nearby Parking',
            trailing: SpChip(label: '$count found', color: spExitColor),
          ),
          const SizedBox(height: 2),
          Text(
            widget.currentPosition == null
                ? 'Turn on location to see parking around you.'
                : 'Within ${_formatKm(_selectedRadiusKm)} km of you. Tap a card for details.',
            style: const TextStyle(fontSize: 12, color: AppTheme.textMuted),
          ),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _filterChip(
                  label: 'Open now',
                  icon: Icons.schedule_rounded,
                  selected: widget.openNowOnly,
                  onTap: () => widget.onOpenNowChanged(!widget.openNowOnly),
                ),
                _filterChip(
                  label: 'Most slots',
                  icon: Icons.local_parking_rounded,
                  selected: widget.sortOption == DriverSortOption.mostSlots,
                  onTap: () => widget.onSortChanged(
                    widget.sortOption == DriverSortOption.mostSlots
                        ? DriverSortOption.none
                        : DriverSortOption.mostSlots,
                  ),
                ),
                Container(
                  width: 1,
                  height: 24,
                  margin: const EdgeInsets.only(right: 8),
                  color: spCardBorder,
                ),
                for (final double km in _radiusOptionsKm)
                  _filterChip(
                    label: '${_formatKm(km)} km',
                    selected: _selectedRadiusKm == km,
                    onTap: () => setState(() => _selectedRadiusKm = km),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DriverParkingCard extends StatelessWidget {
  const _DriverParkingCard({
    required this.data,
    required this.distanceMeters,
    this.onTap,
  });

  final Map<String, dynamic> data;
  final double? distanceMeters;
  final VoidCallback? onTap;

  /// Lowest base rate (first [spBaseStayHours] hours) across vehicle types,
  /// or null if unknown.
  double? _startingPrice() {
    final Map<dynamic, dynamic> rates =
        ((data['rates'] ?? data['ratesByType']) as Map<dynamic, dynamic>?) ??
        <dynamic, dynamic>{};
    double? lowest;
    for (final dynamic value in rates.values) {
      final dynamic raw = value is Map
          ? (value['initial'] ?? value['hourly'])
          : value;
      final double? price = double.tryParse('${raw ?? ''}'.trim());
      if (price != null && price > 0 && (lowest == null || price < lowest)) {
        lowest = price;
      }
    }
    if (lowest != null) {
      return lowest;
    }
    final Match? match = RegExp(
      r'\d+(?:\.\d+)?',
    ).firstMatch((data['pricing'] as String?) ?? '');
    return match == null ? null : double.tryParse(match.group(0)!);
  }

  String _formatDistance(double meters) => meters < 1000
      ? '${meters.round()} m'
      : '${(meters / 1000).toStringAsFixed(1)} km';

  Widget _overlayChip(IconData icon, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(999),
        boxShadow: const [BoxShadow(color: Color(0x22000000), blurRadius: 6)],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoChip(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFFF6F7FA),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: AppTheme.textDark),
          const SizedBox(width: 4),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 170),
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: AppTheme.textDark,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final String name = ((data['name'] as String?) ?? '').trim();
    final String address = ((data['address'] as String?) ?? '').trim();
    final String hours = OperatingHours.parse(data).isSet
        ? OperatingHours.parse(data).label
        : ((data['operatingHours'] as String?) ?? '').trim();
    final String establishmentId = ((data['establishmentID'] as String?) ?? '')
        .trim();
    final Map<dynamic, dynamic> slotCounts =
        (data['slotCounts'] as Map<dynamic, dynamic>?) ?? <dynamic, dynamic>{};
    final int carSlots = ((slotCounts['car'] as num?) ?? 0).toInt();
    final int motorcycleSlots = ((slotCounts['motorcycle'] as num?) ?? 0)
        .toInt();
    final List<String> photoUrls =
        ((data['photoUrls'] as List<dynamic>?) ?? <dynamic>[])
            .whereType<String>()
            .toList();
    final String? thumbnailUrl = photoUrls.isEmpty ? null : photoUrls.first;
    final bool openNow = DriverEstablishmentService.isOpenNow(data);
    final double? price = _startingPrice();
    final double rating = ((data['rating'] as num?) ?? 0).toDouble();

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: Colors.white,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: spCardBorder),
        ),
        child: InkWell(
          onTap: onTap,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                height: 120,
                width: double.infinity,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (thumbnailUrl == null)
                      const ColoredBox(
                        color: Color(0xFFF1F3F7),
                        child: Icon(
                          Icons.local_parking_rounded,
                          color: Color(0xFF9DA1AB),
                          size: 40,
                        ),
                      )
                    else
                      Image.network(
                        thumbnailUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => const ColoredBox(
                          color: Color(0xFFF1F3F7),
                          child: Icon(
                            Icons.local_parking_rounded,
                            color: Color(0xFF9DA1AB),
                            size: 40,
                          ),
                        ),
                      ),
                    Positioned(
                      top: 10,
                      left: 10,
                      child: _overlayChip(
                        Icons.circle,
                        openNow ? 'Open now' : 'Closed',
                        openNow ? spEntryColor : spDeniedColor,
                      ),
                    ),
                    if (distanceMeters != null)
                      Positioned(
                        top: 10,
                        right: 10,
                        child: _overlayChip(
                          Icons.near_me_rounded,
                          _formatDistance(distanceMeters!),
                          AppTheme.textDark,
                        ),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            name.isEmpty ? 'Parking Establishment' : name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: AppTheme.textDark,
                            ),
                          ),
                        ),
                        if (rating > 0) ...[
                          const SizedBox(width: 8),
                          const Icon(
                            Icons.star_rounded,
                            color: Color(0xFFF8BA00),
                            size: 18,
                          ),
                          const SizedBox(width: 2),
                          Text(
                            rating.toStringAsFixed(1),
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              color: AppTheme.textDark,
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        const Icon(
                          Icons.location_on_outlined,
                          size: 14,
                          color: AppTheme.textMuted,
                        ),
                        const SizedBox(width: 3),
                        Expanded(
                          child: Text(
                            address.isEmpty ? 'Address not available' : address,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppTheme.textMuted,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                      stream: establishmentId.isEmpty
                          ? null
                          : SpOccupancy.watch(establishmentId),
                      builder:
                          (
                            BuildContext context,
                            AsyncSnapshot<
                              DocumentSnapshot<Map<String, dynamic>>
                            >
                            snapshot,
                          ) {
                            final SpOccupancy? live = SpOccupancy.fromDoc(
                              snapshot.data,
                            );
                            String slots(
                              int capacity,
                              int? occupied,
                              String what,
                            ) => occupied == null
                                ? '$capacity $what slots'
                                : '${(capacity - occupied).clamp(0, capacity)}/$capacity $what free';
                            return Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: [
                                if (carSlots > 0)
                                  _infoChip(
                                    Icons.directions_car_rounded,
                                    slots(carSlots, live?.car, 'car'),
                                  ),
                                if (motorcycleSlots > 0)
                                  _infoChip(
                                    Icons.two_wheeler_rounded,
                                    slots(
                                      motorcycleSlots,
                                      live?.motorcycle,
                                      'moto',
                                    ),
                                  ),
                                if (hours.isNotEmpty)
                                  _infoChip(Icons.schedule_rounded, hours),
                              ],
                            );
                          },
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: price == null
                              ? const Text(
                                  'See rates',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: AppTheme.textMuted,
                                  ),
                                )
                              : Text.rich(
                                  TextSpan(
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: AppTheme.textMuted,
                                    ),
                                    children: [
                                      const TextSpan(text: 'From '),
                                      TextSpan(
                                        text:
                                            'PHP ${price.toStringAsFixed(price % 1 == 0 ? 0 : 2)}',
                                        style: const TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w800,
                                          color: AppTheme.textDark,
                                        ),
                                      ),
                                      const TextSpan(
                                        text: ' / first $spBaseStayLabel',
                                      ),
                                    ],
                                  ),
                                ),
                        ),
                        const Text(
                          'View details',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: spExitColor,
                          ),
                        ),
                        const Icon(
                          Icons.chevron_right_rounded,
                          size: 18,
                          color: spExitColor,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
