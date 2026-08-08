import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../colors.dart';
import '../providers/theme_provider.dart';
import '../services/career_service.dart';
import '../services/admin_auth_service.dart';
import 'administration_screen.dart';

class CareerSelectionScreen extends StatefulWidget {
  const CareerSelectionScreen({super.key});

  @override
  State<CareerSelectionScreen> createState() => _CareerSelectionScreenState();
}

class _CareerSelectionScreenState extends State<CareerSelectionScreen> {
  final CareerService _careerService = CareerService();
  final TextEditingController _accessKeyController = TextEditingController();
  bool _isLoading = false;

  /// Carreras que el servidor no reconoció y se quitaron del dispositivo. Sin
  /// esto el usuario aparece acá sin saber por qué dejó de ver su carrera.
  List<String> _revokedCareers = [];

  @override
  void initState() {
    super.initState();
    // Dos momentos posibles y hay que cubrir los dos: la reconciliación puede
    // haber terminado antes de abrir esta pantalla (se lee acá) o después,
    // con la pantalla ya montada (llega por el listener).
    _revokedCareers = _careerService.takeRevokedCareerNames();
    _careerService.addListener(_consumeRevokedCareers);
  }

  void _consumeRevokedCareers() {
    final names = _careerService.takeRevokedCareerNames();
    if (names.isEmpty || !mounted) return;
    setState(() => _revokedCareers = names);
  }

  @override
  void dispose() {
    _careerService.removeListener(_consumeRevokedCareers);
    _accessKeyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final primaryColor = context.watch<ThemeProvider>().primaryColor;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Seleccionar Carrera'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Logo o título
            Icon(Icons.school, size: 80, color: primaryColor),
            const SizedBox(height: 32),
            Text(
              'Bitácora',
              style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.bold,
                color: primaryColor,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Selecciona tu carrera para comenzar',
              style: TextStyle(fontSize: 16, color: context.textSecondaryColor),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 48),

            if (_revokedCareers.isNotEmpty) ...[
              Card(
                color: AppColors.warning.withValues(alpha: 0.10),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.info_outline, color: AppColors.warning),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _revokedCareers.length == 1
                              ? 'Tu acceso a "${_revokedCareers.first}" ya no está '
                                  'registrado en el servidor, así que se quitó de este '
                                  'dispositivo. Vuelve a ingresar su clave para '
                                  'recuperar sus tareas y reuniones compartidas.'
                              : 'Tu acceso a estas carreras ya no está registrado en '
                                  'el servidor, así que se quitaron de este '
                                  'dispositivo: ${_revokedCareers.join(', ')}. Vuelve a '
                                  'ingresar sus claves para recuperar lo compartido.',
                          style: TextStyle(
                            fontSize: 13,
                            color: context.textColor,
                            height: 1.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
            ],

            // Opción para ingresar con clave de acceso
            Text(
              'Ingresa tu clave de acceso',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: primaryColor,
              ),
            ),
            const SizedBox(height: 16),

            Card(
              elevation: 4,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    TextFormField(
                      controller: _accessKeyController,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: 'Clave de Acceso',
                        hintText: 'Ingresa la clave de tu carrera',
                        prefixIcon: Icon(Icons.key),
                      ),
                      onFieldSubmitted: (_) => _validateAccessKey(),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _isLoading ? null : _validateAccessKey,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: primaryColor,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                        child: _isLoading
                            ? const CircularProgressIndicator(
                                color: Colors.white,
                              )
                            : const Text('Validar Clave'),
                      ),
                    ),
                  ],
                ),
              ),
            ),

          ],
        ),
      ),
    );
  }

  Future<void> _validateAccessKey() async {
    final accessKey = _accessKeyController.text.trim();

    if (accessKey.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Por favor ingresa una clave de acceso'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      // El panel de administración no se anuncia en ninguna parte: se entra
      // escribiendo la contraseña de admin en este mismo campo.
      //
      // A diferencia de la contraseña maestra que había antes, acá no se
      // compara nada en el cliente. verify_admin_password() corre en Postgres
      // y exige las dos cosas a la vez: que la cuenta tenga is_admin y que la
      // contraseña calce con el hash bcrypt guardado. Para quien no sea
      // administrador es indistinguible de una clave de carrera equivocada.
      if (await AdminAuthService.verifyPassword(accessKey)) {
        if (!mounted) return;
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const AdministrationScreen()),
        );
        return;
      }

      // Si no era eso, se valida como clave de carrera. También contra el
      // servidor: la clave ya no viaja en la app.
      final career = await _careerService.validateAccessKey(accessKey);
      if (!mounted) return;

      if (career == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Clave de acceso inválida'),
            backgroundColor: Colors.red,
          ),
        );
      } else {
        await _careerService.saveSelectedCareer(career);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ Carrera configurada: ${career.name}'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }
}
