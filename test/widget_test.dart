import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sentinel_one/house_plan_screen.dart';
import 'package:sentinel_one/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('SENTINEL ONE dashboard renders', (tester) async {
    await tester.pumpWidget(const SentinelApp());
    expect(find.text('SENTINEL ONE'), findsOneWidget);
    expect(find.text('La tua casa.'), findsOneWidget);
    expect(find.text('Telecamere'), findsOneWidget);
  });

  testWidgets('house plan lets the user add and persist a camera marker', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: HousePlanScreen()));
    await tester.pumpAndSettle();

    final plan = find.byType(AspectRatio);
    expect(plan, findsOneWidget);
    await tester.ensureVisible(plan);
    await tester.pumpAndSettle();
    await tester.tapAt(tester.getCenter(plan));
    await tester.pumpAndSettle();

    expect(find.text('Aggiungi punto telecamera'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'Ingresso');
    await tester.tap(find.widgetWithText(FilledButton, 'Aggiungi'));
    await tester.pumpAndSettle();

    expect(find.text('Ingresso'), findsWidgets);
    expect(find.text('PUNTI SALVATI'), findsOneWidget);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('sentinel_house_plan_camera_markers_v1'), contains('Ingresso'));
  });
}
