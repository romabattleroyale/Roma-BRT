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

    // Scroll the ListView normally instead of ensureVisible(AspectRatio): the
    // latter can trigger a Flutter test build-scope assertion during animated
    // scrolling on this screen.
    await tester.drag(find.byType(ListView), const Offset(0, -500));
    await tester.pumpAndSettle();

    final plan = find.byType(GestureDetector).first;
    expect(plan, findsOneWidget);
    await tester.tap(plan);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

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
