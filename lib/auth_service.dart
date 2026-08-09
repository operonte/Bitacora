import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../utils/logger.dart';
import 'services/local_cache_service.dart';
import 'services/google_drive_service.dart';
import 'services/study_file_service.dart';
import 'services/meeting_service.dart';

const _webClientId =
    '651071616802-1pgjc8uu88a58m5999noa0uits5n6s1j.apps.googleusercontent.com';

/// Servicio de autenticación usando Supabase Auth + Google Sign-In Nativo.
class AuthService {
  final SupabaseClient _client = Supabase.instance.client;

  AuthService();

  /// Cliente nativo de Google. Se construye igual en todos lados para que
  /// cerrar sesión afecte a la misma sesión que después inicia sesión.
  GoogleSignIn _buildGoogleSignIn() => GoogleSignIn(
        serverClientId: _webClientId,
        scopes: const [
          'email',
          'profile',
          // Permiso completo de Drive: ver la explicación en
          // lib/utils/drive_token_stub.dart. Resumen: `drive.file` solo daba
          // acceso a lo que la app había creado, así que un archivo subido a
          // mano en Drive era invisible. La restricción a la carpeta Bitácora
          // la impone el código, no Google.
          'https://www.googleapis.com/auth/drive',
        ],
      );

  /// Stream estable de sesión de usuario.
  Stream<AuthState> get authStateChanges => _client.auth.onAuthStateChange;

  /// Stream mapeado a User?
  Stream<User?> get userStream => _client.auth.onAuthStateChange
      .map((authState) => authState.session?.user);

  /// Usuario actual (null si no hay sesión)
  User? get currentUser => _client.auth.currentUser;

  /// Inicia sesión con Google.
  /// En Android/iOS: Ventana flotante 100% nativa (sin abrir Chrome ni URLs raras).
  /// En Web: OAuth popup.
  Future<void> signInWithGoogle() async {
    try {
      Logger.auth('Iniciando proceso de Google Sign-In');

      if (kIsWeb) {
        await _client.auth.signInWithOAuth(
          OAuthProvider.google,
          scopes: 'https://www.googleapis.com/auth/drive',
          queryParams: {
            'access_type': 'offline',
            'prompt': 'select_account',
          },
        );
      } else {
        // En Móvil (Android): Login 100% Nativo sin abrir navegador ni URLs
        final googleSignIn = _buildGoogleSignIn();

        // Sin esto, signIn() reutiliza en silencio la última cuenta usada y
        // nunca muestra el selector. Equivale al prompt=select_account que
        // ya se pasa en la rama web: quien tiene varias cuentas de Google en
        // el teléfono tiene que poder elegir con cuál entra.
        try {
          await googleSignIn.signOut();
        } catch (e) {
          Logger.warning('No se pudo limpiar la sesión de Google previa: $e',
              tag: 'AuthService');
        }

        final googleUser = await googleSignIn.signIn();
        if (googleUser == null) {
          Logger.auth('El usuario canceló el inicio de sesión nativo');
          return;
        }

        final googleAuth = await googleUser.authentication;
        final idToken = googleAuth.idToken;
        final accessToken = googleAuth.accessToken;

        if (idToken == null) {
          throw Exception('No se pudo obtener el ID Token de Google.');
        }

        await _client.auth.signInWithIdToken(
          provider: OAuthProvider.google,
          idToken: idToken,
          accessToken: accessToken,
        );

        if (accessToken != null && accessToken.isNotEmpty) {
          await GoogleDriveService.persistToken(accessToken);
        }
      }
      Logger.auth('Google Sign-In completado exitosamente');
    } catch (e) {
      Logger.error('Error en signInWithGoogle', error: e, tag: 'AuthService');
      throw Exception('Error al iniciar sesión con Google: $e');
    }
  }

  /// Cierra sesión y limpia caché local.
  Future<void> signOut() async {
    try {
      await LocalCacheService().clearAllCache();
      // clearAllCache solo vacía tareas, materias y metadatos. Sin esto la
      // caja de archivos quedaba con los de la cuenta anterior.
      await StudyFileService().clearCache();
      await MeetingService().clearCache();
      await GoogleDriveService.clearToken();
      // Cerrar solo la sesión de Supabase dejaba viva la de Google, así que
      // el siguiente inicio volvía a entrar con la misma cuenta sin preguntar.
      if (!kIsWeb) {
        try {
          await _buildGoogleSignIn().signOut();
        } catch (e) {
          Logger.warning('No se pudo cerrar la sesión de Google: $e',
              tag: 'AuthService');
        }
      }
      await _client.auth.signOut();
      Logger.auth('Sesión cerrada exitosamente');
    } catch (e) {
      Logger.error('Error signing out', error: e, tag: 'AuthService');
    }
  }

  bool get isSignedIn => _client.auth.currentUser != null;
  String? get userDisplayName =>
      _client.auth.currentUser?.userMetadata?['full_name'] as String? ??
      _client.auth.currentUser?.userMetadata?['name'] as String?;
  String? get userEmail => _client.auth.currentUser?.email;
  String? get userPhotoURL =>
      _client.auth.currentUser?.userMetadata?['avatar_url'] as String?;
}
