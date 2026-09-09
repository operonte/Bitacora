import 'dart:typed_data';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'google_drive_service.dart';
import 'supabase_service.dart';

/// Historia de perfil: una foto o un video corto, visible 48 horas y
/// después borrada — como en WhatsApp. Solo una activa por persona: subir
/// una nueva reemplaza la anterior.
///
/// El archivo en sí vive en el Drive de quien lo sube (igual que el resto
/// de los archivos de la app, ver GoogleDriveService), compartido por link.
/// La limpieza de las vencidas no depende de ningún proceso en segundo
/// plano — no hay cron en este proyecto —, se hace perezosamente dentro de
/// get_active_story cada vez que alguien consulta a esa persona.
class StoryService {
  static SupabaseClient get _client => SupabaseService.client;

  /// Historia activa de [userId], o null si no tiene ninguna vigente (o
  /// nunca subió una). Sirve tanto para ver la propia como la de otra
  /// persona que comparta alguna carrera — el RPC exige eso último.
  static Future<Map<String, dynamic>?> getActiveStory(String userId) async {
    final rows = await _client.rpc(
      'get_active_story',
      params: {'p_user_id': userId},
    );
    final list = List<Map<String, dynamic>>.from(rows as List);
    return list.isEmpty ? null : list.first;
  }

  /// Sube [bytes]/[filePath] como la nueva historia, reemplazando la que
  /// hubiera: borra la fila anterior y revoca su link de Drive antes de
  /// insertar la nueva, para no dejar el archivo viejo accesible sin que
  /// nadie lo vea desde la app.
  static Future<void> uploadStory({
    required String fileName,
    required int sizeBytes,
    required String mimeType,
    required String mediaType, // 'photo' | 'video'
    String? filePath,
    Uint8List? bytes,
    void Function(double progress)? onProgress,
  }) async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) throw Exception('Usuario no autenticado');

    final previa = await getActiveStory(uid);

    final res = await GoogleDriveService().uploadStudyFile(
      fileName: fileName,
      sizeBytes: sizeBytes,
      filePath: filePath,
      bytes: bytes,
      mimeType: mimeType,
      career: 'Historias',
      onProgress: onProgress,
    );
    await GoogleDriveService().setLinkViewable(res.fileId);

    if (previa != null) {
      await _deleteRow(previa);
    }

    await _client.from('stories').insert({
      'user_id': uid,
      'media_url': 'https://drive.google.com/uc?export=view&id=${res.fileId}',
      'media_type': mediaType,
      'drive_file_id': res.fileId,
    });
  }

  /// Borra mi historia activa antes de que se venzan las 48 h, si el dueño
  /// quiere sacarla antes.
  static Future<void> deleteMyStory() async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) return;
    final previa = await getActiveStory(uid);
    if (previa == null) return;
    await _deleteRow(previa);
  }

  static Future<void> _deleteRow(Map<String, dynamic> story) async {
    final id = story['id'] as String?;
    if (id != null) {
      await _client.from('stories').delete().eq('id', id);
    }
    final oldFileId = story['drive_file_id'] as String?;
    if (oldFileId != null && oldFileId.isNotEmpty) {
      try {
        await GoogleDriveService().revokeLinkViewable(oldFileId);
      } catch (_) {
        // No bloquea el reemplazo por esto: en el peor caso el archivo
        // viejo queda con el link abierto, pero ya no aparece en la app.
      }
    }
  }
}
