import 'package:flutter/material.dart';

class AppIconWidget extends StatelessWidget {
  final double size;

  const AppIconWidget({super.key, this.size = 24.0});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: AppIconPainter(), child: Container()),
    );
  }
}

class AppIconPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color =
          const Color(0xFF2196F3) // Azul claro como el icono descrito
      ..style = PaintingStyle.fill;

    final strokePaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    final centerX = size.width / 2;
    final centerY = size.height / 2;
    final bookWidth = size.width * 0.7;
    final bookHeight = size.height * 0.8;

    // Dibujar libro abierto (dos páginas)
    final leftPage = Rect.fromCenter(
      center: Offset(centerX - bookWidth * 0.25, centerY),
      width: bookWidth * 0.5,
      height: bookHeight,
    );

    final rightPage = Rect.fromCenter(
      center: Offset(centerX + bookWidth * 0.25, centerY),
      width: bookWidth * 0.5,
      height: bookHeight,
    );

    // Páginas del libro
    canvas.drawRRect(
      RRect.fromRectAndRadius(leftPage, const Radius.circular(4)),
      paint,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(rightPage, const Radius.circular(4)),
      paint,
    );

    // Línea central del libro
    canvas.drawLine(
      Offset(centerX, centerY - bookHeight / 2),
      Offset(centerX, centerY + bookHeight / 2),
      strokePaint,
    );

    // Cruz en la página izquierda
    final crossSize = size.width * 0.15;
    final crossCenter = Offset(centerX - bookWidth * 0.25, centerY);
    canvas.drawLine(
      Offset(crossCenter.dx - crossSize / 2, crossCenter.dy),
      Offset(crossCenter.dx + crossSize / 2, crossCenter.dy),
      strokePaint,
    );
    canvas.drawLine(
      Offset(crossCenter.dx, crossCenter.dy - crossSize / 2),
      Offset(crossCenter.dx, crossCenter.dy + crossSize / 2),
      strokePaint,
    );

    // Casillas de verificación en la página derecha
    final checkboxSize = size.width * 0.08;
    final checkboxSpacing = size.height * 0.15;
    final checkboxStartY = centerY - checkboxSpacing;

    for (int i = 0; i < 3; i++) {
      final checkboxY = checkboxStartY + (i * checkboxSpacing);
      final checkboxRect = RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(centerX + bookWidth * 0.25, checkboxY),
          width: checkboxSize,
          height: checkboxSize,
        ),
        const Radius.circular(2),
      );

      // Dibujar casilla
      canvas.drawRRect(checkboxRect, strokePaint);

      // Marcar las primeras dos casillas
      if (i < 2) {
        final checkPaint = Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.0;

        final checkSize = checkboxSize * 0.6;
        final checkCenter = Offset(centerX + bookWidth * 0.25, checkboxY);

        // Dibujar checkmark
        final path = Path();
        path.moveTo(checkCenter.dx - checkSize * 0.3, checkCenter.dy);
        path.lineTo(
          checkCenter.dx - checkSize * 0.1,
          checkCenter.dy + checkSize * 0.2,
        );
        path.lineTo(
          checkCenter.dx + checkSize * 0.3,
          checkCenter.dy - checkSize * 0.2,
        );
        canvas.drawPath(path, checkPaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
