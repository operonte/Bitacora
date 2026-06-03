import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:provider/provider.dart';
import 'colors.dart';
import 'models/career_model.dart';
import 'services/career_service.dart';
import 'notification_service.dart';
import 'providers/theme_provider.dart';

class ConfigScreen extends StatefulWidget {
  const ConfigScreen({super.key});

  @override
  _ConfigScreenState createState() => _ConfigScreenState();
}

class _ConfigScreenState extends State<ConfigScreen> {
  final CareerService _careerService = CareerService();
  final NotificationService _notifService = NotificationService();
  Career? _selectedCareer;
  bool _notif24h = true;
  bool _notif2h = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final career = _careerService.getSelectedCareer();
    final n24 = await _notifService.is24hEnabled;
    final n2 = await _notifService.is2hEnabled;
    if (mounted) {
      setState(() {
        _selectedCareer = career;
        _notif24h = n24;
        _notif2h = n2;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = context.watch<ThemeProvider>();

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _selectedCareer != null
              ? 'Configuración — ${_selectedCareer!.name}'
              : 'Configuración',
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // ── Apariencia ──────────────────────────────────────
          _sectionHeader(context, 'Apariencia', Icons.palette_outlined),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Column(
                children: AppThemeMode.values.map((mode) {
                  final icons = {
                    AppThemeMode.light: Icons.light_mode,
                    AppThemeMode.dark: Icons.dark_mode,
                    AppThemeMode.system: Icons.brightness_auto,
                  };
                  final labels = {
                    AppThemeMode.light: 'Claro',
                    AppThemeMode.dark: 'Oscuro',
                    AppThemeMode.system: 'Seguir al sistema',
                  };
                  final selected = themeProvider.mode == mode;
                  return ListTile(
                    leading: Icon(
                      icons[mode],
                      color: selected ? AppColors.primary : null,
                    ),
                    title: Text(labels[mode]!),
                    trailing: selected
                        ? const Icon(
                            Icons.check_circle,
                            color: AppColors.primary,
                          )
                        : null,
                    onTap: () => themeProvider.setMode(mode),
                  );
                }).toList(),
              ),
            ),
          ),

          const SizedBox(height: 24),

          // ── Materias ────────────────────────────────────────
          _sectionHeader(context, 'Materias', Icons.book_outlined),
          const SizedBox(height: 8),
          Card(
            child: ListTile(
              leading: const Icon(Icons.refresh, color: AppColors.primary),
              title: const Text('Actualizar nombres de profesores'),
              subtitle: const Text(
                'Recargar materias con información actualizada',
              ),
              trailing: const Icon(Icons.arrow_forward_ios, size: 16),
              onTap: _reloadSubjects,
            ),
          ),

          const SizedBox(height: 24),

          // ── Notificaciones ───────────────────────────────────
          _sectionHeader(
            context,
            'Recordatorios',
            Icons.notifications_outlined,
          ),
          const SizedBox(height: 8),
          Card(
            child: Column(
              children: [
                SwitchListTile(
                  value: _notif24h,
                  activeThumbColor: AppColors.primary,
                  secondary: const Icon(Icons.access_alarm),
                  title: const Text('Aviso 24 h antes'),
                  subtitle: const Text('Un día antes del vencimiento'),
                  onChanged: (v) async {
                    setState(() => _notif24h = v);
                    await _notifService.set24hEnabled(v);
                  },
                ),
                const Divider(height: 1),
                SwitchListTile(
                  value: _notif2h,
                  activeThumbColor: AppColors.primary,
                  secondary: const Icon(Icons.alarm),
                  title: const Text('Aviso 2 h antes'),
                  subtitle: const Text('Alerta de última hora'),
                  onChanged: (v) async {
                    setState(() => _notif2h = v);
                    await _notifService.set2hEnabled(v);
                  },
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // ── Carrera ─────────────────────────────────────────
          _sectionHeader(context, 'Cuenta', Icons.manage_accounts_outlined),
          const SizedBox(height: 8),
          Card(
            child: ListTile(
              leading: const Icon(Icons.logout, color: AppColors.error),
              title: const Text('Salir de la carrera'),
              subtitle: const Text('Volver a la pantalla de acceso'),
              onTap: _logout,
            ),
          ),

          const SizedBox(height: 24),

          // ── Legal / Acerca de ────────────────────────────────
          _sectionHeader(context, 'Información', Icons.info_outline),
          const SizedBox(height: 8),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(
                    Icons.privacy_tip,
                    color: AppColors.primary,
                  ),
                  title: const Text('Política de Privacidad'),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                  onTap: () => _launchUrl(
                    'https://bitacora-2d643.web.app/policies/privacy_policy.html',
                    'Política de Privacidad',
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(
                    Icons.description,
                    color: AppColors.primary,
                  ),
                  title: const Text('Términos de Uso'),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                  onTap: () => _launchUrl(
                    'https://bitacora-2d643.web.app/policies/terms_of_use.html',
                    'Términos de Uso',
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.school, color: AppColors.primary),
                  title: const Text('Acerca de Bitácora'),
                  subtitle: const Text('Versión 1.0.0'),
                  trailing: const Icon(Icons.info_outline, size: 16),
                  onTap: () => _showAboutDialog(context),
                ),
              ],
            ),
          ),

          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _sectionHeader(BuildContext context, String label, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 18, color: AppColors.textSecondary),
        const SizedBox(width: 8),
        Text(
          label.toUpperCase(),
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.2,
            color: AppColors.textSecondary,
          ),
        ),
      ],
    );
  }

  Future<void> _reloadSubjects() async {
    try {
      await _careerService.reloadCareerWithUpdatedSubjects();
      _showSnack('✅ Materias actualizadas correctamente', Colors.green);
      setState(() {
        _selectedCareer = _careerService.getSelectedCareer();
      });
    } catch (e) {
      _showSnack('Error al actualizar materias: $e', AppColors.error);
    }
  }

  Future<void> _logout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Salir de la carrera'),
        content: const Text(
          '¿Seguro que quieres salir? Tendrás que ingresar la clave de acceso nuevamente.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Salir',
              style: TextStyle(color: AppColors.error),
            ),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    await _careerService.clearSelectedCareer();
    setState(() => _selectedCareer = null);
  }

  Future<void> _launchUrl(String url, String title) async {
    final uri = Uri.parse(url);
    try {
      if (!await canLaunchUrl(uri)) {
        _showSnack(
          'No se puede abrir $title. Verifica tu conexión.',
          Colors.orange,
        );
        return;
      }
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      _showSnack('Error al abrir $title', AppColors.error);
    }
  }

  void _showSnack(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(msg), backgroundColor: color));
  }

  void _showAboutDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.school, color: AppColors.primary),
            SizedBox(width: 8),
            Text('Acerca de Bitácora'),
          ],
        ),
        content: const SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Bitácora',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
              ),
              SizedBox(height: 4),
              Text(
                'Versión 1.0.0',
                style: TextStyle(color: AppColors.textSecondary),
              ),
              SizedBox(height: 16),
              Text(
                'Aplicación diseñada para estudiantes universitarios. '
                'Organiza tus tareas, exámenes y trabajos por materia, '
                'con soporte offline y recordatorios inteligentes.',
              ),
              SizedBox(height: 16),
              Text(
                'Características:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 8),
              Text('• Gestión de tareas por materia y carrera'),
              Text('• Recordatorios 24 h y 2 h antes del vencimiento'),
              Text('• Funciona sin conexión a internet'),
              Text('• Sincronización automática en la nube'),
              Text('• Modo oscuro'),
              SizedBox(height: 16),
              Text(
                'Desarrollado por:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 4),
              Text('Operonte'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
  }
}
