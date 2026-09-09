import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../providers/theme_provider.dart';

enum MascotState { bored, content, angry, surprised, sad }

/// Mascota ilustrada, según [MascotOption] elegida en Configuración. Si el
/// usuario no eligió ninguna, no dibuja nada — quien lo use debe reservar su
/// propio layout con [MascotWidget.isEnabled].
///
/// `robot`/`hamsterYellow`/`catBlue` son PNG con transparencia (sin fuente
/// vectorial disponible); el resto son SVG real — `cat`/`bunny`/
/// `hamsterBrown` vienen de un `.eps`/`.ai` convertido con Inkscape. El
/// widget resuelve cuál cargar según [option].
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

  /// `robot`/`cat` son de antes de que existiera el estado `sad` (nadie les
  /// dibujó una cara triste todavía) — caen a `angry` en vez de romper.
  bool get _hasNoSadArt =>
      option == MascotOption.robot || option == MascotOption.cat;

  String get _stateName {
    if (state == MascotState.sad && _hasNoSadArt) return 'angry';
    return switch (state) {
      MascotState.bored => 'bored',
      MascotState.content => 'content',
      MascotState.angry => 'angry',
      MascotState.surprised => 'surprised',
      MascotState.sad => 'sad',
    };
  }

  bool get _isSvg =>
      option == MascotOption.cat ||
      option == MascotOption.bunny ||
      option == MascotOption.hamsterBrown;

  String get _assetPath {
    // robot -> robot_h y cat -> cat_x: nombres que el usuario les puso a
    // mano en assets/mascots/ para que no se confundan con las 4 nuevas
    // (especialmente cat_x vs. cat_blue, que si no comparten prefijo).
    final base = switch (option) {
      MascotOption.robot => 'robot_h',
      MascotOption.cat => 'cat_x',
      MascotOption.hamsterYellow => 'hamster_yellow',
      MascotOption.catBlue => 'cat_blue',
      MascotOption.bunny => 'bunny',
      MascotOption.hamsterBrown => 'hamster_brown',
      MascotOption.none => 'robot_h',
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
