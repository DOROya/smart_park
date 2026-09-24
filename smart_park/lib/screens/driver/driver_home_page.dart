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
import 'services/driver_establishment_service.dart';
import 'widgets/driver_home_section.dart';
import 'widgets/driver_profile_section.dart';
import 'widgets/driver_ticket_history_section.dart';
import 'establishment_detail_page.dart';
import '../auth/sign_in_screen.dart';

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
  bool _savingProfile = false;
  bool _updatingPassword = false;

  final TextEditingController _profileFirstNameController =
      TextEditingController();
  final TextEditingController _profileLastNameController =
      TextEditingController();
  final TextEditingController _profileEmailController = TextEditingController();
  final TextEditingController _newPasswordController = TextEditingController();
  final TextEditingController _confirmPasswordController =
      TextEditingController();

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
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    _mapController?.dispose();
    super.dispose();
  }

  void _showSnackBar(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  void _seedProfileControllers(Map<String, dynamic>? data) {
    if (_profileSeeded) {
      return;
    }

    _profileSeeded = true;
    _profileFirstNameController.text = ((data?['firstName'] as String?) ?? '')
        .trim();
    _profileLastNameController.text = ((data?['lastName'] as String?) ?? '')
        .trim();
    _profileEmailController.text =
        ((data?['email'] as String?) ??
                FirebaseAuth.instance.currentUser?.email ??
                '')
            .trim();
  }

  Future<void> _saveProfile() async {
    if (_savingProfile) {
      return;
    }

    final String? uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      _showSnackBar('No logged-in user found.');
      return;
    }

    final String firstName = _profileFirstNameController.text.trim();
    final String lastName = _profileLastNameController.text.trim();
    final String email = _profileEmailController.text.trim();

    if (firstName.isEmpty || lastName.isEmpty || email.isEmpty) {
      _showSnackBar('Please complete profile fields.');
      return;
    }

    setState(() {
      _savingProfile = true;
    });

    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .update(<String, dynamic>{
            'firstName': firstName,
            'lastName': lastName,
            'email': email,
            'updatedAt': FieldValue.serverTimestamp(),
          });
      _showSnackBar('Profile updated.');
    } finally {
      if (mounted) {
        setState(() {
          _savingProfile = false;
        });
      }
    }
  }

  Future<void> _changePassword() async {
    if (_updatingPassword) {
      return;
    }

    final User? user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _showSnackBar('No logged-in user found.');
      return;
    }

    final String newPassword = _newPasswordController.text.trim();
    final String confirmPassword = _confirmPasswordController.text.trim();

    if (newPassword.length < 6) {
      _showSnackBar('Password must be at least 6 characters.');
      return;
    }

    if (newPassword != confirmPassword) {
      _showSnackBar('Password confirmation does not match.');
      return;
    }

    setState(() {
      _updatingPassword = true;
    });

    try {
      await user.updatePassword(newPassword);
      _newPasswordController.clear();
      _confirmPasswordController.clear();
      _showSnackBar('Password updated successfully.');
    } on FirebaseAuthException catch (error) {
      if (error.code == 'requires-recent-login') {
        _showSnackBar(
          'For security, please sign out and sign in again before changing password.',
        );
      } else {
        _showSnackBar(error.message ?? 'Failed to update password.');
      }
    } finally {
      if (mounted) {
        setState(() {
          _updatingPassword = false;
        });
      }
    }
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
            borderRadius: BorderRadius.circular(18),
          ),
          title: const Text(
            'Enable Location Services',
            style: TextStyle(
              color: AppTheme.textDark,
              fontWeight: FontWeight.w700,
            ),
          ),
          content: const Text(
            'SmartPark needs GPS enabled to discover nearby parking.',
            style: TextStyle(
              color: AppTheme.textMuted,
              fontWeight: FontWeight.w500,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text(
                'Not Now',
                style: TextStyle(color: Color(0xFF6E7483)),
              ),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.accent,
                foregroundColor: const Color(0xFF22252C),
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

  Widget _buildBodyByIndex() {
    switch (_selectedIndex) {
      case 1:
        return const DriverTicketHistorySection();
      case 2:
        return DriverProfileSection(
          profileFirstNameController: _profileFirstNameController,
          profileLastNameController: _profileLastNameController,
          profileEmailController: _profileEmailController,
          newPasswordController: _newPasswordController,
          confirmPasswordController: _confirmPasswordController,
          savingProfile: _savingProfile,
          updatingPassword: _updatingPassword,
          onSaveProfile: _saveProfile,
          onChangePassword: _changePassword,
          onSignOut: _signOut,
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
            final String firstName = ((data?['firstName'] as String?) ?? '')
                .trim();
            final String greeting = spGreeting(DateTime.now());

            _seedProfileControllers(data);

            return Scaffold(
              appBar: AppBar(
                elevation: 0,
                scrolledUnderElevation: 0,
                backgroundColor: Colors.white,
                titleSpacing: 16,
                automaticallyImplyLeading: false,
                actions: [
                  IconButton(
                    onPressed: _refreshCurrentLocation,
                    icon: const Icon(Icons.my_location_rounded),
                    tooltip: 'Refresh location',
                  ),
                ],
                title: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      firstName.isEmpty ? greeting : '$greeting, $firstName',
                      style: const TextStyle(
                        color: AppTheme.textDark,
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        const Icon(
                          Icons.place_rounded,
                          size: 14,
                          color: spEntryColor,
                        ),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            _locationLabel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AppTheme.textMuted,
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              body: _buildBodyByIndex(),
              bottomNavigationBar: BottomNavigationBar(
                currentIndex: _selectedIndex,
                selectedItemColor: const Color(0xFF22252C),
                unselectedItemColor: const Color(0xFF6C727F),
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
