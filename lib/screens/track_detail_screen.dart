import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../models/session.dart';
import '../models/session_analytics.dart';
import '../providers/analytics_provider.dart';
import '../providers/track_provider.dart';
import '../utils/time_formatter.dart';
import '../widgets/track_painter.dart';

/// Screen displaying track detail with associated sessions.
///
/// Shows track metadata (name, session count, last driven) and a list
/// of all sessions recorded on this track, each navigable to Session Detail.
///
/// Validates: Requirements 7.4, 8.3, 8.4, 11.1, 11.2, 11.3
class TrackDetailScreen extends ConsumerWidget {
  const TrackDetailScreen({super.key, required this.trackId});

  final String trackId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final trackDetailAsync = ref.watch(trackDetailProvider(trackId));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Track Detail'),
        actions: [
          IconButton(
            icon: const Icon(Icons.compare_arrows),
            tooltip: 'Compare Laps',
            onPressed: () => context.push('/lap-comparison/$trackId'),
          ),
        ],
      ),
      body: trackDetailAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Text(
              'Failed to load track: $error',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
              textAlign: TextAlign.center,
            ),
          ),
        ),
        data: (detail) {
          if (detail == null) {
            return const Center(child: Text('Track not found'));
          }

          return _TrackDetailContent(detail: detail);
        },
      ),
    );
  }
}

/// Main content of the track detail screen.
class _TrackDetailContent extends StatelessWidget {
  const _TrackDetailContent({required this.detail});

  final TrackDetail detail;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final track = detail.track;
    final sessions = detail.sessions;
    final trackName = track.name ?? 'Unnamed Track';

    return ListView(
      padding: const EdgeInsets.all(16.0),
      children: [
        // Track info header
        Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: theme.colorScheme.outlineVariant),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  trackName,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Icon(
                      Icons.timer_outlined,
                      size: 16,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${sessions.length} ${sessions.length == 1 ? 'session' : 'sessions'}',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(width: 24),
                    Icon(
                      Icons.calendar_today_outlined,
                      size: 16,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Last driven: ${_formatDate(track.lastDriven)}',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),

        // Circuit map
        if (track.polyline.length >= 2)
          Card(
            color: const Color(0xFF2D2D2D),
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'CIRCUIT',
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: Colors.grey[400],
                      letterSpacing: 1.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 220,
                    width: double.infinity,
                    child: CustomPaint(
                      painter: TrackLinePainter(
                        points: track.polyline,
                        sector1Fraction: track.sector1Fraction,
                        sector2Fraction: track.sector2Fraction,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

        const SizedBox(height: 24),

        // Sessions section header
        Text(
          'Sessions on this track',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 12),

        // Sessions list or empty state
        if (sessions.isEmpty)
          _EmptySessionsState()
        else
          ...sessions.map(
            (session) => _TrackSessionCard(session: session),
          ),
      ],
    );
  }

  String _formatDate(int epochMs) {
    final date = DateTime.fromMillisecondsSinceEpoch(epochMs);
    return DateFormat.yMMMd().format(date);
  }
}

/// Empty state when no sessions are associated with the track.
class _EmptySessionsState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Icon(
            Icons.info_outline,
            size: 48,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 12),
          Text(
            'No sessions recorded on this track yet',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

/// A card for a session associated with this track.
/// Tapping navigates to the Session Detail screen.
class _TrackSessionCard extends ConsumerWidget {
  const _TrackSessionCard({required this.session});

  final Session session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final analyticsAsync = ref.watch(sessionAnalyticsProvider(session.id));
    final theme = Theme.of(context);

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 12.0),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: InkWell(
        onTap: () => context.push('/session/${session.id}'),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Session name + chevron
              Row(
                children: [
                  Expanded(
                    child: Text(
                      session.name ?? 'Unnamed Session',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Icon(
                    Icons.chevron_right,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
              const SizedBox(height: 4),
              // Date row
              Row(
                children: [
                  Icon(
                    Icons.calendar_today_outlined,
                    size: 14,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    _formatSessionDate(session.startTime),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // Metrics
              analyticsAsync.when(
                data: (analytics) =>
                    _SessionMetrics(session: session, analytics: analytics),
                loading: () => const SizedBox(
                  height: 32,
                  child: Center(
                    child: SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                ),
                error: (_, _) =>
                    _SessionMetrics(session: session, analytics: null),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatSessionDate(int epochMs) {
    final date = DateTime.fromMillisecondsSinceEpoch(epochMs);
    return DateFormat.yMMMd().add_jm().format(date);
  }
}

/// Displays key metrics for a session within the track detail view.
class _SessionMetrics extends StatelessWidget {
  const _SessionMetrics({required this.session, required this.analytics});

  final Session session;
  final SessionAnalytics? analytics;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final durationDisplay = _getDurationDisplay();
    final bestLapDisplay = _getBestLapDisplay();
    final lapsDisplay = _getLapsDisplay();

    return Wrap(
      spacing: 16,
      runSpacing: 4,
      children: [
        _MetricItem(
          icon: Icons.timer_outlined,
          value: durationDisplay,
          theme: theme,
        ),
        _MetricItem(
          icon: Icons.emoji_events_outlined,
          value: bestLapDisplay,
          theme: theme,
        ),
        _MetricItem(
          icon: Icons.loop,
          value: '$lapsDisplay laps',
          theme: theme,
        ),
      ],
    );
  }

  String _getDurationDisplay() {
    if (analytics != null) {
      return formatDuration(analytics!.durationSeconds.round());
    }
    if (session.durationMs != null) {
      return formatDuration(session.durationMs! ~/ 1000);
    }
    return '--:--';
  }

  String _getBestLapDisplay() {
    if (analytics != null && analytics!.bestLapTimeMs != null) {
      return formatLapTime(analytics!.bestLapTimeMs!);
    }
    return '--:--.---';
  }

  String _getLapsDisplay() {
    if (analytics != null) {
      return '${analytics!.totalLaps}';
    }
    return '--';
  }
}

/// A compact metric item with icon and value.
class _MetricItem extends StatelessWidget {
  const _MetricItem({
    required this.icon,
    required this.value,
    required this.theme,
  });

  final IconData icon;
  final String value;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(width: 4),
        Text(
          value,
          style: theme.textTheme.bodySmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
