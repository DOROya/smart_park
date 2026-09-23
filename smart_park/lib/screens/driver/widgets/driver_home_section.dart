import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../../theme/app_theme.dart';
import '../services/driver_establishment_service.dart';

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

class _DriverHomeSectionState extends State<DriverHomeSection> {
  double _selectedRadiusKm = 1;
  bool _radiusExpanded = false;

  double _distanceToUserKm(Map<String, dynamic> establishment) {
    return DriverEstablishmentService.distanceToUserMeters(
          establishment: establishment,
          currentPosition: widget.currentPosition,
        ) /
        1000;
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('establishment_details')
          .where('status', isEqualTo: 'approved')
          .snapshots(),
      builder: (
        BuildContext context,
        AsyncSnapshot<QuerySnapshot<Map<String, dynamic>>> detailsSnapshot,
      ) {
        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection('establishments')
              .snapshots(),
          builder: (
            BuildContext context,
            AsyncSnapshot<QuerySnapshot<Map<String, dynamic>>> snapshot,
          ) {
            final List<QueryDocumentSnapshot<Map<String, dynamic>>> detailsDocs =
                detailsSnapshot.data?.docs ??
                <QueryDocumentSnapshot<Map<String, dynamic>>>[];
            final List<QueryDocumentSnapshot<Map<String, dynamic>>>
            establishmentDocs =
                snapshot.data?.docs ??
                <QueryDocumentSnapshot<Map<String, dynamic>>>[];

            final Map<String, Map<String, dynamic>> detailsById =
                <String, Map<String, dynamic>>{};
            for (final QueryDocumentSnapshot<Map<String, dynamic>> doc
                in detailsDocs) {
              final Map<String, dynamic> details = <String, dynamic>{
                ...doc.data(),
                'establishmentID':
                    (doc.data()['establishmentID'] as String?) ?? doc.id,
              };
              detailsById[doc.id] = details;
              detailsById[details['establishmentID'] as String] = details;
            }

            final List<Map<String, dynamic>> mergedEstablishments =
                establishmentDocs
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

            final List<Map<String, dynamic>> baseDocs =
                DriverEstablishmentService.filterAndSort(
                  establishments: mergedEstablishments,
                  searchQuery: widget.searchQuery,
                  openNowOnly: widget.openNowOnly,
                  sortOption: widget.sortOption,
                  currentPosition: widget.currentPosition,
                );

            final List<Map<String, dynamic>> displayedDocs =
                widget.currentPosition == null
                ? baseDocs
                : baseDocs.where((Map<String, dynamic> establishment) {
                    return DriverEstablishmentService.distanceToUserMeters(
                          establishment: establishment,
                          currentPosition: widget.currentPosition,
                        ) <=
                        _selectedRadiusKm * 1000;
                  }).toList();

            displayedDocs.sort((Map<String, dynamic> a, Map<String, dynamic> b) {
              return DriverEstablishmentService.distanceToUserMeters(
                establishment: a,
                currentPosition: widget.currentPosition,
              ).compareTo(
                DriverEstablishmentService.distanceToUserMeters(
                  establishment: b,
                  currentPosition: widget.currentPosition,
                ),
              );
            });

            final Set<Marker> parkingMarkers =
                DriverEstablishmentService.buildMarkers(
                  establishments: displayedDocs,
                  onTap: widget.onEstablishmentTap,
                );

            final Set<Circle> userLocationCircle =
                DriverEstablishmentService.buildUserLocationCircle(
                  widget.currentPosition,
                );
            if (widget.currentPosition != null) {
              userLocationCircle.add(
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
                  myLocationButtonEnabled: true,
                  markers: parkingMarkers,
                  circles: userLocationCircle,
                  onMapCreated: widget.onMapCreated,
                ),
                Positioned(
                  top: 16,
                  left: 16,
                  right: 16,
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x22000000),
                          blurRadius: 10,
                          offset: Offset(0, 5),
                        ),
                      ],
                    ),
                    child: TextField(
                      controller: widget.searchController,
                      decoration: const InputDecoration(
                        hintText: 'Search parking near you...',
                        prefixIcon: Icon(Icons.search_rounded),
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 14,
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned.fill(
                  child: DraggableScrollableSheet(
                    initialChildSize: 0.15,
                    minChildSize: 0.15,
                    maxChildSize: 0.82,
                    expand: true,
                    snap: true,
                    snapSizes: const <double>[0.15, 0.55, 0.82],
                    builder: (
                      BuildContext context,
                      ScrollController scrollController,
                    ) {
                      return DecoratedBox(
                        decoration: const BoxDecoration(
                          color: Color(0xFFF7F8FB),
                          borderRadius: BorderRadius.vertical(
                            top: Radius.circular(24),
                          ),
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
                              child: Column(
                                children: [
                                  const SizedBox(height: 10),
                                  Container(
                                    width: 42,
                                    height: 5,
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFD1D5DE),
                                      borderRadius: BorderRadius.circular(999),
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                    ),
                                    child: Row(
                                      children: [
                                        Container(
                                          width: 34,
                                          height: 34,
                                          decoration: BoxDecoration(
                                            color: const Color(0xFFFFF2CA),
                                            borderRadius:
                                                BorderRadius.circular(10),
                                          ),
                                          child: const Icon(
                                            Icons.local_parking_rounded,
                                            color: Color(0xFF373D4A),
                                            size: 20,
                                          ),
                                        ),
                                        const SizedBox(width: 10),
                                        const Expanded(
                                          child: Text(
                                            'Nearby Parking',
                                            style: TextStyle(
                                              fontSize: 18,
                                              fontWeight: FontWeight.w700,
                                              color: AppTheme.textDark,
                                            ),
                                          ),
                                        ),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 10,
                                            vertical: 6,
                                          ),
                                          decoration: BoxDecoration(
                                            color: Colors.white,
                                            borderRadius:
                                                BorderRadius.circular(999),
                                            border: Border.all(
                                              color: const Color(0xFFE2E5ED),
                                            ),
                                          ),
                                          child: Text(
                                            '${displayedDocs.length} found',
                                            style: const TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w700,
                                              color: Color(0xFF616877),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  const Padding(
                                    padding: EdgeInsets.symmetric(
                                      horizontal: 16,
                                    ),
                                    child: Align(
                                      alignment: Alignment.centerLeft,
                                      child: Text(
                                        'Drag up to browse and tap a card to open details.',
                                        style: TextStyle(
                                          color: AppTheme.textMuted,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                    ),
                                    child: Container(
                                      width: double.infinity,
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        borderRadius: BorderRadius.circular(14),
                                        border: Border.all(
                                          color: const Color(0xFFE3E5EA),
                                        ),
                                      ),
                                      child: Theme(
                                        data: Theme.of(context).copyWith(
                                          dividerColor: Colors.transparent,
                                        ),
                                        child: ExpansionTile(
                                          initiallyExpanded: _radiusExpanded,
                                          onExpansionChanged: (bool expanded) {
                                            setState(() {
                                              _radiusExpanded = expanded;
                                            });
                                          },
                                          tilePadding:
                                              const EdgeInsets.symmetric(
                                                horizontal: 12,
                                              ),
                                          title: Text(
                                            'Radius: ${_selectedRadiusKm.toStringAsFixed(_selectedRadiusKm % 1 == 0 ? 0 : 1)} km',
                                            style: const TextStyle(
                                              color: AppTheme.textDark,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                          subtitle: Text(
                                            '${displayedDocs.length} registered establishment(s) within radius',
                                            style: const TextStyle(
                                              color: AppTheme.textMuted,
                                              fontSize: 12,
                                            ),
                                          ),
                                          childrenPadding:
                                              const EdgeInsets.fromLTRB(
                                                12,
                                                0,
                                                12,
                                                10,
                                              ),
                                          children: [
                                            Slider(
                                              value: _selectedRadiusKm,
                                              min: 0.5,
                                              max: 5,
                                              divisions: 9,
                                              label:
                                                  '${_selectedRadiusKm.toStringAsFixed(_selectedRadiusKm % 1 == 0 ? 0 : 1)} km',
                                              onChanged: (double value) {
                                                setState(() {
                                                  _selectedRadiusKm = value;
                                                });
                                              },
                                            ),
                                            Text(
                                              'Showing establishments within ${_selectedRadiusKm.toStringAsFixed(_selectedRadiusKm % 1 == 0 ? 0 : 1)} km.',
                                              style: const TextStyle(
                                                color: AppTheme.textMuted,
                                                fontSize: 12,
                                              ),
                                            ),
                                            const SizedBox(height: 8),
                                            if (widget.currentPosition == null)
                                              const Text(
                                                'Enable location to apply accurate radius filtering.',
                                                style: TextStyle(
                                                  color: AppTheme.textMuted,
                                                ),
                                              )
                                            else if (displayedDocs.isEmpty)
                                              const Text(
                                                'No registered establishments found in this radius.',
                                                style: TextStyle(
                                                  color: AppTheme.textMuted,
                                                ),
                                              )
                                            else
                                              ConstrainedBox(
                                                constraints:
                                                    const BoxConstraints(
                                                      maxHeight: 120,
                                                    ),
                                                child: ListView.builder(
                                                  itemCount: displayedDocs.length,
                                                  itemBuilder: (
                                                    BuildContext context,
                                                    int index,
                                                  ) {
                                                    final Map<String, dynamic> doc =
                                                        displayedDocs[index];
                                                    final String establishmentId =
                                                        (doc['establishmentID']
                                                                as String?) ??
                                                            '';
                                                    return ListTile(
                                                      dense: true,
                                                      contentPadding:
                                                          EdgeInsets.zero,
                                                      title: Text(
                                                        (doc['name']
                                                                as String?) ??
                                                            'Parking Establishment',
                                                        maxLines: 1,
                                                        overflow:
                                                            TextOverflow.ellipsis,
                                                      ),
                                                      subtitle: Text(
                                                        '${_distanceToUserKm(doc).toStringAsFixed(2)} km away',
                                                        maxLines: 1,
                                                        overflow:
                                                            TextOverflow.ellipsis,
                                                      ),
                                                      onTap: establishmentId.isEmpty
                                                          ? null
                                                          : () => widget
                                                              .onEstablishmentTap(
                                                                establishmentId,
                                                              ),
                                                    );
                                                  },
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                ],
                              ),
                            ),
                            if (snapshot.hasError || detailsSnapshot.hasError)
                              const SliverFillRemaining(
                                hasScrollBody: false,
                                child: Center(
                                  child: Text(
                                    'Unable to load nearby parking right now.',
                                    style: TextStyle(
                                      color: AppTheme.textMuted,
                                    ),
                                  ),
                                ),
                              )
                            else if (snapshot.connectionState ==
                                    ConnectionState.waiting ||
                                detailsSnapshot.connectionState ==
                                    ConnectionState.waiting)
                              const SliverFillRemaining(
                                hasScrollBody: false,
                                child: Center(
                                  child: CircularProgressIndicator(),
                                ),
                              )
                            else if (displayedDocs.isEmpty)
                              SliverFillRemaining(
                                hasScrollBody: false,
                                child: Center(
                                  child: Text(
                                    'No parking establishments found within ${_selectedRadiusKm.toStringAsFixed(_selectedRadiusKm % 1 == 0 ? 0 : 1)} km.',
                                    style: const TextStyle(
                                      color: AppTheme.textMuted,
                                    ),
                                  ),
                                ),
                              )
                            else
                              SliverPadding(
                                padding: const EdgeInsets.fromLTRB(
                                  16,
                                  0,
                                  16,
                                  20,
                                ),
                                sliver: SliverList(
                                  delegate: SliverChildBuilderDelegate((
                                    BuildContext context,
                                    int index,
                                  ) {
                                    final Map<String, dynamic> doc =
                                        displayedDocs[index];
                                    final String establishmentId =
                                        (doc['establishmentID'] as String?) ??
                                            '';
                                    return _DriverParkingCard(
                                      data: doc,
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
          },
        );
      },
    );
  }
}

class _DriverParkingCard extends StatelessWidget {
  const _DriverParkingCard({required this.data, this.onTap});

  final Map<String, dynamic> data;
  final VoidCallback? onTap;

  String _startingPrice(String pricing) {
    final Match? match = RegExp(r'\d+(?:\.\d+)?').firstMatch(pricing);
    return match?.group(0) ?? '--';
  }

  List<String> _vehicleKeys(Map<String, dynamic> slotCounts) {
    return slotCounts.entries
        .where((MapEntry<String, dynamic> entry) => entry.value is num)
        .map((MapEntry<String, dynamic> entry) => entry.key)
        .toList();
  }

  String _vehicleLabel(String key) {
    return switch (key) {
      'car' => 'Car',
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

  @override
  Widget build(BuildContext context) {
    final String parkingName =
        (data['name'] as String?) ?? 'Parking Establishment';
    final String address =
        (data['address'] as String?) ?? 'Address not available';
    final double rating = ((data['rating'] as num?) ?? 0).toDouble();
    final Map<String, dynamic> slotCounts =
        (data['slotCounts'] as Map<String, dynamic>?) ?? <String, dynamic>{};
    final Map<String, dynamic> activeSlots =
      (data['slots'] as Map<String, dynamic>?) ?? <String, dynamic>{};
    final String operatingHours =
        (data['operatingHours'] as String?) ?? 'Not provided';
    final String pricing = (data['pricing'] as String?) ?? 'Not provided';
    final List<String> photoUrls =
        ((data['photoUrls'] as List<dynamic>?) ?? <dynamic>[])
        .whereType<String>()
        .toList();
    final String? thumbnailUrl = photoUrls.isEmpty ? null : photoUrls.first;
    final List<String> vehicleKeys = _vehicleKeys(slotCounts);

    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFFE6E8EE)),
          boxShadow: const [
            BoxShadow(
              color: Color(0x11000000),
              blurRadius: 10,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: 118,
              width: double.infinity,
              child: thumbnailUrl == null
                  ? Container(
                      color: const Color(0xFFF1F3F7),
                      alignment: Alignment.center,
                      child: const Icon(
                        Icons.local_parking_rounded,
                        color: Color(0xFF757B88),
                        size: 38,
                      ),
                    )
                  : Image.network(
                      thumbnailUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) => Container(
                        color: const Color(0xFFF1F3F7),
                        alignment: Alignment.center,
                        child: const Icon(
                          Icons.broken_image_rounded,
                          color: Color(0xFF757B88),
                          size: 32,
                        ),
                      ),
                    ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 11, 14, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          parkingName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: AppTheme.textDark,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Icon(
                        Icons.star_rounded,
                        color: Color(0xFFF8BA00),
                        size: 19,
                      ),
                      const SizedBox(width: 3),
                      Text(
                        rating.toStringAsFixed(1),
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.textDark,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    address,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 10,
                      color: Color(0xFF949AA6),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      ...vehicleKeys.map(
                        (String key) => _CompactParkingStat(
                          icon: _vehicleIcon(key),
                          label: _vehicleLabel(key),
                          value:
                              '${_vehicleCount(activeSlots, key)}/${_vehicleCount(slotCounts, key)}',
                        ),
                      ),
                      _CompactParkingStat(
                          icon: Icons.access_time_rounded,
                          label: 'Hours',
                          value: operatingHours,
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  RichText(
                    text: TextSpan(
                      style: const TextStyle(
                        fontSize: 10,
                        color: Color(0xFF757B88),
                      ),
                      children: [
                        const TextSpan(text: 'From '),
                        TextSpan(
                          text: 'P${_startingPrice(pricing)}',
                          style: const TextStyle(
                            color: Color(0xFF2463D4),
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const TextSpan(text: '/hr'),
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
}

class _CompactParkingStat extends StatelessWidget {
  const _CompactParkingStat({
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
      constraints: const BoxConstraints(minWidth: 80),
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xFFFCFCFD),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: const Color(0xFFE0E2E7)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 19, color: const Color(0xFF171B22)),
          const SizedBox(width: 7),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 10,
                    color: Color(0xFF4F5561),
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF20242C),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

