import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/gps_sample.dart';
import '../models/session_analytics.dart';
import '../providers/analytics_provider.dart';
import '../utils/time_formatter.dart';

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
    final gpsSamplesAsync = ref.watch(_gpsSamplesProvider(sessionId));

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
                _buildMetricsCard(context, analytics),
                const SizedBox(height: 16),
                _buildMapSection(context, gpsSamplesAsync),
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
  Widget _buildMetricsCard(BuildContext context, SessionAnalytics analytics) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Performance Metrics',
              style: Theme.of(context).textTheme.titleLarge,
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

  /// Builds the map section showing the GPS racing line as a polyline.
  Widget _buildMapSection(
    BuildContext context,
    AsyncValue<List<GpsSample>> gpsSamplesAsync,
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
              child: gpsSamplesAsync.when(
                loading: () =>
                    const Center(child: CircularProgressIndicator()),
                error: (error, stack) =>
                    Center(child: Text('Error loading map: $error')),
                data: (samples) {
                  if (samples.isEmpty) {
                    return const Center(
                      child: Text('No GPS data available.',
                          style: TextStyle(color: Colors.grey)),
                    );
                  }
                  return _buildTrackLine(samples);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Builds a custom painted track line with sector colors on a dark background.
  Widget _buildTrackLine(List<GpsSample> samples) {
    return CustomPaint(
      size: const Size(double.infinity, 250),
      painter: _TrackLinePainter(samples: samples),
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

/// A provider that fetches GPS samples for the session map display.
final _gpsSamplesProvider =
    FutureProvider.family<List<GpsSample>, String>((ref, sessionId) async {
  final gpsSampleRepo = ref.watch(gpsSampleRepositoryProvider);
  return gpsSampleRepo.getBySessionId(sessionId);
});

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

/// Custom painter that draws the track line with 3 sector colors
/// on a dark background, similar to F1-style circuit diagrams.
///
/// Sector 1: Red, Sector 2: Cyan, Sector 3: Orange/Yellow
class _TrackLinePainter extends CustomPainter {
  final List<GpsSample> samples;

  /// Sector colors matching F1-style: Red, Cyan, Orange
  static const _sectorColors = [
    Color(0xFFE53935), // Sector 1 - Red
    Color(0xFF00E5FF), // Sector 2 - Cyan
    Color(0xFFFFAB00), // Sector 3 - Orange/Yellow
  ];

  _TrackLinePainter({required this.samples});

  @override
  void paint(Canvas canvas, Size size) {
    if (samples.length < 2) return;

    // Calculate bounds of the GPS data
    double minLat = samples.first.latitude;
    double maxLat = samples.first.latitude;
    double minLng = samples.first.longitude;
    double maxLng = samples.first.longitude;

    for (final sample in samples) {
      if (sample.latitude < minLat) minLat = sample.latitude;
      if (sample.latitude > maxLat) maxLat = sample.latitude;
      if (sample.longitude < minLng) minLng = sample.longitude;
      if (sample.longitude > maxLng) maxLng = sample.longitude;
    }

    final latRange = maxLat - minLat;
    final lngRange = maxLng - minLng;

    // Add padding (10% on each side)
    const padding = 0.1;
    final effectiveWidth = size.width * (1 - 2 * padding);
    final effectiveHeight = size.height * (1 - 2 * padding);
    final offsetX = size.width * padding;
    final offsetY = size.height * padding;

    // Scale to fit while maintaining aspect ratio
    double scale;
    double translateX = offsetX;
    double translateY = offsetY;

    if (latRange == 0 && lngRange == 0) {
      // Single point — just center it
      scale = 1.0;
    } else if (latRange == 0) {
      scale = effectiveWidth / lngRange;
      translateY = size.height / 2;
    } else if (lngRange == 0) {
      scale = effectiveHeight / latRange;
      translateX = size.width / 2;
    } else {
      final scaleX = effectiveWidth / lngRange;
      final scaleY = effectiveHeight / latRange;
      scale = scaleX < scaleY ? scaleX : scaleY;

      // Center the track
      final actualWidth = lngRange * scale;
      final actualHeight = latRange * scale;
      translateX = (size.width - actualWidth) / 2;
      translateY = (size.height - actualHeight) / 2;
    }

    // Convert GPS coordinates to canvas points
    // Note: latitude increases upward but canvas Y increases downward
    final points = samples.map((s) {
      final x = translateX + (s.longitude - minLng) * scale;
      final y = translateY + (maxLat - s.latitude) * scale;
      return Offset(x, y);
    }).toList();

    // Split into 3 sectors by point count (1/3 each)
    final sectorSize = points.length ~/ 3;

    for (int sector = 0; sector < 3; sector++) {
      final start = sector * sectorSize;
      final end = sector == 2 ? points.length : (sector + 1) * sectorSize + 1;

      if (start >= points.length) break;

      final sectorPoints = points.sublist(start, end.clamp(0, points.length));
      if (sectorPoints.length < 2) continue;

      final paint = Paint()
        ..color = _sectorColors[sector]
        ..strokeWidth = 3.5
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke;

      final path = Path();
      path.moveTo(sectorPoints.first.dx, sectorPoints.first.dy);

      for (int i = 1; i < sectorPoints.length; i++) {
        path.lineTo(sectorPoints[i].dx, sectorPoints[i].dy);
      }

      canvas.drawPath(path, paint);
    }

    // Draw start/finish marker
    if (points.isNotEmpty) {
      final markerPaint = Paint()
        ..color = Colors.white
        ..style = PaintingStyle.fill;
      canvas.drawCircle(points.first, 4, markerPaint);

      // Draw a small cross at start/finish
      final crossPaint = Paint()
        ..color = Colors.white
        ..strokeWidth = 1.5
        ..strokeCap = StrokeCap.round;
      const crossSize = 6.0;
      canvas.drawLine(
        Offset(points.first.dx - crossSize, points.first.dy),
        Offset(points.first.dx + crossSize, points.first.dy),
        crossPaint,
      );
      canvas.drawLine(
        Offset(points.first.dx, points.first.dy - crossSize),
        Offset(points.first.dx, points.first.dy + crossSize),
        crossPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _TrackLinePainter oldDelegate) {
    return oldDelegate.samples != samples;
  }
}
