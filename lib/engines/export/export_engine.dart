import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../data/gps_sample_repository.dart';
import '../../models/gps_sample.dart';
import '../../services/google_drive_service.dart';

/// Thrown when a session has no GPS samples and export is not allowed.
class EmptySessionException implements Exception {
  final String sessionId;
  final String message;

  const EmptySessionException(this.sessionId,
      [this.message = 'Cannot export session with 0 samples']);

  @override
  String toString() => 'EmptySessionException: $message (sessionId: $sessionId)';
}

/// Thrown when there is insufficient storage to write the export file.
class InsufficientStorageException implements Exception {
  final String message;

  const InsufficientStorageException(
      [this.message = 'Insufficient storage to generate export file']);

  @override
  String toString() => 'InsufficientStorageException: $message';
}

/// Thrown when a data read error occurs while fetching session samples.
class DataReadException implements Exception {
  final String message;
  final Object? cause;

  const DataReadException(
      [this.message = 'Failed to read session data', this.cause]);

  @override
  String toString() => 'DataReadException: $message';
}

/// Public interface for the Export Engine.
abstract class IExportEngine {
  /// Generates a CSV file for the given session.
  /// Returns the file path of the generated CSV.
  ///
  /// Throws [EmptySessionException] if the session has 0 samples.
  /// Throws [InsufficientStorageException] if storage is insufficient.
  /// Throws [DataReadException] if samples cannot be read from the database.
  Future<String> exportCsv(String sessionId);

  /// Generates a JSON file for the given session.
  /// Returns the file path of the generated JSON.
  ///
  /// Throws [EmptySessionException] if the session has 0 samples.
  /// Throws [InsufficientStorageException] if storage is insufficient.
  /// Throws [DataReadException] if samples cannot be read from the database.
  Future<String> exportJson(String sessionId);

  /// Uploads a file to the user's Google Drive.
  /// Throws [GoogleDriveAuthException] if authentication fails.
  /// Throws [GoogleDriveUploadException] if upload fails.
  Future<void> uploadToGoogleDrive(String filePath);

  /// Presents the platform share sheet for the given file.
  Future<void> shareFile(String filePath);
}

/// Implementation of [IExportEngine] that generates CSV and JSON export files
/// from locally stored GPS telemetry data and supports sharing via the
/// platform share sheet.
class ExportEngine implements IExportEngine {
  final GpsSampleRepository _gpsSampleRepository;
  final IGoogleDriveService _googleDriveService;

  ExportEngine(this._gpsSampleRepository, this._googleDriveService);

  /// Fetches samples for the given session, throwing appropriate exceptions
  /// for empty sessions or data read errors.
  Future<List<GpsSample>> _fetchSamples(String sessionId) async {
    List<GpsSample> samples;
    try {
      samples = await _gpsSampleRepository.getBySessionId(sessionId);
    } catch (e) {
      throw DataReadException(
        'Failed to read GPS samples for session $sessionId',
        e,
      );
    }

    if (samples.isEmpty) {
      throw EmptySessionException(sessionId);
    }

    return samples;
  }

  /// Writes content to a temporary file, handling storage errors.
  Future<String> _writeToTempFile(String fileName, String content) async {
    try {
      final tempDir = await getTemporaryDirectory();
      final file = File('${tempDir.path}/$fileName');
      await file.writeAsString(content);
      return file.path;
    } on FileSystemException catch (e) {
      if (e.osError != null &&
          (e.osError!.errorCode == 28 || // ENOSPC (Linux/macOS)
              e.osError!.errorCode == 112)) {
        // ERROR_DISK_FULL (Windows)
        throw InsufficientStorageException(
          'Insufficient storage to write export file: ${e.message}',
        );
      }
      throw InsufficientStorageException(
        'Failed to write export file: ${e.message}',
      );
    }
  }

  @override
  Future<String> exportCsv(String sessionId) async {
    final samples = await _fetchSamples(sessionId);

    final buffer = StringBuffer();
    buffer.writeln('timestamp,latitude,longitude,speed');

    for (final sample in samples) {
      final speed = sample.speed ?? 0.0;
      buffer.writeln(
          '${sample.timestamp},${sample.latitude},${sample.longitude},$speed');
    }

    final fileName = 'session_${sessionId}_export.csv';
    return _writeToTempFile(fileName, buffer.toString());
  }

  @override
  Future<String> exportJson(String sessionId) async {
    final samples = await _fetchSamples(sessionId);

    final samplesList = samples.map((sample) {
      return {
        'timestamp': sample.timestamp,
        'latitude': sample.latitude,
        'longitude': sample.longitude,
        'speed': sample.speed ?? 0.0,
      };
    }).toList();

    final jsonData = {'samples': samplesList};
    final jsonString = jsonEncode(jsonData);

    final fileName = 'session_${sessionId}_export.json';
    return _writeToTempFile(fileName, jsonString);
  }

  @override
  Future<void> uploadToGoogleDrive(String filePath) async {
    // Authenticate with Google Drive — let exceptions propagate
    // so the provider can show error UI with fallback option.
    await _googleDriveService.authenticate();

    // Upload the file to Google Drive
    final fileName = filePath.split('/').last;
    await _googleDriveService.uploadFile(filePath, fileName);
  }

  @override
  Future<void> shareFile(String filePath) async {
    final file = XFile(filePath);
    await Share.shareXFiles([file]);
  }
}
