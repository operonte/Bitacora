import 'package:flutter/material.dart';
import '../colors.dart';

/// Acomodar la foto de portada arrastrándola, como en Facebook: no recorta
/// el archivo — solo elige qué parte queda visible dentro del marco fijo
/// de la portada, y esa posición es lo único que se guarda.
class CoverPhotoPositionerScreen extends StatefulWidget {
  final String imageUrl;
  final double initialOffset;
  final double frameHeight;

  const CoverPhotoPositionerScreen({
    super.key,
    required this.imageUrl,
    required this.initialOffset,
    this.frameHeight = 160,
  });

  @override
  State<CoverPhotoPositionerScreen> createState() =>
      _CoverPhotoPositionerScreenState();
}

class _CoverPhotoPositionerScreenState
    extends State<CoverPhotoPositionerScreen> {
  late double _offsetY = widget.initialOffset;

  void _onDrag(DragUpdateDetails details) {
    setState(() {
      // El recorrido total de Alignment es 2 (-1 a 1) sobre el alto extra
      // que le sobra a la imagen respecto del marco — una aproximación
      // simple y suficiente: mover el dedo la mitad del alto del marco ya
      // lleva de una punta a la otra.
      final delta = details.delta.dy / (widget.frameHeight / 2);
      _offsetY = (_offsetY + delta).clamp(-1.0, 1.0);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Acomodar portada'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, _offsetY),
            child: const Text('Guardar'),
          ),
        ],
      ),
      body: Column(
        children: [
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'Arrastra la foto hacia arriba o abajo para elegir qué parte '
              'se ve en tu perfil.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ),
          ClipRect(
            child: SizedBox(
              height: widget.frameHeight,
              width: double.infinity,
              child: GestureDetector(
                onVerticalDragUpdate: _onDrag,
                child: Container(
                  decoration: BoxDecoration(
                    image: DecorationImage(
                      image: NetworkImage(widget.imageUrl),
                      fit: BoxFit.cover,
                      alignment: Alignment(0, _offsetY),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Así se va a ver en tu perfil',
            style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}
