import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart' as geo;

import '../models/session_analytics.dart';
import '../models/track.dart';
import '../providers/analytics_provider.dart';
import '../providers/track_provider.dart';
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
                _buildMetricsCard(context, analytics),
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
                    painter: _TrackLinePainter(
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

/// Custom painter that draws the refined circuit polyline with 3 sector colors
/// on a dark background, similar to F1-style circuit diagrams.
///
/// Sector 1: Red, Sector 2: Cyan, Sector 3: Orange/Yellow
/// Sector boundaries are placed at arc-length fractions (sector1Fraction, sector2Fraction).
class _TrackLinePainter extends CustomPainter {
  final List<geo.LatLng> points;
  final double sector1Fraction;
  final double sector2Fraction;

  static const _sectorColors = [
    Color(0xFFE53935), // Sector 1 - Red
    Color(0xFF00E5FF), // Sector 2 - Cyan
    Color(0xFFFFAB00), // Sector 3 - Orange/Yellow
  ];

  _TrackLinePainter({
    required this.points,
    required this.sector1Fraction,
    required this.sector2Fraction,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2) return;

    double minLat = points.first.latitude;
    double maxLat = points.first.latitude;
    double minLng = points.first.longitude;
    double maxLng = points.first.longitude;

    for (final p in points) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLng) minLng = p.longitude;
      if (p.longitude > maxLng) maxLng = p.longitude;
    }

    final latRange = maxLat - minLat;
    final lngRange = maxLng - minLng;

    const padding = 0.1;
    final effectiveWidth = size.width * (1 - 2 * padding);
    final effectiveHeight = size.height * (1 - 2 * padding);

    double scale;
    double translateX;
    double translateY;

    if (latRange == 0 && lngRange == 0) {
      scale = 1.0;
      translateX = size.width / 2;
      translateY = size.height / 2;
    } else if (latRange == 0) {
      scale = effectiveWidth / lngRange;
      translateX = size.width * padding;
      translateY = size.height / 2;
    } else if (lngRange == 0) {
      scale = effectiveHeight / latRange;
      translateX = size.width / 2;
      translateY = size.height * padding;
    } else {
      final scaleX = effectiveWidth / lngRange;
      final scaleY = effectiveHeight / latRange;
      scale = scaleX < scaleY ? scaleX : scaleY;
      final actualWidth = lngRange * scale;
      final actualHeight = latRange * scale;
      translateX = (size.width - actualWidth) / 2;
      translateY = (size.height - actualHeight) / 2;
    }

    // Convert LatLng to canvas offsets.
    // Latitude increases upward; canvas Y increases downward.
    final canvasPoints = points.map((p) {
      final x = translateX + (p.longitude - minLng) * scale;
      final y = translateY + (maxLat - p.latitude) * scale;
      return Offset(x, y);
    }).toList();

    // Compute cumulative arc lengths to split sectors by fraction.
    final segLengths = <double>[0.0];
    for (int i = 1; i < canvasPoints.length; i++) {
      segLengths.add(segLengths.last + (canvasPoints[i] - canvasPoints[i - 1]).distance);
    }
    final totalLength = segLengths.last;

    final s1End = totalLength * sector1Fraction.clamp(0.0, 1.0);
    final s2End = totalLength * sector2Fraction.clamp(0.0, 1.0);
    final boundaries = [0.0, s1End, s2End, totalLength];

    for (int sector = 0; sector < 3; sector++) {
      final segStart = boundaries[sector];
      final segEnd = boundaries[sector + 1];
      if (segEnd <= segStart) continue;

      final paint = Paint()
        ..color = _sectorColors[sector]
        ..strokeWidth = 3.5
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke;

      final path = Path();
      bool started = false;

      for (int i = 0; i < canvasPoints.length - 1; i++) {
        final arcA = segLengths[i];
        final arcB = segLengths[i + 1];

        if (arcB <= segStart || arcA >= segEnd) continue;

        final a = canvasPoints[i];
        final b = canvasPoints[i + 1];
        final segLen = arcB - arcA;

        final tA = segLen == 0
            ? 0.0
            : ((segStart - arcA) / segLen).clamp(0.0, 1.0);
        final tB = segLen == 0
            ? 1.0
            : ((segEnd - arcA) / segLen).clamp(0.0, 1.0);

        final pA = arcA < segStart ? Offset.lerp(a, b, tA)! : a;
        final pB = arcB > segEnd ? Offset.lerp(a, b, tB)! : b;

        if (!started) {
          path.moveTo(pA.dx, pA.dy);
          started = true;
        } else {
          path.lineTo(pA.dx, pA.dy);
        }
        path.lineTo(pB.dx, pB.dy);
      }

      if (started) canvas.drawPath(path, paint);
    }

    // Start/finish marker
    if (canvasPoints.isNotEmpty) {
      final markerPaint = Paint()
        ..color = Colors.white
        ..style = PaintingStyle.fill;
      canvas.drawCircle(canvasPoints.first, 4, markerPaint);

      final crossPaint = Paint()
        ..color = Colors.white
        ..strokeWidth = 1.5
        ..strokeCap = StrokeCap.round;
      const crossSize = 6.0;
      canvas.drawLine(
        Offset(canvasPoints.first.dx - crossSize, canvasPoints.first.dy),
        Offset(canvasPoints.first.dx + crossSize, canvasPoints.first.dy),
        crossPaint,
      );
      canvas.drawLine(
        Offset(canvasPoints.first.dx, canvasPoints.first.dy - crossSize),
        Offset(canvasPoints.first.dx, canvasPoints.first.dy + crossSize),
        crossPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _TrackLinePainter oldDelegate) {
    return oldDelegate.points != points ||
        oldDelegate.sector1Fraction != sector1Fraction ||
        oldDelegate.sector2Fraction != sector2Fraction;
  }
}
