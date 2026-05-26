import 'package:flutter_test/flutter_test.dart';
import 'package:apx_tracer/utils/speed_converter.dart';

void main() {
  group('metersPerSecondToKmh', () {
    test('converts 0 m/s to 0 km/h', () {
      expect(metersPerSecondToKmh(0.0), equals(0.0));
    });

    test('converts 1 m/s to 3.6 km/h', () {
      expect(metersPerSecondToKmh(1.0), equals(3.6));
    });

    test('converts 10 m/s to 36 km/h', () {
      expect(metersPerSecondToKmh(10.0), equals(36.0));
    });

    test('converts typical driving speed (27.78 m/s ≈ 100 km/h)', () {
      expect(metersPerSecondToKmh(27.78), closeTo(100.0, 0.1));
    });

    test('converts high motorsport speed (83.33 m/s ≈ 300 km/h)', () {
      expect(metersPerSecondToKmh(83.33), closeTo(300.0, 0.1));
    });

    test('handles small fractional values accurately', () {
      // 0.5 m/s = 1.8 km/h
      expect(metersPerSecondToKmh(0.5), closeTo(1.8, 0.001));
    });

    test('conversion is consistent with formula (multiply by 3.6)', () {
      const speed = 42.5;
      expect(metersPerSecondToKmh(speed), equals(speed * 3.6));
    });
  });
}
