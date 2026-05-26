import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:mocktail/mocktail.dart';

import 'package:apx_tracer/data/session_repository.dart';
import 'package:apx_tracer/data/track_repository.dart';
import 'package:apx_tracer/models/track.dart';
import 'package:apx_tracer/providers/track_provider.dart';

// --- Mocks ---

class MockTrackRepository extends Mock implements TrackRepository {}

class MockSessionRepository extends Mock implements SessionRepository {}

// --- Fakes ---

class FakeTrack extends Fake implements Track {}

void main() {
  late MockTrackRepository mockTrackRepo;
  late MockSessionRepository mockSessionRepo;

  setUpAll(() {
    registerFallbackValue(FakeTrack());
  });

  setUp(() {
    mockTrackRepo = MockTrackRepository();
    mockSessionRepo = MockSessionRepository();
  });

  group('validateTrackName', () {
    test('accepts names with 1 character', () {
      expect(validateTrackName('A'), isNull);
    });

    test('accepts names with exactly 50 characters', () {
      final name = 'A' * 50;
      expect(validateTrackName(name), isNull);
    });

    test('accepts names between 1 and 50 characters', () {
      expect(validateTrackName('Silverstone GP'), isNull);
      expect(validateTrackName('My Track'), isNull);
      expect(validateTrackName('A' * 25), isNull);
    });

    test('rejects empty string', () {
      final result = validateTrackName('');
      expect(result, isNotNull);
      expect(result, contains('1 and 50'));
    });

    test('rejects null', () {
      final result = validateTrackName(null);
      expect(result, isNotNull);
      expect(result, contains('1 and 50'));
    });

    test('rejects names longer than 50 characters', () {
      final name = 'A' * 51;
      final result = validateTrackName(name);
      expect(result, isNotNull);
      expect(result, contains('1 and 50'));
    });
  });

  group('TrackNotifier', () {
    late TrackNotifier notifier;

    setUp(() {
      when(() => mockTrackRepo.getAll()).thenAnswer((_) async => []);
      notifier = TrackNotifier(
        trackRepository: mockTrackRepo,
        sessionRepository: mockSessionRepo,
      );
    });

    group('renameTrack', () {
      test('succeeds with valid name (1-50 chars)', () async {
        final track = Track(
          id: 'track-1',
          name: 'Old Name',
          polyline: [const LatLng(51.5, -0.1), const LatLng(51.6, -0.2)],
          startFinish: const LatLng(51.5, -0.1),
          lastDriven: 1700000000000,
        );

        when(() => mockTrackRepo.getById('track-1'))
            .thenAnswer((_) async => track);
        when(() => mockTrackRepo.update(any())).thenAnswer((_) async {});
        when(() => mockTrackRepo.getAll()).thenAnswer((_) async => [track]);

        final result = await notifier.renameTrack('track-1', 'New Name');

        expect(result.success, isTrue);
        expect(result.error, isNull);
        verify(() => mockTrackRepo.update(any())).called(1);
      });

      test('returns error and retains previous name for empty name', () async {
        final result = await notifier.renameTrack('track-1', '');

        expect(result.success, isFalse);
        expect(result.error, isNotNull);
        expect(result.error, contains('1 and 50'));

        // Should NOT call update on the repository
        verifyNever(() => mockTrackRepo.update(any()));
      });

      test('returns error and retains previous name for name > 50 chars',
          () async {
        final longName = 'A' * 51;

        final result = await notifier.renameTrack('track-1', longName);

        expect(result.success, isFalse);
        expect(result.error, isNotNull);
        expect(result.error, contains('1 and 50'));

        // Should NOT call update on the repository
        verifyNever(() => mockTrackRepo.update(any()));
      });

      test('returns error when track not found', () async {
        when(() => mockTrackRepo.getById('non-existent'))
            .thenAnswer((_) async => null);

        final result =
            await notifier.renameTrack('non-existent', 'Valid Name');

        expect(result.success, isFalse);
        expect(result.error, contains('not found'));
      });

      test('succeeds with exactly 1 character name', () async {
        final track = Track(
          id: 'track-1',
          name: 'Old Name',
          polyline: [const LatLng(51.5, -0.1), const LatLng(51.6, -0.2)],
          startFinish: const LatLng(51.5, -0.1),
          lastDriven: 1700000000000,
        );

        when(() => mockTrackRepo.getById('track-1'))
            .thenAnswer((_) async => track);
        when(() => mockTrackRepo.update(any())).thenAnswer((_) async {});
        when(() => mockTrackRepo.getAll()).thenAnswer((_) async => [track]);

        final result = await notifier.renameTrack('track-1', 'X');

        expect(result.success, isTrue);
      });

      test('succeeds with exactly 50 character name', () async {
        final track = Track(
          id: 'track-1',
          name: 'Old Name',
          polyline: [const LatLng(51.5, -0.1), const LatLng(51.6, -0.2)],
          startFinish: const LatLng(51.5, -0.1),
          lastDriven: 1700000000000,
        );

        when(() => mockTrackRepo.getById('track-1'))
            .thenAnswer((_) async => track);
        when(() => mockTrackRepo.update(any())).thenAnswer((_) async {});
        when(() => mockTrackRepo.getAll()).thenAnswer((_) async => [track]);

        final name50 = 'A' * 50;
        final result = await notifier.renameTrack('track-1', name50);

        expect(result.success, isTrue);
      });
    });
  });
}
