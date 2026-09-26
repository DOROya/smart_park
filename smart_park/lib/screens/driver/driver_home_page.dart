import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../services/permission_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/smartpark_ui.dart';
import '../../widgets/sp_profile_view.dart';
import '../auth/sign_in_screen.dart';
import 'establishment_detail_page.dart';
import 'services/driver_establishment_service.dart';
import 'widgets/driver_home_section.dart';
import 'widgets/driver_ticket_history_section.dart';

class DriverHomePage extends StatefulWidget {
  const DriverHomePage({super.key, this.role = 'driver'});

  final String role;

  @override
  State<DriverHomePage> createState() => _DriverHomePageState();
}

class _DriverHomePageState extends State<DriverHomePage>
    with WidgetsBindingObserver {
  late final Future<DocumentSnapshot<Map<String, dynamic>>> _userFuture;
  final PermissionService _permissionService = const PermissionService();
  final TextEditingController _searchController = TextEditingController();
  StreamSubscription<Position>? _positionSubscription;

  GoogleMapController? _mapController;
  Position? _currentPosition;
  String _locationLabel = 'Detecting your location...';
  String _searchQuery = '';
  int _selectedIndex = 0;
  DriverSortOption _sortOption = DriverSortOption.none;
  bool _openNowOnly = false;
  bool _locationServiceDialogOpen = false;
  bool _awaitingLocationSettingsReturn = false;

  final TextEditingController _profileFirstNameController =
      TextEditingController();
  final TextEditingController _profileLastNameController =
      TextEditingController();
  final TextEditingController _profileEmailController = TextEditingController();

  bool _profileSeeded = false;

  /// Where the location label was last reverse-geocoded, so live GPS updates
  /// only look the place name up again after moving a few hundred meters.
  Position? _labelPosition;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _searchController.addListener(_onSearchChanged);
    _userFuture = _fetchUserDocument();
    unawaited(_initializeDriverPermissions());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _awaitingLocationSettingsReturn) {
      _awaitingLocationSettingsReturn = false;
      unawaited(_loadCurrentLocation(promptForServiceEnable: false));
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _positionSubscription?.cancel();
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    _profileFirstNameController.dispose();
    _profileLastNameController.dispose();
    _profileEmailController.dispose();
    _mapController?.dispose();
    super.dispose();
  }

  void _seedProfileControllers(Map<String, dynamic>? data) {
    // The first build runs before the user document loads; seeding then
    // would lock the fields to empty values.
    if (_profileSeeded || data == null) {
      return;
    }

    _profileSeeded = true;
    _profileFirstNameController.text = ((data['firstName'] as String?) ?? '')
        .trim();
    _profileLastNameController.text = ((data['lastName'] as String?) ?? '')
        .trim();
    _profileEmailController.text =
        ((data['email'] as String?) ??
                FirebaseAuth.instance.currentUser?.email ??
                '')
            .trim();
  }

  Future<DocumentSnapshot<Map<String, dynamic>>> _fetchUserDocument() {
    final String? uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      return Future<DocumentSnapshot<Map<String, dynamic>>>.error(
        StateError('No logged-in user found.'),
      );
    }

    return FirebaseFirestore.instance.collection('users').doc(uid).get();
  }

  Future<void> _initializeDriverPermissions() async {
    final bool locationGranted = await _permissionService
        .ensureDriverLocationPermission(context);

    if (!mounted || !locationGranted) {
      if (mounted) {
        setState(() {
          _locationLabel = 'Location permission not granted';
        });
      }
      return;
    }

    await _loadCurrentLocation();
    _startLiveLocationUpdates();
  }

  void _onSearchChanged() {
    final String query = _searchController.text.trim().toLowerCase();
    if (query == _searchQuery) {
      return;
    }

    setState(() {
      _searchQuery = query;
    });
  }

  void _startLiveLocationUpdates() {
    _positionSubscription?.cancel();
    _positionSubscription =
        Geolocator.getPositionStream(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.best,
            distanceFilter: 8,
          ),
        ).listen((Position position) {
          if (!mounted) {
            return;
          }

          _setPosition(position);
        });
  }

  void _setPosition(Position position) {
    setState(() {
      _currentPosition = position;
    });
    final Position? last = _labelPosition;
    if (last == null ||
        Geolocator.distanceBetween(
              last.latitude,
              last.longitude,
              position.latitude,
              position.longitude,
            ) >
            300) {
      _labelPosition = position;
      unawaited(_updateLocationLabel(position));
    }
  }

  /// Shows a readable place (e.g. "Makati, Metro Manila") instead of raw
  /// coordinates, falling back to coordinates if lookup fails.
  Future<void> _updateLocationLabel(Position position) async {
    String label =
        '${position.latitude.toStringAsFixed(4)}, ${position.longitude.toStringAsFixed(4)}';
    try {
      final List<Placemark> places = await placemarkFromCoordinates(
        position.latitude,
        position.longitude,
      );
      if (places.isNotEmpty) {
        final Placemark place = places.first;
        final List<String> parts = <String>[
          (place.subLocality ?? '').trim(),
          (place.locality ?? '').trim(),
          (place.administrativeArea ?? '').trim(),
        ].where((String part) => part.isNotEmpty).toSet().take(2).toList();
        if (parts.isNotEmpty) {
          label = parts.join(', ');
        }
      }
    } catch (_) {
      // Keep the coordinate label.
    }
    if (mounted) {
      setState(() {
        _locationLabel = label;
      });
    }
  }

  Future<void> _refreshCurrentLocation() async {
    final bool locationGranted = await _permissionService
        .ensureDriverLocationPermission(context);
    if (!mounted || !locationGranted) {
      return;
    }

    await _loadCurrentLocation();
  }

  Future<void> _loadCurrentLocation({
    bool promptForServiceEnable = true,
  }) async {
    final bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      setState(() {
        _locationLabel = 'Location services are disabled';
      });

      if (promptForServiceEnable) {
        await _promptEnableLocationServices();
      }
      return;
    }

    Position position;
    try {
      position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _locationLabel = 'Unable to fetch current location';
      });
      return;
    }

    if (!mounted) {
      return;
    }

    _labelPosition = null;
    _setPosition(position);

    await _mapController?.animateCamera(
      CameraUpdate.newLatLng(LatLng(position.latitude, position.longitude)),
    );
  }

  Future<void> _promptEnableLocationServices() async {
    if (_locationServiceDialogOpen || !mounted) {
      return;
    }

    _locationServiceDialogOpen = true;
    final bool? openSettings = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          backgroundColor: AppTheme.background,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
          ),
          title: Text(
            'Enable Location Services',
            style: TextStyle(
              color: AppTheme.textDark,
              fontWeight: FontWeight.w700,
            ),
          ),
          content: Text(
            'SmartPark needs GPS enabled to discover nearby parking.',
            style: TextStyle(
              color: AppTheme.textMuted,
              fontWeight: FontWeight.w500,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(
                'Not Now',
                style: TextStyle(color: AppTheme.textMuted),
              ),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.accent,
                foregroundColor: AppTheme.onAccent,
              ),
              child: const Text('Open Settings'),
            ),
          ],
        );
      },
    );

    _locationServiceDialogOpen = false;

    if (openSettings != true) {
      return;
    }

    _awaitingLocationSettingsReturn = true;
    await Geolocator.openLocationSettings();
  }

  Future<void> _signOut() async {
    await FirebaseAuth.instance.signOut();
    if (!mounted) {
      return;
    }

    unawaited(
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute<void>(builder: (_) => const SignInScreen()),
        (route) => false,
      ),
    );
  }

  void _openEstablishmentDetails(String establishmentId) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            EstablishmentDetailPage(establishmentId: establishmentId),
      ),
    );
  }

  String _initials() {
    final String first = _profileFirstNameController.text.trim();
    final String last = _profileLastNameController.text.trim();
    final String initials =
        '${first.isEmpty ? '' : first[0]}${last.isEmpty ? '' : last[0]}';
    return initials.isEmpty ? 'D' : initials.toUpperCase();
  }

  PreferredSizeWidget _locationBar() {
    return PreferredSize(
      preferredSize: const Size.fromHeight(30),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
        child: Row(
          children: [
            Icon(Icons.place_rounded, size: 14, color: spEntryColor),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                _locationLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: AppTheme.textMuted,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBodyByIndex() {
    switch (_selectedIndex) {
      case 1:
        return const DriverTicketHistorySection();
      case 2:
        return SpProfileView(
          roleLabel: 'Driver',
          firstNameController: _profileFirstNameController,
          lastNameController: _profileLastNameController,
          email: _profileEmailController.text.isNotEmpty
              ? _profileEmailController.text
              : FirebaseAuth.instance.currentUser?.email ?? '',
          onSignOut: _signOut,
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        );
      case 0:
      default:
        return DriverHomeSection(
          currentPosition: _currentPosition,
          searchController: _searchController,
          searchQuery: _searchQuery,
          sortOption: _sortOption,
          openNowOnly: _openNowOnly,
          onSortChanged: (DriverSortOption value) {
            setState(() {
              _sortOption = value;
            });
          },
          onOpenNowChanged: (bool value) {
            setState(() {
              _openNowOnly = value;
            });
          },
          onMapCreated: (GoogleMapController controller) {
            _mapController = controller;
          },
          onEstablishmentTap: _openEstablishmentDetails,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      future: _userFuture,
      builder:
          (
            BuildContext context,
            AsyncSnapshot<DocumentSnapshot<Map<String, dynamic>>> snapshot,
          ) {
            final Map<String, dynamic>? data = snapshot.data?.data();
            _seedProfileControllers(data);

            return Scaffold(
              appBar: AppBar(
                backgroundColor: AppTheme.surface,
                elevation: 0,
                scrolledUnderElevation: 0,
                automaticallyImplyLeading: false,
                title: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.local_parking_rounded, color: AppTheme.textDark),
                    const SizedBox(width: 8),
                    Text(
                      'SmartPark',
                      style: TextStyle(
                        color: AppTheme.textDark,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                actions: [
                  if (_selectedIndex == 0)
                    IconButton(
                      onPressed: _refreshCurrentLocation,
                      icon: const Icon(Icons.my_location_rounded),
                      tooltip: 'Refresh location',
                    ),
                  SpAccountAvatarButton(
                    active: _selectedIndex == 2,
                    onTap: () => setState(() => _selectedIndex = 2),
                    child: Text(_initials()),
                  ),
                  const SizedBox(width: 12),
                ],
                // Drivers pick parking by distance, so the map tab keeps
                // showing where the app thinks they are.
                bottom: _selectedIndex == 0 ? _locationBar() : null,
              ),
              body: _buildBodyByIndex(),
              bottomNavigationBar: BottomNavigationBar(
                currentIndex: _selectedIndex,
                selectedItemColor: AppTheme.textDark,
                unselectedItemColor: AppTheme.textMuted,
                showSelectedLabels: true,
                showUnselectedLabels: true,
                type: BottomNavigationBarType.fixed,
                selectedLabelStyle: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
                unselectedLabelStyle: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
                onTap: (int index) {
                  setState(() {
                    _selectedIndex = index;
                  });
                },
                items: const [
                  BottomNavigationBarItem(
                    icon: Icon(Icons.home_outlined),
                    activeIcon: Icon(Icons.home_rounded),
                    label: 'Home',
                  ),
                  BottomNavigationBarItem(
                    icon: Icon(Icons.receipt_long_outlined),
                    activeIcon: Icon(Icons.receipt_long_rounded),
                    label: 'Tickets',
                  ),
                  BottomNavigationBarItem(
                    icon: Icon(Icons.person_outlined),
                    activeIcon: Icon(Icons.person_rounded),
                    label: 'Profile',
                  ),
                ],
              ),
            );
          },
    );
  }
}
