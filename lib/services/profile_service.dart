import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'google_drive_service.dart';
import 'supabase_service.dart';

/// Perfil personal: datos propios (bio, edad, género, situación
/// sentimental, religión, fotos) y el perfil público de otra persona de tu
/// carrera.
///
/// El nombre y la foto principal siguen viviendo en los metadatos de
/// Supabase Auth (`full_name`/`avatar_url`), como ya hacía la app —
/// `sync_profile_from_auth` los refleja en `public.profiles` solo. Los
/// campos nuevos van directo a `public.profiles`: la política
/// `profiles_update_own` ya permite escribir la propia fila, así que no
/// hace falta un RPC para guardarlos, solo para leer el perfil de otro.
class ProfileService {
  static final ProfileService _instance = ProfileService._internal();
  factory ProfileService() => _instance;
  ProfileService._internal();

  SupabaseClient get _client => SupabaseService.client;

  static const maxExtraPhotos = 4;

  Future<Map<String, dynamic>?> getMyProfile() async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) return null;
    return await _client.from('profiles').select().eq('id', uid).maybeSingle();
  }

  Future<void> updateMyProfile({
    String? bio,
    int? age,
    String? gender,
    String? relationshipStatus,
    String? religion,
  }) async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) throw Exception('Usuario no autenticado');
    await _client
        .from('profiles')
        .update({
          'bio': bio,
          'age': age,
          'gender': gender,
          'relationship_status': relationshipStatus,
          'religion': religion,
        })
        .eq('id', uid);
  }

  /// Perfil de otra persona. Solo funciona si comparte al menos una carrera
  /// con vos — el RPC del servidor lo exige, ver get_public_profile.
  Future<Map<String, dynamic>?> getPublicProfile(String userId) async {
    final rows = await _client.rpc(
      'get_public_profile',
      params: {'p_user_id': userId},
    );
    final list = List<Map<String, dynamic>>.from(rows as List);
    return list.isEmpty ? null : list.first;
  }

  /// Todos los miembros de una carrera (alumnos y docentes) para el
  /// directorio — cualquier miembro puede pedirlo, no solo docente o admin.
  Future<List<Map<String, dynamic>>> getCareerMembers(String careerId) async {
    final rows = await _client.rpc(
      'get_career_members',
      params: {'p_career_id': careerId},
    );
    return List<Map<String, dynamic>>.from(rows as List);
  }

  /// Sube una foto al Drive del usuario, fuera del árbol de archivos de
  /// estudio (carpeta `Bitácora/Perfil`, que `classifyDrivePath` ignora sin
  /// problema por no calzar con ninguna carrera real) y la deja visible por
  /// enlace para poder mostrarla en el perfil. Devuelve la URL para usar en
  /// una `Image.network`.
  Future<String> uploadPhoto({
    required String fileName,
    required int sizeBytes,
    required String extension,
    String? filePath,
    Uint8List? bytes,
    void Function(double progress)? onProgress,
  }) async {
    final res = await GoogleDriveService().uploadStudyFile(
      fileName: fileName,
      sizeBytes: sizeBytes,
      filePath: filePath,
      bytes: bytes,
      mimeType: extension,
      career: 'Perfil',
      onProgress: onProgress,
    );
    await GoogleDriveService().setLinkViewable(res.fileId);
    return 'https://drive.google.com/uc?export=view&id=${res.fileId}';
  }

  /// Cambia la foto principal. Va a través de Auth (no de `profiles`
  /// directo) para que `sync_profile_from_auth` la refleje sola, igual que
  /// ya hacía el diálogo de "Editar perfil" con la URL pegada a mano.
  Future<void> setMainPhoto(String url) async {
    await _client.auth.updateUser(UserAttributes(data: {'avatar_url': url}));
  }

  Future<void> addExtraPhoto(String url) async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) throw Exception('Usuario no autenticado');
    final current = await getMyProfile();
    final list = List<String>.from(
      (current?['extra_photo_urls'] as List?) ?? [],
    );
    if (list.length >= maxExtraPhotos) {
      throw Exception(
        'Ya tenés el máximo de $maxExtraPhotos fotos. Borrá una para agregar otra.',
      );
    }
    list.add(url);
    await _client
        .from('profiles')
        .update({'extra_photo_urls': list})
        .eq('id', uid);
  }

  Future<void> removeExtraPhoto(String url) async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) throw Exception('Usuario no autenticado');
    final current = await getMyProfile();
    final list = List<String>.from(
      (current?['extra_photo_urls'] as List?) ?? [],
    );
    list.remove(url);
    await _client
        .from('profiles')
        .update({'extra_photo_urls': list})
        .eq('id', uid);
  }
}
