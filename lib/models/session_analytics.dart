import 'dart:convert';

/// Cached computation results for a session's performance metrics.
class SessionAnalytics {
  final String sessionId;
  final double durationSeconds;
  final double distanceKm; // 2 decimal places
  final int totalLaps;
  final int? bestLapTimeMs; // null if no laps
  final int? averageLapTimeMs; // null if no laps
  final double averageSpeedKmh; // 1 decimal place
  final double maxSpeedKmh; // 1 decimal place
  final List<double> speedTraceKmh; // one per sample
  final int? bestSector1Ms;
  final int? bestSector2Ms;
  final int? bestSector3Ms;

  const SessionAnalytics({
    required this.sessionId,
    required this.durationSeconds,
    required this.distanceKm,
    required this.totalLaps,
    this.bestLapTimeMs,
    this.averageLapTimeMs,
    required this.averageSpeedKmh,
    required this.maxSpeedKmh,
    required this.speedTraceKmh,
    this.bestSector1Ms,
    this.bestSector2Ms,
    this.bestSector3Ms,
  });

  /// Serializes this analytics object to a map for database storage.
  /// The speed trace is JSON-encoded as a list of doubles.
  Map<String, dynamic> toMap() {
    return {
      'session_id': sessionId,
      'duration_seconds': durationSeconds,
      'distance_km': distanceKm,
      'total_laps': totalLaps,
      'best_lap_time_ms': bestLapTimeMs,
      'average_lap_time_ms': averageLapTimeMs,
      'average_speed_kmh': averageSpeedKmh,
      'max_speed_kmh': maxSpeedKmh,
      'speed_trace': jsonEncode(speedTraceKmh),
      'best_sector1_ms': bestSector1Ms,
      'best_sector2_ms': bestSector2Ms,
      'best_sector3_ms': bestSector3Ms,
    };
  }

  /// Creates a [SessionAnalytics] from a database row map.
  /// The speed trace is decoded from a JSON string.
  factory SessionAnalytics.fromMap(Map<String, dynamic> map) {
    final speedTraceJson =
        jsonDecode(map['speed_trace'] as String) as List<dynamic>;
    final speedTrace =
        speedTraceJson.map((v) => (v as num).toDouble()).toList();

    return SessionAnalytics(
      sessionId: map['session_id'] as String,
      durationSeconds: (map['duration_seconds'] as num).toDouble(),
      distanceKm: (map['distance_km'] as num).toDouble(),
      totalLaps: map['total_laps'] as int,
      bestLapTimeMs: map['best_lap_time_ms'] != null
          ? map['best_lap_time_ms'] as int
          : null,
      averageLapTimeMs: map['average_lap_time_ms'] != null
          ? map['average_lap_time_ms'] as int
          : null,
      averageSpeedKmh: (map['average_speed_kmh'] as num).toDouble(),
      maxSpeedKmh: (map['max_speed_kmh'] as num).toDouble(),
      speedTraceKmh: speedTrace,
      bestSector1Ms: map['best_sector1_ms'] != null
          ? map['best_sector1_ms'] as int
          : null,
      bestSector2Ms: map['best_sector2_ms'] != null
          ? map['best_sector2_ms'] as int
          : null,
      bestSector3Ms: map['best_sector3_ms'] != null
          ? map['best_sector3_ms'] as int
          : null,
    );
  }
}
