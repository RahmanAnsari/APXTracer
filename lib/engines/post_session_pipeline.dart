import '../data/gps_sample_repository.dart';
import '../data/lap_repository.dart';
import '../data/session_repository.dart';
import '../models/lap.dart';
import '../models/session_analytics.dart';
import '../models/track.dart';
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
/// 1. Track Discovery — detect closed loop and match/create track
/// 2. Lap Detection — find start/finish crossings and assign laps
/// 3. Sector Times — compute sector crossing times via interpolation
/// 4. Analytics — compute all session metrics
///
/// All results are persisted atomically to ensure data consistency.
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

  /// Executes the full post-session processing pipeline for the given session.
  ///
  /// Loads the session and GPS samples from the database, then runs:
  /// 1. Track Discovery — detects closed loop, matches or creates track
  /// 2. Lap Detection — identifies laps if a track was found
  /// 3. Sector Times — computes sector crossing times for each lap
  /// 4. Analytics — computes all session metrics
  ///
  /// All results (track association, laps, analytics) are persisted atomically.
  ///
  /// Throws [ArgumentError] if the session ID is not found in the database.
  Future<PostSessionResult> execute(String sessionId) async {
    // Load session from database
    final session = await _sessionRepository.getById(sessionId);
    if (session == null) {
      throw ArgumentError('Session not found: $sessionId');
    }

    // Load GPS samples from database
    final samples = await _gpsSampleRepository.getBySessionId(sessionId);

    // Stage 1: Track Discovery
    final track = await _trackDiscoveryEngine.discoverTrack(session, samples);

    // Stage 2 & 3: Lap Detection and Sector Times (only if track found)
    List<Lap> laps = [];
    List<LapSectors> sectorTimes = [];

    if (track != null) {
      // Detect laps using start/finish crossings
      final detectedLaps = await _lapDetectionEngine.detectLaps(samples, track);

      // Set the session ID on each detected lap
      laps = detectedLaps
          .map((lap) => Lap(
                id: lap.id,
                sessionId: sessionId,
                trackId: track.id,
                lapNumber: lap.lapNumber,
                startTimestamp: lap.startTimestamp,
                endTimestamp: lap.endTimestamp,
                lapTimeMs: lap.lapTimeMs,
                sector1Ms: lap.sector1Ms,
                sector2Ms: lap.sector2Ms,
                sector3Ms: lap.sector3Ms,
                isBestLap: lap.isBestLap,
              ))
          .toList();

      // Compute sector boundaries and sector times
      final sectorBoundaries = _trackDiscoveryEngine.computeSectors(track);
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

    // Stage 4: Analytics computation
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
      );
    }).toList();
  }
}
