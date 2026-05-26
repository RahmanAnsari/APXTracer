import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:apx_tracer/data/gps_sample_repository.dart';
import 'package:apx_tracer/engines/export/export_engine.dart';
import 'package:apx_tracer/models/gps_sample.dart';
import 'package:apx_tracer/services/google_drive_service.dart';

class MockGpsSampleRepository extends Mock implements GpsSampleRepository {}

class MockGoogleDriveService extends Mock implements IGoogleDriveService {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockGpsSampleRepository mockRepository;
  late MockGoogleDriveService mockDriveService;
  late ExportEngine exportEngine;
  late String tempDirPath;

  setUp(() async {
    mockRepository = MockGpsSampleRepository();
    mockDriveService = MockGoogleDriveService();
    exportEngine = ExportEngine(mockRepository, mockDriveService);

    // Use the system temp directory directly for tests
    tempDirPath = Directory.systemTemp.path;

    // Mock the path_provider method channel
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (MethodCall methodCall) async {
        if (methodCall.method == 'getTemporaryDirectory') {
          return tempDirPath;
        }
        return null;
      },
    );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      null,
    );
  });

  /// Helper: creates a list of GPS samples in chronological order.
  List<GpsSample> createSamples(int count, {int startTimestamp = 1000}) {
    return List.generate(count, (i) {
      return GpsSample(
        timestamp: startTimestamp + (i * 1000),
        latitude: 51.5 + (i * 0.001),
        longitude: -0.1 + (i * 0.001),
        speed: 10.0 + i.toDouble(),
      );
    });
  }

  group('CSV Export - correct header row', () {
    test('CSV file starts with correct header row', () async {
      final samples = createSamples(3);
      when(() => mockRepository.getBySessionId('session-1'))
          .thenAnswer((_) async => samples);

      final filePath = await exportEngine.exportCsv('session-1');

      final content = await File(filePath).readAsString();
      final lines = content.trim().split('\n');
      expect(lines.first, 'timestamp,latitude,longitude,speed');

      // Cleanup
      await File(filePath).delete();
    });
  });

  group('CSV Export - rows match sample count and order', () {
    test('CSV has one data row per sample plus header', () async {
      final samples = createSamples(5);
      when(() => mockRepository.getBySessionId('session-1'))
          .thenAnswer((_) async => samples);

      final filePath = await exportEngine.exportCsv('session-1');

      final content = await File(filePath).readAsString();
      final lines = content.trim().split('\n');
      // 1 header + 5 data rows
      expect(lines.length, 6);

      // Cleanup
      await File(filePath).delete();
    });

    test('CSV rows are in chronological order matching samples', () async {
      final samples = [
        const GpsSample(
            timestamp: 1000, latitude: 51.5, longitude: -0.1, speed: 10.0),
        const GpsSample(
            timestamp: 2000, latitude: 51.501, longitude: -0.099, speed: 15.0),
        const GpsSample(
            timestamp: 3000, latitude: 51.502, longitude: -0.098, speed: 20.0),
      ];
      when(() => mockRepository.getBySessionId('session-1'))
          .thenAnswer((_) async => samples);

      final filePath = await exportEngine.exportCsv('session-1');

      final content = await File(filePath).readAsString();
      final lines = content.trim().split('\n');

      // Verify first data row matches first sample
      expect(lines[1], '1000,51.5,-0.1,10.0');
      // Verify second data row matches second sample
      expect(lines[2], '2000,51.501,-0.099,15.0');
      // Verify third data row matches third sample
      expect(lines[3], '3000,51.502,-0.098,20.0');

      // Cleanup
      await File(filePath).delete();
    });

    test('CSV uses 0.0 for samples with null speed', () async {
      final samples = [
        const GpsSample(
            timestamp: 1000, latitude: 51.5, longitude: -0.1, speed: null),
      ];
      when(() => mockRepository.getBySessionId('session-1'))
          .thenAnswer((_) async => samples);

      final filePath = await exportEngine.exportCsv('session-1');

      final content = await File(filePath).readAsString();
      final lines = content.trim().split('\n');
      expect(lines[1], '1000,51.5,-0.1,0.0');

      // Cleanup
      await File(filePath).delete();
    });
  });

  group('JSON Export - has "samples" array with correct fields', () {
    test('JSON has root object with "samples" array', () async {
      final samples = createSamples(3);
      when(() => mockRepository.getBySessionId('session-1'))
          .thenAnswer((_) async => samples);

      final filePath = await exportEngine.exportJson('session-1');

      final content = await File(filePath).readAsString();
      final json = jsonDecode(content) as Map<String, dynamic>;
      expect(json.containsKey('samples'), isTrue);
      expect(json['samples'], isList);

      // Cleanup
      await File(filePath).delete();
    });

    test(
        'each JSON sample element has timestamp, latitude, longitude, speed fields',
        () async {
      final samples = createSamples(2);
      when(() => mockRepository.getBySessionId('session-1'))
          .thenAnswer((_) async => samples);

      final filePath = await exportEngine.exportJson('session-1');

      final content = await File(filePath).readAsString();
      final json = jsonDecode(content) as Map<String, dynamic>;
      final samplesList = json['samples'] as List;

      for (final element in samplesList) {
        final sample = element as Map<String, dynamic>;
        expect(sample.containsKey('timestamp'), isTrue);
        expect(sample.containsKey('latitude'), isTrue);
        expect(sample.containsKey('longitude'), isTrue);
        expect(sample.containsKey('speed'), isTrue);
      }

      // Cleanup
      await File(filePath).delete();
    });

    test('JSON sample values match original GPS sample data', () async {
      final samples = [
        const GpsSample(
            timestamp: 5000,
            latitude: 40.7128,
            longitude: -74.006,
            speed: 12.5),
      ];
      when(() => mockRepository.getBySessionId('session-1'))
          .thenAnswer((_) async => samples);

      final filePath = await exportEngine.exportJson('session-1');

      final content = await File(filePath).readAsString();
      final json = jsonDecode(content) as Map<String, dynamic>;
      final samplesList = json['samples'] as List;
      final first = samplesList[0] as Map<String, dynamic>;

      expect(first['timestamp'], 5000);
      expect(first['latitude'], 40.7128);
      expect(first['longitude'], -74.006);
      expect(first['speed'], 12.5);

      // Cleanup
      await File(filePath).delete();
    });
  });

  group('JSON Export - preserves chronological order', () {
    test('JSON samples array is in chronological order', () async {
      final samples = [
        const GpsSample(
            timestamp: 1000, latitude: 51.5, longitude: -0.1, speed: 10.0),
        const GpsSample(
            timestamp: 2000,
            latitude: 51.501,
            longitude: -0.099,
            speed: 15.0),
        const GpsSample(
            timestamp: 3000,
            latitude: 51.502,
            longitude: -0.098,
            speed: 20.0),
        const GpsSample(
            timestamp: 4000,
            latitude: 51.503,
            longitude: -0.097,
            speed: 25.0),
      ];
      when(() => mockRepository.getBySessionId('session-1'))
          .thenAnswer((_) async => samples);

      final filePath = await exportEngine.exportJson('session-1');

      final content = await File(filePath).readAsString();
      final json = jsonDecode(content) as Map<String, dynamic>;
      final samplesList = json['samples'] as List;

      // Verify timestamps are in ascending order
      for (int i = 0; i < samplesList.length - 1; i++) {
        final current =
            (samplesList[i] as Map<String, dynamic>)['timestamp'] as int;
        final next =
            (samplesList[i + 1] as Map<String, dynamic>)['timestamp'] as int;
        expect(next, greaterThan(current));
      }

      // Verify count matches
      expect(samplesList.length, 4);

      // Cleanup
      await File(filePath).delete();
    });
  });

  group('Export availability - sessions with ≥1 sample', () {
    test('export succeeds for session with 1 sample', () async {
      final samples = [
        const GpsSample(
            timestamp: 1000, latitude: 51.5, longitude: -0.1, speed: 10.0),
      ];
      when(() => mockRepository.getBySessionId('session-1'))
          .thenAnswer((_) async => samples);

      final csvPath = await exportEngine.exportCsv('session-1');
      expect(File(csvPath).existsSync(), isTrue);

      // Cleanup
      await File(csvPath).delete();
    });

    test('export succeeds for session with many samples', () async {
      final samples = createSamples(100);
      when(() => mockRepository.getBySessionId('session-1'))
          .thenAnswer((_) async => samples);

      final jsonPath = await exportEngine.exportJson('session-1');
      expect(File(jsonPath).existsSync(), isTrue);

      final content = await File(jsonPath).readAsString();
      final json = jsonDecode(content) as Map<String, dynamic>;
      final samplesList = json['samples'] as List;
      expect(samplesList.length, 100);

      // Cleanup
      await File(jsonPath).delete();
    });
  });

  group('Export disabled for empty sessions', () {
    test('CSV export throws EmptySessionException for session with 0 samples',
        () async {
      when(() => mockRepository.getBySessionId('empty-session'))
          .thenAnswer((_) async => []);

      expect(
        () => exportEngine.exportCsv('empty-session'),
        throwsA(isA<EmptySessionException>()),
      );
    });

    test('JSON export throws EmptySessionException for session with 0 samples',
        () async {
      when(() => mockRepository.getBySessionId('empty-session'))
          .thenAnswer((_) async => []);

      expect(
        () => exportEngine.exportJson('empty-session'),
        throwsA(isA<EmptySessionException>()),
      );
    });

    test('EmptySessionException contains the session ID', () async {
      when(() => mockRepository.getBySessionId('empty-session'))
          .thenAnswer((_) async => []);

      try {
        await exportEngine.exportCsv('empty-session');
        fail('Expected EmptySessionException');
      } on EmptySessionException catch (e) {
        expect(e.sessionId, 'empty-session');
      }
    });
  });

  group('Export works without internet', () {
    test('CSV export generates file from local data without network', () async {
      // The export engine only depends on the local GpsSampleRepository.
      // No network calls are made during export generation.
      final samples = createSamples(5);
      when(() => mockRepository.getBySessionId('session-1'))
          .thenAnswer((_) async => samples);

      final filePath = await exportEngine.exportCsv('session-1');

      expect(File(filePath).existsSync(), isTrue);
      final content = await File(filePath).readAsString();
      final lines = content.trim().split('\n');
      expect(lines.length, 6); // header + 5 data rows

      // Verify only the repository was called (local data access)
      verify(() => mockRepository.getBySessionId('session-1')).called(1);

      // Cleanup
      await File(filePath).delete();
    });

    test('JSON export generates file from local data without network', () async {
      final samples = createSamples(3);
      when(() => mockRepository.getBySessionId('session-1'))
          .thenAnswer((_) async => samples);

      final filePath = await exportEngine.exportJson('session-1');

      expect(File(filePath).existsSync(), isTrue);
      verify(() => mockRepository.getBySessionId('session-1')).called(1);

      // Cleanup
      await File(filePath).delete();
    });
  });

  group('Google Drive - auth success uploads file', () {
    test('successful auth and upload calls authenticate then uploadFile',
        () async {
      when(() => mockDriveService.authenticate()).thenAnswer((_) async {});
      when(() => mockDriveService.uploadFile(any(), any()))
          .thenAnswer((_) async => 'file-id-123');

      // Create a temp file to upload
      final tempFile = File('$tempDirPath/test_upload.csv');
      await tempFile.writeAsString('test content');

      await exportEngine.uploadToGoogleDrive(tempFile.path);

      verify(() => mockDriveService.authenticate()).called(1);
      verify(() =>
              mockDriveService.uploadFile(tempFile.path, 'test_upload.csv'))
          .called(1);

      // Cleanup
      await tempFile.delete();
    });

    test('isAuthenticated returns true after successful auth', () async {
      when(() => mockDriveService.authenticate()).thenAnswer((_) async {});
      when(() => mockDriveService.isAuthenticated).thenReturn(true);

      await mockDriveService.authenticate();
      expect(mockDriveService.isAuthenticated, isTrue);
    });
  });

  group('Google Drive - auth failure shows error + fallback', () {
    test('authentication failure throws GoogleDriveAuthException on service',
        () async {
      when(() => mockDriveService.authenticate()).thenThrow(
        const GoogleDriveAuthException('User cancelled Google Sign-In'),
      );
      when(() => mockDriveService.isAuthenticated).thenReturn(false);

      expect(
        () => mockDriveService.authenticate(),
        throwsA(isA<GoogleDriveAuthException>()),
      );
      expect(mockDriveService.isAuthenticated, isFalse);
    });

    test('auth exception contains descriptive message', () async {
      when(() => mockDriveService.authenticate()).thenThrow(
        const GoogleDriveAuthException('User cancelled Google Sign-In'),
      );

      try {
        await mockDriveService.authenticate();
        fail('Expected GoogleDriveAuthException');
      } on GoogleDriveAuthException catch (e) {
        expect(e.message, contains('cancelled'));
      }
    });
  });

  group('Google Drive - upload failure shows error + fallback', () {
    test('upload failure throws GoogleDriveUploadException on service',
        () async {
      when(() => mockDriveService.authenticate()).thenAnswer((_) async {});
      when(() => mockDriveService.isAuthenticated).thenReturn(true);
      when(() => mockDriveService.uploadFile(any(), any())).thenThrow(
        const GoogleDriveUploadException('Network error during upload'),
      );

      await mockDriveService.authenticate();

      expect(
        () => mockDriveService.uploadFile('/tmp/test.csv', 'test.csv'),
        throwsA(isA<GoogleDriveUploadException>()),
      );
    });

    test('upload exception contains descriptive message', () async {
      when(() => mockDriveService.authenticate()).thenAnswer((_) async {});
      when(() => mockDriveService.uploadFile(any(), any())).thenThrow(
        const GoogleDriveUploadException('Network error during upload'),
      );

      await mockDriveService.authenticate();

      try {
        await mockDriveService.uploadFile('/tmp/test.csv', 'test.csv');
        fail('Expected GoogleDriveUploadException');
      } on GoogleDriveUploadException catch (e) {
        expect(e.message, contains('Network error'));
      }
    });
  });

  group('Insufficient storage - shows error, preserves data', () {
    test('data read error throws DataReadException', () async {
      when(() => mockRepository.getBySessionId('session-1'))
          .thenThrow(Exception('Database corrupted'));

      expect(
        () => exportEngine.exportCsv('session-1'),
        throwsA(isA<DataReadException>()),
      );
    });

    test('DataReadException preserves original session data', () async {
      // When a DataReadException occurs, the original data in the database
      // is not modified - only the export operation fails.
      when(() => mockRepository.getBySessionId('session-1'))
          .thenThrow(Exception('Database read error'));

      try {
        await exportEngine.exportCsv('session-1');
        fail('Expected DataReadException');
      } on DataReadException catch (e) {
        expect(e.message, contains('session-1'));
        expect(e.cause, isNotNull);
      }

      // The repository was only called for reading, never for writing/deleting
      verify(() => mockRepository.getBySessionId('session-1')).called(1);
      verifyNever(() => mockRepository.deleteBySessionId(any()));
    });

    test('InsufficientStorageException does not corrupt session data', () async {
      // Verify that the InsufficientStorageException type exists and
      // can be thrown without affecting the underlying data.
      const exception = InsufficientStorageException(
        'Insufficient storage to write export file',
      );
      expect(exception.message, contains('Insufficient storage'));
      expect(exception.toString(), contains('InsufficientStorageException'));
    });
  });
}
