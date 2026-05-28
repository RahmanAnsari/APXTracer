import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart' as geo;

import '../models/lap.dart';
import '../models/session.dart';
import '../models/session_analytics.dart';
import '../models/track.dart';
import '../providers/analytics_provider.dart';
import '../providers/export_provider.dart';
import '../providers/recording_provider.dart';
import '../providers/session_provider.dart';
import '../providers/track_provider.dart';
import '../utils/time_formatter.dart';
import '../widgets/track_painter.dart';

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
  bool _isReassigning = false;
  int? _touchedTimestamp;

  @override
  Widget build(BuildContext context) {
    final detailAsync = ref.watch(sessionDetailProvider(widget.sessionId));
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
            icon: const Icon(Icons.compare_arrows),
            tooltip: 'Compare Laps',
            onPressed: detailAsync.maybeWhen(
              data: (detail) {
                final trackId = detail?.session.trackId;
                if (trackId == null) return null;
                return () => context.push(
                      '/lap-comparison/$trackId?sessionId=${detail!.session.id}',
                    );
              },
              orElse: () => null,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.flag_outlined),
            tooltip: 'Change track',
            onPressed: _isReassigning
                ? null
                : detailAsync.maybeWhen(
                    data: (detail) => detail != null
                        ? () => _reassignTrack(context, detail.session)
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
      body: Stack(
        children: [
          detailAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, stack) => Center(
              child: Text('Error loading session: $error'),
            ),
            data: (detail) {
              if (detail == null) {
                return const Center(child: Text('Session not found'));
              }

              return speedTraceAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (error, stack) => Center(
                  child: Text('Error loading speed data: $error'),
                ),
                data: (speedTrace) {
                  return _buildContent(context, detail, speedTrace);
                },
              );
            },
          ),
          if (_isReassigning)
            Positioned.fill(
              child: ColoredBox(
                color: Colors.black54,
                child: const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(color: Colors.white),
                      SizedBox(height: 16),
                      Text(
                        'Re-processing session...',
                        style: TextStyle(color: Colors.white, fontSize: 16),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildContent(
    BuildContext context,
    SessionDetail detail,
    List<SpeedTracePoint> speedTrace,
  ) {
    final hasLaps = detail.laps.isNotEmpty;
    final trackAsync = ref.watch(sessionTrackProvider(widget.sessionId));
    final trackName = trackAsync.valueOrNull?.name ??
        (detail.session.trackId != null ? 'Unnamed Track' : null);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Overall session metrics
        if (detail.analytics != null)
          _SessionMetricsSection(
            analytics: detail.analytics!,
            trackName: trackName,
          ),
        if (detail.analytics != null) const SizedBox(height: 16),

        // Track visualization (dark background, sector colors)
        _TrackMapSection(
          sessionId: widget.sessionId,
          touchedTimestamp: _touchedTimestamp,
        ),
        const SizedBox(height: 16),

        // Speed graph
        _SpeedGraphSection(
          speedTrace: speedTrace,
          onTimestampTouched: (ts) {
            if (_touchedTimestamp != ts) {
              setState(() => _touchedTimestamp = ts);
            }
          },
        ),
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

  /// Shows the track picker and re-runs the pipeline against the chosen track.
  Future<void> _reassignTrack(BuildContext context, Session session) async {
    final selection =
        await _showReassignTrackPicker(context, session.trackId);
    if (selection == null || !mounted) return; // dismissed

    // '' means "unlink", non-empty string means new track ID
    final String? newTrackId = selection.isEmpty ? null : selection;
    if (newTrackId == session.trackId) return; // no change

    setState(() => _isReassigning = true);

    try {
      // Correct the old track's session count before relinking
      if (session.trackId != null) {
        await _decrementTrackSessionCount(session.trackId!, session.id);
      }

      // Clear stale lap and analytics data computed against the wrong geometry
      await ref.read(lapRepositoryProvider).deleteBySessionId(session.id);
      await ref
          .read(analyticsRepositoryProvider)
          .deleteBySessionId(session.id);

      if (newTrackId != null) {
        // Re-run lap detection + sector times + analytics for the correct track
        await ref.read(postSessionPipelineProvider).execute(
              session.id,
              preSelectedTrackId: newTrackId,
            );
      } else {
        // Unlink: just clear track_id; no laps/analytics without a track
        await ref.read(sessionRepositoryProvider).update(Session(
              id: session.id,
              name: session.name,
              startTime: session.startTime,
              endTime: session.endTime,
              durationMs: session.durationMs,
              trackId: null,
            ));
      }

      // Refresh every provider that depends on this session or either track
      ref.invalidate(sessionDetailProvider(widget.sessionId));
      ref.invalidate(sessionTrackProvider(widget.sessionId));
      ref.invalidate(sessionsProvider);
      ref.invalidate(trackNotifierProvider);
      if (session.trackId != null) {
        ref.invalidate(trackDetailProvider(session.trackId!));
      }
      if (newTrackId != null) {
        ref.invalidate(trackDetailProvider(newTrackId));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to change track: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isReassigning = false);
    }
  }

  /// Recalculates [trackId]'s session count after [excludeSessionId] is removed.
  Future<void> _decrementTrackSessionCount(
    String trackId,
    String excludeSessionId,
  ) async {
    final trackRepo = ref.read(trackRepositoryProvider);
    final sessionRepo = ref.read(sessionRepositoryProvider);

    final track = await trackRepo.getById(trackId);
    if (track == null) return;

    final remaining = (await sessionRepo.getByTrackId(trackId))
        .where((s) => s.id != excludeSessionId)
        .toList();

    await trackRepo.update(Track(
      id: track.id,
      name: track.name,
      polyline: track.polyline,
      startFinish: track.startFinish,
      sector1Fraction: track.sector1Fraction,
      sector2Fraction: track.sector2Fraction,
      lengthM: track.lengthM,
      sessionCount: remaining.length,
      lastDriven: remaining.isNotEmpty
          ? remaining
              .map((s) => s.startTime)
              .reduce((a, b) => a > b ? a : b)
          : track.lastDriven,
    ));
  }

  /// Shows a bottom sheet of saved tracks.
  ///
  /// Returns:
  /// - `null`  — dismissed, take no action
  /// - `''`    — user chose to unlink
  /// - track ID — user chose to reassign to that track
  Future<String?> _showReassignTrackPicker(
    BuildContext context,
    String? currentTrackId,
  ) {
    final tracks = ref.read(trackNotifierProvider).valueOrNull ?? [];

    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        final theme = Theme.of(ctx);
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Text(
                  'Change Track',
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              const Divider(height: 1),
              // Unlink option
              ListTile(
                leading: Icon(Icons.link_off,
                    color: theme.colorScheme.error),
                title: Text(
                  'Unlink track',
                  style: TextStyle(color: theme.colorScheme.error),
                ),
                subtitle: const Text(
                    'Remove track association and clear lap data'),
                onTap: () => Navigator.pop(ctx, ''),
              ),
              if (tracks.isNotEmpty) ...[
                const Divider(height: 1),
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight:
                        MediaQuery.of(ctx).size.height * 0.4,
                  ),
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: tracks.length,
                    itemBuilder: (_, i) {
                      final track = tracks[i];
                      final isCurrent = track.id == currentTrackId;
                      return ListTile(
                        leading: Icon(
                          Icons.flag_outlined,
                          color: isCurrent
                              ? theme.colorScheme.primary
                              : null,
                        ),
                        title: Text(track.name ?? 'Unnamed Track'),
                        subtitle: Text(
                          '${track.sessionCount} '
                          '${track.sessionCount == 1 ? 'session' : 'sessions'}',
                        ),
                        trailing: isCurrent
                            ? Icon(Icons.check,
                                color: theme.colorScheme.primary)
                            : null,
                        // Disable tapping the already-assigned track
                        onTap: isCurrent
                            ? null
                            : () => Navigator.pop(ctx, track.id),
                      );
                    },
                  ),
                ),
              ],
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }
}

/// Displays the refined circuit polyline with sector colors on a dark background.
class _TrackMapSection extends ConsumerWidget {
  const _TrackMapSection({
    required this.sessionId,
    this.touchedTimestamp,
  });

  final String sessionId;
  final int? touchedTimestamp;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final trackAsync = ref.watch(sessionTrackProvider(sessionId));
    final samplesAsync = ref.watch(sessionGpsSamplesProvider(sessionId));

    geo.LatLng? marker;
    if (touchedTimestamp != null) {
      final samples = samplesAsync.valueOrNull;
      if (samples != null && samples.isNotEmpty) {
        final pos = nearestPosition(samples, touchedTimestamp!);
        if (pos != null) {
          marker = geo.LatLng(pos.latitude, pos.longitude);
        }
      }
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
              child: trackAsync.when(
                loading: () =>
                    const Center(child: CircularProgressIndicator()),
                error: (e, _) =>
                    Center(child: Text('Error loading circuit: $e')),
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
                      markerA: marker,
                      markerAColor: Colors.white,
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
}

/// Displays a speed-over-time line chart using fl_chart.
class _SpeedGraphSection extends StatelessWidget {
  const _SpeedGraphSection({
    required this.speedTrace,
    this.onTimestampTouched,
  });

  final List<SpeedTracePoint> speedTrace;
  final ValueChanged<int?>? onTimestampTouched;

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
                touchCallback: (event, response) {
                  if (onTimestampTouched == null) return;
                  final spot = response?.lineBarSpots?.firstOrNull;
                  if (spot != null) {
                    final idx = spot.x.round().clamp(0, speedTrace.length - 1);
                    onTimestampTouched!(speedTrace[idx].timestamp);
                  } else {
                    onTimestampTouched!(null);
                  }
                },
                touchTooltipData: LineTouchTooltipData(
                  getTooltipColor: (_) => Colors.black87,
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
  const _SessionMetricsSection({
    required this.analytics,
    this.trackName,
  });

  final SessionAnalytics analytics;
  final String? trackName;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
                    'Session Overview',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
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
                    trackName!,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ],
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
