import 'package:flutter/material.dart';
import '../models/career_model.dart';
import '../services/career_service.dart';

/// Par de desplegables carrera → asignatura, en cascada.
///
/// La carrera va primero y acota las asignaturas: sin eso se podía guardar un
/// archivo de Informática bajo una asignatura de Teología, que es el error que
/// esto viene a impedir. La carrera es obligatoria — no se puede usar la app
/// sin pertenecer a alguna.
///
/// Estaba copiado tres veces dentro de `area_personal_screen.dart` (subir
/// archivo, editar archivo, agregar enlace), cada copia con su propia lista de
/// materias y su propio `onChanged` recalculando lo mismo.
class CareerSubjectPicker extends StatefulWidget {
  /// Carrera preseleccionada. Si es null o el usuario ya no pertenece a ella,
  /// se cae a la carrera activa y, si tampoco, a la primera de la lista.
  final String? initialCareerId;

  /// Asignatura preseleccionada.
  final String initialSubject;

  /// Materias creadas por el usuario. Se ofrecen en todas las carreras porque
  /// el modelo Subject no guarda carrera.
  final List<String> ownSubjects;

  /// Se llama con la carrera y la asignatura vigentes, incluida la primera vez
  /// al construirse: así el formulario que lo contiene arranca con los valores
  /// ya resueltos y no tiene que repetir la lógica de "cuál es la carrera por
  /// defecto".
  final void Function(String? careerId, String subject) onChanged;

  const CareerSubjectPicker({
    super.key,
    required this.onChanged,
    this.initialCareerId,
    this.initialSubject = '',
    this.ownSubjects = const [],
  });

  /// Asignatura genérica, siempre disponible.
  static const String generalSubject = 'General';

  @override
  State<CareerSubjectPicker> createState() => _CareerSubjectPickerState();
}

class _CareerSubjectPickerState extends State<CareerSubjectPicker> {
  late final List<Career> _careers = CareerService().getCareers();
  String? _careerId;
  late String _subject;
  List<String> _subjects = const [];

  @override
  void initState() {
    super.initState();

    _careerId = _careers.any((c) => c.id == widget.initialCareerId)
        ? widget.initialCareerId
        : (CareerService().getSelectedCareer()?.id ??
            (_careers.isNotEmpty ? _careers.first.id : null));

    _subjects = _subjectsFor(_careerId);

    // Una asignatura guardada puede no estar en la carrera: archivo viejo, mal
    // clasificado, o carrera de la que el usuario se salió. Se agrega para no
    // perderla en silencio al abrir el desplegable.
    if (widget.initialSubject.isNotEmpty &&
        !_subjects.contains(widget.initialSubject)) {
      _subjects = [..._subjects]..insert(1, widget.initialSubject);
    }

    _subject = _subjects.contains(widget.initialSubject)
        ? widget.initialSubject
        : (_subjects.length > 1 ? _subjects[1] : _subjects.first);

    // Después del primer frame: llamar al callback durante initState haría
    // setState en el padre mientras todavía se está construyendo.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onChanged(_careerId, _subject);
    });
  }

  List<String> _subjectsFor(String? careerId) {
    final subjects = <String>[CareerSubjectPicker.generalSubject];

    for (final c in _careers) {
      if (careerId != null && c.id != careerId) continue;
      for (final s in c.predefinedSubjects) {
        if (!subjects.contains(s.name)) subjects.add(s.name);
      }
    }

    for (final nombre in widget.ownSubjects) {
      if (!subjects.any((s) => s.toLowerCase() == nombre.toLowerCase())) {
        subjects.add(nombre);
      }
    }

    return subjects;
  }

  void _onCareerChanged(String? careerId) {
    setState(() {
      _careerId = careerId;
      _subjects = _subjectsFor(careerId);
      // La asignatura elegida puede no existir en la carrera nueva.
      if (!_subjects.contains(_subject)) {
        _subject = _subjects.length > 1 ? _subjects[1] : _subjects.first;
      }
    });
    widget.onChanged(_careerId, _subject);
  }

  @override
  Widget build(BuildContext context) {
    final borde = OutlineInputBorder(borderRadius: BorderRadius.circular(12));

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_careers.isNotEmpty) ...[
          DropdownButtonFormField<String>(
            initialValue: _careerId,
            decoration: InputDecoration(
              labelText: 'Carrera',
              helperText: 'Define qué asignaturas puedes elegir',
              prefixIcon: const Icon(Icons.workspace_premium_outlined),
              border: borde,
            ),
            items: [
              for (final c in _careers)
                DropdownMenuItem<String>(
                  value: c.id,
                  child: Text(c.name, overflow: TextOverflow.ellipsis),
                ),
            ],
            validator: (val) => val == null ? 'Elige una carrera' : null,
            onChanged: _onCareerChanged,
          ),
          const SizedBox(height: 16),
        ],
        DropdownButtonFormField<String>(
          initialValue: _subjects.contains(_subject) ? _subject : _subjects.first,
          decoration: InputDecoration(
            labelText: 'Asignatura / Materia',
            prefixIcon: const Icon(Icons.school_outlined),
            border: borde,
          ),
          items: _subjects
              .map((sub) => DropdownMenuItem<String>(
                    value: sub,
                    child: Text(sub, overflow: TextOverflow.ellipsis),
                  ))
              .toList(),
          onChanged: (val) {
            if (val == null) return;
            setState(() => _subject = val);
            widget.onChanged(_careerId, _subject);
          },
        ),
      ],
    );
  }
}
