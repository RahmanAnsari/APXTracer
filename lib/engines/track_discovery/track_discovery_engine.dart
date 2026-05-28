import 'package:latlong2/latlong.dart';
import 'package:uuid/uuid.dart';

import '../../data/session_repository.dart';
import '../../data/track_repository.dart';
import '../../models/gps_sample.dart';
import '../../models/sector_boundary.dart';
import '../../models/session.dart';
import '../../models/track.dart';
import '../../utils/circuit_builder.dart';
import '../../utils/haversine.dart';
import '../../utils/polyline_utils.dart';

/// Interface for the Track Discovery Engine.
///
/// Analyzes GPS paths to detect closed-loop circuits and generate
/// track geometry with sector boundaries.
abstract class ITrackDiscoveryEngine {
  /// Analyzes a session's GPS path for closed-loop detection.
  /// Returns the discovered or matched Track, or null if no closed loop.
  Future<Track?> discoverTrack(Session session, List<GpsSample> samples);

  /// Splits a track into 3 sectors at 1/3 and 2/3 polyline distance.
  /// Returns sector boundary points as polyline distance fractions.
  List<SectorBoundary> computeSectors(Track track);

  /// Refines the track's circuit polyline using the best lap's GPS samples.
  ///
  /// Applies Chaikin smoothing + Douglas-Peucker simplification to produce a
  /// professional-quality circuit centerline. Also computes and stores the
  /// arc length. Persists the updated track to the database.
  Future<Track> refineCircuit(Track track, List<GpsSample> bestLapSamples);
}

/// Minimum number of GPS samples required for closed-loop detection.
const int _minSamplesForClosedLoop = 20;

/// Maximum Haversine distance (meters) between first and last sample
/// for closed-loop detection.
const double _closedLoopThresholdMeters = 50.0;

/// Implementation of [ITrackDiscoveryEngine].
///
/// Detects closed-loop circuits from GPS paths, matches against existing
/// tracks, and computes sector boundaries at 1/3 and 2/3 polyline distance.
class TrackDiscoveryEngine implements ITrackDiscoveryEngine {
  final TrackRepository _trackRepository;
  final SessionRepository _sessionRepository;
  final Uuid _uuid;

  // ignore: prefer_initializing_formals
  TrackDiscoveryEngine({
    required TrackRepository trackRepository,
    required SessionRepository sessionRepository,
    Uuid? uuid,
  })  : _trackRepository = trackRepository,
        _sessionRepository = sessionRepository,
        _uuid = uuid ?? const Uuid();

  @override
  Future<Track?> discoverTrack(
      Session session, List<GpsSample> samples) async {
    // Need at least the minimum number of samples for closed-loop detection
    if (samples.length < _minSamplesForClosedLoop) {
      return null;
    }

    final firstSample = samples.first;
    final startFinish = LatLng(firstSample.latitude, firstSample.longitude);

    // ── Step 1: Match against known tracks regardless of loop closure ──────
    //
    // A known track is matched purely by the session's starting position
    // (within 50 m of an existing track's start/finish point).  This means
    // partial sessions — e.g. the driver completed one clean lap then stopped
    // mid-circuit on the second — are still linked to the correct track so
    // that the completed laps and the incomplete lap tail are recorded.
    final nearbyTracks = await _trackRepository.findNearby(
      startFinish.latitude,
      startFinish.longitude,
    );

    if (nearbyTracks.isNotEmpty) {
      final existingTrack = nearbyTracks.first;
      final updatedTrack = Track(
        id: existingTrack.id,
        name: existingTrack.name,
        polyline: existingTrack.polyline,
        startFinish: existingTrack.startFinish,
        sector1Fraction: existingTrack.sector1Fraction,
        sector2Fraction: existingTrack.sector2Fraction,
        sessionCount: existingTrack.sessionCount + 1,
        lastDriven: session.startTime,
      );
      await _trackRepository.update(updatedTrack);

      await _sessionRepository.update(Session(
        id: session.id,
        startTime: session.startTime,
        endTime: session.endTime,
        durationMs: session.durationMs,
        trackId: updatedTrack.id,
      ));

      return updatedTrack;
    }

    // ── Step 2: Only create a NEW track if the path forms a closed loop ────
    //
    // Creating a new track from a partial session is meaningless — you need
    // at least one complete lap to define the circuit geometry.  If the last
    // sample is more than 50 m from the first the session ended mid-circuit
    // and we cannot infer the track shape.
    final lastSample = samples.last;
    final distance = haversineDistance(
      firstSample.latitude,
      firstSample.longitude,
      lastSample.latitude,
      lastSample.longitude,
    );

    if (distance > _closedLoopThresholdMeters) {
      return null;
    }

    // Closed loop on an unknown track — create a new track record.
    final polyline =
        samples.map((s) => LatLng(s.latitude, s.longitude)).toList();

    final newTrack = Track(
      id: _uuid.v4(),
      polyline: polyline,
      startFinish: startFinish,
      sector1Fraction: 1 / 3,
      sector2Fraction: 2 / 3,
      sessionCount: 1,
      lastDriven: session.startTime,
    );
    await _trackRepository.insert(newTrack);

    await _sessionRepository.update(Session(
      id: session.id,
      startTime: session.startTime,
      endTime: session.endTime,
      durationMs: session.durationMs,
      trackId: newTrack.id,
    ));

    return newTrack;
  }

  @override
  List<SectorBoundary> computeSectors(Track track) {
    final points = track.polyline;

    // Cannot compute sectors without at least 2 points
    if (points.length < 2) {
      return [];
    }

    // Sector boundaries at the fractions stored on the track.
    // For a new track these default to 1/3 and 2/3; they can be customised
    // in the future without changing this computation.
    final s1 = track.sector1Fraction.clamp(0.0, 1.0);
    final s2 = track.sector2Fraction.clamp(0.0, 1.0);

    final sector1Point = pointAtFraction(points, s1);
    final sector2Point = pointAtFraction(points, s2);

    return [
      SectorBoundary(
        polylineFraction: s1,
        point: sector1Point,
      ),
      SectorBoundary(
        polylineFraction: s2,
        point: sector2Point,
      ),
    ];
  }

  @override
  Future<Track> refineCircuit(
    Track track,
    List<GpsSample> bestLapSamples,
  ) async {
    // Need enough points for meaningful smoothing
    if (bestLapSamples.length < 3) return track;

    final rawPoints =
        bestLapSamples.map((s) => LatLng(s.latitude, s.longitude)).toList();

    final refined = CircuitBuilder.buildReferencePolyline(rawPoints);
    final lengthM = CircuitBuilder.computeArcLengthMeters(refined);

    final refinedTrack = Track(
      id: track.id,
      name: track.name,
      polyline: refined,
      startFinish: track.startFinish,
      sector1Fraction: track.sector1Fraction,
      sector2Fraction: track.sector2Fraction,
      lengthM: lengthM,
      sessionCount: track.sessionCount,
      lastDriven: track.lastDriven,
    );

    await _trackRepository.update(refinedTrack);
    return refinedTrack;
  }
}
