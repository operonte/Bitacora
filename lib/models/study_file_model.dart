import 'package:flutter/material.dart';
import '../utils/file_type_icons.dart';

/// Categorías de archivo. Son lo mismo salvo por dónde se muestran y en qué
/// carpeta de Drive viven: [trabajo] son los trabajos que sube el estudiante
/// ("Mis archivos") y [guia] el material docente.
class StudyFileCategory {
  static const String trabajo = 'trabajo';
  static const String guia = 'guia';

  static const List<String> values = [trabajo, guia];

  /// Normaliza lo que venga de Supabase o de la caché: cualquier valor
  /// desconocido cae en [trabajo], que es el comportamiento histórico.
  static String parse(Object? raw) =>
      raw?.toString() == guia ? guia : trabajo;
}

/// Un archivo de estudio: un archivo subido a Google Drive o un enlace
/// externo. Los campos de Drive son nulos cuando es un enlace.
class StudyFile {
  final String? id;
  final String name;
  final String subject;
  final String? driveFileId;
  final String? mimeType;
  final int? sizeBytes;
  final String driveLink;
  final String userId;
  final String category;
  final String? description;
  final String? externalUrl;

  /// Carrera a la que pertenece el archivo, solo para poder filtrarlo. No
  /// cambia quién lo ve: los archivos siguen siendo privados de quien los
  /// sube (política study_files_own). Null en los subidos antes de que
  /// existiera este campo, que aparecen como "Sin carrera".
  final String? careerId;
  final DateTime createdAt;

  StudyFile({
    this.id,
    required this.name,
    required this.subject,
    this.driveFileId,
    this.mimeType,
    this.sizeBytes,
    this.driveLink = '',
    required this.userId,
    this.category = StudyFileCategory.trabajo,
    this.description,
    this.externalUrl,
    this.careerId,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  bool get isLink => externalUrl != null && externalUrl!.isNotEmpty;
  bool get isGuia => category == StudyFileCategory.guia;

  /// URL a abrir al tocarlo: el enlace externo si lo tiene, o el de Drive.
  String get openUrl => isLink ? externalUrl! : driveLink;

  Map<String, dynamic> toMap() {
    return {
      'id': id ?? DateTime.now().millisecondsSinceEpoch.toString(),
      'name': name,
      'subject': subject,
      'drive_file_id': driveFileId,
      'mime_type': mimeType,
      'size_bytes': sizeBytes,
      'drive_link': driveLink,
      'user_id': userId,
      'category': category,
      'description': description,
      'external_url': externalUrl,
      'career_id': careerId,
      'created_at': createdAt.toIso8601String(),
    };
  }

  factory StudyFile.fromMap(Map<String, dynamic> map) {
    return StudyFile(
      id: map['id']?.toString(),
      // 'title' era el nombre del campo en el modelo viejo de material
      // docente, que se guardaba en su propia caja de Hive.
      name: (map['name'] ?? map['title'] ?? '').toString(),
      subject: map['subject']?.toString() ?? '',
      driveFileId: _nullIfEmpty(map['drive_file_id']),
      mimeType: _nullIfEmpty(map['mime_type']),
      sizeBytes: map['size_bytes'] is int
          ? map['size_bytes'] as int
          : int.tryParse(map['size_bytes']?.toString() ?? ''),
      driveLink: map['drive_link']?.toString() ?? '',
      userId: map['user_id']?.toString() ?? '',
      category: StudyFileCategory.parse(map['category']),
      description: _nullIfEmpty(map['description']),
      externalUrl: _nullIfEmpty(map['external_url']),
      careerId: _nullIfEmpty(map['career_id']),
      createdAt: _parseDate(map['created_at']),
    );
  }

  StudyFile copyWith({
    String? id,
    String? name,
    String? subject,
    String? driveFileId,
    String? mimeType,
    int? sizeBytes,
    String? driveLink,
    String? userId,
    String? category,
    String? description,
    String? externalUrl,
    String? careerId,
    DateTime? createdAt,
  }) {
    return StudyFile(
      id: id ?? this.id,
      name: name ?? this.name,
      subject: subject ?? this.subject,
      driveFileId: driveFileId ?? this.driveFileId,
      mimeType: mimeType ?? this.mimeType,
      sizeBytes: sizeBytes ?? this.sizeBytes,
      driveLink: driveLink ?? this.driveLink,
      userId: userId ?? this.userId,
      category: category ?? this.category,
      description: description ?? this.description,
      externalUrl: externalUrl ?? this.externalUrl,
      careerId: careerId ?? this.careerId,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  static String? _nullIfEmpty(Object? value) {
    final text = value?.toString().trim();
    return (text == null || text.isEmpty || text == 'null') ? null : text;
  }

  /// Acepta ISO 8601 (lo que escribe [toMap] y devuelve Supabase) y también
  /// epoch en milisegundos, que es como serializaba el modelo viejo de
  /// material docente y quedó así en la caché local de quienes ya lo usaron.
  static DateTime _parseDate(Object? raw) {
    if (raw == null) return DateTime.now();
    if (raw is num) return DateTime.fromMillisecondsSinceEpoch(raw.toInt());
    final text = raw.toString();
    final epoch = int.tryParse(text);
    if (epoch != null) return DateTime.fromMillisecondsSinceEpoch(epoch);
    return DateTime.tryParse(text) ?? DateTime.now();
  }

  IconData get fileIcon =>
      isLink ? Icons.link_rounded : iconForFileExtension(extensionOf(name));

  Color get fileColor =>
      isLink ? Colors.indigo : colorForFileExtension(extensionOf(name));

  String get formattedSize {
    final bytes = sizeBytes;
    if (bytes == null) return '';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}
