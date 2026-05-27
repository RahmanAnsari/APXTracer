/// Represents a single lap within a Session.
///
/// A lap is either complete (crossed start/finish twice) or incomplete
/// (crossed start/finish once but the session ended before the next crossing).
class Lap {
  final String id;
  final String sessionId;
  final String trackId;
  final int lapNumber;
  final int startTimestamp; // Unix epoch ms
  final int endTimestamp; // Unix epoch ms
  final int lapTimeMs;
  final int? sector1Ms;
  final int? sector2Ms;
  final int? sector3Ms;
  final bool isBestLap;

  /// True when the driver crossed the start/finish line but the session ended
  /// before they completed the lap. Displayed as "Returned to pit".
  /// Incomplete laps are never eligible for best-lap.
  final bool isIncomplete;

  const Lap({
    required this.id,
    required this.sessionId,
    required this.trackId,
    required this.lapNumber,
    required this.startTimestamp,
    required this.endTimestamp,
    required this.lapTimeMs,
    this.sector1Ms,
    this.sector2Ms,
    this.sector3Ms,
    this.isBestLap = false,
    this.isIncomplete = false,
  });

  /// Serializes this lap to a map for database storage.
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'session_id': sessionId,
      'track_id': trackId,
      'lap_number': lapNumber,
      'start_timestamp': startTimestamp,
      'end_timestamp': endTimestamp,
      'lap_time_ms': lapTimeMs,
      'sector1_ms': sector1Ms,
      'sector2_ms': sector2Ms,
      'sector3_ms': sector3Ms,
      'is_best_lap': isBestLap ? 1 : 0,
      'is_incomplete': isIncomplete ? 1 : 0,
    };
  }

  /// Creates a [Lap] from a database row map.
  factory Lap.fromMap(Map<String, dynamic> map) {
    return Lap(
      id: map['id'] as String,
      sessionId: map['session_id'] as String,
      trackId: map['track_id'] as String,
      lapNumber: map['lap_number'] as int,
      startTimestamp: map['start_timestamp'] as int,
      endTimestamp: map['end_timestamp'] as int,
      lapTimeMs: map['lap_time_ms'] as int,
      sector1Ms: map['sector1_ms'] != null ? map['sector1_ms'] as int : null,
      sector2Ms: map['sector2_ms'] != null ? map['sector2_ms'] as int : null,
      sector3Ms: map['sector3_ms'] != null ? map['sector3_ms'] as int : null,
      isBestLap: map['is_best_lap'] == 1,
      isIncomplete: map['is_incomplete'] == 1,
    );
  }
}
