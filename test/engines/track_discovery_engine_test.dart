import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:mocktail/mocktail.dart';

import 'package:apx_tracer/data/session_repository.dart';
import 'package:apx_tracer/data/track_repository.dart';
import 'package:apx_tracer/engines/track_discovery/track_discovery_engine.dart';
import 'package:apx_tracer/models/gps_sample.dart';
import 'package:apx_tracer/models/session.dart';
import 'package:apx_tracer/models/track.dart';

// --- Mocks ---

class MockTrackRepository extends Mock implements TrackRepository {}

class MockSessionRepository extends Mock implements SessionRepository {}

// --- Fakes for mocktail argument matchers ---

class FakeTrack extends Fake implements Track {}

class FakeSession extends Fake implements Session {}

void main() {
  late MockTrackRepository mockTrackRepo;
  late MockSessionRepository mockSessionRepo;
  late TrackDiscoveryEngine engine;

  setUpAll(() {
    registerFallbackValue(FakeTrack());
    registerFallbackValue(FakeSession());
  });

  setUp(() {
    mockTrackRepo = MockTrackRepository();
    mockSessionRepo = MockSessionRepository();
    engine = TrackDiscoveryEngine(
      trackRepository: mockTrackRepo,
      sessionRepository: mockSessionRepo,
    );
  });

  group('computeSectors', () {
    test('returns 2 sector boundaries at 1/3 and 2/3 fractions', () {
      // A simple straight-line track with 4 equidistant points
      final track = Track(
        id: 'track-1',
        polyline: [
          LatLng(0.0, 0.0),
          LatLng(0.0, 1.0),
          LatLng(0.0, 2.0),
          LatLng(0.0, 3.0),
        ],
        startFinish: LatLng(0.0, 0.0),
        lastDriven: 1000,
      );

      final sectors = engine.computeSectors(track);

      expect(sectors.length, 2);
      expect(sectors[0].polylineFraction, closeTo(1 / 3, 0.0001));
      expect(sectors[1].polylineFraction, closeTo(2 / 3, 0.0001));
    });

    test('sector boundary points are interpolated correctly', () {
      // A straight-line track along the equator
      final track = Track(
        id: 'track-2',
        polyline: [
          LatLng(0.0, 0.0),
          LatLng(0.0, 3.0),
        ],
        startFinish: LatLng(0.0, 0.0),
        lastDriven: 1000,
      );

      final sectors = engine.computeSectors(track);

      // At 1/3 of a straight line from (0,0) to (0,3), the point should be near (0,1)
      expect(sectors[0].point.latitude, closeTo(0.0, 0.001));
      expect(sectors[0].point.longitude, closeTo(1.0, 0.001));

      // At 2/3 of a straight line from (0,0) to (0,3), the point should be near (0,2)
      expect(sectors[1].point.latitude, closeTo(0.0, 0.001));
      expect(sectors[1].point.longitude, closeTo(2.0, 0.001));
    });

    test('returns empty list when polyline has fewer than 2 points', () {
      final track = Track(
        id: 'track-3',
        polyline: [LatLng(0.0, 0.0)],
        startFinish: LatLng(0.0, 0.0),
        lastDriven: 1000,
      );

      final sectors = engine.computeSectors(track);

      expect(sectors, isEmpty);
    });

    test('works with a multi-segment polyline', () {
      // L-shaped track: go east then north
      final track = Track(
        id: 'track-4',
        polyline: [
          LatLng(0.0, 0.0),
          LatLng(0.0, 1.0), // East
          LatLng(1.0, 1.0), // North
        ],
        startFinish: LatLng(0.0, 0.0),
        lastDriven: 1000,
      );

      final sectors = engine.computeSectors(track);

      expect(sectors.length, 2);
      expect(sectors[0].polylineFraction, closeTo(1 / 3, 0.0001));
      expect(sectors[1].polylineFraction, closeTo(2 / 3, 0.0001));

      // Both points should be valid LatLng values
      expect(sectors[0].point.latitude, isNotNull);
      expect(sectors[0].point.longitude, isNotNull);
      expect(sectors[1].point.latitude, isNotNull);
      expect(sectors[1].point.longitude, isNotNull);
    });

    test('sector 1 boundary is before sector 2 boundary', () {
      final track = Track(
        id: 'track-5',
        polyline: [
          LatLng(10.0, 20.0),
          LatLng(10.5, 20.5),
          LatLng(11.0, 21.0),
          LatLng(11.5, 21.5),
          LatLng(12.0, 22.0),
        ],
        startFinish: LatLng(10.0, 20.0),
        lastDriven: 1000,
      );

      final sectors = engine.computeSectors(track);

      expect(sectors[0].polylineFraction, lessThan(sectors[1].polylineFraction));
    });
  });

  group('discoverTrack', () {
    // Helper: generates a list of GPS samples forming a closed loop
    // around a point, with the last sample close to the first.
    List<GpsSample> closedLoopSamples({int count = 25}) {
      // Create samples in a small circle around (51.5, -0.1)
      // Radius ~0.0003 degrees ≈ ~33m, so first and last are within 50m.
      final samples = <GpsSample>[];
      for (int i = 0; i < count; i++) {
        final angle = 2 * pi * i / count;
        final lat = 51.5 + 0.0003 * cos(angle);
        final lng = -0.1 + 0.0003 * sin(angle);
        samples.add(GpsSample(
          timestamp: 1000 + i * 100,
          latitude: lat,
          longitude: lng,
        ));
      }
      return samples;
    }

    // Helper: generates samples where first and last are far apart (> 50m)
    List<GpsSample> openPathSamples({int count = 25}) {
      final samples = <GpsSample>[];
      for (int i = 0; i < count; i++) {
        // Straight line going north — ~111m per 0.001 degree
        samples.add(GpsSample(
          timestamp: 1000 + i * 100,
          latitude: 51.5 + i * 0.001,
          longitude: -0.1,
        ));
      }
      return samples;
    }

    final testSession = Session(
      id: 'session-1',
      startTime: 1000,
      endTime: 5000,
      durationMs: 4000,
    );

    test('returns null when samples.length < 20 (no closed loop)', () async {
      // Only 10 samples — below the 20-sample minimum
      final samples = List.generate(
        10,
        (i) => GpsSample(
          timestamp: 1000 + i * 100,
          latitude: 51.5,
          longitude: -0.1,
        ),
      );

      final result = await engine.discoverTrack(testSession, samples);

      expect(result, isNull);
      verifyNever(() => mockTrackRepo.findNearby(any(), any()));
      verifyNever(() => mockTrackRepo.insert(any()));
      verifyNever(() => mockSessionRepo.update(any()));
    });

    test('returns null when Haversine distance between first and last > 50m',
        () async {
      final samples = openPathSamples(count: 25);

      final result = await engine.discoverTrack(testSession, samples);

      expect(result, isNull);
      verifyNever(() => mockTrackRepo.findNearby(any(), any()));
      verifyNever(() => mockTrackRepo.insert(any()));
      verifyNever(() => mockSessionRepo.update(any()));
    });

    test('detects closed loop when distance ≤ 50m AND samples ≥ 20',
        () async {
      final samples = closedLoopSamples(count: 25);

      when(() => mockTrackRepo.findNearby(any(), any()))
          .thenAnswer((_) async => []);
      when(() => mockTrackRepo.insert(any())).thenAnswer((_) async {});
      when(() => mockSessionRepo.update(any())).thenAnswer((_) async {});

      final result = await engine.discoverTrack(testSession, samples);

      expect(result, isNotNull);
      expect(result!.polyline.length, samples.length);
    });

    test('generates polyline from GPS samples', () async {
      final samples = closedLoopSamples(count: 30);

      when(() => mockTrackRepo.findNearby(any(), any()))
          .thenAnswer((_) async => []);
      when(() => mockTrackRepo.insert(any())).thenAnswer((_) async {});
      when(() => mockSessionRepo.update(any())).thenAnswer((_) async {});

      final result = await engine.discoverTrack(testSession, samples);

      expect(result, isNotNull);
      // Polyline should have one LatLng per sample
      expect(result!.polyline.length, samples.length);
      // Each polyline point should match the corresponding sample
      for (int i = 0; i < samples.length; i++) {
        expect(result.polyline[i].latitude, samples[i].latitude);
        expect(result.polyline[i].longitude, samples[i].longitude);
      }
    });

    test('matches existing track within 50m and increments sessionCount',
        () async {
      final samples = closedLoopSamples(count: 25);
      final existingTrack = Track(
        id: 'existing-track-1',
        name: 'Silverstone',
        polyline: [LatLng(51.5, -0.1), LatLng(51.501, -0.1)],
        startFinish: LatLng(51.5, -0.1),
        sessionCount: 3,
        lastDriven: 500,
      );

      when(() => mockTrackRepo.findNearby(any(), any()))
          .thenAnswer((_) async => [existingTrack]);
      when(() => mockTrackRepo.update(any())).thenAnswer((_) async {});
      when(() => mockSessionRepo.update(any())).thenAnswer((_) async {});

      final result = await engine.discoverTrack(testSession, samples);

      expect(result, isNotNull);
      expect(result!.id, 'existing-track-1');
      expect(result.sessionCount, 4); // incremented from 3

      // Verify track was updated (not inserted)
      verify(() => mockTrackRepo.update(any())).called(1);
      verifyNever(() => mockTrackRepo.insert(any()));

      // Verify session was updated with track ID
      verify(() => mockSessionRepo.update(any())).called(1);
    });

    test('creates new track when no match exists', () async {
      final samples = closedLoopSamples(count: 25);

      when(() => mockTrackRepo.findNearby(any(), any()))
          .thenAnswer((_) async => []);
      when(() => mockTrackRepo.insert(any())).thenAnswer((_) async {});
      when(() => mockSessionRepo.update(any())).thenAnswer((_) async {});

      final result = await engine.discoverTrack(testSession, samples);

      expect(result, isNotNull);
      expect(result!.sessionCount, 1);
      expect(result.sector1Fraction, closeTo(1 / 3, 0.0001));
      expect(result.sector2Fraction, closeTo(2 / 3, 0.0001));

      // Verify track was inserted (not updated)
      verify(() => mockTrackRepo.insert(any())).called(1);
      verifyNever(() => mockTrackRepo.update(any()));

      // Verify session was updated with track ID
      verify(() => mockSessionRepo.update(any())).called(1);
    });

    test('session updated with track ID when track is discovered', () async {
      final samples = closedLoopSamples(count: 25);

      when(() => mockTrackRepo.findNearby(any(), any()))
          .thenAnswer((_) async => []);
      when(() => mockTrackRepo.insert(any())).thenAnswer((_) async {});
      when(() => mockSessionRepo.update(any())).thenAnswer((_) async {});

      final result = await engine.discoverTrack(testSession, samples);

      // Capture the session that was passed to update
      final captured = verify(() => mockSessionRepo.update(captureAny()))
          .captured
          .single as Session;
      expect(captured.id, testSession.id);
      expect(captured.trackId, result!.id);
    });

    test('session not updated when no closed loop detected', () async {
      // Use fewer than 20 samples — no loop
      final samples = List.generate(
        15,
        (i) => GpsSample(
          timestamp: 1000 + i * 100,
          latitude: 51.5,
          longitude: -0.1,
        ),
      );

      final result = await engine.discoverTrack(testSession, samples);

      expect(result, isNull);
      verifyNever(() => mockSessionRepo.update(any()));
    });
  });
}
