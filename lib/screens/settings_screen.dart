import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../data/database_helper.dart';
import '../providers/session_provider.dart';
import '../providers/track_provider.dart';

final _packageInfoProvider = FutureProvider<PackageInfo>(
  (_) => PackageInfo.fromPlatform(),
);

/// Settings screen providing app preferences and data management options.
///
/// Includes a "Delete All Data" option that atomically removes all telemetry
/// data (sessions, GPS samples, tracks, laps, and analytics) after user
/// confirmation via a dialog. Also displays app version information.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final packageInfo = ref.watch(_packageInfoProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: ListView(
        children: [
          const _SectionHeader(title: 'Data Management'),
          ListTile(
            leading: const Icon(Icons.delete_forever, color: Colors.red),
            title: const Text('Delete All Data'),
            subtitle: const Text(
              'Permanently remove all sessions, tracks, and telemetry data',
            ),
            onTap: () => _showDeleteConfirmationDialog(context, ref),
          ),
          const Divider(),
          const _SectionHeader(title: 'About'),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('APXTracer'),
            subtitle: Text(
              packageInfo.whenOrNull(
                    data: (info) => 'Version ${info.version}',
                  ) ??
                  'Version —',
            ),
          ),
          const ListTile(
            leading: Icon(Icons.storage_outlined),
            title: Text('Storage'),
            subtitle: Text('All data stored locally with encryption'),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.exit_to_app),
            title: const Text('Exit App'),
            subtitle: const Text('Close the application'),
            onTap: () {
              if (Platform.isIOS) {
                exit(0);
              } else {
                SystemNavigator.pop();
              }
            },
          ),
        ],
      ),
    );
  }

  /// Shows a confirmation dialog before deleting all data.
  Future<void> _showDeleteConfirmationDialog(
      BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          icon: const Icon(Icons.warning_amber_rounded, color: Colors.red),
          title: const Text('Delete All Data?'),
          content: const Text(
            'This will permanently delete all your sessions, tracks, laps, '
            'and telemetry data. This action cannot be undone.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Colors.red,
              ),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );

    if (confirmed == true && context.mounted) {
      _deleteAllData(context, ref);
    }
  }

  /// Performs atomic deletion of all telemetry data and shows feedback.
  Future<void> _deleteAllData(BuildContext context, WidgetRef ref) async {
    try {
      await DatabaseHelper().deleteAllData();

      // Invalidate all data providers so the UI refreshes
      ref.invalidate(sessionsProvider);
      ref.invalidate(trackNotifierProvider);

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('All data has been deleted successfully.'),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to delete data: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}

/// A section header widget for grouping settings items.
class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: Theme.of(context).colorScheme.primary,
            ),
      ),
    );
  }
}
