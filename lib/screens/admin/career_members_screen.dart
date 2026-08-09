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
              onSelected: (_) => _remove(m),
              itemBuilder: (context) => const [
                PopupMenuItem(
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
