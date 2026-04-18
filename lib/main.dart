import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'firebase_options.dart';
import 'pending_tasks_screen.dart';
import 'overdue_tasks_screen.dart';
import 'delivered_tasks_screen.dart';
import 'notification_service.dart';
import 'colors.dart';
import 'auth_service.dart';
import 'auth_screen.dart';
import 'config_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Inicializar Firebase
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  
  // Solicitar permisos solo en móvil (no en web)
  if (!kIsWeb) {
    await _requestPermissions();
    
    // Inicializar notificaciones solo en móvil
    final notificationService = NotificationService();
    await notificationService.initialize();
    
    // Programar recordatorio diario solo en móvil
    await notificationService.scheduleDailyReminder();
  }
  
  runApp(const BitacoraApp());
}

Future<void> _requestPermissions() async {
  // Solo solicitar permisos en plataformas móviles
  if (kIsWeb) return;
  
  // Solicitar permiso de notificaciones
  final notificationStatus = await Permission.notification.request();
  print('Permiso de notificaciones: ${notificationStatus.isGranted ? 'Concedido' : 'Denegado'}');
  
  // Solicitar permiso de alarmas exactas (Android 12+)
  if (await Permission.scheduleExactAlarm.isGranted) {
    print('Permiso de alarmas exactas: Concedido');
  } else {
    final alarmStatus = await Permission.scheduleExactAlarm.request();
    print('Permiso de alarmas exactas: ${alarmStatus.isGranted ? 'Concedido' : 'Denegado'}');
  }
}

class BitacoraApp extends StatelessWidget {
  const BitacoraApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Bitácora',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        primaryColor: AppColors.primary,
        scaffoldBackgroundColor: AppColors.background,
        appBarTheme: const AppBarTheme(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          elevation: 2,
        ),
        cardTheme: CardThemeData(
          elevation: 4,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
      ),
      home: const MainScreen(),
    );
  }
}

class MainScreen extends StatefulWidget {
  const MainScreen({Key? key}) : super(key: key);

  @override
  _MainScreenState createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _currentIndex = 0;
  final AuthService _authService = AuthService();
  final List<Widget> _screens = [
    const PendingTasksScreen(),
    const OverdueTasksScreen(),
    const DeliveredTasksScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    // Usar StreamBuilder para escuchar cambios en el estado de autenticación
    return StreamBuilder<User?>(
      stream: _authService.authStateChanges,
      builder: (context, snapshot) {
        // Mostrar loading mientras se verifica el estado inicial
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
              ),
            ),
          );
        }

        // Si no hay usuario autenticado, mostrar pantalla de login
        if (!snapshot.hasData || snapshot.data == null) {
          return const AuthScreen();
        }

        // Usuario autenticado - mostrar pantalla principal
        return Scaffold(
          appBar: AppBar(
            title: const Text('Bitácora'),
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            actions: [
              IconButton(
                icon: const Icon(Icons.logout),
                onPressed: _signOut,
                tooltip: 'Cerrar sesión',
              ),
              IconButton(
                icon: const Icon(Icons.settings),
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const ConfigScreen()),
                ),
                tooltip: 'Configuración',
              ),
            ],
          ),
          drawer: _buildDrawer(context),
          body: IndexedStack(
            index: _currentIndex,
            children: _screens,
          ),
          bottomNavigationBar: BottomNavigationBar(
            currentIndex: _currentIndex,
            onTap: (index) {
              setState(() {
                _currentIndex = index;
              });
            },
            items: const [
              BottomNavigationBarItem(
                icon: Icon(Icons.task),
                label: 'Pendientes',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.history),
                label: 'Vencidas',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.check_circle_outline),
                label: 'Entregadas',
              ),
            ],
            selectedItemColor: AppColors.primary,
            unselectedItemColor: Colors.grey,
          ),
        );
      },
    );
  }

  Future<void> _signOut() async {
    await _authService.signOut();
    // El StreamBuilder automáticamente redirigirá al AuthScreen cuando el usuario sea null
  }

  Widget _buildDrawer(BuildContext context) {
    return Drawer(
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          DrawerHeader(
            decoration: const BoxDecoration(
              color: AppColors.primary,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.school,
                  size: 48,
                  color: Colors.white,
                ),
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
                  _authService.currentUser?.displayName ?? 'Usuario',
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 14,
                  ),
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
              setState(() {
                _currentIndex = 0;
              });
            },
          ),
          ListTile(
            leading: const Icon(Icons.history),
            title: const Text('Tareas Vencidas'),
            selected: _currentIndex == 1,
            onTap: () {
              Navigator.pop(context);
              setState(() {
                _currentIndex = 1;
              });
            },
          ),
          ListTile(
            leading: const Icon(Icons.check_circle_outline),
            title: const Text('Tareas Entregadas'),
            selected: _currentIndex == 2,
            onTap: () {
              Navigator.pop(context);
              setState(() {
                _currentIndex = 2;
              });
            },
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.settings),
            title: const Text('Configuración'),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const ConfigScreen()),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.logout, color: Colors.red),
            title: const Text('Cerrar sesión', style: TextStyle(color: Colors.red)),
            onTap: () {
              Navigator.pop(context);
              _signOut();
            },
          ),
        ],
      ),
    );
  }
}
