import 'dart:async';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz;

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _notifications = FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) return;

    tz.initializeTimeZones();

    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    const InitializationSettings initializationSettings = InitializationSettings(
      android: initializationSettingsAndroid,
    );

    await _notifications.initialize(
      initializationSettings,
      onDidReceiveNotificationResponse: _onNotificationTapped,
    );

    _initialized = true;
  }

  void _onNotificationTapped(NotificationResponse response) {
    // Manejar tap en notificación
    print('Notificación tocada: ${response.payload}');
  }

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
            channelDescription: 'Recordatorios diarios de tareas',
            importance: Importance.high,
            priority: Priority.high,
            ongoing: false,
          ),
        ),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        matchDateTimeComponents: DateTimeComponents.time,
      );
    } catch (e) {
      print('Error al programar recordatorio exacto: $e');
      // Intentar con modo inexacto como fallback
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
              channelDescription: 'Recordatorios diarios de tareas',
              importance: Importance.high,
              priority: Priority.high,
              ongoing: false,
            ),
          ),
          androidScheduleMode: AndroidScheduleMode.inexact,
          uiLocalNotificationDateInterpretation:
              UILocalNotificationDateInterpretation.absoluteTime,
          matchDateTimeComponents: DateTimeComponents.time,
        );
        print('Recordatorio programado con modo inexacto');
      } catch (e2) {
        print('Error al programar recordatorio inexacto: $e2');
      }
    }
  }

  tz.TZDateTime _nextInstanceOf8AM() {
    final tz.TZDateTime now = tz.TZDateTime.now(tz.local);
    tz.TZDateTime scheduledDate = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      8,
      0,
    );

    if (scheduledDate.isBefore(now)) {
      scheduledDate = scheduledDate.add(const Duration(days: 1));
    }

    return scheduledDate;
  }

  Future<void> scheduleProximityReminder(
    int id,
    String title,
    String description,
    DateTime dueDate,
  ) async {
    try {
      final tz.TZDateTime scheduledDate = tz.TZDateTime.from(dueDate, tz.local);

      await _notifications.zonedSchedule(
        id,
        'Tarea Próxima a Vencer',
        '$title - $description',
        scheduledDate.subtract(const Duration(hours: 2)),
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'proximity_channel',
            'Alertas de Proximidad',
            channelDescription: 'Alertas cuando una tarea está próxima a vencer',
            importance: Importance.high,
            priority: Priority.high,
            ongoing: false,
          ),
        ),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
      );
    } catch (e) {
      print('Error al programar recordatorio de proximidad: $e');
      // Intentar con modo inexacto como fallback
      try {
        final tz.TZDateTime scheduledDate = tz.TZDateTime.from(dueDate, tz.local);
        
        await _notifications.zonedSchedule(
          id,
          'Tarea Próxima a Vencer',
          '$title - $description',
          scheduledDate.subtract(const Duration(hours: 2)),
          const NotificationDetails(
            android: AndroidNotificationDetails(
              'proximity_channel',
              'Alertas de Proximidad',
              channelDescription: 'Alertas cuando una tarea está próxima a vencer',
              importance: Importance.high,
              priority: Priority.high,
              ongoing: false,
            ),
          ),
          androidScheduleMode: AndroidScheduleMode.inexact,
          uiLocalNotificationDateInterpretation:
              UILocalNotificationDateInterpretation.absoluteTime,
        );
        print('Recordatorio de proximidad programado con modo inexacto');
      } catch (e2) {
        print('Error al programar recordatorio de proximidad inexacto: $e2');
      }
    }
  }

  Future<void> cancelNotification(int id) async {
    await _notifications.cancel(id);
  }

  Future<void> cancelAllNotifications() async {
    await _notifications.cancelAll();
  }

  Future<void> showImmediateNotification(
    String title,
    String description,
  ) async {
    const NotificationDetails notificationDetails = NotificationDetails(
      android: AndroidNotificationDetails(
        'immediate_channel',
        'Notificaciones Inmediatas',
        channelDescription: 'Notificaciones inmediatas de la app',
        importance: Importance.high,
        priority: Priority.high,
      ),
    );

    await _notifications.show(
      DateTime.now().millisecondsSinceEpoch.remainder(100000),
      title,
      description,
      notificationDetails,
    );
  }
}
