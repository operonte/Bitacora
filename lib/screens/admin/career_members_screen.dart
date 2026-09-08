import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../colors.dart';
import '../../models/career_model.dart';
import '../../services/admin_auth_service.dart';

/// Quién pertenece a una carrera, y quitarle el acceso a alguien.
///
/// Hasta ahora esto no existía en ninguna parte: la única forma de saber si
/// alguien estaba inscrito, o de sacarlo, era escribir SQL contra
/// `user_careers`. Con el acceso repartido por clave y sin forma de revocarlo,
/// una clave filtrada no tenía vuelta atrás.
class CareerMembersScreen extends StatefulWidget {
  final Career career;

  const CareerMembersScreen({super.key, required this.career});

  @override
  State<CareerMembersScreen> createState() => _CareerMembersScreenState();
}

class _CareerMembersScreenState extends State<CareerMembersScreen> {
  List<AdminMember>? _members;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final members = await AdminAuthService.careerMembers(widget.career.id);
      if (mounted) setState(() => _members = members);
    } catch (e) {
      if (mounted) {
        setState(() => _error = e.toString().replaceAll('Exception: ', ''));
      }
    }
  }

  /// Inscribe a alguien sin repartirle la clave de acceso — para cuando la
  /// perdió, o nunca la tuvo. Reutiliza admin_find_user + admin_add_member,
  /// que ya existían para el "Deshacer" de _remove pero nunca tenían un
  /// botón propio.
  Future<void> _addMemberByEmail() async {
    final controller = TextEditingController();
    String? errorText;

    final email = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Agregar por correo'),
          content: TextField(
            controller: controller,
            autofocus: true,
            keyboardType: TextInputType.emailAddress,
            decoration: InputDecoration(
              labelText: 'Correo de la cuenta de Google',
              border: const OutlineInputBorder(),
              errorText: errorText,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () async {
                final value = controller.text.trim();
                if (value.isEmpty) return;
                Navigator.pop(ctx, value);
              },
              child: const Text('Buscar'),
            ),
          ],
        ),
      ),
    );
    if (email == null || !mounted) return;

    try {
      final found = await AdminAuthService.findUser(email);
      if (found == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('No hay ninguna cuenta con ese correo — tiene que haber iniciado sesión en Bitácora al menos una vez.'),
            ),
          );
        }
        return;
      }
      await AdminAuthService.addMember(widget.career.id, found.userId);
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${found.label} agregado a ${widget.career.name}')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo agregar: $e'), backgroundColor: AppColors.error),
        );
      }
    }
  }

  Future<void> _toggleDocente(AdminMember member) async {
    final nuevoRol = member.isDocente ? 'estudiante' : 'docente';
    try {
      await AdminAuthService.setMemberRole(
          widget.career.id, member.userId, nuevoRol);
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(nuevoRol == 'docente'
                ? '${member.label} ahora es docente de ${widget.career.name}'
                : '${member.label} ya no es docente'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('No se pudo cambiar el rol: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  Future<void> _remove(AdminMember member) async {
    final confirmado = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('¿Quitar de la carrera?'),
        content: Text(
          '${member.label} dejará de ver las tareas y reuniones compartidas '
          'de ${widget.career.name}.\n\n'
          'Sus tareas y archivos personales no se tocan. Puede volver a '
          'entrar si tiene la clave de acceso: para cerrarle la puerta de '
          'verdad hay que cambiarla también.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Quitar'),
          ),
        ],
      ),
    );

    if (confirmado != true) return;

    try {
      await AdminAuthService.removeMember(widget.career.id, member.userId);
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${member.label} ya no pertenece a la carrera'),
            action: SnackBarAction(
              label: 'Deshacer',
              onPressed: () async {
                await AdminAuthService.addMember(
                    widget.career.id, member.userId);
                await _load();
              },
            ),
            duration: const Duration(seconds: 6),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('No se pudo quitar: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Miembros de ${widget.career.name}'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Actualizar',
            onPressed: _load,
          ),
        ],
      ),
      body: _buildBody(),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addMemberByEmail,
        icon: const Icon(Icons.person_add_alt_1_outlined),
        label: const Text('Agregar por correo'),
      ),
    );
  }

  Widget _buildBody() {
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            _error!,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.error),
          ),
        ),
      );
    }

    final members = _members;
    if (members == null) {
      return const Center(child: CircularProgressIndicator());
    }

    if (members.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text(
            'Nadie está inscrito en esta carrera todavía.\n'
            'Se inscriben solos al ingresar su clave de acceso.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textSecondary, height: 1.5),
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: members.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (context, i) {
          final m = members[i];
          return ListTile(
            leading: CircleAvatar(
              child: Text(m.label.characters.first.toUpperCase()),
            ),
            title: Row(
              children: [
                Flexible(child: Text(m.label, overflow: TextOverflow.ellipsis)),
                if (m.isAdmin) ...[
                  const SizedBox(width: 8),
                  const Icon(Icons.shield_outlined,
                      size: 16, color: AppColors.primary),
                ],
                if (m.isDocente) ...[
                  const SizedBox(width: 8),
                  const Icon(Icons.school_outlined,
                      size: 16, color: AppColors.warning),
                ],
              ],
            ),
            subtitle: Text(
              [
                if (m.email != null && m.email != m.label) m.email!,
                if (m.joinedAt != null)
                  'Desde ${DateFormat('d MMM y', 'es').format(m.joinedAt!)}',
              ].join(' · '),
              style: const TextStyle(fontSize: 12),
            ),
            trailing: PopupMenuButton<String>(
              onSelected: (value) {
                if (value == 'quitar') {
                  _remove(m);
                } else if (value == 'docente') {
                  _toggleDocente(m);
                }
              },
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: 'docente',
                  child: ListTile(
                    leading: Icon(
                      m.isDocente
                          ? Icons.school
                          : Icons.school_outlined,
                      color: AppColors.warning,
                    ),
                    title: Text(m.isDocente
                        ? 'Quitar rol de docente'
                        : 'Hacer docente'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                const PopupMenuItem(
                  value: 'quitar',
                  child: ListTile(
                    leading: Icon(Icons.person_remove_outlined,
                        color: AppColors.error),
                    title: Text('Quitar de la carrera'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
