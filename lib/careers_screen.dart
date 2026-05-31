import 'package:flutter/material.dart';
import 'colors.dart';
import 'services/admin_auth_service.dart';
import 'models/career_model.dart';

class CareersScreen extends StatefulWidget {
  const CareersScreen({super.key});

  @override
  _CareersScreenState createState() => _CareersScreenState();
}

class _CareersScreenState extends State<CareersScreen> {
  List<Career> _customCareers = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadCustomCareers();
  }

  Future<void> _loadCustomCareers() async {
    setState(() => _isLoading = true);
    // Aquí cargaríamos las carreras personalizadas creadas por el usuario
    // Por ahora, mostramos solo las carreras predefinidas
    setState(() {
      _customCareers = Careers.all;
      _isLoading = false;
    });
  }

  void _showCreateCareerDialog() {
    final nameController = TextEditingController();
    final descriptionController = TextEditingController();
    final accessKeyController = TextEditingController();
    final passwordController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Crear Nueva Carrera'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(
                  labelText: 'Nombre de la carrera *',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: descriptionController,
                decoration: const InputDecoration(
                  labelText: 'Descripción (opcional)',
                  border: OutlineInputBorder(),
                ),
                maxLines: 3,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: accessKeyController,
                decoration: const InputDecoration(
                  labelText: 'Clave de acceso *',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: passwordController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Contraseña de administrador *',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () {
              final password = passwordController.text.trim();
              if (AdminAuthService.verifyPassword(password)) {
                // Aquí se implementaría la lógica para crear la carrera
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('✅ Función de crear carrera implementada'),
                    backgroundColor: Colors.green,
                  ),
                );
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('❌ Contraseña incorrecta'),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            },
            child: const Text('Crear'),
          ),
        ],
      ),
    );
  }

  void _showCareerSubjects(Career career) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Materias de ${career.name}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Materias predefinidas:'),
            const SizedBox(height: 8),
            ...career.predefinedSubjects.map(
              (subject) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text('• $subject'),
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () {
                Navigator.pop(context);
                _showAddSubjectDialog(career);
              },
              icon: const Icon(Icons.add),
              label: const Text('Agregar Materia'),
            ),
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

  void _showAddSubjectDialog(Career career) {
    final passwordController = TextEditingController();
    final subjectNameController = TextEditingController();
    final professorController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Agregar Materia'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: subjectNameController,
                decoration: const InputDecoration(
                  labelText: 'Nombre de la materia *',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: professorController,
                decoration: const InputDecoration(
                  labelText: 'Profesor (opcional)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: passwordController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Contraseña de administrador *',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () {
              final password = passwordController.text.trim();
              if (AdminAuthService.verifyPassword(password)) {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('✅ Función de agregar materia implementada'),
                    backgroundColor: Colors.green,
                  ),
                );
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('❌ Contraseña incorrecta'),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            },
            child: const Text('Agregar'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Mis Carreras'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _customCareers.isEmpty
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.work_outline, size: 80, color: Colors.grey),
                  SizedBox(height: 16),
                  Text(
                    'No tienes carreras personalizadas',
                    style: TextStyle(fontSize: 18, color: Colors.grey),
                  ),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _customCareers.length,
              itemBuilder: (context, index) {
                final career = _customCareers[index];
                return Card(
                  elevation: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  child: ListTile(
                    leading: const Icon(Icons.work, color: AppColors.primary),
                    title: Text(career.name),
                    subtitle: Text(
                      '${career.predefinedSubjects.length} materias',
                    ),
                    trailing: const Icon(Icons.arrow_forward_ios),
                    onTap: () => _showCareerSubjects(career),
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showCreateCareerDialog,
        backgroundColor: AppColors.primary,
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }
}
