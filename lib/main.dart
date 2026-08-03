import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'screens/pending_tasks_screen.dart';
import 'screens/overdue_tasks_screen.dart';
import 'screens/delivered_tasks_screen.dart';
import 'screens/area_personal_screen.dart';
import 'widgets/mascot_companion.dart';
import 'notification_service.dart';
import 'colors.dart';
import 'auth_service.dart';
import 'screens/auth_screen.dart';

import 'screens/career_selection_screen.dart';
import 'screens/onboarding_screen.dart';
import 'services/encryption_service.dart';
import 'services/local_cache_service.dart';
import 'services/sync_service.dart';
import 'services/career_service.dart';
import 'services/meeting_service.dart';
import 'services/study_file_service.dart';
import 'services/google_drive_service.dart';
import 'services/task_progress_service.dart';
import 'services/supabase_service.dart';
import 'providers/app_state.dart';
import 'providers/theme_provider.dart';
import 'screens/startup_error_screen.dart';
import 'utils/logger.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    // Inicializar Supabase (reemplaza Firebase)
    await SupabaseService.initialize();

    Supabase.instance.client.auth.onAuthStateChange.listen((data) {
      final token = data.session?.providerToken;
      if (token != null && token.isNotEmpty) {
        GoogleDriveService.persistToken(token);
      }
    });

    await Hive.initFlutter();
    await EncryptionService.initialize();

    final cacheService = LocalCacheService();
    await cacheService.initialize();

    await TaskProgressService().initialize();

    final careerService = CareerService();
    await careerService.initialize();

    final meetingService = MeetingService();
    await meetingService.init();
    // Limpia las reuniones puntuales ya vencidas. Es irreversible, ver
    // MeetingService.pastMeetingRetention.
    await meetingService.purgePastMeetings();

    final studyFileService = StudyFileService();
    await studyFileService.init();

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
          ChangeNotifierProvider<MeetingService>.value(value: meetingService),
          ChangeNotifierProvider<StudyFileService>.value(value: studyFileService),
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

  // Sin esto, algunos fabricantes (Xiaomi, Samsung, Huawei, etc.) matan la
  // app en segundo plano y los recordatorios programados no llegan a sonar.
  if (await Permission.ignoreBatteryOptimizations.isGranted) {
    Logger.info('Permiso optimización de batería: Concedido', tag: 'Permisos');
  } else {
    final batteryStatus = await Permission.ignoreBatteryOptimizations.request();
    Logger.info(
      'Permiso optimización de batería: ${batteryStatus.isGranted ? 'Concedido' : 'Denegado'}',
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
      theme: _buildLightTheme(themeProvider),
      darkTheme: _buildDarkTheme(themeProvider),
      home: const _AppEntry(),
    );
  }

  /// Tipografía: Atkinson Hyperlegible para texto general (muy legible,
  /// pensada para lectura prolongada) y Crimson Pro para títulos/encabezados
  /// (serif académica, le da identidad propia frente al Roboto por defecto).
  TextTheme _appTextTheme(Brightness brightness) {
    final base = brightness == Brightness.light
        ? ThemeData.light().textTheme
        : ThemeData.dark().textTheme;
    final onColor =
        brightness == Brightness.light ? AppColors.onSurface : AppColors.darkOnSurface;

    return GoogleFonts.atkinsonHyperlegibleTextTheme(base).copyWith(
      displayLarge: GoogleFonts.crimsonPro(textStyle: base.displayLarge, color: onColor, fontWeight: FontWeight.w700),
      displayMedium: GoogleFonts.crimsonPro(textStyle: base.displayMedium, color: onColor, fontWeight: FontWeight.w700),
      displaySmall: GoogleFonts.crimsonPro(textStyle: base.displaySmall, color: onColor, fontWeight: FontWeight.w700),
      headlineLarge: GoogleFonts.crimsonPro(textStyle: base.headlineLarge, color: onColor, fontWeight: FontWeight.w700),
      headlineMedium: GoogleFonts.crimsonPro(textStyle: base.headlineMedium, color: onColor, fontWeight: FontWeight.w700),
      headlineSmall: GoogleFonts.crimsonPro(textStyle: base.headlineSmall, color: onColor, fontWeight: FontWeight.w600),
      titleLarge: GoogleFonts.crimsonPro(textStyle: base.titleLarge, color: onColor, fontWeight: FontWeight.w600),
    );
  }

  ThemeData _buildLightTheme(ThemeProvider provider) {
    final primary = provider.primaryColor;
    final accent = provider.accentColor;

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      primaryColor: primary,
      colorScheme: ColorScheme.fromSeed(
        seedColor: primary,
        primary: primary,
        secondary: accent,
        surface: AppColors.surface,
        onSurface: AppColors.onSurface,
        error: AppColors.error,
        brightness: Brightness.light,
      ),
      textTheme: _appTextTheme(Brightness.light),
      scaffoldBackgroundColor: AppColors.background,
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: AppColors.onSurface,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: GoogleFonts.crimsonPro(
          color: AppColors.onSurface,
          fontSize: 24,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.2,
        ),
        iconTheme: const IconThemeData(color: AppColors.onSurface),
      ),
      cardTheme: CardThemeData(
        elevation: 2,
        shadowColor: primary.withValues(alpha: 0.12),
        surfaceTintColor: Colors.transparent,
        color: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        margin: EdgeInsets.zero,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: Colors.white,
          elevation: 2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle:
              const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: primary,
        foregroundColor: Colors.white,
        elevation: 4,
        shape: const CircleBorder(),
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.borderLight),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.borderLight),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: const BorderRadius.all(Radius.circular(12)),
          borderSide: BorderSide(color: primary, width: 2),
        ),
        labelStyle: const TextStyle(color: AppColors.textSecondary, fontSize: 14),
        hintStyle: const TextStyle(color: AppColors.textHint, fontSize: 14),
        filled: true,
        fillColor: Colors.white,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: Colors.white,
        selectedItemColor: primary,
        unselectedItemColor: AppColors.textSecondary,
        elevation: 12,
        type: BottomNavigationBarType.fixed,
        selectedLabelStyle:
            const TextStyle(fontWeight: FontWeight.w700, fontSize: 11),
        unselectedLabelStyle: const TextStyle(fontSize: 11),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: primary.withValues(alpha: 0.08),
        labelStyle: TextStyle(
            color: primary, fontWeight: FontWeight.w600),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
    );
  }

  ThemeData _buildDarkTheme(ThemeProvider provider) {
    final primaryLight = provider.primaryLightColor;
    final accent = provider.accentColor;

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      primaryColor: provider.primaryColor,
      colorScheme: ColorScheme.fromSeed(
        seedColor: provider.primaryColor,
        primary: primaryLight,
        secondary: accent,
        surface: AppColors.darkSurface,
        onSurface: AppColors.darkOnSurface,
        error: AppColors.error,
        brightness: Brightness.dark,
      ),
      textTheme: _appTextTheme(Brightness.dark),
      scaffoldBackgroundColor: AppColors.darkBackground,
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: AppColors.darkOnSurface,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: GoogleFonts.crimsonPro(
          color: AppColors.darkOnSurface,
          fontSize: 24,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.2,
        ),
        iconTheme: const IconThemeData(color: AppColors.darkOnSurface),
      ),
      cardTheme: CardThemeData(
        elevation: 2,
        shadowColor: Colors.black.withValues(alpha: 0.4),
        surfaceTintColor: Colors.transparent,
        color: AppColors.darkCard,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        margin: EdgeInsets.zero,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: provider.primaryColor,
          foregroundColor: Colors.white,
          elevation: 2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle:
              const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: provider.primaryColor,
        foregroundColor: Colors.white,
        elevation: 4,
        shape: const CircleBorder(),
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.darkBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.darkBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: const BorderRadius.all(Radius.circular(12)),
          borderSide: BorderSide(color: primaryLight, width: 2),
        ),
        labelStyle: const TextStyle(color: AppColors.darkTextSecondary, fontSize: 14),
        hintStyle: const TextStyle(color: AppColors.darkTextHint, fontSize: 14),
        prefixIconColor: AppColors.darkTextSecondary,
        suffixIconColor: AppColors.darkTextSecondary,
        filled: true,
        fillColor: AppColors.darkSurface,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: AppColors.darkSurface,
        selectedItemColor: primaryLight,
        unselectedItemColor: AppColors.darkTextSecondary,
        elevation: 12,
        type: BottomNavigationBarType.fixed,
        selectedLabelStyle:
            const TextStyle(fontWeight: FontWeight.w700, fontSize: 11),
        unselectedLabelStyle: const TextStyle(fontSize: 11),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: AppColors.darkSurface,
        selectedColor: primaryLight.withValues(alpha: 0.25),
        labelStyle: const TextStyle(
            color: AppColors.darkOnSurface, fontWeight: FontWeight.w600),
        secondaryLabelStyle: TextStyle(
            color: primaryLight, fontWeight: FontWeight.w700),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: AppColors.darkBorder),
        ),
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
    AreaPersonalScreen(),
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
              body: Stack(
                children: [
                  PageView(
                    controller: _pageController,
                    physics: const NeverScrollableScrollPhysics(),
                    children: _screens,
                  ),
                  const Positioned(
                    left: 16,
                    bottom: 16,
                    child: MascotCompanion(),
                  ),
                ],
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
                            icon: Icon(Icons.assignment_outlined),
                            activeIcon: Icon(Icons.assignment),
                            label: 'Pendientes',
                          ),
                          BottomNavigationBarItem(
                            icon: Icon(Icons.access_time_outlined),
                            activeIcon: Icon(Icons.access_time),
                            label: 'Vencidas',
                          ),
                          BottomNavigationBarItem(
                            icon: Icon(Icons.check_circle_outline),
                            activeIcon: Icon(Icons.check_circle),
                            label: 'Entregadas',
                          ),
                          BottomNavigationBarItem(
                            icon: Icon(Icons.person_outline),
                            activeIcon: Icon(Icons.person),
                            label: 'Mi área',
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
