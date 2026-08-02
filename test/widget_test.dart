import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bitacora/widgets/app_icon_widget.dart';

void main() {
  group('AppIconWidget', () {
    testWidgets('builds without throwing and sizes itself to the requested size',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: Center(child: AppIconWidget(size: 48))),
        ),
      );

      expect(find.byType(AppIconWidget), findsOneWidget);
      expect(find.byType(CustomPaint), findsWidgets);

      final size = tester.getSize(find.byType(AppIconWidget));
      expect(size.width, 48);
      expect(size.height, 48);
    });

    testWidgets('defaults to a size of 24 when none is given',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: Center(child: AppIconWidget())),
        ),
      );

      final size = tester.getSize(find.byType(AppIconWidget));
      expect(size.width, 24);
      expect(size.height, 24);
    });
  });

  group('AppIconPainter', () {
    test('shouldRepaint is always false (icon is static)', () {
      final painter = AppIconPainter();
      expect(painter.shouldRepaint(AppIconPainter()), isFalse);
    });
  });
}
