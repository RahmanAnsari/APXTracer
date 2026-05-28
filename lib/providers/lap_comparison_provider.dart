import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/database_helper.dart';
import '../data/gps_sample_repository.dart';
import '../models/lap.dart';
import '../models/session.dart';
import 'session_provider.dart';

/// A session paired with its complete (non-partial) laps.
class SessionWithLaps {
  final Session session;
  final List<Lap> laps;
  const SessionWithLaps({required this.session, required this.laps});
}

/// A single speed data point, normalised to lap-progress fraction (0.0–1.0).
class LapSpeedPoint {
  final double progress;
  final double speedKmh;
  final double latitude;
  final double longitude;
  const LapSpeedPoint({
    required this.progress,
    required this.speedKmh,
    required this.latitude,
    required this.longitude,
  });
}

/// Equality key used as the [lapSpeedTraceProvider] family parameter.
class LapSpeedKey {
  final String sessionId;
  final int startTimestamp;
  final int endTimestamp;

  const LapSpeedKey({
    required this.sessionId,
    required this.startTimestamp,
    required this.endTimestamp,
  });

  @override
  bool operator ==(Object other) =>
      other is LapSpeedKey &&
      sessionId == other.sessionId &&
      startTimestamp == other.startTimestamp &&
      endTimestamp == other.endTimestamp;

  @override
  int get hashCode => Object.hash(sessionId, startTimestamp, endTimestamp);
}

/// All sessions for a track that contain at least one complete lap,
/// ordered by session start_time descending.
final trackSessionLapsProvider =
    FutureProvider.family<List<SessionWithLaps>, String>((ref, trackId) async {
  final sessionRepo = ref.watch(sessionRepositoryProvider);
  final lapRepo = ref.watch(lapRepositoryProvider);
  final sessions = await sessionRepo.getByTrackId(trackId);
  final result = <SessionWithLaps>[];
  for (final s in sessions) {
    final all = await lapRepo.getBySessionId(s.id);
    final complete = all.where((l) => !l.isIncomplete).toList();
    if (complete.isNotEmpty) {
      result.add(SessionWithLaps(session: s, laps: complete));
    }
  }
  return result;
});

/// Speed trace for a single lap, normalised to lap-progress fraction.
/// GPS samples are filtered to [startTimestamp, endTimestamp] and
/// converted from m/s to km/h.
final lapSpeedTraceProvider =
    FutureProvider.family<List<LapSpeedPoint>, LapSpeedKey>((ref, key) async {
  final gpsSampleRepo = GpsSampleRepository(DatabaseHelper());
  final all = await gpsSampleRepo.getBySessionId(key.sessionId);
  final duration = key.endTimestamp - key.startTimestamp;
  if (duration <= 0) return [];

  return all
      .where((s) =>
          s.timestamp >= key.startTimestamp &&
          s.timestamp <= key.endTimestamp &&
          s.speed != null)
      .map((s) => LapSpeedPoint(
            progress: (s.timestamp - key.startTimestamp) / duration,
            speedKmh: s.speed! * 3.6,
            latitude: s.latitude,
            longitude: s.longitude,
          ))
      .toList();
});
