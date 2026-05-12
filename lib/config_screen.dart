import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'colors.dart';
import 'subjects_screen.dart';
import 'models/career_model.dart';
import 'services/career_service.dart';

class ConfigScreen extends StatefulWidget {
  const ConfigScreen({Key? key}) : super(key: key);

  @override
  _ConfigScreenState createState() => _ConfigScreenState();
}

class _ConfigScreenState extends State<ConfigScreen> {
  final CareerService _careerService = CareerService();
  final TextEditingController _accessKeyController = TextEditingController();
  Career? _selectedCareer;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadCurrentCareer();
  }

  Future<void> _loadCurrentCareer() async {
    final career = _careerService.getSelectedCareer();
    if (career != null) {
      setState(() {
        _selectedCareer = career;
        _accessKeyController.text = '•••••••••';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Configuración'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Logo o título
            const Icon(
              Icons.settings,
              size: 80,
              color: AppColors.primary,
            ),
            const SizedBox(height: 32),
            const Text(
              'Bitácora',
              style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.bold,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: 48),
            const Text(
              'Gestión Académica',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: 24),
            
            // Selección de Carrera
            Card(
              elevation: 4,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Configurar Carrera',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: AppColors.primary,
                      ),
                    ),
                    const SizedBox(height: 16),
                    
                    // Estado actual
                    if (_selectedCareer != null) ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.school, color: AppColors.primary),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Carrera actual: ${_selectedCareer!.name}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.primary,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                    
                    // Input de clave
                    TextFormField(
                      controller: _accessKeyController,
                      obscureText: true,
                      decoration: InputDecoration(
                        labelText: 'Clave de Acceso',
                        hintText: 'Ingresa la clave de tu carrera',
                        prefixIcon: const Icon(Icons.key),
                        border: const OutlineInputBorder(),
                        filled: true,
                        fillColor: Colors.grey[50],
                      ),
                    ),
                    const SizedBox(height: 16),
                    
                    // Botón de validación
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _isLoading ? null : _validateAccessKey,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                        child: _isLoading
                            ? const CircularProgressIndicator(color: Colors.white)
                            : const Text('Validar Clave'),
                      ),
                    ),
                    
                    if (_selectedCareer != null) ...[
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton(
                          onPressed: _changeCareer,
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                          ),
                          child: const Text('Cambiar Carrera'),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            
            const SizedBox(height: 24),
            
            // Mis Materias
            Card(
              elevation: 4,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: ListTile(
                leading: const Icon(Icons.school, color: AppColors.primary),
                title: const Text('Mis Materias'),
                subtitle: const Text('Crear, editar y eliminar materias'),
                trailing: const Icon(Icons.arrow_forward_ios),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const SubjectsScreen()),
                ),
              ),
            ),
            
            const SizedBox(height: 48),
            const Text(
              'Información Legal',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: 24),
            
            // Política de Privacidad
            Card(
              elevation: 4,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: ListTile(
                leading: const Icon(Icons.privacy_tip, color: AppColors.primary),
                title: const Text('Política de Privacidad'),
                subtitle: const Text('Lee cómo manejamos tus datos'),
                trailing: const Icon(Icons.arrow_forward_ios),
                onTap: () => _launchPrivacyPolicy(context),
              ),
            ),
            
            const SizedBox(height: 16),
            
            // Términos de Uso
            Card(
              elevation: 4,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: ListTile(
                leading: const Icon(Icons.description, color: AppColors.primary),
                title: const Text('Términos de Uso'),
                subtitle: const Text('Conoce las reglas de la aplicación'),
                trailing: const Icon(Icons.arrow_forward_ios),
                onTap: () => _launchTermsOfUse(context),
              ),
            ),
            
            const SizedBox(height: 24),
            
            // Información de la app
            Card(
              elevation: 4,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: ListTile(
                leading: const Icon(Icons.info, color: AppColors.primary),
                title: const Text('Acerca de Bitácora'),
                subtitle: const Text('Versión 1.0.0'),
                trailing: const Icon(Icons.info_outline),
                onTap: () => _showAboutDialog(context),
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
      final career = _careerService.validateAccessKey(accessKey);
      
      if (career == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Clave de acceso inválida'),
            backgroundColor: Colors.red,
          ),
        );
      } else {
        await _careerService.saveSelectedCareer(career);
        setState(() {
          _selectedCareer = career;
          _accessKeyController.text = '•••••••';
        });
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ Carrera configurada: ${career.name}'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _changeCareer() async {
    setState(() {
      _selectedCareer = null;
      _accessKeyController.text = '';
    });
    
    await _careerService.clearSelectedCareer();
    
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('📋 Ingresa una nueva clave de acceso'),
        backgroundColor: Colors.blue,
      ),
    );
  }

  Future<void> _launchPrivacyPolicy(BuildContext context) async {
    const url = 'https://bitacora-2d643.web.app/policies/privacy_policy.html';
    await _launchUrl(context, url, 'Política de Privacidad');
  }

  Future<void> _launchTermsOfUse(BuildContext context) async {
    const url = 'https://bitacora-2d643.web.app/policies/terms_of_use.html';
    await _launchUrl(context, url, 'Términos de Uso');
  }

  Future<void> _launchUrl(BuildContext context, String url, String title) async {
    final uri = Uri.parse(url);

    try {
      // Verificar si se puede abrir la URL
      if (!await canLaunchUrl(uri)) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('No se puede abrir $title. Verifica tu conexión a internet.'),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return;
      }

      // Intentar abrir con el navegador del sistema (forzar externo para evitar que la app capture la URL)
      final launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );

      if (!launched && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('No se pudo abrir $title'),
            backgroundColor: Colors.red,
            action: SnackBarAction(
              label: 'Copiar URL',
              onPressed: () {
                // Aquí podríamos copiar al portapapeles
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('URL copiada al portapapeles')),
                );
              },
            ),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al abrir $title. Intenta nuevamente.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _showAboutDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.school, color: AppColors.primary),
            SizedBox(width: 8),
            Text('Acerca de Bitácora'),
          ],
        ),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Bitácora',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
            SizedBox(height: 8),
            Text('Versión 1.0.0'),
            SizedBox(height: 16),
            Text(
              'Aplicación diseñada para estudiantes de Teología '
              'para gestionar tareas académicas, recordatorios '
              'y fechas de entrega.',
              style: TextStyle(fontSize: 14),
            ),
            SizedBox(height: 16),
            Text(
              'Características principales:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 8),
            Text('• Gestión de tareas por materia'),
            Text('• Recordatorios de fechas límite'),
            Text('• Sincronización en la nube'),
            Text('• Notificaciones push'),
            SizedBox(height: 16),
            Text(
              'Desarrollado por:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 4),
            Text('Operonte'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
  }
}
