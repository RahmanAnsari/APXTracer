import 'package:flutter_test/flutter_test.dart';
import 'package:apx_tracer/utils/time_formatter.dart';

void main() {
  group('formatLapTime', () {
    test('formats zero milliseconds', () {
      expect(formatLapTime(0), equals('00:00.000'));
    });

    test('formats sub-second value', () {
      expect(formatLapTime(456), equals('00:00.456'));
    });

    test('formats exact seconds', () {
      expect(formatLapTime(5000), equals('00:05.000'));
    });

    test('formats known lap time (1:23.456)', () {
      expect(formatLapTime(83456), equals('01:23.456'));
    });

    test('formats large value (over 10 minutes)', () {
      // 12 minutes, 34 seconds, 567 ms = 754567 ms
      expect(formatLapTime(754567), equals('12:34.567'));
    });

    test('formats value over 1 hour', () {
      // 65 minutes, 0 seconds, 0 ms = 3900000 ms
      expect(formatLapTime(3900000), equals('65:00.000'));
    });

    test('pads minutes with leading zero', () {
      // 1 minute, 2 seconds, 3 ms
      expect(formatLapTime(62003), equals('01:02.003'));
    });

    test('pads milliseconds with leading zeros', () {
      expect(formatLapTime(60001), equals('01:00.001'));
    });
  });

  group('formatDuration', () {
    test('formats zero seconds', () {
      expect(formatDuration(0), equals('00:00'));
    });

    test('formats sub-minute value', () {
      expect(formatDuration(45), equals('00:45'));
    });

    test('formats exact minute', () {
      expect(formatDuration(60), equals('01:00'));
    });

    test('formats known duration (5:30)', () {
      expect(formatDuration(330), equals('05:30'));
    });

    test('formats large value (over 1 hour)', () {
      // 90 minutes = 5400 seconds
      expect(formatDuration(5400), equals('90:00'));
    });

    test('formats very large value (over 2 hours)', () {
      // 125 minutes, 59 seconds = 7559 seconds
      expect(formatDuration(7559), equals('125:59'));
    });

    test('pads single-digit seconds with leading zero', () {
      expect(formatDuration(61), equals('01:01'));
    });
  });

  group('formatSpeed', () {
    test('formats zero speed', () {
      expect(formatSpeed(0.0), equals('0.0 km/h'));
    });

    test('formats typical driving speed', () {
      expect(formatSpeed(60.0), equals('60.0 km/h'));
    });

    test('rounds to 1 decimal place (round up)', () {
      expect(formatSpeed(123.456), equals('123.5 km/h'));
    });

    test('rounds to 1 decimal place (round down)', () {
      expect(formatSpeed(99.94), equals('99.9 km/h'));
    });

    test('formats high speed value', () {
      expect(formatSpeed(320.7), equals('320.7 km/h'));
    });

    test('formats fractional speed', () {
      expect(formatSpeed(0.5), equals('0.5 km/h'));
    });
  });
}
