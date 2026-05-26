import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../providers/session_provider.dart';
import '../models/session.dart';
import '../models/session_analytics.dart';
import '../utils/time_formatter.dart';

/// Home screen with dashboard layout, quick-start recording button,
/// recent session summary, and navigation to Session History and Track Library.
///
/// Validates: Requirement 1.1 - Start Session button available on home screen.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessionsAsync = ref.watch(sessionsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('APXTracer'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => context.push('/settings'),
            tooltip: 'Settings',
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 32),
              // Quick-start recording button (large, prominent)
              _StartRecordingButton(
                onPressed: () => context.push('/recording'),
              ),
              const SizedBox(height: 32),
              // Recent session summary
              sessionsAsync.when(
                data: (sessions) => _RecentSessionSection(
                  sessions: sessions,
                  ref: ref,
                ),
                loading: () => const _RecentSessionLoading(),
                error: (error, stack) => const _RecentSessionError(),
              ),
              const Spacer(),
              // Navigation buttons
              _NavigationSection(
                onSessionHistoryTap: () => context.push('/sessions'),
                onTrackLibraryTap: () => context.push('/tracks'),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}

/// Large, prominent button to start a new recording session.
class _StartRecordingButton extends StatelessWidget {
  final VoidCallback onPressed;

  const _StartRecordingButton({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return FilledButton.icon(
      onPressed: onPressed,
      icon: const Icon(Icons.fiber_manual_record, size: 28),
      label: const Text(
        'Start Recording',
        style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
      ),
      style: FilledButton.styleFrom(
        minimumSize: const Size(double.infinity, 72),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        backgroundColor: theme.colorScheme.primary,
        foregroundColor: theme.colorScheme.onPrimary,
      ),
    );
  }
}

/// Displays the most recent session's key metrics.
class _RecentSessionSection extends StatelessWidget {
  final List<Session> sessions;
  final WidgetRef ref;

  const _RecentSessionSection({
    required this.sessions,
    required this.ref,
  });

  @override
  Widget build(BuildContext context) {
    if (sessions.isEmpty) {
      return const _EmptySessionCard();
    }

    final lastSession = sessions.first;
    final detailAsync = ref.watch(sessionDetailProvider(lastSession.id));

    return detailAsync.when(
      data: (detail) {
        if (detail == null) return const _EmptySessionCard();
        return _LastSessionCard(
          session: detail.session,
          analytics: detail.analytics,
        );
      },
      loading: () => const _RecentSessionLoading(),
      error: (error, stack) => const _RecentSessionError(),
    );
  }
}

/// Card showing the last session's key metrics.
class _LastSessionCard extends StatelessWidget {
  final Session session;
  final SessionAnalytics? analytics;

  const _LastSessionCard({
    required this.session,
    this.analytics,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.history,
                  size: 20,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  'Last Session',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              _formatSessionDate(session.startTime),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            if (analytics != null) ...[
              Row(
                children: [
                  Expanded(
                    child: _MetricTile(
                      label: 'Duration',
                      value: formatDuration(
                        analytics!.durationSeconds.round(),
                      ),
                      icon: Icons.timer_outlined,
                    ),
                  ),
                  Expanded(
                    child: _MetricTile(
                      label: 'Laps',
                      value: '${analytics!.totalLaps}',
                      icon: Icons.loop,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _MetricTile(
                      label: 'Best Lap',
                      value: analytics!.bestLapTimeMs != null
                          ? formatLapTime(analytics!.bestLapTimeMs!)
                          : '--:--',
                      icon: Icons.emoji_events_outlined,
                    ),
                  ),
                  Expanded(
                    child: _MetricTile(
                      label: 'Distance',
                      value:
                          '${analytics!.distanceKm.toStringAsFixed(2)} km',
                      icon: Icons.straighten_outlined,
                    ),
                  ),
                ],
              ),
            ] else ...[
              Text(
                'No analytics available',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _formatSessionDate(int epochMs) {
    final date = DateTime.fromMillisecondsSinceEpoch(epochMs);
    final now = DateTime.now();
    final diff = now.difference(date);

    if (diff.inDays == 0) {
      return 'Today at ${_timeOfDay(date)}';
    } else if (diff.inDays == 1) {
      return 'Yesterday at ${_timeOfDay(date)}';
    } else {
      return '${date.day}/${date.month}/${date.year} at ${_timeOfDay(date)}';
    }
  }

  String _timeOfDay(DateTime date) {
    return '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }
}

/// A single metric tile showing an icon, label, and value.
class _MetricTile extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;

  const _MetricTile({
    required this.label,
    required this.value,
    required this.icon,
  });

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

/// Empty state card when no sessions have been recorded yet.
class _EmptySessionCard extends StatelessWidget {
  const _EmptySessionCard();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          children: [
            Icon(
              Icons.speed_outlined,
              size: 48,
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 12),
            Text(
              'No sessions yet',
              style: theme.textTheme.titleSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Start your first recording to see metrics here',
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

/// Loading state for the recent session section.
class _RecentSessionLoading extends StatelessWidget {
  const _RecentSessionLoading();

  @override
  Widget build(BuildContext context) {
    return const Card(
      elevation: 0,
      child: Padding(
        padding: EdgeInsets.all(20.0),
        child: Center(
          child: CircularProgressIndicator(),
        ),
      ),
    );
  }
}

/// Error state for the recent session section.
class _RecentSessionError extends StatelessWidget {
  const _RecentSessionError();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: theme.colorScheme.errorContainer),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Text(
          'Unable to load recent session',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.error,
          ),
        ),
      ),
    );
  }
}

/// Navigation section with buttons to Session History and Track Library.
class _NavigationSection extends StatelessWidget {
  final VoidCallback onSessionHistoryTap;
  final VoidCallback onTrackLibraryTap;

  const _NavigationSection({
    required this.onSessionHistoryTap,
    required this.onTrackLibraryTap,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _NavCard(
            icon: Icons.list_alt_outlined,
            label: 'Session History',
            onTap: onSessionHistoryTap,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: _NavCard(
            icon: Icons.map_outlined,
            label: 'Track Library',
            onTap: onTrackLibraryTap,
          ),
        ),
      ],
    );
  }
}

/// A navigation card with an icon and label.
class _NavCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _NavCard({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
          child: Column(
            children: [
              Icon(icon, size: 32, color: theme.colorScheme.primary),
              const SizedBox(height: 8),
              Text(
                label,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: theme.colorScheme.onSurface,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
