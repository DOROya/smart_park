import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../services/error_reporter.dart';
import '../../services/parking_push.dart';
import '../../services/permission_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/sp_announcements.dart';
import '../../services/app_shortcuts.dart';
import '../../services/last_ticket_store.dart';
import 'saved_ticket_page.dart';
import '../../widgets/smartpark_logo.dart';
import '../../widgets/smartpark_ui.dart';
import '../../widgets/sp_connection.dart';
import '../../widgets/sp_profile_view.dart';
import '../auth/sign_in_screen.dart';
import 'driver_guide_page.dart';
import 'driver_help_page.dart';
import 'driver_parking_pass_page.dart';
import 'establishment_detail_page.dart';
import 'services/driver_establishment_service.dart';
import 'widgets/add_hours_sheet.dart';
import 'widgets/driver_active_pass_bar.dart';
import 'widgets/driver_home_section.dart';
import 'widgets/driver_notification_settings_card.dart';
import 'widgets/driver_ticket_history_section.dart';
import 'widgets/driver_warning_watcher.dart';

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

  /// Pops up new warnings from the SmartPark admin once, when the app opens.
  AnnouncementWatcher? _announcements;
  DriverWarningWatcher? _warnings;

  /// The driver's usable temporary QRs, for the Home shortcut.
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _passesSub;
  List<ActivePass> _activePasses = <ActivePass>[];

  /// Gate payments already brought up ("checkoutId@startedAt"), so a QR the
  /// driver closed doesn't keep popping back for the same payment.
  final Set<String> _gatePaymentsShown = <String>{};

  @override
  void initState() {
    super.initState();
    final String? uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) _watchPasses(uid);
    WidgetsBinding.instance.addObserver(this);
    _searchController.addListener(_onSearchChanged);
    _userFuture = _fetchUserDocument();
    unawaited(_startUp(uid));
    // "Show my ticket" from the app icon.
    pendingShortcut.addListener(_onShortcut);
    WidgetsBinding.instance.addPostFrameCallback((_) => _onShortcut());
  }

  void _onShortcut() {
    if (!mounted || pendingShortcut.value != kShowTicketShortcut) return;
    pendingShortcut.value = null;
    unawaited(_openShortcutTicket());
  }

  /// Opens the ticket the shortcut is for (see [pickShortcutTicket]). With
  /// no signal, the copy saved on this phone.
  Future<void> _openShortcutTicket() async {
    final String? uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final NavigatorState navigator = Navigator.of(context);
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    ({String kind, String id, Map<String, dynamic> data})? pick;
    bool offline = false;
    try {
      final FirebaseFirestore db = FirebaseFirestore.instance;
      final List<QuerySnapshot<Map<String, dynamic>>> snaps = await Future.wait(
        <Future<QuerySnapshot<Map<String, dynamic>>>>[
          db.collection('transactions').where('driverId', isEqualTo: uid).get(),
          db
              .collection('parking_checkouts')
              .where('driverId', isEqualTo: uid)
              .where('kind', isEqualTo: 'gate_pass')
              .where('status', whereIn: <String>['awaiting_gate', 'pending'])
              .get(),
        ],
      ).timeout(const Duration(seconds: 6));
      offline = snaps.first.metadata.isFromCache;
      pick = pickShortcutTicket(
        tickets: <(String, Map<String, dynamic>)>[
          for (final QueryDocumentSnapshot<Map<String, dynamic>> d
              in snaps[0].docs)
            (d.id, d.data()),
        ],
        passes: <(String, Map<String, dynamic>)>[
          for (final QueryDocumentSnapshot<Map<String, dynamic>> d
              in snaps[1].docs)
            (d.id, d.data()),
        ],
        createdAt: (Map<String, dynamic> d) =>
            spParseDateTime(d['createdAt']) ??
            spParseDateTime(d['createdAtClient']),
      );
    } catch (_) {
      // No signal and nothing cached: the saved copy below.
      final SavedTicket? saved = await LastTicketStore.load();
      if (!mounted) return;
      if (saved != null) {
        unawaited(
          navigator.push<void>(
            MaterialPageRoute<void>(
              builder: (_) => SavedTicketPage(ticket: saved, offline: true),
            ),
          ),
        );
        return;
      }
    }
    if (!mounted) return;
    if (pick == null) {
      setState(() => _selectedIndex = 1);
      messenger.showSnackBar(
        const SnackBar(content: Text('No active ticket.')),
      );
      return;
    }
    // A temporary QR is paid at the gate, which needs its live page.
    if (pick.kind == 'pass' && !offline) {
      _openPass(pick.id);
      return;
    }
    final SavedTicket ticket = savedTicketFrom(pick.kind, pick.id, pick.data);
    unawaited(LastTicketStore.save(ticket));
    unawaited(
      navigator.push<void>(
        MaterialPageRoute<void>(
          builder: (_) => SavedTicketPage(ticket: ticket, offline: offline),
        ),
      ),
    );
  }

  /// First sign-in on this phone: the guide first, then the notification
  /// and location prompts and any warnings, so none open over the guide.
  Future<void> _startUp(String? uid) async {
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    await DriverGuide.showIfFirstRun(context);
    if (!mounted) return;
    if (uid != null) {
      _warnings = DriverWarningWatcher(() => context, uid)..start();
      _announcements = AnnouncementWatcher(
        () => context,
        'Driver',
        isCurrent: () => mounted && (ModalRoute.of(context)?.isCurrent ?? true),
      )..start();
      _registerPush(uid);
    }
    await _initializeDriverPermissions();
  }

  /// Parking reminders from the server; shown in-app while open.
  void _registerPush(String uid) {
    unawaited(
      ParkingPush.register(
        uid,
        onForeground: (String title, String body) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('$title\n$body'),
              duration: const Duration(seconds: 8),
            ),
          );
        },
        onOpen: (Map<String, dynamic> data) {
          if (data['kind'] == 'announcement') {
            unawaited(_announcements?.check());
            return;
          }
          final Object? id = data['checkoutId'];
          if ((data['kind'] == ParkingPush.kGateConfirm ||
                  data['kind'] == ParkingPush.kGateTurnedAway) &&
              id is String) {
            _openPass(id);
          }
          // "Time almost up" / "overtime started": buy more hours.
          final Object? ticketId = data['ticketId'];
          if ((data['kind'] == 'reminder' || data['kind'] == 'overtime') &&
              ticketId is String) {
            unawaited(_openAddHours(ticketId));
          }
        },
      ),
    );
  }

  void _openHelp() {
    unawaited(
      Navigator.of(context).push<void>(
        MaterialPageRoute<void>(builder: (_) => const DriverHelpPage()),
      ),
    );
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
    _warnings?.dispose();
    _announcements?.dispose();
    pendingShortcut.removeListener(_onShortcut);
    _passesSub?.cancel();
    _positionSubscription?.cancel();
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    _profileFirstNameController.dispose();
    _profileLastNameController.dispose();
    _profileEmailController.dispose();
    _mapController?.dispose();
    super.dispose();
  }

  /// Follows the driver's temporary QRs: keeps the Home shortcut current,
  /// and opens a QR by itself when staff start its payment, so the driver
  /// only has to tap Confirm.
  void _watchPasses(String uid) {
    _passesSub = FirebaseFirestore.instance
        .collection('parking_checkouts')
        .where('driverId', isEqualTo: uid)
        .where('kind', isEqualTo: 'gate_pass')
        .where('status', whereIn: <String>['awaiting_gate', 'pending'])
        .snapshots()
        .listen(
          (QuerySnapshot<Map<String, dynamic>> snap) {
            if (!mounted) return;
            final List<ActivePass> passes = usablePasses(
              snap.docs.map(
                (QueryDocumentSnapshot<Map<String, dynamic>> d) =>
                    (id: d.id, data: d.data()),
              ),
              DateTime.now(),
            );
            setState(() => _activePasses = passes);
            for (final ActivePass p in passes) {
              if (p.data['status'] != 'pending') continue;
              final Object? started = p.data['gatePaymentStartedAt'];
              final String key =
                  '${p.id}@${started is Timestamp ? started.millisecondsSinceEpoch : ''}';
              if (_gatePaymentsShown.add(key)) _openPass(p.id);
            }
          },
          onError: (Object error, StackTrace stack) =>
              reportError(error, stack, reason: 'Temporary QR watcher'),
        );
  }

  /// Tickets tab, then the Add hours sheet for [ticketId].
  Future<void> _openAddHours(String ticketId) async {
    if (!mounted) return;
    setState(() => _selectedIndex = 1);
    try {
      final DocumentSnapshot<Map<String, dynamic>> snap =
          await FirebaseFirestore.instance
              .collection('transactions')
              .doc(ticketId)
              .get();
      final Map<String, dynamic>? ticket = snap.data();
      if (!mounted || ticket == null || !canAddTicketHours(ticket)) return;
      await showAddHoursSheet(context, ticketId: ticketId, ticket: ticket);
    } catch (error, stack) {
      reportError(error, stack, reason: 'Open add hours');
    }
  }

  void _openPass(String checkoutId) {
    if (!mounted || DriverParkingPassPage.isOpen(checkoutId)) return;
    unawaited(
      Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => DriverParkingPassPage(checkoutId: checkoutId),
        ),
      ),
    );
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
        ).listen(
          (Position position) {
            if (!mounted) {
              return;
            }

            _setPosition(position);
          },
          // Location turned off (or permission taken back) while the map is
          // open: show it instead of crashing. Updates resume once it is on.
          onError: (Object error) {
            if (!mounted) {
              return;
            }
            setState(() {
              _locationLabel = error is LocationServiceDisabledException
                  ? 'Location services are disabled'
                  : 'Unable to fetch current location';
            });
          },
        );
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

    try {
      await _mapController?.animateCamera(
        CameraUpdate.newLatLng(LatLng(position.latitude, position.longitude)),
      );
    } catch (_) {
      // The map is gone (another tab is open); it starts on the driver's
      // position when shown again.
      _mapController = null;
    }
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
    if (!await spConfirmSignOut(context)) return;
    final String? uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) await ParkingPush.unregister(uid);
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
        return const SpPullToRefresh(child: DriverTicketHistorySection());
      case 2:
        return SpProfileView(
          roleLabel: 'Driver',
          extraCards: <Widget>[
            if (FirebaseAuth.instance.currentUser?.uid case final String uid)
              DriverNoticesCard(driverId: uid),
            const SpAnnouncementsCard(role: 'Driver'),
            if (FirebaseAuth.instance.currentUser?.uid case final String uid)
              DriverNotificationSettingsCard(driverId: uid),
            SpSectionCard(
              icon: Icons.help_outline_rounded,
              title: 'Help & FAQ',
              subtitle:
                  'How SmartPark works, answers to common questions, and '
                  'how to reach us.',
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _openHelp,
                  icon: const Icon(Icons.support_agent_rounded, size: 18),
                  label: const Text(
                    'Open Help & FAQ',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(44),
                  ),
                ),
              ),
            ),
          ],
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
          belowSearch: DriverActivePassBar(
            passes: _activePasses,
            onOpen: _openPass,
          ),
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
                    const SmartParkLogo(size: 28),
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
                  IconButton(
                    onPressed: _openHelp,
                    icon: const Icon(Icons.help_outline_rounded),
                    tooltip: 'Help & FAQ',
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
