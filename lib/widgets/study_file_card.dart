import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../colors.dart';
import '../models/study_file_model.dart';

/// Tarjeta de un archivo de estudio, en la lista de archivos y en la de
/// material docente.
///
/// Eran dos constructores casi idénticos dentro de `area_personal_screen.dart`
/// —mismo icono, mismo layout, mismos botones— que solo se diferenciaban en la
/// etiqueta y en el subtítulo. Cualquier arreglo había que hacerlo dos veces.
class StudyFileCard extends StatelessWidget {
  final StudyFile file;
  final VoidCallback onOpen;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  /// Si se muestran los botones de editar y eliminar. En el material docente
  /// depende de quién lo subió.
  final bool canModify;

  const StudyFileCard({
    super.key,
    required this.file,
    required this.onOpen,
    required this.onEdit,
    required this.onDelete,
    this.canModify = true,
  });

  /// Etiqueta de color: la asignatura en los trabajos, el tipo en las guías —
  /// ahí la asignatura ya la da el grupo en el que está la tarjeta.
  String get _badge {
    if (file.isGuia) return file.isLink ? 'Enlace' : 'Archivo';
    return file.subject.isNotEmpty ? file.subject : 'General';
  }

  String get _subtitle {
    if (file.isGuia) {
      return [
        DateFormat('d MMM y', 'es').format(file.createdAt),
        if (file.formattedSize.isNotEmpty) file.formattedSize,
      ].join(' · ');
    }
    return '${DateFormat('dd/MM/yy HH:mm').format(file.createdAt)} '
        '• ${file.formattedSize}';
  }

  @override
  Widget build(BuildContext context) {
    final primaryColor = Theme.of(context).primaryColor;
    final secondaryText = context.isDark
        ? AppColors.darkTextSecondary
        : AppColors.textSecondary;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: file.fileColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(file.fileIcon, color: file.fileColor, size: 26),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      file.name,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 14),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: primaryColor.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            _badge,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: primaryColor,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _subtitle,
                            style: TextStyle(fontSize: 11, color: secondaryText),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              // Sin botón de compartir a propósito. Abrir el archivo lleva a la
              // interfaz de Google Drive, que ya trae compartir, permisos,
              // descargar y enviar. Duplicarlo acá no agregaba nada y sí tenía
              // un costo: la versión anterior hacía público el archivo para
              // cualquiera con el enlace, en silencio y sin vuelta atrás desde
              // la app.
              if (canModify) ...[
                IconButton(
                  icon: const Icon(Icons.edit_outlined, size: 20),
                  tooltip: 'Editar',
                  onPressed: onEdit,
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline_rounded,
                      size: 20, color: AppColors.error),
                  tooltip: 'Eliminar',
                  onPressed: onDelete,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
