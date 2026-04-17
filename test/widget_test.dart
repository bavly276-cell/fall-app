import 'package:flutter_test/flutter_test.dart';
import 'package:fall_detection_app/main.dart';
import 'package:provider/provider.dart';
import 'package:fall_detection_app/services/app_state.dart';

void main() {
  testWidgets('App loads successfully', (WidgetTester tester) async {
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => AppState(),
        child: const FallDetectionApp(),
      ),
    );
    expect(find.text('ECU'), findsOneWidget);
  });
}
