import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../colors.dart';

enum AppThemeMode { light, dark, system }

enum MascotOption {
  none,
  robot,
  cat,
  hamsterYellow,
  catBlue,
  bunny,
  hamsterBrown,
}

/// Cómo se muestran las reuniones: lista cronológica u horario semanal
/// tipo grilla (día x hora), pensado para las recurrentes.
enum MeetingsViewMode { list, schedule, month }

/// Cómo se muestran las tareas pendientes: lista cronológica, agenda de la
/// semana (un día al lado del otro, sin hora — las tareas no tienen horario
/// fijo como las reuniones) o calendario del mes completo.
enum TasksViewMode { list, week, month }

class ThemeProvider extends ChangeNotifier {
  static final ThemeProvider _instance = ThemeProvider._internal();
  factory ThemeProvider() => _instance;
  ThemeProvider._internal();

  static const _modeKey = 'app_theme_mode';
  static const _paletteKey = 'app_theme_palette';
  static const _meetingsViewKey = 'meetings_view_mode';
  static const _tasksViewKey = 'tasks_view_mode';
  static const _mascotKey = 'app_mascot_option';

  AppThemeMode _mode = AppThemeMode.system;
  AppColorPalette _palette = AppColorPalette.teal;
  MeetingsViewMode _meetingsViewMode = MeetingsViewMode.list;
  TasksViewMode _tasksViewMode = TasksViewMode.list;
  MascotOption _mascot = MascotOption.none;

  AppThemeMode get mode => _mode;
  AppColorPalette get palette => _palette;
  MeetingsViewMode get meetingsViewMode => _meetingsViewMode;
  TasksViewMode get tasksViewMode => _tasksViewMode;
  MascotOption get mascot => _mascot;

  /// Antes de tener su propia preferencia, la mascota venía atada a la
  /// paleta (verde -> robot, rosa -> gato). Se usa solo una vez, en
  /// [initialize], para migrar a quien ya tenía una paleta elegida sin que
  /// se le desaparezca la mascota de golpe.
  MascotOption _mascotFromPaletteLegacy() {
    switch (_palette) {
      case AppColorPalette.emerald:
        return MascotOption.robot;
      case AppColorPalette.feminine:
        return MascotOption.cat;
      case AppColorPalette.teal:
        return MascotOption.none;
    }
  }

  Color get primaryColor => AppColors.getPrimary(_palette);
  Color get primaryLightColor => AppColors.getPrimaryLight(_palette);
  Color get primaryDarkColor => AppColors.getPrimaryDark(_palette);
  Color get accentColor => AppColors.getAccent(_palette);
  Color get containerBgColor => AppColors.getContainerBg(_palette);
  LinearGradient get gradient => AppColors.getGradient(_palette);

  ThemeMode get themeMode {
    switch (_mode) {
      case AppThemeMode.light:
        return ThemeMode.light;
      case AppThemeMode.dark:
        return ThemeMode.dark;
      case AppThemeMode.system:
        return ThemeMode.system;
    }
  }

  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    final storedMode = prefs.getInt(_modeKey) ?? 2; // default: system
    _mode = AppThemeMode.values[storedMode.clamp(0, 2)];

    final storedPalette = prefs.getInt(_paletteKey) ?? 0; // default: teal
    _palette = AppColorPalette.values[storedPalette.clamp(0, 2)];

    final storedMeetingsView =
        prefs.getInt(_meetingsViewKey) ?? 0; // default: lista
    _meetingsViewMode = MeetingsViewMode.values[storedMeetingsView.clamp(0, 2)];

    final storedTasksView = prefs.getInt(_tasksViewKey) ?? 0; // default: lista
    _tasksViewMode = TasksViewMode.values[storedTasksView.clamp(0, 2)];

    final storedMascot = prefs.getInt(_mascotKey);
    if (storedMascot == null) {
      // Nunca se guardó una preferencia propia: quien ya tenía una paleta
      // elegida conserva la mascota que esa paleta implicaba, y desde ahora
      // queda guardada aparte — a partir de acá, paleta y mascota se eligen
      // por separado.
      _mascot = _mascotFromPaletteLegacy();
      await prefs.setInt(_mascotKey, _mascot.index);
    } else {
      _mascot = MascotOption.values[storedMascot.clamp(
        0,
        MascotOption.values.length - 1,
      )];
    }

    notifyListeners();
  }

  Future<void> setMascot(MascotOption mascot) async {
    _mascot = mascot;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_mascotKey, mascot.index);
  }

  Future<void> setMode(AppThemeMode mode) async {
    _mode = mode;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_modeKey, mode.index);
  }

  Future<void> setPalette(AppColorPalette palette) async {
    _palette = palette;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_paletteKey, palette.index);
  }

  Future<void> setMeetingsViewMode(MeetingsViewMode mode) async {
    _meetingsViewMode = mode;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_meetingsViewKey, mode.index);
  }

  Future<void> setTasksViewMode(TasksViewMode mode) async {
    _tasksViewMode = mode;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_tasksViewKey, mode.index);
  }

  String get modeLabel {
    switch (_mode) {
      case AppThemeMode.light:
        return 'Claro';
      case AppThemeMode.dark:
        return 'Oscuro';
      case AppThemeMode.system:
        return 'Sistema';
    }
  }

  String get paletteLabel {
    switch (_palette) {
      case AppColorPalette.teal:
        return 'Por defecto';
      case AppColorPalette.emerald:
        return 'Verde';
      case AppColorPalette.feminine:
        return 'Rosa';
    }
  }

  IconData get modeIcon {
    switch (_mode) {
      case AppThemeMode.light:
        return Icons.light_mode;
      case AppThemeMode.dark:
        return Icons.dark_mode;
      case AppThemeMode.system:
        return Icons.brightness_auto;
    }
  }
}
