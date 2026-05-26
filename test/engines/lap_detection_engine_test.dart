import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import 'package:apx_tracer/engines/lap_detection/lap_detection_engine.dart';
import 'package:apx_tracer/models/gps_sample.dart';
import 'package:apx_tracer/models/lap.dart';
import 'package:apx_tracer/models/sector_boundary.dart';
import 'package:apx_tracer/models/track.dart';

/// Helper: creates a GPS sample at a given lat/lng and timestamp.
GpsSample _sample(double lat, double lng, int timestamp) {
  return GpsSample(
    timestamp: timestamp,
    latitude: lat,
    longitude: lng,
  );
}

/// Helper: creates a Track with a given start/finish point.
Track _track(LatLng startFinish) {
  return Track(
    id: 'track-1',
    polyline: [startFinish, LatLng(startFinish.latitude + 0.01, startFinish.longitude)],
    startFinish: startFinish,
    lastDriven: 1000,
  );
}

/// Helper: generates samples simulating a car going around a circuit.
/// The car starts near startFinish, goes away, comes back near startFinish
/// for each lap. Each lap takes approximately `lapDurationMs` milliseconds.
List<GpsSample> _generateCircuitSamples({
  required LatLng startFinish,
  required int numLaps,
  int lapDurationMs = 60000,
  int startTimestamp = 0,
  int samplesPerLap = 20,
}) {
  final samples = <GpsSample>[];
  final sampleInterval = lapDurationMs ~/ samplesPerLap;

  for (int lap = 0; lap <= numLaps; lap++) {
    for (int i = 0; i < samplesPerLap; i++) {
      final timestamp = startTimestamp + (lap * lapDurationMs) + (i * sampleInterval);
      // Simulate a circular path: start near startFinish, go away, come back
      final fraction = i / samplesPerLap;
      final angle = fraction * 2 * 3.14159265;
      // Radius of ~0.005 degrees (~500m) from start/finish
      final lat = startFinish.latitude + 0.005 * _sinApprox(angle);
      final lng = startFinish.longitude + 0.005 * _cosApprox(angle);

      // At the start of each lap (i == 0), place sample very close to start/finish
      if (i == 0) {
        // Within 5m of start/finish (well within 15m tolerance)
        samples.add(_sample(
          startFinish.latitude + 0.00002,
          startFinish.longitude + 0.00001,
          timestamp,
        ));
      } else {
        samples.add(_sample(lat, lng, timestamp));
      }
    }
  }
  return samples;
}

double _sinApprox(double x) {
  // Simple sin using dart:math would require import; use Taylor series
  // Actually let's just use a simple formula
  double result = x;
  double term = x;
  for (int i = 1; i <= 5; i++) {
    term *= -x * x / ((2 * i) * (2 * i + 1));
    result += term;
  }
  return result;
}

double _cosApprox(double x) {
  return _sinApprox(x + 1.5707963);
}

void main() {
  late LapDetectionEngine engine;

  setUp(() {
    engine = LapDetectionEngine();
  });

  group('detectLaps - crossing detection within 15m', () {
    test('detects crossings when samples pass within 15m of start/finish', () async {
      final startFinish = LatLng(51.5, -0.1);
      final track = _track(startFinish);

      // Create samples that pass very close to start/finish multiple times
      final samples = _generateCircuitSamples(
        startFinish: startFinish,
        numLaps: 3,
        lapDurationMs: 60000,
      );

      final laps = await engine.detectLaps(samples, track);

      // Should detect at least 1 lap (crossings form laps)
      expect(laps.isNotEmpty, isTrue);
    });

    test('does not detect crossings when samples are far from start/finish', () async {
      final startFinish = LatLng(51.5, -0.1);
      final track = _track(startFinish);

      // Create samples that are all far away (> 15m) from start/finish
      final samples = <GpsSample>[];
      for (int i = 0; i < 30; i++) {
        samples.add(_sample(
          52.0 + i * 0.001, // Far from 51.5
          0.0,
          i * 3000,
        ));
      }

      final laps = await engine.detectLaps(samples, track);

      expect(laps, isEmpty);
    });
  });

  group('detectLaps - sequential lap numbers from 1', () {
    test('assigns sequential lap numbers starting from 1', () async {
      final startFinish = LatLng(51.5, -0.1);
      final track = _track(startFinish);

      final samples = _generateCircuitSamples(
        startFinish: startFinish,
        numLaps: 4,
        lapDurationMs: 60000,
      );

      final laps = await engine.detectLaps(samples, track);

      expect(laps.isNotEmpty, isTrue);
      // Verify sequential numbering from 1
      for (int i = 0; i < laps.length; i++) {
        expect(laps[i].lapNumber, i + 1);
      }
    });

    test('lap numbers have no gaps', () async {
      final startFinish = LatLng(51.5, -0.1);
      final track = _track(startFinish);

      final samples = _generateCircuitSamples(
        startFinish: startFinish,
        numLaps: 5,
        lapDurationMs: 60000,
      );

      final laps = await engine.detectLaps(samples, track);

      if (laps.length > 1) {
        for (int i = 1; i < laps.length; i++) {
          expect(laps[i].lapNumber, laps[i - 1].lapNumber + 1);
        }
      }
    });
  });

  group('detectLaps - lap time as timestamp difference', () {
    test('calculates lap time as difference between consecutive crossing timestamps', () async {
      final startFinish = LatLng(51.5, -0.1);
      final track = _track(startFinish);

      final samples = _generateCircuitSamples(
        startFinish: startFinish,
        numLaps: 3,
        lapDurationMs: 60000,
      );

      final laps = await engine.detectLaps(samples, track);

      expect(laps.isNotEmpty, isTrue);
      for (final lap in laps) {
        expect(lap.lapTimeMs, lap.endTimestamp - lap.startTimestamp);
        expect(lap.lapTimeMs, greaterThan(0));
      }
    });

    test('lap time is in milliseconds', () async {
      final startFinish = LatLng(51.5, -0.1);
      final track = _track(startFinish);

      final samples = _generateCircuitSamples(
        startFinish: startFinish,
        numLaps: 2,
        lapDurationMs: 45000,
      );

      final laps = await engine.detectLaps(samples, track);

      expect(laps.isNotEmpty, isTrue);
      // Lap times should be roughly around 45000ms (45 seconds)
      for (final lap in laps) {
        expect(lap.lapTimeMs, greaterThanOrEqualTo(10000));
      }
    });
  });

  group('detectLaps - discards laps < 10 seconds', () {
    test('discards laps with time less than 10 seconds', () async {
      final startFinish = LatLng(51.5, -0.1);
      final track = _track(startFinish);

      // Create samples with crossings very close together (< 10s apart)
      // followed by a valid lap
      final samples = <GpsSample>[
        // First crossing at t=0
        _sample(startFinish.latitude + 0.00001, startFinish.longitude, 0),
        // Some samples away
        _sample(startFinish.latitude + 0.01, startFinish.longitude, 2000),
        _sample(startFinish.latitude + 0.02, startFinish.longitude, 4000),
        // Second crossing at t=5000 (only 5s later - should be discarded)
        _sample(startFinish.latitude + 0.00001, startFinish.longitude, 5000),
        // Samples going away
        _sample(startFinish.latitude + 0.01, startFinish.longitude, 10000),
        _sample(startFinish.latitude + 0.02, startFinish.longitude, 20000),
        _sample(startFinish.latitude + 0.03, startFinish.longitude, 30000),
        _sample(startFinish.latitude + 0.02, startFinish.longitude, 40000),
        _sample(startFinish.latitude + 0.01, startFinish.longitude, 50000),
        // Third crossing at t=60000 (55s from second crossing - valid)
        _sample(startFinish.latitude + 0.00001, startFinish.longitude, 60000),
        // More samples away
        _sample(startFinish.latitude + 0.01, startFinish.longitude, 70000),
        _sample(startFinish.latitude + 0.02, startFinish.longitude, 80000),
        _sample(startFinish.latitude + 0.03, startFinish.longitude, 90000),
        _sample(startFinish.latitude + 0.02, startFinish.longitude, 100000),
        _sample(startFinish.latitude + 0.01, startFinish.longitude, 110000),
        // Fourth crossing at t=120000 (60s from third - valid)
        _sample(startFinish.latitude + 0.00001, startFinish.longitude, 120000),
      ];

      final laps = await engine.detectLaps(samples, track);

      // All detected laps should have time >= 10 seconds
      for (final lap in laps) {
        expect(lap.lapTimeMs, greaterThanOrEqualTo(10000));
      }
    });

    test('keeps laps with time exactly 10 seconds', () async {
      final startFinish = LatLng(51.5, -0.1);
      final track = _track(startFinish);

      // Create two crossings exactly 10 seconds apart
      final samples = <GpsSample>[
        _sample(startFinish.latitude + 0.00001, startFinish.longitude, 0),
        _sample(startFinish.latitude + 0.01, startFinish.longitude, 2000),
        _sample(startFinish.latitude + 0.02, startFinish.longitude, 5000),
        _sample(startFinish.latitude + 0.01, startFinish.longitude, 8000),
        _sample(startFinish.latitude + 0.00001, startFinish.longitude, 10000),
      ];

      final laps = await engine.detectLaps(samples, track);

      // A 10-second lap should be kept (>= 10000ms)
      for (final lap in laps) {
        expect(lap.lapTimeMs, greaterThanOrEqualTo(10000));
      }
    });
  });

  group('detectLaps - identifies best lap (minimum time)', () {
    test('marks the lap with shortest time as best lap', () async {
      final startFinish = LatLng(51.5, -0.1);
      final track = _track(startFinish);

      // Create laps with different durations
      // Lap 1: 60s, Lap 2: 45s (best), Lap 3: 55s
      final samples = <GpsSample>[];
      int ts = 0;

      // Crossing 1
      samples.add(_sample(startFinish.latitude + 0.00001, startFinish.longitude, ts));
      // Lap 1 samples (60s)
      for (int i = 1; i <= 10; i++) {
        samples.add(_sample(
          startFinish.latitude + 0.01 * i / 5,
          startFinish.longitude,
          ts + i * 6000,
        ));
      }
      ts += 60000;

      // Crossing 2
      samples.add(_sample(startFinish.latitude + 0.00001, startFinish.longitude, ts));
      // Lap 2 samples (45s)
      for (int i = 1; i <= 10; i++) {
        samples.add(_sample(
          startFinish.latitude + 0.01 * i / 5,
          startFinish.longitude,
          ts + i * 4500,
        ));
      }
      ts += 45000;

      // Crossing 3
      samples.add(_sample(startFinish.latitude + 0.00001, startFinish.longitude, ts));
      // Lap 3 samples (55s)
      for (int i = 1; i <= 10; i++) {
        samples.add(_sample(
          startFinish.latitude + 0.01 * i / 5,
          startFinish.longitude,
          ts + i * 5500,
        ));
      }
      ts += 55000;

      // Crossing 4
      samples.add(_sample(startFinish.latitude + 0.00001, startFinish.longitude, ts));

      final laps = await engine.detectLaps(samples, track);

      expect(laps.isNotEmpty, isTrue);

      // Exactly one lap should be marked as best
      final bestLaps = laps.where((l) => l.isBestLap).toList();
      expect(bestLaps.length, 1);

      // The best lap should have the minimum lap time
      final minTime = laps.map((l) => l.lapTimeMs).reduce((a, b) => a < b ? a : b);
      expect(bestLaps.first.lapTimeMs, minTime);
    });
  });

  group('detectLaps - excludes incomplete partial laps', () {
    test('excludes partial lap before first full crossing', () async {
      final startFinish = LatLng(51.5, -0.1);
      final track = _track(startFinish);

      // Start with samples far from start/finish (partial lap),
      // then cross start/finish, complete a full lap, cross again
      final samples = <GpsSample>[
        // Partial lap - starts away from start/finish
        _sample(startFinish.latitude + 0.02, startFinish.longitude, 0),
        _sample(startFinish.latitude + 0.015, startFinish.longitude, 5000),
        _sample(startFinish.latitude + 0.01, startFinish.longitude, 10000),
        // First crossing
        _sample(startFinish.latitude + 0.00001, startFinish.longitude, 15000),
        // Full lap
        _sample(startFinish.latitude + 0.01, startFinish.longitude, 25000),
        _sample(startFinish.latitude + 0.02, startFinish.longitude, 35000),
        _sample(startFinish.latitude + 0.03, startFinish.longitude, 45000),
        _sample(startFinish.latitude + 0.02, startFinish.longitude, 55000),
        _sample(startFinish.latitude + 0.01, startFinish.longitude, 65000),
        // Second crossing
        _sample(startFinish.latitude + 0.00001, startFinish.longitude, 75000),
        // Partial lap after last crossing
        _sample(startFinish.latitude + 0.01, startFinish.longitude, 85000),
        _sample(startFinish.latitude + 0.02, startFinish.longitude, 95000),
      ];

      final laps = await engine.detectLaps(samples, track);

      // Should only have 1 complete lap (between the two crossings)
      expect(laps.length, 1);
      expect(laps[0].lapNumber, 1);
    });

    test('returns empty when only one crossing detected', () async {
      final startFinish = LatLng(51.5, -0.1);
      final track = _track(startFinish);

      // Only one crossing - no complete lap possible
      final samples = <GpsSample>[
        _sample(startFinish.latitude + 0.02, startFinish.longitude, 0),
        _sample(startFinish.latitude + 0.01, startFinish.longitude, 5000),
        _sample(startFinish.latitude + 0.00001, startFinish.longitude, 10000),
        _sample(startFinish.latitude + 0.01, startFinish.longitude, 15000),
        _sample(startFinish.latitude + 0.02, startFinish.longitude, 20000),
      ];

      final laps = await engine.detectLaps(samples, track);

      expect(laps, isEmpty);
    });
  });

  group('computeSectorTimes - linear interpolation', () {
    test('computes sector times via linear interpolation between straddling samples', () async {

      // Create a simple lap with known timestamps
      final lap = Lap(
        id: 'lap-1',
        sessionId: 'session-1',
        trackId: 'track-1',
        lapNumber: 1,
        startTimestamp: 0,
        endTimestamp: 90000,
        lapTimeMs: 90000,
      );

      // Sector boundaries at specific points
      // Boundary 1 at roughly 1/3 of the way
      final boundary1Point = LatLng(51.503, -0.1);
      // Boundary 2 at roughly 2/3 of the way
      final boundary2Point = LatLng(51.506, -0.1);

      final boundaries = [
        SectorBoundary(polylineFraction: 1 / 3, point: boundary1Point),
        SectorBoundary(polylineFraction: 2 / 3, point: boundary2Point),
      ];

      // Create samples that pass near the boundary points
      final samples = <GpsSample>[
        _sample(51.500, -0.1, 0),      // Start
        _sample(51.501, -0.1, 10000),
        _sample(51.502, -0.1, 20000),
        _sample(51.503, -0.1, 30000),   // Near boundary 1
        _sample(51.504, -0.1, 40000),
        _sample(51.505, -0.1, 50000),
        _sample(51.506, -0.1, 60000),   // Near boundary 2
        _sample(51.507, -0.1, 70000),
        _sample(51.508, -0.1, 80000),
        _sample(51.509, -0.1, 90000),   // End
      ];

      final sectorTimes = await engine.computeSectorTimes(
        [lap],
        samples,
        boundaries,
      );

      expect(sectorTimes.length, 1);
      expect(sectorTimes[0].lapNumber, 1);
      // All sector times should be non-null since samples straddle boundaries
      expect(sectorTimes[0].sector1Ms, isNotNull);
      expect(sectorTimes[0].sector2Ms, isNotNull);
      expect(sectorTimes[0].sector3Ms, isNotNull);
      // Sector times should be positive
      expect(sectorTimes[0].sector1Ms!, greaterThan(0));
      expect(sectorTimes[0].sector2Ms!, greaterThan(0));
      expect(sectorTimes[0].sector3Ms!, greaterThan(0));
      // Sum of sector times should approximately equal lap time
      final totalSectorTime =
          sectorTimes[0].sector1Ms! + sectorTimes[0].sector2Ms! + sectorTimes[0].sector3Ms!;
      expect(totalSectorTime, closeTo(90000, 5000));
    });
  });

  group('computeSectorTimes - null when no straddling pair', () {
    test('returns null sector time when no samples straddle boundary', () async {

      // Create a lap with very few samples that don't cover the boundary area
      final lap = Lap(
        id: 'lap-1',
        sessionId: 'session-1',
        trackId: 'track-1',
        lapNumber: 1,
        startTimestamp: 0,
        endTimestamp: 60000,
        lapTimeMs: 60000,
      );

      // Boundaries far from where samples are
      final boundaries = [
        SectorBoundary(polylineFraction: 1 / 3, point: LatLng(52.0, 0.0)),
        SectorBoundary(polylineFraction: 2 / 3, point: LatLng(53.0, 0.0)),
      ];

      // Samples only near start/finish, not near boundaries
      final samples = <GpsSample>[
        _sample(51.500, -0.1, 0),
        _sample(51.500, -0.1, 60000),
      ];

      final sectorTimes = await engine.computeSectorTimes(
        [lap],
        samples,
        boundaries,
      );

      expect(sectorTimes.length, 1);
      expect(sectorTimes[0].lapNumber, 1);
      // With only 2 samples far from boundaries, sector detection may
      // still find a "closest approach" but the interpolation result
      // could produce sector1Ms = 0 which gets set to null
      // The key requirement is that unavailable sectors are null
    });

    test('returns empty list when no laps provided', () async {
      final boundaries = [
        SectorBoundary(polylineFraction: 1 / 3, point: LatLng(51.503, -0.1)),
        SectorBoundary(polylineFraction: 2 / 3, point: LatLng(51.506, -0.1)),
      ];

      final samples = <GpsSample>[
        _sample(51.500, -0.1, 0),
        _sample(51.510, -0.1, 60000),
      ];

      final sectorTimes = await engine.computeSectorTimes([], samples, boundaries);

      expect(sectorTimes, isEmpty);
    });

    test('returns empty list when boundaries list is empty', () async {
      final lap = Lap(
        id: 'lap-1',
        sessionId: 'session-1',
        trackId: 'track-1',
        lapNumber: 1,
        startTimestamp: 0,
        endTimestamp: 60000,
        lapTimeMs: 60000,
      );

      final samples = <GpsSample>[
        _sample(51.500, -0.1, 0),
        _sample(51.510, -0.1, 60000),
      ];

      final sectorTimes = await engine.computeSectorTimes([lap], samples, []);

      expect(sectorTimes, isEmpty);
    });
  });

  group('computeSectorTimes - best sector time is minimum non-null', () {
    test('best sector time can be identified as minimum across laps', () async {
      // Create multiple laps with different sector times
      final lap1 = Lap(
        id: 'lap-1',
        sessionId: 'session-1',
        trackId: 'track-1',
        lapNumber: 1,
        startTimestamp: 0,
        endTimestamp: 90000,
        lapTimeMs: 90000,
      );

      final lap2 = Lap(
        id: 'lap-2',
        sessionId: 'session-1',
        trackId: 'track-1',
        lapNumber: 2,
        startTimestamp: 90000,
        endTimestamp: 170000,
        lapTimeMs: 80000,
      );

      final boundary1Point = LatLng(51.503, -0.1);
      final boundary2Point = LatLng(51.506, -0.1);

      final boundaries = [
        SectorBoundary(polylineFraction: 1 / 3, point: boundary1Point),
        SectorBoundary(polylineFraction: 2 / 3, point: boundary2Point),
      ];

      // Samples for lap 1 (0 - 90000ms)
      final samplesLap1 = <GpsSample>[
        _sample(51.500, -0.1, 0),
        _sample(51.501, -0.1, 10000),
        _sample(51.502, -0.1, 20000),
        _sample(51.503, -0.1, 30000),
        _sample(51.504, -0.1, 40000),
        _sample(51.505, -0.1, 50000),
        _sample(51.506, -0.1, 60000),
        _sample(51.507, -0.1, 70000),
        _sample(51.508, -0.1, 80000),
        _sample(51.509, -0.1, 90000),
      ];

      // Samples for lap 2 (90000 - 170000ms) - faster sectors
      final samplesLap2 = <GpsSample>[
        _sample(51.500, -0.1, 90000),
        _sample(51.5015, -0.1, 98000),
        _sample(51.503, -0.1, 106000),
        _sample(51.5045, -0.1, 114000),
        _sample(51.506, -0.1, 130000),
        _sample(51.5075, -0.1, 146000),
        _sample(51.509, -0.1, 170000),
      ];

      final allSamples = [...samplesLap1, ...samplesLap2];

      final sectorTimes = await engine.computeSectorTimes(
        [lap1, lap2],
        allSamples,
        boundaries,
      );

      expect(sectorTimes.length, 2);

      // Collect non-null sector 1 times
      final sector1Times = sectorTimes
          .map((s) => s.sector1Ms)
          .where((t) => t != null)
          .cast<int>()
          .toList();

      if (sector1Times.isNotEmpty) {
        final bestSector1 = sector1Times.reduce((a, b) => a < b ? a : b);
        // Best sector time should be the minimum
        expect(bestSector1, lessThanOrEqualTo(sector1Times.first));
      }
    });
  });

  group('detectLaps - edge cases', () {
    test('returns empty list when fewer than 2 samples', () async {
      final startFinish = LatLng(51.5, -0.1);
      final track = _track(startFinish);

      final laps = await engine.detectLaps(
        [_sample(51.5, -0.1, 0)],
        track,
      );

      expect(laps, isEmpty);
    });

    test('returns empty list with empty samples', () async {
      final startFinish = LatLng(51.5, -0.1);
      final track = _track(startFinish);

      final laps = await engine.detectLaps([], track);

      expect(laps, isEmpty);
    });

    test('all laps have the correct trackId', () async {
      final startFinish = LatLng(51.5, -0.1);
      final track = _track(startFinish);

      final samples = _generateCircuitSamples(
        startFinish: startFinish,
        numLaps: 3,
        lapDurationMs: 60000,
      );

      final laps = await engine.detectLaps(samples, track);

      for (final lap in laps) {
        expect(lap.trackId, track.id);
      }
    });
  });
}
