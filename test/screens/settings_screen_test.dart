import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:apx_tracer/data/database_helper.dart';
import 'package:apx_tracer/screens/settings_screen.dart';

/// Mock for DatabaseHelper to test deletion behavior without a real database.
class MockDatabaseHelper extends Mock implements DatabaseHelper {}

void main() {
  group('SettingsScreen', () {
    testWidgets('displays Data Management section with Delete All Data option',
        (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: SettingsScreen(),
          ),
        ),
      );

      expect(find.text('Settings'), findsOneWidget);
      expect(find.text('Data Management'), findsOneWidget);
      expect(find.text('Delete All Data'), findsOneWidget);
      expect(
        find.text(
          'Permanently remove all sessions, tracks, and telemetry data',
        ),
        findsOneWidget,
      );
    });

    testWidgets('displays About section with app version info',
        (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: SettingsScreen(),
          ),
        ),
      );

      expect(find.text('About'), findsOneWidget);
      expect(find.text('APXTracer'), findsOneWidget);
      expect(find.text('Version 1.0.0'), findsOneWidget);
      expect(
        find.text('All data stored locally with encryption'),
        findsOneWidget,
      );
    });

    testWidgets('shows confirmation dialog when Delete All Data is tapped',
        (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: SettingsScreen(),
          ),
        ),
      );

      await tester.tap(find.text('Delete All Data'));
      await tester.pumpAndSettle();

      // Verify dialog content
      expect(find.text('Delete All Data?'), findsOneWidget);
      expect(
        find.text(
          'This will permanently delete all your sessions, tracks, laps, '
          'and telemetry data. This action cannot be undone.',
        ),
        findsOneWidget,
      );
      expect(find.text('Cancel'), findsOneWidget);
      expect(find.text('Delete'), findsOneWidget);
      expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
    });

    testWidgets('dismisses dialog when Cancel is tapped', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: SettingsScreen(),
          ),
        ),
      );

      await tester.tap(find.text('Delete All Data'));
      await tester.pumpAndSettle();

      // Tap Cancel
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      // Dialog should be dismissed
      expect(find.text('Delete All Data?'), findsNothing);
    });

    testWidgets('has delete icon with red color', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: SettingsScreen(),
          ),
        ),
      );

      final deleteIcon = find.byIcon(Icons.delete_forever);
      expect(deleteIcon, findsOneWidget);

      final iconWidget = tester.widget<Icon>(deleteIcon);
      expect(iconWidget.color, Colors.red);
    });
  });
}
