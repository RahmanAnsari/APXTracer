import 'package:sqflite_sqlcipher/sqflite.dart';

import '../models/lap.dart';
import 'database_helper.dart';

/// Repository for managing [Lap] records in the local database.
///
/// Provides insert, batch insert, query by session, and delete operations.
class LapRepository {
  final DatabaseHelper _databaseHelper;

  LapRepository(this._databaseHelper);

  /// Inserts a single lap into the database.
  Future<void> insert(Lap lap) async {
    final db = await _databaseHelper.database;
    await db.insert(
      'laps',
      lap.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Inserts a batch of laps atomically within a transaction.
  Future<void> insertBatch(List<Lap> laps) async {
    if (laps.isEmpty) return;

    final db = await _databaseHelper.database;
    await db.transaction((txn) async {
      final batch = txn.batch();
      for (final lap in laps) {
        batch.insert(
          'laps',
          lap.toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      await batch.commit(noResult: true);
    });
  }

  /// Retrieves all laps for a session ordered by lap_number ascending.
  Future<List<Lap>> getBySessionId(String sessionId) async {
    final db = await _databaseHelper.database;
    final results = await db.query(
      'laps',
      where: 'session_id = ?',
      whereArgs: [sessionId],
      orderBy: 'lap_number ASC',
    );
    return results.map((map) => Lap.fromMap(map)).toList();
  }

  /// Deletes all laps for a given session.
  Future<void> deleteBySessionId(String sessionId) async {
    final db = await _databaseHelper.database;
    await db.delete(
      'laps',
      where: 'session_id = ?',
      whereArgs: [sessionId],
    );
  }
}
