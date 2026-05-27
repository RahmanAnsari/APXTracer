/// Represents a continuous recording period from start to stop.
class Session {
  final String id;

  /// User-defined session name. Null until the user renames it; the UI should
  /// fall back to displaying the formatted [startTime] when this is null.
  final String? name;

  final int startTime; // Unix epoch ms
  final int? endTime; // Unix epoch ms
  final int? durationMs;
  final String? trackId;

  const Session({
    required this.id,
    this.name,
    required this.startTime,
    this.endTime,
    this.durationMs,
    this.trackId,
  });

  /// Serializes this session to a map for database storage.
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
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
      name: map['name'] as String?,
      startTime: map['start_time'] as int,
      endTime: map['end_time'] as int?,
      durationMs: map['duration_ms'] as int?,
      trackId: map['track_id'] as String?,
    );
  }
}
