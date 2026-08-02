import 'dart:async';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz;
import 'models/meeting_model.dart';
import 'models/task_model.dart';
import 'utils/logger.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  // Claves de preferencias
  static const _key24h = 'notif_24h_enabled';
  static const _key2h = 'notif_2h_enabled';
  static const _keyMeetingReminder = 'notif_meeting_reminder_enabled';

  /// Convierte taskId a int de 32 bits estable.
  static int taskIdToNotificationId(String taskId) {
    if (taskId.isEmpty) return 1;
    final chars =
        taskId.length > 8 ? taskId.substring(taskId.length - 8) : taskId;
    int result = 0;
    for (int i = 0; i < chars.length; i++) {
      result = (result * 31 + chars.codeUnitAt(i)) & 0x7FFFFFFF;
    }
    return result == 0 ? 1 : result;
  }

  /// Convierte meetingId a un id de notificación distinto del de tareas
  /// (mismo hash, pero sobre un string con prefijo, para no chocar con
  /// taskIdToNotificationId).
  static int meetingIdToNotificationId(String meetingId) {
    return taskIdToNotificationId('meeting_$meetingId');
  }

  Future<void> initialize() async {
    if (_initialized) return;
    tz.initializeTimeZones();

    // Sin esto, el paquete `timezone` asume que la zona local es UTC y los
    // recordatorios terminan sonando varias horas antes/después de lo
    // esperado. Se detecta la zona real del dispositivo (ej. America/Santiago)
    // y se usa como referencia para tz.local en el resto del servicio.
    try {
      final deviceTimezone = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(deviceTimezone.identifier));
      Logger.info('Zona horaria detectada: ${deviceTimezone.identifier}', tag: 'Notif');
    } catch (e) {
      Logger.error(
        'No se pudo detectar la zona horaria del dispositivo, los recordatorios podrían programarse a la hora incorrecta',
        error: e,
        tag: 'Notif',
      );
    }

    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    const InitializationSettings initializationSettings =
        InitializationSettings(android: initializationSettingsAndroid);

    await _notifications.initialize(
      initializationSettings,
      onDidReceiveNotificationResponse: _onNotificationTapped,
    );

    _initialized = true;
  }

  void _onNotificationTapped(NotificationResponse response) {
    Logger.info('Notificación tocada: ${response.payload}', tag: 'Notif');
  }

  // ==================== PREFERENCIAS ====================

  Future<bool> get is24hEnabled async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_key24h) ?? true;
  }

  Future<bool> get is2hEnabled async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_key2h) ?? true;
  }

  Future<void> set24hEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key24h, value);
  }

  Future<void> set2hEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key2h, value);
  }

  Future<bool> get isMeetingReminderEnabled async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyMeetingReminder) ?? true;
  }

  Future<void> setMeetingReminderEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyMeetingReminder, value);
  }

  // ==================== RECORDATORIOS INTELIGENTES ====================

  /// Programa recordatorios inteligentes para una tarea (24h y/o 2h antes),
  /// según las preferencias del usuario.
  Future<void> scheduleTaskReminders(Task task) async {
    if (task.id == null) return;
    final baseId = taskIdToNotificationId(task.id!);

    final enabled24h = await is24hEnabled;
    final enabled2h = await is2hEnabled;

    if (enabled24h) {
      await _scheduleReminder(
        id: baseId,
        title: '📚 Tarea mañana',
        body: '${task.title} — ${task.subject} vence en 24 horas',
        scheduledTime: task.dueDate.subtract(const Duration(hours: 24)),
      );
    }

    if (enabled2h) {
      // Usar baseId + 1000000 para el recordatorio de 2h (evitar colisiones)
      await _scheduleReminder(
        id: baseId + 1000000,
        title: '⚠️ Tarea en 2 horas',
        body: '${task.title} — ${task.subject} vence muy pronto',
        scheduledTime: task.dueDate.subtract(const Duration(hours: 2)),
      );
    }
  }

  Future<void> _scheduleReminder({
    required int id,
    required String title,
    required String body,
    required DateTime scheduledTime,
  }) async {
    if (scheduledTime.isBefore(DateTime.now())) return;

    try {
      await _notifications.zonedSchedule(
        id,
        title,
        body,
        tz.TZDateTime.from(scheduledTime, tz.local),
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'task_smart_reminders',
            'Recordatorios Inteligentes',
            channelDescription:
                'Alertas 24h y 2h antes del vencimiento de tareas',
            importance: Importance.high,
            priority: Priority.high,
          ),
        ),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
      );
      Logger.info('Recordatorio programado: $title a las $scheduledTime',
          tag: 'Notif');
    } catch (e) {
      Logger.error('Error al programar recordatorio', error: e, tag: 'Notif');
      // Fallback inexacto
      try {
        await _notifications.zonedSchedule(
          id,
          title,
          body,
          tz.TZDateTime.from(scheduledTime, tz.local),
          const NotificationDetails(
            android: AndroidNotificationDetails(
              'task_smart_reminders',
              'Recordatorios Inteligentes',
              channelDescription:
                  'Alertas 24h y 2h antes del vencimiento de tareas',
              importance: Importance.high,
              priority: Priority.high,
            ),
          ),
          androidScheduleMode: AndroidScheduleMode.inexact,
          uiLocalNotificationDateInterpretation:
              UILocalNotificationDateInterpretation.absoluteTime,
        );
      } catch (e2) {
        Logger.error('Fallback también falló', error: e2, tag: 'Notif');
      }
    }
  }

  /// Cancela los recordatorios de una tarea específica
  Future<void> cancelTaskReminders(String taskId) async {
    final baseId = taskIdToNotificationId(taskId);
    await _notifications.cancel(baseId);
    await _notifications.cancel(baseId + 1000000);
  }

  // ==================== RECORDATORIO DE REUNIONES ====================

  /// Programa un recordatorio 30 minutos antes de una reunión, si la
  /// preferencia está activada. Cancela cualquier recordatorio previo de
  /// la misma reunión primero (para que reprogramar por una edición no
  /// duplique avisos).
  Future<void> scheduleMeetingReminder(Meeting meeting) async {
    if (meeting.id == null) return;
    await cancelMeetingReminder(meeting.id!);

    if (!await isMeetingReminderEnabled) return;

    await _scheduleReminder(
      id: meetingIdToNotificationId(meeting.id!),
      title: '📹 Reunión en 30 minutos',
      body: '${meeting.title} — ${meeting.subject}',
      scheduledTime: meeting.meetingDate.subtract(const Duration(minutes: 30)),
    );
  }

  /// Cancela el recordatorio de una reunión específica.
  Future<void> cancelMeetingReminder(String meetingId) async {
    await _notifications.cancel(meetingIdToNotificationId(meetingId));
  }

  /// Sincroniza todas las notificaciones locales con la lista actual de tareas
  Future<void> syncAllTaskReminders(List<Task> tasks) async {
    try {
      for (final task in tasks) {
        if (task.id == null) continue;
        final isDelivered = task.isCompleted && task.isSubmitted;
        final isFuture = task.dueDate.isAfter(DateTime.now());

        if (!isDelivered && isFuture) {
          await scheduleTaskReminders(task);
        } else {
          await cancelTaskReminders(task.id!);
        }
      }
      Logger.info('Sincronizados recordatorios locales para ${tasks.length} tareas', tag: 'Notif');
    } catch (e) {
      Logger.error('Error sincronizando recordatorios de tareas: $e', tag: 'Notif');
    }
  }

  // ==================== RECORDATORIO DIARIO ====================

  Future<void> scheduleDailyReminder() async {
    try {
      await _notifications.zonedSchedule(
        0,
        'Recordatorio de Tareas',
        'Revisa tus tareas pendientes para hoy',
        _nextInstanceOf8AM(),
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'daily_reminder_channel',
            'Recordatorios Diarios',
            channelDescription: 'Recordatorio diario de tareas',
            importance: Importance.high,
            priority: Priority.high,
          ),
        ),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        matchDateTimeComponents: DateTimeComponents.time,
      );
    } catch (e) {
      Logger.error('Error recordatorio diario', error: e, tag: 'Notif');
      try {
        await _notifications.zonedSchedule(
          0,
          'Recordatorio de Tareas',
          'Revisa tus tareas pendientes para hoy',
          _nextInstanceOf8AM(),
          const NotificationDetails(
            android: AndroidNotificationDetails(
              'daily_reminder_channel',
              'Recordatorios Diarios',
              channelDescription: 'Recordatorio diario de tareas',
              importance: Importance.high,
              priority: Priority.high,
            ),
          ),
          androidScheduleMode: AndroidScheduleMode.inexact,
          uiLocalNotificationDateInterpretation:
              UILocalNotificationDateInterpretation.absoluteTime,
          matchDateTimeComponents: DateTimeComponents.time,
        );
      } catch (e2) {
        Logger.error('Fallback diario también falló', error: e2, tag: 'Notif');
      }
    }
  }

  tz.TZDateTime _nextInstanceOf8AM() {
    final tz.TZDateTime now = tz.TZDateTime.now(tz.local);
    tz.TZDateTime scheduledDate =
        tz.TZDateTime(tz.local, now.year, now.month, now.day, 8, 0);
    if (scheduledDate.isBefore(now)) {
      scheduledDate = scheduledDate.add(const Duration(days: 1));
    }
    return scheduledDate;
  }

  Future<void> cancelNotification(int id) async {
    await _notifications.cancel(id);
  }

  Future<void> cancelAllNotifications() async {
    await _notifications.cancelAll();
  }

  Future<void> showImmediateNotification(
      String title, String description) async {
    await _notifications.show(
      DateTime.now().millisecondsSinceEpoch.remainder(100000),
      title,
      description,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'immediate_channel',
          'Notificaciones Inmediatas',
          channelDescription: 'Notificaciones inmediatas de la app',
          importance: Importance.high,
          priority: Priority.high,
        ),
      ),
    );
  }
}
