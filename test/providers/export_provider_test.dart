import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:apx_tracer/engines/export/export_engine.dart';
import 'package:apx_tracer/providers/export_provider.dart';
import 'package:apx_tracer/services/google_drive_service.dart';

// --- Mocks ---

class MockExportEngine extends Mock implements IExportEngine {}

void main() {
  late MockExportEngine mockExportEngine;
  late ExportNotifier notifier;

  setUp(() {
    mockExportEngine = MockExportEngine();
    notifier = ExportNotifier(mockExportEngine);
  });

  group('ExportNotifier', () {
    group('exportCsv', () {
      test('transitions state to exporting then success via share sheet',
          () async {
        when(() => mockExportEngine.exportCsv('session-1'))
            .thenAnswer((_) async => '/tmp/export.csv');
        when(() => mockExportEngine.shareFile('/tmp/export.csv'))
            .thenAnswer((_) async {});

        // Track state transitions
        final states = <ExportStatus>[];
        notifier.addListener((state) {
          states.add(state.status);
        });

        await notifier.exportCsv('session-1', ExportDestination.shareSheet);

        expect(notifier.state.status, equals(ExportStatus.success));
        expect(notifier.state.filePath, equals('/tmp/export.csv'));

        // Verify exporting was reached before success
        expect(states, contains(ExportStatus.exporting));
        expect(states.last, equals(ExportStatus.success));
      });

      test('transitions state to exporting then success via Google Drive',
          () async {
        when(() => mockExportEngine.exportCsv('session-1'))
            .thenAnswer((_) async => '/tmp/export.csv');
        when(() => mockExportEngine.uploadToGoogleDrive('/tmp/export.csv'))
            .thenAnswer((_) async {});

        await notifier.exportCsv('session-1', ExportDestination.googleDrive);

        expect(notifier.state.status, equals(ExportStatus.success));
        expect(notifier.state.filePath, equals('/tmp/export.csv'));
      });
    });

    group('exportJson', () {
      test('transitions state to exporting then success via share sheet',
          () async {
        when(() => mockExportEngine.exportJson('session-1'))
            .thenAnswer((_) async => '/tmp/export.json');
        when(() => mockExportEngine.shareFile('/tmp/export.json'))
            .thenAnswer((_) async {});

        final states = <ExportStatus>[];
        notifier.addListener((state) {
          states.add(state.status);
        });

        await notifier.exportJson('session-1', ExportDestination.shareSheet);

        expect(notifier.state.status, equals(ExportStatus.success));
        expect(notifier.state.filePath, equals('/tmp/export.json'));
        expect(states, contains(ExportStatus.exporting));
      });
    });

    group('Google Drive failure', () {
      test('sets error state with showShareSheetFallback=true on auth failure',
          () async {
        when(() => mockExportEngine.exportCsv('session-1'))
            .thenAnswer((_) async => '/tmp/export.csv');
        when(() => mockExportEngine.uploadToGoogleDrive('/tmp/export.csv'))
            .thenThrow(
                const GoogleDriveAuthException('Auth cancelled by user'));

        await notifier.exportCsv('session-1', ExportDestination.googleDrive);

        expect(notifier.state.status, equals(ExportStatus.error));
        expect(notifier.state.showShareSheetFallback, isTrue);
        expect(notifier.state.errorMessage, contains('authentication'));
        expect(notifier.state.filePath, equals('/tmp/export.csv'));
      });

      test(
          'sets error state with showShareSheetFallback=true on upload failure',
          () async {
        when(() => mockExportEngine.exportJson('session-1'))
            .thenAnswer((_) async => '/tmp/export.json');
        when(() => mockExportEngine.uploadToGoogleDrive('/tmp/export.json'))
            .thenThrow(
                const GoogleDriveUploadException('Network timeout'));

        await notifier.exportJson('session-1', ExportDestination.googleDrive);

        expect(notifier.state.status, equals(ExportStatus.error));
        expect(notifier.state.showShareSheetFallback, isTrue);
        expect(notifier.state.errorMessage, contains('upload'));
        expect(notifier.state.filePath, equals('/tmp/export.json'));
      });
    });

    group('shareViaShareSheet', () {
      test('works as fallback after Google Drive failure', () async {
        // First, simulate a Google Drive failure to set filePath in state
        when(() => mockExportEngine.exportCsv('session-1'))
            .thenAnswer((_) async => '/tmp/export.csv');
        when(() => mockExportEngine.uploadToGoogleDrive('/tmp/export.csv'))
            .thenThrow(
                const GoogleDriveAuthException('Auth failed'));

        await notifier.exportCsv('session-1', ExportDestination.googleDrive);

        // Verify we're in error state with fallback available
        expect(notifier.state.status, equals(ExportStatus.error));
        expect(notifier.state.showShareSheetFallback, isTrue);
        expect(notifier.state.filePath, equals('/tmp/export.csv'));

        // Now use the share sheet fallback
        when(() => mockExportEngine.shareFile('/tmp/export.csv'))
            .thenAnswer((_) async {});

        await notifier.shareViaShareSheet();

        expect(notifier.state.status, equals(ExportStatus.success));
        verify(() => mockExportEngine.shareFile('/tmp/export.csv')).called(1);
      });

      test('does nothing when filePath is null', () async {
        // State is idle with no filePath
        expect(notifier.state.filePath, isNull);

        await notifier.shareViaShareSheet();

        // State should remain unchanged
        expect(notifier.state.status, equals(ExportStatus.idle));
        verifyNever(() => mockExportEngine.shareFile(any()));
      });
    });

    group('reset', () {
      test('returns state to idle', () async {
        // Put notifier in a non-idle state first
        when(() => mockExportEngine.exportCsv('session-1'))
            .thenAnswer((_) async => '/tmp/export.csv');
        when(() => mockExportEngine.shareFile('/tmp/export.csv'))
            .thenAnswer((_) async {});

        await notifier.exportCsv('session-1', ExportDestination.shareSheet);
        expect(notifier.state.status, equals(ExportStatus.success));

        // Reset
        notifier.reset();

        expect(notifier.state.status, equals(ExportStatus.idle));
        expect(notifier.state.filePath, isNull);
        expect(notifier.state.errorMessage, isNull);
        expect(notifier.state.showShareSheetFallback, isFalse);
      });
    });

    group('error states', () {
      test('empty session exception sets error state', () async {
        when(() => mockExportEngine.exportCsv('empty-session'))
            .thenThrow(const EmptySessionException('empty-session'));

        await notifier.exportCsv(
            'empty-session', ExportDestination.shareSheet);

        expect(notifier.state.status, equals(ExportStatus.error));
        expect(notifier.state.errorMessage, isNotNull);
      });

      test('insufficient storage exception sets error state', () async {
        when(() => mockExportEngine.exportJson('session-1'))
            .thenThrow(const InsufficientStorageException());

        await notifier.exportJson('session-1', ExportDestination.shareSheet);

        expect(notifier.state.status, equals(ExportStatus.error));
        expect(notifier.state.errorMessage, isNotNull);
      });
    });
  });
}
