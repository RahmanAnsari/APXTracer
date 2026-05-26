import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/gps_sample_repository.dart';
import '../data/database_helper.dart';
import '../models/gps_sample.dart';
import '../models/session_analytics.dart';
import 'session_provider.dart';

/// Provides the [GpsSampleRepository] instance.
final gpsSampleRepositoryProvider = Provider<GpsSampleRepository>((ref) {
  return GpsSampleRepository(DatabaseHelper());
});

/// Provides analytics for a given session ID.
///
/// Validates: Requirement 6.5 - Display Session Summary with all computed metrics.
/// Validates: Requirement 8.2 - Correct metrics displayed per session.
/// Validates: Requirement 8.3 - Available offline from locally stored data.
final sessionAnalyticsProvider =
    FutureProvider.family<SessionAnalytics?, String>((ref, sessionId) async {
  final analyticsRepo = ref.watch(analyticsRepositoryProvider);
  return analyticsRepo.getBySessionId(sessionId);
});

/// A data class representing a single point in the speed trace for charting.
class SpeedTracePoint {
  /// The index of this point in the trace (corresponds to sample index).
  final int index;

  /// Speed in km/h at this point.
  final double speedKmh;

  /// Timestamp in Unix epoch ms for this point.
  final int timestamp;

  const SpeedTracePoint({
    required this.index,
    required this.speedKmh,
    required this.timestamp,
  });
}

/// Provides speed trace data for charting for a given session ID.
///
/// Returns a list of [SpeedTracePoint] objects suitable for rendering
/// a speed-over-time graph. Each point corresponds to one GPS sample.
///
/// Validates: Requirement 6.5 - Speed trace displayed as a graph.
final speedTraceProvider =
    FutureProvider.family<List<SpeedTracePoint>, String>(
        (ref, sessionId) async {
  final analyticsRepo = ref.watch(analyticsRepositoryProvider);
  final gpsSampleRepo = ref.watch(gpsSampleRepositoryProvider);

  // First try to get the cached speed trace from analytics
  final analytics = await analyticsRepo.getBySessionId(sessionId);
  if (analytics != null && analytics.speedTraceKmh.isNotEmpty) {
    // Load GPS samples to get timestamps for the x-axis
    final samples = await gpsSampleRepo.getBySessionId(sessionId);
    return _buildSpeedTrace(analytics.speedTraceKmh, samples);
  }

  // Fallback: compute speed trace directly from GPS samples
  final samples = await gpsSampleRepo.getBySessionId(sessionId);
  if (samples.isEmpty) return [];

  final speedTraceKmh = samples.map((s) {
    // Convert speed from m/s to km/h; default to 0 if null
    return (s.speed ?? 0.0) * 3.6;
  }).toList();

  return _buildSpeedTrace(speedTraceKmh, samples);
});

/// Builds a list of [SpeedTracePoint] from speed values and GPS samples.
List<SpeedTracePoint> _buildSpeedTrace(
  List<double> speedTraceKmh,
  List<GpsSample> samples,
) {
  final points = <SpeedTracePoint>[];
  final count =
      speedTraceKmh.length < samples.length
          ? speedTraceKmh.length
          : samples.length;

  for (int i = 0; i < count; i++) {
    points.add(SpeedTracePoint(
      index: i,
      speedKmh: speedTraceKmh[i],
      timestamp: samples[i].timestamp,
    ));
  }

  return points;
}
