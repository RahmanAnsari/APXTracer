import '../kalman/kalman_models.dart';

/// Warning emitted when IMU sample rate drops below 50 Hz.
class ImuDegradedWarning {
  final double measuredRateHz;
  final DateTime timestamp;

  const ImuDegradedWarning({
    required this.measuredRateHz,
    required this.timestamp,
  });
}

/// Thrown when IMU hardware is not available or permission is denied.
class ImuUnavailableException implements Exception {
  final String message;
  const ImuUnavailableException(this.message);

  @override
  String toString() => 'ImuUnavailableException: $message';
}

/// Abstract IMU service for accelerometer and gyroscope data acquisition.
/// Mirrors the GpsService pattern for testability via dependency injection.
abstract class ImuService {
  /// Checks whether the device has both accelerometer and gyroscope hardware.
  /// Returns true if both sensors are available.
  Future<bool> checkAvailability();

  /// Starts streaming IMU data at the highest available rate (targeting 100 Hz).
  /// Returns a broadcast stream of ImuData measurements.
  /// Throws [ImuUnavailableException] if sensors are not accessible.
  Stream<ImuData> startStreaming();

  /// Stops streaming and releases hardware resources.
  Future<void> stopStreaming();

  /// Stream that emits warnings when sample rate degrades below 50 Hz.
  Stream<ImuDegradedWarning> get warnings;
}
