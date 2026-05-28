import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/session_analytics.dart';
import '../models/track.dart';
import '../providers/analytics_provider.dart';
import '../providers/track_provider.dart';
import '../utils/time_formatter.dart';
import '../widgets/track_painter.dart';

/// Session Summary screen displaying post-session analytics, racing line map,
/// and speed trace graph.
///
/// Validates: Requirements 6.1, 6.2, 6.3, 6.4, 6.5, 6.6
class SessionSummaryScreen extends ConsumerWidget {
  const SessionSummaryScreen({super.key, required this.sessionId});

  final String sessionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final analyticsAsync = ref.watch(sessionAnalyticsProvider(sessionId));
    final speedTraceAsync = ref.watch(speedTraceProvider(sessionId));
    final trackAsync = ref.watch(sessionTrackProvider(sessionId));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Session Summary'),
      ),
      body: analyticsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => Center(
          child: Text('Error loading analytics: $error'),
        ),
        data: (analytics) {
          if (analytics == null) {
            return const Center(
              child: Text('No analytics available for this session.'),
            );
          }

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildMetricsCard(context, analytics, trackAsync),
                const SizedBox(height: 16),
                _buildMapSection(context, trackAsync),
                const SizedBox(height: 16),
                _buildSpeedGraphSection(context, speedTraceAsync),
              ],
            ),
          );
        },
      ),
    );
  }

  /// Builds the metrics card displaying session statistics.
  Widget _buildMetricsCard(
    BuildContext context,
    SessionAnalytics analytics,
    AsyncValue<Track?> trackAsync,
  ) {
    final theme = Theme.of(context);
    final trackName = trackAsync.valueOrNull?.name ??
        (trackAsync.valueOrNull != null ? 'Unnamed Track' : null);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Performance Metrics',
                    style: theme.textTheme.titleLarge,
                  ),
                ),
                if (trackName != null) ...[
                  Icon(
                    Icons.flag_outlined,
                    size: 14,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    trackName,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 12),
            _MetricRow(
              label: 'Duration',
              value: formatDuration(analytics.durationSeconds.round()),
            ),
            _MetricRow(
              label: 'Distance',
              value: '${analytics.distanceKm.toStringAsFixed(2)} km',
            ),
            _MetricRow(
              label: 'Total Laps',
              value: analytics.totalLaps.toString(),
            ),
            if (analytics.totalLaps > 0 && analytics.bestLapTimeMs != null)
              _MetricRow(
                label: 'Best Lap Time',
                value: formatLapTime(analytics.bestLapTimeMs!),
              ),
            if (analytics.totalLaps > 0 && analytics.averageLapTimeMs != null)
              _MetricRow(
                label: 'Average Lap Time',
                value: formatLapTime(analytics.averageLapTimeMs!),
              ),
            _MetricRow(
              label: 'Average Speed',
              value: formatSpeed(analytics.averageSpeedKmh),
            ),
            _MetricRow(
              label: 'Max Speed',
              value: formatSpeed(analytics.maxSpeedKmh),
            ),
          ],
        ),
      ),
    );
  }

  /// Builds the map section showing the refined circuit polyline.
  Widget _buildMapSection(
    BuildContext context,
    AsyncValue<Track?> trackAsync,
  ) {
    return Card(
      color: const Color(0xFF2D2D2D),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'CIRCUIT',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: Colors.grey[400],
                    letterSpacing: 1.5,
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 250,
              child: trackAsync.when(
                loading: () =>
                    const Center(child: CircularProgressIndicator()),
                error: (error, stack) =>
                    Center(child: Text('Error loading circuit: $error')),
                data: (track) {
                  if (track == null || track.polyline.length < 2) {
                    return const Center(
                      child: Text(
                        'No circuit data available.',
                        style: TextStyle(color: Colors.grey),
                      ),
                    );
                  }
                  return CustomPaint(
                    size: const Size(double.infinity, 250),
                    painter: TrackLinePainter(
                      points: track.polyline,
                      sector1Fraction: track.sector1Fraction,
                      sector2Fraction: track.sector2Fraction,
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Builds the speed graph section using fl_chart.
  Widget _buildSpeedGraphSection(
    BuildContext context,
    AsyncValue<List<SpeedTracePoint>> speedTraceAsync,
  ) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Speed Trace',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 200,
              child: speedTraceAsync.when(
                loading: () =>
                    const Center(child: CircularProgressIndicator()),
                error: (error, stack) =>
                    Center(child: Text('Error loading speed data: $error')),
                data: (tracePoints) {
                  if (tracePoints.isEmpty) {
                    return const Center(
                      child: Text('No speed data available.'),
                    );
                  }
                  return _buildSpeedChart(tracePoints);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Builds the fl_chart LineChart for speed trace over sample index.
  Widget _buildSpeedChart(List<SpeedTracePoint> tracePoints) {
    final spots = tracePoints
        .map((p) => FlSpot(p.index.toDouble(), p.speedKmh))
        .toList();

    final maxSpeed = tracePoints
        .map((p) => p.speedKmh)
        .reduce((a, b) => a > b ? a : b);

    return LineChart(
      LineChartData(
        gridData: const FlGridData(show: true),
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(
            axisNameWidget: const Text(
              'km/h',
              style: TextStyle(fontSize: 12),
            ),
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 40,
              getTitlesWidget: (value, meta) {
                return Text(
                  value.toInt().toString(),
                  style: const TextStyle(fontSize: 10),
                );
              },
            ),
          ),
          bottomTitles: AxisTitles(
            axisNameWidget: const Text(
              'Sample',
              style: TextStyle(fontSize: 12),
            ),
            sideTitles: const SideTitles(showTitles: false),
          ),
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
        ),
        borderData: FlBorderData(show: true),
        minX: 0,
        maxX: (tracePoints.length - 1).toDouble(),
        minY: 0,
        maxY: (maxSpeed * 1.1).ceilToDouble(),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            curveSmoothness: 0.2,
            color: Colors.deepPurple,
            barWidth: 2,
            isStrokeCapRound: true,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              color: Colors.deepPurple.withValues(alpha: 0.1),
            ),
          ),
        ],
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipItems: (touchedSpots) {
              return touchedSpots.map((spot) {
                return LineTooltipItem(
                  '${spot.y.toStringAsFixed(1)} km/h',
                  const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                );
              }).toList();
            },
          ),
        ),
      ),
    );
  }
}


/// A simple row widget for displaying a metric label and value.
class _MetricRow extends StatelessWidget {
  const _MetricRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Colors.grey[600],
                ),
          ),
          Text(
            value,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
        ],
      ),
    );
  }
}
