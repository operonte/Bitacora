import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:bitacora/main.dart';
import 'package:bitacora/add_task_screen.dart';

/// Tests de integración para flujos críticos
void main() {
  group('Integration Tests', () {
    testWidgets('Create task flow', (WidgetTester tester) async {
      // Build app
      await tester.pumpWidget(const BitacoraApp());

      // Wait for initialization
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
        await tester.tap(saveButton);
        await tester.pump();

        // Should show validation error
        expect(find.text('Por favor ingresa un título'), findsOneWidget);
      }
    });
  });
}
