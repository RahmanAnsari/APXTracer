import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../engines/recording/recording_messages.dart';
import '../models/track.dart';
import '../providers/recording_provider.dart';
import '../providers/session_provider.dart';
import '../providers/track_provider.dart';

/// Recording screen with live telemetry display.
///
/// Displays current speed (km/h), elapsed time, GPS status indicator,
/// and sample count. Provides Start/Stop session controls with error handling
/// for permission denied and GPS fix timeout scenarios.
///
/// Updates at minimum 1 Hz from the recording provider stream.
///
/// Requirements: 1.1, 1.7, 1.8, 1.9, 1.10
class RecordingScreen extends ConsumerStatefulWidget {
  const RecordingScreen({super.key});

  @override
  ConsumerState<RecordingScreen> createState() => _RecordingScreenState();
}

class _RecordingScreenState extends ConsumerState<RecordingScreen> {
  /// Track the previous error to detect new errors for SnackBar display.
  String? _lastShownError;

  @override
  Widget build(BuildContext context) {
    final recordingState = ref.watch(recordingProvider);

    // Listen for error state changes and show SnackBars.
    ref.listen<RecordingState>(recordingProvider, (previous, next) {
      if (next.error != null && next.error != _lastShownError) {
        _lastShownError = next.error;
        _showErrorSnackBar(context, next.error!);
      }
      // Clear tracked error when state clears it.
      if (next.error == null) {
        _lastShownError = null;
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('Recording'),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            children: [
              const Spacer(),

              // Live telemetry display
              _TelemetryDisplay(
                update: recordingState.latestUpdate,
                isRecording:
                    recordingState.status == RecordingStatus.recording,
              ),

              const Spacer(),

              // GPS status indicator
              _GpsStatusIndicator(
                status: recordingState.latestUpdate?.gpsStatus,
                isRecording:
                    recordingState.status == RecordingStatus.recording,
              ),

              const SizedBox(height: 32),

              // Track selector (visible only when idle)
              if (recordingState.status == RecordingStatus.idle) ...[
                _TrackSelector(
                  preSelectedTrackId: recordingState.preSelectedTrackId,
                  onChanged: (id) =>
                      ref.read(recordingProvider.notifier).setPreSelectedTrack(id),
                ),
                const SizedBox(height: 16),
              ],

              // Start/Stop button
              _RecordingButton(
                status: recordingState.status,
                onStart: () => _handleStart(context, ref),
                onStop: () => _handleStop(context, ref),
              ),

              const SizedBox(height: 24),

              // Processing indicator
              if (recordingState.status == RecordingStatus.processing)
                const _ProcessingIndicator(),
            ],
          ),
        ),
      ),
    );
  }

  /// Shows an error SnackBar with appropriate messaging for GPS errors.
  void _showErrorSnackBar(BuildContext context, String error) {
    final String message;
    final IconData icon;

    if (error.contains('permission') || error.contains('Permission')) {
      message = 'Location permission is required to start a session.';
      icon = Icons.location_disabled;
    } else if (error.contains('fix') ||
        error.contains('timeout') ||
        error.contains('Timeout')) {
      message = 'GPS signal is unavailable. Please try again in an open area.';
      icon = Icons.gps_off;
    } else {
      message = error;
      icon = Icons.error_outline;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(icon, color: Colors.white, size: 20),
            const SizedBox(width: 12),
            Expanded(child: Text(message)),
          ],
        ),
        behavior: SnackBarBehavior.floating,
        backgroundColor: Theme.of(context).colorScheme.error,
        duration: const Duration(seconds: 4),
        action: SnackBarAction(
          label: 'Dismiss',
          textColor: Colors.white,
          onPressed: () {
            ScaffoldMessenger.of(context).hideCurrentSnackBar();
          },
        ),
      ),
    );
  }

  Future<void> _handleStart(BuildContext context, WidgetRef ref) async {
    await ref.read(recordingProvider.notifier).startSession();
  }

  Future<void> _handleStop(BuildContext context, WidgetRef ref) async {
    final session =
        await ref.read(recordingProvider.notifier).stopSession();

    if (session != null && context.mounted) {
      // Invalidate sessions so home page and history refresh with new data
      ref.invalidate(sessionsProvider);
      context.push('/session/${session.id}/summary');
    }
  }
}

/// Displays live telemetry: speed, elapsed time, and sample count.
class _TelemetryDisplay extends StatelessWidget {
  final RecordingUpdate? update;
  final bool isRecording;

  const _TelemetryDisplay({
    required this.update,
    required this.isRecording,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Current speed
        Text(
          _formatSpeed(update?.currentSpeedKmh),
          style: theme.textTheme.displayLarge?.copyWith(
            fontWeight: FontWeight.bold,
            color: isRecording
                ? theme.colorScheme.primary
                : theme.colorScheme.onSurfaceVariant,
          ),
        ),
        Text(
          'km/h',
          style: theme.textTheme.titleMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),

        const SizedBox(height: 32),

        // Elapsed time and sample count row
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _MetricTile(
              label: 'Elapsed',
              value: _formatElapsed(update?.elapsed),
              icon: Icons.timer_outlined,
            ),
            _MetricTile(
              label: 'Samples',
              value: _formatSampleCount(update?.sampleCount),
              icon: Icons.data_usage_outlined,
            ),
          ],
        ),
      ],
    );
  }

  String _formatSpeed(double? speed) {
    if (speed == null || !isRecording) return '0.0';
    return speed.toStringAsFixed(1);
  }

  String _formatElapsed(Duration? elapsed) {
    if (elapsed == null || !isRecording) return '00:00';
    final minutes = elapsed.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = elapsed.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  String _formatSampleCount(int? count) {
    if (count == null || !isRecording) return '0';
    return count.toString();
  }
}

/// A single metric tile showing an icon, value, and label.
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

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          icon,
          size: 24,
          color: theme.colorScheme.onSurfaceVariant,
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

/// GPS status indicator showing current signal state.
class _GpsStatusIndicator extends StatelessWidget {
  final GpsStatus? status;
  final bool isRecording;

  const _GpsStatusIndicator({
    required this.status,
    required this.isRecording,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final effectiveStatus = isRecording ? (status ?? GpsStatus.acquiring) : null;

    final (Color color, String label, IconData icon) = switch (effectiveStatus) {
      GpsStatus.active => (
          Colors.green,
          'GPS Active',
          Icons.gps_fixed,
        ),
      GpsStatus.acquiring => (
          Colors.orange,
          'Acquiring GPS...',
          Icons.gps_not_fixed,
        ),
      GpsStatus.signalLost => (
          Colors.red,
          'Signal Lost',
          Icons.gps_off,
        ),
      GpsStatus.noPermission => (
          Colors.red,
          'No Permission',
          Icons.location_disabled,
        ),
      null => (
          theme.colorScheme.onSurfaceVariant,
          'GPS Idle',
          Icons.gps_not_fixed,
        ),
    };

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 8),
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 4),
        Text(
          label,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: color,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

/// Start/Stop recording button.
///
/// Disables Start while recording to prevent duplicates (Req 1.9).
class _RecordingButton extends StatelessWidget {
  final RecordingStatus status;
  final VoidCallback onStart;
  final VoidCallback onStop;

  const _RecordingButton({
    required this.status,
    required this.onStart,
    required this.onStop,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    switch (status) {
      case RecordingStatus.idle:
        return FilledButton.icon(
          onPressed: onStart,
          icon: const Icon(Icons.play_arrow, size: 28),
          label: const Text('Start Session'),
          style: FilledButton.styleFrom(
            minimumSize: const Size(double.infinity, 56),
            textStyle: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        );
      case RecordingStatus.recording:
        return FilledButton.icon(
          onPressed: onStop,
          icon: const Icon(Icons.stop, size: 28),
          label: const Text('Stop Session'),
          style: FilledButton.styleFrom(
            minimumSize: const Size(double.infinity, 56),
            backgroundColor: theme.colorScheme.error,
            foregroundColor: theme.colorScheme.onError,
            textStyle: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        );
      case RecordingStatus.processing:
        // Disable both buttons while processing
        return FilledButton.icon(
          onPressed: null,
          icon: const Icon(Icons.hourglass_top, size: 28),
          label: const Text('Processing...'),
          style: FilledButton.styleFrom(
            minimumSize: const Size(double.infinity, 56),
            textStyle: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        );
    }
  }
}

/// Processing indicator shown while post-session pipeline runs.
class _ProcessingIndicator extends StatelessWidget {
  const _ProcessingIndicator();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const LinearProgressIndicator(),
        const SizedBox(height: 8),
        Text(
          'Analyzing session...',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

/// Lets the user pin a specific track before starting a session, or keep
/// "Auto-detect" (the default).  Tapping opens a bottom-sheet list of all
/// saved tracks.
class _TrackSelector extends ConsumerWidget {
  const _TrackSelector({
    required this.preSelectedTrackId,
    required this.onChanged,
  });

  final String? preSelectedTrackId;
  final void Function(String? trackId) onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final tracksAsync = ref.watch(trackNotifierProvider);
    final tracks = tracksAsync.valueOrNull ?? [];

    final Track? selected = preSelectedTrackId == null
        ? null
        : tracks.where((t) => t.id == preSelectedTrackId).firstOrNull;

    final bool isAutoDetect = preSelectedTrackId == null;
    final String label = isAutoDetect
        ? 'Auto-detect'
        : (selected?.name ?? 'Unknown Track');

    return InkWell(
      onTap: () => _openPicker(context, tracks),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          border: Border.all(color: theme.colorScheme.outlineVariant),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(
              isAutoDetect ? Icons.gps_fixed : Icons.flag_outlined,
              size: 20,
              color: isAutoDetect
                  ? theme.colorScheme.onSurfaceVariant
                  : theme.colorScheme.primary,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Track',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  Text(
                    label,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w500,
                      color: isAutoDetect
                          ? theme.colorScheme.onSurfaceVariant
                          : theme.colorScheme.onSurface,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            Icon(
              Icons.expand_more,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }

  void _openPicker(BuildContext context, List<Track> tracks) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Text(
                  'Select Track',
                  style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ),
              const Divider(height: 1),
              // Auto-detect option
              ListTile(
                leading: const Icon(Icons.gps_fixed),
                title: const Text('Auto-detect'),
                subtitle: const Text('Detect and create track automatically'),
                selected: preSelectedTrackId == null,
                selectedColor: Theme.of(ctx).colorScheme.primary,
                onTap: () {
                  onChanged(null);
                  Navigator.pop(ctx);
                },
              ),
              if (tracks.isNotEmpty) ...[
                const Divider(height: 1),
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.of(ctx).size.height * 0.4,
                  ),
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: tracks.length,
                    itemBuilder: (_, i) {
                      final track = tracks[i];
                      return ListTile(
                        leading: const Icon(Icons.flag_outlined),
                        title: Text(track.name ?? 'Unnamed Track'),
                        subtitle: Text(
                          '${track.sessionCount} ${track.sessionCount == 1 ? 'session' : 'sessions'}',
                        ),
                        selected: track.id == preSelectedTrackId,
                        selectedColor: Theme.of(ctx).colorScheme.primary,
                        onTap: () {
                          onChanged(track.id);
                          Navigator.pop(ctx);
                        },
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
