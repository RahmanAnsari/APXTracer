import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../models/track.dart';
import '../providers/track_provider.dart';

/// Screen displaying all auto-generated tracks ordered by last driven date descending.
///
/// Validates: Requirements 7.1, 7.2, 7.3, 7.4, 7.5
class TrackLibraryScreen extends ConsumerWidget {
  const TrackLibraryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tracksAsync = ref.watch(trackNotifierProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Track Library'),
      ),
      body: tracksAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Text(
              'Failed to load tracks: $error',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
              textAlign: TextAlign.center,
            ),
          ),
        ),
        data: (tracks) {
          if (tracks.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(16.0),
                child: Text(
                  'No tracks discovered yet.\nComplete a session on a closed circuit to auto-generate a track.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(8.0),
            itemCount: tracks.length,
            itemBuilder: (context, index) {
              return _TrackCard(track: tracks[index]);
            },
          );
        },
      ),
    );
  }
}

/// A card displaying a single track with inline name editing.
class _TrackCard extends ConsumerStatefulWidget {
  final Track track;

  const _TrackCard({required this.track});

  @override
  ConsumerState<_TrackCard> createState() => _TrackCardState();
}

class _TrackCardState extends ConsumerState<_TrackCard> {
  bool _isEditing = false;
  late TextEditingController _nameController;
  String? _validationError;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(
      text: widget.track.name ?? '',
    );
  }

  @override
  void didUpdateWidget(covariant _TrackCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.track.id != widget.track.id ||
        oldWidget.track.name != widget.track.name) {
      _nameController.text = widget.track.name ?? '';
      _isEditing = false;
      _validationError = null;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _startEditing() {
    setState(() {
      _isEditing = true;
      _validationError = null;
    });
  }

  void _cancelEditing() {
    setState(() {
      _isEditing = false;
      _validationError = null;
      _nameController.text = widget.track.name ?? '';
    });
  }

  Future<void> _submitName() async {
    final newName = _nameController.text.trim();

    // Client-side validation for immediate feedback.
    final error = validateTrackName(newName);
    if (error != null) {
      setState(() {
        _validationError = error;
      });
      return;
    }

    final notifier = ref.read(trackNotifierProvider.notifier);
    final result = await notifier.renameTrack(widget.track.id, newName);

    if (result.success) {
      setState(() {
        _isEditing = false;
        _validationError = null;
      });
    } else {
      setState(() {
        _validationError = result.error;
      });
    }
  }

  void _onNameChanged(String value) {
    // Live validation as user types.
    final error = validateTrackName(value.trim());
    if (_validationError != null || error != null) {
      setState(() {
        _validationError = error;
      });
    }
  }

  String _formatLastDriven(int epochMs) {
    final date = DateTime.fromMillisecondsSinceEpoch(epochMs);
    return DateFormat.yMMMd().format(date);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final trackName = widget.track.name ?? 'Unnamed Track';

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4.0),
      child: InkWell(
        onTap: _isEditing ? null : () => context.push('/track/${widget.track.id}'),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Track name row (display or edit mode).
              if (_isEditing) ...[
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _nameController,
                        autofocus: true,
                        maxLength: 50,
                        decoration: InputDecoration(
                          labelText: 'Track name',
                          errorText: _validationError,
                          counterText: '',
                          border: const OutlineInputBorder(),
                          isDense: true,
                        ),
                        onChanged: _onNameChanged,
                        onSubmitted: (_) => _submitName(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: const Icon(Icons.check),
                      tooltip: 'Save',
                      onPressed: _submitName,
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      tooltip: 'Cancel',
                      onPressed: _cancelEditing,
                    ),
                  ],
                ),
              ] else ...[
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        trackName,
                        style: theme.textTheme.titleMedium,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      icon: Icon(
                        Icons.edit,
                        size: 16,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      tooltip: 'Rename track',
                      onPressed: _startEditing,
                    ),
                    Icon(
                      Icons.chevron_right,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 8),
              // Track metadata row.
              Row(
                children: [
                  Icon(
                    Icons.timer_outlined,
                    size: 16,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '${widget.track.sessionCount} ${widget.track.sessionCount == 1 ? 'session' : 'sessions'}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Icon(
                    Icons.calendar_today_outlined,
                    size: 16,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'Last driven: ${_formatLastDriven(widget.track.lastDriven)}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
