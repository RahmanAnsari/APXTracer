import 'package:flutter_test/flutter_test.dart';

import 'package:apx_tracer/engines/kalman/kalman_models.dart';
import 'package:apx_tracer/engines/fusion/nav_state_converter.dart';

/// Helper to create a NavState with sensible defaults.
/// Only override the fields relevant to each test.
NavState _makeNavState({
  double px = 0,
  double py = 0,
  double pz = 0,
  double vx = 0,
  double vy = 0,
  double vz = 0,
  double roll = 0,
  double pitch = 0,
  double yaw = 0,
  double biasAx = 0,
  double biasAy = 0,
  double biasAz = 0,
  double biasGx = 0,
  double biasGy = 0,
  double biasGz = 0,
  double originLat = 0,
  double originLon = 0,
  double originAlt = 0,
}) {
  return NavState(
    px: px,
    py: py,
    pz: pz,
    vx: vx,
    vy: vy,
    vz: vz,
    roll: roll,
    pitch: pitch,
    yaw: yaw,
    biasAx: biasAx,
    biasAy: biasAy,
    biasAz: biasAz,
    biasGx: biasGx,
    biasGy: biasGy,
    biasGz: biasGz,
    originLat: originLat,
    originLon: originLon,
    originAlt: originAlt,
  );
}

void main() {
  group('navStateToGpsSample', () {
    group('valid NavState produces correct GpsSample', () {
      test('all fields are mapped correctly', () {
        // A NavState at origin with zero displacement → lat/lon = origin
        final navState = _makeNavState(
          originLat: 51.5074,
          originLon: -0.1278,
          originAlt: 100.0,
          px: 0,
          py: 0,
          pz: 10.0,
          vx: 3.0,
          vy: 4.0,
          vz: 0,
          yaw: 0, // bearingDeg = 90 degrees (East)
        );

        final result = navStateToGpsSample(
          navState: navState,
          gpsAccuracy: 5.0,
          timestampMs: 1700000000000,
        );

        expect(result, isNotNull);
        expect(result!.latitude, navState.latitude);
        expect(result.longitude, navState.longitude);
        expect(result.altitude, navState.altitude);
        expect(result.speed, navState.groundSpeed);
        expect(result.heading, navState.bearingDeg.clamp(0.0, 360.0));
        expect(result.accuracy, 5.0);
        expect(result.isLowAccuracy, false);
      });

      test('speed is computed as ground speed (horizontal magnitude)', () {
        final navState = _makeNavState(
          originLat: 40.0,
          originLon: -74.0,
          originAlt: 0,
          vx: 3.0,
          vy: 4.0,
          vz: 10.0, // vertical component should not affect groundSpeed
        );

        final result = navStateToGpsSample(
          navState: navState,
          gpsAccuracy: 3.0,
          timestampMs: 1000,
        );

        expect(result, isNotNull);
        expect(result!.speed, closeTo(5.0, 1e-10)); // sqrt(9+16) = 5
      });
    });

    group('heading clamping', () {
      test('heading is clamped to [0, 360] range for normal bearing', () {
        // yaw = pi/2 → bearingDeg = 90 - 90 = 0 degrees
        final navState = _makeNavState(
          originLat: 10.0,
          originLon: 20.0,
          yaw: 3.14159265 / 2, // pi/2
        );

        final result = navStateToGpsSample(
          navState: navState,
          gpsAccuracy: 10.0,
          timestampMs: 5000,
        );

        expect(result, isNotNull);
        expect(result!.heading, greaterThanOrEqualTo(0.0));
        expect(result.heading, lessThanOrEqualTo(360.0));
      });

      test('bearing wraps correctly and stays in [0, 360]', () {
        // yaw = 0 → bearingDeg = 90 degrees (East)
        final navState = _makeNavState(
          originLat: 10.0,
          originLon: 20.0,
          yaw: 0,
        );

        final result = navStateToGpsSample(
          navState: navState,
          gpsAccuracy: 10.0,
          timestampMs: 5000,
        );

        expect(result, isNotNull);
        expect(result!.heading, closeTo(90.0, 1e-10));
      });

      test('negative yaw produces valid heading in [0, 360]', () {
        // yaw = -pi/2 → bearingDeg = 90 - (-90) = 180 degrees
        final navState = _makeNavState(
          originLat: 10.0,
          originLon: 20.0,
          yaw: -3.14159265 / 2,
        );

        final result = navStateToGpsSample(
          navState: navState,
          gpsAccuracy: 10.0,
          timestampMs: 5000,
        );

        expect(result, isNotNull);
        expect(result!.heading, greaterThanOrEqualTo(0.0));
        expect(result.heading, lessThanOrEqualTo(360.0));
        expect(result.heading, closeTo(180.0, 1e-6));
      });
    });

    group('isLowAccuracy', () {
      test('is true when accuracy > 50 m', () {
        final navState = _makeNavState(originLat: 10.0, originLon: 20.0);

        final result = navStateToGpsSample(
          navState: navState,
          gpsAccuracy: 50.1,
          timestampMs: 1000,
        );

        expect(result, isNotNull);
        expect(result!.isLowAccuracy, true);
      });

      test('is false when accuracy == 50 m', () {
        final navState = _makeNavState(originLat: 10.0, originLon: 20.0);

        final result = navStateToGpsSample(
          navState: navState,
          gpsAccuracy: 50.0,
          timestampMs: 1000,
        );

        expect(result, isNotNull);
        expect(result!.isLowAccuracy, false);
      });

      test('is false when accuracy < 50 m', () {
        final navState = _makeNavState(originLat: 10.0, originLon: 20.0);

        final result = navStateToGpsSample(
          navState: navState,
          gpsAccuracy: 3.0,
          timestampMs: 1000,
        );

        expect(result, isNotNull);
        expect(result!.isLowAccuracy, false);
      });

      test('is true for very large accuracy values', () {
        final navState = _makeNavState(originLat: 10.0, originLon: 20.0);

        final result = navStateToGpsSample(
          navState: navState,
          gpsAccuracy: 1000.0,
          timestampMs: 1000,
        );

        expect(result, isNotNull);
        expect(result!.isLowAccuracy, true);
      });
    });

    group('out-of-range latitude returns null', () {
      test('latitude > 90 returns null', () {
        // Place origin at 89.9 and add enough py to push latitude above 90
        final navState = _makeNavState(
          originLat: 89.9,
          originLon: 0,
          py: 20000, // ~0.18 degrees north → lat ≈ 90.08
        );

        // Verify the latitude is indeed > 90
        expect(navState.latitude, greaterThan(90));

        final result = navStateToGpsSample(
          navState: navState,
          gpsAccuracy: 5.0,
          timestampMs: 1000,
        );

        expect(result, isNull);
      });

      test('latitude < -90 returns null', () {
        final navState = _makeNavState(
          originLat: -89.9,
          originLon: 0,
          py: -20000, // pushes latitude below -90
        );

        expect(navState.latitude, lessThan(-90));

        final result = navStateToGpsSample(
          navState: navState,
          gpsAccuracy: 5.0,
          timestampMs: 1000,
        );

        expect(result, isNull);
      });
    });

    group('out-of-range longitude returns null', () {
      test('longitude > 180 returns null', () {
        final navState = _makeNavState(
          originLat: 0,
          originLon: 179.9,
          px: 20000, // ~0.18 degrees east → lon ≈ 180.08
        );

        expect(navState.longitude, greaterThan(180));

        final result = navStateToGpsSample(
          navState: navState,
          gpsAccuracy: 5.0,
          timestampMs: 1000,
        );

        expect(result, isNull);
      });

      test('longitude < -180 returns null', () {
        final navState = _makeNavState(
          originLat: 0,
          originLon: -179.9,
          px: -20000, // pushes longitude below -180
        );

        expect(navState.longitude, lessThan(-180));

        final result = navStateToGpsSample(
          navState: navState,
          gpsAccuracy: 5.0,
          timestampMs: 1000,
        );

        expect(result, isNull);
      });
    });

    group('boundary values return valid GpsSample', () {
      test('latitude exactly +90 returns valid GpsSample', () {
        // NavState with latitude exactly 90
        // originLat = 90, py = 0 → latitude = 90
        final navState = _makeNavState(
          originLat: 90.0,
          originLon: 0,
          px: 0,
          py: 0,
        );

        expect(navState.latitude, 90.0);

        final result = navStateToGpsSample(
          navState: navState,
          gpsAccuracy: 5.0,
          timestampMs: 1000,
        );

        expect(result, isNotNull);
        expect(result!.latitude, 90.0);
      });

      test('latitude exactly -90 returns valid GpsSample', () {
        final navState = _makeNavState(
          originLat: -90.0,
          originLon: 0,
          px: 0,
          py: 0,
        );

        expect(navState.latitude, -90.0);

        final result = navStateToGpsSample(
          navState: navState,
          gpsAccuracy: 5.0,
          timestampMs: 1000,
        );

        expect(result, isNotNull);
        expect(result!.latitude, -90.0);
      });

      test('longitude exactly +180 returns valid GpsSample', () {
        final navState = _makeNavState(
          originLat: 0,
          originLon: 180.0,
          px: 0,
          py: 0,
        );

        expect(navState.longitude, 180.0);

        final result = navStateToGpsSample(
          navState: navState,
          gpsAccuracy: 5.0,
          timestampMs: 1000,
        );

        expect(result, isNotNull);
        expect(result!.longitude, 180.0);
      });

      test('longitude exactly -180 returns valid GpsSample', () {
        final navState = _makeNavState(
          originLat: 0,
          originLon: -180.0,
          px: 0,
          py: 0,
        );

        expect(navState.longitude, -180.0);

        final result = navStateToGpsSample(
          navState: navState,
          gpsAccuracy: 5.0,
          timestampMs: 1000,
        );

        expect(result, isNotNull);
        expect(result!.longitude, -180.0);
      });
    });

    group('timestamp passthrough', () {
      test('timestamp is passed through correctly', () {
        final navState = _makeNavState(originLat: 10.0, originLon: 20.0);

        final result = navStateToGpsSample(
          navState: navState,
          gpsAccuracy: 5.0,
          timestampMs: 1700000000000,
        );

        expect(result, isNotNull);
        expect(result!.timestamp, 1700000000000);
      });

      test('timestamp zero is passed through', () {
        final navState = _makeNavState(originLat: 10.0, originLon: 20.0);

        final result = navStateToGpsSample(
          navState: navState,
          gpsAccuracy: 5.0,
          timestampMs: 0,
        );

        expect(result, isNotNull);
        expect(result!.timestamp, 0);
      });
    });
  });
}
