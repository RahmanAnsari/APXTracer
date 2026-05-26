import 'package:apx_tracer/engines/kalman/kalman_models.dart';
import 'package:apx_tracer/models/gps_sample.dart';
import 'package:geolocator/geolocator.dart';

/// Converts a [NavState] and associated GPS metadata to a [GpsSample].
///
/// Pure function — no side effects, independently testable.
///
/// Returns `null` if the NavState produces coordinates outside valid ranges
/// (latitude not in [-90, 90] or longitude not in [-180, 180]).
GpsSample? navStateToGpsSample({
  required NavState navState,
  required double gpsAccuracy,
  required int timestampMs,
}) {
  final lat = navState.latitude;
  final lon = navState.longitude;

  // Validity check: discard out-of-range coordinates
  if (lat < -90 || lat > 90 || lon < -180 || lon > 180) {
    return null;
  }

  return GpsSample(
    timestamp: timestampMs,
    latitude: lat,
    longitude: lon,
    altitude: navState.altitude,
    speed: navState.groundSpeed,
    heading: navState.bearingDeg.clamp(0.0, 360.0),
    accuracy: gpsAccuracy,
    isLowAccuracy: gpsAccuracy > 50.0,
  );
}

/// Converts a geolocator [Position] to the filter's [GpsData] model.
///
/// Maps latitude, longitude, and altitude directly. Speed and heading are
/// set to null when negative (indicating unavailable data from the platform).
/// Accuracy defaults to 100.0 when the reported value is zero or negative.
GpsData positionToGpsData(Position position) {
  return GpsData(
    latitude: position.latitude,
    longitude: position.longitude,
    altitude: position.altitude,
    speed: position.speed >= 0 ? position.speed : null,
    heading: position.heading >= 0 ? position.heading : null,
    accuracy: position.accuracy > 0 ? position.accuracy : 100.0,
    timestamp: position.timestamp,
  );
}
