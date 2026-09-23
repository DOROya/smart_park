import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class DriverPackageOption {
  const DriverPackageOption({
    required this.key,
    required this.label,
    required this.icon,
    required this.initialAmount,
    this.succeedingHourAmount = 0.0,
    this.dailyAmount = 0.0,
  });

  final String key;
  final String label;
  final IconData icon;
  final double initialAmount;
  final double succeedingHourAmount;
  final double dailyAmount;
}

class DriverPackageSelection {
  const DriverPackageSelection({
    required this.plan,
    required this.duration,
    required this.unitAmount,
    required this.totalAmount,
    required this.displayPlanLabel,
    required this.displayDurationLabel,
  });

  final String plan;
  final int duration;
  final double unitAmount;
  final double totalAmount;
  final String displayPlanLabel;
  final String displayDurationLabel;
}

class DriverPackageSelectionPage extends StatefulWidget {
  const DriverPackageSelectionPage({
    super.key,
    required this.establishmentName,
    required this.vehicleLabel,
    required this.options,
  });

  final String establishmentName;
  final String vehicleLabel;
  final List<DriverPackageOption> options;

  @override
  State<DriverPackageSelectionPage> createState() =>
      _DriverPackageSelectionPageState();
}

class _DriverPackageSelectionPageState
    extends State<DriverPackageSelectionPage> {
  late String _selectedPlan;
  int _duration = 1;

  @override
  void initState() {
    super.initState();
    _selectedPlan = widget.options.first.key;
  }

  String _amountText(double amount) {
    return amount % 1 == 0
        ? 'P${amount.toStringAsFixed(0)}'
        : 'P${amount.toStringAsFixed(2)}';
  }

  double _calculateTotalAmount(DriverPackageOption option, int duration) {
    switch (option.key) {
      case 'base':
        return option.initialAmount;
      case 'extended':
        return option.initialAmount + (option.succeedingHourAmount * duration);
      case 'daily':
        return option.dailyAmount * duration;
      default:
        return option.initialAmount > 0
            ? option.initialAmount
            : option.dailyAmount * duration;
    }
  }

  List<int> _durationOptions(String planKey) {
    return switch (planKey) {
      'base' => const <int>[], // Do not display duration
      'extended' => List<int>.generate(12, (int i) => i + 1), // 1 to 12
      'daily' => List<int>.generate(7, (int i) => i + 1), // 1 to 7
      _ => List<int>.generate(7, (int i) => i + 1),
    };
  }

  String _durationTitle(String planKey) {
    return switch (planKey) {
      'extended' => 'Additional Hours',
      'daily' => 'Number of Days',
      _ => 'Duration',
    };
  }

  String _durationUnitLabel(String planKey, int count) {
    return switch (planKey) {
      'extended' => count == 1 ? '1 hour additional' : '$count hours additional',
      'daily' => count == 1 ? '1 day' : '$count days',
      _ => '$count',
    };
  }

  String _cardSubtext(DriverPackageOption option) {
    switch (option.key) {
      case 'base':
        return _amountText(option.initialAmount);
      case 'extended':
        return '${_amountText(option.initialAmount)} + ${_amountText(option.succeedingHourAmount)}/hr';
      case 'daily':
        return '${_amountText(option.dailyAmount)}/day';
      default:
        final double amt = option.initialAmount > 0
            ? option.initialAmount
            : option.dailyAmount;
        return _amountText(amt);
    }
  }

  void _continue() {
    final DriverPackageOption selectedOption = widget.options.firstWhere(
      (DriverPackageOption option) => option.key == _selectedPlan,
    );
    final int effectiveDuration = _selectedPlan == 'base' ? 1 : _duration;
    final double totalAmount = _calculateTotalAmount(selectedOption, effectiveDuration);

    final String displayPlanLabel = selectedOption.label;
    final String displayDurationLabel = switch (_selectedPlan) {
      'base' => 'Base Stay',
      'extended' => '+$effectiveDuration hr${effectiveDuration == 1 ? "" : "s"} additional',
      'daily' => '$effectiveDuration day${effectiveDuration == 1 ? "" : "s"}',
      _ => '$effectiveDuration',
    };

    Navigator.of(context).pop(
      DriverPackageSelection(
        plan: _selectedPlan,
        duration: effectiveDuration,
        unitAmount: selectedOption.initialAmount > 0
            ? selectedOption.initialAmount
            : selectedOption.dailyAmount,
        totalAmount: totalAmount,
        displayPlanLabel: displayPlanLabel,
        displayDurationLabel: displayDurationLabel,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final DriverPackageOption selectedOption = widget.options.firstWhere(
      (DriverPackageOption option) => option.key == _selectedPlan,
    );
    final List<int> durations = _durationOptions(_selectedPlan);
    final double totalAmount = _calculateTotalAmount(selectedOption, _duration);

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
              'Select Package',
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
                    'Step 2 of 3',
                    style: TextStyle(
                      color: Color(0xFF565C6B),
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: const [
                      _StepDot(number: '1', complete: true),
                      _StepLine(),
                      _StepDot(number: '2', selected: true),
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
                    Text(
                      'Choose a package for your ${widget.vehicleLabel}',
                      style: const TextStyle(
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
                            mainAxisExtent: 115,
                          ),
                          itemCount: widget.options.length,
                          itemBuilder: (context, index) {
                            final DriverPackageOption option =
                                widget.options[index];
                            final bool isSelected = option.key == _selectedPlan;
                            return InkWell(
                              onTap: () {
                                setState(() {
                                  _selectedPlan = option.key;
                                  _duration = 1;
                                });
                              },
                              borderRadius: BorderRadius.circular(12),
                              child: Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? const Color(0xFFFFF4CF)
                                      : Colors.white,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: isSelected
                                        ? AppTheme.accent
                                        : const Color(0xFFE1E4EA),
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
                                          color: AppTheme.textDark,
                                          size: 20,
                                        ),
                                        const Spacer(),
                                        if (isSelected)
                                          const Icon(
                                            Icons.check_circle_rounded,
                                            color: Color(0xFFB78300),
                                            size: 20,
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
                                    const SizedBox(height: 3),
                                    Text(
                                      _cardSubtext(option),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: AppTheme.textDark,
                                        fontSize: 14,
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
                    if (durations.isNotEmpty) ...[
                      const SizedBox(height: 20),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFE1E4EA)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(
                                  _durationTitle(_selectedPlan),
                                  style: const TextStyle(
                                    color: AppTheme.textDark,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                const Spacer(),
                                Text(
                                  _durationUnitLabel(_selectedPlan, _duration),
                                  style: const TextStyle(
                                    color: Color(0xFF7A6030),
                                    fontSize: 12,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            DropdownButtonFormField<int>(
                              value: durations.contains(_duration) ? _duration : durations.first,
                              decoration: InputDecoration(
                                filled: true,
                                fillColor: const Color(0xFFF8F9FC),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide: const BorderSide(color: Color(0xFFE1E4EA)),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide: const BorderSide(color: Color(0xFFE1E4EA)),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide: const BorderSide(color: AppTheme.accent, width: 1.5),
                                ),
                              ),
                              dropdownColor: Colors.white,
                              icon: const Icon(Icons.arrow_drop_down_rounded, color: AppTheme.textDark),
                              items: durations.map((int duration) {
                                return DropdownMenuItem<int>(
                                  value: duration,
                                  child: Text(
                                    _durationUnitLabel(_selectedPlan, duration),
                                    style: const TextStyle(
                                      color: AppTheme.textDark,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                );
                              }).toList(),
                              onChanged: (int? newValue) {
                                if (newValue != null) {
                                  setState(() {
                                    _duration = newValue;
                                  });
                                }
                              },
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF4CF),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFF0D67A)),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  selectedOption.label,
                                  style: const TextStyle(
                                    color: AppTheme.textDark,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  durations.isEmpty
                                      ? 'Fixed Stay'
                                      : _durationUnitLabel(_selectedPlan, _duration),
                                  style: const TextStyle(
                                    color: Color(0xFF565C6B),
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Text(
                            _amountText(totalAmount),
                            style: const TextStyle(
                              color: AppTheme.textDark,
                              fontSize: 24,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
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
  const _StepDot({
    required this.number,
    this.selected = false,
    this.complete = false,
  });

  final String number;
  final bool selected;
  final bool complete;

  @override
  Widget build(BuildContext context) {
    final bool emphasized = selected || complete;
    return Container(
      width: 24,
      height: 24,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: emphasized ? AppTheme.textDark : const Color(0xFFFFEAA8),
        shape: BoxShape.circle,
      ),
      child: complete
          ? const Icon(Icons.check_rounded, color: Colors.white, size: 15)
          : Text(
              number,
              style: TextStyle(
                color: emphasized ? Colors.white : const Color(0xFF7A6030),
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