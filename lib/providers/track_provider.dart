import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/database_helper.dart';
import '../data/session_repository.dart';
import '../data/track_repository.dart';
import '../models/session.dart';
import '../models/track.dart';
import 'session_provider.dart';

/// Provides the [TrackRepository] instance.
final trackRepositoryProvider = Provider<TrackRepository>((ref) {
  return TrackRepository(DatabaseHelper());
});

/// Provides all tracks ordered by last_driven descending (most recent first).
///
/// Validates: Requirement 7.1 - Tracks displayed ordered by last driven date descending.
/// Validates: Requirement 7.5 - All tracks private and stored locally.
final tracksProvider = FutureProvider<List<Track>>((ref) async {
  final repository = ref.watch(trackRepositoryProvider);
  return repository.getAll();
});

/// Holds the combined detail data for a single track.
class TrackDetail {
  /// The track record.
  final Track track;

  /// Sessions associated with this track, ordered by start_time descending.
  final List<Session> sessions;

  const TrackDetail({
    required this.track,
    required this.sessions,
  });
}

/// Provides full track detail including associated sessions for a given track ID.
///
/// Validates: Requirement 7.4 - Display session count and last driven date for each track.
final trackDetailProvider =
    FutureProvider.family<TrackDetail?, String>((ref, trackId) async {
  final trackRepo = ref.watch(trackRepositoryProvider);
  final sessionRepo = ref.watch(sessionRepositoryProvider);

  final track = await trackRepo.getById(trackId);
  if (track == null) return null;

  final sessions = await sessionRepo.getByTrackId(trackId);

  return TrackDetail(
    track: track,
    sessions: sessions,
  );
});

/// Result of a track rename operation.
class TrackRenameResult {
  /// Whether the rename was successful.
  final bool success;

  /// Error message if the rename failed (null on success).
  final String? error;

  const TrackRenameResult({required this.success, this.error});
}

/// Minimum allowed track name length.
const int trackNameMinLength = 1;

/// Maximum allowed track name length.
const int trackNameMaxLength = 50;

/// Validates a track name.
///
/// Returns null if valid, or an error message string if invalid.
/// Validates: Requirement 7.2 - Name between 1 and 50 characters.
/// Validates: Requirement 7.3 - Reject empty or >50 char names with error.
String? validateTrackName(String? name) {
  if (name == null || name.isEmpty) {
    return 'Track name must be between 1 and 50 characters';
  }
  if (name.length > trackNameMaxLength) {
    return 'Track name must be between 1 and 50 characters';
  }
  return null;
}

/// StateNotifier that manages track library operations.
///
/// Provides track listing (ordered by last_driven DESC) and track renaming
/// with validation (1-50 chars).
///
/// Validates: Requirements 7.1, 7.2, 7.3, 7.4, 7.5
class TrackNotifier extends StateNotifier<AsyncValue<List<Track>>> {
  final TrackRepository _trackRepository;
  final SessionRepository _sessionRepository;

  TrackNotifier({
    required TrackRepository trackRepository,
    required SessionRepository sessionRepository,
  })  : _trackRepository = trackRepository,
        _sessionRepository = sessionRepository,
        super(const AsyncValue.loading()) {
    _loadTracks();
  }

  /// Loads all tracks ordered by last_driven descending.
  Future<void> _loadTracks() async {
    state = const AsyncValue.loading();
    try {
      final tracks = await _trackRepository.getAll();
      state = AsyncValue.data(tracks);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  /// Refreshes the track list from the database.
  Future<void> refresh() async {
    await _loadTracks();
  }

  /// Renames a track after validating the new name.
  ///
  /// Returns a [TrackRenameResult] indicating success or failure.
  /// If the name is invalid (empty or >50 chars), the previous name is retained
  /// and an error message is returned.
  ///
  /// Validates: Requirement 7.2 - Accept name between 1 and 50 characters.
  /// Validates: Requirement 7.3 - Reject invalid names, retain previous name.
  Future<TrackRenameResult> renameTrack(String trackId, String newName) async {
    // Validate the new name.
    final validationError = validateTrackName(newName);
    if (validationError != null) {
      return TrackRenameResult(success: false, error: validationError);
    }

    try {
      final track = await _trackRepository.getById(trackId);
      if (track == null) {
        return const TrackRenameResult(
          success: false,
          error: 'Track not found',
        );
      }

      // Create updated track with new name.
      final updatedTrack = Track(
        id: track.id,
        name: newName,
        polyline: track.polyline,
        startFinish: track.startFinish,
        sector1Fraction: track.sector1Fraction,
        sector2Fraction: track.sector2Fraction,
        sessionCount: track.sessionCount,
        lastDriven: track.lastDriven,
      );

      await _trackRepository.update(updatedTrack);

      // Refresh the track list to reflect the change.
      await _loadTracks();

      return const TrackRenameResult(success: true);
    } catch (e) {
      return TrackRenameResult(
        success: false,
        error: 'Failed to rename track: $e',
      );
    }
  }

  /// Gets the detail for a specific track including its associated sessions.
  ///
  /// Validates: Requirement 7.4 - Display session count and last driven date.
  Future<TrackDetail?> getTrackDetail(String trackId) async {
    final track = await _trackRepository.getById(trackId);
    if (track == null) return null;

    final sessions = await _sessionRepository.getByTrackId(trackId);

    return TrackDetail(
      track: track,
      sessions: sessions,
    );
  }
}

/// Provider for the track state notifier.
///
/// Exposes the list of all tracks ordered by last_driven descending,
/// and methods for renaming tracks with validation.
final trackNotifierProvider =
    StateNotifierProvider<TrackNotifier, AsyncValue<List<Track>>>((ref) {
  final trackRepository = ref.watch(trackRepositoryProvider);
  final sessionRepository = ref.watch(sessionRepositoryProvider);

  return TrackNotifier(
    trackRepository: trackRepository,
    sessionRepository: sessionRepository,
  );
});
