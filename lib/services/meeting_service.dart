import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/meeting_model.dart';
import '../utils/logger.dart';
import '../notification_service.dart';
import 'career_service.dart';

class MeetingService extends ChangeNotifier {
  static final MeetingService _instance = MeetingService._internal();
  factory MeetingService() => _instance;
  MeetingService._internal();

  static const String _boxName = 'meetings_box';

  /// Cuánto sobrevive una reunión puntual después de su fecha antes de que
  /// [purgePastMeetings] la borre. Margen para poder consultarla al día
  /// siguiente; súbelo o bájalo acá.
  static const Duration pastMeetingRetention = Duration(days: 7);

  /// Valor de [Meeting.careerId] que representa "sin carrera" en el filtro.
  static const String noCareerFilter = '__sin_carrera__';

  Box? _meetingBox;

  Future<void> init() async {
    try {
      _meetingBox = await Hive.openBox(_boxName);
      Logger.info('MeetingService inicializado', tag: 'MeetingService');
    } catch (e) {
      Logger.error('Error inicializando MeetingService: $e', error: e, tag: 'MeetingService');
    }
  }

  /// Reuniones en caché, más próxima primero.
  ///
  /// [careerId] filtra por carrera: null trae todas, [noCareerFilter] trae
  /// solo las que no tienen carrera asignada.
  List<Meeting> getMeetings({String? careerId}) {
    if (_meetingBox == null) return [];
    try {
      final raw = _meetingBox!.values.toList();
      final meetings = raw
          .map((e) {
            if (e is Map) {
              return Meeting.fromMap(Map<String, dynamic>.from(e));
            }
            return null;
          })
          .whereType<Meeting>()
          // Nunca mostrar reuniones de carreras a las que el usuario ya no
          // pertenece: al salir de una carrera su caché local sobrevive, y
          // sin esto seguían apareciendo agrupadas bajo el id crudo de una
          // carrera que ni siquiera se puede resolver a un nombre. Es el
          // mismo criterio que ya se aplicaba a las tareas.
          .where((m) => CareerService().matchesAnyCareer(m.careerId))
          .where((m) {
            if (careerId == null) return true;
            final id = m.careerId;
            if (careerId == noCareerFilter) return id == null || id.isEmpty;
            return id == careerId;
          })
          .toList();

      meetings.sort((a, b) => a.effectiveDate.compareTo(b.effectiveDate));
      return meetings;
    } catch (e) {
      Logger.error('Error parseando reuniones: $e', tag: 'MeetingService');
      return [];
    }
  }

  /// Marca, dentro del mapa guardado en Hive, de que esta reunión todavía no
  /// llegó a Supabase. No es parte de [Meeting]: `fromMap` la ignora.
  static const String _pendingKey = '_pending';

  /// Reuniones guardadas localmente que nunca llegaron al servidor.
  List<Meeting> _pendingMeetings() {
    if (_meetingBox == null) return [];
    return _meetingBox!.values
        .whereType<Map>()
        .where((m) => m[_pendingKey] == true)
        .map((m) => Meeting.fromMap(Map<String, dynamic>.from(m)))
        .toList();
  }

  /// Carreras que aparecen entre las reuniones guardadas, para armar el
  /// filtro sin ofrecer opciones que no seleccionarían nada.
  Set<String> get usedCareerIds => getMeetings()
      .map((m) => (m.careerId == null || m.careerId!.isEmpty)
          ? noCareerFilter
          : m.careerId!)
      .toSet();

  /// Borra las reuniones puntuales que llevan más de [pastMeetingRetention]
  /// vencidas. Las recurrentes nunca entran acá: su [Meeting.effectiveDate]
  /// avanza sola a la próxima semana, así que siempre está en el futuro.
  ///
  /// Es irreversible y no hay papelera, por eso cada borrado se registra.
  Future<int> purgePastMeetings() async {
    if (_meetingBox == null) return 0;

    final cutoff = DateTime.now().subtract(pastMeetingRetention);
    final expired = getMeetings()
        .where((m) => !m.isRecurrent && m.effectiveDate.isBefore(cutoff))
        .toList();

    var deleted = 0;
    for (final meeting in expired) {
      final id = meeting.id;
      if (id == null || id.isEmpty) continue;
      try {
        await deleteMeeting(id);
        Logger.info(
          'Reunión vencida eliminada: "${meeting.title}" del ${meeting.effectiveDate}',
          tag: 'MeetingService',
        );
        deleted++;
      } catch (e) {
        Logger.warning('No se pudo eliminar la reunión vencida "${meeting.title}": $e', tag: 'MeetingService');
      }
    }

    if (deleted > 0) notifyListeners();
    return deleted;
  }

  /// Vacía la caché local de reuniones. Igual que con los archivos, la caja
  /// sobrevive al cierre de sesión y sin esto la cuenta siguiente vería las
  /// reuniones de la anterior hasta la primera sincronización.
  Future<void> clearCache() async {
    await _meetingBox?.clear();
    notifyListeners();
  }

  Future<void> saveMeeting(Meeting meeting) async {
    final user = Supabase.instance.client.auth.currentUser;
    final isNew = meeting.id == null || meeting.id!.isEmpty;
    final meetingId = meeting.id ?? DateTime.now().millisecondsSinceEpoch.toString();
    final meetingToSave = meeting.copyWith(
      id: meetingId,
      userId: user?.id ?? meeting.userId,
    );

    // Si el servidor no la acepta queda marcada para reintentarla en la
    // próxima sincronización. Ver [_pendingKey].
    var pendiente = user == null;
    if (user != null) {
      try {
        final payload = meetingToSave.toMap();
        payload['user_id'] = user.id;

        if (isNew) {
          await Supabase.instance.client
              .from('meetings')
              .insert(payload);
        } else {
          await Supabase.instance.client
              .from('meetings')
              .update(payload)
              .eq('id', meetingId);
        }
      } catch (e) {
        pendiente = true;
        Logger.error('Error guardando reunión en Supabase: $e', error: e, tag: 'MeetingService');
        rethrow;
      }
    }

    await _meetingBox?.put(meetingId, {
      ...meetingToSave.toMap(),
      if (pendiente) _pendingKey: true,
    });

    // Se resincroniza la lista completa, no solo esta reunión: el resumen
    // diario cuenta cuántas hay cada día, así que agregar una obliga a
    // recalcularlo igual.
    try {
      await NotificationService().syncAllMeetingReminders(getMeetings());
    } catch (e) {
      Logger.warning('No se pudo programar el recordatorio de la reunión: $e', tag: 'MeetingService');
    }

    notifyListeners();
  }

  Future<void> deleteMeeting(String meetingId) async {
    await _meetingBox?.delete(meetingId);
    await NotificationService().cancelMeetingReminder(meetingId);
    await NotificationService().syncAllMeetingReminders(getMeetings());

    final user = Supabase.instance.client.auth.currentUser;
    if (user != null) {
      try {
        await Supabase.instance.client
            .from('meetings')
            .delete()
            .eq('id', meetingId);
      } catch (e) {
        Logger.warning('No se pudo borrar reunión remota: $e', tag: 'MeetingService');
      }
    }
    notifyListeners();
  }

  Future<void> syncFromSupabase() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;
    try {
      // 1. Subir SOLO las reuniones que nunca llegaron al servidor.
      //
      // Antes se reenviaba toda la caché propia en cada sincronización, y eso
      // resucitaba lo borrado: al eliminar una reunión en un dispositivo
      // desaparecía de Supabase, pero la caché del otro todavía la tenía y en
      // su siguiente sincronización la volvía a insertar. El servidor manda;
      // la caché solo aporta lo que se creó sin conexión.
      //
      // Se excluyen además las ajenas: reenviarlas con
      // payload['user_id'] = user.id se las robaría a su dueño (y la RLS de
      // update las rechazaría igual).
      final localMeetings = _pendingMeetings()
          .where((m) => m.userId.isEmpty || m.userId == user.id)
          .toList();
      for (final m in localMeetings) {
        if (m.id == null) continue;
        try {
          final payload = m.toMap();
          payload['user_id'] = user.id;
          try {
            await Supabase.instance.client
                .from('meetings')
                .insert(payload);
          } catch (_) {
            await Supabase.instance.client
                .from('meetings')
                .update(payload)
                .eq('id', m.id!);
          }
        } catch (err) {
          Logger.warning('No se pudo respaldar reunión local en Supabase: $err', tag: 'MeetingService');
        }
      }

      // 2. Traer la lista oficial desde Supabase y hacer un MERGE seguro.
      //
      // Sin filtro por user_id a propósito: la política RLS meetings_select
      // ya decide qué puede ver este usuario (las suyas + las compartidas de
      // las carreras a las que pertenece). Filtrar acá por user_id volvería
      // a dejar fuera las reuniones que otros compartieron con su carrera.
      final List<dynamic> response =
          await Supabase.instance.client.from('meetings').select();

      final remoteIds = <String>{};
      for (final item in response) {
        if (item is Map) {
          final m = Meeting.fromMap(Map<String, dynamic>.from(item));
          if (m.id != null) {
            remoteIds.add(m.id!);
            await _meetingBox?.put(m.id, m.toMap());
          }
        }
      }

      // Una reunión compartida que su dueño volvió privada (o borró) sigue
      // en la caché local de los demás miembros: ya no viene en la respuesta,
      // así que hay que sacarla. Solo se purgan las ajenas — las propias
      // pueden ser locales aún no subidas.
      final staleShared = getMeetings()
          .where((m) =>
              m.id != null &&
              m.userId.isNotEmpty &&
              m.userId != user.id &&
              !remoteIds.contains(m.id))
          .toList();
      for (final m in staleShared) {
        await _meetingBox?.delete(m.id);
        await NotificationService().cancelMeetingReminder(m.id!);
      }

      // Los recordatorios locales son por dispositivo: si esta reunión se
      // creó en otro teléfono, este no la tenía programada hasta ahora.
      await NotificationService().syncAllMeetingReminders(getMeetings());

      notifyListeners();
    } catch (e) {
      Logger.warning('Falló sincronización de reuniones: $e', tag: 'MeetingService');
    }
  }
}
