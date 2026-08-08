import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb;
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

/// Avisos locales de la app. Son exactamente cuatro:
///
/// 1. Un resumen diario a las [digestHour] con lo que hay ese día.
/// 2. [taskLeadTime] antes de una tarea (solo tareas).
/// 3. [meetingLeadTime] antes de una reunión (solo reuniones).
/// 4. Un aviso inmediato cuando alguien toca una tarea compartida.
///
/// Todos cuelgan de un único interruptor ([isEnabled]) y de un único canal de
/// Android ([taskReminderChannelId]): antes había tres preferencias distintas
/// y el usuario tenía que entender la diferencia entre "aviso 24 h" y "aviso
/// de reuniones" para apagar algo que en su cabeza era una sola cosa.
class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  // Canal único. Android trata cada canal como un interruptor independiente
  // del permiso general: con varios canales el usuario podía silenciar uno sin
  // darse cuenta y creer que la app estaba rota. Debe coincidir exactamente
  // con el id usado en _detalles más abajo.
  static const taskReminderChannelId = 'task_smart_reminders';
  static const _channelName = 'Recordatorios de Bitácora';
  static const _channelDescription =
      'Resumen diario, aviso antes de cada tarea y reunión, y cambios en '
      'tareas compartidas';
  static const _packageName = 'com.operonte.bitacora';

  /// Interruptor único de todas las notificaciones de la app.
  static const _keyEnabled = 'notif_enabled';

  /// Marca de que los ids ya se migraron al esquema actual. Sin esto quedarían
  /// programadas notificaciones del esquema anterior (avisos de 24 h, el
  /// recordatorio diario fijo con id 0) que nadie puede cancelar una por una.
  static const _keyIdSchemeV3 = 'notif_id_scheme_v3';

  /// Tamaño del espacio de ids de cada tipo de aviso. Los rangos son:
  ///
  /// - `[1, _idSpace)` — aviso previo de una tarea.
  /// - `[_idSpace, 2 * _idSpace)` — aviso previo de una reunión.
  /// - `[_digestIdBase, _digestIdBase + digestDays)` — resúmenes diarios.
  /// - `[_instantIdBase, ...)` — avisos inmediatos de tareas compartidas.
  ///
  /// Separar tareas de reuniones importa: antes el id de una reunión salía del
  /// mismo hash y del mismo rango que el de una tarea, así que dos podían
  /// colisionar y una cancelaba el aviso de la otra.
  static const int _idSpace = 500000000;
  static const int _meetingIdOffset = _idSpace;
  static const int _digestIdBase = 1000000000;
  static const int _instantIdBase = 1500000000;
  static const int _testId = 2100000000;

  /// Cuántos días de resumen quedan programados por adelantado.
  ///
  /// El texto del resumen ("hoy tienes 3 reuniones y 2 tareas") depende del
  /// día, así que no puede ser una notificación repetida con texto fijo: se
  /// programa una por día, cada una con sus propios números. Si la app no se
  /// abre en [digestDays] días los resúmenes se agotan, y es lo correcto —
  /// para entonces los números que tenía guardados ya no valdrían nada.
  static const int digestDays = 7;

  /// Hora del resumen diario.
  static const int digestHour = 8;

  /// Cuánto antes de la fecha límite avisa una tarea.
  static const Duration taskLeadTime = Duration(hours: 2);

  /// Cuánto antes de su hora avisa una reunión.
  static const Duration meetingLeadTime = Duration(minutes: 5);

  /// Última foto conocida de tareas y reuniones. El resumen diario necesita
  /// las dos listas a la vez, y cada una llega por su lado (AppState las
  /// tareas, MeetingService las reuniones), así que se guardan acá para poder
  /// recalcularlo con lo que haya cuando cambie cualquiera de las dos.
  List<Task> _tasks = [];
  List<Meeting> _meetings = [];

  /// Qué hay programado ahora mismo: id de notificación -> huella de lo que se
  /// programó con él.
  ///
  /// Realtime dispara `loadTasks()` en cada cambio del grupo, y cada carga
  /// llamaba al plugin una vez por tarea aunque no hubiera cambiado ninguna:
  /// cientos de saltos al canal nativo por sesión. Con esto, una pasada donde
  /// nada cambió no hace ninguna llamada.
  ///
  /// Vive solo en memoria a propósito: al arrancar la app está vacío y todo se
  /// reprograma una vez, que es lo correcto — el plugin conserva sus alarmas
  /// entre ejecuciones pero no hay forma de saber con qué texto quedaron.
  final Map<int, String> _scheduled = {};

  /// Ids ya cancelados en esta ejecución, para no cancelar dos veces lo mismo.
  final Set<int> _cancelled = {};

  /// Hash estable de 31 bits sobre la cadena completa.
  static int _hash(String value) {
    int result = 0;
    for (int i = 0; i < value.length; i++) {
      result = (result * 31 + value.codeUnitAt(i)) & 0x7FFFFFFF;
    }
    return result;
  }

  /// Convierte taskId a un id de notificación estable dentro del primer rango.
  static int taskIdToNotificationId(String taskId) {
    if (taskId.isEmpty) return 1;
    final result = _hash(taskId) % _idSpace;
    return result == 0 ? 1 : result;
  }

  /// Convierte meetingId a un id del segundo rango, que no se cruza con el de
  /// las tareas.
  static int meetingIdToNotificationId(String meetingId) =>
      _meetingIdOffset + (_hash('meeting_$meetingId') % _idSpace);

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

    await _migrateNotificationIdsIfNeeded();

    _initialized = true;
  }

  /// Cancela de una vez todo lo programado con esquemas anteriores.
  ///
  /// Los ids y los tipos de aviso cambiaron, así que las alarmas viejas ya no
  /// se pueden cancelar una por una: quedarían sonando avisos de 24 h que ya
  /// no existen. Se barre todo y la primera carga de tareas y reuniones —que
  /// ocurre enseguida— vuelve a programar lo que corresponde.
  Future<void> _migrateNotificationIdsIfNeeded() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(_keyIdSchemeV3) ?? false) return;

      await _notifications.cancelAll();
      // Preferencias del esquema de tres interruptores: ya no las lee nadie.
      await prefs.remove('notif_24h_enabled');
      await prefs.remove('notif_2h_enabled');
      await prefs.remove('notif_meeting_reminder_enabled');
      await prefs.setBool(_keyIdSchemeV3, true);
      Logger.info('Notificaciones migradas al esquema nuevo', tag: 'Notif');
    } catch (e) {
      Logger.warning(
        'No se pudo migrar el esquema de notificaciones: $e',
        tag: 'Notif',
      );
    }
  }

  void _onNotificationTapped(NotificationResponse response) {
    Logger.info('Notificación tocada: ${response.payload}', tag: 'Notif');
  }

  // ==================== INTERRUPTOR ÚNICO ====================

  /// En web no hay notificaciones locales: flutter_local_notifications no
  /// tiene implementación para esa plataforma y cada llamada revienta con
  /// MissingPluginException. Todas las entradas públicas se cortan acá.
  bool get _unsupported => kIsWeb;

  Future<bool> get isEnabled async {
    if (_unsupported) return false;
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyEnabled) ?? true;
  }

  /// Enciende o apaga todas las notificaciones. Apagar cancela lo que hubiera
  /// programado; encender lo reprograma con los datos que la app tenga en ese
  /// momento, sin esperar a la próxima sincronización.
  Future<void> setEnabled(bool value) async {
    if (_unsupported) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyEnabled, value);

    if (!value) {
      await _cancelAll();
      Logger.info('Notificaciones desactivadas por el usuario', tag: 'Notif');
      return;
    }

    await syncAllTaskReminders(_tasks);
    await syncAllMeetingReminders(_meetings);
  }

  // ==================== TAREAS ====================

  /// Deja programado el aviso previo de cada tarea pendiente y borra el de las
  /// entregadas o vencidas. Refresca además el resumen diario, porque el
  /// número de tareas del día pudo cambiar.
  Future<void> syncAllTaskReminders(List<Task> tasks) async {
    if (_unsupported) return;
    _tasks = List.of(tasks);

    if (!await isEnabled) {
      await _cancelAll();
      return;
    }

    try {
      final now = DateTime.now();
      for (final task in tasks) {
        if (task.id == null) continue;
        final entregada = task.isCompleted && task.isSubmitted;
        final cuando = task.dueDate.subtract(taskLeadTime);

        if (!entregada && cuando.isAfter(now)) {
          await _scheduleIfChanged(
            id: taskIdToNotificationId(task.id!),
            title: '⏰ Tarea en 2 horas',
            body: '${task.title} — ${task.subject}',
            scheduledTime: cuando,
          );
        } else {
          await cancelTaskReminders(task.id!);
        }
      }
      await _rescheduleDailyDigests();
      Logger.info('Avisos sincronizados para ${tasks.length} tareas', tag: 'Notif');
    } catch (e) {
      Logger.error('Error sincronizando avisos de tareas: $e', tag: 'Notif');
    }
  }

  /// Cancela el aviso de una tarea concreta.
  Future<void> cancelTaskReminders(String taskId) async {
    await _cancelId(taskIdToNotificationId(taskId));
  }

  // ==================== REUNIONES ====================

  /// Deja programado el aviso de [meetingLeadTime] antes de cada reunión y
  /// refresca el resumen diario.
  Future<void> syncAllMeetingReminders(List<Meeting> meetings) async {
    if (_unsupported) return;
    _meetings = List.of(meetings);

    if (!await isEnabled) {
      await _cancelAll();
      return;
    }

    try {
      for (final meeting in meetings) {
        if (meeting.id == null) continue;
        await _scheduleMeetingReminder(meeting);
      }
      await _rescheduleDailyDigests();
      Logger.info('Avisos sincronizados para ${meetings.length} reuniones', tag: 'Notif');
    } catch (e) {
      Logger.error('Error sincronizando avisos de reuniones: $e', tag: 'Notif');
    }
  }

  Future<void> _scheduleMeetingReminder(Meeting meeting) async {
    final id = meetingIdToNotificationId(meeting.id!);
    final ocurrencia = meeting.effectiveDate;
    final cuando = ocurrencia.subtract(meetingLeadTime);

    if (cuando.isBefore(DateTime.now())) {
      await _cancelId(id);
      return;
    }

    // Las semanales se programan como repetición nativa (mismo día de la
    // semana y hora): así siguen avisando aunque la app no se abra en meses,
    // sin depender de que alguien las reprograme.
    await _scheduleIfChanged(
      id: id,
      title: '📹 Reunión en 5 minutos',
      body: '${meeting.title} — ${meeting.subject} a las ${_hhmm(ocurrencia)}',
      scheduledTime: cuando,
      repeatWeekly: meeting.isRecurrent,
    );
  }

  /// Cancela el aviso de una reunión concreta.
  Future<void> cancelMeetingReminder(String meetingId) async {
    await _cancelId(meetingIdToNotificationId(meetingId));
  }

  // ==================== RESUMEN DIARIO ====================

  /// Reprograma los resúmenes de los próximos [digestDays] días.
  ///
  /// Se cancelan y recalculan todos en cada pasada: es barato y evita que un
  /// resumen quede anunciando una tarea que ya se entregó.
  Future<void> _rescheduleDailyDigests() async {
    final now = DateTime.now();
    final hoy = DateTime(now.year, now.month, now.day);

    for (var i = 0; i < digestDays; i++) {
      final dia = hoy.add(Duration(days: i));
      final aLas = DateTime(dia.year, dia.month, dia.day, digestHour);
      final id = _digestIdBase + i;

      final tareas = aLas.isBefore(now) ? 0 : _tasksDueOn(dia);
      final reuniones = aLas.isBefore(now) ? 0 : _meetingsOn(dia);

      // Un resumen que dice "no tienes nada" es ruido: si no hay nada, no
      // suena. Lo mismo si las 8:00 de ese día ya pasaron.
      if (tareas == 0 && reuniones == 0) {
        await _cancelId(id);
        continue;
      }

      await _scheduleIfChanged(
        id: id,
        title: '📅 Tu día en Bitácora',
        body: digestBody(tareas: tareas, reuniones: reuniones),
        scheduledTime: aLas,
      );
    }
  }

  /// Texto del resumen. Público para poder probarlo sin tocar el plugin.
  static String digestBody({required int tareas, required int reuniones}) {
    final partes = <String>[];
    if (reuniones > 0) {
      partes.add(reuniones == 1 ? '1 reunión' : '$reuniones reuniones');
    }
    if (tareas > 0) {
      partes.add(tareas == 1
          ? '1 tarea con fecha límite'
          : '$tareas tareas con fecha límite');
    }
    if (partes.isEmpty) return 'Hoy no tienes nada agendado';
    return 'Hoy tienes ${partes.join(' y ')}';
  }

  int _tasksDueOn(DateTime dia) => _tasks.where((t) {
        if (t.isCompleted && t.isSubmitted) return false;
        return _sameDay(t.dueDate, dia);
      }).length;

  int _meetingsOn(DateTime dia) =>
      _meetings.where((m) => occurrenceOn(m, dia) != null).length;

  /// Hora a la que [meeting] ocurre el día [dia], o null si ese día no toca.
  ///
  /// Una reunión semanal no tiene una sola fecha: la guardada es la primera, y
  /// a partir de ahí se repite cada siete días. Por eso no basta comparar
  /// [Meeting.meetingDate] con el día — hay que comparar el día de la semana y
  /// descartar los días anteriores al comienzo de la serie.
  static DateTime? occurrenceOn(Meeting meeting, DateTime dia) {
    final origen = meeting.meetingDate;

    if (!meeting.isRecurrent) {
      return _sameDay(origen, dia) ? origen : null;
    }

    if (origen.weekday != dia.weekday) return null;
    final ocurrencia =
        DateTime(dia.year, dia.month, dia.day, origen.hour, origen.minute);
    return ocurrencia.isBefore(origen) ? null : ocurrencia;
  }

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  static String _hhmm(DateTime date) =>
      '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';

  // ============ CAMBIOS EN TAREAS COMPARTIDAS ============

  /// Avisa de que otra persona creó o editó una tarea compartida.
  ///
  /// Llega solo mientras el proceso de la app siga vivo, porque nace de la
  /// suscripción Realtime de Supabase y no de un push del servidor: con la app
  /// cerrada por el sistema no hay nada escuchando. Para que llegara siempre
  /// haría falta FCM y una función en el servidor que lo dispare.
  Future<void> notifySharedTaskChange({
    required String title,
    required String subject,
    String? author,
    required bool isNew,
  }) async {
    if (!await isEnabled) return;

    final quien = (author == null || author.trim().isEmpty)
        ? 'Alguien'
        : author.trim();

    await _showNow(
      id: _instantIdBase + DateTime.now().millisecondsSinceEpoch.remainder(100000),
      title: isNew ? '📌 Nueva tarea compartida' : '✏️ Tarea compartida editada',
      body: '$quien ${isNew ? 'agregó' : 'editó'} "$title" — $subject',
    );
  }

  // ==================== PLOMERÍA ====================

  static const NotificationDetails _detalles = NotificationDetails(
    android: AndroidNotificationDetails(
      taskReminderChannelId,
      _channelName,
      channelDescription: _channelDescription,
      importance: Importance.high,
      priority: Priority.high,
    ),
  );

  /// Programa el aviso solo si cambió respecto de lo que ya estaba puesto con
  /// ese mismo id. Ver [_scheduled].
  Future<void> _scheduleIfChanged({
    required int id,
    required String title,
    required String body,
    required DateTime scheduledTime,
    bool repeatWeekly = false,
  }) async {
    final huella =
        '$title|$body|${scheduledTime.millisecondsSinceEpoch}|$repeatWeekly';
    if (_scheduled[id] == huella) return;

    await _scheduleReminder(
      id: id,
      title: title,
      body: body,
      scheduledTime: scheduledTime,
      repeatWeekly: repeatWeekly,
    );
    _scheduled[id] = huella;
    _cancelled.remove(id);
  }

  /// Cancela [id] a lo más una vez, mientras nadie lo vuelva a programar.
  Future<void> _cancelId(int id) async {
    if (_unsupported || _cancelled.contains(id)) return;
    await _notifications.cancel(id);
    _scheduled.remove(id);
    _cancelled.add(id);
  }

  Future<void> _cancelAll() async {
    await _notifications.cancelAll();
    _scheduled.clear();
    _cancelled.clear();
  }

  Future<void> _showNow({
    required int id,
    required String title,
    required String body,
  }) async {
    if (_unsupported) return;
    try {
      await _notifications.show(id, title, body, _detalles);
    } catch (e) {
      Logger.warning('No se pudo mostrar la notificación "$title": $e', tag: 'Notif');
    }
  }

  Future<void> _scheduleReminder({
    required int id,
    required String title,
    required String body,
    required DateTime scheduledTime,
    bool repeatWeekly = false,
  }) async {
    if (_unsupported) return;
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

    final repeticion = repeatWeekly ? DateTimeComponents.dayOfWeekAndTime : null;

    try {
      await _notifications.zonedSchedule(
        id,
        title,
        body,
        tz.TZDateTime.from(scheduledTime, tz.local),
        _detalles,
        androidScheduleMode: mode,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        matchDateTimeComponents: repeticion,
      );
      Logger.info('Aviso programado ($mode): $title a las $scheduledTime',
          tag: 'Notif');
    } catch (e) {
      Logger.error('Error al programar aviso', error: e, tag: 'Notif');
      if (mode == AndroidScheduleMode.inexact) return;

      // El intento exacto falló de forma inesperada pese al chequeo previo:
      // último recurso, inexacto.
      try {
        await _notifications.zonedSchedule(
          id,
          title,
          body,
          tz.TZDateTime.from(scheduledTime, tz.local),
          _detalles,
          androidScheduleMode: AndroidScheduleMode.inexact,
          uiLocalNotificationDateInterpretation:
              UILocalNotificationDateInterpretation.absoluteTime,
          matchDateTimeComponents: repeticion,
        );
      } catch (e2) {
        Logger.error('Fallback también falló', error: e2, tag: 'Notif');
      }
    }
  }

  Future<void> cancelNotification(int id) async {
    await _notifications.cancel(id);
  }

  Future<void> cancelAllNotifications() async {
    await _cancelAll();
  }

  /// Indica si el canal de notificaciones está silenciado a nivel de sistema.
  /// El permiso general puede estar concedido y aun así este canal estar
  /// apagado — Android los trata como interruptores independientes. Si el
  /// canal todavía no fue creado (nunca se programó nada), no hay nada que
  /// revisar todavía.
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
  /// notificaciones de la app — no la pantalla general. Así el usuario no
  /// tiene que encontrar el canal correcto a mano.
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
  /// camino (zonedSchedule) que usan los avisos de tareas y reuniones. A
  /// diferencia de [showImmediateNotification], sirve para aislar si el
  /// problema está en la entrega inmediata o en la alarma programada.
  Future<void> scheduleTestNotification() async {
    await _scheduleReminder(
      id: _testId,
      title: '⏱️ Notificación programada de prueba',
      body: 'Si ves esto, la programación de alarmas funciona correctamente.',
      scheduledTime: DateTime.now().add(const Duration(minutes: 1)),
    );
  }

  Future<void> showImmediateNotification(
      String title, String description) async {
    await _showNow(
      id: _instantIdBase + DateTime.now().millisecondsSinceEpoch.remainder(100000),
      title: title,
      body: description,
    );
  }
}
