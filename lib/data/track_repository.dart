import 'dart:math';

import 'package:sqflite_sqlcipher/sqflite.dart';

import '../models/track.dart';
import 'database_helper.dart';

/// Repository for managing [Track] records in the local database.
///
/// Provides CRUD operations, spatial queries using Haversine distance,
/// and ordering by last_driven descending.
class TrackRepository {
  final DatabaseHelper _databaseHelper;

  /// Earth radius in meters for Haversine calculations.
  static const double _earthRadiusMeters = 6371000;

  /// Maximum distance in meters for findNearby matching.
  static const double _nearbyThresholdMeters = 50;

  TrackRepository(this._databaseHelper);

  /// Inserts a new track into the database.
  Future<void> insert(Track track) async {
    final db = await _databaseHelper.database;
    await db.insert(
      'tracks',
      track.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Retrieves a track by its ID. Returns null if not found.
  Future<Track?> getById(String id) async {
    final db = await _databaseHelper.database;
    final results = await db.query(
      'tracks',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (results.isEmpty) return null;
    return Track.fromMap(results.first);
  }

  /// Retrieves all tracks ordered by last_driven descending (most recent first).
  ///
  /// The returned [Track.sessionCount] is derived from the actual number of
  /// sessions linked to each track in the DB, not the stored counter — so it
  /// stays accurate even when sessions are deleted or reassigned.
  Future<List<Track>> getAll() async {
    final db = await _databaseHelper.database;
    final results = await db.rawQuery('''
      SELECT t.*, COUNT(s.id) AS real_session_count
      FROM tracks t
      LEFT JOIN sessions s ON s.track_id = t.id
      GROUP BY t.id
      ORDER BY t.last_driven DESC
    ''');
    return results.map((row) {
      final corrected = Map<String, dynamic>.from(row);
      corrected['session_count'] = (row['real_session_count'] as int?) ?? 0;
      return Track.fromMap(corrected);
    }).toList();
  }

  /// Finds tracks whose start/finish point is within 50 meters of the
  /// given coordinates using the Haversine formula.
  ///
  /// Loads all tracks and computes the distance in-memory since SQLite
  /// does not support trigonometric functions natively.
  Future<List<Track>> findNearby(double lat, double lng) async {
    final allTracks = await getAll();
    final nearbyTracks = <Track>[];

    for (final track in allTracks) {
      final distance = _haversineDistance(
        lat,
        lng,
        track.startFinish.latitude,
        track.startFinish.longitude,
      );
      if (distance <= _nearbyThresholdMeters) {
        nearbyTracks.add(track);
      }
    }

    return nearbyTracks;
  }

  /// Updates an existing track record.
  ///
  /// Typically used for updating name, session_count, and last_driven.
  Future<void> update(Track track) async {
    final db = await _databaseHelper.database;
    await db.update(
      'tracks',
      track.toMap(),
      where: 'id = ?',
      whereArgs: [track.id],
    );
  }

  /// Deletes a track by its ID.
  Future<void> delete(String id) async {
    final db = await _databaseHelper.database;
    await db.delete(
      'tracks',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Computes the Haversine distance in meters between two geographic points.
  double _haversineDistance(
    double lat1,
    double lng1,
    double lat2,
    double lng2,
  ) {
    final dLat = _toRadians(lat2 - lat1);
    final dLng = _toRadians(lng2 - lng1);

    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_toRadians(lat1)) *
            cos(_toRadians(lat2)) *
            sin(dLng / 2) *
            sin(dLng / 2);

    final c = 2 * atan2(sqrt(a), sqrt(1 - a));

    return _earthRadiusMeters * c;
  }

  /// Converts degrees to radians.
  double _toRadians(double degrees) {
    return degrees * pi / 180;
  }
}
