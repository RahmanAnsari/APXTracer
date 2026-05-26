import 'package:latlong2/latlong.dart';
import 'package:uuid/uuid.dart';

import '../../models/gps_sample.dart';
import '../../models/lap.dart';
import '../../models/sector_boundary.dart';
import '../../models/track.dart';
import '../../utils/haversine.dart';

/// Interface for the Lap Detection Engine.
///
/// Identifies laps by detecting start/finish line crossings and
/// computes sector times using linear interpolation.
abstract class ILapDetectionEngine {
  /// Detects laps by finding start/finish line crossings.
  /// Filters false detections (< 10 second laps).
  Future<List<Lap>> detectLaps(
    List<GpsSample> samples,
    Track track,
  );

  /// Calculates sector times for each lap using linear interpolation.
  Future<List<LapSectors>> computeSectorTimes(
    List<Lap> laps,
    List<GpsSample> samples,
    List<SectorBoundary> boundaries,
  );
}

/// Holds sector time data for a single lap.
class LapSectors {
  final int lapNumber;
  final int? sector1Ms; // null if unavailable
  final int? sector2Ms;
  final int? sector3Ms;

  const LapSectors({
    required this.lapNumber,
    this.sector1Ms,
    this.sector2Ms,
    this.sector3Ms,
  });
}

/// Tolerance radius in meters for detecting start/finish crossings.
const double _crossingToleranceMeters = 15.0;

/// Minimum lap time in milliseconds to filter false detections.
const int _minLapTimeMs = 10000; // 10 seconds

/// Implementation of [ILapDetectionEngine].
///
/// Uses closest-approach method between consecutive GPS samples to detect
/// start/finish line crossings, and linear interpolation for sector times.
class LapDetectionEngine implements ILapDetectionEngine {
  final Uuid _uuid;

  LapDetectionEngine({Uuid? uuid}) : _uuid = uuid ?? const Uuid();

  @override
  Future<List<Lap>> detectLaps(
    List<GpsSample> samples,
    Track track,
  ) async {
    if (samples.length < 2) return [];

    final startFinish = track.startFinish;

    // Find all crossing timestamps using closest-approach method
    final crossingTimestamps = _detectCrossings(samples, startFinish);

    if (crossingTimestamps.length < 2) return [];

    // Build laps from consecutive crossings, filtering false detections
    final laps = <Lap>[];
    int lapNumber = 1;

    for (int i = 0; i < crossingTimestamps.length - 1; i++) {
      final startTs = crossingTimestamps[i];
      final endTs = crossingTimestamps[i + 1];
      final lapTimeMs = endTs - startTs;

      // Filter false detections: discard laps with time < 10 seconds
      if (lapTimeMs < _minLapTimeMs) continue;

      laps.add(Lap(
        id: _uuid.v4(),
        sessionId: '', // Will be set by caller or pipeline
        trackId: track.id,
        lapNumber: lapNumber,
        startTimestamp: startTs,
        endTimestamp: endTs,
        lapTimeMs: lapTimeMs,
      ));
      lapNumber++;
    }

    if (laps.isEmpty) return [];

    // Identify best lap (minimum lap time)
    int bestLapIndex = 0;
    int bestLapTime = laps[0].lapTimeMs;
    for (int i = 1; i < laps.length; i++) {
      if (laps[i].lapTimeMs < bestLapTime) {
        bestLapTime = laps[i].lapTimeMs;
        bestLapIndex = i;
      }
    }

    // Rebuild list with isBestLap flag set on the best lap
    final result = <Lap>[];
    for (int i = 0; i < laps.length; i++) {
      final lap = laps[i];
      result.add(Lap(
        id: lap.id,
        sessionId: lap.sessionId,
        trackId: lap.trackId,
        lapNumber: lap.lapNumber,
        startTimestamp: lap.startTimestamp,
        endTimestamp: lap.endTimestamp,
        lapTimeMs: lap.lapTimeMs,
        sector1Ms: lap.sector1Ms,
        sector2Ms: lap.sector2Ms,
        sector3Ms: lap.sector3Ms,
        isBestLap: i == bestLapIndex,
      ));
    }

    return result;
  }

  /// Detects crossings of the start/finish point using the closest-approach
  /// method between consecutive GPS samples.
  ///
  /// For each pair of consecutive samples, if either sample is within the
  /// tolerance radius of the start/finish point, we check if this pair
  /// represents a closest approach (the distance to start/finish decreases
  /// then increases). The crossing timestamp is interpolated.
  List<int> _detectCrossings(List<GpsSample> samples, LatLng startFinish) {
    final crossings = <int>[];

    // Calculate distances from each sample to the start/finish point
    final distances = <double>[];
    for (final sample in samples) {
      distances.add(haversineDistance(
        sample.latitude,
        sample.longitude,
        startFinish.latitude,
        startFinish.longitude,
      ));
    }

    // Find local minima within tolerance - these represent crossings
    for (int i = 1; i < distances.length - 1; i++) {
      // Check if this point is within tolerance
      if (distances[i] > _crossingToleranceMeters) continue;

      // Check if this is a local minimum (closest approach)
      if (distances[i] <= distances[i - 1] &&
          distances[i] <= distances[i + 1]) {
        // Interpolate the crossing timestamp using the closest-approach method
        // between the sample before and after the minimum
        final crossingTimestamp =
            _interpolateCrossingTimestamp(samples, distances, i);
        crossings.add(crossingTimestamp);
      }
    }

    // Also check the first and last samples as potential crossings
    // First sample: check if it's within tolerance and closer than the next
    if (distances.isNotEmpty &&
        distances[0] <= _crossingToleranceMeters &&
        (distances.length == 1 || distances[0] <= distances[1])) {
      crossings.insert(0, samples[0].timestamp);
    }

    // Last sample: check if it's within tolerance and closer than the previous
    if (distances.length > 1 &&
        distances.last <= _crossingToleranceMeters &&
        distances.last <= distances[distances.length - 2]) {
      crossings.add(samples.last.timestamp);
    }

    // Remove duplicate crossings that are too close together (< 1 second)
    return _deduplicateCrossings(crossings);
  }

  /// Interpolates the exact crossing timestamp at a local minimum.
  ///
  /// Uses the timestamps and distances of the surrounding samples to
  /// estimate the precise moment of closest approach.
  int _interpolateCrossingTimestamp(
    List<GpsSample> samples,
    List<double> distances,
    int minIndex,
  ) {
    // If the minimum distance is essentially zero, use the sample timestamp
    if (distances[minIndex] < 0.1) {
      return samples[minIndex].timestamp;
    }

    // Use quadratic interpolation with the three points around the minimum
    // to find the precise crossing time
    if (minIndex > 0 && minIndex < samples.length - 1) {
      final t0 = samples[minIndex - 1].timestamp.toDouble();
      final t1 = samples[minIndex].timestamp.toDouble();
      final t2 = samples[minIndex + 1].timestamp.toDouble();
      final d0 = distances[minIndex - 1];
      final d1 = distances[minIndex];
      final d2 = distances[minIndex + 1];

      // Quadratic interpolation to find the time of minimum distance
      final denom = 2.0 * ((d0 - d1) * (t2 - t1) - (d2 - d1) * (t0 - t1));
      if (denom.abs() > 1e-10) {
        final tMin = t1 +
            ((d0 - d1) * (t2 - t1) * (t2 - t1) -
                    (d2 - d1) * (t0 - t1) * (t0 - t1)) /
                denom;
        // Clamp to the range [t0, t2]
        final clamped = tMin.clamp(t0, t2);
        return clamped.round();
      }
    }

    return samples[minIndex].timestamp;
  }

  /// Removes duplicate crossings that are within 1 second of each other.
  /// Keeps the first occurrence in each cluster.
  List<int> _deduplicateCrossings(List<int> crossings) {
    if (crossings.length <= 1) return crossings;

    // Sort crossings by timestamp
    final sorted = List<int>.from(crossings)..sort();

    final deduplicated = <int>[sorted[0]];
    for (int i = 1; i < sorted.length; i++) {
      if (sorted[i] - deduplicated.last >= 1000) {
        deduplicated.add(sorted[i]);
      }
    }
    return deduplicated;
  }

  @override
  Future<List<LapSectors>> computeSectorTimes(
    List<Lap> laps,
    List<GpsSample> samples,
    List<SectorBoundary> boundaries,
  ) async {
    if (laps.isEmpty || samples.isEmpty || boundaries.isEmpty) return [];

    // We expect exactly 2 boundaries (sector 1/3 and 2/3) for 3 sectors
    if (boundaries.length != 2) return [];

    final results = <LapSectors>[];

    for (final lap in laps) {
      // Get samples within this lap's time range
      final lapSamples = samples
          .where((s) =>
              s.timestamp >= lap.startTimestamp &&
              s.timestamp <= lap.endTimestamp)
          .toList();

      if (lapSamples.length < 2) {
        results.add(LapSectors(lapNumber: lap.lapNumber));
        continue;
      }

      // Find crossing timestamps for each sector boundary
      final sector1CrossingTs =
          _findSectorCrossingTimestamp(lapSamples, boundaries[0]);
      final sector2CrossingTs =
          _findSectorCrossingTimestamp(lapSamples, boundaries[1]);

      // Calculate sector times
      int? sector1Ms;
      int? sector2Ms;
      int? sector3Ms;

      if (sector1CrossingTs != null) {
        sector1Ms = sector1CrossingTs - lap.startTimestamp;
        if (sector1Ms <= 0) sector1Ms = null;
      }

      if (sector1CrossingTs != null && sector2CrossingTs != null) {
        sector2Ms = sector2CrossingTs - sector1CrossingTs;
        if (sector2Ms <= 0) sector2Ms = null;
      } else if (sector2CrossingTs != null) {
        // Can't compute sector 2 without sector 1 crossing
        sector2Ms = null;
      }

      if (sector2CrossingTs != null) {
        sector3Ms = lap.endTimestamp - sector2CrossingTs;
        if (sector3Ms <= 0) sector3Ms = null;
      }

      results.add(LapSectors(
        lapNumber: lap.lapNumber,
        sector1Ms: sector1Ms,
        sector2Ms: sector2Ms,
        sector3Ms: sector3Ms,
      ));
    }

    return results;
  }

  /// Finds the interpolated timestamp when the GPS path crosses a sector
  /// boundary point.
  ///
  /// Uses the polyline fraction of the boundary to determine which samples
  /// straddle the boundary, then linearly interpolates the crossing time.
  ///
  /// Returns null if no straddling pair exists (GPS gap).
  int? _findSectorCrossingTimestamp(
    List<GpsSample> lapSamples,
    SectorBoundary boundary,
  ) {
    if (lapSamples.length < 2) return null;

    final boundaryPoint = boundary.point;

    // Find the pair of consecutive samples that straddle the boundary point.
    // We look for the pair where the distance to the boundary decreases
    // then increases (closest approach), similar to start/finish detection.
    double bestDistance = double.infinity;
    int bestIndex = -1;

    // Calculate distances from each sample to the boundary point
    final distances = <double>[];
    for (final sample in lapSamples) {
      distances.add(haversineDistance(
        sample.latitude,
        sample.longitude,
        boundaryPoint.latitude,
        boundaryPoint.longitude,
      ));
    }

    // Find the closest approach point (local minimum)
    for (int i = 1; i < distances.length - 1; i++) {
      if (distances[i] <= distances[i - 1] &&
          distances[i] <= distances[i + 1] &&
          distances[i] < bestDistance) {
        bestDistance = distances[i];
        bestIndex = i;
      }
    }

    // Also check first and last samples
    if (distances.isNotEmpty && distances[0] < bestDistance) {
      if (distances.length == 1 || distances[0] <= distances[1]) {
        bestDistance = distances[0];
        bestIndex = 0;
      }
    }
    if (distances.length > 1 && distances.last < bestDistance) {
      if (distances.last <= distances[distances.length - 2]) {
        bestDistance = distances.last;
        bestIndex = distances.length - 1;
      }
    }

    // If no close approach found, return null
    if (bestIndex < 0) return null;

    // Use linear interpolation between the straddling pair
    // to compute the exact crossing timestamp
    if (bestIndex == 0) {
      return lapSamples[0].timestamp;
    }
    if (bestIndex == distances.length - 1) {
      return lapSamples.last.timestamp;
    }

    // Interpolate between the sample before and after the closest approach
    // Use the distances to weight the interpolation
    final prevDist = distances[bestIndex - 1];
    final nextDist = distances[bestIndex + 1];
    final currDist = distances[bestIndex];

    // If the minimum is very close to the boundary, just use its timestamp
    if (currDist < 1.0) {
      return lapSamples[bestIndex].timestamp;
    }

    // Linear interpolation between the two samples that straddle the boundary
    // Find which side is closer to determine the straddling pair
    final int straddleStart;
    final int straddleEnd;
    if (prevDist < nextDist) {
      straddleStart = bestIndex - 1;
      straddleEnd = bestIndex;
    } else {
      straddleStart = bestIndex;
      straddleEnd = bestIndex + 1;
    }

    final d1 = distances[straddleStart];
    final d2 = distances[straddleEnd];
    final totalDist = d1 + d2;

    if (totalDist == 0) {
      return lapSamples[straddleStart].timestamp;
    }

    // Linear interpolation: fraction along the segment
    final fraction = d1 / totalDist;
    final t1 = lapSamples[straddleStart].timestamp.toDouble();
    final t2 = lapSamples[straddleEnd].timestamp.toDouble();
    final interpolatedTime = t1 + fraction * (t2 - t1);

    return interpolatedTime.round();
  }
}
