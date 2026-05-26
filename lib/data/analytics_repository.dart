import 'package:sqflite_sqlcipher/sqflite.dart';

import '../models/session_analytics.dart';
import 'database_helper.dart';

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
