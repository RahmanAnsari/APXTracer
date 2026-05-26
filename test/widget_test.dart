import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:apx_tracer/app.dart';

void main() {
  testWidgets('App renders home screen', (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: ApxTracerApp(),
      ),
    );

    expect(find.text('APXTracer'), findsOneWidget);
    expect(find.text('Start Recording'), findsOneWidget);
  });
}
