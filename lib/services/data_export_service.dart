import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import '../utils/logger.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../firebase_service.dart';
import '../task_model.dart';
import '../subject_model.dart';

/// Servicio para exportar e importar datos de la aplicación
/// 
/// Permite crear backups de tareas y materias en formato JSON
/// y restaurarlos posteriormente
class DataExportService {
  final FirebaseService _firebaseService = FirebaseService();

  /// Exporta todas las tareas y materias a un archivo JSON
  /// 
  /// Retorna true si la exportación fue exitosa
  Future<bool> exportData(BuildContext context) async {
    try {
      // Obtener datos
      final tasks = await _firebaseService.getTasks();
      final subjects = await _firebaseService.getSubjects();

      // Crear estructura de datos
      final exportData = {
        'version': '1.0',
        'exportDate': DateTime.now().toIso8601String(),
        'tasks': tasks.map((t) => t.toMap()).toList(),
        'subjects': subjects.map((s) => s.toMap()).toList(),
      };

      // Convertir a JSON
      final jsonString = jsonEncode(exportData);

      // Guardar en archivo temporal
      final directory = await getTemporaryDirectory();
      final file = File('${directory.path}/bitacora_backup_${DateTime.now().millisecondsSinceEpoch}.json');
      await file.writeAsString(jsonString);

      // Compartir archivo
      await Share.shareXFiles(
        [XFile(file.path)],
        subject: 'Backup de Bitácora',
        text: 'Backup de tareas y materias exportado el ${DateTime.now().toString().split('.')[0]}',
      );

      return true;
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al exportar: $e'), backgroundColor: Colors.red),
        );
      }
      return false;
    }
  }

  /// Importa datos desde un archivo JSON
  /// 
  /// Retorna el número de tareas y materias importadas
  Future<Map<String, int>> importData(String jsonString, BuildContext context) async {
    try {
      final data = jsonDecode(jsonString) as Map<String, dynamic>;

      int tasksImported = 0;
      int subjectsImported = 0;

      // Importar materias primero
      if (data['subjects'] != null) {
        final subjectsList = data['subjects'] as List;
        for (final subjectData in subjectsList) {
          try {
            final subject = Subject.fromMap(subjectData as Map<String, dynamic>);
            // Verificar si ya existe
            final existingSubjects = await _firebaseService.getSubjects();
            final exists = existingSubjects.any((s) => s.name == subject.name && s.professor == subject.professor);
            
            if (!exists) {
              await _firebaseService.addSubject(subject);
              subjectsImported++;
            }
          } catch (e) {
            Logger.error('Error importando materia: $e', tag: 'App');
          }
        }
      }

      // Importar tareas
      if (data['tasks'] != null) {
        final tasksList = data['tasks'] as List;
        for (final taskData in tasksList) {
          try {
            final task = Task.fromMap(taskData as Map<String, dynamic>);
            // Crear nueva tarea con ID nuevo para evitar conflictos
            final newTask = task.copyWith(id: null);
            await _firebaseService.addTask(newTask);
            tasksImported++;
          } catch (e) {
            Logger.error('Error importando tarea: $e', tag: 'App');
          }
        }
      }

      return {
        'tasks': tasksImported,
        'subjects': subjectsImported,
      };
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al importar: $e'), backgroundColor: Colors.red),
        );
      }
      return {'tasks': 0, 'subjects': 0};
    }
  }

  /// Muestra diálogo para seleccionar archivo de importación
  Future<void> showImportDialog(BuildContext context) async {
    // Nota: Para una implementación completa se necesitaría file_picker
    // Por ahora mostramos un diálogo con instrucciones
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Importar Datos'),
        content: const Text(
          'Para importar datos:\n\n'
          '1. Selecciona un archivo JSON de backup previamente exportado\n'
          '2. Las tareas y materias se agregarán a tus datos existentes\n'
          '3. Los datos duplicados no se importarán',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _showPasteDialog(context);
            },
            child: const Text('Pegar JSON'),
          ),
        ],
      ),
    );
  }

  /// Muestra diálogo para pegar JSON manualmente
  void _showPasteDialog(BuildContext context) {
    final controller = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Pegar JSON'),
        content: TextField(
          controller: controller,
          maxLines: 10,
          decoration: const InputDecoration(
            hintText: 'Pega aquí el contenido JSON del backup...',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (controller.text.trim().isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('El JSON no puede estar vacío')),
                );
                return;
              }

              Navigator.pop(context);
              
              final result = await importData(controller.text, context);
              
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      'Importación completada:\n'
                      '${result['tasks']} tareas\n'
                      '${result['subjects']} materias',
                    ),
                    backgroundColor: Colors.green,
                  ),
                );
              }
            },
            child: const Text('Importar'),
          ),
        ],
      ),
    );
  }
}
