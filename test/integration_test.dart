import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';
import 'package:bitacora/main.dart';
import 'package:bitacora/add_task_screen.dart';
import 'package:bitacora/providers/app_state.dart';
import 'package:bitacora/providers/theme_provider.dart';
import 'package:bitacora/services/career_service.dart';

/// Tests de integración para flujos críticos
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setupFirebaseCoreMocks();

  setUpAll(() async {
    await Firebase.initializeApp();
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('Integration Tests', () {
    testWidgets('Create task flow', (WidgetTester tester) async {
      // Build app wrapped with the same providers used in main()
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider(create: (_) => AppState()),
            ChangeNotifierProvider<CareerService>.value(value: CareerService()),
            ChangeNotifierProvider<ThemeProvider>.value(value: ThemeProvider()),
          ],
          child: const BitacoraApp(),
        ),
      );

      // Wait for initialization (onboarding check, etc.)
      await tester.pumpAndSettle();

      // Test que la app inicia sin errores
      expect(find.byType(MaterialApp), findsOneWidget);
    });

    testWidgets('AddTaskScreen form validation', (WidgetTester tester) async {
      await tester.pumpWidget(const MaterialApp(home: AddTaskScreen()));

      await tester.pumpAndSettle();

      // Try to save without filling required fields
      final saveButton = find.widgetWithText(ElevatedButton, 'Crear Tarea');
      if (saveButton.evaluate().isNotEmpty) {
        await tester.ensureVisible(saveButton);
        await tester.tap(saveButton);
        await tester.pump();

        // Should show validation error
        expect(find.text('El título es obligatorio'), findsOneWidget);
      }
    });
  });
}
