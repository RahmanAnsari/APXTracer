import 'dart:async';

import 'package:geolocator/geolocator.dart';

/// Abstract GPS service that provides permission checking, fix acquisition,
/// and position streaming. This abstraction enables dependency injection
/// for testing the RecordingEngine without real GPS hardware.
///
/// Note: GPS operations must run on the root/main isolate because Flutter
/// platform plugins (Geolocator) use platform channels that are only
/// available on the root isolate.
abstract class GpsService {
  /// Checks GPS permissions and acquires an initial fix.
  ///
  /// Throws [GpsPermissionDeniedException] if location permission is denied.
  /// Throws [GpsFixTimeoutException] if no fix within [timeout].
  Future<Position> checkPermissionsAndAcquireFix({Duration timeout});

  /// Returns a stream of GPS positions for continuous tracking.
  ///
  /// The stream emits positions as fast as the device provides them
  /// (targeting 10 Hz on supported hardware).
  Stream<Position> getPositionStream();
}
