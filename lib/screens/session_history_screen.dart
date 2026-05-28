import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../models/session.dart';
import '../models/session_analytics.dart';
import '../providers/analytics_provider.dart';
import '../providers/session_provider.dart';
import '../providers/track_provider.dart';
import '../utils/time_formatter.dart';

/// Session History screen displaying all recorded sessions in reverse
/// chronological order with key metrics per session.
///
/// Validates: Requirement 8.1 - Sessions in reverse chronological order.
/// Validates: Requirement 8.2 - Correct metrics displayed per session.
/// Validates: Requirement 8.3 - Available offline from locally stored data.
/// Validates: Requirement 8.4 - Tap session navigates to Session Detail.
/// Validates: Requirement 8.6 - Empty state when no sessions exist.
class SessionHistoryScreen extends ConsumerWidget {
  const SessionHistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessionsAsync = ref.watch(sessionsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Session History'),
        centerTitle: true,
      ),
      body: sessionsAsync.when(
        data: (sessions) {
          if (sessions.isEmpty) {
            return const _EmptyState();
          }
          return _SessionList(sessions: sessions);
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => _ErrorState(error: error),
      ),
    );
  }
}

/// Empty state displayed when no sessions have been recorded.
class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.timer_off_outlined,
              size: 64,
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 16),
            Text(
              'No sessions recorded yet',
              style: theme.textTheme.titleMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Start a recording session to see your history here.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton.tonalIcon(
              onPressed: () => context.push('/recording'),
              icon: const Icon(Icons.fiber_manual_record),
              label: const Text('Start Recording'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Scrollable list of session cards.
class _SessionList extends StatelessWidget {
  final List<Session> sessions;

  const _SessionList({required this.sessions});

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      itemCount: sessions.length,
      itemBuilder: (context, index) {
        return _SessionCard(session: sessions[index]);
      },
    );
  }
}

String _formatSessionDate(int epochMs) {
  final date = DateTime.fromMillisecondsSinceEpoch(epochMs);
  final now = DateTime.now();
  final diff = now.difference(date);
  if (diff.inDays == 0) return 'Today at ${_timeOfDay(date)}';
  if (diff.inDays == 1) return 'Yesterday at ${_timeOfDay(date)}';
  return '${date.day}/${date.month}/${date.year} at ${_timeOfDay(date)}';
}

String _timeOfDay(DateTime date) =>
    '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';

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

/// A single session card displaying date and key metrics.
/// Tapping navigates to the Session Detail screen.
/// Swipe left to delete with confirmation.
class _SessionCard extends ConsumerWidget {
  final Session session;

  const _SessionCard({required this.session});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final analyticsAsync = ref.watch(sessionAnalyticsProvider(session.id));
    final trackAsync = ref.watch(sessionTrackProvider(session.id));
    final theme = Theme.of(context);

    return Dismissible(
      key: ValueKey(session.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        margin: const EdgeInsets.only(bottom: 12.0),
        decoration: BoxDecoration(
          color: theme.colorScheme.error,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      confirmDismiss: (direction) async {
        return await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Delete Session'),
            content: const Text(
              'This will permanently delete this session and all its data (GPS samples, laps, analytics). This cannot be undone.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                style: FilledButton.styleFrom(
                  backgroundColor: theme.colorScheme.error,
                ),
                child: const Text('Delete'),
              ),
            ],
          ),
        ) ?? false;
      },
      onDismissed: (direction) async {
        final sessionRepo = ref.read(sessionRepositoryProvider);
        await sessionRepo.delete(session.id);
        // Refresh the sessions list
        ref.invalidate(sessionsProvider);

        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Session deleted'),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      },
      child: Card(
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
              // Name / date header with inline rename action
              Row(
                children: [
                  Icon(
                    Icons.calendar_today_outlined,
                    size: 16,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          session.name ?? _formatSessionDate(session.startTime),
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (session.name != null)
                          Text(
                            _formatSessionDate(session.startTime),
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    color: theme.colorScheme.onSurfaceVariant,
                    visualDensity: VisualDensity.compact,
                    tooltip: 'Rename',
                    onPressed: () async {
                      final newName =
                          await _showRenameDialog(context, session.name);
                      if (newName == null || !context.mounted) return;
                      final repo = ref.read(sessionRepositoryProvider);
                      await repo.rename(
                          session.id, newName.isEmpty ? null : newName);
                      ref.invalidate(sessionsProvider);
                    },
                  ),
                  Icon(
                    Icons.chevron_right,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
              // Circuit name chip
              if (session.trackId != null) ...[
                const SizedBox(height: 6),
                Row(
                  children: [
                    Icon(
                      Icons.flag_outlined,
                      size: 13,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      trackAsync.valueOrNull?.name ?? 'Unnamed Track',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.w500,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 12),
              // Metrics row
              analyticsAsync.when(
                data: (analytics) => _MetricsGrid(
                  session: session,
                  analytics: analytics,
                ),
                loading: () => const SizedBox(
                  height: 48,
                  child: Center(
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                ),
                error: (_, _) => _MetricsGrid(
                  session: session,
                  analytics: null,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
    );
  }

}

/// Grid of session metrics: duration, best lap, total laps, distance, top speed.
class _MetricsGrid extends StatelessWidget {
  final Session session;
  final SessionAnalytics? analytics;

  const _MetricsGrid({
    required this.session,
    required this.analytics,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Compute duration from session if analytics not available
    final durationDisplay = _getDurationDisplay();
    final bestLapDisplay = _getBestLapDisplay();
    final totalLapsDisplay = _getTotalLapsDisplay();
    final distanceDisplay = _getDistanceDisplay();
    final topSpeedDisplay = _getTopSpeedDisplay();

    return Wrap(
      spacing: 16,
      runSpacing: 8,
      children: [
        _MetricChip(
          icon: Icons.timer_outlined,
          label: 'Duration',
          value: durationDisplay,
          theme: theme,
        ),
        _MetricChip(
          icon: Icons.emoji_events_outlined,
          label: 'Best Lap',
          value: bestLapDisplay,
          theme: theme,
        ),
        _MetricChip(
          icon: Icons.loop,
          label: 'Laps',
          value: totalLapsDisplay,
          theme: theme,
        ),
        _MetricChip(
          icon: Icons.straighten_outlined,
          label: 'Distance',
          value: distanceDisplay,
          theme: theme,
        ),
        _MetricChip(
          icon: Icons.speed_outlined,
          label: 'Top Speed',
          value: topSpeedDisplay,
          theme: theme,
        ),
      ],
    );
  }

  /// Duration formatted as mm:ss.
  String _getDurationDisplay() {
    if (analytics != null) {
      return formatDuration(analytics!.durationSeconds.round());
    }
    // Fallback: compute from session durationMs
    if (session.durationMs != null) {
      final seconds = session.durationMs! ~/ 1000;
      return formatDuration(seconds);
    }
    return '--:--';
  }

  /// Best lap time formatted as mm:ss.SSS.
  String _getBestLapDisplay() {
    if (analytics != null && analytics!.bestLapTimeMs != null) {
      return formatLapTime(analytics!.bestLapTimeMs!);
    }
    return '--:--.---';
  }

  /// Total laps count.
  String _getTotalLapsDisplay() {
    if (analytics != null) {
      return '${analytics!.totalLaps}';
    }
    return '--';
  }

  /// Distance in km with 1 decimal place.
  String _getDistanceDisplay() {
    if (analytics != null) {
      return '${analytics!.distanceKm.toStringAsFixed(1)} km';
    }
    return '-- km';
  }

  /// Top speed in km/h with 1 decimal place.
  String _getTopSpeedDisplay() {
    if (analytics != null) {
      return '${analytics!.maxSpeedKmh.toStringAsFixed(1)} km/h';
    }
    return '-- km/h';
  }
}

/// A compact metric chip showing icon, label, and value.
class _MetricChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final ThemeData theme;

  const _MetricChip({
    required this.icon,
    required this.label,
    required this.value,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(width: 4),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontSize: 10,
              ),
            ),
            Text(
              value,
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Error state widget.
class _ErrorState extends StatelessWidget {
  final Object error;

  const _ErrorState({required this.error});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: 48,
              color: theme.colorScheme.error,
            ),
            const SizedBox(height: 16),
            Text(
              'Unable to load sessions',
              style: theme.textTheme.titleMedium?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              error.toString(),
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
