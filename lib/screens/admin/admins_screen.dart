import 'package:flutter/material.dart';
import '../../colors.dart';
import '../../services/admin_auth_service.dart';

/// Quién puede entrar al panel, y nombrar o quitar administradores.
///
/// `profiles.is_admin` es la única llave del panel y el cliente no puede
/// escribirla —el GRANT de UPDATE sobre `profiles` la deja fuera a propósito—,
/// así que hasta ahora nombrar a alguien exigía escribir SQL a mano. Eso
/// dejaba la instalación colgando de una sola cuenta de Google: perderla era
/// perder el panel.
///
/// Tener un segundo administrador es el respaldo. Todo pasa por
/// `admin_set_admin()`, que además impide quedarse sin ninguno.
class AdminsScreen extends StatefulWidget {
  const AdminsScreen({super.key});

  @override
  State<AdminsScreen> createState() => _AdminsScreenState();
}

class _AdminsScreenState extends State<AdminsScreen> {
  List<AdminMember>? _admins;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final admins = await AdminAuthService.admins();
      if (mounted) setState(() => _admins = admins);
    } catch (e) {
      if (mounted) {
        setState(() => _error = e.toString().replaceAll('Exception: ', ''));
      }
    }
  }

  Future<void> _add() async {
    final emailController = TextEditingController();
    final passwordController = TextEditingController();
    final formKey = GlobalKey<FormState>();
    AdminMember? encontrado;
    String? mensaje;
    var buscando = false;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Nombrar administrador'),
          content: SingleChildScrollView(
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'La cuenta tiene que haber entrado a Bitácora al menos una '
                    'vez. Busca por el correo con el que inicia sesión.',
                    style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: emailController,
                    autofocus: true,
                    enabled: encontrado == null,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                      labelText: 'Correo',
                      border: OutlineInputBorder(),
                    ),
                    validator: (val) => (val == null || !val.contains('@'))
                        ? 'Ingresa un correo válido'
                        : null,
                  ),
                  // La contraseña se pide en el mismo gesto de nombrar: dar el
                  // permiso sin darle una llave deja a la persona con acceso
                  // en la base y sin forma de abrir el panel.
                  if (encontrado != null && !encontrado!.isAdmin) ...[
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: passwordController,
                      autofocus: true,
                      decoration: const InputDecoration(
                        labelText: 'Contraseña que le darás',
                        helperText: 'Mínimo 8 caracteres. Comunícasela tú.',
                        border: OutlineInputBorder(),
                      ),
                      validator: (val) => (val == null ||
                              val.length < AdminAuthService.minPasswordLength)
                          ? 'Mínimo ${AdminAuthService.minPasswordLength} caracteres'
                          : null,
                    ),
                  ],
                  if (mensaje != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      mensaje!,
                      style: TextStyle(
                        fontSize: 13,
                        color: encontrado == null
                            ? AppColors.error
                            : AppColors.success,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: buscando
                  ? null
                  : () async {
                      if (!formKey.currentState!.validate()) return;

                      // Dos pasos a propósito: primero se confirma a quién se
                      // le va a dar la llave del panel, y recién después se
                      // otorga. Un solo botón invitaba a dársela a un correo
                      // mal escrito.
                      if (encontrado == null) {
                        setDialogState(() => buscando = true);
                        final user = await AdminAuthService.findUser(
                            emailController.text);
                        setDialogState(() {
                          buscando = false;
                          encontrado = user;
                          if (user == null) {
                            mensaje = 'No hay ninguna cuenta con ese correo. '
                                'Pídele que abra la app una vez.';
                          } else if (user.isAdmin) {
                            mensaje = '${user.label} ya es administrador. '
                                'Usa la llave de su fila para cambiarle la '
                                'contraseña.';
                          } else {
                            mensaje = 'Encontrada: ${user.label}. '
                                'Define su contraseña y confirma.';
                          }
                        });
                        return;
                      }

                      if (encontrado!.isAdmin) {
                        Navigator.pop(ctx);
                        return;
                      }

                      try {
                        await AdminAuthService.setAdmin(
                            encontrado!.userId, true);
                        await AdminAuthService.resetPasswordFor(
                            encontrado!.userId, passwordController.text);
                        if (ctx.mounted) Navigator.pop(ctx);
                      } catch (e) {
                        setDialogState(() => mensaje =
                            e.toString().replaceAll('Exception: ', ''));
                      }
                    },
              child: Text(encontrado == null ? 'Buscar' : 'Confirmar'),
            ),
          ],
        ),
      ),
    );

    emailController.dispose();
    passwordController.dispose();
    await _load();
  }

  /// Le pone (o le repone) la contraseña a un administrador que ya existe.
  Future<void> _resetPassword(AdminMember member) async {
    final controller = TextEditingController();
    final formKey = GlobalKey<FormState>();

    final puesta = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(member.hasPassword
            ? 'Cambiar su contraseña'
            : 'Definir su contraseña'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                member.hasPassword
                    ? 'La contraseña anterior de ${member.label} dejará de '
                        'servir. Comunícale la nueva.'
                    : '${member.label} tiene el permiso pero todavía no puede '
                        'entrar. Dale una contraseña y comunícasela.',
                style: const TextStyle(
                    fontSize: 13, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: controller,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Contraseña',
                  border: OutlineInputBorder(),
                ),
                validator: (val) => (val == null ||
                        val.length < AdminAuthService.minPasswordLength)
                    ? 'Mínimo ${AdminAuthService.minPasswordLength} caracteres'
                    : null,
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
                await AdminAuthService.resetPasswordFor(
                    member.userId, controller.text);
                if (ctx.mounted) Navigator.pop(ctx, true);
              } catch (e) {
                if (ctx.mounted) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    SnackBar(
                      content:
                          Text(e.toString().replaceAll('Exception: ', '')),
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
    );

    controller.dispose();
    if (puesta == true) {
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Contraseña definida para ${member.label}'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    }
  }

  Future<void> _revoke(AdminMember member) async {
    final confirmado = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('¿Quitar el acceso?'),
        content: Text(
          '${member.label} dejará de poder abrir el panel, y su contraseña de '
          'administrador se borra.\n\n'
          'Su cuenta y sus carreras no se tocan.',
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
      await AdminAuthService.setAdmin(member.userId, false);
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString().replaceAll('Exception: ', '')),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Administradores')),
      body: _buildBody(),
      floatingActionButton: FloatingActionButton(
        onPressed: _add,
        backgroundColor: Theme.of(context).primaryColor,
        elevation: 4,
        shape: const CircleBorder(),
        tooltip: 'Nombrar administrador',
        child: const Icon(Icons.add, color: Colors.white, size: 26),
      ),
    );
  }

  Widget _buildBody() {
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(_error!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.error)),
        ),
      );
    }

    final admins = _admins;
    if (admins == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        if (admins.length == 1)
          Container(
            margin: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.warning.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline, color: AppColors.warning, size: 20),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Hay un solo administrador. Si pierdes el acceso a esa '
                    'cuenta de Google, nadie podrá abrir el panel sin tocar '
                    'la base de datos a mano. Nombra a una segunda cuenta '
                    'tuya como respaldo.',
                    style: TextStyle(fontSize: 13, height: 1.5),
                  ),
                ),
              ],
            ),
          ),
        for (final a in admins) ...[
          ListTile(
            leading: CircleAvatar(
              child: Text(a.label.characters.first.toUpperCase()),
            ),
            title: Text(a.label),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (a.email != null && a.email != a.label)
                  Text(a.email!, style: const TextStyle(fontSize: 12)),
                if (!a.hasPassword)
                  const Text(
                    'Sin contraseña: todavía no puede entrar',
                    style: TextStyle(fontSize: 12, color: AppColors.warning),
                  ),
              ],
            ),
            trailing: PopupMenuButton<String>(
              onSelected: (value) {
                switch (value) {
                  case 'clave':
                    _resetPassword(a);
                  case 'quitar':
                    _revoke(a);
                }
              },
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: 'clave',
                  child: ListTile(
                    leading: Icon(
                      Icons.key_outlined,
                      color: a.hasPassword ? null : AppColors.warning,
                    ),
                    title: Text(a.hasPassword
                        ? 'Cambiar contraseña'
                        : 'Definir contraseña'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                const PopupMenuItem(
                  value: 'quitar',
                  child: ListTile(
                    leading: Icon(Icons.remove_moderator_outlined,
                        color: AppColors.error),
                    title: Text('Quitar acceso'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
        ],
      ],
    );
  }
}
