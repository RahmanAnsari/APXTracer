import 'package:sqflite_sqlcipher/sqflite.dart';

import '../models/session.dart';
import 'database_helper.dart';

/// Repository for managing [Session] records in the local database.
///
/// Provides CRUD operations with sessions ordered by start_time descending.
class SessionRepository {
  final DatabaseHelper _databaseHelper;

  SessionRepository(this._databaseHelper);

  /// Inserts a new session into the database.
  Future<void> insert(Session session) async {
    final db = await _databaseHelper.database;
    await db.insert(
      'sessions',
      session.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Retrieves a session by its ID. Returns null if not found.
  Future<Session?> getById(String id) async {
    final db = await _databaseHelper.database;
    final results = await db.query(
      'sessions',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (results.isEmpty) return null;
    return Session.fromMap(results.first);
  }

  /// Retrieves all sessions ordered by start_time descending (most recent first).
  Future<List<Session>> getAll() async {
    final db = await _databaseHelper.database;
    final results = await db.query(
      'sessions',
      orderBy: 'start_time DESC',
    );
    return results.map((map) => Session.fromMap(map)).toList();
  }

  /// Updates an existing session record.
  Future<void> update(Session session) async {
    final db = await _databaseHelper.database;
    await db.update(
      'sessions',
      session.toMap(),
      where: 'id = ?',
      whereArgs: [session.id],
    );
  }

  /// Retrieves all sessions associated with a given track ID,
  /// ordered by start_time descending (most recent first).
  Future<List<Session>> getByTrackId(String trackId) async {
    final db = await _databaseHelper.database;
    final results = await db.query(
      'sessions',
      where: 'track_id = ?',
      whereArgs: [trackId],
      orderBy: 'start_time DESC',
    );
    return results.map((map) => Session.fromMap(map)).toList();
  }

  /// Updates the user-defined name for a session.
  ///
  /// Pass an empty string or null to clear a previously set name.
  Future<void> rename(String id, String? name) async {
    final db = await _databaseHelper.database;
    await db.update(
      'sessions',
      {'name': name},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Deletes a session and all associated data (samples, laps, analytics)
  /// atomically within a transaction.
  Future<void> delete(String id) async {
    final db = await _databaseHelper.database;
    await db.transaction((txn) async {
      await txn.delete(
        'session_analytics',
        where: 'session_id = ?',
        whereArgs: [id],
      );
      await txn.delete(
        'laps',
        where: 'session_id = ?',
        whereArgs: [id],
      );
      await txn.delete(
        'gps_samples',
        where: 'session_id = ?',
        whereArgs: [id],
      );
      await txn.delete(
        'sessions',
        where: 'id = ?',
        whereArgs: [id],
      );
    });
  }
}
