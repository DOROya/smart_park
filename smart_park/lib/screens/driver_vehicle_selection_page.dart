import 'package:flutter/material.dart';

import 'driver_checkout_payment_page.dart';
import 'driver_package_selection_page.dart';
import 'driver_payment_page.dart';
import '../theme/app_theme.dart';

class DriverVehicleOption {
  const DriverVehicleOption({
    required this.key,
    required this.label,
    required this.icon,
    required this.activeCount,
    required this.capacity,
    required this.rate,
  });

  final String key;
  final String label;
  final IconData icon;
  final int activeCount;
  final int capacity;
  final String rate;
}

class DriverVehicleSelection {
  const DriverVehicleSelection({
    required this.vehicleType,
    required this.plateNumber,
    required this.plan,
    required this.duration,
    required this.amount,
    required this.paymentMethod,
  });

  final String vehicleType;
  final String plateNumber;
  final String plan;
  final int duration;
  final double amount;
  final DriverPaymentMethod paymentMethod;
}

class DriverVehicleSelectionPage extends StatefulWidget {
  const DriverVehicleSelectionPage({
    super.key,
    required this.establishmentName,
    required this.vehicleOptions,
    required this.ratesByType,
    required this.packageRates,
    required this.isPayMongoConfigured,
    this.onProcessPayment,
  });

  final String establishmentName;
  final List<DriverVehicleOption> vehicleOptions;
  final Map<String, dynamic> ratesByType;
  final Map<String, dynamic> packageRates;
  final bool isPayMongoConfigured;
  final Future<bool> Function({
    required String vehicleType,
    required String plateNumber,
    required String plan,
    required int duration,
    required double amount,
    required DriverPaymentMethod paymentMethod,
  })? onProcessPayment;

  @override
  State<DriverVehicleSelectionPage> createState() =>
      _DriverVehicleSelectionPageState();
}

class _DriverVehicleSelectionPageState
    extends State<DriverVehicleSelectionPage> {
  late String _selectedVehicleType;
  final TextEditingController _plateNumberController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _selectedVehicleType = widget.vehicleOptions.first.key;
  }

  @override
  void dispose() {
    _plateNumberController.dispose();
    super.dispose();
  }

  double _parseAmount(dynamic value) {
    if (value is num) {
      return value.toDouble();
    }
    final String text = (value as String?)?.trim() ?? '';
    final Match? match = RegExp(r'([0-9]+(?:\.[0-9]+)?)').firstMatch(text);
    return double.tryParse(match?.group(1) ?? '') ?? 0;
  }

  Future<void> _continue() async {
    final String plateNumber = _plateNumberController.text.trim();
    if (plateNumber.isEmpty) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Plate number is required. Please enter your plate number.'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    final dynamic vehicleRate = widget.ratesByType[_selectedVehicleType];
    final Map<String, dynamic> rateMap = vehicleRate is Map
        ? vehicleRate.map<String, dynamic>(
            (dynamic k, dynamic v) => MapEntry(k.toString(), v),
          )
        : <String, dynamic>{};

    final double initial = _parseAmount(
        rateMap['initial'] ?? rateMap['hourly'] ?? rateMap['rates'] ?? vehicleRate);
    final double succHour = _parseAmount(
        rateMap['succeedingHour'] ?? rateMap['succeeding_hour']);
    final double succDaily = _parseAmount(
        rateMap['succeedingDaily'] ?? rateMap['succeeding_daily'] ?? rateMap['daily']);

    final List<DriverPackageOption> options = <DriverPackageOption>[];

    if (initial > 0) {
      options.add(
        DriverPackageOption(
          key: 'base',
          label: 'Base Package',
          icon: Icons.timer_outlined,
          initialAmount: initial,
        ),
      );
    }

    if (initial > 0 && succHour > 0) {
      options.add(
        DriverPackageOption(
          key: 'extended',
          label: 'Extended Stay',
          icon: Icons.more_time_outlined,
          initialAmount: initial,
          succeedingHourAmount: succHour,
        ),
      );
    }

    if (succDaily > 0) {
      options.add(
        DriverPackageOption(
          key: 'daily',
          label: 'Daily Package',
          icon: Icons.calendar_today_outlined,
          initialAmount: 0,
          dailyAmount: succDaily,
        ),
      );
    }

    if (options.isEmpty) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No parking packages are configured for this vehicle type.'),
        ),
      );
      return;
    }

    final DriverVehicleOption vehicle = widget.vehicleOptions.firstWhere(
      (DriverVehicleOption option) => option.key == _selectedVehicleType,
    );
    final DriverPackageSelection? packageSelection = await Navigator.of(context)
        .push<DriverPackageSelection>(
          MaterialPageRoute<DriverPackageSelection>(
            builder: (_) => DriverPackageSelectionPage(
              establishmentName: widget.establishmentName,
              vehicleLabel: vehicle.label,
              options: options,
            ),
          ),
        );

    if (packageSelection == null || !mounted) {
      return;
    }

    final dynamic paymentResult = await Navigator.of(context).push(
      MaterialPageRoute<dynamic>(
        builder: (_) => DriverCheckoutPaymentPage(
          establishmentName: widget.establishmentName,
          vehicleLabel: vehicle.label,
          plan: packageSelection.displayPlanLabel,
          duration: packageSelection.duration,
          amount: packageSelection.totalAmount,
          isPayMongoConfigured: widget.isPayMongoConfigured,
          onProcessPayment: widget.onProcessPayment != null
              ? (DriverPaymentMethod method) {
                  return widget.onProcessPayment!(
                    vehicleType: _selectedVehicleType,
                    plateNumber: plateNumber,
                    plan: packageSelection.plan,
                    duration: packageSelection.duration,
                    amount: packageSelection.totalAmount,
                    paymentMethod: method,
                  );
                }
              : null,
        ),
      ),
    );

    if (paymentResult == null || !mounted) {
      return;
    }

    if (paymentResult is bool && paymentResult) {
      Navigator.of(context).pop(true);
    } else if (paymentResult is DriverCheckoutPaymentSelection) {
      Navigator.of(context).pop(
        DriverVehicleSelection(
          vehicleType: _selectedVehicleType,
          plateNumber: plateNumber,
          plan: packageSelection.plan,
          duration: packageSelection.duration,
          amount: packageSelection.totalAmount,
          paymentMethod: paymentResult.method,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        titleSpacing: 8,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Select Vehicle',
              style: TextStyle(
                color: AppTheme.textDark,
                fontSize: 17,
                fontWeight: FontWeight.w800,
              ),
            ),
            Text(
              widget.establishmentName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppTheme.textMuted,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 18),
              color: const Color(0xFFFFF4CF),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Step 1 of 3',
                    style: TextStyle(
                      color: Color(0xFF565C6B),
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: const [
                      _StepDot(number: '1', selected: true),
                      _StepLine(),
                      _StepDot(number: '2'),
                      _StepLine(),
                      _StepDot(number: '3'),
                    ],
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Select Vehicle Type',
                      style: TextStyle(
                        color: AppTheme.textDark,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 12),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final int columns = constraints.maxWidth >= 580 ? 3 : 2;
                        return GridView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          gridDelegate:
                              SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: columns,
                            mainAxisSpacing: 10,
                            crossAxisSpacing: 10,
                            mainAxisExtent: 125,
                          ),
                          itemCount: widget.vehicleOptions.length,
                          itemBuilder: (context, index) {
                            final DriverVehicleOption option =
                                widget.vehicleOptions[index];
                            final bool isSelected =
                                option.key == _selectedVehicleType;
                            final int available =
                                (option.capacity - option.activeCount)
                                    .clamp(0, option.capacity);

                            return InkWell(
                              onTap: () {
                                setState(() {
                                  _selectedVehicleType = option.key;
                                });
                              },
                              borderRadius: BorderRadius.circular(12),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 10,
                                ),
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? const Color(0xFFFFF4CF)
                                      : Colors.white,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: isSelected
                                        ? AppTheme.accent
                                        : const Color(0xFFE1E1EA),
                                    width: isSelected ? 1.6 : 1,
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Icon(
                                          option.icon,
                                          size: 20,
                                          color: AppTheme.textDark,
                                        ),
                                        const Spacer(),
                                        if (isSelected)
                                          const Icon(
                                            Icons.check_circle_rounded,
                                            color: Color(0xFFB78300),
                                            size: 19,
                                          ),
                                      ],
                                    ),
                                    const Spacer(),
                                    Text(
                                      option.label,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: AppTheme.textDark,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                    const SizedBox(height: 1),
                                    Text(
                                      '$available slots available',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: AppTheme.textMuted,
                                        fontSize: 10,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      option.rate,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: AppTheme.textDark,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        );
                      },
                    ),
                    const SizedBox(height: 24),
                    Row(
                      children: const [
                        Text(
                          'Plate Number',
                          style: TextStyle(
                            color: AppTheme.textDark,
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          ' *',
                          style: TextStyle(
                            color: Colors.red,
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _plateNumberController,
                      textCapitalization: TextCapitalization.characters,
                      decoration: InputDecoration(
                        hintText: 'E.G. ABC 1234',
                        filled: true,
                        fillColor: Colors.white,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(
                            color: Color(0xFFE1E4EA),
                          ),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(
                            color: Color(0xFFE1E4EA),
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(
                            color: AppTheme.accent,
                            width: 1.5,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SafeArea(
              top: false,
              minimum: const EdgeInsets.fromLTRB(16, 10, 16, 14),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _continue,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.accent,
                    foregroundColor: const Color(0xFF22252C),
                    minimumSize: const Size.fromHeight(50),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'Continue',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StepDot extends StatelessWidget {
  const _StepDot({required this.number, this.selected = false});

  final String number;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 24,
      height: 24,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: selected ? AppTheme.textDark : const Color(0xFFFFEAA8),
        shape: BoxShape.circle,
      ),
      child: Text(
        number,
        style: TextStyle(
          color: selected ? Colors.white : const Color(0xFF7A6030),
          fontSize: 12,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _StepLine extends StatelessWidget {
  const _StepLine();

  @override
  Widget build(BuildContext context) {
    return const Expanded(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 8),
        child: Divider(color: Color(0xFFE0B735), thickness: 2),
      ),
    );
  }
}