import '../../models/gps_sample.dart';

/// Message types sent between main isolate and recording isolate.
///
/// Uses a sealed class hierarchy so that switch expressions are exhaustive.
sealed class RecordingMessage {}

/// Sent from main isolate to GPS isolate to begin capturing samples.
class StartRecording extends RecordingMessage {
  /// Target capture rate in Hz (default 10).
  final int targetHz;

  StartRecording({this.targetHz = 10});
}

/// Sent from main isolate to GPS isolate to stop capturing.
class StopRecording extends RecordingMessage {}

/// Sent from GPS isolate to main isolate with a batch of captured samples.
class GpsSampleBatch extends RecordingMessage {
  /// The batch of GPS samples captured since the last batch.
  final List<GpsSample> samples;

  GpsSampleBatch({required this.samples});
}

/// Sent from GPS isolate to main isolate when an error occurs.
class RecordingError extends RecordingMessage {
  /// Machine-readable error code.
  final String code;

  /// Human-readable error description.
  final String message;

  RecordingError({required this.code, required this.message});
}

/// Live recording state update emitted to the UI at 1 Hz.
class RecordingUpdate {
  /// Current speed in km/h.
  final double currentSpeedKmh;

  /// Time elapsed since session start.
  final Duration elapsed;

  /// Current GPS acquisition status.
  final GpsStatus gpsStatus;

  /// Total number of samples captured so far.
  final int sampleCount;

  const RecordingUpdate({
    required this.currentSpeedKmh,
    required this.elapsed,
    required this.gpsStatus,
    required this.sampleCount,
  });
}

/// GPS status indicator for the recording UI.
enum GpsStatus {
  /// Waiting for initial GPS fix.
  acquiring,

  /// Actively receiving GPS samples.
  active,

  /// GPS signal temporarily lost.
  signalLost,

  /// Location permission not granted.
  noPermission,
}

/// Thrown when GPS location permission is denied by the user.
class GpsPermissionDeniedException implements Exception {
  final String message;

  const GpsPermissionDeniedException(
      [this.message = 'GPS location permission denied']);

  @override
  String toString() => 'GpsPermissionDeniedException: $message';
}

/// Thrown when the device cannot acquire a GPS fix within the timeout period.
class GpsFixTimeoutException implements Exception {
  final Duration timeout;
  final String message;

  const GpsFixTimeoutException({
    this.timeout = const Duration(seconds: 10),
    this.message = 'Could not acquire GPS fix within timeout',
  });

  @override
  String toString() =>
      'GpsFixTimeoutException: $message (timeout: ${timeout.inSeconds}s)';
}
