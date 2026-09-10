import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:add_2_calendar/add_2_calendar.dart';
import '../models/meeting_model.dart';
import '../providers/theme_provider.dart';
import '../utils/meeting_link_launcher.dart';
import '../services/meeting_service.dart';
import '../widgets/subject_group_list.dart';
import '../widgets/month_calendar_grid.dart';
import 'add_meeting_screen.dart';
import '../colors.dart';
import 'config_screen.dart';
import 'my_profile_screen.dart';
import '../services/career_service.dart';

class MeetingsScreen extends StatefulWidget {
  final bool isEmbedded;
  const MeetingsScreen({super.key, this.isEmbedded = false});

  @override
  State<MeetingsScreen> createState() => _MeetingsScreenState();
}

class _MeetingsScreenState extends State<MeetingsScreen> {
  final MeetingService _meetingService = MeetingService();

  /// null = todas las carreras. Se conserva mientras viva la pantalla; no se
  /// persiste a propósito, para que al volver siempre veas todo y no te
  /// pierdas una reunión por un filtro que dejaste puesto hace días.
  String? _careerFilter;

  /// Primer día del mes que muestra la vista de calendario mensual. Arranca
  /// en el mes actual; no se persiste — cada vez que se entra a la pantalla
  /// vuelve al mes de hoy, para no encontrarla "perdida" en un mes viejo.
  DateTime _monthCursor = DateTime(DateTime.now().year, DateTime.now().month);

  @override
  void initState() {
    super.initState();
    _meetingService.syncFromSupabase();
  }

  /// Desplegable de carrera. Solo se muestra si hay más de una opción real:
  /// con una sola carrera el filtro no filtraría nada y sería solo ruido.
  Widget? _buildCareerFilter() {
    final used = _meetingService.usedCareerIds;
    if (used.length < 2) return null;

    final careers = CareerService().getCareers();
    String labelFor(String id) {
      if (id == MeetingService.noCareerFilter) return 'Sin carrera';
      for (final c in careers) {
        if (c.id == id) return c.name;
      }
      return id;
    }

    final options = used.toList()
      ..sort((a, b) => labelFor(a).compareTo(labelFor(b)));

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: DropdownButtonFormField<String?>(
        initialValue: _careerFilter,
        isDense: true,
        decoration: InputDecoration(
          labelText: 'Carrera',
          prefixIcon: const Icon(Icons.school_outlined, size: 20),
          isDense: true,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        ),
        items: [
          const DropdownMenuItem<String?>(
            value: null,
            child: Text('Todas las carreras'),
          ),
          for (final id in options)
            DropdownMenuItem<String?>(value: id, child: Text(labelFor(id))),
        ],
        onChanged: (value) => setState(() => _careerFilter = value),
      ),
    );
  }

  Future<void> _launchMeetingUrl(String url) =>
      MeetingLinkLauncher.open(context, url);

  /// Solo Android/iOS: el paquete no cubre Linux ni Web, y Bitácora corre en
  /// las cuatro.
  bool get _canAddToDeviceCalendar =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  /// Abre el calendario nativo con el evento precargado — el usuario todavía
  /// tiene que tocar "Guardar" ahí, así que no hace falta pedir permiso de
  /// calendario (el modo por defecto del plugin no lo necesita).
  Future<void> _addToDeviceCalendar(Meeting meeting) async {
    final start = meeting.effectiveDate;
    // El modelo no guarda cuánto dura una reunión, solo la hora de inicio;
    // una hora es un duración de clase típica y evitamos pedirle ese dato al
    // usuario solo para esto.
    final end = start.add(const Duration(hours: 1));

    final event = Event(
      title: meeting.title,
      description: meeting.description,
      location: meeting.meetingLink ?? '',
      startDate: start,
      endDate: end,
      recurrence: meeting.isRecurrent
          ? Recurrence(
              frequency: Frequency.weekly,
              // Un año cubre de sobra un semestre; evita dejar un evento
              // "para siempre" en el calendario si la reunión se da de baja.
              endDate: start.add(const Duration(days: 365)),
            )
          : null,
    );

    final ok = await Add2Calendar.addEvent2Cal(event);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No se pudo abrir el calendario del teléfono.'),
        ),
      );
    }
  }

  Future<void> _toggleMeetingCompleted(Meeting meeting) async {
    final messenger = ScaffoldMessenger.of(context);
    final marcada = !meeting.isCompleted;
    try {
      await _meetingService.saveMeeting(meeting.copyWith(isCompleted: marcada));
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            marcada
                ? 'Reunión marcada como realizada'
                : 'Reunión marcada como pendiente',
          ),
        ),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('No se pudo actualizar la reunión: $e')),
      );
    }
  }

  String _formatMeetingDate(DateTime date) {
    const days = ['Lun', 'Mar', 'Mié', 'Jue', 'Vie', 'Sáb', 'Dom'];
    const months = [
      'Ene',
      'Feb',
      'Mar',
      'Abr',
      'May',
      'Jun',
      'Jul',
      'Ago',
      'Sep',
      'Oct',
      'Nov',
      'Dic',
    ];
    final dayName = days[(date.weekday - 1) % 7];
    final monthName = months[(date.month - 1) % 12];
    final hour = date.hour.toString().padLeft(2, '0');
    final min = date.minute.toString().padLeft(2, '0');
    return '$dayName ${date.day} $monthName \u2022 $hour:$min';
  }

  @override
  Widget build(BuildContext context) {
    final career = CareerService().getSelectedCareer();
    final careerName = career?.name ?? '';
    final viewMode = context.watch<ThemeProvider>().meetingsViewMode;

    return ListenableBuilder(
      listenable: _meetingService,
      builder: (context, _) {
        // Sin filtro para decidir el estado vacío: si no hay ninguna reunión
        // corresponde el mensaje de bienvenida, pero si solo el filtro las
        // esconde hay que dejar el desplegable a la vista para poder soltarlo.
        final hasAnyMeeting = _meetingService.getMeetings().isNotEmpty;
        final meetings = _meetingService.getMeetings(careerId: _careerFilter);

        final bodyContent = SizedBox(
          width: double.infinity,
          height: double.infinity,
          child: !hasAnyMeeting
              ? _buildEmptyMeetingsState()
              : RefreshIndicator(
                  onRefresh: () => _meetingService.syncFromSupabase(),
                  child: viewMode == MeetingsViewMode.schedule
                      ? _buildScheduleView(meetings)
                      : viewMode == MeetingsViewMode.month
                      ? _buildMonthView(meetings)
                      : SubjectGroupList<Meeting>(
                          items: meetings,
                          subjectOf: (m) => m.subject,
                          countLabelOf: (count) =>
                              '$count ${count == 1 ? 'reunión' : 'reuniones'}',
                          itemBuilder: _buildMeetingCard,
                          dateOf: (m) => m.effectiveDate,
                          header: _buildCareerFilter(),
                          searchHint: 'Buscar reunión o materia',
                          searchTextOf: (m) =>
                              '${m.title} ${m.subject} ${m.professor}',
                        ),
                ),
        );

        if (widget.isEmbedded) {
          return bodyContent;
        }

        return Scaffold(
          appBar: AppBar(
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text('Reuniones'),
                    if (meetings.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '${meetings.length}',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: AppColors.primary,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                if (careerName.isNotEmpty)
                  Text(
                    careerName,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.normal,
                      color: AppColors.textSecondary,
                    ),
                  ),
              ],
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.person_outline),
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const MyProfileScreen()),
                ),
                tooltip: 'Mi perfil',
              ),
              IconButton(
                icon: const Icon(Icons.settings),
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const ConfigScreen()),
                ),
                tooltip: 'Configuración',
              ),
            ],
          ),
          body: bodyContent,
          floatingActionButton: FloatingActionButton(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const AddMeetingScreen()),
            ),
            backgroundColor: Theme.of(context).primaryColor,
            elevation: 4,
            shape: const CircleBorder(),
            child: const Icon(Icons.add, color: Colors.white, size: 26),
          ),
        );
      },
    );
  }

  Widget _buildEmptyMeetingsState() {
    return Center(
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: Container(
          margin: const EdgeInsets.all(24),
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      AppColors.primary.withValues(alpha: 0.15),
                      const Color(0xFF48CAE4).withValues(alpha: 0.15),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.video_camera_front_rounded,
                  size: 44,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'No tienes reuniones programadas',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              const Text(
                'Agrega tus clases virtuales (Zoom, Meet, Teams) o presenciales para mantener tus horarios al día.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  color: AppColors.textSecondary,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Color _getTypeColor(String type) {
    switch (type.toLowerCase()) {
      case 'zoom':
        return const Color(0xFF2D8CFF);
      case 'meet':
      case 'google meet':
        return const Color(0xFF00832D);
      case 'teams':
      case 'microsoft teams':
        return const Color(0xFF6264A7);
      case 'presencial':
        return const Color(0xFFE65100);
      default:
        return Theme.of(context).primaryColor;
    }
  }

  static const _weekdayShort = [
    'Lun',
    'Mar',
    'Mié',
    'Jue',
    'Vie',
    'Sáb',
    'Dom',
  ];

  /// Vista de horario semanal, tipo horario de clases: columnas por día,
  /// filas por hora. Solo tiene sentido para lo que se repite cada semana a
  /// la misma hora, así que las recurrentes van siempre y las puntuales solo
  /// si su fecha cae en la semana actual — si no, se vería como "de esta
  /// semana" algo que puede ser dentro de un mes. El resto queda abajo, en
  /// una lista aparte, para no perderlas de vista.
  Widget _buildScheduleView(List<Meeting> meetings) {
    final now = DateTime.now();
    final startOfWeek = DateTime(
      now.year,
      now.month,
      now.day,
    ).subtract(Duration(days: now.weekday - 1));
    final endOfWeek = startOfWeek.add(const Duration(days: 7));

    final inGrid = <Meeting>[];
    final outsideGrid = <Meeting>[];
    for (final m in meetings) {
      final date = m.effectiveDate;
      final isThisWeek =
          !date.isBefore(startOfWeek) && date.isBefore(endOfWeek);
      if (m.isRecurrent || isThisWeek) {
        inGrid.add(m);
      } else {
        outsideGrid.add(m);
      }
    }
    outsideGrid.sort((a, b) => a.effectiveDate.compareTo(b.effectiveDate));

    var minHour = 8;
    var maxHour = 20;
    if (inGrid.isNotEmpty) {
      minHour = inGrid
          .map((m) => m.effectiveDate.hour)
          .reduce((a, b) => a < b ? a : b);
      maxHour = inGrid
          .map((m) => m.effectiveDate.hour)
          .reduce((a, b) => a > b ? a : b);
    }
    final hours = [for (var h = minHour; h <= maxHour; h++) h];

    final cells = <int, Map<int, List<Meeting>>>{};
    for (final m in inGrid) {
      final weekday = m.effectiveDate.weekday;
      final hour = m.effectiveDate.hour;
      final byHour = cells.putIfAbsent(weekday, () => {});
      byHour.putIfAbsent(hour, () => []).add(m);
    }

    final header = _buildCareerFilter();

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        if (header != null) header,
        _buildWeeklyGrid(hours, cells),
        if (outsideGrid.isNotEmpty) ...[
          const SizedBox(height: 20),
          const Text(
            'OTRAS REUNIONES',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 8),
          ...outsideGrid.map(_buildMeetingCard),
        ],
      ],
    );
  }

  /// En qué fechas de calendario cae [m] dentro de [monthStart]..[monthEnd]
  /// (un mes completo, ambos límites inclusive). Las puntuales dan a lo sumo
  /// una fecha; las semanales dan una por cada semana del mes que coincida
  /// con su día, sin retroceder antes de que la reunión existiera.
  ///
  /// La aritmética de "sumar 7 días" se ancla en UTC (sin huso horario) por
  /// el mismo motivo que [Meeting._nextWeek]: sumar Duration(days: 7) sobre
  /// una fecha local directamente puede correrse un día si de por medio hay
  /// un cambio de horario.
  List<DateTime> _occurrencesInMonth(
    Meeting m,
    DateTime monthStart,
    DateTime monthEnd,
  ) {
    final base = DateTime(
      m.meetingDate.year,
      m.meetingDate.month,
      m.meetingDate.day,
    );
    if (!m.isRecurrent) {
      if (!base.isBefore(monthStart) && !base.isAfter(monthEnd)) return [base];
      return const [];
    }

    final monthStartUtc = DateTime.utc(
      monthStart.year,
      monthStart.month,
      monthStart.day,
    );
    final monthEndUtc = DateTime.utc(
      monthEnd.year,
      monthEnd.month,
      monthEnd.day,
    );
    var cursor = DateTime.utc(base.year, base.month, base.day);
    while (cursor.isBefore(monthStartUtc)) {
      cursor = cursor.add(const Duration(days: 7));
    }
    final result = <DateTime>[];
    while (!cursor.isAfter(monthEndUtc)) {
      result.add(DateTime(cursor.year, cursor.month, cursor.day));
      cursor = cursor.add(const Duration(days: 7));
    }
    return result;
  }

  void _changeMonth(int delta) {
    setState(() {
      _monthCursor = DateTime(_monthCursor.year, _monthCursor.month + delta);
    });
  }

  Widget _buildMonthView(List<Meeting> meetings) {
    final monthStart = DateTime(_monthCursor.year, _monthCursor.month, 1);
    final monthEnd = DateTime(_monthCursor.year, _monthCursor.month + 1, 0);

    // Fecha -> reuniones que caen ese día, entre las puntuales y cada
    // ocurrencia de las semanales dentro del mes visible.
    final byDay = <DateTime, List<Meeting>>{};
    for (final m in meetings) {
      for (final day in _occurrencesInMonth(m, monthStart, monthEnd)) {
        byDay.putIfAbsent(day, () => []).add(m);
      }
    }

    final header = _buildCareerFilter();

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        if (header != null) header,
        MonthCalendarGrid<Meeting>(
          monthCursor: _monthCursor,
          onMonthDelta: _changeMonth,
          itemsByDay: byDay,
          colorOf: (m) => _getTypeColor(m.effectiveType),
          onDayTap: (meetingsThatDay) => _showMeetingsAtSlot(meetingsThatDay),
        ),
      ],
    );
  }

  Widget _buildWeeklyGrid(
    List<int> hours,
    Map<int, Map<int, List<Meeting>>> cells,
  ) {
    const hourColWidth = 46.0;
    const dayColWidth = 88.0;
    const rowHeight = 52.0;

    Widget hourCell(int? hour) => SizedBox(
      width: hourColWidth,
      height: rowHeight,
      child: Center(
        child: hour == null
            ? null
            : Text(
                '${hour.toString().padLeft(2, '0')}:00',
                style: const TextStyle(
                  fontSize: 10.5,
                  color: AppColors.textSecondary,
                ),
              ),
      ),
    );

    Widget dayHeaderCell(int weekday) => SizedBox(
      width: dayColWidth,
      height: rowHeight,
      child: Center(
        child: Text(
          _weekdayShort[weekday - 1],
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
        ),
      ),
    );

    Widget dayCell(int weekday, int hour) {
      final meetingsHere = cells[weekday]?[hour] ?? const <Meeting>[];
      if (meetingsHere.isEmpty) {
        return Container(
          width: dayColWidth,
          height: rowHeight,
          margin: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            color: Theme.of(context).dividerColor.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(8),
          ),
        );
      }
      final first = meetingsHere.first;
      final color = _getTypeColor(first.effectiveType);
      return Container(
        width: dayColWidth,
        height: rowHeight,
        margin: const EdgeInsets.all(2),
        child: Material(
          color: color.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(8),
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => _showMeetingsAtSlot(meetingsHere),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    first.subject.isNotEmpty ? first.subject : first.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                      color: color,
                    ),
                  ),
                  if (meetingsHere.length > 1)
                    Text(
                      '+${meetingsHere.length - 1}',
                      style: TextStyle(fontSize: 9, color: color),
                    ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Column(
              children: [hourCell(null), for (final h in hours) hourCell(h)],
            ),
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Column(
                  children: [
                    Row(
                      children: [
                        for (var wd = 1; wd <= 7; wd++) dayHeaderCell(wd),
                      ],
                    ),
                    for (final h in hours)
                      Row(
                        children: [
                          for (var wd = 1; wd <= 7; wd++) dayCell(wd, h),
                        ],
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Una celda puede tener más de una reunión (dos materias compartidas a la
  /// misma hora). Se abre una hoja con la tarjeta completa de cada una —así
  /// no se pierden los botones de editar/eliminar/conectarse.
  void _showMeetingsAtSlot(List<Meeting> meetingsHere) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.5,
        minChildSize: 0.3,
        maxChildSize: 0.9,
        expand: false,
        builder: (ctx, scrollController) => ListView(
          controller: scrollController,
          padding: const EdgeInsets.all(16),
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: AppColors.textSecondary.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            ...meetingsHere.map(_buildMeetingCard),
          ],
        ),
      ),
    );
  }

  Widget _buildMeetingCard(Meeting meeting) {
    final effectiveType = meeting.effectiveType;
    final typeColor = _getTypeColor(effectiveType);
    final hasLink =
        meeting.meetingLink != null && meeting.meetingLink!.isNotEmpty;

    // Una reunión compartida por otro miembro se ve pero no se toca: la RLS
    // rechaza el update/delete igual, así que ofrecer los botones solo
    // llevaría a un error confuso.
    final uid = Supabase.instance.client.auth.currentUser?.id;
    final isOwn =
        uid == null || meeting.userId.isEmpty || meeting.userId == uid;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: typeColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(meeting.typeIcon, color: typeColor, size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        meeting.title,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          decoration: meeting.isCompleted
                              ? TextDecoration.lineThrough
                              : null,
                          color: meeting.isCompleted
                              ? AppColors.textSecondary
                              : null,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${meeting.subject}${meeting.professor.isNotEmpty ? ' \u2022 Prof. ${meeting.professor}' : ''}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      if (!isOwn) ...[
                        const SizedBox(height: 2),
                        Text(
                          'Compartida por ${meeting.userName}',
                          style: const TextStyle(
                            fontSize: 11,
                            fontStyle: FontStyle.italic,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (_canAddToDeviceCalendar)
                  IconButton(
                    icon: const Icon(Icons.event_available_outlined, size: 18),
                    tooltip: 'Agregar a mi calendario',
                    onPressed: () => _addToDeviceCalendar(meeting),
                  ),
                if (isOwn) ...[
                  // is_completed existía en el modelo y en la tabla desde el
                  // principio, pero no había forma de marcarlo. Solo tiene
                  // sentido en las puntuales: una recurrente vuelve sola la
                  // semana siguiente.
                  if (!meeting.isRecurrent)
                    IconButton(
                      icon: Icon(
                        meeting.isCompleted
                            ? Icons.check_circle
                            : Icons.check_circle_outline,
                        size: 18,
                        color: meeting.isCompleted
                            ? AppColors.success
                            : AppColors.textSecondary,
                      ),
                      tooltip: meeting.isCompleted
                          ? 'Marcar como pendiente'
                          : 'Marcar como realizada',
                      onPressed: () => _toggleMeetingCompleted(meeting),
                    ),
                  IconButton(
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    tooltip: 'Editar',
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => AddMeetingScreen(meeting: meeting),
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(
                      Icons.delete_outline_rounded,
                      size: 18,
                      color: AppColors.error,
                    ),
                    tooltip: 'Eliminar',
                    onPressed: () => _confirmDeleteMeeting(meeting),
                  ),
                ] else
                  Tooltip(
                    message: 'Compartida por ${meeting.userName}',
                    child: const Padding(
                      padding: EdgeInsets.all(8),
                      child: Icon(
                        Icons.groups_outlined,
                        size: 18,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
              ],
            ),
            if (meeting.description.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                meeting.description,
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
            const SizedBox(height: 12),
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 12,
              runSpacing: 10,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.access_time_rounded,
                      size: 15,
                      color: AppColors.textSecondary,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      _formatMeetingDate(meeting.effectiveDate),
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (meeting.isRecurrent) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.purple.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text(
                          'Semanal',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: Colors.purple,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                if (hasLink)
                  FilledButton.icon(
                    onPressed: () => _launchMeetingUrl(meeting.meetingLink!),
                    icon: const Icon(Icons.video_call_rounded, size: 16),
                    label: Text('Conectarse a $effectiveType'),
                    style: FilledButton.styleFrom(
                      backgroundColor: typeColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDeleteMeeting(Meeting meeting) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('\u00bfEliminar reuni\u00f3n?'),
        content: Text('"${meeting.title}" ser\u00e1 eliminada de tu agenda.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await _meetingService.deleteMeeting(meeting.id!);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Reuni\u00f3n eliminada')));
      }
    }
  }
}
