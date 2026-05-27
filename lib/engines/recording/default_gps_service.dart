import 'dart:async';

import 'package:geolocator/geolocator.dart';

import 'gps_service.dart';
import 'recording_messages.dart';

/// Default implementation of [GpsService] that uses the Geolocator plugin
/// directly on the main isolate.
///
/// Platform plugins only work on the root isolate because they rely on
/// platform channels. This implementation calls Geolocator APIs directly.
class DefaultGpsService implements GpsService {
  const DefaultGpsService();

  @override
  Future<Position> checkPermissionsAndAcquireFix({
    Duration timeout = const Duration(seconds: 10),
  }) async {
    // Check if location services are enabled.
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      throw const GpsPermissionDeniedException(
        'Location services are disabled on this device',
      );
    }

    // Check and request permission.
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        throw const GpsPermissionDeniedException(
          'Location permission was denied',
        );
      }
    }

    if (permission == LocationPermission.deniedForever) {
      throw const GpsPermissionDeniedException(
        'Location permission is permanently denied. Please enable it in Settings.',
      );
    }

    // Attempt to acquire a GPS fix within the timeout.
    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.bestForNavigation,
        ),
      ).timeout(timeout);
      return position;
    } on TimeoutException {
      throw GpsFixTimeoutException(
        timeout: timeout,
        message: 'Could not acquire GPS fix within ${timeout.inSeconds} seconds',
      );
    }
  }

  @override
  Stream<Position> getPositionStream() {
    // Use Apple-specific settings to enable background location updates.
    // This allows GPS capture to continue when the screen is locked or
    // the app is in the background during a recording session.
    final locationSettings = AppleSettings(
      accuracy: LocationAccuracy.bestForNavigation,
      distanceFilter: 0,
      activityType: ActivityType.automotiveNavigation,
      allowBackgroundLocationUpdates: true,
      showBackgroundLocationIndicator: true,
      pauseLocationUpdatesAutomatically: false,
    );

    return Geolocator.getPositionStream(
      locationSettings: locationSettings,
    );
  }
}
