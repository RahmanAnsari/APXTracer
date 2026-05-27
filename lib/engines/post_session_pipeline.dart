import '../data/gps_sample_repository.dart';
import '../data/lap_repository.dart';
import '../data/session_repository.dart';
import '../models/gps_sample.dart';
import '../models/lap.dart';
import '../models/session_analytics.dart';
import '../models/track.dart';
import '../utils/haversine.dart';
import 'analytics/analytics_engine.dart';
import 'lap_detection/lap_detection_engine.dart';
import 'track_discovery/track_discovery_engine.dart';

/// Result of the post-session processing pipeline.
///
/// Contains all computed results from the pipeline stages:
/// track discovery, lap detection, sector times, and analytics.
class PostSessionResult {
  /// The discovered or matched track, or null if no closed loop detected.
  final Track? track;

  /// Detected laps with sector times applied, empty if no track found.
  final List<Lap> laps;

  /// Computed session analytics.
  final SessionAnalytics analytics;

  const PostSessionResult({
    this.track,
    required this.laps,
    required this.analytics,
  });
}

/// Orchestrates the post-session processing pipeline.
///
/// After a recording session is stopped, this pipeline coordinates:
/// 0. Stationary Trim   — strip prefix/suffix samples recorded while stationary
/// 1. Track Discovery   — detect closed loop, match or create track record
/// 2. Lap Detection     — find start/finish crossings, build lap list
/// 3. Sector Times      — interpolate sector crossing timestamps
/// 4. Circuit Refinement — smooth polyline from best lap (Chaikin + D-P)
/// 5. Analytics         — compute all session metrics and persist
///
/// Each stage persists its own results; there is no single wrapping transaction.
class PostSessionPipeline {
  final SessionRepository _sessionRepository;
  final GpsSampleRepository _gpsSampleRepository;
  final LapRepository _lapRepository;
  final ITrackDiscoveryEngine _trackDiscoveryEngine;
  final ILapDetectionEngine _lapDetectionEngine;
  final IAnalyticsEngine _analyticsEngine;

  PostSessionPipeline({
    required SessionRepository sessionRepository,
    required GpsSampleRepository gpsSampleRepository,
    required LapRepository lapRepository,
    required ITrackDiscoveryEngine trackDiscoveryEngine,
    required ILapDetectionEngine lapDetectionEngine,
    required IAnalyticsEngine analyticsEngine,
  })  : _sessionRepository = sessionRepository,
        _gpsSampleRepository = gpsSampleRepository,
        _lapRepository = lapRepository,
        _trackDiscoveryEngine = trackDiscoveryEngine,
        _lapDetectionEngine = lapDetectionEngine,
        _analyticsEngine = analyticsEngine;

  // ─── Movement detection thresholds ────────────────────────────────────────

  /// Minimum speed (m/s) to count as physical movement. 1.39 m/s = 5 km/h,
  /// safely above GPS/IMU noise (~1–2 km/h) and well below pit-lane speeds.
  static const double _movementSpeedThreshold = 1.39;

  /// Minimum displacement (metres) from the session's first sample to count
  /// as movement when speed data is unavailable.
  static const double _displacementThreshold = 15.0;

  /// How long (milliseconds) the movement criterion must hold continuously
  /// before movement is confirmed and the trim point is set.
  static const int _movementConfirmMs = 2000;

  // ─── Pipeline entry point ──────────────────────────────────────────────────

  /// Executes the full post-session processing pipeline for the given session.
  ///
  /// Loads the session and GPS samples from the database, then runs:
  /// 0. Stationary Trim   — strips prefix/suffix while car was stationary
  /// 1. Track Discovery   — detects closed loop, matches or creates track
  /// 2. Lap Detection     — identifies laps if a track was found
  /// 3. Sector Times      — computes sector crossing times for each lap
  /// 4. Circuit Refinement — refines polyline from best lap (Chaikin + D-P)
  /// 5. Analytics         — computes all session metrics
  ///
  /// Throws [ArgumentError] if the session ID is not found in the database.
  Future<PostSessionResult> execute(String sessionId) async {
    // Load session from database
    final session = await _sessionRepository.getById(sessionId);
    if (session == null) {
      throw ArgumentError('Session not found: $sessionId');
    }

    // Load GPS samples from database
    final rawSamples = await _gpsSampleRepository.getBySessionId(sessionId);

    // Stage 0: Strip stationary samples at the start and end of the session.
    // Downstream stages must see only real driving data so the closed-loop
    // shape and lap boundaries are clean.
    final prefixTrimmed = await _trimStationaryPrefix(sessionId, rawSamples);
    final samples = await _trimStationarySuffix(sessionId, prefixTrimmed);

    // Guard: too few samples to do anything meaningful after trimming.
    if (samples.length < 2) {
      final emptyAnalytics = await _analyticsEngine.computeAnalytics(
        session,
        samples,
        [],
        [],
      );
      return PostSessionResult(laps: [], analytics: emptyAnalytics);
    }

    // Stage 1: Track Discovery
    var track = await _trackDiscoveryEngine.discoverTrack(session, samples);

    // Stage 2 & 3: Lap Detection and Sector Times (only if track found)
    List<Lap> laps = [];
    List<LapSectors> sectorTimes = [];

    if (track != null) {
      // Capture in a final local so closures below see a non-nullable type.
      // (var track is reassigned in Stage 5, which disables Dart's promotion.)
      final resolvedTrack = track;

      // Detect laps using start/finish crossings
      final detectedLaps = await _lapDetectionEngine.detectLaps(samples, resolvedTrack);

      // Set the session ID on each detected lap
      laps = detectedLaps
          .map((lap) => Lap(
                id: lap.id,
                sessionId: sessionId,
                trackId: resolvedTrack.id,
                lapNumber: lap.lapNumber,
                startTimestamp: lap.startTimestamp,
                endTimestamp: lap.endTimestamp,
                lapTimeMs: lap.lapTimeMs,
                sector1Ms: lap.sector1Ms,
                sector2Ms: lap.sector2Ms,
                sector3Ms: lap.sector3Ms,
                isBestLap: lap.isBestLap,
                isIncomplete: lap.isIncomplete,
              ))
          .toList();

      // Compute sector boundaries and sector times
      final sectorBoundaries = _trackDiscoveryEngine.computeSectors(resolvedTrack);
      if (sectorBoundaries.isNotEmpty && laps.isNotEmpty) {
        sectorTimes = await _lapDetectionEngine.computeSectorTimes(
          laps,
          samples,
          sectorBoundaries,
        );

        // Apply sector times to laps
        laps = _applySectorTimesToLaps(laps, sectorTimes);
      }

      // Persist laps atomically
      await _lapRepository.insertBatch(laps);
    }

    // Stage 4: Circuit refinement — build a clean professional polyline from
    // the best available driving data using Chaikin + Douglas-Peucker.
    //
    // Sample priority:
    //   1. Best complete lap  — cleanest single-loop reference
    //   2. Longest lap        — driver went far but didn't finish
    //   3. All session samples — fallback when the line was never crossed
    //
    // Stage 1 confirmed a closed loop, so the shape is always correct;
    // smoothing runs unconditionally to remove GPS jitter.
    if (track != null) {
      final List<GpsSample> refinementSamples;

      final bestLap = laps.where((l) => l.isBestLap).firstOrNull;
      if (bestLap != null) {
        refinementSamples = samples
            .where((s) =>
                s.timestamp >= bestLap.startTimestamp &&
                s.timestamp <= bestLap.endTimestamp)
            .toList();
      } else if (laps.isNotEmpty) {
        // No complete lap — use whichever lap covered the most time on track.
        final longestLap = laps.reduce(
          (a, b) => a.lapTimeMs >= b.lapTimeMs ? a : b,
        );
        refinementSamples = samples
            .where((s) =>
                s.timestamp >= longestLap.startTimestamp &&
                s.timestamp <= longestLap.endTimestamp)
            .toList();
      } else {
        // Driver never crossed the start/finish line — smooth all samples.
        refinementSamples = samples;
      }

      track = await _trackDiscoveryEngine.refineCircuit(track, refinementSamples);
    }

    // Stage 5: Analytics computation
    // Reload session in case track discovery updated it
    final updatedSession =
        await _sessionRepository.getById(sessionId) ?? session;

    final analytics = await _analyticsEngine.computeAnalytics(
      updatedSession,
      samples,
      laps,
      sectorTimes,
    );

    return PostSessionResult(
      track: track,
      laps: laps,
      analytics: analytics,
    );
  }

  // ─── Stage 0: Stationary prefix trim ──────────────────────────────────────

  /// Trims samples recorded before the car first moved and deletes them from
  /// the database. Returns the trimmed list for use in subsequent stages.
  ///
  /// If movement is never confirmed (too-short session, engine never started),
  /// the full sample list is returned unchanged.
  Future<List<GpsSample>> _trimStationaryPrefix(
    String sessionId,
    List<GpsSample> samples,
  ) async {
    final trimIndex = _findMovementStart(samples);
    if (trimIndex == null || trimIndex == 0) return samples;

    final firstKeptTimestamp = samples[trimIndex].timestamp;
    await _gpsSampleRepository.deleteBeforeTimestamp(
      sessionId,
      firstKeptTimestamp,
    );

    return samples.sublist(trimIndex);
  }

  /// Scans [samples] to find the index of the first sample belonging to a
  /// confirmed movement window.
  ///
  /// Movement is confirmed when the movement criterion (speed ≥ threshold OR
  /// displacement ≥ threshold) holds continuously for [_movementConfirmMs].
  ///
  /// Returns `null` if movement is never confirmed (caller should not trim).
  /// Returns `0` if movement is confirmed from the very first sample.
  int? _findMovementStart(List<GpsSample> samples) {
    if (samples.length < 2) return null;

    final anchorLat = samples.first.latitude;
    final anchorLng = samples.first.longitude;

    // Index of the first sample in the current candidate movement window.
    int? windowStart;

    for (int i = 0; i < samples.length; i++) {
      final sample = samples[i];
      final speedMs = sample.speed ?? 0.0;
      final displacement = haversineDistance(
        anchorLat, anchorLng,
        sample.latitude, sample.longitude,
      );

      final isMoving = speedMs >= _movementSpeedThreshold ||
          displacement >= _displacementThreshold;

      if (isMoving) {
        windowStart ??= i;

        final windowDurationMs =
            sample.timestamp - samples[windowStart].timestamp;
        if (windowDurationMs >= _movementConfirmMs) {
          return windowStart;
        }
      } else {
        // Movement interrupted — reset and look for the next candidate window.
        windowStart = null;
      }
    }

    // Movement was never sustained long enough to confirm.
    return null;
  }

  // ─── Stage 0b: Stationary suffix trim ─────────────────────────────────────

  /// Trims samples recorded after the car stopped moving at the end of the
  /// session and deletes them from the database.
  ///
  /// If no stationary suffix is detected, the sample list is returned unchanged.
  Future<List<GpsSample>> _trimStationarySuffix(
    String sessionId,
    List<GpsSample> samples,
  ) async {
    final trimFrom = _findMovementEnd(samples);
    if (trimFrom == null || trimFrom >= samples.length) return samples;

    final lastKeptTimestamp = samples[trimFrom - 1].timestamp;
    await _gpsSampleRepository.deleteAfterTimestamp(
      sessionId,
      lastKeptTimestamp,
    );

    return samples.sublist(0, trimFrom);
  }

  /// Scans [samples] forward to find the exclusive end index of the last
  /// confirmed movement window.
  ///
  /// Tracks the furthest sample index that lies inside a sustained movement
  /// window (speed ≥ threshold for [_movementConfirmMs]). Once the scan
  /// completes, if a stationary tail of at least [_movementConfirmMs] follows
  /// that index, the tail is confirmed and trimming is warranted.
  ///
  /// Displacement is intentionally NOT used here — the car returns to the pit
  /// which is often near the session start point, making start-anchored
  /// displacement unreliable for the end.
  ///
  /// Returns the first index of the stationary tail to trim, or `null` if
  /// no trim is needed.
  int? _findMovementEnd(List<GpsSample> samples) {
    if (samples.length < 2) return null;

    int? lastConfirmedEnd; // last index inside a confirmed movement window
    int? windowStart;      // start of the current candidate movement window

    for (int i = 0; i < samples.length; i++) {
      final speedMs = samples[i].speed ?? 0.0;
      final isMoving = speedMs >= _movementSpeedThreshold;

      if (isMoving) {
        windowStart ??= i;
        final windowDurationMs =
            samples[i].timestamp - samples[windowStart].timestamp;
        if (windowDurationMs >= _movementConfirmMs) {
          lastConfirmedEnd = i;
        }
      } else {
        windowStart = null;
      }
    }

    // No confirmed movement at all, or movement runs to the very last sample.
    if (lastConfirmedEnd == null || lastConfirmedEnd == samples.length - 1) {
      return null;
    }

    // Only trim if the stationary tail is long enough to be meaningful.
    final tailDurationMs =
        samples.last.timestamp - samples[lastConfirmedEnd].timestamp;
    if (tailDurationMs < _movementConfirmMs) return null;

    return lastConfirmedEnd + 1;
  }

  /// Applies computed sector times to the corresponding laps.
  ///
  /// Matches sector times to laps by lap number and creates new Lap
  /// instances with the sector time fields populated.
  List<Lap> _applySectorTimesToLaps(
    List<Lap> laps,
    List<LapSectors> sectorTimes,
  ) {
    // Build a map of lap number to sector times for efficient lookup
    final sectorMap = <int, LapSectors>{};
    for (final st in sectorTimes) {
      sectorMap[st.lapNumber] = st;
    }

    return laps.map((lap) {
      final sectors = sectorMap[lap.lapNumber];
      if (sectors == null) return lap;

      return Lap(
        id: lap.id,
        sessionId: lap.sessionId,
        trackId: lap.trackId,
        lapNumber: lap.lapNumber,
        startTimestamp: lap.startTimestamp,
        endTimestamp: lap.endTimestamp,
        lapTimeMs: lap.lapTimeMs,
        sector1Ms: sectors.sector1Ms,
        sector2Ms: sectors.sector2Ms,
        sector3Ms: sectors.sector3Ms,
        isBestLap: lap.isBestLap,
        isIncomplete: lap.isIncomplete,
      );
    }).toList();
  }
}
