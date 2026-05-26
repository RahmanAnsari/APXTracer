import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/analytics_repository.dart';
import '../data/database_helper.dart';
import '../data/lap_repository.dart';
import '../data/session_repository.dart';
import '../models/lap.dart';
import '../models/session.dart';
import '../models/session_analytics.dart';

/// Provides the [SessionRepository] instance.
final sessionRepositoryProvider = Provider<SessionRepository>((ref) {
  return SessionRepository(DatabaseHelper());
});

/// Provides the [LapRepository] instance.
final lapRepositoryProvider = Provider<LapRepository>((ref) {
  return LapRepository(DatabaseHelper());
});

/// Provides the [AnalyticsRepository] instance.
final analyticsRepositoryProvider = Provider<AnalyticsRepository>((ref) {
  return AnalyticsRepository(DatabaseHelper());
});

/// Provides all sessions in reverse chronological order (most recent first).
///
/// Validates: Requirement 8.1 - Sessions displayed in reverse chronological order.
/// Validates: Requirement 8.3 - Available offline from locally stored data.
final sessionsProvider = FutureProvider<List<Session>>((ref) async {
  final repository = ref.watch(sessionRepositoryProvider);
  return repository.getAll();
});

/// Holds the combined detail data for a single session.
class SessionDetail {
  final Session session;
  final SessionAnalytics? analytics;
  final List<Lap> laps;

  const SessionDetail({
    required this.session,
    this.analytics,
    required this.laps,
  });
}

/// Provides full session detail including analytics and laps for a given session ID.
///
/// Validates: Requirement 8.2 - Correct metrics displayed per session.
/// Validates: Requirement 8.3 - Available offline from locally stored data.
final sessionDetailProvider =
    FutureProvider.family<SessionDetail?, String>((ref, sessionId) async {
  final sessionRepo = ref.watch(sessionRepositoryProvider);
  final analyticsRepo = ref.watch(analyticsRepositoryProvider);
  final lapRepo = ref.watch(lapRepositoryProvider);

  final session = await sessionRepo.getById(sessionId);
  if (session == null) return null;

  final analytics = await analyticsRepo.getBySessionId(sessionId);
  final laps = await lapRepo.getBySessionId(sessionId);

  return SessionDetail(
    session: session,
    analytics: analytics,
    laps: laps,
  );
});
