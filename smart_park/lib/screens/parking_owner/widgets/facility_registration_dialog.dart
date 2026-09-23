import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:image_picker/image_picker.dart';

import '../../../models/facility_registration_data.dart';
import '../../../services/parking_storage_service.dart';
import '../../../theme/app_theme.dart';

class FacilityRegistrationPage extends StatefulWidget {
  const FacilityRegistrationPage({super.key, this.facilityData});

  final Map<String, dynamic>? facilityData;

  @override
  State<FacilityRegistrationPage> createState() =>
      _FacilityRegistrationPageState();
}

class _FacilityRegistrationPageState extends State<FacilityRegistrationPage> {
  static const LatLng _fallbackCenter = LatLng(14.5995, 120.9842);

  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _addressController = TextEditingController();
  final TextEditingController _hoursController = TextEditingController();
  final TextEditingController _policiesController = TextEditingController();

  final TextEditingController _rateCarInitialController = TextEditingController();
  final TextEditingController _rateCarSucceedingHourController = TextEditingController();
  final TextEditingController _rateCarSucceedingDailyController = TextEditingController();
  final TextEditingController _rateCarWeeklyController = TextEditingController();
  final TextEditingController _rateCarMonthlyController = TextEditingController();

  final TextEditingController _rateMotorInitialController = TextEditingController();
  final TextEditingController _rateMotorSucceedingHourController = TextEditingController();
  final TextEditingController _rateMotorSucceedingDailyController = TextEditingController();
  final TextEditingController _rateMotorWeeklyController = TextEditingController();
  final TextEditingController _rateMotorMonthlyController = TextEditingController();

  final TextEditingController _slotCarController = TextEditingController();
  final TextEditingController _slotMotorController = TextEditingController();

  bool _allowLongTermRates = false;

  GoogleMapController? _mapController;
  LatLng _cameraCenter = _fallbackCenter;
  LatLng? _selectedLocation;
  bool _fetchingLocation = true;
  bool _saving = false;
  String _mapHint = 'Fetching your current location...';

  final ImagePicker _imagePicker = ImagePicker();
  final List<String> _existingPhotoUrls = <String>[];
  final List<String> _removedPhotoUrls = <String>[];
  final List<File> _newPhotoFiles = <File>[];

  int get _totalPhotoCount => _existingPhotoUrls.length + _newPhotoFiles.length;

  @override
  void initState() {
    super.initState();
    _seedFromExistingData();
    _initializeMapCenter();
  }

  @override
  void dispose() {
    _mapController?.dispose();
    _nameController.dispose();
    _addressController.dispose();
    _hoursController.dispose();
    _policiesController.dispose();

    _rateCarInitialController.dispose();
    _rateCarSucceedingHourController.dispose();
    _rateCarSucceedingDailyController.dispose();
    _rateCarWeeklyController.dispose();
    _rateCarMonthlyController.dispose();

    _rateMotorInitialController.dispose();
    _rateMotorSucceedingHourController.dispose();
    _rateMotorSucceedingDailyController.dispose();
    _rateMotorWeeklyController.dispose();
    _rateMotorMonthlyController.dispose();

    _slotCarController.dispose();
    _slotMotorController.dispose();
    super.dispose();
  }

  void _seedFromExistingData() {
    final Map<String, dynamic> data =
        widget.facilityData ?? <String, dynamic>{};

    _nameController.text = (data['name'] as String?)?.trim() ?? '';
    _addressController.text = (data['address'] as String?)?.trim() ?? '';
    _hoursController.text = (data['operatingHours'] as String?)?.trim() ?? '';
    _policiesController.text = (data['policies'] as String?)?.trim() ?? '';

    _allowLongTermRates = (data['allowLongTermRates'] as bool?) ?? false;

    final Map<String, dynamic> rates =
        (data['rates'] as Map<String, dynamic>?) ??
        (data['ratesByType'] as Map<String, dynamic>?) ??
        <String, dynamic>{};

    void seedVehicleRates(
      dynamic val,
      TextEditingController initCtrl,
      TextEditingController succHCtrl,
      TextEditingController succDCtrl,
      TextEditingController weeklyCtrl,
      TextEditingController monthlyCtrl,
    ) {
      if (val is Map) {
        initCtrl.text =
            (val['initial'] ?? val['hourly'] ?? val['rates'] ?? '').toString().trim();
        succHCtrl.text =
            (val['succeedingHour'] ?? val['succeeding_hour'] ?? '').toString().trim();
        succDCtrl.text =
            (val['succeedingDaily'] ?? val['succeeding_daily'] ?? val['daily'] ?? '')
                .toString()
                .trim();
        weeklyCtrl.text = (val['weekly'] ?? '').toString().trim();
        monthlyCtrl.text = (val['monthly'] ?? '').toString().trim();

        if (weeklyCtrl.text.isNotEmpty || monthlyCtrl.text.isNotEmpty) {
          _allowLongTermRates = true;
        }
      } else if (val != null) {
        initCtrl.text = val.toString().trim();
      }
    }

    seedVehicleRates(
      rates['car'],
      _rateCarInitialController,
      _rateCarSucceedingHourController,
      _rateCarSucceedingDailyController,
      _rateCarWeeklyController,
      _rateCarMonthlyController,
    );
    seedVehicleRates(
      rates['motorcycle'],
      _rateMotorInitialController,
      _rateMotorSucceedingHourController,
      _rateMotorSucceedingDailyController,
      _rateMotorWeeklyController,
      _rateMotorMonthlyController,
    );

    final Map<String, dynamic> slots =
      (data['slotCounts'] as Map<String, dynamic>?) ??
      (data['slots'] as Map<String, dynamic>?) ??
      <String, dynamic>{};
    _slotCarController.text = ((slots['car'] as num?) ?? 0).toString();
    _slotMotorController.text = ((slots['motorcycle'] as num?) ?? 0).toString();

    final GeoPoint? point = data['location'] as GeoPoint?;
    final num? legacyLat = data['latitude'] as num?;
    final num? legacyLng = data['longitude'] as num?;

    final double? latitude = point?.latitude ?? legacyLat?.toDouble();
    final double? longitude = point?.longitude ?? legacyLng?.toDouble();
    if (latitude != null && longitude != null) {
      _selectedLocation = LatLng(latitude, longitude);
      _cameraCenter = _selectedLocation!;
      _mapHint = 'Tap map to adjust your facility pin.';
    }

    final List<dynamic> photoUrls = (data['photoUrls'] as List<dynamic>?) ?? <dynamic>[];
    _existingPhotoUrls
      ..clear()
      ..addAll(photoUrls.whereType<String>());
  }

  Future<void> _initializeMapCenter() async {
    final bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (!mounted) {
        return;
      }
      setState(() {
        _fetchingLocation = false;
        _mapHint = 'Location service is disabled. Use map manually.';
      });
      return;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      if (!mounted) {
        return;
      }
      setState(() {
        _fetchingLocation = false;
        _mapHint = 'Location permission denied. Use map manually.';
      });
      return;
    }

    try {
      final Position position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );

      if (!mounted) {
        return;
      }

      final LatLng current = LatLng(position.latitude, position.longitude);
      setState(() {
        _cameraCenter = current;
        _fetchingLocation = false;
        _mapHint = _selectedLocation == null
            ? 'Tap on map to pin your facility location.'
            : _mapHint;
      });

      await _mapController?.animateCamera(CameraUpdate.newLatLng(current));
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _fetchingLocation = false;
        _mapHint = 'Unable to fetch your location. Use map manually.';
      });
    }
  }

  Future<void> _reverseGeocodePin() async {
    if (_selectedLocation == null) {
      _showSnackBar('Pin your facility on the map first.');
      return;
    }

    try {
      final List<Placemark> places = await placemarkFromCoordinates(
        _selectedLocation!.latitude,
        _selectedLocation!.longitude,
      );
      if (places.isEmpty) {
        _showSnackBar('No address found for selected location.');
        return;
      }

      final Placemark place = places.first;
      final List<String> segments = <String>[
        place.street ?? '',
        place.subLocality ?? '',
        place.locality ?? '',
        place.administrativeArea ?? '',
        place.postalCode ?? '',
        place.country ?? '',
      ].where((String part) => part.trim().isNotEmpty).toList();

      if (segments.isEmpty) {
        _showSnackBar('No usable address details found.');
        return;
      }

      _addressController.text = segments.join(', ');
      _showSnackBar('Address updated from pinned location.');
    } catch (_) {
      _showSnackBar(
        'Reverse geocoding failed. You can enter address manually.',
      );
    }
  }

  void _showSnackBar(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  String? _requiredValidator(String? value, String label) {
    if (value == null || value.trim().isEmpty) {
      return 'Please provide $label';
    }
    return null;
  }

  String? _slotValidator(String? value, String label) {
    final String text = value?.trim() ?? '';
    if (text.isEmpty) {
      return 'Please provide $label';
    }
    final int? parsed = int.tryParse(text);
    if (parsed == null || parsed < 0) {
      return '$label should be a non-negative number';
    }
    return null;
  }

  Future<void> _pickPhoto() async {
    if (_totalPhotoCount >= ParkingStorageService.maxPhotosPerEstablishment) {
      _showSnackBar('You can only add up to 3 facility photos.');
      return;
    }

    final XFile? picked = await _imagePicker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 80,
    );
    if (picked == null) {
      return;
    }

    setState(() {
      _newPhotoFiles.add(File(picked.path));
    });
  }

  void _removeExistingPhoto(String url) {
    setState(() {
      _existingPhotoUrls.remove(url);
      _removedPhotoUrls.add(url);
    });
  }

  void _removeNewPhoto(File file) {
    setState(() {
      _newPhotoFiles.remove(file);
    });
  }

  void _handleSave() {
    if (_saving) {
      return;
    }

    if (!_formKey.currentState!.validate()) {
      return;
    }

    if (_selectedLocation == null) {
      _showSnackBar('Tap on the map to pin your facility location.');
      return;
    }

    if (_totalPhotoCount < 1) {
      _showSnackBar('Add at least 1 facility photo.');
      return;
    }

    if (_totalPhotoCount > ParkingStorageService.maxPhotosPerEstablishment) {
      _showSnackBar('You can only add up to 3 facility photos.');
      return;
    }

    setState(() {
      _saving = true;
    });

    Map<String, dynamic> buildVehicleRateMap(
      TextEditingController initCtrl,
      TextEditingController succHCtrl,
      TextEditingController succDCtrl,
      TextEditingController weeklyCtrl,
      TextEditingController monthlyCtrl,
    ) {
      final Map<String, dynamic> map = <String, dynamic>{
        'initial': initCtrl.text.trim(),
        'succeedingHour': succHCtrl.text.trim(),
        'succeedingDaily': succDCtrl.text.trim(),
      };
      if (_allowLongTermRates) {
        if (weeklyCtrl.text.trim().isNotEmpty) {
          map['weekly'] = weeklyCtrl.text.trim();
        }
        if (monthlyCtrl.text.trim().isNotEmpty) {
          map['monthly'] = monthlyCtrl.text.trim();
        }
      }
      return map;
    }

    final FacilityRegistrationData data = FacilityRegistrationData(
      name: _nameController.text.trim(),
      address: _addressController.text.trim(),
      operatingHours: _hoursController.text.trim(),
      policies: _policiesController.text.trim(),
      rates: <String, dynamic>{
        'car': buildVehicleRateMap(
          _rateCarInitialController,
          _rateCarSucceedingHourController,
          _rateCarSucceedingDailyController,
          _rateCarWeeklyController,
          _rateCarMonthlyController,
        ),
        'motorcycle': buildVehicleRateMap(
          _rateMotorInitialController,
          _rateMotorSucceedingHourController,
          _rateMotorSucceedingDailyController,
          _rateMotorWeeklyController,
          _rateMotorMonthlyController,
        ),
      },
      slots: <String, int>{
        'car': int.parse(_slotCarController.text.trim()),
        'motorcycle': int.parse(_slotMotorController.text.trim()),
      },
      location: _selectedLocation!,
      keepPhotoUrls: List<String>.from(_existingPhotoUrls),
      newPhotoFiles: List<File>.from(_newPhotoFiles),
      removedPhotoUrls: List<String>.from(_removedPhotoUrls),
    );

    Navigator.of(context).pop(data);
  }

  Widget _sectionCard({
    required String title,
    required String subtitle,
    required Widget child,
    IconData icon = Icons.layers_rounded,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE4E7EF)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x12000000),
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF4CF),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: const Color(0xFF2F3544), size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: AppTheme.textDark,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: Color(0xFF737A88),
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }

  Widget _doubleFields({
    required Widget first,
    required Widget second,
  }) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        if (constraints.maxWidth < 680) {
          return Column(
            children: [
              first,
              const SizedBox(height: 8),
              second,
            ],
          );
        }

        return Row(
          children: [
            Expanded(child: first),
            const SizedBox(width: 8),
            Expanded(child: second),
          ],
        );
      },
    );
  }

  Widget _tripleFields({
    required Widget first,
    required Widget second,
    required Widget third,
  }) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        if (constraints.maxWidth < 680) {
          return Column(
            children: [
              first,
              const SizedBox(height: 8),
              second,
              const SizedBox(height: 8),
              third,
            ],
          );
        }

        return Row(
          children: [
            Expanded(child: first),
            const SizedBox(width: 8),
            Expanded(child: second),
            const SizedBox(width: 8),
            Expanded(child: third),
          ],
        );
      },
    );
  }

  Widget _buildInputField({
    required String label,
    required String hint,
    required TextEditingController controller,
    TextInputType keyboardType = TextInputType.text,
    int maxLines = 1,
    String? Function(String?)? validator,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: AppTheme.textDark,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: controller,
          keyboardType: keyboardType,
          maxLines: maxLines,
          validator:
              validator ?? (String? value) => _requiredValidator(value, label),
          decoration: InputDecoration(
            hintText: hint,
            filled: true,
            fillColor: const Color(0xFFF8F9FC),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 12,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFFE4E7EF)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFFE4E7EF)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppTheme.accent, width: 1.4),
            ),
            hintStyle: const TextStyle(
              color: Color(0xFF9AA0AE),
              fontSize: 12,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMapCard() {
    final Set<Marker> markers = _selectedLocation == null
        ? <Marker>{}
        : <Marker>{
            Marker(
              markerId: const MarkerId('facility_pin'),
              position: _selectedLocation!,
              infoWindow: const InfoWindow(title: 'Facility Location'),
            ),
          };

    return _sectionCard(
      title: 'Facility Pin',
      subtitle: 'Drop a pin to map your exact parking location.',
      icon: Icons.location_on_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFFF8F9FC),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE4E7EF)),
            ),
            child: Text(
              _mapHint,
              style: const TextStyle(
                color: Color(0xFF596173),
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 240,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: GoogleMap(
                initialCameraPosition: CameraPosition(
                  target: _cameraCenter,
                  zoom: 15,
                ),
                myLocationEnabled: true,
                myLocationButtonEnabled: true,
                zoomControlsEnabled: false,
                markers: markers,
                onMapCreated: (GoogleMapController controller) {
                  _mapController = controller;
                },
                onTap: (LatLng point) {
                  setState(() {
                    _selectedLocation = point;
                    _mapHint =
                        'Pinned at ${point.latitude.toStringAsFixed(6)}, '
                        '${point.longitude.toStringAsFixed(6)}';
                  });
                },
              ),
            ),
          ),
          if (_selectedLocation != null) ...[
            const SizedBox(height: 8),
            Text(
              'Lat: ${_selectedLocation!.latitude.toStringAsFixed(6)}, '
              'Lng: ${_selectedLocation!.longitude.toStringAsFixed(6)}',
              style: const TextStyle(
                color: Color(0xFF596173),
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: _fetchingLocation ? null : _initializeMapCenter,
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF2F3544),
                  side: const BorderSide(color: Color(0xFFDDE1EA)),
                ),
                icon: const Icon(Icons.my_location_rounded),
                label: const Text('Use My Location'),
              ),
              OutlinedButton.icon(
                onPressed: _reverseGeocodePin,
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF2F3544),
                  side: const BorderSide(color: Color(0xFFDDE1EA)),
                ),
                icon: const Icon(Icons.place_rounded),
                label: const Text('Use Pin Address'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPhotoThumbnail({
    required Widget image,
    required VoidCallback onRemove,
  }) {
    return Stack(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: SizedBox(width: 92, height: 92, child: image),
        ),
        Positioned(
          top: 4,
          right: 4,
          child: GestureDetector(
            onTap: onRemove,
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: const BoxDecoration(
                color: Color(0xCC1F2532),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.close_rounded,
                color: Colors.white,
                size: 14,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPhotosSection() {
    final bool canAddMore =
        _totalPhotoCount < ParkingStorageService.maxPhotosPerEstablishment;

    return _sectionCard(
      title: 'Facility Photos',
      subtitle: 'Add 1 to 3 photos so drivers can recognize your place.',
      icon: Icons.photo_library_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final String url in _existingPhotoUrls)
                _buildPhotoThumbnail(
                  image: Image.network(url, fit: BoxFit.cover),
                  onRemove: () => _removeExistingPhoto(url),
                ),
              for (final File file in _newPhotoFiles)
                _buildPhotoThumbnail(
                  image: Image.file(file, fit: BoxFit.cover),
                  onRemove: () => _removeNewPhoto(file),
                ),
              if (canAddMore)
                InkWell(
                  onTap: _pickPhoto,
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    width: 92,
                    height: 92,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8F9FC),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFE4E7EF)),
                    ),
                    child: const Icon(
                      Icons.add_a_photo_rounded,
                      color: Color(0xFF737A88),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '$_totalPhotoCount / ${ParkingStorageService.maxPhotosPerEstablishment} photos added',
            style: const TextStyle(
              color: Color(0xFF737A88),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVehicleRateGroup({
    required String title,
    required IconData icon,
    required TextEditingController initialCtrl,
    required TextEditingController succHCtrl,
    required TextEditingController succDCtrl,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 16, color: AppTheme.textDark),
            const SizedBox(width: 6),
            Text(
              title,
              style: const TextStyle(
                color: AppTheme.textDark,
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        _tripleFields(
          first: _buildInputField(
            label: 'Base Rate (₱)',
            hint: 'e.g. 50',
            controller: initialCtrl,
            keyboardType: TextInputType.number,
          ),
          second: _buildInputField(
            label: 'Succeeding /hr (₱)',
            hint: 'e.g. 20',
            controller: succHCtrl,
            keyboardType: TextInputType.number,
          ),
          third: _buildInputField(
            label: 'Daily Rate (₱)',
            hint: 'e.g. 250',
            controller: succDCtrl,
            keyboardType: TextInputType.number,
          ),
        ),
      ],
    );
  }

  Widget _buildRatesAndSlots() {
    return _sectionCard(
      title: 'Rates and Capacity',
      subtitle: 'Define base rates, succeeding rates, and available slots.',
      icon: Icons.payments_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildVehicleRateGroup(
            title: 'Car Rates',
            icon: Icons.directions_car_rounded,
            initialCtrl: _rateCarInitialController,
            succHCtrl: _rateCarSucceedingHourController,
            succDCtrl: _rateCarSucceedingDailyController,
          ),
          const SizedBox(height: 14),
          _buildVehicleRateGroup(
            title: 'Motorcycle Rates',
            icon: Icons.two_wheeler_rounded,
            initialCtrl: _rateMotorInitialController,
            succHCtrl: _rateMotorSucceedingHourController,
            succDCtrl: _rateMotorSucceedingDailyController,
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFFF8F9FC),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE4E7EF)),
            ),
            child: SwitchListTile(
              contentPadding: EdgeInsets.zero,
              activeColor: AppTheme.accent,
              title: const Text(
                'Allow Long-Term Parking (Weekly & Monthly)',
                style: TextStyle(
                  color: AppTheme.textDark,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
              subtitle: const Text(
                'By default, only hourly & daily rates are enabled.',
                style: TextStyle(
                  color: AppTheme.textMuted,
                  fontSize: 11,
                ),
              ),
              value: _allowLongTermRates,
              onChanged: (bool val) {
                setState(() {
                  _allowLongTermRates = val;
                });
              },
            ),
          ),
          if (_allowLongTermRates) ...[
            const SizedBox(height: 12),
            _doubleFields(
              first: _buildInputField(
                label: 'Car Weekly Rate (₱)',
                hint: 'e.g. 1200',
                controller: _rateCarWeeklyController,
                keyboardType: TextInputType.number,
              ),
              second: _buildInputField(
                label: 'Car Monthly Rate (₱)',
                hint: 'e.g. 4000',
                controller: _rateCarMonthlyController,
                keyboardType: TextInputType.number,
              ),
            ),
            const SizedBox(height: 10),
            _doubleFields(
              first: _buildInputField(
                label: 'Motorcycle Weekly Rate (₱)',
                hint: 'e.g. 500',
                controller: _rateMotorWeeklyController,
                keyboardType: TextInputType.number,
              ),
              second: _buildInputField(
                label: 'Motorcycle Monthly Rate (₱)',
                hint: 'e.g. 1800',
                controller: _rateMotorMonthlyController,
                keyboardType: TextInputType.number,
              ),
            ),
          ],
          const SizedBox(height: 16),
          const Divider(color: Color(0xFFE4E7EF)),
          const SizedBox(height: 12),
          const Text(
            'Slot Counts (Car / Motorcycle)',
            style: TextStyle(
              color: AppTheme.textDark,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          _doubleFields(
            first: _buildInputField(
              label: 'Car Slots',
              hint: '0',
              controller: _slotCarController,
              keyboardType: TextInputType.number,
              validator: (String? value) =>
                  _slotValidator(value, 'Car slot count'),
            ),
            second: _buildInputField(
              label: 'Motorcycle Slots',
              hint: '0',
              controller: _slotMotorController,
              keyboardType: TextInputType.number,
              validator: (String? value) =>
                  _slotValidator(value, 'Motorcycle slot count'),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final String pageTitle = widget.facilityData == null
        ? 'Register Facility'
        : 'Update Facility';

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0,
        title: Text(
          pageTitle,
          style: const TextStyle(
            color: AppTheme.textDark,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: <Color>[Color(0xFFFFEAA8), Color(0xFFF7C846)],
                        ),
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x22000000),
                            blurRadius: 10,
                            offset: Offset(0, 5),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              color: const Color(0x35FFFFFF),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: const Icon(
                              Icons.storefront_rounded,
                              color: Color(0xFF2F3544),
                              size: 26,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              pageTitle,
                              style: const TextStyle(
                                color: Color(0xFF1F2532),
                                fontSize: 20,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Complete the establishment details and pin its location on the map.',
                      style: TextStyle(color: AppTheme.textMuted),
                    ),
                    const SizedBox(height: 16),
                    _sectionCard(
                      title: 'Basic Information',
                      subtitle: 'Set your establishment identity and operating window.',
                      icon: Icons.badge_rounded,
                      child: Column(
                        children: [
                          _buildInputField(
                            label: 'Establishment Name',
                            hint: 'Enter establishment name',
                            controller: _nameController,
                          ),
                          const SizedBox(height: 10),
                          _buildInputField(
                            label: 'Address',
                            hint: 'Enter complete address',
                            controller: _addressController,
                          ),
                          const SizedBox(height: 10),
                          _buildInputField(
                            label: 'Operating Hours',
                            hint: 'e.g. 6:00 AM - 10:00 PM',
                            controller: _hoursController,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    _buildPhotosSection(),
                    const SizedBox(height: 10),
                    _buildMapCard(),
                    const SizedBox(height: 10),
                    _buildRatesAndSlots(),
                    const SizedBox(height: 10),
                    _sectionCard(
                      title: 'Policies',
                      subtitle: 'State parking rules and reminders for customers.',
                      icon: Icons.rule_rounded,
                      child: _buildInputField(
                        label: 'Policies',
                        hint: 'Enter facility policies',
                        controller: _policiesController,
                        maxLines: 3,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: _saving ? null : () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton(
                onPressed: _saving ? null : _handleSave,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.accent,
                  foregroundColor: const Color(0xFF22252C),
                ),
                child: Text(_saving ? 'Saving...' : 'Save'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
