import 'package:flutter/material.dart';
import '../utils/file_type_icons.dart';

class StudyFile {
  final String? id;
  final String name;
  final String subject;
  final String driveFileId;
  final String mimeType;
  final int sizeBytes;
  final String driveLink;
  final String userId;
  final DateTime createdAt;

  StudyFile({
    this.id,
    required this.name,
    required this.subject,
    required this.driveFileId,
    required this.mimeType,
    required this.sizeBytes,
    required this.driveLink,
    required this.userId,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

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
      'created_at': createdAt.toIso8601String(),
    };
  }

  factory StudyFile.fromMap(Map<String, dynamic> map) {
    return StudyFile(
      id: map['id']?.toString(),
      name: map['name'] ?? '',
      subject: map['subject'] ?? '',
      driveFileId: map['drive_file_id'] ?? '',
      mimeType: map['mime_type'] ?? '',
      sizeBytes: map['size_bytes'] is int ? map['size_bytes'] : int.tryParse(map['size_bytes']?.toString() ?? '0') ?? 0,
      driveLink: map['drive_link'] ?? '',
      userId: map['user_id'] ?? '',
      createdAt: map['created_at'] != null
          ? DateTime.parse(map['created_at'])
          : DateTime.now(),
    );
  }

  IconData get fileIcon => iconForFileExtension(extensionOf(name));

  Color get fileColor => colorForFileExtension(extensionOf(name));

  String get formattedSize {
    if (sizeBytes < 1024) return '$sizeBytes B';
    if (sizeBytes < 1024 * 1024) return '${(sizeBytes / 1024).toStringAsFixed(1)} KB';
    return '${(sizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}
