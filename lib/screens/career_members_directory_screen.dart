import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../colors.dart';
import '../models/career_model.dart';
import '../services/profile_service.dart';
import 'my_profile_screen.dart';
import 'public_profile_screen.dart';

/// Directorio de la carrera: todos sus miembros, docentes y alumnos, para
/// llegar al perfil de cualquiera — no solo el docente ve alumnos (Ficha del
/// alumno) o el admin ve la lista completa (gestión de miembros); esto es
/// para cualquiera que comparta la carrera.
class CareerMembersDirectoryScreen extends StatefulWidget {
  final Career career;
  const CareerMembersDirectoryScreen({super.key, required this.career});

  @override
  State<CareerMembersDirectoryScreen> createState() =>
      _CareerMembersDirectoryScreenState();
}

class _CareerMembersDirectoryScreenState
    extends State<CareerMembersDirectoryScreen> {
  List<Map<String, dynamic>>? _members;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final members = await ProfileService().getCareerMembers(widget.career.id);
      if (mounted) setState(() => _members = members);
    } catch (e) {
      if (mounted) {
        setState(() => _error = e.toString().replaceAll('Exception: ', ''));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final myId = Supabase.instance.client.auth.currentUser?.id;
    final members = _members;

    return Scaffold(
      appBar: AppBar(title: Text('Miembros — ${widget.career.name}')),
      body: _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  _error!,
                  style: const TextStyle(color: AppColors.error),
                ),
              ),
            )
          : members == null
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 8),
                children: [
                  ..._grupo(
                    'Docentes',
                    members.where((m) => m['role'] == 'docente').toList(),
                    myId,
                  ),
                  ..._grupo(
                    'Alumnos',
                    members.where((m) => m['role'] != 'docente').toList(),
                    myId,
                  ),
                ],
              ),
            ),
    );
  }

  List<Widget> _grupo(
    String titulo,
    List<Map<String, dynamic>> filas,
    String? myId,
  ) {
    if (filas.isEmpty) return const [];
    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: Text(
          '$titulo (${filas.length})',
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.1,
            color: AppColors.textSecondary,
          ),
        ),
      ),
      for (final m in filas) _memberTile(m, esYo: m['user_id'] == myId),
    ];
  }

  Widget _memberTile(Map<String, dynamic> m, {required bool esYo}) {
    final displayName = (m['display_name'] as String?)?.trim();
    final name = (displayName != null && displayName.isNotEmpty)
        ? displayName
        : 'Sin nombre';
    final photoUrl = m['photo_url'] as String?;

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: AppColors.primary.withValues(alpha: 0.15),
        backgroundImage: (photoUrl != null && photoUrl.isNotEmpty)
            ? NetworkImage(photoUrl)
            : null,
        child: (photoUrl == null || photoUrl.isEmpty)
            ? const Icon(Icons.person, color: AppColors.primary)
            : null,
      ),
      title: Text(esYo ? '$name (tú)' : name),
      trailing: const Icon(Icons.arrow_forward_ios, size: 14),
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => esYo
              ? const MyProfileScreen()
              : PublicProfileScreen(
                  userId: m['user_id'].toString(),
                  fallbackName: name,
                  career: widget.career,
                  role: m['role'] as String?,
                ),
        ),
      ),
    );
  }
}
