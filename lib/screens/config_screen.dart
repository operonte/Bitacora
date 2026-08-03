import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:provider/provider.dart';
import '../colors.dart';
import '../models/career_model.dart';
import '../auth_service.dart';
import '../services/career_service.dart';
import '../notification_service.dart';
import '../providers/app_state.dart';
import '../providers/theme_provider.dart';
import 'onboarding_screen.dart';

class ConfigScreen extends StatefulWidget {
  const ConfigScreen({super.key});

  @override
  State<ConfigScreen> createState() => _ConfigScreenState();
}

class _ConfigScreenState extends State<ConfigScreen> with WidgetsBindingObserver {
  final CareerService _careerService = CareerService();
  final NotificationService _notifService = NotificationService();
  final AuthService _authService = AuthService();
  Career? _selectedCareer;
  List<Career> _careers = [];
  bool _notif24h = true;
  bool _notif2h = true;
  bool _notifMeeting = true;

  // Estado real a nivel de sistema operativo — los switches de arriba solo
  // controlan la preferencia dentro de la app, pero si Android bloqueó el
  // permiso o la app está bajo optimización de batería, el recordatorio
  // jamás llega aunque el switch esté prendido.
  PermissionStatus? _notifPermStatus;
  PermissionStatus? _alarmPermStatus;
  PermissionStatus? _batteryPermStatus;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadData();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // El usuario puede volver de Ajustes del sistema tras cambiar un
    // permiso: refrescar el estado mostrado sin que tenga que reabrir.
    if (state == AppLifecycleState.resumed) {
      _loadPermissionStatuses();
    }
  }

  Future<void> _loadPermissionStatuses() async {
    if (kIsWeb) return;
    final notif = await Permission.notification.status;
    final alarm = await Permission.scheduleExactAlarm.status;
    final battery = await Permission.ignoreBatteryOptimizations.status;
    if (mounted) {
      setState(() {
        _notifPermStatus = notif;
        _alarmPermStatus = alarm;
        _batteryPermStatus = battery;
      });
    }
  }

  Future<void> _loadData() async {
    await _loadPermissionStatuses();
    // Sincronizar automáticamente materias y profesores desde Supabase
    try {
      await _careerService.reloadCareerWithUpdatedSubjects();
    } catch (_) {}

    final career = _careerService.getSelectedCareer();
    final careers = _careerService.getCareers();
    final n24 = await _notifService.is24hEnabled;
    final n2 = await _notifService.is2hEnabled;
    final nMeeting = await _notifService.isMeetingReminderEnabled;
    if (mounted) {
      setState(() {
        _selectedCareer = career;
        _careers = careers;
        _notif24h = n24;
        _notif2h = n2;
        _notifMeeting = nMeeting;
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
                children: [
                  const ListTile(
                    title: Text(
                      'Modo de Tema',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                  ),
                  ...AppThemeMode.values.map((mode) {
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
                        color: selected ? themeProvider.primaryColor : null,
                      ),
                      title: Text(labels[mode]!),
                      trailing: selected
                          ? Icon(
                              Icons.check_circle,
                              color: themeProvider.primaryColor,
                            )
                          : null,
                      onTap: () => themeProvider.setMode(mode),
                    );
                  }),
                  const Divider(height: 16),
                  const ListTile(
                    title: Text(
                      'Paleta de Colores',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                  ),
                  ListTile(
                    leading: const CircleAvatar(
                      backgroundColor: AppColors.primaryTeal,
                      radius: 12,
                    ),
                    title: const Text('Por defecto'),
                    trailing: themeProvider.palette == AppColorPalette.teal
                        ? Icon(Icons.check_circle, color: themeProvider.primaryColor)
                        : null,
                    onTap: () => themeProvider.setPalette(AppColorPalette.teal),
                  ),
                  ListTile(
                    leading: const CircleAvatar(
                      backgroundColor: AppColors.primaryEmerald,
                      radius: 12,
                    ),
                    title: const Text('Verde'),
                    trailing: themeProvider.palette == AppColorPalette.emerald
                        ? Icon(Icons.check_circle, color: themeProvider.primaryColor)
                        : null,
                    onTap: () => themeProvider.setPalette(AppColorPalette.emerald),
                  ),
                  ListTile(
                    leading: const CircleAvatar(
                      backgroundColor: AppColors.primaryFeminine,
                      radius: 12,
                    ),
                    title: const Text('Rosa'),
                    trailing: themeProvider.palette == AppColorPalette.feminine
                        ? Icon(Icons.check_circle, color: themeProvider.primaryColor)
                        : null,
                    onTap: () => themeProvider.setPalette(AppColorPalette.feminine),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 24),

          // ── Estudias dos o más carreras ───────────────────────
          _sectionHeader(context, 'Estudias dos o más carreras', Icons.school_outlined),
          const SizedBox(height: 8),
          Card(
            child: Column(
              children: [
                ..._careers.map(_careerTile),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.add_circle_outline,
                      color: AppColors.primary),
                  title: const Text('Unirse a otra carrera'),
                  subtitle: const Text('Ingresar una clave de acceso'),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                  onTap: _joinCareerDialog,
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // ── Recordatorios ───────────────────────────────────
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
                    final tasks = context.read<AppState>().tasks;
                    setState(() => _notif24h = v);
                    await _notifService.set24hEnabled(v);
                    await _notifService.syncAllTaskReminders(tasks);
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
                    final tasks = context.read<AppState>().tasks;
                    setState(() => _notif2h = v);
                    await _notifService.set2hEnabled(v);
                    await _notifService.syncAllTaskReminders(tasks);
                  },
                ),
                const Divider(height: 1),
                SwitchListTile(
                  value: _notifMeeting,
                  activeThumbColor: AppColors.primary,
                  secondary: const Icon(Icons.video_camera_front_outlined),
                  title: const Text('Aviso de reuniones'),
                  subtitle: const Text('La mañana del día y 2 horas antes'),
                  onChanged: (v) async {
                    setState(() => _notifMeeting = v);
                    await _notifService.setMeetingReminderEnabled(v);
                  },
                ),
              ],
            ),
          ),

          if (!kIsWeb) ...[
            const SizedBox(height: 12),
            _buildPermissionStatusCard(),
          ],

          const SizedBox(height: 24),

          // ── Tutorial ─────────────────────────────────────────
          _sectionHeader(context, 'Tutorial', Icons.auto_stories_outlined),
          const SizedBox(height: 8),
          Card(
            child: ListTile(
              leading: const Icon(Icons.play_circle_outline, color: AppColors.primary),
              title: const Text('Ver tutorial de inicio'),
              subtitle: const Text('Repasar las pantallas iniciales de la app'),
              trailing: const Icon(Icons.arrow_forward_ios, size: 16),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => OnboardingScreen(
                      onFinished: () => Navigator.pop(context),
                    ),
                  ),
                );
              },
            ),
          ),

          const SizedBox(height: 24),

          // ── Cuenta ──────────────────────────────────────────
          _sectionHeader(context, 'Cuenta', Icons.manage_accounts_outlined),
          const SizedBox(height: 8),
          Card(
            child: Column(
              children: [
                _accountTile(),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.school_outlined, color: AppColors.warning),
                  title: const Text('Salir de todas las carreras'),
                  subtitle: const Text('Volver a la selección de carrera'),
                  onTap: _logout,
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.exit_to_app, color: AppColors.error),
                  title: const Text('Cerrar sesión de la cuenta'),
                  subtitle: const Text('Cerrar Sesión'),
                  onTap: _signOutAccount,
                ),
              ],
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

  Widget _accountTile() {
    final User? user = _authService.currentUser;

    if (user == null) {
      return const ListTile(
        leading: CircleAvatar(child: Icon(Icons.person_outline)),
        title: Text('Sin sesión iniciada'),
        subtitle: Text('No hay una cuenta conectada'),
      );
    }

    final name = (_authService.userDisplayName?.trim().isNotEmpty ?? false)
        ? _authService.userDisplayName!.trim()
        : 'Sin nombre';
    final email = user.email ?? 'Sin correo';
    final photoUrl = _authService.userPhotoURL;
    final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: Theme.of(context).primaryColor,
        foregroundImage:
            (photoUrl != null && photoUrl.isNotEmpty) ? NetworkImage(photoUrl) : null,
        child: Text(
          initial,
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
      ),
      title: Text(name, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text('$email • Toca para editar perfil'),
      trailing: const Icon(Icons.edit_outlined, size: 20),
      onTap: _editProfileDialog,
    );
  }

  Future<void> _editProfileDialog() async {
    final user = _authService.currentUser;
    if (user == null) return;

    final nameController = TextEditingController(text: _authService.userDisplayName ?? '');
    final photoController = TextEditingController(text: _authService.userPhotoURL ?? '');

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.person_pin, color: AppColors.primary),
            SizedBox(width: 8),
            Text('Editar Perfil'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(
                labelText: 'Nombre completo (opcional)',
                prefixIcon: Icon(Icons.person),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: photoController,
              decoration: const InputDecoration(
                labelText: 'URL Foto de perfil (opcional)',
                prefixIcon: Icon(Icons.link),
                hintText: 'https://ejemplo.com/mi_foto.jpg',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () async {
              try {
                await Supabase.instance.client.auth.updateUser(
                  UserAttributes(
                    data: {
                      'full_name': nameController.text.trim(),
                      'avatar_url': photoController.text.trim(),
                    },
                  ),
                );
                if (ctx.mounted) Navigator.pop(ctx);
                setState(() {});
                _showSnack('✅ Perfil actualizado correctamente', Colors.green);
              } catch (e) {
                _showSnack('Error al actualizar perfil: $e', AppColors.error);
              }
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
  }

  Widget _careerTile(Career career) {
    final isActive = _selectedCareer?.id == career.id;
    return ListTile(
      leading: Icon(
        isActive ? Icons.radio_button_checked : Icons.radio_button_off,
        color: isActive ? AppColors.primary : AppColors.textSecondary,
      ),
      title: Text(
        career.name,
        style: TextStyle(
          fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
        ),
      ),
      subtitle: Text(isActive ? 'Carrera activa' : 'Tocar para activar'),
      trailing: _careers.length > 1
          ? IconButton(
              icon: const Icon(Icons.logout, color: AppColors.error, size: 20),
              tooltip: 'Salir de esta carrera',
              onPressed: () => _leaveCareer(career),
            )
          : null,
      onTap: isActive ? null : () => _setActiveCareer(career),
    );
  }

  Future<void> _setActiveCareer(Career career) async {
    await _careerService.setActiveCareer(career.id);
    await _loadData();
  }

  Future<void> _joinCareerDialog() async {
    // Refrescar las carreras creadas en el admin para poder validar su clave.
    await _careerService.loadRemoteCareers();

    final controller = TextEditingController();
    String? errorText;

    if (!mounted) return;
    final added = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Unirse a otra carrera'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Ingresa la clave de acceso de la carrera o grupo al que quieres unirte.',
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: 'Clave de acceso',
                  border: const OutlineInputBorder(),
                  errorText: errorText,
                ),
                onSubmitted: (_) {},
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar'),
            ),
            TextButton(
              onPressed: () async {
                final key = controller.text.trim();
                Career? career;
                try {
                  // Consulta al servidor: la clave ya no viaja en la app.
                  career = await _careerService.validateAccessKey(key);
                } catch (e) {
                  setLocal(() => errorText = 'Sin conexión para validar la clave');
                  return;
                }
                if (career == null) {
                  setLocal(() => errorText = 'Clave de acceso inválida');
                  return;
                }
                if (_careerService.isMember(career.id)) {
                  setLocal(() => errorText = 'Ya perteneces a esta carrera');
                  return;
                }
                await _careerService.addCareer(career);
                if (ctx.mounted) Navigator.pop(ctx, true);
              },
              child: const Text('Unirse'),
            ),
          ],
        ),
      ),
    );

    if (added == true) {
      await _loadData();
      _showSnack('✅ Te uniste a la carrera', Colors.green);
    }
  }

  Future<void> _leaveCareer(Career career) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Salir de la carrera'),
        content: Text(
          '¿Seguro que quieres salir de "${career.name}"? Dejarás de ver sus tareas. '
          'Podrás volver a unirte con la clave de acceso.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Salir', style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    await _careerService.removeCareer(career.id);

    // Si era la última carrera, volver para que el routing muestre el acceso.
    if (_careerService.getCareers().isEmpty && mounted) {
      Navigator.of(context).pop();
      return;
    }
    await _loadData();
    _showSnack('Saliste de ${career.name}', Colors.orange);
  }

  Future<void> _fixPermission(Permission permission) async {
    final current = await permission.status;
    if (current.isPermanentlyDenied) {
      await openAppSettings();
    } else {
      await permission.request();
    }
    await _loadPermissionStatuses();
  }

  Widget _buildPermissionStatusCard() {
    final rows = <Widget>[];

    void addRow({
      required String title,
      required String okSubtitle,
      required String badSubtitle,
      required PermissionStatus? status,
      required Permission permission,
    }) {
      if (rows.isNotEmpty) rows.add(const Divider(height: 1));
      final granted = status?.isGranted ?? false;
      rows.add(
        ListTile(
          leading: Icon(
            granted ? Icons.check_circle : Icons.error_outline,
            color: granted ? AppColors.success : AppColors.error,
          ),
          title: Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          subtitle: Text(
            granted ? okSubtitle : badSubtitle,
            style: const TextStyle(fontSize: 12),
          ),
          trailing: granted
              ? null
              : TextButton(
                  onPressed: () => _fixPermission(permission),
                  child: const Text('Arreglar'),
                ),
        ),
      );
    }

    addRow(
      title: 'Permiso de notificaciones',
      okSubtitle: 'Concedido',
      badSubtitle: 'Sin esto, ningún aviso llega — actívalo',
      status: _notifPermStatus,
      permission: Permission.notification,
    );
    addRow(
      title: 'Alarmas exactas',
      okSubtitle: 'Concedido',
      badSubtitle: 'Los avisos pueden llegar tarde o no llegar a tiempo',
      status: _alarmPermStatus,
      permission: Permission.scheduleExactAlarm,
    );
    addRow(
      title: 'Optimización de batería',
      okSubtitle: 'Exenta — la app puede avisar en segundo plano',
      badSubtitle: 'El sistema puede matar la app y perder el aviso',
      status: _batteryPermStatus,
      permission: Permission.ignoreBatteryOptimizations,
    );

    final allGranted = [_notifPermStatus, _alarmPermStatus, _batteryPermStatus]
        .every((s) => s?.isGranted ?? false);

    return Card(
      color: allGranted ? null : AppColors.error.withValues(alpha: 0.06),
      child: Column(
        children: [
          ListTile(
            dense: true,
            leading: Icon(
              allGranted ? Icons.verified_outlined : Icons.warning_amber_rounded,
              color: allGranted ? AppColors.success : AppColors.error,
            ),
            title: Text(
              allGranted
                  ? 'Notificaciones listas para avisarte'
                  : 'Revisa esto para no perderte avisos',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
            ),
          ),
          const Divider(height: 1),
          ...rows,
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
    if (mounted) {
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
  }

  Future<void> _signOutAccount() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cerrar sesión'),
        content: const Text(
          '¿Seguro que quieres cerrar sesión de tu cuenta? Se borrará la caché local y deberás iniciar sesión nuevamente.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Cerrar sesión',
              style: TextStyle(color: AppColors.error),
            ),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    await _authService.signOut();
    await _careerService.clearSelectedCareer();
    if (mounted) {
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
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
