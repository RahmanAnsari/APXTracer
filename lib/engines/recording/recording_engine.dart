import 'dart:async';

import 'package:geolocator/geolocator.dart';
import 'package:uuid/uuid.dart';

import '../../data/gps_sample_repository.dart';
import '../../data/session_repository.dart';
import '../../models/gps_sample.dart';
import '../../models/session.dart';
import '../fusion/fusion_engine.dart';
import 'default_gps_service.dart';
import 'gps_service.dart';
import 'recording_messages.dart';

/// Public interface for the Recording Engine.
abstract class IRecordingEngine {
  /// Starts a new session. Returns session ID.
  /// Throws [GpsPermissionDeniedException] if location not granted.
  /// Throws [GpsFixTimeoutException] if no fix within 10 seconds.
  Future<String> startSession();

  /// Stops the active session. Finalizes and persists all data.
  Future<Session> stopSession();

  /// Stream of live recording state updates for UI consumption.
  Stream<RecordingUpdate> get updates;

  /// Whether a session is currently active.
  bool get isRecording;
}

/// Implementation of [IRecordingEngine] that captures GPS samples on the
/// main isolate using Geolocator's position stream and persists them in
/// batches to the local DB.
///
/// Note: Flutter platform plugins (Geolocator) only work on the root isolate
/// because platform channels are bound to it. The GPS stream is async and
/// event-driven, so it does not block the UI thread.
///
/// Key behaviors:
/// - Prevents duplicate concurrent sessions via [isRecording] guard
/// - Buffers GPS samples and writes to DB in batches for efficiency
/// - Emits [RecordingUpdate] at 1 Hz for UI consumption
/// - Detects signal loss when no samples arrive for a threshold period
/// - Resumes on signal restore without data loss
class RecordingEngine implements IRecordingEngine {
  final SessionRepository _sessionRepository;
  final GpsSampleRepository _gpsSampleRepository;
  final GpsService _gpsService;
  final Uuid _uuid;

  /// Optional FusionEngine for IMU sensor fusion. Null = GPS-only mode.
  final FusionEngine? _fusionEngine;

  /// Duration after which GPS signal is considered lost.
  /// At 1 Hz GPS, 5 s gives enough headroom for brief obstructions without
  /// producing false positives on-track (walls, trees, grandstands).
  static const _signalLossThreshold = Duration(seconds: 5);

  /// Interval for persisting buffered samples to the database.
  static const _batchPersistInterval = Duration(seconds: 1);

  /// Interval for emitting UI updates.
  static const _uiUpdateInterval = Duration(seconds: 1);

  // --- Session state ---
  bool _isRecording = false;
  String? _currentSessionId;
  int? _sessionStartTimeMs;

  // --- GPS stream subscription ---
  StreamSubscription<Position>? _positionSubscription;

  // --- Sample buffering ---
  final List<GpsSample> _sampleBuffer = [];
  Timer? _batchPersistTimer;
  int _totalSampleCount = 0;

  // --- UI update stream ---
  final StreamController<RecordingUpdate> _updatesController =
      StreamController<RecordingUpdate>.broadcast();
  Timer? _uiUpdateTimer;

  // --- Signal loss tracking ---
  DateTime? _lastSampleReceivedAt;
  GpsStatus _currentGpsStatus = GpsStatus.acquiring;
  double _currentSpeedKmh = 0.0;

  // --- Fusion state ---
  StreamSubscription<GpsSample>? _fusedSampleSubscription;
  StreamSubscription<FusionStatusUpdate>? _fusionStatusSubscription;
  bool _fusionActive = false;

  RecordingEngine({
    required SessionRepository sessionRepository,
    required GpsSampleRepository gpsSampleRepository,
    GpsService? gpsService,
    Uuid? uuid,
    FusionEngine? fusionEngine,
  })  : _sessionRepository = sessionRepository,
        _gpsSampleRepository = gpsSampleRepository,
        _gpsService = gpsService ?? const DefaultGpsService(),
        _uuid = uuid ?? const Uuid(),
        _fusionEngine = fusionEngine;

  @override
  bool get isRecording => _isRecording;

  @override
  Stream<RecordingUpdate> get updates => _updatesController.stream;

  @override
  Future<String> startSession() async {
    // Prevent duplicate concurrent sessions.
    if (_isRecording) {
      throw StateError('A recording session is already active');
    }

    // Check permissions and acquire GPS fix (throws on failure).
    await _gpsService.checkPermissionsAndAcquireFix();

    // Mark as recording to prevent duplicates.
    _isRecording = true;
    _currentGpsStatus = GpsStatus.active;
    _totalSampleCount = 0;
    _currentSpeedKmh = 0.0;
    _lastSampleReceivedAt = DateTime.now();
    _fusionActive = false;

    // Generate session ID and record start time.
    final sessionId = _uuid.v4();
    _currentSessionId = sessionId;
    _sessionStartTimeMs = DateTime.now().millisecondsSinceEpoch;

    try {
      // Create session record in DB.
      final session = Session(
        id: sessionId,
        startTime: _sessionStartTimeMs!,
      );
      await _sessionRepository.insert(session);

      // Start FusionEngine if available.
      if (_fusionEngine != null) {
        await _fusionEngine.start();

        // Subscribe to fused samples → feed into _sampleBuffer.
        _fusedSampleSubscription =
            _fusionEngine.fusedSamples.listen(_onFusedSampleReceived);

        // Subscribe to status updates → handle active/fallback transitions.
        _fusionStatusSubscription =
            _fusionEngine.statusUpdates.listen(_onFusionStatusUpdate);
      }

      // Start listening to GPS position stream on the main isolate.
      // Platform plugins only work on the root isolate.
      _positionSubscription = _gpsService.getPositionStream().listen(
        _onPositionReceived,
        onError: _onPositionError,
        onDone: _onPositionStreamDone,
      );

      // Start batch persistence timer.
      _batchPersistTimer = Timer.periodic(_batchPersistInterval, (_) {
        _persistBufferedSamples();
      });

      // Start UI update timer (1 Hz).
      _uiUpdateTimer = Timer.periodic(_uiUpdateInterval, (_) {
        _emitUpdate();
      });
    } catch (e) {
      // Reset all state so the next startSession() attempt is clean.
      _isRecording = false;
      _currentSessionId = null;
      _sessionStartTimeMs = null;
      _currentGpsStatus = GpsStatus.acquiring;
      _currentSpeedKmh = 0.0;
      _fusionActive = false;
      await _positionSubscription?.cancel();
      _positionSubscription = null;
      await _fusedSampleSubscription?.cancel();
      _fusedSampleSubscription = null;
      await _fusionStatusSubscription?.cancel();
      _fusionStatusSubscription = null;
      _batchPersistTimer?.cancel();
      _batchPersistTimer = null;
      _uiUpdateTimer?.cancel();
      _uiUpdateTimer = null;
      rethrow;
    }

    return sessionId;
  }

  @override
  Future<Session> stopSession() async {
    if (!_isRecording) {
      throw StateError('No recording session is active');
    }

    // Cancel GPS stream subscription.
    await _positionSubscription?.cancel();
    _positionSubscription = null;

    // Stop FusionEngine and cancel fusion subscriptions.
    if (_fusionEngine != null) {
      await _fusionEngine.stop();
      await _fusedSampleSubscription?.cancel();
      _fusedSampleSubscription = null;
      await _fusionStatusSubscription?.cancel();
      _fusionStatusSubscription = null;
      _fusionActive = false;
    }

    // Cancel timers.
    _batchPersistTimer?.cancel();
    _batchPersistTimer = null;
    _uiUpdateTimer?.cancel();
    _uiUpdateTimer = null;

    // Persist any remaining buffered samples (must complete within 500 ms).
    await _persistBufferedSamples();

    // Compute session end time and duration.
    final endTimeMs = DateTime.now().millisecondsSinceEpoch;
    final durationMs = endTimeMs - _sessionStartTimeMs!;

    // Update session record with finalization data.
    final finalizedSession = Session(
      id: _currentSessionId!,
      startTime: _sessionStartTimeMs!,
      endTime: endTimeMs,
      durationMs: durationMs,
    );
    await _sessionRepository.update(finalizedSession);

    // Reset state.
    _isRecording = false;
    final sessionId = _currentSessionId!;
    _currentSessionId = null;
    _sessionStartTimeMs = null;
    _currentGpsStatus = GpsStatus.acquiring;
    _currentSpeedKmh = 0.0;
    _totalSampleCount = 0;

    // Return the finalized session from DB to ensure consistency.
    final session = await _sessionRepository.getById(sessionId);
    return session ?? finalizedSession;
  }

  /// Handles an incoming GPS position from the Geolocator stream.
  void _onPositionReceived(Position position) {
    if (_fusionActive && _fusionEngine != null) {
      // FusionEngine handles conversion; output arrives via _fusedSampleSubscription.
      _fusionEngine.onGpsFix(position);

      // Update signal status — GPS fix arriving means GPS is active.
      _lastSampleReceivedAt = DateTime.now();
      _currentGpsStatus = GpsStatus.active;
    } else {
      // Existing GPS-only path (unchanged).
      _persistRawGpsSample(position);
    }
  }

  /// Persists a raw GPS sample directly (GPS-only path or fallback mode).
  void _persistRawGpsSample(Position position) {
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

    // Update signal status — samples arriving means GPS is active.
    _lastSampleReceivedAt = DateTime.now();
    _currentGpsStatus = GpsStatus.active;

    // Update current speed from the sample.
    if (sample.speed != null) {
      _currentSpeedKmh = sample.speed! * 3.6;
    }

    // Buffer sample for batch persistence.
    _sampleBuffer.add(sample);
    _totalSampleCount++;
  }

  /// Handles errors from the Geolocator position stream.
  void _onPositionError(Object error) {
    _currentGpsStatus = GpsStatus.signalLost;
  }

  /// Called when the Geolocator position stream closes unexpectedly.
  ///
  /// The stream should run for the life of the session. If it closes while
  /// still recording, restart it after a brief delay so GPS resumes without
  /// requiring the user to stop and restart the session.
  void _onPositionStreamDone() {
    if (!_isRecording) return;
    Future.delayed(const Duration(seconds: 2), _restartPositionStream);
  }

  /// Cancels the current position subscription and opens a fresh stream.
  void _restartPositionStream() {
    if (!_isRecording) return;
    _positionSubscription?.cancel();
    _positionSubscription = _gpsService.getPositionStream().listen(
      _onPositionReceived,
      onError: _onPositionError,
      onDone: _onPositionStreamDone,
    );
  }

  /// Handles a fused GpsSample from the FusionEngine.
  ///
  /// Samples arrive here for both GPS-corrected and IMU-only (dead-reckoned)
  /// cases. GPS signal tracking (_lastSampleReceivedAt / _currentGpsStatus)
  /// is intentionally NOT updated here — that only happens in _onPositionReceived
  /// when real GPS data arrives, so the signal-lost indicator still fires
  /// correctly even when IMU is continuously producing dead-reckoned samples.
  void _onFusedSampleReceived(GpsSample sample) {
    // Update current speed from the fused sample.
    if (sample.speed != null) {
      _currentSpeedKmh = sample.speed! * 3.6;
    }

    // Buffer fused sample for batch persistence.
    _sampleBuffer.add(sample);
    _totalSampleCount++;
  }

  /// Handles FusionEngine status updates to manage active/fallback transitions.
  void _onFusionStatusUpdate(FusionStatusUpdate update) {
    switch (update.status) {
      case FusionStatus.active:
        _fusionActive = true;
        break;
      case FusionStatus.fallback:
        _fusionActive = false;
        break;
      case FusionStatus.error:
        _fusionActive = false;
        break;
      default:
        // For aligning, initialized, uninitialized — fusion not active yet.
        break;
    }
  }

  /// Persists buffered samples to the database.
  Future<void> _persistBufferedSamples() async {
    if (_sampleBuffer.isEmpty || _currentSessionId == null) return;

    // Take a snapshot of the buffer and clear it.
    final samplesToWrite = List<GpsSample>.from(_sampleBuffer);
    _sampleBuffer.clear();

    // Write to DB in a batch.
    await _gpsSampleRepository.batchInsert(_currentSessionId!, samplesToWrite);
  }

  /// Emits a [RecordingUpdate] to the UI stream at 1 Hz.
  void _emitUpdate() {
    if (!_isRecording || _sessionStartTimeMs == null) return;

    // Check for signal loss.
    _checkSignalLoss();

    final elapsed = Duration(
      milliseconds:
          DateTime.now().millisecondsSinceEpoch - _sessionStartTimeMs!,
    );

    final update = RecordingUpdate(
      currentSpeedKmh: _currentSpeedKmh,
      elapsed: elapsed,
      gpsStatus: _currentGpsStatus,
      sampleCount: _totalSampleCount,
    );

    _updatesController.add(update);
  }

  /// Checks if GPS signal has been lost based on time since last sample.
  void _checkSignalLoss() {
    if (_lastSampleReceivedAt == null) return;

    final timeSinceLastSample =
        DateTime.now().difference(_lastSampleReceivedAt!);

    if (timeSinceLastSample > _signalLossThreshold &&
        _currentGpsStatus == GpsStatus.active) {
      _currentGpsStatus = GpsStatus.signalLost;
    }
  }

  /// Disposes of resources. Call when the engine is no longer needed.
  void dispose() {
    _batchPersistTimer?.cancel();
    _uiUpdateTimer?.cancel();
    _positionSubscription?.cancel();
    _fusedSampleSubscription?.cancel();
    _fusionStatusSubscription?.cancel();
    _updatesController.close();
  }
}
