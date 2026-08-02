import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/meeting_model.dart';
import '../utils/logger.dart';
import '../notification_service.dart';
import 'supabase_db_service.dart';

class MeetingService extends ChangeNotifier {
  static final MeetingService _instance = MeetingService._internal();
  factory MeetingService() => _instance;
  MeetingService._internal();

  static const String _boxName = 'meetings_box';
  Box? _meetingBox;

  Future<void> init() async {
    try {
      _meetingBox = await Hive.openBox(_boxName);
      Logger.info('MeetingService inicializado', tag: 'MeetingService');
    } catch (e) {
      Logger.error('Error inicializando MeetingService: $e', error: e, tag: 'MeetingService');
    }
  }

  List<Meeting> getMeetings() {
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
          .toList();

      meetings.sort((a, b) => a.meetingDate.compareTo(b.meetingDate));
      return meetings;
    } catch (e) {
      Logger.error('Error parseando reuniones: $e', tag: 'MeetingService');
      return [];
    }
  }

  Future<void> saveMeeting(Meeting meeting) async {
    final user = Supabase.instance.client.auth.currentUser;
    final isNew = meeting.id == null || meeting.id!.isEmpty;
    final meetingId = meeting.id ?? DateTime.now().millisecondsSinceEpoch.toString();
    final meetingToSave = meeting.copyWith(
      id: meetingId,
      userId: user?.id ?? meeting.userId,
    );

    if (user != null) {
      try {
        await SupabaseDbService().registerCareerMemberships();

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
        Logger.error('Error guardando reunión en Supabase: $e', error: e, tag: 'MeetingService');
        rethrow;
      }
    }

    await _meetingBox?.put(meetingId, meetingToSave.toMap());

    try {
      await NotificationService().scheduleMeetingReminder(meetingToSave);
    } catch (e) {
      Logger.warning('No se pudo programar el recordatorio de la reunión: $e', tag: 'MeetingService');
    }

    notifyListeners();
  }

  Future<void> deleteMeeting(String meetingId) async {
    await _meetingBox?.delete(meetingId);
    await NotificationService().cancelMeetingReminder(meetingId);

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
      await SupabaseDbService().registerCareerMemberships();

      // 1. Subir o actualizar todas las reuniones locales a Supabase
      final localMeetings = getMeetings();
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

      // 2. Traer la lista oficial desde Supabase y hacer un MERGE seguro
      final List<dynamic> response = await Supabase.instance.client
          .from('meetings')
          .select()
          .eq('user_id', user.id);

      for (final item in response) {
        if (item is Map) {
          final m = Meeting.fromMap(Map<String, dynamic>.from(item));
          if (m.id != null) {
            await _meetingBox?.put(m.id, m.toMap());
          }
        }
      }

      // Los recordatorios locales son por dispositivo: si esta reunión se
      // creó en otro teléfono, este no la tenía programada hasta ahora.
      await _resyncAllReminders();

      notifyListeners();
    } catch (e) {
      Logger.warning('Falló sincronización de reuniones: $e', tag: 'MeetingService');
    }
  }

  /// Reprograma el recordatorio de toda reunión futura y cancela el de las
  /// que ya pasaron, para el dispositivo actual.
  Future<void> _resyncAllReminders() async {
    for (final meeting in getMeetings()) {
      if (meeting.id == null) continue;
      try {
        if (meeting.meetingDate.isAfter(DateTime.now())) {
          await NotificationService().scheduleMeetingReminder(meeting);
        } else {
          await NotificationService().cancelMeetingReminder(meeting.id!);
        }
      } catch (e) {
        Logger.warning('No se pudo reprogramar recordatorio de ${meeting.id}: $e', tag: 'MeetingService');
      }
    }
  }
}
