import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'input_sanitizer.dart';

/// Abrir el enlace de una reunión (Zoom/Meet/etc). Centralizado porque el
/// enlace puede haberlo escrito otro miembro de la carrera al compartir la
/// reunión: se valida el esquema antes de abrirlo en ambos puntos de entrada
/// (pantalla de Reuniones y la franja "Hoy").
class MeetingLinkLauncher {
  MeetingLinkLauncher._();

  static Future<void> open(BuildContext context, String url) async {
    // El prefijo https:// cubre el caso normal de pegar "meet.google.com/...".
    final normalized = url.startsWith('http') ? url : 'https://$url';
    if (!InputSanitizer.isSafeExternalUrl(normalized)) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('El enlace de la reunión no es válido.'),
          ),
        );
      }
      return;
    }

    final uri = Uri.parse(normalized);
    try {
      if (!await canLaunchUrl(uri)) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('No se puede abrir el enlace de la reunión.'),
            ),
          );
        }
        return;
      }
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Error al abrir el enlace de la reunión.')),
        );
      }
    }
  }
}
