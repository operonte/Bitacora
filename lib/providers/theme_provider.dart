import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../colors.dart';

enum AppThemeMode { light, dark, system }

enum MascotOption { none, robot, cat }

/// Cómo se muestran las reuniones: lista cronológica u horario semanal
/// tipo grilla (día x hora), pensado para las recurrentes.
enum MeetingsViewMode { list, schedule, month }

class ThemeProvider extends ChangeNotifier {
  static final ThemeProvider _instance = ThemeProvider._internal();
  factory ThemeProvider() => _instance;
  ThemeProvider._internal();

  static const _modeKey = 'app_theme_mode';
  static const _paletteKey = 'app_theme_palette';
  static const _meetingsViewKey = 'meetings_view_mode';

  AppThemeMode _mode = AppThemeMode.system;
  AppColorPalette _palette = AppColorPalette.teal;
  MeetingsViewMode _meetingsViewMode = MeetingsViewMode.list;

  AppThemeMode get mode => _mode;
  AppColorPalette get palette => _palette;
  MeetingsViewMode get meetingsViewMode => _meetingsViewMode;

  /// La mascota no se elige por separado: viene con la paleta.
  /// Verde -> robot hackercore. Rosa -> gato. El resto, sin mascota.
  MascotOption get mascot {
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

    notifyListeners();
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
