import 'package:flutter/material.dart';
import '../colors.dart';
import '../services/admin_auth_service.dart';
import 'admin/admins_screen.dart';
import 'admin/career_members_screen.dart';
import 'admin/career_subjects_screen.dart';
import '../models/career_model.dart';
import '../services/career_supabase_service.dart';

/// Pantalla de administración para gestionar carreras y asignaturas.
///
/// Usa streams en tiempo real para mostrar cambios instantáneos.
class AdministrationScreen extends StatefulWidget {
  const AdministrationScreen({super.key});

  @override
  State<AdministrationScreen> createState() => _AdministrationScreenState();
}

class _AdministrationScreenState extends State<AdministrationScreen> {
  final CareerSupabaseService _careerService = CareerSupabaseService();

  /// Filtro por nombre. Vacío = todas.
  String _query = '';
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// Carreras que calzan con [_query], ordenadas por nombre.
  ///
  /// El orden importa aunque hoy haya dos: la lista venía en el orden que
  /// devolviera el servidor, así que cambiaba sola entre recargas.
  List<Career> _filtrar(List<Career> careers) {
    final q = _query.trim().toLowerCase();
    final lista = q.isEmpty
        ? [...careers]
        : careers.where((c) {
            if (c.name.toLowerCase().contains(q)) return true;
            // También busca dentro de las materias: con muchas carreras es más
            // rápido acordarse de un ramo que del nombre exacto de la carrera.
            return c.predefinedSubjects
                .any((s) => s.name.toLowerCase().contains(q));
          }).toList();
    lista.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return lista;
  }

  void _showCreateCareerDialog() {
    final nameController = TextEditingController();
    final descriptionController = TextEditingController();
    final accessKeyController = TextEditingController();
    final formKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Crear Nueva Carrera'),
        content: Form(
          key: formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    labelText: 'Nombre de la carrera *',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'El nombre es obligatorio';
                    }
                    if (value.trim().length < 3) {
                      return 'El nombre debe tener al menos 3 caracteres';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: descriptionController,
                  decoration: const InputDecoration(
                    labelText: 'Descripción (opcional)',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 3,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: accessKeyController,
                  decoration: const InputDecoration(
                    labelText: 'Clave de acceso *',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'La clave de acceso es obligatoria';
                    }
                    if (value.trim().length < 4) {
                      return 'La clave debe tener al menos 4 caracteres';
                    }
                    return null;
                  },
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (!formKey.currentState!.validate()) {
                return;
              }

              final name = nameController.text.trim();
              final description = descriptionController.text.trim();
              final accessKey = accessKeyController.text.trim();

              final career = Career(
                id: 'custom_${DateTime.now().millisecondsSinceEpoch}',
                name: name,
                accessKey: accessKey,
                description: description.isEmpty ? null : description,
                predefinedSubjects: [],
              );

              try {
                await _careerService.createCareer(career);
                if (context.mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('✅ Carrera creada exitosamente'),
                      backgroundColor: Colors.green,
                    ),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Error al crear carrera: $e'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              }
            },
            child: const Text('Crear'),
          ),
        ],
      ),
    );
  }

  void _showEditCareerDialog(Career career) {
    final nameController = TextEditingController(text: career.name);
    final descriptionController = TextEditingController(
      text: career.description ?? '',
    );
    final accessKeyController = TextEditingController(text: career.accessKey);
    final formKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Editar Carrera'),
        content: Form(
          key: formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    labelText: 'Nombre de la carrera *',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'El nombre es obligatorio';
                    }
                    if (value.trim().length < 3) {
                      return 'El nombre debe tener al menos 3 caracteres';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: descriptionController,
                  decoration: const InputDecoration(
                    labelText: 'Descripción (opcional)',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 3,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: accessKeyController,
                  decoration: const InputDecoration(
                    labelText: 'Clave de acceso *',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'La clave de acceso es obligatoria';
                    }
                    if (value.trim().length < 4) {
                      return 'La clave debe tener al menos 4 caracteres';
                    }
                    return null;
                  },
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (!formKey.currentState!.validate()) {
                return;
              }

              final name = nameController.text.trim();
              final description = descriptionController.text.trim();
              final accessKey = accessKeyController.text.trim();

              final updatedCareer = Career(
                id: career.id,
                name: name,
                accessKey: accessKey,
                description: description.isEmpty ? null : description,
                predefinedSubjects: career.predefinedSubjects,
              );

              try {
                await _careerService.updateCareer(updatedCareer);
                if (context.mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('✅ Carrera actualizada exitosamente'),
                      backgroundColor: Colors.green,
                    ),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Error al actualizar carrera: $e'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              }
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
  }

  /// Borrar una carrera no es solo borrar una fila: `user_careers` tiene
  /// borrado en cascada, así que expulsa de golpe a todos sus miembros y deja
  /// huérfanas sus tareas, reuniones y archivos compartidos.
  ///
  /// Antes el diálogo solo decía "no se puede deshacer", que es cierto y no
  /// dice nada. Ahora se le pregunta al servidor qué cuelga de esa carrera, se
  /// muestra, y hay que escribir su nombre para confirmar.
  Future<void> _showDeleteCareerDialog(Career career) async {
    CareerImpact? impacto;
    try {
      impacto = await AdminAuthService.careerImpact(career.id);
    } catch (_) {
      // Sin el detalle igual se puede borrar, pero se avisa que se está
      // decidiendo a ciegas.
    }

    if (!mounted) return;

    final nombreController = TextEditingController();
    final confirmado = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Eliminar carrera'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Vas a eliminar "${career.name}".'),
                const SizedBox(height: 12),
                if (impacto == null)
                  const Text(
                    'No se pudo consultar qué contiene. Continúa solo si '
                    'estás seguro.',
                    style: TextStyle(fontSize: 13, color: AppColors.warning),
                  )
                else if (impacto.isEmpty)
                  const Text(
                    'No tiene miembros ni contenido compartido.',
                    style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
                  )
                else ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.error.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _impactRow('${impacto.members} miembros',
                            'pierden el acceso'),
                        _impactRow('${impacto.tasks} tareas compartidas',
                            'quedan sin carrera'),
                        _impactRow('${impacto.meetings} reuniones',
                            'quedan sin carrera'),
                        _impactRow('${impacto.files} archivos',
                            'quedan sin carrera'),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                const Text(
                  'No se puede deshacer. Escribe el nombre de la carrera para '
                  'confirmar:',
                  style: TextStyle(fontSize: 13),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: nombreController,
                  autofocus: true,
                  decoration: InputDecoration(
                    hintText: career.name,
                    border: const OutlineInputBorder(),
                  ),
                  onChanged: (_) => setDialogState(() {}),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: AppColors.error),
              onPressed: nombreController.text.trim().toLowerCase() ==
                      career.name.trim().toLowerCase()
                  ? () => Navigator.pop(ctx, true)
                  : null,
              child: const Text('Eliminar'),
            ),
          ],
        ),
      ),
    );

    nombreController.dispose();
    if (confirmado != true) return;

    try {
      await _careerService.deleteCareer(career.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Carrera "${career.name}" eliminada'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('No se pudo eliminar: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  static Widget _impactRow(String cantidad, String consecuencia) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Text(
          '• $cantidad $consecuencia',
          style: const TextStyle(fontSize: 13),
        ),
      );

  void _openSubjects(Career career) => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => CareerSubjectsScreen(career: career),
        ),
      );

  void _openMembers(Career career) => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => CareerMembersScreen(career: career),
        ),
      );

  Future<void> _showChangePasswordDialog() async {
    final formKey = GlobalKey<FormState>();
    final nuevaController = TextEditingController();
    final repetirController = TextEditingController();
    var obscure = true;

    final cambiada = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Cambiar contraseña'),
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Es la que se escribe en el campo de clave de acceso para '
                  'entrar acá. Se guarda cifrada en el servidor.',
                  style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: nuevaController,
                  obscureText: obscure,
                  autofocus: true,
                  decoration: InputDecoration(
                    labelText: 'Contraseña nueva',
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      icon: Icon(obscure
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined),
                      onPressed: () =>
                          setDialogState(() => obscure = !obscure),
                    ),
                  ),
                  validator: (val) =>
                      (val == null || val.length < AdminAuthService.minPasswordLength)
                          ? 'Mínimo ${AdminAuthService.minPasswordLength} caracteres'
                          : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: repetirController,
                  obscureText: obscure,
                  decoration: const InputDecoration(
                    labelText: 'Repetir',
                    border: OutlineInputBorder(),
                  ),
                  validator: (val) =>
                      val != nuevaController.text ? 'No coinciden' : null,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () async {
                if (!formKey.currentState!.validate()) return;
                try {
                  await AdminAuthService.setPassword(nuevaController.text);
                  if (ctx.mounted) Navigator.pop(ctx, true);
                } catch (e) {
                  if (ctx.mounted) {
                    ScaffoldMessenger.of(ctx).showSnackBar(
                      SnackBar(
                        content: Text(e.toString().replaceAll('Exception: ', '')),
                        backgroundColor: AppColors.error,
                      ),
                    );
                  }
                }
              },
              child: const Text('Guardar'),
            ),
          ],
        ),
      ),
    );

    nuevaController.dispose();
    repetirController.dispose();

    if (cambiada == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Contraseña actualizada'),
          backgroundColor: AppColors.success,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Administración'),
        actions: [
          IconButton(
            icon: const Icon(Icons.shield_outlined),
            tooltip: 'Administradores',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const AdminsScreen()),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.password_outlined),
            tooltip: 'Cambiar contraseña de administrador',
            onPressed: _showChangePasswordDialog,
          ),
        ],
      ),
      body: StreamBuilder<List<Career>>(
        stream: _careerService.getCareersStream(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline, size: 80, color: Colors.red),
                  const SizedBox(height: 16),
                  Text(
                    'Error al cargar carreras: ${snapshot.error}',
                    style: const TextStyle(fontSize: 16, color: Colors.red),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () {
                      setState(() {}); // Rebuild para reintentar
                    },
                    child: const Text('Reintentar'),
                  ),
                ],
              ),
            );
          }

          final careers = snapshot.data ?? [];

          if (careers.isEmpty) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.work_outline, size: 80, color: Colors.grey),
                  SizedBox(height: 16),
                  Text(
                    'No hay carreras registradas',
                    style: TextStyle(fontSize: 18, color: Colors.grey),
                  ),
                ],
              ),
            );
          }

          final visibles = _filtrar(careers);

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Buscar carrera o materia',
                    prefixIcon: const Icon(Icons.search),
                    border: const OutlineInputBorder(),
                    isDense: true,
                    suffixIcon: _query.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.clear),
                            tooltip: 'Limpiar',
                            onPressed: () {
                              _searchController.clear();
                              setState(() => _query = '');
                            },
                          ),
                  ),
                  onChanged: (v) => setState(() => _query = v),
                ),
              ),
              if (visibles.isEmpty)
                const Expanded(
                  child: Center(
                    child: Text('Ninguna carrera calza con la búsqueda'),
                  ),
                )
              else
                Expanded(
                  child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: visibles.length,
            itemBuilder: (context, index) {
              final career = visibles[index];
              // La etiqueta "(predefinida)" salía siempre: se calculaba con
              // `Careers.all`, que fusiona las definidas en el código con las
              // que vienen de Supabase, así que cualquier carrera cargada del
              // servidor quedaba marcada como predefinida. Se compara contra
              // las del código y nada más.
              final isPredefined =
                  Careers.predefined.any((c) => c.id == career.id);
              return Card(
                elevation: 4,
                margin: const EdgeInsets.only(bottom: 16),
                child: ListTile(
                  leading: const Icon(Icons.work, color: AppColors.primary),
                  title: Text(career.name),
                  subtitle: Text(
                    '${career.predefinedSubjects.length} materias'
                    '${isPredefined ? ' · definida en la app' : ' · creada aquí'}',
                  ),
                  trailing: PopupMenuButton<String>(
                    onSelected: (value) {
                      switch (value) {
                        case 'materias':
                          _openSubjects(career);
                        case 'miembros':
                          _openMembers(career);
                        case 'editar':
                          _showEditCareerDialog(career);
                        case 'eliminar':
                          _showDeleteCareerDialog(career);
                      }
                    },
                    itemBuilder: (context) => const [
                      PopupMenuItem(
                        value: 'materias',
                        child: ListTile(
                          leading: Icon(Icons.menu_book_outlined),
                          title: Text('Materias'),
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                      PopupMenuItem(
                        value: 'miembros',
                        child: ListTile(
                          leading: Icon(Icons.group_outlined),
                          title: Text('Miembros'),
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                      PopupMenuItem(
                        value: 'editar',
                        child: ListTile(
                          leading: Icon(Icons.edit_outlined),
                          title: Text('Editar'),
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                      PopupMenuItem(
                        value: 'eliminar',
                        child: ListTile(
                          leading: Icon(Icons.delete_outline_rounded,
                              color: AppColors.error),
                          title: Text('Eliminar'),
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                    ],
                  ),
                  onTap: () => _openSubjects(career),
                ),
              );
            },
                  ),
                ),
            ],
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
