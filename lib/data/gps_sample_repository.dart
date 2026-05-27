import 'package:sqflite_sqlcipher/sqflite.dart';

import '../models/gps_sample.dart';
import 'database_helper.dart';

/// Repository for managing [GpsSample] records in the local database.
///
/// Optimized for high-volume batch inserts during recording sessions
/// and sequential reads ordered by timestamp.
class GpsSampleRepository {
  final DatabaseHelper _databaseHelper;

  GpsSampleRepository(this._databaseHelper);

  /// Inserts a batch of GPS samples atomically using a database transaction
  /// and batch operations for efficiency.
  ///
  /// Each sample is associated with the given [sessionId].
  /// Note: GpsSample.toMap() does not include session_id, so it is added here.
  Future<void> batchInsert(String sessionId, List<GpsSample> samples) async {
    if (samples.isEmpty) return;

    final db = await _databaseHelper.database;
    await db.transaction((txn) async {
      final batch = txn.batch();
      for (final sample in samples) {
        final map = sample.toMap();
        map['session_id'] = sessionId;
        batch.insert('gps_samples', map);
      }
      await batch.commit(noResult: true);
    });
  }

  /// Retrieves all GPS samples for a session ordered by timestamp ascending.
  Future<List<GpsSample>> getBySessionId(String sessionId) async {
    final db = await _databaseHelper.database;
    final results = await db.query(
      'gps_samples',
      where: 'session_id = ?',
      whereArgs: [sessionId],
      orderBy: 'timestamp ASC',
    );
    return results.map((map) => GpsSample.fromMap(map)).toList();
  }

  /// Returns the count of GPS samples for a given session.
  Future<int> countBySessionId(String sessionId) async {
    final db = await _databaseHelper.database;
    final result = await db.rawQuery(
      'SELECT COUNT(*) as count FROM gps_samples WHERE session_id = ?',
      [sessionId],
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }

  /// Deletes all GPS samples for a given session.
  Future<void> deleteBySessionId(String sessionId) async {
    final db = await _databaseHelper.database;
    await db.delete(
      'gps_samples',
      where: 'session_id = ?',
      whereArgs: [sessionId],
    );
  }

  /// Deletes all GPS samples for a session with timestamp strictly before
  /// [beforeTimestampMs]. Used to strip the stationary prefix recorded
  /// before physical movement begins.
  Future<void> deleteBeforeTimestamp(
    String sessionId,
    int beforeTimestampMs,
  ) async {
    final db = await _databaseHelper.database;
    await db.delete(
      'gps_samples',
      where: 'session_id = ? AND timestamp < ?',
      whereArgs: [sessionId, beforeTimestampMs],
    );
  }

  /// Deletes all GPS samples for a session with timestamp strictly after
  /// [afterTimestampMs]. Used to strip the stationary suffix recorded
  /// after the car stopped moving at the end of a session.
  Future<void> deleteAfterTimestamp(
    String sessionId,
    int afterTimestampMs,
  ) async {
    final db = await _databaseHelper.database;
    await db.delete(
      'gps_samples',
      where: 'session_id = ? AND timestamp > ?',
      whereArgs: [sessionId, afterTimestampMs],
    );
  }
}
