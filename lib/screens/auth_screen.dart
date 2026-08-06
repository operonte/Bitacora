import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../auth_service.dart';
import '../colors.dart';
import '../providers/theme_provider.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final AuthService _authService = AuthService();
  bool _isLoading = false;

  static const _privacyPolicyUrl =
      'https://bitacora-2d643.web.app/policies/privacy_policy.html';
  static const _termsOfUseUrl =
      'https://bitacora-2d643.web.app/policies/terms_of_use.html';

  @override
  Widget build(BuildContext context) {
    final themeProvider = context.watch<ThemeProvider>();
    final primaryColor = themeProvider.primaryColor;
    final surfaceColor = context.isDark ? AppColors.darkSurface : AppColors.surface;

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              themeProvider.primaryDarkColor,
              themeProvider.primaryColor,
              themeProvider.primaryLightColor,
            ],
            stops: const [0.0, 0.55, 1.0],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // Parte superior: logo e ilustración
              Expanded(
                flex: 5,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Ícono con fondo blanco translúcido
                    Container(
                      width: 96,
                      height: 96,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(28),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.3),
                          width: 1.5,
                        ),
                      ),
                      child: const Icon(
                        Icons.auto_stories_rounded,
                        size: 52,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'Bitácora',
                      style: GoogleFonts.crimsonPro(
                        fontSize: 40,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Tu agenda académica inteligente',
                      style: TextStyle(
                        fontSize: 15,
                        color: Colors.white.withValues(alpha: 0.8),
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ],
                ),
              ),

              // Parte inferior: tarjeta de login
              Container(
                decoration: BoxDecoration(
                  color: surfaceColor,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(32),
                    topRight: Radius.circular(32),
                  ),
                ),
                padding: const EdgeInsets.fromLTRB(28, 36, 28, 40),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Bienvenido',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        color: context.textColor,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Inicia sesión para sincronizar tus tareas\nen todos tus dispositivos.',
                      style: TextStyle(
                        fontSize: 14,
                        color: context.textSecondaryColor,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 32),

                    // Beneficios
                    _BenefitRow(
                      icon: Icons.cloud_sync_rounded,
                      text: 'Sincronización automática en la nube',
                      accentColor: primaryColor,
                    ),
                    const SizedBox(height: 12),
                    _BenefitRow(
                      icon: Icons.notifications_active_rounded,
                      text: 'Recordatorios antes de cada entrega',
                      accentColor: primaryColor,
                    ),
                    const SizedBox(height: 12),
                    _BenefitRow(
                      icon: Icons.offline_bolt_rounded,
                      text: 'Funciona sin conexión a internet',
                      accentColor: primaryColor,
                    ),

                    const SizedBox(height: 36),

                    // Botón Google
                    if (_isLoading)
                      Center(
                        child: CircularProgressIndicator(
                          color: primaryColor,
                        ),
                      )
                    else
                      _GoogleSignInButton(
                        onPressed: _signInWithGoogle,
                        primaryColor: primaryColor,
                      ),

                    const SizedBox(height: 16),
                    Center(
                      child: _LegalText(
                        hintColor: context.textHintColor,
                        onTapTerms: () => _launchUrl(_termsOfUseUrl),
                        onTapPrivacy: () => _launchUrl(_privacyPolicyUrl),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _signInWithGoogle() async {
    setState(() => _isLoading = true);
    try {
      // En Supabase, signInWithGoogle() redirige al navegador para OAuth.
      // El resultado de autenticación llega por el stream authStateChanges,
      // no por valor de retorno.
      await _authService.signInWithGoogle();
      // El stream de auth en main.dart se encarga del redirect.
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al iniciar sesión: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _launchUrl(String url) async {
    final uri = Uri.parse(url);
    try {
      if (!await canLaunchUrl(uri)) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('No se puede abrir el enlace. Verifica tu conexión.'),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return;
      }
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Error al abrir el enlace'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }
}

class _BenefitRow extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color accentColor;
  const _BenefitRow({
    required this.icon,
    required this.text,
    required this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(7),
          decoration: BoxDecoration(
            color: accentColor.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 18, color: accentColor),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 13,
              color: context.textColor,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }
}

class _GoogleSignInButton extends StatelessWidget {
  final VoidCallback onPressed;
  final Color primaryColor;
  const _GoogleSignInButton({required this.onPressed, required this.primaryColor});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 54,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryColor,
          foregroundColor: Colors.white,
          elevation: 3,
          shadowColor: primaryColor.withValues(alpha: 0.4),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.login_rounded, size: 22),
            SizedBox(width: 10),
            Text(
              'Continuar con Google',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.3,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LegalText extends StatelessWidget {
  final Color hintColor;
  final VoidCallback onTapTerms;
  final VoidCallback onTapPrivacy;
  const _LegalText({
    required this.hintColor,
    required this.onTapTerms,
    required this.onTapPrivacy,
  });

  @override
  Widget build(BuildContext context) {
    final linkStyle = TextStyle(
      fontSize: 11,
      color: hintColor,
      fontWeight: FontWeight.w700,
      decoration: TextDecoration.underline,
    );
    final baseStyle = TextStyle(fontSize: 11, color: hintColor);

    return Text.rich(
      TextSpan(
        style: baseStyle,
        children: [
          const TextSpan(text: 'Al continuar aceptas nuestros '),
          TextSpan(
            text: 'Términos de uso',
            style: linkStyle,
            recognizer: TapGestureRecognizer()..onTap = onTapTerms,
          ),
          const TextSpan(text: '\ny '),
          TextSpan(
            text: 'Política de privacidad',
            style: linkStyle,
            recognizer: TapGestureRecognizer()..onTap = onTapPrivacy,
          ),
          const TextSpan(text: '.'),
        ],
      ),
      textAlign: TextAlign.center,
    );
  }
}
