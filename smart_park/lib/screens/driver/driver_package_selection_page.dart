import 'package:flutter/material.dart';

import '../../services/parking_pricing.dart';
import '../../theme/app_theme.dart';
import '../../widgets/smartpark_ui.dart';

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
        ? '₱${amount.toStringAsFixed(0)}'
        : '₱${amount.toStringAsFixed(2)}';
  }

  double _calculateTotalAmount(DriverPackageOption option, int duration) {
    return packageTotal(
      plan: option.key,
      initialAmount: option.initialAmount,
      succeedingHourAmount: option.succeedingHourAmount,
      dailyAmount: option.dailyAmount,
      duration: duration,
    );
  }

  /// Largest duration each plan allows (matches the checkout function).
  int _maxDuration(String planKey) => switch (planKey) {
    'extended' => 12,
    'daily' => 7,
    _ => 1,
  };

  bool _hasDuration(String planKey) =>
      planKey == 'extended' || planKey == 'daily';

  String _durationTitle(String planKey) => switch (planKey) {
    'extended' => 'Additional hours',
    'daily' => 'Number of days',
    _ => 'Duration',
  };

  String _durationUnit(String planKey, int count) => switch (planKey) {
    'extended' => count == 1 ? 'hour' : 'hours',
    'daily' => count == 1 ? 'day' : 'days',
    _ => '',
  };

  String _optionDescription(DriverPackageOption option) => switch (option.key) {
    'base' => 'Park up to $spBaseStayHours hours.',
    'extended' =>
      'First $spBaseStayHours hours, then add hours at '
          '${_amountText(option.succeedingHourAmount)}/hr.',
    'daily' => 'Full-day parking, charged per day.',
    _ => '',
  };

  (String, String) _optionPrice(DriverPackageOption option) =>
      switch (option.key) {
        'base' => (_amountText(option.initialAmount), '/ $spBaseStayLabel'),
        'extended' => (_amountText(option.initialAmount), '+ hours'),
        'daily' => (_amountText(option.dailyAmount), '/ day'),
        _ => (
          _amountText(
            option.initialAmount > 0
                ? option.initialAmount
                : option.dailyAmount,
          ),
          '',
        ),
      };

  /// When the paid time ends if the driver parks now.
  String _paidUntil(String planKey, int duration) {
    final DateTime now = DateTime.now();
    final DateTime until = now.add(
      Duration(
        hours: includedStayHours(plan: planKey, duration: duration),
      ),
    );
    final int hour12 = until.hour % 12 == 0 ? 12 : until.hour % 12;
    final String minutes = until.minute.toString().padLeft(2, '0');
    final String suffix = until.hour < 12 ? 'AM' : 'PM';
    final String time = '$hour12:$minutes $suffix';
    final int dayDiff = DateTime(
      until.year,
      until.month,
      until.day,
    ).difference(DateTime(now.year, now.month, now.day)).inDays;
    return switch (dayDiff) {
      0 => 'today, $time',
      1 => 'tomorrow, $time',
      _ => '${spFormatDate(until)}, $time',
    };
  }

  void _continue() {
    final DriverPackageOption selectedOption = widget.options.firstWhere(
      (DriverPackageOption option) => option.key == _selectedPlan,
    );
    final int effectiveDuration = _hasDuration(_selectedPlan) ? _duration : 1;
    final double totalAmount = _calculateTotalAmount(
      selectedOption,
      effectiveDuration,
    );

    final String displayPlanLabel = selectedOption.label;
    final String displayDurationLabel = switch (_selectedPlan) {
      'base' => 'Base Stay · $spBaseStayHours hours',
      'extended' =>
        '+$effectiveDuration hr${effectiveDuration == 1 ? "" : "s"} additional',
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

  Widget _buildOptionCard(DriverPackageOption option) {
    final bool selected = option.key == _selectedPlan;
    final (String price, String unit) = _optionPrice(option);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: selected ? const Color(0xFFFFF8E1) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => setState(() {
            _selectedPlan = option.key;
            _duration = 1;
          }),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: selected ? AppTheme.accent : const Color(0xFFE1E4EA),
                width: selected ? 2 : 1,
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: selected ? AppTheme.accent : const Color(0xFFF3F4F7),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(option.icon, color: AppTheme.textDark, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        option.label,
                        style: const TextStyle(
                          color: AppTheme.textDark,
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _optionDescription(option),
                        style: const TextStyle(
                          color: AppTheme.textMuted,
                          fontSize: 12,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      price,
                      style: const TextStyle(
                        color: AppTheme.textDark,
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (unit.isNotEmpty)
                      Text(
                        unit,
                        style: const TextStyle(
                          color: AppTheme.textMuted,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                  ],
                ),
                const SizedBox(width: 8),
                Icon(
                  selected
                      ? Icons.radio_button_checked_rounded
                      : Icons.radio_button_off_rounded,
                  color: selected
                      ? const Color(0xFFB78300)
                      : const Color(0xFFC3C7D0),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _stepButton(IconData icon, String tooltip, VoidCallback? onPressed) {
    return SizedBox(
      width: 48,
      height: 48,
      child: IconButton.filled(
        onPressed: onPressed,
        tooltip: tooltip,
        icon: Icon(icon),
        style: IconButton.styleFrom(
          backgroundColor: AppTheme.accent,
          foregroundColor: AppTheme.textDark,
          disabledBackgroundColor: const Color(0xFFF1F2F5),
          disabledForegroundColor: const Color(0xFFB5B9C3),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }

  Widget _buildDurationStepper() {
    final int max = _maxDuration(_selectedPlan);
    final String maxUnit = _durationUnit(_selectedPlan, max);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE1E4EA)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            _durationTitle(_selectedPlan),
            style: const TextStyle(
              color: AppTheme.textDark,
              fontSize: 14,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _stepButton(
                Icons.remove_rounded,
                'Less',
                _duration > 1 ? () => setState(() => _duration--) : null,
              ),
              Expanded(
                child: Column(
                  children: [
                    Text(
                      '$_duration',
                      style: const TextStyle(
                        color: AppTheme.textDark,
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                        height: 1.1,
                      ),
                    ),
                    Text(
                      _durationUnit(_selectedPlan, _duration),
                      style: const TextStyle(
                        color: AppTheme.textMuted,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              _stepButton(
                Icons.add_rounded,
                'More',
                _duration < max ? () => setState(() => _duration++) : null,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            _duration >= max
                ? 'Maximum of $max $maxUnit.'
                : 'Up to $max $maxUnit.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppTheme.textMuted, fontSize: 11),
          ),
        ],
      ),
    );
  }

  Widget _summaryLine(String label, String value, {bool strong = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: strong ? AppTheme.textDark : const Color(0xFF565C6B),
                fontSize: strong ? 14 : 13,
                fontWeight: strong ? FontWeight.w800 : FontWeight.w500,
              ),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              color: AppTheme.textDark,
              fontSize: strong ? 16 : 13,
              fontWeight: strong ? FontWeight.w800 : FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummary(DriverPackageOption option, int duration, double total) {
    final String unit = _durationUnit(option.key, duration);
    final List<Widget> lines = switch (option.key) {
      'extended' => <Widget>[
        _summaryLine(
          'Base stay ($spBaseStayLabel)',
          _amountText(option.initialAmount),
        ),
        _summaryLine(
          '$duration additional $unit × '
          '${_amountText(option.succeedingHourAmount)}',
          _amountText(option.succeedingHourAmount * duration),
        ),
      ],
      'daily' => <Widget>[
        _summaryLine(
          '$duration $unit × ${_amountText(option.dailyAmount)}',
          _amountText(option.dailyAmount * duration),
        ),
      ],
      _ => <Widget>[
        _summaryLine(
          'Base stay ($spBaseStayLabel)',
          _amountText(option.initialAmount),
        ),
      ],
    };
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE1E4EA)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Summary',
            style: TextStyle(
              color: AppTheme.textDark,
              fontSize: 14,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          ...lines,
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Divider(height: 1, color: Color(0xFFEDEFF3)),
          ),
          _summaryLine('Total', _amountText(total), strong: true),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.schedule_rounded,
                size: 15,
                color: AppTheme.textMuted,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'If you park now, you are covered until '
                  '${_paidUntil(option.key, duration)}. Extra time is billed '
                  'per hour at the exit gate.',
                  style: const TextStyle(
                    color: AppTheme.textMuted,
                    fontSize: 11,
                    height: 1.3,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final DriverPackageOption selectedOption = widget.options.firstWhere(
      (DriverPackageOption option) => option.key == _selectedPlan,
    );
    final int effectiveDuration = _hasDuration(_selectedPlan) ? _duration : 1;
    final double totalAmount = _calculateTotalAmount(
      selectedOption,
      effectiveDuration,
    );

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
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Step 2 of 3',
                    style: TextStyle(
                      color: Color(0xFF565C6B),
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  SizedBox(height: 8),
                  Row(
                    children: [
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
              child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 640),
                  child: ListView(
                    padding: const EdgeInsets.all(16),
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
                      for (final DriverPackageOption option in widget.options)
                        _buildOptionCard(option),
                      if (_hasDuration(_selectedPlan)) ...[
                        const SizedBox(height: 6),
                        _buildDurationStepper(),
                      ],
                      const SizedBox(height: 12),
                      _buildSummary(
                        selectedOption,
                        effectiveDuration,
                        totalAmount,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                border: Border(top: BorderSide(color: Color(0xFFE8EAF0))),
              ),
              child: SafeArea(
                top: false,
                minimum: const EdgeInsets.fromLTRB(16, 12, 16, 14),
                child: Row(
                  children: [
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Total',
                          style: TextStyle(
                            color: AppTheme.textMuted,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          _amountText(totalAmount),
                          style: const TextStyle(
                            color: AppTheme.textDark,
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(width: 16),
                    Expanded(
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
                  ],
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
