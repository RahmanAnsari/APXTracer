import 'dart:io';

import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:http/http.dart' as http;

/// Thrown when Google Drive authentication fails.
class GoogleDriveAuthException implements Exception {
  final String message;
  final Object? cause;

  const GoogleDriveAuthException(
      [this.message = 'Google Drive authentication failed', this.cause]);

  @override
  String toString() => 'GoogleDriveAuthException: $message';
}

/// Thrown when Google Drive file upload fails.
class GoogleDriveUploadException implements Exception {
  final String message;
  final Object? cause;

  const GoogleDriveUploadException(
      [this.message = 'Google Drive upload failed', this.cause]);

  @override
  String toString() => 'GoogleDriveUploadException: $message';
}

/// Public interface for the Google Drive Service.
abstract class IGoogleDriveService {
  /// Authenticates with Google and requests Drive file scope.
  /// Throws [GoogleDriveAuthException] if user denies or auth fails.
  Future<void> authenticate();

  /// Uploads a file to the authenticated user's Google Drive.
  /// Returns the file ID of the uploaded file.
  /// Throws [GoogleDriveUploadException] on failure.
  Future<String> uploadFile(String filePath, String fileName);

  /// Whether the user is currently authenticated with Google.
  bool get isAuthenticated;
}

/// Google authenticated HTTP client that wraps an auth client from GoogleSignIn.
class _GoogleAuthClient extends http.BaseClient {
  final Map<String, String> _headers;
  final http.Client _baseClient = http.Client();

  _GoogleAuthClient(this._headers);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    request.headers.addAll(_headers);
    return _baseClient.send(request);
  }
}

/// Implementation of [IGoogleDriveService] using google_sign_in and googleapis.
class GoogleDriveService implements IGoogleDriveService {
  final GoogleSignIn _googleSignIn;
  GoogleSignInAccount? _currentUser;

  GoogleDriveService({GoogleSignIn? googleSignIn})
      : _googleSignIn = googleSignIn ??
            GoogleSignIn(
              scopes: [drive.DriveApi.driveFileScope],
            );

  @override
  bool get isAuthenticated => _currentUser != null;

  @override
  Future<void> authenticate() async {
    try {
      // Try silent sign-in first (if user previously authenticated)
      _currentUser = await _googleSignIn.signInSilently();

      // If silent sign-in fails, prompt interactive sign-in
      _currentUser ??= await _googleSignIn.signIn();

      if (_currentUser == null) {
        throw const GoogleDriveAuthException(
          'User cancelled Google Sign-In',
        );
      }
    } catch (e) {
      if (e is GoogleDriveAuthException) rethrow;
      throw GoogleDriveAuthException(
        'Google Drive authentication failed: $e',
        e,
      );
    }
  }

  @override
  Future<String> uploadFile(String filePath, String fileName) async {
    if (!isAuthenticated) {
      throw const GoogleDriveAuthException(
        'Not authenticated. Call authenticate() first.',
      );
    }

    try {
      final authHeaders = await _currentUser!.authHeaders;
      final httpClient = _GoogleAuthClient(authHeaders);

      final driveApi = drive.DriveApi(httpClient);

      final file = File(filePath);
      final fileStream = file.openRead();
      final fileLength = await file.length();

      final driveFile = drive.File()..name = fileName;

      final response = await driveApi.files.create(
        driveFile,
        uploadMedia: drive.Media(fileStream, fileLength),
      );

      if (response.id == null) {
        throw const GoogleDriveUploadException(
          'Upload succeeded but no file ID was returned',
        );
      }

      return response.id!;
    } catch (e) {
      if (e is GoogleDriveUploadException) rethrow;
      if (e is GoogleDriveAuthException) rethrow;
      throw GoogleDriveUploadException(
        'Failed to upload file to Google Drive: $e',
        e,
      );
    }
  }
}
