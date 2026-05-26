/// A single GPS telemetry data point captured during a session.
class GpsSample {
  final int timestamp; // Unix epoch ms
  final double latitude;
  final double longitude;
  final double? altitude; // meters
  final double? speed; // m/s
  final double? heading; // degrees 0-360
  final double? accuracy; // meters
  final bool isLowAccuracy; // accuracy > 50m

  const GpsSample({
    required this.timestamp,
    required this.latitude,
    required this.longitude,
    this.altitude,
    this.speed,
    this.heading,
    this.accuracy,
    this.isLowAccuracy = false,
  });

  /// Serializes this GPS sample to a map for database storage.
  Map<String, dynamic> toMap() {
    return {
      'timestamp': timestamp,
      'latitude': latitude,
      'longitude': longitude,
      'altitude': altitude,
      'speed': speed,
      'heading': heading,
      'accuracy': accuracy,
      'is_low_accuracy': isLowAccuracy ? 1 : 0,
    };
  }

  /// Creates a [GpsSample] from a database row map.
  factory GpsSample.fromMap(Map<String, dynamic> map) {
    return GpsSample(
      timestamp: map['timestamp'] as int,
      latitude: (map['latitude'] as num).toDouble(),
      longitude: (map['longitude'] as num).toDouble(),
      altitude: map['altitude'] != null
          ? (map['altitude'] as num).toDouble()
          : null,
      speed: map['speed'] != null ? (map['speed'] as num).toDouble() : null,
      heading:
          map['heading'] != null ? (map['heading'] as num).toDouble() : null,
      accuracy:
          map['accuracy'] != null ? (map['accuracy'] as num).toDouble() : null,
      isLowAccuracy: map['is_low_accuracy'] == 1,
    );
  }
}
