import 'package:flutter_ci_example/main.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows the environment', (tester) async {
    await tester.pumpWidget(const ExampleApp());
    expect(find.textContaining('Environment:'), findsOneWidget);
  });
}
