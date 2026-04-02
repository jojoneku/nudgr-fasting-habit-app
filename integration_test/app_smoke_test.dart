import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:intermittent_fasting/main.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('hub loads and shows all module cards', (tester) async {
    app.main();
    await tester.pumpAndSettle(const Duration(seconds: 5));

    expect(find.text('DISCIPLINE PROTOCOL'), findsOneWidget);
    expect(find.text('ALCHEMY LAB'), findsOneWidget);
    expect(find.text('TRAINING GROUNDS'), findsOneWidget);
  });

  testWidgets('fasting module opens from hub', (tester) async {
    app.main();
    await tester.pumpAndSettle(const Duration(seconds: 5));

    await tester.tap(find.text('Fasting'));
    await tester.pumpAndSettle();

    expect(find.text('START FAST'), findsOneWidget);
  });
}
