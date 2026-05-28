import '../../data/analytics_repository.dart';
import '../../models/gps_sample.dart';
import '../../models/lap.dart';
import '../../models/session.dart';
import '../../models/session_analytics.dart';
import '../../utils/haversine.dart';
import '../../utils/speed_converter.dart';
import '../lap_detection/lap_detection_engine.dart';

/// Interface for the Analytics Engine.
///
/// Computes all session metrics from GPS samples and detected laps.
abstract class IAnalyticsEngine {
  /// Computes full session analytics from GPS samples and detected laps.
  Future<SessionAnalytics> computeAnalytics(
    Session session,
    List<GpsSample> samples,
    List<Lap> laps,
    List<LapSectors> sectorTimes,
  );
}

/// Implementation of [IAnalyticsEngine].
///
/// Computes session duration, distance, lap statistics, speed metrics,
/// speed trace, and best sector times from locally stored data.
/// Persists computed analytics to the session_analytics table.
class AnalyticsEngine implements IAnalyticsEngine {
  final AnalyticsRepository _analyticsRepository;

  AnalyticsEngine(this._analyticsRepository);

  @override
  Future<SessionAnalytics> computeAnalytics(
    Session session,
    List<GpsSample> samples,
    List<Lap> laps,
    List<LapSectors> sectorTimes,
  ) async {
    // Duration: (endTime - startTime) / 1000 in seconds
    final durationSeconds = _computeDuration(session);

    // Distance: sum of Haversine distances between consecutive samples, in km
    final distanceKm = _computeDistance(samples);

    // Total laps: count of complete laps only (incomplete final lap excluded)
    final totalLaps = laps.where((l) => !l.isIncomplete).length;

    // Best lap time: minimum lap_time_ms (null if no laps)
    final bestLapTimeMs = _computeBestLapTime(laps);

    // Average lap time: mean of all lap_time_ms (null if no laps)
    final averageLapTimeMs = _computeAverageLapTime(laps);

    // Average speed: distance / duration in km/h (1 decimal place)
    final averageSpeedKmh = _computeAverageSpeed(distanceKm, durationSeconds);

    // Max speed: maximum sample speed converted to km/h (1 decimal place)
    final maxSpeedKmh = _computeMaxSpeed(samples);

    // Speed trace: list of speed values in km/h, one per sample
    final speedTraceKmh = _computeSpeedTrace(samples);

    // Best sector times: minimum non-null sector time per sector
    final bestSector1Ms = _computeBestSectorTime(sectorTimes, 1);
    final bestSector2Ms = _computeBestSectorTime(sectorTimes, 2);
    final bestSector3Ms = _computeBestSectorTime(sectorTimes, 3);

    final analytics = SessionAnalytics(
      sessionId: session.id,
      durationSeconds: durationSeconds,
      distanceKm: distanceKm,
      totalLaps: totalLaps,
      bestLapTimeMs: bestLapTimeMs,
      averageLapTimeMs: averageLapTimeMs,
      averageSpeedKmh: averageSpeedKmh,
      maxSpeedKmh: maxSpeedKmh,
      speedTraceKmh: speedTraceKmh,
      bestSector1Ms: bestSector1Ms,
      bestSector2Ms: bestSector2Ms,
      bestSector3Ms: bestSector3Ms,
    );

    // Persist computed analytics to session_analytics table
    await _analyticsRepository.insert(analytics);

    return analytics;
  }

  /// Computes session duration in seconds from start and end times.
  double _computeDuration(Session session) {
    if (session.endTime == null) return 0.0;
    return (session.endTime! - session.startTime) / 1000.0;
  }

  /// Computes total distance by summing Haversine distances between
  /// consecutive GPS samples, converted to kilometres (2 decimal places).
  double _computeDistance(List<GpsSample> samples) {
    if (samples.length < 2) return 0.0;

    double totalMeters = 0.0;
    for (int i = 0; i < samples.length - 1; i++) {
      totalMeters += haversineDistance(
        samples[i].latitude,
        samples[i].longitude,
        samples[i + 1].latitude,
        samples[i + 1].longitude,
      );
    }

    // Convert meters to km and round to 2 decimal places
    final distanceKm = totalMeters / 1000.0;
    return double.parse(distanceKm.toStringAsFixed(2));
  }

  /// Returns the minimum lap_time_ms among complete laps only, or null if none.
  int? _computeBestLapTime(List<Lap> laps) {
    final complete = laps.where((l) => !l.isIncomplete).toList();
    if (complete.isEmpty) return null;

    int best = complete[0].lapTimeMs;
    for (int i = 1; i < complete.length; i++) {
      if (complete[i].lapTimeMs < best) {
        best = complete[i].lapTimeMs;
      }
    }
    return best;
  }

  /// Returns the mean lap_time_ms of complete laps only, or null if none.
  int? _computeAverageLapTime(List<Lap> laps) {
    final complete = laps.where((l) => !l.isIncomplete).toList();
    if (complete.isEmpty) return null;

    int total = 0;
    for (final lap in complete) {
      total += lap.lapTimeMs;
    }
    return (total / complete.length).round();
  }

  /// Computes average speed in km/h (1 decimal place).
  /// Average speed = distance (km) / duration (hours).
  double _computeAverageSpeed(double distanceKm, double durationSeconds) {
    if (durationSeconds <= 0) return 0.0;

    final durationHours = durationSeconds / 3600.0;
    final avgSpeed = distanceKm / durationHours;
    return double.parse(avgSpeed.toStringAsFixed(1));
  }

  /// Computes maximum speed from GPS samples, converted to km/h (1 decimal).
  double _computeMaxSpeed(List<GpsSample> samples) {
    double maxSpeedMs = 0.0;

    for (final sample in samples) {
      if (sample.speed != null && sample.speed! > maxSpeedMs) {
        maxSpeedMs = sample.speed!;
      }
    }

    final maxSpeedKmh = metersPerSecondToKmh(maxSpeedMs);
    return double.parse(maxSpeedKmh.toStringAsFixed(1));
  }

  /// Generates a speed trace: list of speed values in km/h, one per sample.
  List<double> _computeSpeedTrace(List<GpsSample> samples) {
    return samples.map((sample) {
      final speedMs = sample.speed ?? 0.0;
      return metersPerSecondToKmh(speedMs);
    }).toList();
  }

  /// Computes the best (minimum non-null) sector time for a given sector.
  /// Returns null if no non-null values exist for that sector.
  int? _computeBestSectorTime(List<LapSectors> sectorTimes, int sectorNumber) {
    int? best;

    for (final lapSector in sectorTimes) {
      final int? sectorMs;
      switch (sectorNumber) {
        case 1:
          sectorMs = lapSector.sector1Ms;
        case 2:
          sectorMs = lapSector.sector2Ms;
        case 3:
          sectorMs = lapSector.sector3Ms;
        default:
          sectorMs = null;
      }

      if (sectorMs != null) {
        if (best == null || sectorMs < best) {
          best = sectorMs;
        }
      }
    }

    return best;
  }
}
