/// Represents a continuous recording period from start to stop.
class Session {
  final String id;
  final int startTime; // Unix epoch ms
  final int? endTime; // Unix epoch ms
  final int? durationMs;
  final String? trackId;

  const Session({
    required this.id,
    required this.startTime,
    this.endTime,
    this.durationMs,
    this.trackId,
  });

  /// Serializes this session to a map for database storage.
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'start_time': startTime,
      'end_time': endTime,
      'duration_ms': durationMs,
      'track_id': trackId,
      'created_at': startTime,
    };
  }

  /// Creates a [Session] from a database row map.
  factory Session.fromMap(Map<String, dynamic> map) {
    return Session(
      id: map['id'] as String,
      startTime: map['start_time'] as int,
      endTime: map['end_time'] != null ? map['end_time'] as int : null,
      durationMs:
          map['duration_ms'] != null ? map['duration_ms'] as int : null,
      trackId: map['track_id'] != null ? map['track_id'] as String : null,
    );
  }
}
