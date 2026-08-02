import 'package:flutter/material.dart';
import '../utils/file_type_icons.dart';

/// Material que un profesor comparte con todo el curso: un archivo (subido a
/// Drive) o un enlace externo (Zoom grabado, YouTube, Drive de un tercero,
/// etc.). A diferencia de [StudyFile] (privado, solo el propio usuario lo
/// ve), esto es visible para todos los miembros de [careerId].
class TeachingMaterial {
  final String? id;
  final String careerId;
  final String subject;
  final String title;
  final String? description;
  final String type; // 'file' | 'link'
  final String? driveFileId;
  final String? driveLink;
  final String? externalUrl;
  final String? mimeType;
  final int? sizeBytes;
  final String userId;
  final String userName;
  final DateTime createdAt;

  TeachingMaterial({
    this.id,
    required this.careerId,
    required this.subject,
    required this.title,
    this.description,
    required this.type,
    this.driveFileId,
    this.driveLink,
    this.externalUrl,
    this.mimeType,
    this.sizeBytes,
    required this.userId,
    required this.userName,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  bool get isLink => type == 'link';
  bool get isFile => type == 'file';

  /// URL a abrir al tocar el material: el enlace externo si es tipo 'link',
  /// o el link de Drive si es un archivo.
  String get openUrl => isLink ? (externalUrl ?? '') : (driveLink ?? '');

  IconData get materialIcon =>
      isLink ? Icons.link_rounded : iconForFileExtension(extensionOf(title));

  Color get materialColor =>
      isLink ? Colors.indigo : colorForFileExtension(extensionOf(title));

  String get formattedSize {
    final bytes = sizeBytes;
    if (bytes == null) return '';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id ?? DateTime.now().millisecondsSinceEpoch.toString(),
      'career_id': careerId,
      'subject': subject,
      'title': title,
      'description': description,
      'type': type,
      'drive_file_id': driveFileId,
      'drive_link': driveLink,
      'external_url': externalUrl,
      'mime_type': mimeType,
      'size_bytes': sizeBytes,
      'user_id': userId,
      'user_name': userName,
      'created_at': createdAt.millisecondsSinceEpoch,
    };
  }

  factory TeachingMaterial.fromMap(Map<String, dynamic> map) {
    return TeachingMaterial(
      id: map['id']?.toString(),
      careerId: map['career_id']?.toString() ?? '',
      subject: map['subject']?.toString() ?? 'General',
      title: map['title']?.toString() ?? 'Sin título',
      description: map['description']?.toString(),
      type: map['type']?.toString() == 'link' ? 'link' : 'file',
      driveFileId: map['drive_file_id']?.toString(),
      driveLink: map['drive_link']?.toString(),
      externalUrl: map['external_url']?.toString(),
      mimeType: map['mime_type']?.toString(),
      sizeBytes: map['size_bytes'] is int
          ? map['size_bytes'] as int
          : int.tryParse(map['size_bytes']?.toString() ?? ''),
      userId: map['user_id']?.toString() ?? '',
      userName: map['user_name']?.toString() ?? 'Usuario',
      createdAt: map['created_at'] != null
          ? DateTime.fromMillisecondsSinceEpoch((map['created_at'] as num).toInt())
          : DateTime.now(),
    );
  }
}
