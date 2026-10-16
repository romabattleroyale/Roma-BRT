import 'package:flutter_test/flutter_test.dart';
import 'package:sentinel_one/main.dart';
void main() {
  testWidgets('SENTINEL ONE dashboard renders', (tester) async {
    await tester.pumpWidget(const SentinelApp());
    expect(find.text('SENTINEL ONE'), findsOneWidget);
    expect(find.text('La tua casa.'), findsOneWidget);
    expect(find.text('Telecamere'), findsOneWidget);
  });
}
