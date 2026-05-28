import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart' as geo;

import '../models/lap.dart';
import '../models/session.dart';
import '../models/track.dart';
import '../providers/lap_comparison_provider.dart';
import '../providers/track_provider.dart';
import '../utils/time_formatter.dart';
import '../widgets/track_painter.dart';

const Color _colorA = Color(0xFF1565C0);
const Color _colorB = Color(0xFFE65100);

/// A session + lap pairing representing one slot in the comparison.
class SelectedLap {
  final Session session;
  final Lap lap;
  const SelectedLap({required this.session, required this.lap});
}

/// Side-by-side speed trace comparison for any two laps from any two sessions
/// on the same track.
///
/// Accessible from Track Detail and Session Detail.
class LapComparisonScreen extends ConsumerStatefulWidget {
  const LapComparisonScreen({
    super.key,
    required this.trackId,
    this.preSessionId,
  });

  final String trackId;

  /// When provided, pre-selects the best lap of this session as Lap A.
  final String? preSessionId;

  @override
  ConsumerState<LapComparisonScreen> createState() =>
      _LapComparisonScreenState();
}

class _LapComparisonScreenState extends ConsumerState<LapComparisonScreen> {
  SelectedLap? _lapA;
  SelectedLap? _lapB;
  // Progress fraction (0.0–1.0) of the currently touched speed-graph point.
  double? _touchedProgress;

  @override
  void initState() {
    super.initState();
    if (widget.preSessionId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        final data =
            await ref.read(trackSessionLapsProvider(widget.trackId).future);
        if (!mounted) return;
        final entry = data
            .where((e) => e.session.id == widget.preSessionId)
            .firstOrNull;
        if (entry != null && entry.laps.isNotEmpty) {
          final best =
              entry.laps.where((l) => l.isBestLap).firstOrNull ??
              entry.laps.first;
          setState(() {
            _lapA = SelectedLap(session: entry.session, lap: best);
          });
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final sessionsAsync =
        ref.watch(trackSessionLapsProvider(widget.trackId));
    final track =
        ref.watch(trackDetailProvider(widget.trackId)).valueOrNull?.track;

    return Scaffold(
      appBar: AppBar(title: const Text('Lap Comparison')),
      body: sessionsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text('Failed to load laps: $e'),
          ),
        ),
        data: (sessions) {
          if (sessions.isEmpty) {
            return const _EmptyState();
          }
          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Lap selector cards
                Row(
                  children: [
                    Expanded(
                      child: _LapSelectorCard(
                        label: 'Lap A',
                        color: _colorA,
                        selected: _lapA,
                        onTap: () =>
                            _openPicker(context, sessions, isA: true),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _LapSelectorCard(
                        label: 'Lap B',
                        color: _colorB,
                        selected: _lapB,
                        onTap: () =>
                            _openPicker(context, sessions, isA: false),
                      ),
                    ),
                  ],
                ),

                if (_lapA != null && _lapB != null) ...[
                  const SizedBox(height: 16),
                  _DeltaBanner(lapA: _lapA!.lap, lapB: _lapB!.lap),
                  const SizedBox(height: 16),
                  _SpeedComparisonSection(
                    lapA: _lapA!,
                    lapB: _lapB!,
                    track: track,
                    touchedProgress: _touchedProgress,
                    onProgressTouched: (p) {
                      if (_touchedProgress != p) {
                        setState(() => _touchedProgress = p);
                      }
                    },
                  ),
                  const SizedBox(height: 16),
                  _SectorComparisonSection(
                    lapA: _lapA!.lap,
                    lapB: _lapB!.lap,
                  ),
                ] else ...[
                  const SizedBox(height: 40),
                  const _SelectionHint(),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  void _openPicker(
    BuildContext context,
    List<SessionWithLaps> sessions, {
    required bool isA,
  }) {
    final otherLap = isA ? _lapB?.lap : _lapA?.lap;
    final currentLap = isA ? _lapA?.lap : _lapB?.lap;

    showModalBottomSheet<SelectedLap>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => _LapPickerSheet(
        sessions: sessions,
        otherLap: otherLap,
        currentLap: currentLap,
      ),
    ).then((selected) {
      if (selected == null || !mounted) return;
      setState(() {
        if (isA) {
          _lapA = selected;
        } else {
          _lapB = selected;
        }
      });
    });
  }
}

// ─── Lap selector card ─────────────────────────────────────────────────────

class _LapSelectorCard extends StatelessWidget {
  const _LapSelectorCard({
    required this.label,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final Color color;
  final SelectedLap? selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lap = selected?.lap;
    final session = selected?.session;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          border: Border.all(color: color, width: 1.5),
          borderRadius: BorderRadius.circular(12),
          color: color.withValues(alpha: 0.05),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.flag_outlined, size: 14, color: color),
                const SizedBox(width: 4),
                Text(
                  label,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: color,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                  ),
                ),
                const Spacer(),
                Icon(
                  Icons.edit_outlined,
                  size: 14,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (lap != null && session != null) ...[
              Text(
                session.name ?? _shortDate(session.startTime),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Text(
                'Lap ${lap.lapNumber}',
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                formatLapTime(lap.lapTimeMs),
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
            ] else ...[
              Text(
                'Tap to select',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _shortDate(int epochMs) {
    final d = DateTime.fromMillisecondsSinceEpoch(epochMs);
    return DateFormat.MMMd().format(d);
  }
}

// ─── Lap picker sheet ───────────────────────────────────────────────────────

class _LapPickerSheet extends StatelessWidget {
  const _LapPickerSheet({
    required this.sessions,
    required this.otherLap,
    required this.currentLap,
  });

  final List<SessionWithLaps> sessions;
  final Lap? otherLap;
  final Lap? currentLap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: theme.colorScheme.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Text(
              'Select Lap',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const Divider(height: 1),
          ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.55,
            ),
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final entry in sessions) ...[
                  _SessionHeader(session: entry.session),
                  for (final lap in entry.laps)
                    _LapTile(
                      lap: lap,
                      session: entry.session,
                      isSelected: lap.id == currentLap?.id,
                      isDisabled: lap.id == otherLap?.id,
                    ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _SessionHeader extends StatelessWidget {
  const _SessionHeader({required this.session});

  final Session session;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = session.name ??
        DateFormat.yMMMd().add_jm().format(
              DateTime.fromMillisecondsSinceEpoch(session.startTime),
            );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      color: theme.colorScheme.surfaceContainerLow,
      child: Text(
        label,
        style: theme.textTheme.labelMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _LapTile extends StatelessWidget {
  const _LapTile({
    required this.lap,
    required this.session,
    required this.isSelected,
    required this.isDisabled,
  });

  final Lap lap;
  final Session session;
  final bool isSelected;
  final bool isDisabled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasSectors =
        lap.sector1Ms != null && lap.sector2Ms != null && lap.sector3Ms != null;

    return ListTile(
      enabled: !isDisabled,
      selected: isSelected,
      selectedColor: theme.colorScheme.primary,
      selectedTileColor: theme.colorScheme.primary.withValues(alpha: 0.08),
      leading: CircleAvatar(
        radius: 16,
        backgroundColor: lap.isBestLap
            ? Colors.amber.shade700
            : theme.colorScheme.surfaceContainerHigh,
        child: Text(
          '${lap.lapNumber}',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: lap.isBestLap
                ? Colors.white
                : theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
      title: Text(
        formatLapTime(lap.lapTimeMs),
        style: theme.textTheme.bodyMedium?.copyWith(
          fontWeight: FontWeight.w600,
        ),
      ),
      subtitle: hasSectors
          ? Text(
              'S1 ${_ms(lap.sector1Ms)}  S2 ${_ms(lap.sector2Ms)}  S3 ${_ms(lap.sector3Ms)}',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            )
          : null,
      trailing: isDisabled
          ? Text(
              'In use',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            )
          : isSelected
              ? Icon(Icons.check_circle,
                  size: 18, color: theme.colorScheme.primary)
              : null,
      onTap: isDisabled
          ? null
          : () => Navigator.of(context).pop(
                SelectedLap(session: session, lap: lap),
              ),
    );
  }

  String _ms(int? ms) {
    if (ms == null) return '--';
    final s = ms ~/ 1000;
    final r = ms % 1000;
    return '$s.${r.toString().padLeft(3, '0')}';
  }
}

// ─── Delta banner ───────────────────────────────────────────────────────────

class _DeltaBanner extends StatelessWidget {
  const _DeltaBanner({required this.lapA, required this.lapB});

  final Lap lapA;
  final Lap lapB;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final deltaMs = lapB.lapTimeMs - lapA.lapTimeMs;
    final faster = deltaMs < 0 ? 'B' : (deltaMs > 0 ? 'A' : null);
    final deltaStr = _formatDelta(deltaMs);
    final deltaColor = deltaMs < 0
        ? Colors.green.shade700
        : deltaMs > 0
            ? Colors.red.shade700
            : theme.colorScheme.onSurfaceVariant;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Lap A',
                    style: theme.textTheme.labelSmall
                        ?.copyWith(color: _colorA, fontWeight: FontWeight.w700),
                  ),
                  Text(
                    formatLapTime(lapA.lapTimeMs),
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: _colorA,
                    ),
                  ),
                ],
              ),
            ),
            Column(
              children: [
                Text(
                  deltaStr,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: deltaColor,
                  ),
                ),
                if (faster != null)
                  Text(
                    'Lap $faster faster',
                    style: theme.textTheme.labelSmall
                        ?.copyWith(color: deltaColor),
                  ),
              ],
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    'Lap B',
                    style: theme.textTheme.labelSmall
                        ?.copyWith(color: _colorB, fontWeight: FontWeight.w700),
                  ),
                  Text(
                    formatLapTime(lapB.lapTimeMs),
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: _colorB,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDelta(int deltaMs) {
    final abs = deltaMs.abs();
    final s = abs ~/ 1000;
    final ms = abs % 1000;
    final sign = deltaMs >= 0 ? '+' : '-';
    return '$sign$s.${ms.toString().padLeft(3, '0')}s';
  }
}

// ─── Speed comparison section ───────────────────────────────────────────────

class _SpeedComparisonSection extends ConsumerWidget {
  const _SpeedComparisonSection({
    required this.lapA,
    required this.lapB,
    required this.track,
    required this.touchedProgress,
    required this.onProgressTouched,
  });

  final SelectedLap lapA;
  final SelectedLap lapB;
  final Track? track;
  final double? touchedProgress;
  final ValueChanged<double?> onProgressTouched;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final keyA = LapSpeedKey(
      sessionId: lapA.session.id,
      startTimestamp: lapA.lap.startTimestamp,
      endTimestamp: lapA.lap.endTimestamp,
    );
    final keyB = LapSpeedKey(
      sessionId: lapB.session.id,
      startTimestamp: lapB.lap.startTimestamp,
      endTimestamp: lapB.lap.endTimestamp,
    );

    final traceAAsync = ref.watch(lapSpeedTraceProvider(keyA));
    final traceBAsync = ref.watch(lapSpeedTraceProvider(keyB));

    final theme = Theme.of(context);

    // Resolve marker positions from the touched progress.
    geo.LatLng? markerA;
    geo.LatLng? markerB;
    if (touchedProgress != null) {
      final traceA = traceAAsync.valueOrNull;
      final traceB = traceBAsync.valueOrNull;
      if (traceA != null && traceA.isNotEmpty) {
        final pt = _nearestByProgress(traceA, touchedProgress!);
        markerA = geo.LatLng(pt.latitude, pt.longitude);
      }
      if (traceB != null && traceB.isNotEmpty) {
        final pt = _nearestByProgress(traceB, touchedProgress!);
        markerB = geo.LatLng(pt.latitude, pt.longitude);
      }
    }

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Speed Trace',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            // Legend
            Row(
              children: [
                _LegendDot(color: _colorA),
                const SizedBox(width: 4),
                Text(
                  'Lap A — Lap ${lapA.lap.lapNumber}',
                  style: theme.textTheme.labelSmall,
                ),
                const SizedBox(width: 16),
                _LegendDot(color: _colorB),
                const SizedBox(width: 4),
                Text(
                  'Lap B — Lap ${lapB.lap.lapNumber}',
                  style: theme.textTheme.labelSmall,
                ),
              ],
            ),
            // Track map with two markers (shown when track available)
            if (track != null) ...[
              const SizedBox(height: 12),
              SizedBox(
                height: 180,
                width: double.infinity,
                child: CustomPaint(
                  painter: TrackLinePainter(
                    points: track!.polyline,
                    sector1Fraction: track!.sector1Fraction,
                    sector2Fraction: track!.sector2Fraction,
                    markerA: markerA,
                    markerB: markerB,
                    markerAColor: _colorA,
                    markerBColor: _colorB,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 12),
            if (traceAAsync.isLoading || traceBAsync.isLoading)
              const SizedBox(
                height: 200,
                child: Center(child: CircularProgressIndicator()),
              )
            else if (traceAAsync.hasError || traceBAsync.hasError)
              const SizedBox(
                height: 80,
                child: Center(child: Text('Error loading speed data')),
              )
            else
              _ComparisonChart(
                traceA: traceAAsync.value ?? [],
                traceB: traceBAsync.value ?? [],
                track: track,
                onProgressTouched: onProgressTouched,
              ),
          ],
        ),
      ),
    );
  }

  /// Returns the [LapSpeedPoint] from [trace] whose progress is closest to [target].
  LapSpeedPoint _nearestByProgress(List<LapSpeedPoint> trace, double target) {
    LapSpeedPoint best = trace.first;
    double bestDiff = (best.progress - target).abs();
    for (final p in trace) {
      final d = (p.progress - target).abs();
      if (d < bestDiff) {
        bestDiff = d;
        best = p;
      }
    }
    return best;
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 12,
      height: 12,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}

// ─── Comparison chart ───────────────────────────────────────────────────────

class _ComparisonChart extends StatelessWidget {
  const _ComparisonChart({
    required this.traceA,
    required this.traceB,
    required this.track,
    required this.onProgressTouched,
  });

  final List<LapSpeedPoint> traceA;
  final List<LapSpeedPoint> traceB;
  final Track? track;
  final ValueChanged<double?> onProgressTouched;

  @override
  Widget build(BuildContext context) {
    if (traceA.isEmpty && traceB.isEmpty) {
      return const SizedBox(
        height: 200,
        child: Center(child: Text('No speed data available for these laps')),
      );
    }

    final allSpeeds = [
      ...traceA.map((p) => p.speedKmh),
      ...traceB.map((p) => p.speedKmh),
    ];
    final maxSpeed =
        allSpeeds.isEmpty ? 200.0 : allSpeeds.reduce((a, b) => a > b ? a : b);

    final spotsA =
        traceA.map((p) => FlSpot(p.progress * 100, p.speedKmh)).toList();
    final spotsB =
        traceB.map((p) => FlSpot(p.progress * 100, p.speedKmh)).toList();

    final sectorLines = <VerticalLine>[];
    if (track != null) {
      sectorLines.addAll([
        VerticalLine(
          x: track!.sector1Fraction * 100,
          color: Colors.grey.withValues(alpha: 0.6),
          strokeWidth: 1,
          dashArray: [5, 5],
          label: VerticalLineLabel(
            show: true,
            alignment: Alignment.topCenter,
            labelResolver: (_) => 'S2',
            style: const TextStyle(
              color: Colors.grey,
              fontSize: 9,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        VerticalLine(
          x: track!.sector2Fraction * 100,
          color: Colors.grey.withValues(alpha: 0.6),
          strokeWidth: 1,
          dashArray: [5, 5],
          label: VerticalLineLabel(
            show: true,
            alignment: Alignment.topCenter,
            labelResolver: (_) => 'S3',
            style: const TextStyle(
              color: Colors.grey,
              fontSize: 9,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ]);
    }

    return SizedBox(
      height: 220,
      child: LineChart(
        LineChartData(
          minX: 0,
          maxX: 100,
          minY: 0,
          maxY: (maxSpeed * 1.15).ceilToDouble(),
          clipData: const FlClipData.all(),
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            getDrawingHorizontalLine: (value) => FlLine(
              color: Colors.grey.withValues(alpha: 0.2),
              strokeWidth: 1,
            ),
          ),
          titlesData: FlTitlesData(
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 40,
                interval: 50,
                getTitlesWidget: (value, _) => Text(
                  '${value.toInt()}',
                  style: const TextStyle(fontSize: 10, color: Colors.grey),
                ),
              ),
            ),
            bottomTitles: AxisTitles(
              axisNameWidget: const Text(
                'Lap progress (%)',
                style: TextStyle(fontSize: 10, color: Colors.grey),
              ),
              axisNameSize: 18,
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 22,
                interval: 25,
                getTitlesWidget: (value, _) => Text(
                  '${value.toInt()}%',
                  style: const TextStyle(fontSize: 10, color: Colors.grey),
                ),
              ),
            ),
            topTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            rightTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
          ),
          borderData: FlBorderData(show: false),
          extraLinesData: sectorLines.isNotEmpty
              ? ExtraLinesData(verticalLines: sectorLines)
              : null,
          lineBarsData: [
            if (spotsA.isNotEmpty)
              LineChartBarData(
                spots: spotsA,
                isCurved: true,
                curveSmoothness: 0.15,
                color: _colorA,
                barWidth: 2,
                dotData: const FlDotData(show: false),
              ),
            if (spotsB.isNotEmpty)
              LineChartBarData(
                spots: spotsB,
                isCurved: true,
                curveSmoothness: 0.15,
                color: _colorB,
                barWidth: 2,
                dotData: const FlDotData(show: false),
              ),
          ],
          lineTouchData: LineTouchData(
            touchCallback: (event, response) {
              final spot = response?.lineBarSpots?.firstOrNull;
              if (spot != null) {
                onProgressTouched(spot.x / 100.0);
              } else {
                onProgressTouched(null);
              }
            },
            touchTooltipData: LineTouchTooltipData(
              getTooltipColor: (_) => Colors.black87,
              getTooltipItems: (touchedSpots) {
                return touchedSpots.map((spot) {
                  final isA = spot.barIndex == 0;
                  return LineTooltipItem(
                    '${isA ? 'A' : 'B'}: ${spot.y.toStringAsFixed(1)} km/h',
                    TextStyle(
                      color: isA ? _colorA : _colorB,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  );
                }).toList();
              },
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Sector comparison table ────────────────────────────────────────────────

class _SectorComparisonSection extends StatelessWidget {
  const _SectorComparisonSection({
    required this.lapA,
    required this.lapB,
  });

  final Lap lapA;
  final Lap lapB;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Sector Times',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            // Header row
            Row(
              children: [
                const SizedBox(width: 32),
                Expanded(
                  child: Text(
                    'Lap A',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: _colorA,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    'Lap B',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: _colorB,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    'Δ (B−A)',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
            const Divider(height: 16),
            _SectorRow(
              label: 'S1',
              aMs: lapA.sector1Ms,
              bMs: lapB.sector1Ms,
            ),
            const SizedBox(height: 8),
            _SectorRow(
              label: 'S2',
              aMs: lapA.sector2Ms,
              bMs: lapB.sector2Ms,
            ),
            const SizedBox(height: 8),
            _SectorRow(
              label: 'S3',
              aMs: lapA.sector3Ms,
              bMs: lapB.sector3Ms,
            ),
            const Divider(height: 16),
            _SectorRow(
              label: 'Lap',
              aMs: lapA.lapTimeMs,
              bMs: lapB.lapTimeMs,
              isBold: true,
            ),
          ],
        ),
      ),
    );
  }
}

class _SectorRow extends StatelessWidget {
  const _SectorRow({
    required this.label,
    required this.aMs,
    required this.bMs,
    this.isBold = false,
  });

  final String label;
  final int? aMs;
  final int? bMs;
  final bool isBold;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final delta = (aMs != null && bMs != null) ? bMs! - aMs! : null;
    final deltaColor = delta == null
        ? theme.colorScheme.onSurfaceVariant
        : delta < 0
            ? Colors.green.shade700
            : delta > 0
                ? Colors.red.shade700
                : theme.colorScheme.onSurfaceVariant;

    final style = theme.textTheme.bodySmall?.copyWith(
      fontWeight: isBold ? FontWeight.w700 : FontWeight.normal,
    );

    return Row(
      children: [
        SizedBox(
          width: 32,
          child: Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontWeight: isBold ? FontWeight.w700 : null,
            ),
          ),
        ),
        Expanded(
          child: Text(
            aMs != null ? formatLapTime(aMs!) : '--:--.---',
            textAlign: TextAlign.center,
            style: style?.copyWith(color: _colorA),
          ),
        ),
        Expanded(
          child: Text(
            bMs != null ? formatLapTime(bMs!) : '--:--.---',
            textAlign: TextAlign.center,
            style: style?.copyWith(color: _colorB),
          ),
        ),
        Expanded(
          child: Text(
            _formatDelta(delta),
            textAlign: TextAlign.center,
            style: style?.copyWith(
              color: deltaColor,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }

  String _formatDelta(int? deltaMs) {
    if (deltaMs == null) return '--';
    final abs = deltaMs.abs();
    final s = abs ~/ 1000;
    final ms = abs % 1000;
    final sign = deltaMs >= 0 ? '+' : '-';
    return '$sign$s.${ms.toString().padLeft(3, '0')}';
  }
}

// ─── Empty / hint states ────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.compare_arrows,
              size: 64,
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
            ),
            const SizedBox(height: 16),
            Text(
              'No laps to compare',
              style: theme.textTheme.titleMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Complete at least two sessions on this track to unlock lap comparison.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _SelectionHint extends StatelessWidget {
  const _SelectionHint();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        children: [
          Icon(
            Icons.compare_arrows,
            size: 48,
            color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
          ),
          const SizedBox(height: 12),
          Text(
            'Select two laps above to compare speed traces and sector times.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
