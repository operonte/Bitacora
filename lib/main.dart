import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'firebase_options.dart';
import 'pending_tasks_screen.dart';
import 'overdue_tasks_screen.dart';
import 'delivered_tasks_screen.dart';
import 'notification_service.dart';
import 'colors.dart';
import 'auth_service.dart';
import 'auth_screen.dart';
import 'config_screen.dart';
import 'career_selection_screen.dart';
import 'onboarding_screen.dart';
import 'services/local_cache_service.dart';
import 'services/sync_service.dart';
import 'services/career_service.dart';
import 'services/task_progress_service.dart';
import 'providers/app_state.dart';
import 'providers/theme_provider.dart';
import 'utils/logger.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Hive.initFlutter();

  final cacheService = LocalCacheService();
  await cacheService.initialize();

  await TaskProgressService().initialize();

  final careerService = CareerService();
  await careerService.initialize();

  final themeProvider = ThemeProvider();
  await themeProvider.initialize();

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  final syncService = SyncService();
  syncService.initialize();

  if (!kIsWeb) {
    await _requestPermissions();
    final notificationService = NotificationService();
    await notificationService.initialize();
    await notificationService.scheduleDailyReminder();
  }

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AppState()),
        ChangeNotifierProvider<CareerService>.value(value: careerService),
        ChangeNotifierProvider<ThemeProvider>.value(value: themeProvider),
      ],
      child: const BitacoraApp(),
    ),
  );
}

Future<void> _requestPermissions() async {
  if (kIsWeb) return;

  final notificationStatus = await Permission.notification.request();
  Logger.info(
    'Permiso notificaciones: ${notificationStatus.isGranted ? 'Concedido' : 'Denegado'}',
    tag: 'Permisos',
  );

  if (await Permission.scheduleExactAlarm.isGranted) {
    Logger.info('Permiso alarmas exactas: Concedido', tag: 'Permisos');
  } else {
    final alarmStatus = await Permission.scheduleExactAlarm.request();
    Logger.info(
      'Permiso alarmas exactas: ${alarmStatus.isGranted ? 'Concedido' : 'Denegado'}',
      tag: 'Permisos',
    );
  }
}

class BitacoraApp extends StatelessWidget {
  const BitacoraApp({super.key});

  @override
  Widget build(BuildContext context) {
    final themeProvider = context.watch<ThemeProvider>();

    return MaterialApp(
      title: 'Bitácora',
      themeMode: themeProvider.themeMode,
      theme: _buildLightTheme(),
      darkTheme: _buildDarkTheme(),
      home: const _AppEntry(),
    );
  }

  ThemeData _buildLightTheme() {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.primary,
        primary: AppColors.primary,
        secondary: AppColors.accent,
        surface: AppColors.surface,
        error: AppColors.error,
        brightness: Brightness.light,
      ),
      scaffoldBackgroundColor: AppColors.background,
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: Colors.white,
          fontSize: 20,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.3,
        ),
        iconTheme: IconThemeData(color: Colors.white),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        margin: EdgeInsets.zero,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          elevation: 2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle:
              const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
        ),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 4,
        shape: CircleBorder(),
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        focusedBorder: const OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
          borderSide: BorderSide(color: AppColors.primary, width: 2),
        ),
        filled: true,
        fillColor: Colors.white,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: Colors.white,
        selectedItemColor: AppColors.primary,
        unselectedItemColor: AppColors.textSecondary,
        elevation: 12,
        type: BottomNavigationBarType.fixed,
        selectedLabelStyle:
            TextStyle(fontWeight: FontWeight.w700, fontSize: 11),
        unselectedLabelStyle: TextStyle(fontSize: 11),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: AppColors.primary.withValues(alpha: 0.08),
        labelStyle: const TextStyle(
            color: AppColors.primary, fontWeight: FontWeight.w600),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
    );
  }

  ThemeData _buildDarkTheme() {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.primary,
        primary: AppColors.primaryLight,
        secondary: AppColors.accent,
        surface: AppColors.darkSurface,
        error: AppColors.error,
        brightness: Brightness.dark,
      ),
      scaffoldBackgroundColor: AppColors.darkBackground,
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.darkAppBar,
        foregroundColor: AppColors.darkOnSurface,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: AppColors.darkOnSurface,
          fontSize: 20,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.3,
        ),
        iconTheme: IconThemeData(color: AppColors.darkOnSurface),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: AppColors.darkCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        margin: EdgeInsets.zero,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          elevation: 2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle:
              const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
        ),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 4,
        shape: CircleBorder(),
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.darkTextSecondary),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.darkTextSecondary),
        ),
        focusedBorder: const OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
          borderSide: BorderSide(color: AppColors.primaryLight, width: 2),
        ),
        filled: true,
        fillColor: AppColors.darkSurface,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: AppColors.darkSurface,
        selectedItemColor: AppColors.primaryLight,
        unselectedItemColor: AppColors.darkTextSecondary,
        elevation: 12,
        type: BottomNavigationBarType.fixed,
        selectedLabelStyle:
            TextStyle(fontWeight: FontWeight.w700, fontSize: 11),
        unselectedLabelStyle: TextStyle(fontSize: 11),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: AppColors.primaryLight.withValues(alpha: 0.15),
        labelStyle: const TextStyle(
            color: AppColors.primaryLight, fontWeight: FontWeight.w600),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
    );
  }
}

// ─── Punto de entrada: onboarding → auth → app ───────────────────────────────

class _AppEntry extends StatefulWidget {
  const _AppEntry();

  @override
  State<_AppEntry> createState() => _AppEntryState();
}

class _AppEntryState extends State<_AppEntry> {
  bool? _onboardingDone;

  @override
  void initState() {
    super.initState();
    _checkOnboarding();
  }

  Future<void> _checkOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    final done = prefs.getBool('onboarding_done') ?? false;
    setState(() => _onboardingDone = done);
  }

  @override
  Widget build(BuildContext context) {
    if (_onboardingDone == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (!_onboardingDone!) {
      return OnboardingScreen(
        onFinished: () => setState(() => _onboardingDone = true),
      );
    }

    return const MainScreen();
  }
}

// ─── Pantalla principal ───────────────────────────────────────────────────────

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  _MainScreenState createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _currentIndex = 0;
  final AuthService _authService = AuthService();
  final SyncService _syncService = SyncService();
  final CareerService _careerService = CareerService();
  final List<Widget> _screens = const [
    PendingTasksScreen(),
    OverdueTasksScreen(),
    DeliveredTasksScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: _authService.authStateChanges,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(
              child: CircularProgressIndicator(
                valueColor:
                    AlwaysStoppedAnimation<Color>(AppColors.primary),
              ),
            ),
          );
        }

        if (!snapshot.hasData || snapshot.data == null) {
          return const AuthScreen();
        }

        return Consumer<CareerService>(
          builder: (context, careerService, child) {
            final career = careerService.getSelectedCareer();

            if (career == null) {
              return const CareerSelectionScreen();
            }

            return Scaffold(
              appBar: AppBar(
                title: Text('Bitácora — ${career.name}'),
                actions: [
                  IconButton(
                    icon: const Icon(Icons.logout),
                    onPressed: () async => await _authService.signOut(),
                    tooltip: 'Cerrar sesión',
                  ),
                  // Indicador de sincronización
                  StreamBuilder<SyncStatus>(
                    stream: _syncService.statusStream,
                    initialData: SyncStatus.idle,
                    builder: (context, snap) {
                      final status = snap.data ?? SyncStatus.idle;

                      if (status == SyncStatus.syncing) {
                        return const Padding(
                          padding: EdgeInsets.all(8),
                          child: SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                  Colors.white),
                            ),
                          ),
                        );
                      } else if (_syncService.hasPendingChanges()) {
                        return IconButton(
                          icon: const Icon(Icons.cloud_off,
                              color: Colors.orange),
                          onPressed: () async {
                            final result = await _syncService.forceSync();
                            if (mounted) {
                              final msg = switch (result) {
                                SyncResult.success => '✅ Datos sincronizados',
                                SyncResult.noConnection =>
                                  '⚠️ Sin conexión a internet',
                                SyncResult.nothingToSync =>
                                  'ℹ️ No hay cambios pendientes',
                                _ => '❌ Error en sincronización',
                              };
                              ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text(msg)));
                            }
                          },
                          tooltip: 'Sincronizar',
                        );
                      }
                      return const SizedBox.shrink();
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.settings),
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const ConfigScreen()),
                    ),
                    tooltip: 'Configuración',
                  ),
                ],
              ),
              drawer: Drawer(
                child: ListView(
                  padding: EdgeInsets.zero,
                  children: [
                    DrawerHeader(
                      decoration:
                          const BoxDecoration(color: AppColors.primary),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.school,
                              size: 48, color: Colors.white),
                          const SizedBox(height: 8),
                          const Text(
                            'Bitácora',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            _authService.currentUser?.displayName ??
                                'Usuario',
                            style: const TextStyle(
                                color: Colors.white70, fontSize: 14),
                          ),
                        ],
                      ),
                    ),
                    ListTile(
                      leading: const Icon(Icons.task),
                      title: const Text('Tareas Pendientes'),
                      selected: _currentIndex == 0,
                      onTap: () {
                        Navigator.pop(context);
                        setState(() => _currentIndex = 0);
                      },
                    ),
                    ListTile(
                      leading: const Icon(Icons.history),
                      title: const Text('Tareas Vencidas'),
                      selected: _currentIndex == 1,
                      onTap: () {
                        Navigator.pop(context);
                        setState(() => _currentIndex = 1);
                      },
                    ),
                    ListTile(
                      leading: const Icon(Icons.check_circle_outline),
                      title: const Text('Tareas Entregadas'),
                      selected: _currentIndex == 2,
                      onTap: () {
                        Navigator.pop(context);
                        setState(() => _currentIndex = 2);
                      },
                    ),
                  ],
                ),
              ),
              body: IndexedStack(
                  index: _currentIndex, children: _screens),
              bottomNavigationBar: BottomNavigationBar(
                currentIndex: _currentIndex,
                onTap: (i) => setState(() => _currentIndex = i),
                items: const [
                  BottomNavigationBarItem(
                      icon: Icon(Icons.task), label: 'Pendientes'),
                  BottomNavigationBarItem(
                      icon: Icon(Icons.history), label: 'Vencidas'),
                  BottomNavigationBarItem(
                      icon: Icon(Icons.check_circle_outline),
                      label: 'Entregadas'),
                ],
              ),
            );
          },
        );
      },
    );
  }
}
