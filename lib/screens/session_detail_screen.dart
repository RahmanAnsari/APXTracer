import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../models/gps_sample.dart';
import '../models/lap.dart';
import '../models/session.dart';
import '../models/session_analytics.dart';
import '../providers/analytics_provider.dart';
import '../providers/export_provider.dart';
import '../providers/session_provider.dart';
import '../utils/time_formatter.dart';

String _formatSessionDate(int epochMs) {
  final date = DateTime.fromMillisecondsSinceEpoch(epochMs);
  final now = DateTime.now();
  final diff = now.difference(date);
  if (diff.inDays == 0) return 'Today at ${_tod(date)}';
  if (diff.inDays == 1) return 'Yesterday at ${_tod(date)}';
  return '${date.day}/${date.month}/${date.year}';
}

String _tod(DateTime d) =>
    '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

Future<String?> _showRenameDialog(BuildContext context, String? currentName) {
  final controller = TextEditingController(text: currentName ?? '');
  return showDialog<String?>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Rename Session'),
      content: TextField(
        controller: controller,
        autofocus: true,
        decoration: const InputDecoration(
          hintText: 'Session name',
          border: OutlineInputBorder(),
        ),
        onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, controller.text.trim()),
          child: const Text('Save'),
        ),
      ],
    ),
  ).then((result) {
    controller.dispose();
    return result;
  });
}

/// Provides GPS samples for a given session ID.
final gpsSamplesProvider =
    FutureProvider.family<List<GpsSample>, String>((ref, sessionId) async {
  final repo = ref.watch(gpsSampleRepositoryProvider);
  return repo.getBySessionId(sessionId);
});

/// Session Detail screen displaying track visualization, speed graph,
/// lap list with sector times, and export options.
///
/// Validates: Requirements 5.4, 8.4, 8.5, 9.5
class SessionDetailScreen extends ConsumerStatefulWidget {
  const SessionDetailScreen({super.key, required this.sessionId});

  final String sessionId;

  @override
  ConsumerState<SessionDetailScreen> createState() =>
      _SessionDetailScreenState();
}

class _SessionDetailScreenState extends ConsumerState<SessionDetailScreen> {
  @override
  Widget build(BuildContext context) {
    final detailAsync = ref.watch(sessionDetailProvider(widget.sessionId));
    final samplesAsync = ref.watch(gpsSamplesProvider(widget.sessionId));
    final speedTraceAsync = ref.watch(speedTraceProvider(widget.sessionId));

    // Listen to export state changes for success/error feedback
    ref.listen<ExportState>(exportProvider, (previous, next) {
      if (next.status == ExportStatus.success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Export completed successfully'),
            behavior: SnackBarBehavior.floating,
          ),
        );
        ref.read(exportProvider.notifier).reset();
      } else if (next.status == ExportStatus.error) {
        _showExportErrorDialog(context, next);
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: detailAsync.maybeWhen(
          data: (detail) {
            if (detail == null) return const Text('Session Detail');
            final name = detail.session.name;
            return Text(
              name != null && name.isNotEmpty
                  ? name
                  : _formatSessionDate(detail.session.startTime),
            );
          },
          orElse: () => const Text('Session Detail'),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: 'Rename',
            onPressed: detailAsync.maybeWhen(
              data: (detail) => detail != null
                  ? () => _renameSession(context, ref, detail.session)
                  : null,
              orElse: () => null,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.ios_share),
            tooltip: 'Export',
            onPressed: () => _showFormatSelectionSheet(context),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Delete session',
            onPressed: () => _confirmDeleteSession(context, ref),
          ),
        ],
      ),
      body: detailAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => Center(
          child: Text('Error loading session: $error'),
        ),
        data: (detail) {
          if (detail == null) {
            return const Center(child: Text('Session not found'));
          }

          return samplesAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, stack) => Center(
              child: Text('Error loading GPS data: $error'),
            ),
            data: (samples) {
              return speedTraceAsync.when(
                loading: () =>
                    const Center(child: CircularProgressIndicator()),
                error: (error, stack) => Center(
                  child: Text('Error loading speed data: $error'),
                ),
                data: (speedTrace) {
                  return _buildContent(
                    context,
                    detail,
                    samples,
                    speedTrace,
                  );
                },
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildContent(
    BuildContext context,
    SessionDetail detail,
    List<GpsSample> samples,
    List<SpeedTracePoint> speedTrace,
  ) {
    final hasLaps = detail.laps.isNotEmpty;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Overall session metrics
        if (detail.analytics != null)
          _SessionMetricsSection(analytics: detail.analytics!),
        if (detail.analytics != null) const SizedBox(height: 16),

        // Track visualization (dark background, sector colors)
        _TrackMapSection(samples: samples),
        const SizedBox(height: 16),

        // Speed graph
        _SpeedGraphSection(speedTrace: speedTrace),
        const SizedBox(height: 16),

        // Lap list or "no laps detected" message
        if (hasLaps)
          _LapListSection(
            laps: detail.laps,
            analytics: detail.analytics,
          )
        else
          const _NoLapsSection(),
      ],
    );
  }

  /// Step 1: Show format selection (CSV or JSON)
  void _showFormatSelectionSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Export Session',
                style: Theme.of(sheetContext).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(
                'Choose export format',
                style: Theme.of(sheetContext).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(sheetContext)
                          .colorScheme
                          .onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 16),
              ListTile(
                leading: const Icon(Icons.table_chart),
                title: const Text('CSV'),
                subtitle: const Text('Comma-separated values'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _showDestinationSelectionSheet(context, ExportFormat.csv);
                },
              ),
              ListTile(
                leading: const Icon(Icons.data_object),
                title: const Text('JSON'),
                subtitle: const Text('JavaScript Object Notation'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _showDestinationSelectionSheet(context, ExportFormat.json);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Step 2: Show destination selection (Google Drive or Share)
  void _showDestinationSelectionSheet(
      BuildContext context, ExportFormat format) {
    final formatLabel = format == ExportFormat.csv ? 'CSV' : 'JSON';

    showModalBottomSheet(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Export as $formatLabel',
                style: Theme.of(sheetContext).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(
                'Choose destination',
                style: Theme.of(sheetContext).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(sheetContext)
                          .colorScheme
                          .onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 16),
              ListTile(
                leading: const Icon(Icons.cloud_upload),
                title: const Text('Google Drive'),
                subtitle: const Text('Upload to your Google Drive'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _executeExport(format, ExportDestination.googleDrive);
                },
              ),
              ListTile(
                leading: const Icon(Icons.share),
                title: const Text('Share'),
                subtitle: const Text('Share via platform share sheet'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _executeExport(format, ExportDestination.shareSheet);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Execute the export with the selected format and destination.
  void _executeExport(ExportFormat format, ExportDestination destination) {
    final notifier = ref.read(exportProvider.notifier);
    switch (format) {
      case ExportFormat.csv:
        notifier.exportCsv(widget.sessionId, destination);
      case ExportFormat.json:
        notifier.exportJson(widget.sessionId, destination);
    }
  }

  /// Show error dialog with fallback to share sheet option when applicable.
  void _showExportErrorDialog(BuildContext context, ExportState state) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Export Failed'),
        content: Text(
          state.errorMessage ?? 'An unknown error occurred during export.',
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              ref.read(exportProvider.notifier).reset();
            },
            child: const Text('OK'),
          ),
          if (state.showShareSheetFallback)
            FilledButton.icon(
              icon: const Icon(Icons.share),
              label: const Text('Share Instead'),
              onPressed: () {
                Navigator.pop(dialogContext);
                ref.read(exportProvider.notifier).shareViaShareSheet();
              },
            ),
        ],
      ),
    );
  }

  /// Shows a rename dialog and persists the new name.
  Future<void> _renameSession(
    BuildContext context,
    WidgetRef ref,
    Session session,
  ) async {
    final newName = await _showRenameDialog(context, session.name);
    if (newName == null || !context.mounted) return;
    final repo = ref.read(sessionRepositoryProvider);
    await repo.rename(session.id, newName.isEmpty ? null : newName);
    ref.invalidate(sessionDetailProvider(widget.sessionId));
    ref.invalidate(sessionsProvider);
  }

  /// Shows a confirmation dialog and deletes the session if confirmed.
  Future<void> _confirmDeleteSession(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete Session'),
        content: const Text(
          'This will permanently delete this session and all its data. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      final sessionRepo = ref.read(sessionRepositoryProvider);
      await sessionRepo.delete(widget.sessionId);
      ref.invalidate(sessionsProvider);

      if (context.mounted) {
        context.pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Session deleted'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }
}

/// Displays the GPS path as a track line with sector colors on a dark background.
class _TrackMapSection extends StatelessWidget {
  const _TrackMapSection({required this.samples});

  final List<GpsSample> samples;

  @override
  Widget build(BuildContext context) {
    if (samples.isEmpty) {
      return const SizedBox(
        height: 200,
        child: Center(child: Text('No GPS data available')),
      );
    }

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
              width: double.infinity,
              child: CustomPaint(
                painter: _TrackLinePainter(samples: samples),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Displays a speed-over-time line chart using fl_chart.
class _SpeedGraphSection extends StatelessWidget {
  const _SpeedGraphSection({required this.speedTrace});

  final List<SpeedTracePoint> speedTrace;

  @override
  Widget build(BuildContext context) {
    if (speedTrace.isEmpty) {
      return const SizedBox(
        height: 150,
        child: Center(child: Text('No speed data available')),
      );
    }

    final maxSpeed = speedTrace
        .map((p) => p.speedKmh)
        .reduce((a, b) => a > b ? a : b);

    final spots = speedTrace
        .map((p) => FlSpot(p.index.toDouble(), p.speedKmh))
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Speed',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 180,
          child: LineChart(
            LineChartData(
              minY: 0,
              maxY: (maxSpeed * 1.1).ceilToDouble(),
              gridData: const FlGridData(show: true),
              titlesData: FlTitlesData(
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 45,
                    getTitlesWidget: (value, meta) {
                      return Text(
                        '${value.toInt()}',
                        style: const TextStyle(fontSize: 10),
                      );
                    },
                  ),
                ),
                bottomTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                topTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                rightTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
              ),
              borderData: FlBorderData(show: false),
              lineBarsData: [
                LineChartBarData(
                  spots: spots,
                  isCurved: true,
                  curveSmoothness: 0.2,
                  color: Theme.of(context).colorScheme.primary,
                  barWidth: 2,
                  dotData: const FlDotData(show: false),
                  belowBarData: BarAreaData(
                    show: true,
                    color: Theme.of(context)
                        .colorScheme
                        .primary
                        .withValues(alpha: 0.1),
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
                          fontSize: 12,
                        ),
                      );
                    }).toList();
                  },
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Displays the lap list with lap number, lap time, and sector times.
/// Highlights the best lap and best sector times.
class _LapListSection extends StatelessWidget {
  const _LapListSection({
    required this.laps,
    required this.analytics,
  });

  final List<Lap> laps;
  final dynamic analytics;

  @override
  Widget build(BuildContext context) {
    // Determine best sector times from analytics or compute from laps
    final bestSector1Ms = _findBestSectorTime(laps, 1);
    final bestSector2Ms = _findBestSectorTime(laps, 2);
    final bestSector3Ms = _findBestSectorTime(laps, 3);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Laps',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        ...laps.map((lap) => _LapRow(
              lap: lap,
              bestSector1Ms: bestSector1Ms,
              bestSector2Ms: bestSector2Ms,
              bestSector3Ms: bestSector3Ms,
            )),
      ],
    );
  }

  int? _findBestSectorTime(List<Lap> laps, int sector) {
    int? best;
    for (final lap in laps) {
      final sectorTime = switch (sector) {
        1 => lap.sector1Ms,
        2 => lap.sector2Ms,
        3 => lap.sector3Ms,
        _ => null,
      };
      if (sectorTime != null && (best == null || sectorTime < best)) {
        best = sectorTime;
      }
    }
    return best;
  }
}

/// A single lap row displaying lap number, lap time, and sector times.
class _LapRow extends StatelessWidget {
  const _LapRow({
    required this.lap,
    this.bestSector1Ms,
    this.bestSector2Ms,
    this.bestSector3Ms,
  });

  final Lap lap;
  final int? bestSector1Ms;
  final int? bestSector2Ms;
  final int? bestSector3Ms;

  @override
  Widget build(BuildContext context) {
    final isBestLap = lap.isBestLap;
    final bestLapColor = Colors.amber.shade700;
    final bestSectorColor = Colors.purple.shade400;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: isBestLap
            ? Colors.amber.shade50
            : Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(8),
        border: isBestLap
            ? Border.all(color: bestLapColor, width: 1.5)
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Lap number
              SizedBox(
                width: 50,
                child: Text(
                  'Lap ${lap.lapNumber}',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: isBestLap ? bestLapColor : null,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Lap time
              Text(
                formatLapTime(lap.lapTimeMs),
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: isBestLap ? bestLapColor : null,
                ),
              ),
              if (isBestLap) ...[
                const SizedBox(width: 8),
                Icon(Icons.emoji_events, color: bestLapColor, size: 18),
              ],
            ],
          ),
          const SizedBox(height: 4),
          // Sector times
          Row(
            children: [
              _SectorChip(
                label: 'S1',
                timeMs: lap.sector1Ms,
                isBest: lap.sector1Ms != null &&
                    lap.sector1Ms == bestSector1Ms,
                bestColor: bestSectorColor,
              ),
              const SizedBox(width: 8),
              _SectorChip(
                label: 'S2',
                timeMs: lap.sector2Ms,
                isBest: lap.sector2Ms != null &&
                    lap.sector2Ms == bestSector2Ms,
                bestColor: bestSectorColor,
              ),
              const SizedBox(width: 8),
              _SectorChip(
                label: 'S3',
                timeMs: lap.sector3Ms,
                isBest: lap.sector3Ms != null &&
                    lap.sector3Ms == bestSector3Ms,
                bestColor: bestSectorColor,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A small chip displaying a sector label and time.
class _SectorChip extends StatelessWidget {
  const _SectorChip({
    required this.label,
    required this.timeMs,
    required this.isBest,
    required this.bestColor,
  });

  final String label;
  final int? timeMs;
  final bool isBest;
  final Color bestColor;

  @override
  Widget build(BuildContext context) {
    final displayTime =
        timeMs != null ? formatLapTime(timeMs!) : '--:--.---';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: isBest ? bestColor.withValues(alpha: 0.15) : Colors.grey.shade100,
        borderRadius: BorderRadius.circular(4),
        border: isBest ? Border.all(color: bestColor, width: 1) : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$label ',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: isBest ? bestColor : Colors.grey.shade600,
            ),
          ),
          Text(
            displayTime,
            style: TextStyle(
              fontSize: 11,
              fontWeight: isBest ? FontWeight.bold : FontWeight.normal,
              color: isBest ? bestColor : null,
            ),
          ),
        ],
      ),
    );
  }
}

/// Shown when no laps were detected for the session.
/// Displays a message in place of the lap list.
class _NoLapsSection extends StatelessWidget {
  const _NoLapsSection();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Icon(
            Icons.info_outline,
            size: 48,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 12),
          Text(
            'No laps detected',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 4),
          Text(
            'This session does not have a detected track or lap crossings.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        ],
      ),
    );
  }
}

// Export flow is now handled by the two-step bottom sheet methods
// in _SessionDetailScreenState (_showFormatSelectionSheet and
// _showDestinationSelectionSheet) with error handling via _showExportErrorDialog.

/// Displays overall session metrics (duration, distance, laps, speeds).
class _SessionMetricsSection extends StatelessWidget {
  const _SessionMetricsSection({required this.analytics});

  final SessionAnalytics analytics;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Session Overview',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _MetricTile(
                    icon: Icons.timer_outlined,
                    label: 'Duration',
                    value: formatDuration(analytics.durationSeconds.round()),
                  ),
                ),
                Expanded(
                  child: _MetricTile(
                    icon: Icons.straighten_outlined,
                    label: 'Distance',
                    value: '${analytics.distanceKm.toStringAsFixed(2)} km',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _MetricTile(
                    icon: Icons.loop,
                    label: 'Laps',
                    value: '${analytics.totalLaps}',
                  ),
                ),
                Expanded(
                  child: _MetricTile(
                    icon: Icons.speed_outlined,
                    label: 'Max Speed',
                    value: '${analytics.maxSpeedKmh.toStringAsFixed(1)} km/h',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _MetricTile(
                    icon: Icons.emoji_events_outlined,
                    label: 'Best Lap',
                    value: analytics.bestLapTimeMs != null
                        ? formatLapTime(analytics.bestLapTimeMs!)
                        : '--',
                  ),
                ),
                Expanded(
                  child: _MetricTile(
                    icon: Icons.speed,
                    label: 'Avg Speed',
                    value:
                        '${analytics.averageSpeedKmh.toStringAsFixed(1)} km/h',
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// A metric tile with icon, label, and value.
class _MetricTile extends StatelessWidget {
  const _MetricTile({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(icon, size: 18, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            Text(
              value,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Custom painter that draws the track line with 3 sector colors
/// on a dark background, similar to F1-style circuit diagrams.
class _TrackLinePainter extends CustomPainter {
  final List<GpsSample> samples;

  static const _sectorColors = [
    Color(0xFFE53935), // Sector 1 - Red
    Color(0xFF00E5FF), // Sector 2 - Cyan
    Color(0xFFFFAB00), // Sector 3 - Orange/Yellow
  ];

  _TrackLinePainter({required this.samples});

  @override
  void paint(Canvas canvas, Size size) {
    if (samples.length < 2) return;

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

    final points = samples.map((s) {
      final x = translateX + (s.longitude - minLng) * scale;
      final y = translateY + (maxLat - s.latitude) * scale;
      return Offset(x, y);
    }).toList();

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

    // Start/finish marker
    if (points.isNotEmpty) {
      final markerPaint = Paint()
        ..color = Colors.white
        ..style = PaintingStyle.fill;
      canvas.drawCircle(points.first, 4, markerPaint);

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
