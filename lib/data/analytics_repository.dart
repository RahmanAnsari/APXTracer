import 'package:sqflite_sqlcipher/sqflite.dart';

import '../models/session_analytics.dart';
import 'database_helper.dart';

/// Aggregated statistics across all recorded sessions.
class LifetimeStats {
  final double totalKm;
  final double totalSeconds;
  final int totalSessions;
  final int totalTracks;

  const LifetimeStats({
    required this.totalKm,
    required this.totalSeconds,
    required this.totalSessions,
    required this.totalTracks,
  });
}

/// Repository for managing [SessionAnalytics] records in the local database.
///
/// Provides insert, query by session, and delete operations for cached
/// analytics computation results.
class AnalyticsRepository {
  final DatabaseHelper _databaseHelper;

  AnalyticsRepository(this._databaseHelper);

  /// Inserts or replaces analytics for a session.
  Future<void> insert(SessionAnalytics analytics) async {
    final db = await _databaseHelper.database;
    await db.insert(
      'session_analytics',
      analytics.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Retrieves analytics for a session. Returns null if not found.
  Future<SessionAnalytics?> getBySessionId(String sessionId) async {
    final db = await _databaseHelper.database;
    final results = await db.query(
      'session_analytics',
      where: 'session_id = ?',
      whereArgs: [sessionId],
      limit: 1,
    );
    if (results.isEmpty) return null;
    return SessionAnalytics.fromMap(results.first);
  }

  /// Returns aggregated lifetime stats across all sessions in one query.
  ///
  /// - [totalKm]: sum of distance_km from all processed sessions.
  /// - [totalSeconds]: sum of duration_seconds from all processed sessions.
  /// - [totalSessions]: count of all session rows.
  /// - [totalTracks]: count of distinct non-null track_ids.
  Future<LifetimeStats> getLifetimeStats() async {
    final db = await _databaseHelper.database;
    final rows = await db.rawQuery('''
      SELECT
        COALESCE(SUM(a.distance_km), 0)    AS total_km,
        COALESCE(SUM(a.duration_seconds), 0) AS total_seconds,
        COUNT(DISTINCT s.id)               AS total_sessions,
        COUNT(DISTINCT s.track_id)         AS total_tracks
      FROM sessions s
      LEFT JOIN session_analytics a ON a.session_id = s.id
    ''');
    final row = rows.first;
    return LifetimeStats(
      totalKm: (row['total_km'] as num).toDouble(),
      totalSeconds: (row['total_seconds'] as num).toDouble(),
      totalSessions: row['total_sessions'] as int,
      totalTracks: row['total_tracks'] as int,
    );
  }

  /// Deletes analytics for a given session.
  Future<void> deleteBySessionId(String sessionId) async {
    final db = await _databaseHelper.database;
    await db.delete(
      'session_analytics',
      where: 'session_id = ?',
      whereArgs: [sessionId],
    );
  }
}
