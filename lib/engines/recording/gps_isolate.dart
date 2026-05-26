import 'dart:async';
import 'dart:isolate';

import 'package:geolocator/geolocator.dart';

import '../../models/gps_sample.dart';
import 'recording_messages.dart';

/// Entry point for the GPS capture isolate.
///
/// This function runs on a background Dart isolate to capture GPS samples
/// at 10 Hz without blocking the UI thread. It communicates with the main
/// isolate via [SendPort]/[ReceivePort] message passing.
///
/// The [sendPort] is used to send [RecordingMessage] instances back to the
/// main isolate (primarily [GpsSampleBatch] and [RecordingError] messages).
void gpsIsolateEntryPoint(SendPort sendPort) {
  final isolateHandler = _GpsIsolateHandler(sendPort);
  isolateHandler.initialize();
}

class _GpsIsolateHandler {
  final SendPort _sendPort;
  ReceivePort? _receivePort;
  StreamSubscription<Position>? _positionSubscription;
  Timer? _batchTimer;
  List<GpsSample> _sampleBuffer = [];
  bool _isRunning = false;

  /// Batch interval — send accumulated samples every 100ms (10 Hz).
  static const _batchInterval = Duration(milliseconds: 1000);

  _GpsIsolateHandler(this._sendPort);

  /// Initializes the isolate by setting up a [ReceivePort] to listen for
  /// commands from the main isolate.
  void initialize() {
    _receivePort = ReceivePort();
    // Send our receive port back so the main isolate can communicate with us.
    _sendPort.send(_receivePort!.sendPort);

    _receivePort!.listen((message) {
      if (message is StartRecording) {
        _startCapture(message.targetHz);
      } else if (message is StopRecording) {
        _stopCapture();
      }
    });
  }

  /// Starts GPS capture at the specified rate.
  void _startCapture(int targetHz) {
    if (_isRunning) return;
    _isRunning = true;

    // Configure location settings for high-frequency capture.
    // distanceFilter: 0 ensures we get updates as fast as possible.
    final locationSettings = LocationSettings(
      accuracy: LocationAccuracy.best,
      distanceFilter: 0,
      timeLimit: null,
    );

    _positionSubscription = Geolocator.getPositionStream(
      locationSettings: locationSettings,
    ).listen(
      _onPositionReceived,
      onError: _onPositionError,
    );

    // Set up a periodic timer to flush batches to the main isolate.
    _batchTimer = Timer.periodic(_batchInterval, (_) {
      _flushBatch();
    });
  }

  /// Handles an incoming GPS position from the Geolocator stream.
  void _onPositionReceived(Position position) {
    final sample = GpsSample(
      timestamp: position.timestamp.millisecondsSinceEpoch,
      latitude: position.latitude,
      longitude: position.longitude,
      altitude: position.altitude != 0.0 ? position.altitude : null,
      speed: position.speed >= 0 ? position.speed : null,
      heading: position.heading >= 0 ? position.heading : null,
      accuracy: position.accuracy > 0 ? position.accuracy : null,
      isLowAccuracy: position.accuracy > 50.0,
    );

    _sampleBuffer.add(sample);
  }

  /// Handles errors from the Geolocator position stream.
  void _onPositionError(Object error) {
    _sendPort.send(RecordingError(
      code: 'gps_stream_error',
      message: error.toString(),
    ));
  }

  /// Sends any buffered samples to the main isolate as a [GpsSampleBatch].
  void _flushBatch() {
    if (_sampleBuffer.isEmpty) return;

    final batch = GpsSampleBatch(samples: List.unmodifiable(_sampleBuffer));
    _sendPort.send(batch);
    _sampleBuffer = [];
  }

  /// Stops GPS capture, flushes remaining samples, and cleans up resources.
  void _stopCapture() {
    if (!_isRunning) return;
    _isRunning = false;

    _batchTimer?.cancel();
    _batchTimer = null;

    _positionSubscription?.cancel();
    _positionSubscription = null;

    // Flush any remaining samples before shutting down.
    _flushBatch();

    // Close the receive port to allow the isolate to terminate.
    _receivePort?.close();
    _receivePort = null;
  }
}

/// Checks GPS permissions and acquires an initial fix before spawning
/// the GPS isolate. This runs on the main isolate.
///
/// Throws [GpsPermissionDeniedException] if location permission is not granted.
/// Throws [GpsFixTimeoutException] if no GPS fix is acquired within [timeout].
///
/// Returns the initial [Position] once a fix is acquired.
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
        accuracy: LocationAccuracy.best,
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

/// Spawns the GPS isolate and returns the communication ports.
///
/// Call [checkPermissionsAndAcquireFix] before this to ensure GPS is available.
///
/// Returns a record containing:
/// - [Isolate] the spawned isolate instance
/// - [ReceivePort] for receiving messages from the isolate (kept for cleanup)
/// - [SendPort] for sending commands to the isolate
/// - [Stream<dynamic>] a broadcast stream that relays all messages from the isolate
Future<
    ({
      Isolate isolate,
      ReceivePort receivePort,
      SendPort commandPort,
      Stream<dynamic> messageStream,
    })> spawnGpsIsolate() async {
  final receivePort = ReceivePort();

  final isolate = await Isolate.spawn(
    gpsIsolateEntryPoint,
    receivePort.sendPort,
  );

  // Create a broadcast StreamController to relay messages from the ReceivePort.
  // This avoids the single-subscription limitation of ReceivePort — the
  // broadcast stream can be listened to multiple times without issue.
  final controller = StreamController<dynamic>.broadcast();

  // Set up a single permanent listener on the ReceivePort that forwards
  // all messages to the broadcast StreamController.
  receivePort.listen(controller.add);

  // The first message from the isolate is its SendPort for receiving commands.
  // Using controller.stream.first works on broadcast streams without
  // consuming or cancelling the underlying subscription.
  final commandPort = await controller.stream.first as SendPort;

  return (
    isolate: isolate,
    receivePort: receivePort,
    commandPort: commandPort,
    messageStream: controller.stream,
  );
}
