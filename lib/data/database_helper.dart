import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';

/// Singleton helper for managing the SQLCipher-encrypted local database.
///
/// On first launch, generates a random 256-bit encryption key and stores it
/// in flutter_secure_storage. On subsequent launches, retrieves the key and
/// opens the database with SQLCipher encryption.
class DatabaseHelper {
  static const String _dbName = 'apx_tracer.db';
  static const int _dbVersion = 4;
  static const String _encryptionKeyStorageKey = 'apx_tracer_db_encryption_key';

  static DatabaseHelper? _instance;
  static Database? _database;

  final FlutterSecureStorage _secureStorage;

  DatabaseHelper._internal(this._secureStorage);

  /// Returns the singleton instance of [DatabaseHelper].
  ///
  /// Optionally accepts a [FlutterSecureStorage] for testing purposes.
  factory DatabaseHelper({FlutterSecureStorage? secureStorage}) {
    _instance ??= DatabaseHelper._internal(
      secureStorage ?? const FlutterSecureStorage(),
    );
    return _instance!;
  }

  /// Resets the singleton instance. Used for testing only.
  static void resetInstance() {
    _instance = null;
    _database = null;
  }

  /// Returns the open database instance, initializing it if necessary.
  Future<Database> get database async {
    if (_database != null && _database!.isOpen) {
      return _database!;
    }
    _database = await _initDatabase();
    return _database!;
  }

  /// Initializes the database with SQLCipher encryption.
  Future<Database> _initDatabase() async {
    final documentsDir = await getApplicationDocumentsDirectory();
    final dbPath = '${documentsDir.path}/$_dbName';
    final encryptionKey = await _getOrCreateEncryptionKey();

    return await openDatabase(
      dbPath,
      version: _dbVersion,
      password: encryptionKey,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
      onConfigure: _onConfigure,
    );
  }

  /// Retrieves the encryption key from secure storage, or generates and
  /// stores a new one if none exists.
  Future<String> _getOrCreateEncryptionKey() async {
    String? key = await _secureStorage.read(key: _encryptionKeyStorageKey);
    if (key == null) {
      key = _generateEncryptionKey();
      await _secureStorage.write(key: _encryptionKeyStorageKey, value: key);
    }
    return key;
  }

  /// Generates a random 256-bit (32-byte) encryption key as a hex string.
  String _generateEncryptionKey() {
    final random = Random.secure();
    final bytes = List<int>.generate(32, (_) => random.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  /// Configures the database connection (enables foreign keys).
  Future<void> _onConfigure(Database db) async {
    await db.execute('PRAGMA foreign_keys = ON');
  }

  /// Creates all tables and indexes on first database creation.
  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE sessions (
        id TEXT PRIMARY KEY,
        name TEXT,
        start_time INTEGER NOT NULL,
        end_time INTEGER,
        duration_ms INTEGER,
        track_id TEXT,
        created_at INTEGER NOT NULL,
        FOREIGN KEY (track_id) REFERENCES tracks(id)
      )
    ''');

    await db.execute('''
      CREATE TABLE gps_samples (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        session_id TEXT NOT NULL,
        timestamp INTEGER NOT NULL,
        latitude REAL NOT NULL,
        longitude REAL NOT NULL,
        altitude REAL,
        speed REAL,
        heading REAL,
        accuracy REAL,
        is_low_accuracy INTEGER DEFAULT 0,
        FOREIGN KEY (session_id) REFERENCES sessions(id)
      )
    ''');

    await db.execute(
      'CREATE INDEX idx_samples_session ON gps_samples(session_id, timestamp)',
    );

    await db.execute('''
      CREATE TABLE tracks (
        id TEXT PRIMARY KEY,
        name TEXT,
        polyline TEXT NOT NULL,
        start_lat REAL NOT NULL,
        start_lng REAL NOT NULL,
        sector1_fraction REAL NOT NULL,
        sector2_fraction REAL NOT NULL,
        length_m REAL DEFAULT 0,
        session_count INTEGER DEFAULT 1,
        last_driven INTEGER NOT NULL,
        created_at INTEGER NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE laps (
        id TEXT PRIMARY KEY,
        session_id TEXT NOT NULL,
        track_id TEXT NOT NULL,
        lap_number INTEGER NOT NULL,
        start_timestamp INTEGER NOT NULL,
        end_timestamp INTEGER NOT NULL,
        lap_time_ms INTEGER NOT NULL,
        sector1_ms INTEGER,
        sector2_ms INTEGER,
        sector3_ms INTEGER,
        is_best_lap INTEGER DEFAULT 0,
        is_incomplete INTEGER DEFAULT 0,
        FOREIGN KEY (session_id) REFERENCES sessions(id),
        FOREIGN KEY (track_id) REFERENCES tracks(id)
      )
    ''');

    await db.execute(
      'CREATE INDEX idx_laps_session ON laps(session_id)',
    );

    await db.execute('''
      CREATE TABLE session_analytics (
        session_id TEXT PRIMARY KEY,
        duration_seconds REAL NOT NULL,
        distance_km REAL NOT NULL,
        total_laps INTEGER NOT NULL,
        best_lap_time_ms INTEGER,
        average_lap_time_ms INTEGER,
        average_speed_kmh REAL NOT NULL,
        max_speed_kmh REAL NOT NULL,
        speed_trace TEXT NOT NULL,
        best_sector1_ms INTEGER,
        best_sector2_ms INTEGER,
        best_sector3_ms INTEGER,
        FOREIGN KEY (session_id) REFERENCES sessions(id)
      )
    ''');
  }

  /// Handles database schema migrations for future versions.
  ///
  /// Each version upgrade is applied sequentially so that upgrading from
  /// any prior version to the current version works correctly.
  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    // Migration strategy: apply each version's changes sequentially.
    if (oldVersion < 2) {
      await db.execute(
        'ALTER TABLE laps ADD COLUMN is_incomplete INTEGER DEFAULT 0',
      );
    }
    if (oldVersion < 3) {
      await db.execute(
        'ALTER TABLE tracks ADD COLUMN length_m REAL DEFAULT 0',
      );
    }
    if (oldVersion < 4) {
      await db.execute(
        'ALTER TABLE sessions ADD COLUMN name TEXT',
      );
    }
  }

  /// Closes the database connection.
  Future<void> close() async {
    if (_database != null && _database!.isOpen) {
      await _database!.close();
      _database = null;
    }
  }

  /// Deletes all telemetry data from the database.
  ///
  /// Removes all records from sessions, gps_samples, tracks, laps, and
  /// session_analytics tables atomically within a transaction.
  Future<void> deleteAllData() async {
    final db = await database;
    await db.transaction((txn) async {
      // Delete in order respecting foreign key constraints
      await txn.delete('session_analytics');
      await txn.delete('laps');
      await txn.delete('gps_samples');
      await txn.delete('sessions');
      await txn.delete('tracks');
    });
  }
}
