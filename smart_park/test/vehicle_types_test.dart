import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_park/widgets/sp_vehicle_type.dart';

void main() {
  test('a custom vehicle name becomes a stable key and label', () {
    expect(spCustomVehicleKey(' Truck '), 'truck');
    expect(spCustomVehicleKey('Mini Bus'), 'mini_bus');
    expect(spVehicleTypeLabel('mini_bus'), 'Mini Bus');
    expect(spVehicleTypeLabel('car'), 'Car');
  });

  test('a facility takes car, motorcycle and custom types with slots', () {
    final Map<String, dynamic> slots = <String, dynamic>{
      'car': 10,
      'motorcycle': 5,
      'truck': 2,
      'old_type': 0,
    };
    expect(spFacilityVehicleKeys(slots), <String>[
      'car',
      'motorcycle',
      'truck',
    ]);
    expect(spOtherVehicleSlots(slots), <String, int>{'truck': 2});
  });

  test('a custom type gets an icon from its name, else a neutral one', () {
    expect(spVehicleTypeIcon('truck'), Icons.local_shipping_rounded);
    expect(spVehicleTypeIcon('mini_bus'), Icons.directions_bus_rounded);
    expect(spVehicleTypeIcon('golf_cart'), Icons.commute_rounded);
  });
}
