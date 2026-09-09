import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../colors.dart';
import '../models/career_model.dart';
import '../services/supabase_db_service.dart';
import '../utils/input_sanitizer.dart';

/// Lo que los alumnos subieron a su área personal — sin pasar por ninguna
/// tarea oficial — en las asignaturas que el docente imparte.
///
/// Existe para entregas informales que no encajan en el flujo normal de
/// tareas: un trabajo extra para subir nota, información complementaria,
/// algo que alumno y docente ya conversaron fuera de la app. El docente no
/// puede calificarlo desde acá (no está atado a ninguna tarea ni nota);
/// solo puede verlo y abrirlo.
class StudentUploadsScreen extends StatefulWidget {
  final Career career;
  const StudentUploadsScreen({super.key, required this.career});

  @override
  State<StudentUploadsScreen> createState() => _StudentUploadsScreenState();
}

class _StudentUploadsScreenState extends State<StudentUploadsScreen> {
  final _service = SupabaseDbService();
  List<Map<String, dynamic>>? _uploads;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _error = null;
      _uploads = null;
    });
    try {
      final uploads = await _service.getStudentUploadsForTeachingSubjects(
        widget.career.id,
      );
      if (mounted) setState(() => _uploads = uploads);
    } catch (e) {
      if (mounted) {
        setState(() => _error = e.toString().replaceAll('Exception: ', ''));
      }
    }
  }

  Future<void> _openFileLink(String? url) async {
    if (url == null || url.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Este archivo no tiene enlace disponible.')),
      );
      return;
    }
    if (!InputSanitizer.isSafeExternalUrl(url)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('El enlace no es válido (solo se admite http o https).'),
        ),
      );
      return;
    }
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      try {
        await launchUrl(uri);
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('No se pudo abrir el archivo: $e')));
        }
      }
    }
  }

  IconData _categoryIcon(String category) {
    switch (category) {
      case 'guia':
        return Icons.menu_book_outlined;
      default:
        return Icons.description_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Archivos de alumnos — ${widget.career.name}'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load, tooltip: 'Actualizar'),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            _error!,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.error),
          ),
        ),
      );
    }
    final uploads = _uploads;
    if (uploads == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (uploads.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      AppColors.primary.withValues(alpha: 0.15),
                      const Color(0xFF48CAE4).withValues(alpha: 0.15),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.upload_file_outlined,
                  size: 40,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(height: 14),
              const Text(
                'Todavía no hay nada subido en tus asignaturas',
                textAlign: TextAlign.center,
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
              ),
              const SizedBox(height: 6),
              const Text(
                'Acá aparece lo que un alumno suba a su área personal en una '
                'materia que impartís, aunque no esté atado a ninguna tarea.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textSecondary, fontSize: 12.5),
              ),
            ],
          ),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 16),
        itemCount: uploads.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (context, i) {
          final row = uploads[i];
          final name = row['name'] as String? ?? 'Archivo sin nombre';
          final displayName = row['display_name'] as String? ?? 'Alumno';
          final subject = row['subject'] as String? ?? '';
          final category = row['category'] as String? ?? 'trabajo';
          final description = row['description'] as String?;
          final createdAtRaw = row['created_at'] as String?;
          final createdAt = createdAtRaw != null
              ? DateTime.tryParse(createdAtRaw)
              : null;
          final link =
              (row['drive_link'] as String?)?.trim().isNotEmpty == true
              ? row['drive_link'] as String
              : row['external_url'] as String?;

          return Material(
            color: Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(16),
            elevation: 0,
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () => _openFileLink(link),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: AppColors.primary.withValues(alpha: 0.2),
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CircleAvatar(
                      radius: 18,
                      backgroundColor: AppColors.primary.withValues(alpha: 0.12),
                      child: Icon(
                        _categoryIcon(category),
                        color: AppColors.primary,
                        size: 18,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name,
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 13.5,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            '$displayName · $subject',
                            style: const TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 12,
                            ),
                          ),
                          if (description != null && description.trim().isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              description,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 12),
                            ),
                          ],
                          if (createdAt != null) ...[
                            const SizedBox(height: 4),
                            Text(
                              DateFormat('dd/MM/yyyy').format(createdAt),
                              style: const TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const Icon(
                      Icons.open_in_new,
                      size: 18,
                      color: AppColors.textSecondary,
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
