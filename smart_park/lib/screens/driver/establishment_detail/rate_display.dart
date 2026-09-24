part of '../establishment_detail_page.dart';

// Rate grid / quick-rate formatting for the establishment detail page.

String _formatGridAmount(dynamic val) {
  if (val == null) return '';
  String text = val.toString().trim();
  if (text.isEmpty || text.toLowerCase() == 'not provided') return '';

  final num? n = num.tryParse(text);
  if (n != null) {
    final String numStr = (n % 1 == 0)
        ? n.toInt().toString()
        : n.toStringAsFixed(0);
    return '₱$numStr';
  }

  text = text
      .replaceAll(
        RegExp(
          r'/hr|/hour|per hour|/day|per day|/week|per week|/month|per month',
          caseSensitive: false,
        ),
        '',
      )
      .trim();

  if (text.toUpperCase().startsWith('PHP')) {
    text = '₱${text.substring(3).trim()}';
  } else if (text.toUpperCase().startsWith('P')) {
    text = '₱${text.substring(1).trim()}';
  } else if (!text.startsWith('₱')) {
    text = '₱$text';
  }

  return text;
}

class _RateDetailCell {
  const _RateDetailCell({
    required this.label,
    required this.amount,
    required this.unit,
  });

  final String label;
  final String amount;
  final String unit;
}

dynamic _extractRateValue(
  Map<String, dynamic> data,
  Map<String, dynamic> vMap,
  String vehicleKey,
  List<String> fieldKeys,
) {
  for (final String k in fieldKeys) {
    if (vMap.containsKey(k) && vMap[k] != null) {
      final String val = vMap[k].toString().trim();
      if (val.isNotEmpty) return val;
    }
  }

  final Map<String, dynamic> packageRates = _asStringMap(
    data['packageRates'] ?? data['packages'] ?? data['packagePricing'],
  );

  for (final Map<String, dynamic> source in <Map<String, dynamic>>[
    data,
    packageRates,
  ]) {
    for (final String fieldKey in fieldKeys) {
      if (source.containsKey(fieldKey)) {
        final dynamic topVal = source[fieldKey];
        if (topVal is Map) {
          final Map<String, dynamic> topMap = _asStringMap(topVal);
          final dynamic vehicleVal =
              topMap[vehicleKey] ??
              (vehicleKey == 'motorcycle' ? topMap['motor'] : null);
          if (vehicleVal != null && vehicleVal.toString().trim().isNotEmpty) {
            return vehicleVal;
          }
        } else if (topVal != null && topVal.toString().trim().isNotEmpty) {
          return topVal;
        }
      }
    }
  }

  return null;
}

List<_RateDetailCell> _getRateGridCells(
  Map<String, dynamic> data,
  String vehicleKey,
) {
  final Map<String, dynamic> ratesByType = _asStringMap(data['ratesByType']);
  final Map<String, dynamic> rates = _asStringMap(data['rates']);

  final dynamic rawVehicleValue = ratesByType[vehicleKey] ?? rates[vehicleKey];
  final Map<String, dynamic> vMap = rawVehicleValue is Map
      ? _asStringMap(rawVehicleValue)
      : <String, dynamic>{};

  final dynamic rawInitial =
      vMap['initial'] ??
      vMap['rates'] ??
      vMap['hourly'] ??
      vMap['firstHours'] ??
      rawVehicleValue;

  final dynamic rawDaily = _extractRateValue(data, vMap, vehicleKey, <String>[
    'succeedingDaily',
    'SucceedingDaily',
    'succeeding_daily',
    'daily',
    'ratesByDaily',
  ]);

  final dynamic rawWeekly = _extractRateValue(data, vMap, vehicleKey, <String>[
    'succeedingWeekly',
    'SucceedingWeekly',
    'succeeding_weekly',
    'weekly',
    'SucceedingWeeklyRates',
    'succeedingWeeklyRates',
  ]);

  final dynamic rawMonthly = _extractRateValue(data, vMap, vehicleKey, <String>[
    'succeedingMonthly',
    'SucceedingMonthly',
    'succeeding_monthly',
    'monthly',
    'SucceedingMonthlyRates',
    'succeedingMonthlyRates',
  ]);

  final List<_RateDetailCell> cells = <_RateDetailCell>[];

  // 1. HOURLY
  final String hourlyAmt = _formatGridAmount(rawInitial);
  cells.add(
    _RateDetailCell(
      label: 'HOURLY',
      amount: hourlyAmt.isNotEmpty ? hourlyAmt : '₱0',
      unit: 'per hour',
    ),
  );

  // 2. DAILY
  final String dailyAmt = _formatGridAmount(rawDaily);
  cells.add(
    _RateDetailCell(
      label: 'DAILY',
      amount: dailyAmt.isNotEmpty ? dailyAmt : '₱0',
      unit: 'per day',
    ),
  );

  // 3. WEEKLY (Only displayed if explicitly provided by establishment)
  final String weeklyAmt = _formatGridAmount(rawWeekly);
  if (weeklyAmt.isNotEmpty && weeklyAmt != '₱0') {
    cells.add(
      _RateDetailCell(label: 'WEEKLY', amount: weeklyAmt, unit: 'per week'),
    );
  }

  // 4. MONTHLY (Only displayed if explicitly provided by establishment)
  final String monthlyAmt = _formatGridAmount(rawMonthly);
  if (monthlyAmt.isNotEmpty && monthlyAmt != '₱0') {
    cells.add(
      _RateDetailCell(label: 'MONTHLY', amount: monthlyAmt, unit: 'per month'),
    );
  }

  return cells;
}

class _QuickRateData {
  const _QuickRateData({
    required this.hourlyAmount,
    required this.hourlyUnit,
    this.succeedingHourText,
    this.dailyText,
  });

  final String hourlyAmount;
  final String hourlyUnit;
  final String? succeedingHourText;
  final String? dailyText;
}

_QuickRateData _getQuickRateData(Map<String, dynamic> data, String vehicleKey) {
  final Map<String, dynamic> ratesByType = _asStringMap(data['ratesByType']);
  final Map<String, dynamic> rates = _asStringMap(data['rates']);

  final Map<String, dynamic> initialRates = _asStringMap(
    data['initialRates'] ?? data['ratesByInitial'] ?? data['ratesByHour'],
  );
  final Map<String, dynamic> succeedingHourRates = _asStringMap(
    data['succeedingHour'] ??
        data['succeedingHourRates'] ??
        data['ratesBySucceedingHour'],
  );
  final Map<String, dynamic> succeedingDailyRates = _asStringMap(
    data['succeedingDaily'] ??
        data['succeedingDailyRates'] ??
        data['ratesBySucceedingDaily'] ??
        data['ratesByDaily'],
  );

  final dynamic rawVehicleValue = ratesByType[vehicleKey] ?? rates[vehicleKey];

  dynamic rawInitial;
  dynamic rawSucceedingHour;
  dynamic rawSucceedingDaily;

  if (rawVehicleValue is Map) {
    final Map<String, dynamic> vMap = _asStringMap(rawVehicleValue);
    rawInitial =
        vMap['initial'] ??
        vMap['rates'] ??
        vMap['hourly'] ??
        vMap['firstHours'];
    rawSucceedingHour =
        vMap['succeedingHour'] ?? vMap['succeeding_hour'] ?? vMap['succeeding'];
    rawSucceedingDaily =
        vMap['succeedingDaily'] ?? vMap['succeeding_daily'] ?? vMap['daily'];
  } else {
    rawInitial = rawVehicleValue;
  }

  rawInitial ??= initialRates[vehicleKey] ?? rates[vehicleKey];
  rawSucceedingHour ??= succeedingHourRates[vehicleKey];
  rawSucceedingDaily ??= succeedingDailyRates[vehicleKey];

  final String initialAmt = _formatQuickAmount(rawInitial);
  final String succHourAmt = _formatQuickAmount(rawSucceedingHour);
  final String succDailyAmt = _formatQuickAmount(rawSucceedingDaily);

  return _QuickRateData(
    hourlyAmount: initialAmt.isEmpty ? 'N/A' : initialAmt,
    hourlyUnit: initialAmt.isEmpty ? '' : ' / $spBaseStayLabel',
    succeedingHourText: succHourAmt.isNotEmpty
        ? '+$succHourAmt/hr succeeding'
        : null,
    dailyText: succDailyAmt.isNotEmpty ? '$succDailyAmt/day' : null,
  );
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

String _formatQuickAmount(dynamic val) {
  if (val == null) return '';
  String text = val.toString().trim();
  if (text.isEmpty || text.toLowerCase() == 'not provided') return '';

  final num? n = num.tryParse(text);
  if (n != null) {
    final String numStr = (n % 1 == 0)
        ? n.toInt().toString()
        : n.toStringAsFixed(2);
    return 'P$numStr';
  }

  text = text
      .replaceAll(RegExp(r'/hr|/hour|per hour', caseSensitive: false), '')
      .trim();

  if (text.toUpperCase().startsWith('PHP')) {
    text = 'P${text.substring(3).trim()}';
  } else if (text.startsWith('₱')) {
    text = 'P${text.substring(1).trim()}';
  } else if (!text.toUpperCase().startsWith('P') &&
      RegExp(r'^\d').hasMatch(text)) {
    text = 'P$text';
  }

  return text;
}
