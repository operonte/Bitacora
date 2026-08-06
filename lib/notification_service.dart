import 'dart:async';
import 'package:android_intent_plus/android_intent.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:permission_handler/permission_handler.dart';
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

  // Canal usado por los recordatorios de tareas/reuniones (24h, 2h, mañana
  // de la reunión). Android trata cada canal como un interruptor
  // independiente del permiso general: el usuario puede haberlo silenciado
  // sin tocar el permiso de notificaciones. Debe coincidir exactamente con
  // el id usado en _scheduleReminder más abajo.
  static const taskReminderChannelId = 'task_smart_reminders';
  static const _packageName = 'com.operonte.bitacora';

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

    // Desde Android 14, SCHEDULE_EXACT_ALARM viene denegado por defecto para
    // apps que no son de alarma/calendario — Bitácora no lo es, así que no
    // hay que asumirlo concedido solo porque está en el manifest. Se
    // confirma en runtime ANTES de pedir el modo exacto, en vez de
    // intentarlo a ciegas y recién reaccionar si el sistema lo rechaza
    // (recomendación oficial: developer.android.com/about/versions/14/
    // changes/schedule-exact-alarms).
    //
    // OJO: AndroidScheduleMode.alarmClock (setAlarmClock, lo que usa una app
    // Reloj real) NO es la alternativa acá — el plugin lanza una
    // SecurityException nativa sin try/catch cuando el permiso no está
    // realmente concedido, y eso tronaba la app entera sin que ningún catch
    // de Dart pudiera atraparlo (github.com/MaikuB/flutter_local_notifications/
    // issues/2248). Para una app de recordatorios de tareas (no un reloj de
    // alarma), exactAllowWhileIdle con este chequeo previo es el patrón
    // correcto.
    final canBeExact = await Permission.scheduleExactAlarm.isGranted;
    final mode = canBeExact
        ? AndroidScheduleMode.exactAllowWhileIdle
        : AndroidScheduleMode.inexact;

    try {
      await _notifications.zonedSchedule(
        id,
        title,
        body,
        tz.TZDateTime.from(scheduledTime, tz.local),
        const NotificationDetails(
          android: AndroidNotificationDetails(
            taskReminderChannelId,
            'Recordatorios Inteligentes',
            channelDescription:
                'Alertas 24h y 2h antes del vencimiento de tareas',
            importance: Importance.high,
            priority: Priority.high,
          ),
        ),
        androidScheduleMode: mode,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
      );
      Logger.info('Recordatorio programado ($mode): $title a las $scheduledTime',
          tag: 'Notif');
    } catch (e) {
      Logger.error('Error al programar recordatorio', error: e, tag: 'Notif');
      if (mode == AndroidScheduleMode.inexact) return;

      // El intento exacto falló de forma inesperada pese al chequeo previo:
      // último recurso, inexacto.
      try {
        await _notifications.zonedSchedule(
          id,
          title,
          body,
          tz.TZDateTime.from(scheduledTime, tz.local),
          const NotificationDetails(
            android: AndroidNotificationDetails(
              taskReminderChannelId,
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

  /// Programa dos recordatorios para una reunión, igual que para tareas
  /// (mañana del día + 2 horas antes), si la preferencia está activada.
  /// Cancela cualquier recordatorio previo de la misma reunión primero
  /// (para que reprogramar por una edición no duplique avisos).
  Future<void> scheduleMeetingReminder(Meeting meeting) async {
    if (meeting.id == null) return;
    await cancelMeetingReminder(meeting.id!);

    if (!await isMeetingReminderEnabled) return;

    final baseId = meetingIdToNotificationId(meeting.id!);
    final date = meeting.effectiveDate;
    final time = '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';

    // Aviso la mañana del mismo día de la reunión (8:00 am).
    final morningOf = DateTime(date.year, date.month, date.day, 8, 0);
    if (morningOf.isBefore(date)) {
      await _scheduleReminder(
        id: baseId,
        title: '📹 Reunión hoy',
        body: '${meeting.title} — ${meeting.subject} a las $time',
        scheduledTime: morningOf,
      );
    }

    // Aviso 2 horas antes.
    await _scheduleReminder(
      id: baseId + 1000000,
      title: '📹 Reunión en 2 horas',
      body: '${meeting.title} — ${meeting.subject}',
      scheduledTime: date.subtract(const Duration(hours: 2)),
    );
  }

  /// Cancela los recordatorios de una reunión específica.
  Future<void> cancelMeetingReminder(String meetingId) async {
    final baseId = meetingIdToNotificationId(meetingId);
    await _notifications.cancel(baseId);
    await _notifications.cancel(baseId + 1000000);
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
    final canBeExact = await Permission.scheduleExactAlarm.isGranted;
    if (!canBeExact) {
      await _scheduleDailyReminderInexact();
      return;
    }

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
      await _scheduleDailyReminderInexact();
    }
  }

  Future<void> _scheduleDailyReminderInexact() async {
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
    } catch (e) {
      Logger.error('Fallback diario también falló', error: e, tag: 'Notif');
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

  /// Indica si el canal de recordatorios de tareas está silenciado a nivel
  /// de sistema. El permiso general de notificaciones puede estar concedido
  /// y aun así este canal puntual estar apagado — Android los trata como
  /// interruptores independientes. Si el canal todavía no fue creado (nunca
  /// se programó un recordatorio), no hay nada que revisar todavía.
  Future<bool> isTaskReminderChannelBlocked() async {
    final androidPlugin = _notifications.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (androidPlugin == null) return false;
    final channels = await androidPlugin.getNotificationChannels();
    if (channels == null) return false;
    for (final channel in channels) {
      if (channel.id == taskReminderChannelId) {
        return channel.importance == Importance.none;
      }
    }
    return false;
  }

  /// Abre directamente la pantalla de Ajustes de Android para el canal de
  /// recordatorios de tareas — no la pantalla general de la app. Así el
  /// usuario no tiene que encontrar el canal correcto a mano entre varios.
  Future<void> openTaskReminderChannelSettings() async {
    const intent = AndroidIntent(
      action: 'android.settings.CHANNEL_NOTIFICATION_SETTINGS',
      arguments: {
        'android.provider.extra.APP_PACKAGE': _packageName,
        'android.provider.extra.CHANNEL_ID': taskReminderChannelId,
      },
    );
    await intent.launch();
  }

  /// Diagnóstico: programa una notificación real a 1 minuto, por el mismo
  /// camino (zonedSchedule) que usan los recordatorios de tareas/reuniones.
  /// A diferencia de [showImmediateNotification], esto sirve para aislar si
  /// el problema está en la entrega inmediata o en la alarma programada.
  Future<void> scheduleTestNotification() async {
    await _scheduleReminder(
      id: 2100000000,
      title: '⏱️ Notificación programada de prueba',
      body: 'Si ves esto, la programación de alarmas funciona correctamente.',
      scheduledTime: DateTime.now().add(const Duration(minutes: 1)),
    );
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
