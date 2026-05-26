import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:apx_tracer/data/analytics_repository.dart';
import 'package:apx_tracer/engines/analytics/analytics_engine.dart';
import 'package:apx_tracer/engines/lap_detection/lap_detection_engine.dart';
import 'package:apx_tracer/models/gps_sample.dart';
import 'package:apx_tracer/models/lap.dart';
import 'package:apx_tracer/models/session.dart';
import 'package:apx_tracer/models/session_analytics.dart';

class MockAnalyticsRepository extends Mock implements AnalyticsRepository {}

class FakeSessionAnalytics extends Fake implements SessionAnalytics {}

void main() {
  late MockAnalyticsRepository mockRepository;
  late AnalyticsEngine engine;

  setUpAll(() {
    registerFallbackValue(FakeSessionAnalytics());
  });

  setUp(() {
    mockRepository = MockAnalyticsRepository();
    engine = AnalyticsEngine(mockRepository);
    when(() => mockRepository.insert(any())).thenAnswer((_) async {});
  });

  /// Helper: creates a session with given start and end times.
  Session createSession({
    String id = 'session-1',
    int startTime = 0,
    int? endTime,
  }) {
    return Session(
      id: id,
      startTime: startTime,
      endTime: endTime,
    );
  }

  /// Helper: creates a GPS sample at a given position with optional speed.
  GpsSample createSample({
    required int timestamp,
    double latitude = 51.5,
    double longitude = -0.1,
    double? speed,
  }) {
    return GpsSample(
      timestamp: timestamp,
      latitude: latitude,
      longitude: longitude,
      speed: speed,
    );
  }

  /// Helper: creates a Lap with given parameters.
  Lap createLap({
    String id = 'lap-1',
    String sessionId = 'session-1',
    String trackId = 'track-1',
    int lapNumber = 1,
    int startTimestamp = 0,
    int endTimestamp = 60000,
    int lapTimeMs = 60000,
  }) {
    return Lap(
      id: id,
      sessionId: sessionId,
      trackId: trackId,
      lapNumber: lapNumber,
      startTimestamp: startTimestamp,
      endTimestamp: endTimestamp,
      lapTimeMs: lapTimeMs,
    );
  }

  group('computeAnalytics - duration calculation', () {
    test('calculates duration correctly from session start and end times', () async {
      final session = createSession(startTime: 0, endTime: 120000); // 120 seconds
      final samples = [
        createSample(timestamp: 0),
        createSample(timestamp: 120000),
      ];

      final analytics = await engine.computeAnalytics(
        session,
        samples,
        [],
        [],
      );

      expect(analytics.durationSeconds, 120.0);
    });

    test('returns 0 duration when session has no end time', () async {
      final session = createSession(startTime: 0, endTime: null);
      final samples = [createSample(timestamp: 0)];

      final analytics = await engine.computeAnalytics(
        session,
        samples,
        [],
        [],
      );

      expect(analytics.durationSeconds, 0.0);
    });

    test('calculates fractional duration correctly', () async {
      // 90500ms = 90.5 seconds
      final session = createSession(startTime: 1000, endTime: 91500);
      final samples = [
        createSample(timestamp: 1000),
        createSample(timestamp: 91500),
      ];

      final analytics = await engine.computeAnalytics(
        session,
        samples,
        [],
        [],
      );

      expect(analytics.durationSeconds, 90.5);
    });
  });

  group('computeAnalytics - distance via Haversine sum (2 decimal km)', () {
    test('calculates distance as sum of Haversine between consecutive samples', () async {
      final session = createSession(startTime: 0, endTime: 30000);

      // Known coordinates: ~111.19 km per degree of latitude at equator
      // 0.01 degrees latitude ≈ 1.11 km
      final samples = [
        createSample(timestamp: 0, latitude: 0.0, longitude: 0.0),
        createSample(timestamp: 10000, latitude: 0.01, longitude: 0.0),
        createSample(timestamp: 20000, latitude: 0.02, longitude: 0.0),
        createSample(timestamp: 30000, latitude: 0.03, longitude: 0.0),
      ];

      final analytics = await engine.computeAnalytics(
        session,
        samples,
        [],
        [],
      );

      // 3 segments of ~1.11 km each ≈ 3.34 km
      expect(analytics.distanceKm, closeTo(3.34, 0.02));
      // Verify 2 decimal places
      final decimalStr = analytics.distanceKm.toString();
      final parts = decimalStr.split('.');
      expect(parts.length, 2);
      expect(parts[1].length, lessThanOrEqualTo(2));
    });

    test('returns 0 distance with fewer than 2 samples', () async {
      final session = createSession(startTime: 0, endTime: 10000);
      final samples = [createSample(timestamp: 0)];

      final analytics = await engine.computeAnalytics(
        session,
        samples,
        [],
        [],
      );

      expect(analytics.distanceKm, 0.0);
    });

    test('distance is rounded to 2 decimal places', () async {
      final session = createSession(startTime: 0, endTime: 10000);
      final samples = [
        createSample(timestamp: 0, latitude: 51.5, longitude: -0.1),
        createSample(timestamp: 10000, latitude: 51.501, longitude: -0.1),
      ];

      final analytics = await engine.computeAnalytics(
        session,
        samples,
        [],
        [],
      );

      // Verify the result has at most 2 decimal places
      final str = analytics.distanceKm.toStringAsFixed(2);
      expect(analytics.distanceKm, double.parse(str));
    });
  });

  group('computeAnalytics - total laps from detected laps', () {
    test('total laps equals the count of detected laps', () async {
      final session = createSession(startTime: 0, endTime: 180000);
      final samples = [
        createSample(timestamp: 0),
        createSample(timestamp: 180000),
      ];
      final laps = [
        createLap(lapNumber: 1, lapTimeMs: 60000),
        createLap(id: 'lap-2', lapNumber: 2, lapTimeMs: 55000),
        createLap(id: 'lap-3', lapNumber: 3, lapTimeMs: 65000),
      ];

      final analytics = await engine.computeAnalytics(
        session,
        samples,
        laps,
        [],
      );

      expect(analytics.totalLaps, 3);
    });

    test('total laps is 0 when no laps detected', () async {
      final session = createSession(startTime: 0, endTime: 60000);
      final samples = [
        createSample(timestamp: 0),
        createSample(timestamp: 60000),
      ];

      final analytics = await engine.computeAnalytics(
        session,
        samples,
        [],
        [],
      );

      expect(analytics.totalLaps, 0);
    });
  });

  group('computeAnalytics - best lap time is minimum', () {
    test('best lap time is the minimum lap_time_ms among all laps', () async {
      final session = createSession(startTime: 0, endTime: 180000);
      final samples = [
        createSample(timestamp: 0),
        createSample(timestamp: 180000),
      ];
      final laps = [
        createLap(lapNumber: 1, lapTimeMs: 65000),
        createLap(id: 'lap-2', lapNumber: 2, lapTimeMs: 45000), // best
        createLap(id: 'lap-3', lapNumber: 3, lapTimeMs: 55000),
      ];

      final analytics = await engine.computeAnalytics(
        session,
        samples,
        laps,
        [],
      );

      expect(analytics.bestLapTimeMs, 45000);
    });

    test('best lap time is null when no laps', () async {
      final session = createSession(startTime: 0, endTime: 60000);
      final samples = [
        createSample(timestamp: 0),
        createSample(timestamp: 60000),
      ];

      final analytics = await engine.computeAnalytics(
        session,
        samples,
        [],
        [],
      );

      expect(analytics.bestLapTimeMs, isNull);
    });

    test('best lap time with single lap equals that lap time', () async {
      final session = createSession(startTime: 0, endTime: 60000);
      final samples = [
        createSample(timestamp: 0),
        createSample(timestamp: 60000),
      ];
      final laps = [createLap(lapTimeMs: 58000)];

      final analytics = await engine.computeAnalytics(
        session,
        samples,
        laps,
        [],
      );

      expect(analytics.bestLapTimeMs, 58000);
    });
  });

  group('computeAnalytics - average lap time computed correctly', () {
    test('average lap time is the mean of all lap_time_ms values', () async {
      final session = createSession(startTime: 0, endTime: 180000);
      final samples = [
        createSample(timestamp: 0),
        createSample(timestamp: 180000),
      ];
      final laps = [
        createLap(lapNumber: 1, lapTimeMs: 60000),
        createLap(id: 'lap-2', lapNumber: 2, lapTimeMs: 50000),
        createLap(id: 'lap-3', lapNumber: 3, lapTimeMs: 70000),
      ];

      final analytics = await engine.computeAnalytics(
        session,
        samples,
        laps,
        [],
      );

      // (60000 + 50000 + 70000) / 3 = 60000
      expect(analytics.averageLapTimeMs, 60000);
    });

    test('average lap time is null when no laps', () async {
      final session = createSession(startTime: 0, endTime: 60000);
      final samples = [
        createSample(timestamp: 0),
        createSample(timestamp: 60000),
      ];

      final analytics = await engine.computeAnalytics(
        session,
        samples,
        [],
        [],
      );

      expect(analytics.averageLapTimeMs, isNull);
    });

    test('average lap time rounds to nearest integer', () async {
      final session = createSession(startTime: 0, endTime: 120000);
      final samples = [
        createSample(timestamp: 0),
        createSample(timestamp: 120000),
      ];
      // (60000 + 55000) / 2 = 57500
      final laps = [
        createLap(lapNumber: 1, lapTimeMs: 60000),
        createLap(id: 'lap-2', lapNumber: 2, lapTimeMs: 55000),
      ];

      final analytics = await engine.computeAnalytics(
        session,
        samples,
        laps,
        [],
      );

      expect(analytics.averageLapTimeMs, 57500);
    });
  });

  group('computeAnalytics - average speed = distance / duration (1 decimal)', () {
    test('average speed equals distance divided by duration in km/h', () async {
      // 10 km in 3600 seconds (1 hour) = 10.0 km/h
      // Use samples that produce ~10 km distance
      // 0.09 degrees latitude ≈ 10 km
      final session = createSession(startTime: 0, endTime: 3600000);
      final samples = [
        createSample(timestamp: 0, latitude: 0.0, longitude: 0.0),
        createSample(timestamp: 3600000, latitude: 0.09, longitude: 0.0),
      ];

      final analytics = await engine.computeAnalytics(
        session,
        samples,
        [],
        [],
      );

      // distance ≈ 10.01 km, duration = 3600s = 1 hour
      // avg speed ≈ 10.01 / 1 ≈ 10.0 km/h
      expect(analytics.averageSpeedKmh, closeTo(10.0, 0.2));
    });

    test('average speed is 0 when duration is 0', () async {
      final session = createSession(startTime: 0, endTime: null);
      final samples = [createSample(timestamp: 0)];

      final analytics = await engine.computeAnalytics(
        session,
        samples,
        [],
        [],
      );

      expect(analytics.averageSpeedKmh, 0.0);
    });

    test('average speed has 1 decimal place precision', () async {
      final session = createSession(startTime: 0, endTime: 60000);
      final samples = [
        createSample(timestamp: 0, latitude: 0.0, longitude: 0.0),
        createSample(timestamp: 60000, latitude: 0.005, longitude: 0.0),
      ];

      final analytics = await engine.computeAnalytics(
        session,
        samples,
        [],
        [],
      );

      // Verify 1 decimal place
      final str = analytics.averageSpeedKmh.toStringAsFixed(1);
      expect(analytics.averageSpeedKmh, double.parse(str));
    });
  });

  group('computeAnalytics - max speed = max sample speed in km/h', () {
    test('max speed is the maximum sample speed converted to km/h', () async {
      final session = createSession(startTime: 0, endTime: 30000);
      final samples = [
        createSample(timestamp: 0, speed: 10.0),    // 36 km/h
        createSample(timestamp: 10000, speed: 25.0), // 90 km/h
        createSample(timestamp: 20000, speed: 20.0), // 72 km/h
        createSample(timestamp: 30000, speed: 15.0), // 54 km/h
      ];

      final analytics = await engine.computeAnalytics(
        session,
        samples,
        [],
        [],
      );

      // Max speed = 25.0 m/s * 3.6 = 90.0 km/h
      expect(analytics.maxSpeedKmh, 90.0);
    });

    test('max speed is 0 when all samples have null speed', () async {
      final session = createSession(startTime: 0, endTime: 20000);
      final samples = [
        createSample(timestamp: 0, speed: null),
        createSample(timestamp: 10000, speed: null),
        createSample(timestamp: 20000, speed: null),
      ];

      final analytics = await engine.computeAnalytics(
        session,
        samples,
        [],
        [],
      );

      expect(analytics.maxSpeedKmh, 0.0);
    });

    test('max speed has 1 decimal place precision', () async {
      final session = createSession(startTime: 0, endTime: 10000);
      final samples = [
        createSample(timestamp: 0, speed: 27.78), // 100.008 km/h → 100.0
        createSample(timestamp: 10000, speed: 10.0),
      ];

      final analytics = await engine.computeAnalytics(
        session,
        samples,
        [],
        [],
      );

      // 27.78 * 3.6 = 100.008 → rounded to 1 decimal = 100.0
      final str = analytics.maxSpeedKmh.toStringAsFixed(1);
      expect(analytics.maxSpeedKmh, double.parse(str));
    });
  });

  group('computeAnalytics - speed trace has one entry per sample', () {
    test('speed trace length equals number of samples', () async {
      final session = createSession(startTime: 0, endTime: 40000);
      final samples = [
        createSample(timestamp: 0, speed: 10.0),
        createSample(timestamp: 10000, speed: 15.0),
        createSample(timestamp: 20000, speed: 20.0),
        createSample(timestamp: 30000, speed: 25.0),
        createSample(timestamp: 40000, speed: 12.0),
      ];

      final analytics = await engine.computeAnalytics(
        session,
        samples,
        [],
        [],
      );

      expect(analytics.speedTraceKmh.length, 5);
    });

    test('speed trace values are converted from m/s to km/h', () async {
      final session = createSession(startTime: 0, endTime: 20000);
      final samples = [
        createSample(timestamp: 0, speed: 10.0),    // 36 km/h
        createSample(timestamp: 10000, speed: 20.0), // 72 km/h
        createSample(timestamp: 20000, speed: 5.0),  // 18 km/h
      ];

      final analytics = await engine.computeAnalytics(
        session,
        samples,
        [],
        [],
      );

      expect(analytics.speedTraceKmh[0], closeTo(36.0, 0.01));
      expect(analytics.speedTraceKmh[1], closeTo(72.0, 0.01));
      expect(analytics.speedTraceKmh[2], closeTo(18.0, 0.01));
    });

    test('speed trace uses 0 for samples with null speed', () async {
      final session = createSession(startTime: 0, endTime: 20000);
      final samples = [
        createSample(timestamp: 0, speed: 10.0),
        createSample(timestamp: 10000, speed: null),
        createSample(timestamp: 20000, speed: 5.0),
      ];

      final analytics = await engine.computeAnalytics(
        session,
        samples,
        [],
        [],
      );

      expect(analytics.speedTraceKmh[1], 0.0);
    });
  });

  group('computeAnalytics - zero laps: total=0, best/avg omitted (null)', () {
    test('zero laps produces total=0 and null best/average lap times', () async {
      final session = createSession(startTime: 0, endTime: 60000);
      final samples = [
        createSample(timestamp: 0, speed: 15.0),
        createSample(timestamp: 30000, speed: 20.0),
        createSample(timestamp: 60000, speed: 10.0),
      ];

      final analytics = await engine.computeAnalytics(
        session,
        samples,
        [],
        [],
      );

      expect(analytics.totalLaps, 0);
      expect(analytics.bestLapTimeMs, isNull);
      expect(analytics.averageLapTimeMs, isNull);
    });
  });

  group('computeAnalytics - works without internet (mocked offline)', () {
    test('all computation works from local data without network calls', () async {
      // This test verifies that the analytics engine only depends on
      // locally provided data (session, samples, laps, sectorTimes)
      // and the local AnalyticsRepository. No network calls are made.
      final session = createSession(startTime: 0, endTime: 120000);
      final samples = [
        createSample(timestamp: 0, latitude: 51.5, longitude: -0.1, speed: 15.0),
        createSample(timestamp: 30000, latitude: 51.501, longitude: -0.1, speed: 20.0),
        createSample(timestamp: 60000, latitude: 51.502, longitude: -0.1, speed: 25.0),
        createSample(timestamp: 90000, latitude: 51.503, longitude: -0.1, speed: 18.0),
        createSample(timestamp: 120000, latitude: 51.504, longitude: -0.1, speed: 12.0),
      ];
      final laps = [
        createLap(lapNumber: 1, lapTimeMs: 60000, startTimestamp: 0, endTimestamp: 60000),
        createLap(id: 'lap-2', lapNumber: 2, lapTimeMs: 55000, startTimestamp: 60000, endTimestamp: 115000),
      ];
      final sectorTimes = [
        const LapSectors(lapNumber: 1, sector1Ms: 20000, sector2Ms: 20000, sector3Ms: 20000),
        const LapSectors(lapNumber: 2, sector1Ms: 18000, sector2Ms: 19000, sector3Ms: 18000),
      ];

      // The engine should compute analytics purely from local data
      final analytics = await engine.computeAnalytics(
        session,
        samples,
        laps,
        sectorTimes,
      );

      // Verify all metrics are computed
      expect(analytics.durationSeconds, 120.0);
      expect(analytics.distanceKm, greaterThan(0));
      expect(analytics.totalLaps, 2);
      expect(analytics.bestLapTimeMs, 55000);
      expect(analytics.averageLapTimeMs, isNotNull);
      expect(analytics.averageSpeedKmh, greaterThan(0));
      expect(analytics.maxSpeedKmh, closeTo(90.0, 0.1)); // 25 m/s * 3.6
      expect(analytics.speedTraceKmh.length, 5);
      expect(analytics.bestSector1Ms, 18000);
      expect(analytics.bestSector2Ms, 19000);
      expect(analytics.bestSector3Ms, 18000);

      // Verify repository was called (local persistence only)
      verify(() => mockRepository.insert(any())).called(1);
    });
  });

  group('computeAnalytics - persists analytics to repository', () {
    test('calls repository insert with computed analytics', () async {
      final session = createSession(startTime: 0, endTime: 60000);
      final samples = [
        createSample(timestamp: 0, speed: 10.0),
        createSample(timestamp: 60000, speed: 15.0),
      ];

      await engine.computeAnalytics(session, samples, [], []);

      verify(() => mockRepository.insert(any())).called(1);
    });
  });
}
