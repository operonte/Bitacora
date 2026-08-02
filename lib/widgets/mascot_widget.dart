import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../providers/theme_provider.dart';

enum MascotState { bored, content, angry, surprised }

/// Mascota ilustrada (robot o gato, según [MascotOption] elegida en
/// Configuración). Si el usuario no eligió ninguna, no dibuja nada — quien
/// lo use debe reservar su propio layout con [MascotWidget.isEnabled].
///
/// El gato es SVG, el robot es PNG (assets de origen distinto) — el widget
/// resuelve cuál cargar según [option].
class MascotWidget extends StatelessWidget {
  final MascotOption option;
  final MascotState state;
  final double size;

  const MascotWidget({
    super.key,
    required this.option,
    required this.state,
    this.size = 96,
  });

  static bool isEnabled(MascotOption option) => option != MascotOption.none;

  String get _stateName => switch (state) {
        MascotState.bored => 'bored',
        MascotState.content => 'content',
        MascotState.angry => 'angry',
        MascotState.surprised => 'surprised',
      };

  bool get _isSvg => option == MascotOption.cat;

  String get _assetPath {
    final base = switch (option) {
      MascotOption.robot => 'robot',
      MascotOption.cat => 'cat',
      MascotOption.none => 'robot',
    };
    final ext = _isSvg ? 'svg' : 'png';
    return 'assets/mascots/${base}_$_stateName.$ext';
  }

  @override
  Widget build(BuildContext context) {
    if (option == MascotOption.none) return const SizedBox.shrink();

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 350),
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: ScaleTransition(scale: animation, child: child),
      ),
      child: _isSvg
          ? SvgPicture.asset(
              _assetPath,
              key: ValueKey(_assetPath),
              width: size,
              height: size,
            )
          : Image.asset(
              _assetPath,
              key: ValueKey(_assetPath),
              width: size,
              height: size,
            ),
    );
  }
}
