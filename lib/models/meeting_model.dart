import 'package:flutter/material.dart';

class Meeting {
  final String? id;
  final String title;
  final String description;
  final String subject;
  final String professor;
  final DateTime meetingDate;
  final String type; // Zoom, Google Meet, Microsoft Teams, Presencial, Otro
  final bool isRecurrent; // Semanal
  final String? meetingLink;
  final String? careerId;
  final String userId;
  final bool isCompleted;
  final DateTime createdAt;

  Meeting({
    this.id,
    required this.title,
    this.description = '',
    required this.subject,
    required this.professor,
    required this.meetingDate,
    required this.type,
    this.isRecurrent = false,
    this.meetingLink,
    this.careerId,
    required this.userId,
    this.isCompleted = false,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  /// Para reuniones semanales cuya fecha guardada ya pasó, calcula la
  /// próxima ocurrencia (mismo día de la semana y hora, N semanas después).
  /// Las no recurrentes o aún futuras devuelven [meetingDate] tal cual.
  DateTime get effectiveDate {
    if (!isRecurrent) return meetingDate;
    var next = meetingDate;
    final now = DateTime.now();
    while (!next.isAfter(now)) {
      next = next.add(const Duration(days: 7));
    }
    return next;
  }

  /// Detecta automáticamente el tipo efectivo basado en el enlace si existe
  String get effectiveType {
    if (meetingLink != null && meetingLink!.isNotEmpty) {
      final lower = meetingLink!.toLowerCase();
      if (lower.contains('zoom.us') || lower.contains('zoom.com')) return 'Zoom';
      if (lower.contains('meet.google.com')) return 'Google Meet';
      if (lower.contains('teams.microsoft.com') || lower.contains('teams.live.com')) return 'Microsoft Teams';
    }
    return type;
  }

  Map<String, dynamic> toMap() {
    final map = <String, dynamic>{
      'id': id ?? DateTime.now().millisecondsSinceEpoch.toString(),
      'title': title,
      'description': description,
      'subject': subject,
      'professor': professor,
      'meeting_date': meetingDate.toIso8601String(),
      'type': effectiveType,
      'is_recurrent': isRecurrent,
      'user_id': userId,
      'is_completed': isCompleted,
      'created_at': createdAt.toIso8601String(),
    };

    if (meetingLink != null && meetingLink!.isNotEmpty) {
      map['meeting_link'] = meetingLink;
    }
    if (careerId != null && careerId!.isNotEmpty) {
      map['career_id'] = careerId;
    }
    return map;
  }

  factory Meeting.fromMap(Map<String, dynamic> map) {
    return Meeting(
      id: map['id']?.toString(),
      title: map['title'] ?? '',
      description: map['description'] ?? '',
      subject: map['subject'] ?? '',
      professor: map['professor'] ?? '',
      meetingDate: map['meeting_date'] != null
          ? DateTime.parse(map['meeting_date'])
          : DateTime.now(),
      type: map['type'] ?? 'Zoom',
      isRecurrent: map['is_recurrent'] ?? false,
      meetingLink: map['meeting_link']?.toString().isEmpty ?? true
          ? null
          : map['meeting_link'],
      careerId: map['career_id']?.toString(),
      userId: map['user_id'] ?? '',
      isCompleted: map['is_completed'] ?? false,
      createdAt: map['created_at'] != null
          ? DateTime.parse(map['created_at'])
          : DateTime.now(),
    );
  }

  Meeting copyWith({
    String? id,
    String? title,
    String? description,
    String? subject,
    String? professor,
    DateTime? meetingDate,
    String? type,
    bool? isRecurrent,
    String? meetingLink,
    String? careerId,
    String? userId,
    bool? isCompleted,
    DateTime? createdAt,
  }) {
    return Meeting(
      id: id ?? this.id,
      title: title ?? this.title,
      description: description ?? this.description,
      subject: subject ?? this.subject,
      professor: professor ?? this.professor,
      meetingDate: meetingDate ?? this.meetingDate,
      type: type ?? this.type,
      isRecurrent: isRecurrent ?? this.isRecurrent,
      meetingLink: meetingLink ?? this.meetingLink,
      careerId: careerId ?? this.careerId,
      userId: userId ?? this.userId,
      isCompleted: isCompleted ?? this.isCompleted,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  IconData get typeIcon {
    switch (effectiveType.toLowerCase()) {
      case 'zoom':
        return Icons.video_call;
      case 'meet':
      case 'google meet':
        return Icons.videocam;
      case 'teams':
      case 'microsoft teams':
        return Icons.groups;
      case 'presencial':
        return Icons.location_on;
      default:
        return Icons.event;
    }
  }
}
