import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'data/analytics_repository.dart';
import 'data/database_helper.dart';
import 'data/gps_sample_repository.dart';
import 'data/lap_repository.dart';
import 'data/session_repository.dart';
import 'data/track_repository.dart';
import 'engines/analytics/analytics_engine.dart';
import 'engines/lap_detection/lap_detection_engine.dart';
import 'engines/post_session_pipeline.dart';
import 'engines/recording/recording_engine.dart';
import 'engines/track_discovery/track_discovery_engine.dart';
import 'providers/recording_provider.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // Create shared DatabaseHelper singleton instance.
  final databaseHelper = DatabaseHelper();

  // Create repository instances.
  final sessionRepository = SessionRepository(databaseHelper);
  final gpsSampleRepository = GpsSampleRepository(databaseHelper);
  final lapRepository = LapRepository(databaseHelper);
  final trackRepository = TrackRepository(databaseHelper);
  final analyticsRepository = AnalyticsRepository(databaseHelper);

  // Create engine instances.
  final recordingEngine = RecordingEngine(
    sessionRepository: sessionRepository,
    gpsSampleRepository: gpsSampleRepository,
  );

  final trackDiscoveryEngine = TrackDiscoveryEngine(
    trackRepository: trackRepository,
    sessionRepository: sessionRepository,
  );

  final lapDetectionEngine = LapDetectionEngine();

  final analyticsEngine = AnalyticsEngine(analyticsRepository);

  // Create the post-session pipeline.
  final postSessionPipeline = PostSessionPipeline(
    sessionRepository: sessionRepository,
    gpsSampleRepository: gpsSampleRepository,
    lapRepository: lapRepository,
    trackDiscoveryEngine: trackDiscoveryEngine,
    lapDetectionEngine: lapDetectionEngine,
    analyticsEngine: analyticsEngine,
  );

  runApp(
    ProviderScope(
      overrides: [
        recordingEngineProvider.overrideWithValue(recordingEngine),
        postSessionPipelineProvider.overrideWithValue(postSessionPipeline),
      ],
      child: const ApxTracerApp(),
    ),
  );
}
