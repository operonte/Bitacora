/// Anuncio de un docente para su carrera (o una asignatura puntual dentro de
/// ella). Sin caché local a propósito: se lee siempre de Supabase — la
/// pantalla que lo usa se abre poco y necesita conexión igual para publicar.
class Announcement {
  final String? id;
  final String careerId;

  /// Null = para toda la carrera. Con valor, es solo de esa asignatura.
  final String? subject;
  final String title;
  final String body;
  final bool urgent;
  final String createdBy;
  final String createdByName;
  final DateTime createdAt;

  Announcement({
    this.id,
    required this.careerId,
    this.subject,
    required this.title,
    this.body = '',
    this.urgent = false,
    required this.createdBy,
    required this.createdByName,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toInsertRow() {
    final map = <String, dynamic>{
      'career_id': careerId,
      'title': title,
      'body': body,
      'urgent': urgent,
      'created_by': createdBy,
      'created_by_name': createdByName,
    };
    if (subject != null && subject!.isNotEmpty) map['subject'] = subject;
    return map;
  }

  factory Announcement.fromMap(Map<String, dynamic> map) => Announcement(
        id: map['id']?.toString(),
        careerId: map['career_id']?.toString() ?? '',
        subject: (map['subject'] as String?)?.trim().isEmpty ?? true
            ? null
            : map['subject'] as String,
        title: map['title']?.toString() ?? '',
        body: map['body']?.toString() ?? '',
        urgent: map['urgent'] == true,
        createdBy: map['created_by']?.toString() ?? '',
        createdByName: map['created_by_name']?.toString() ?? 'Docente',
        createdAt: map['created_at'] != null
            ? DateTime.parse(map['created_at'].toString()).toLocal()
            : DateTime.now(),
      );
}
