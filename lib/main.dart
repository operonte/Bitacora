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

import 'career_selection_screen.dart';
import 'onboarding_screen.dart';
import 'services/encryption_service.dart';
import 'services/local_cache_service.dart';
import 'services/sync_service.dart';
import 'services/career_service.dart';
import 'services/task_progress_service.dart';
import 'providers/app_state.dart';
import 'providers/theme_provider.dart';
import 'startup_error_screen.dart';
import 'utils/logger.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );

    await Hive.initFlutter();
    await EncryptionService.initialize();

    final cacheService = LocalCacheService();
    await cacheService.initialize();

    await TaskProgressService().initialize();

    final careerService = CareerService();
    await careerService.initialize();

    final themeProvider = ThemeProvider();
    await themeProvider.initialize();

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
  } catch (e, stack) {
    Logger.error('Error fatal en arranque', error: e, tag: 'Main');
    debugPrintStack(stackTrace: stack);
    runApp(StartupErrorScreen(error: e.toString()));
  }
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
        backgroundColor: Colors.transparent,
        foregroundColor: AppColors.onSurface,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: AppColors.onSurface,
          fontSize: 22,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.3,
        ),
        iconTheme: IconThemeData(color: AppColors.onSurface),
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
        backgroundColor: Colors.transparent,
        foregroundColor: AppColors.darkOnSurface,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: AppColors.darkOnSurface,
          fontSize: 22,
          fontWeight: FontWeight.w800,
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
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _currentIndex = 0;
  final AuthService _authService = AuthService();
  late final Stream<User?> _authStream;
  late final PageController _pageController;
  final List<Widget> _screens = const [
    PendingTasksScreen(),
    OverdueTasksScreen(),
    DeliveredTasksScreen(),
  ];

  @override
  void initState() {
    super.initState();
    _authStream = _authService.userStream;
    _pageController = PageController(initialPage: _currentIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: _authStream,
      initialData: _authService.currentUser,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            snapshot.data == null) {
          return const Scaffold(
            body: Center(
              child: CircularProgressIndicator(
                valueColor:
                    AlwaysStoppedAnimation<Color>(AppColors.primary),
              ),
            ),
          );
        }

        final user = snapshot.data;
        if (user == null) {
          return const AuthScreen();
        }

        return Consumer<CareerService>(
          builder: (context, careerService, child) {
            final career = careerService.getSelectedCareer();

            if (career == null) {
              return const CareerSelectionScreen();
            }

            return Scaffold(
              body: PageView(
                controller: _pageController,
                physics: const NeverScrollableScrollPhysics(),
                children: _screens,
              ),
              bottomNavigationBar: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surface,
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.06),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(24),
                      child: BottomNavigationBar(
                        elevation: 0,
                        backgroundColor: Colors.transparent,
                        currentIndex: _currentIndex,
                        onTap: (i) {
                          setState(() => _currentIndex = i);
                          _pageController.animateToPage(
                            i,
                            duration: const Duration(milliseconds: 300),
                            curve: Curves.easeInOutCubic,
                          );
                        },
                        items: const [
                          BottomNavigationBarItem(
                            icon: Icon(Icons.task_outlined),
                            activeIcon: Icon(Icons.task),
                            label: 'Pendientes',
                          ),
                          BottomNavigationBarItem(
                            icon: Icon(Icons.history_outlined),
                            activeIcon: Icon(Icons.history),
                            label: 'Vencidas',
                          ),
                          BottomNavigationBarItem(
                            icon: Icon(Icons.check_circle_outline),
                            activeIcon: Icon(Icons.check_circle),
                            label: 'Entregadas',
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}
