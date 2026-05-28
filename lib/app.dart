import 'dart:io' show Platform;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'screens/home_screen.dart';
import 'screens/recording_screen.dart';
import 'screens/session_summary_screen.dart';
import 'screens/session_history_screen.dart';
import 'screens/session_detail_screen.dart';
import 'screens/track_detail_screen.dart';
import 'screens/track_library_screen.dart';
import 'screens/lap_comparison_screen.dart';
import 'screens/settings_screen.dart';

/// Wraps a child widget in a platform-appropriate Page.
/// On iOS, uses [CupertinoPage] to enable the swipe-back gesture.
/// On other platforms, uses [MaterialPage].
Page<void> _buildPage(Widget child, GoRouterState state) {
  if (Platform.isIOS) {
    return CupertinoPage(key: state.pageKey, child: child);
  }
  return MaterialPage(key: state.pageKey, child: child);
}

/// GoRouter configuration for APXTracer.
final GoRouter router = GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(
      path: '/',
      pageBuilder: (context, state) => _buildPage(const HomeScreen(), state),
    ),
    GoRoute(
      path: '/recording',
      pageBuilder: (context, state) =>
          _buildPage(const RecordingScreen(), state),
    ),
    GoRoute(
      path: '/session/:id/summary',
      pageBuilder: (context, state) {
        final sessionId = state.pathParameters['id']!;
        return _buildPage(SessionSummaryScreen(sessionId: sessionId), state);
      },
    ),
    GoRoute(
      path: '/sessions',
      pageBuilder: (context, state) =>
          _buildPage(const SessionHistoryScreen(), state),
    ),
    GoRoute(
      path: '/session/:id',
      pageBuilder: (context, state) {
        final sessionId = state.pathParameters['id']!;
        return _buildPage(SessionDetailScreen(sessionId: sessionId), state);
      },
    ),
    GoRoute(
      path: '/tracks',
      pageBuilder: (context, state) =>
          _buildPage(const TrackLibraryScreen(), state),
    ),
    GoRoute(
      path: '/track/:id',
      pageBuilder: (context, state) {
        final trackId = state.pathParameters['id']!;
        return _buildPage(TrackDetailScreen(trackId: trackId), state);
      },
    ),
    GoRoute(
      path: '/lap-comparison/:trackId',
      pageBuilder: (context, state) {
        final trackId = state.pathParameters['trackId']!;
        final sessionId = state.uri.queryParameters['sessionId'];
        return _buildPage(
          LapComparisonScreen(trackId: trackId, preSessionId: sessionId),
          state,
        );
      },
    ),
    GoRoute(
      path: '/settings',
      pageBuilder: (context, state) =>
          _buildPage(const SettingsScreen(), state),
    ),
  ],
);

/// Root application widget using MaterialApp.router with GoRouter.
class ApxTracerApp extends StatelessWidget {
  const ApxTracerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'APXTracer',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      routerConfig: router,
    );
  }
}
