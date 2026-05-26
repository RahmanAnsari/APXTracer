import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../engines/export/export_engine.dart';
import '../services/google_drive_service.dart';

/// Represents the possible states of an export operation.
enum ExportStatus {
  /// No export operation in progress.
  idle,

  /// An export operation is currently in progress.
  exporting,

  /// The export operation completed successfully.
  success,

  /// The export operation failed with an error.
  error,
}

/// Represents the format of the export file.
enum ExportFormat {
  csv,
  json,
}

/// Represents the destination for the export file.
enum ExportDestination {
  googleDrive,
  shareSheet,
}

/// Immutable state for the export provider.
class ExportState {
  final ExportStatus status;
  final String? filePath;
  final String? errorMessage;
  final bool showShareSheetFallback;

  const ExportState({
    this.status = ExportStatus.idle,
    this.filePath,
    this.errorMessage,
    this.showShareSheetFallback = false,
  });

  ExportState copyWith({
    ExportStatus? status,
    String? filePath,
    String? errorMessage,
    bool? showShareSheetFallback,
  }) {
    return ExportState(
      status: status ?? this.status,
      filePath: filePath ?? this.filePath,
      errorMessage: errorMessage ?? this.errorMessage,
      showShareSheetFallback:
          showShareSheetFallback ?? this.showShareSheetFallback,
    );
  }
}

/// Manages export operations including CSV/JSON generation,
/// Google Drive upload, and platform share sheet sharing.
///
/// Validates: Requirements 9.1, 9.2, 9.5, 9.6, 9.7
class ExportNotifier extends StateNotifier<ExportState> {
  final IExportEngine _exportEngine;

  ExportNotifier(this._exportEngine) : super(const ExportState());

  /// Exports a session as CSV and delivers it to the specified destination.
  ///
  /// Generates the CSV file first, then routes to Google Drive or share sheet.
  /// On Google Drive auth/upload failure, shows error and offers share sheet fallback.
  ///
  /// Validates: Requirements 9.1, 9.5, 9.6, 9.7
  Future<void> exportCsv(String sessionId, ExportDestination destination) async {
    await _export(sessionId, ExportFormat.csv, destination);
  }

  /// Exports a session as JSON and delivers it to the specified destination.
  ///
  /// Generates the JSON file first, then routes to Google Drive or share sheet.
  /// On Google Drive auth/upload failure, shows error and offers share sheet fallback.
  ///
  /// Validates: Requirements 9.2, 9.5, 9.6, 9.7
  Future<void> exportJson(
      String sessionId, ExportDestination destination) async {
    await _export(sessionId, ExportFormat.json, destination);
  }

  /// Shares the last exported file via the platform share sheet.
  ///
  /// Used as a fallback when Google Drive upload fails.
  /// Validates: Requirement 9.7
  Future<void> shareViaShareSheet() async {
    final filePath = state.filePath;
    if (filePath == null) return;

    state = state.copyWith(
      status: ExportStatus.exporting,
      showShareSheetFallback: false,
    );

    try {
      await _exportEngine.shareFile(filePath);
      state = state.copyWith(status: ExportStatus.success);
    } catch (e) {
      state = ExportState(
        status: ExportStatus.error,
        filePath: filePath,
        errorMessage: 'Failed to share file: $e',
        showShareSheetFallback: false,
      );
    }
  }

  /// Resets the export state back to idle.
  void reset() {
    state = const ExportState();
  }

  /// Internal method that handles the full export flow:
  /// 1. Generate the file (CSV or JSON)
  /// 2. Deliver to destination (Google Drive or share sheet)
  Future<void> _export(
    String sessionId,
    ExportFormat format,
    ExportDestination destination,
  ) async {
    state = ExportState(status: ExportStatus.exporting);

    // Step 1: Generate the export file
    String filePath;
    try {
      filePath = switch (format) {
        ExportFormat.csv => await _exportEngine.exportCsv(sessionId),
        ExportFormat.json => await _exportEngine.exportJson(sessionId),
      };
    } on EmptySessionException catch (e) {
      state = ExportState(
        status: ExportStatus.error,
        errorMessage: e.message,
      );
      return;
    } on InsufficientStorageException catch (e) {
      state = ExportState(
        status: ExportStatus.error,
        errorMessage: e.message,
      );
      return;
    } on DataReadException catch (e) {
      state = ExportState(
        status: ExportStatus.error,
        errorMessage: e.message,
      );
      return;
    } catch (e) {
      state = ExportState(
        status: ExportStatus.error,
        errorMessage: 'Failed to generate export file: $e',
      );
      return;
    }

    // Step 2: Deliver to destination
    switch (destination) {
      case ExportDestination.shareSheet:
        await _deliverViaShareSheet(filePath);
      case ExportDestination.googleDrive:
        await _deliverToGoogleDrive(filePath);
    }
  }

  /// Delivers the file via the platform share sheet.
  Future<void> _deliverViaShareSheet(String filePath) async {
    try {
      await _exportEngine.shareFile(filePath);
      state = ExportState(
        status: ExportStatus.success,
        filePath: filePath,
      );
    } catch (e) {
      state = ExportState(
        status: ExportStatus.error,
        filePath: filePath,
        errorMessage: 'Failed to share file: $e',
      );
    }
  }

  /// Delivers the file to Google Drive. On auth or upload failure,
  /// shows an error and offers the share sheet as a fallback.
  ///
  /// Validates: Requirements 9.6, 9.7
  Future<void> _deliverToGoogleDrive(String filePath) async {
    try {
      await _exportEngine.uploadToGoogleDrive(filePath);
      state = ExportState(
        status: ExportStatus.success,
        filePath: filePath,
      );
    } on GoogleDriveAuthException catch (e) {
      state = ExportState(
        status: ExportStatus.error,
        filePath: filePath,
        errorMessage: 'Google Drive authentication failed: ${e.message}',
        showShareSheetFallback: true,
      );
    } on GoogleDriveUploadException catch (e) {
      state = ExportState(
        status: ExportStatus.error,
        filePath: filePath,
        errorMessage: 'Google Drive upload failed: ${e.message}',
        showShareSheetFallback: true,
      );
    } catch (e) {
      state = ExportState(
        status: ExportStatus.error,
        filePath: filePath,
        errorMessage: 'Google Drive export failed: $e',
        showShareSheetFallback: true,
      );
    }
  }
}

/// Provider for the export engine instance.
/// Override this in tests or at app startup with the actual implementation.
final exportEngineProvider = Provider<IExportEngine>((ref) {
  throw UnimplementedError(
    'exportEngineProvider must be overridden with an actual IExportEngine implementation',
  );
});

/// Provider for the export state notifier.
final exportProvider =
    StateNotifierProvider<ExportNotifier, ExportState>((ref) {
  final exportEngine = ref.watch(exportEngineProvider);
  return ExportNotifier(exportEngine);
});
