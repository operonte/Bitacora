import 'package:flutter/material.dart';
import '../colors.dart';

/// Calendario de un mes completo: encabezado con el nombre del mes y flechas
/// para navegar, más una grilla de 7xN días con puntos de color por cada
/// item que caiga ese día. Genérico en [T] para que reuniones y tareas usen
/// la misma base — antes de esto la aritmética de días (con el mismo riesgo
/// de desfase por huso horario que ya se corrigió en reuniones) hubiera
/// quedado copiada dos veces.
class MonthCalendarGrid<T> extends StatelessWidget {
  final DateTime monthCursor;
  final ValueChanged<int> onMonthDelta;
  final Map<DateTime, List<T>> itemsByDay;
  final Color Function(T item) colorOf;
  final void Function(List<T> itemsThatDay) onDayTap;

  const MonthCalendarGrid({
    super.key,
    required this.monthCursor,
    required this.onMonthDelta,
    required this.itemsByDay,
    required this.colorOf,
    required this.onDayTap,
  });

  static const _weekdayShort = [
    'Lun',
    'Mar',
    'Mié',
    'Jue',
    'Vie',
    'Sáb',
    'Dom',
  ];
  static const _months = [
    'enero',
    'febrero',
    'marzo',
    'abril',
    'mayo',
    'junio',
    'julio',
    'agosto',
    'septiembre',
    'octubre',
    'noviembre',
    'diciembre',
  ];

  DateTime _localDate(DateTime utc) => DateTime(utc.year, utc.month, utc.day);

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  @override
  Widget build(BuildContext context) {
    final monthStart = DateTime(monthCursor.year, monthCursor.month, 1);
    final monthEnd = DateTime(monthCursor.year, monthCursor.month + 1, 0);

    // La grilla arranca en el lunes de la semana del día 1, para que las
    // columnas queden alineadas con el encabezado Lun..Dom. Anclado en UTC:
    // sumar/restar Duration sobre una fecha local puede correrse un día si
    // hay un cambio de huso horario en el medio (mismo motivo que
    // Meeting._nextWeek).
    final gridStartUtc = DateTime.utc(
      monthStart.year,
      monthStart.month,
      1,
    ).subtract(Duration(days: monthStart.weekday - 1));
    final monthEndUtc = DateTime.utc(
      monthEnd.year,
      monthEnd.month,
      monthEnd.day,
    );
    final totalCells =
        ((monthEndUtc.difference(gridStartUtc).inDays + 1) / 7).ceil() * 7;

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.chevron_left),
                  onPressed: () => onMonthDelta(-1),
                ),
                Expanded(
                  child: Text(
                    '${_months[monthCursor.month - 1]} ${monthCursor.year}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.chevron_right),
                  onPressed: () => onMonthDelta(1),
                ),
              ],
            ),
            Row(
              children: [
                for (final label in _weekdayShort)
                  Expanded(
                    child: Center(
                      child: Text(
                        label,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 11,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            for (var week = 0; week < totalCells ~/ 7; week++)
              Row(
                children: [
                  for (var wd = 0; wd < 7; wd++)
                    Expanded(
                      child: _dayCell(
                        context,
                        _localDate(
                          gridStartUtc.add(Duration(days: week * 7 + wd)),
                        ),
                        monthStart,
                      ),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _dayCell(BuildContext context, DateTime day, DateTime monthStart) {
    final inMonth = day.month == monthStart.month;
    final isToday = _isSameDay(day, DateTime.now());
    final here = itemsByDay[day] ?? const [];

    return AspectRatio(
      aspectRatio: 1,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: here.isEmpty ? null : () => onDayTap(here),
        child: Container(
          margin: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            color: isToday
                ? Theme.of(context).primaryColor.withValues(alpha: 0.12)
                : null,
            border: isToday
                ? Border.all(color: Theme.of(context).primaryColor)
                : null,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                '${day.day}',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: isToday ? FontWeight.bold : FontWeight.normal,
                  color: inMonth
                      ? (isToday ? Theme.of(context).primaryColor : null)
                      : AppColors.textSecondary.withValues(alpha: 0.4),
                ),
              ),
              if (here.isNotEmpty) ...[
                const SizedBox(height: 2),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 2,
                  children: [
                    for (final item in here.take(3))
                      Container(
                        width: 5,
                        height: 5,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: colorOf(item),
                        ),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
