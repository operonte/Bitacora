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

  /// Privada (solo la ve quien la creó) o compartida con los miembros de
  /// [careerId]. Compartir es explícito: por defecto es privada para no
  /// publicar algo personal al grupo sin querer. Una reunión compartida
  /// siempre necesita carrera, si no no tendría con quién compartirse.
  final bool isPrivate;
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
    this.isPrivate = true,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  /// Hora a la que una reunión recurrente deja de contar como "la de hoy" y
  /// pasa a mostrarse como la de la semana siguiente. Sin esto el salto
  /// ocurría apenas terminaba la hora de la reunión, y una reunión del
  /// miércoles a las 10:00 desaparecía del tope de la lista a las 10:01 del
  /// mismo miércoles.
  static const int rolloverHour = 23;

  /// Para reuniones semanales cuya fecha guardada ya pasó, calcula la
  /// próxima ocurrencia (mismo día de la semana y hora, N semanas después).
  /// Las no recurrentes o aún futuras devuelven [meetingDate] tal cual.
  DateTime get effectiveDate {
    if (!isRecurrent) return meetingDate;
    var next = meetingDate;
    final now = DateTime.now();
    while (!_stillCurrent(next, now)) {
      next = next.add(const Duration(days: 7));
    }
    return next;
  }

  /// Una ocurrencia sigue siendo la vigente hasta [rolloverHour] de su propio
  /// día, aunque su hora ya haya pasado.
  static bool _stillCurrent(DateTime occurrence, DateTime now) {
    final rollover = DateTime(
      occurrence.year,
      occurrence.month,
      occurrence.day,
      rolloverHour,
    );
    return now.isBefore(rollover);
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
      // .toUtc() explícito: la columna es timestamptz, y sin marca de huso
      // Postgres interpreta la hora local tal cual como si fuera UTC —
      // 19:00 en Chile quedaba guardado como 19:00 UTC (15:00 Chile real).
      'meeting_date': meetingDate.toUtc().toIso8601String(),
      'type': effectiveType,
      'is_recurrent': isRecurrent,
      'user_id': userId,
      'is_completed': isCompleted,
      'is_private': isPrivate,
      'created_at': createdAt.toUtc().toIso8601String(),
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
      // .toLocal(): Supabase devuelve timestamptz con offset explícito
      // (correcto), pero el resto de la app —_hhmm, _formatMeetingDate,
      // effectiveDate, occurrenceOn— lee .hour/.day directo asumiendo hora
      // local, igual que antes de que existiera este bug.
      meetingDate: map['meeting_date'] != null
          ? DateTime.parse(map['meeting_date']).toLocal()
          : DateTime.now(),
      type: map['type'] ?? 'Zoom',
      isRecurrent: map['is_recurrent'] ?? false,
      meetingLink: map['meeting_link']?.toString().isEmpty ?? true
          ? null
          : map['meeting_link'],
      careerId: map['career_id']?.toString(),
      userId: map['user_id'] ?? '',
      isCompleted: map['is_completed'] ?? false,
      // Ausente en filas viejas (previas a la migración): se asume privada,
      // que es como se comportaban antes de existir esta opción.
      isPrivate: map['is_private'] ?? true,
      createdAt: map['created_at'] != null
          ? DateTime.parse(map['created_at']).toLocal()
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
    bool? isPrivate,
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
      isPrivate: isPrivate ?? this.isPrivate,
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
