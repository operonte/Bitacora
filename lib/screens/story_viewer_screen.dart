import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../colors.dart';
import '../utils/input_sanitizer.dart';

/// Pantalla completa para ver una historia: foto en pantalla completa, o
/// —para video, sin reproductor propio en la app— un botón para abrirlo en
/// una app externa. Dura 48 h desde que se subió; quien la ve no tiene por
/// qué saber la hora exacta, así que no se muestra cuenta regresiva.
class StoryViewerScreen extends StatelessWidget {
  final String mediaUrl;
  final String mediaType; // 'photo' | 'video'
  final String ownerName;
  final bool isOwn;
  final Future<void> Function()? onDelete;

  const StoryViewerScreen({
    super.key,
    required this.mediaUrl,
    required this.mediaType,
    required this.ownerName,
    this.isOwn = false,
    this.onDelete,
  });

  Future<void> _abrir(BuildContext context) async {
    if (!InputSanitizer.isSafeExternalUrl(mediaUrl)) return;
    final uri = Uri.tryParse(mediaUrl);
    if (uri == null) return;
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      try {
        await launchUrl(uri);
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('No se pudo abrir: $e')));
        }
      }
    }
  }

  Future<void> _confirmarBorrar(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Eliminar historia?'),
        content: const Text('Se borra para siempre, antes de las 48 horas.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (ok != true || onDelete == null) return;
    await onDelete!();
    if (context.mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(ownerName),
        actions: [
          if (isOwn && onDelete != null)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Eliminar historia',
              onPressed: () => _confirmarBorrar(context),
            ),
        ],
      ),
      body: Center(
        child: mediaType == 'photo'
            ? InteractiveViewer(
                child: Image.network(
                  mediaUrl,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => const Icon(
                    Icons.broken_image_outlined,
                    color: Colors.white54,
                    size: 64,
                  ),
                ),
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.videocam_outlined,
                    color: Colors.white70,
                    size: 64,
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Historia en video',
                    style: TextStyle(color: Colors.white, fontSize: 16),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Se abre en tu reproductor de video',
                    style: TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    onPressed: () => _abrir(context),
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('Reproducir'),
                  ),
                ],
              ),
      ),
    );
  }
}
