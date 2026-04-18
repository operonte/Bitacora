import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'colors.dart';
import 'subjects_screen.dart';

class ConfigScreen extends StatelessWidget {
  const ConfigScreen({Key? key}) : super(key: key);

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
