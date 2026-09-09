import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../colors.dart';
import '../models/career_model.dart';
import '../services/career_service.dart';
import '../services/profile_service.dart';
import 'student_profile_screen.dart';

/// Perfil público de otra persona de tu carrera: solo lectura, más los
/// comentarios que le dejen — la alternativa visible-para-todos al chat
/// privado que se decidió no construir. El servidor (get_public_profile,
/// profile_comments RLS) ya exige que compartas una carrera con ella; acá
/// solo se pinta lo que llegó.
class PublicProfileScreen extends StatefulWidget {
  final String userId;
  final String fallbackName;

  /// Carrera y rol de la persona vista, ambos opcionales: solo quien ya los
  /// tiene a mano al navegar (el directorio de la carrera) los pasa. Sin
  /// ellos no se puede saber si mostrar el acceso a su ficha, así que
  /// directamente no aparece — mejor que adivinar.
  final Career? career;
  final String? role;

  const PublicProfileScreen({
    super.key,
    required this.userId,
    required this.fallbackName,
    this.career,
    this.role,
  });

  @override
  State<PublicProfileScreen> createState() => _PublicProfileScreenState();
}

class _PublicProfileScreenState extends State<PublicProfileScreen> {
  Map<String, dynamic>? _profile;
  List<Map<String, dynamic>> _comments = [];
  bool _loading = true;
  bool _sending = false;
  String? _error;
  final _commentController = TextEditingController();

  String? get _myId => Supabase.instance.client.auth.currentUser?.id;
  bool get _esMiPropioPerfil => widget.userId == _myId;

  /// Si corresponde ofrecer "Ver notas y asistencia": hace falta saber la
  /// carrera y que la persona vista sea alumna de ella — un docente viendo
  /// a otro docente no tiene ficha que mostrar.
  bool get _puedeVerFicha =>
      !_esMiPropioPerfil &&
      widget.career != null &&
      widget.role == 'estudiante' &&
      CareerService().isDocente(widget.career!.id);

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final results = await Future.wait([
        ProfileService().getPublicProfile(widget.userId),
        ProfileService().getComments(widget.userId),
      ]);
      if (mounted) {
        setState(() {
          _profile = results[0] as Map<String, dynamic>?;
          _comments = results[1] as List<Map<String, dynamic>>;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = e.toString().replaceAll('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _sendComment() async {
    final text = _commentController.text.trim();
    if (text.isEmpty) return;
    setState(() => _sending = true);
    try {
      await ProfileService().addComment(widget.userId, text);
      _commentController.clear();
      final comments = await ProfileService().getComments(widget.userId);
      if (mounted) setState(() => _comments = comments);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceAll('Exception: ', ''))),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _deleteComment(String id) async {
    try {
      await ProfileService().deleteComment(id);
      if (mounted) {
        setState(() => _comments.removeWhere((c) => c['id'] == id));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceAll('Exception: ', ''))),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final name =
        (_profile?['display_name'] as String?)?.trim().isNotEmpty == true
        ? _profile!['display_name'] as String
        : widget.fallbackName;
    final photoUrl = _profile?['photo_url'] as String?;
    final bio = (_profile?['bio'] as String?)?.trim();
    final extraPhotos = List<String>.from(
      (_profile?['extra_photo_urls'] as List?) ?? [],
    );
    final details = <(IconData, String, String?)>[
      (Icons.cake_outlined, 'Edad', _profile?['age']?.toString()),
      (Icons.wc_outlined, 'Género', _profile?['gender'] as String?),
      (
        Icons.favorite_outline,
        'Situación sentimental',
        _profile?['relationship_status'] as String?,
      ),
      (
        Icons.auto_awesome_outlined,
        'Creencias',
        _profile?['religion'] as String?,
      ),
      (Icons.phone_outlined, 'Teléfono', _profile?['phone'] as String?),
      (
        Icons.alternate_email_rounded,
        'Redes sociales',
        _profile?['social_media'] as String?,
      ),
      (
        Icons.interests_outlined,
        'Intereses',
        _profile?['interests'] as String?,
      ),
      (
        Icons.history_edu_outlined,
        'Carrera anterior / ocupación',
        _profile?['previous_career'] as String?,
      ),
      (
        Icons.work_outline_rounded,
        'Trabajo o profesión',
        _profile?['occupation'] as String?,
      ),
    ].where((d) => (d.$3?.trim().isNotEmpty ?? false)).toList();

    return Scaffold(
      appBar: AppBar(title: Text(name)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  _error!,
                  style: const TextStyle(color: AppColors.error),
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.only(bottom: 40),
              children: [
                _banner(photoUrl),
                const SizedBox(height: 56),
                Text(
                  name,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (bio != null && bio.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Text(
                      bio,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: AppColors.textSecondary),
                    ),
                  ),
                ],
                if (extraPhotos.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  SizedBox(
                    height: 96,
                    child: ListView.separated(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      scrollDirection: Axis.horizontal,
                      itemCount: extraPhotos.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 10),
                      itemBuilder: (_, i) => ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: Image.network(
                          extraPhotos[i],
                          width: 96,
                          height: 96,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
                            width: 96,
                            height: 96,
                            color: AppColors.primary.withValues(alpha: 0.1),
                            child: const Icon(Icons.broken_image_outlined),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
                if (details.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: _infoCard(details),
                  ),
                ],
                if (_puedeVerFicha) ...[
                  const SizedBox(height: 16),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: OutlinedButton.icon(
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => StudentProfileScreen(
                            career: widget.career!,
                            studentId: widget.userId,
                            studentName: name,
                          ),
                        ),
                      ),
                      icon: const Icon(Icons.grading_outlined, size: 18),
                      label: const Text('Ver notas y asistencia'),
                    ),
                  ),
                ],
                if (bio == null && extraPhotos.isEmpty && details.isEmpty) ...[
                  const SizedBox(height: 20),
                  const Center(
                    child: Text(
                      'Todavía no completó su perfil.',
                      style: TextStyle(color: AppColors.textSecondary),
                    ),
                  ),
                ],
                const SizedBox(height: 28),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: _commentsSection(),
                ),
              ],
            ),
    );
  }

  Widget _banner(String? photoUrl) {
    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.topCenter,
      children: [
        Container(
          height: 120,
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [AppColors.primary, AppColors.primaryLight],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        Positioned(
          top: 76,
          child: Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: Theme.of(context).scaffoldBackgroundColor,
              shape: BoxShape.circle,
            ),
            child: CircleAvatar(
              radius: 48,
              backgroundColor: AppColors.primary.withValues(alpha: 0.15),
              backgroundImage: (photoUrl != null && photoUrl.isNotEmpty)
                  ? NetworkImage(photoUrl)
                  : null,
              child: (photoUrl == null || photoUrl.isEmpty)
                  ? const Icon(Icons.person, size: 44, color: AppColors.primary)
                  : null,
            ),
          ),
        ),
      ],
    );
  }

  Widget _infoCard(List<(IconData, String, String?)> details) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          for (final d in details)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(d.$1, size: 18, color: AppColors.primary),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    '${d.$2}: ',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  Expanded(child: Text(d.$3!)),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _commentsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Comentarios (${_comments.length})',
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
        ),
        const SizedBox(height: 4),
        const Text(
          'Visibles para toda tu carrera.',
          style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
        ),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: TextField(
                controller: _commentController,
                maxLength: 300,
                decoration: const InputDecoration(
                  hintText: 'Dejá un comentario…',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              icon: _sending
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.send, color: AppColors.primary),
              onPressed: _sending ? null : _sendComment,
            ),
          ],
        ),
        const SizedBox(height: 8),
        for (final c in _comments) _commentTile(c),
      ],
    );
  }

  Widget _commentTile(Map<String, dynamic> c) {
    final canDelete = c['created_by'] == _myId || _esMiPropioPerfil;
    final createdAt = DateTime.tryParse(c['created_at'].toString());
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      (c['created_by_name'] as String?) ?? 'Alguien',
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                    if (createdAt != null) ...[
                      const SizedBox(width: 6),
                      Text(
                        DateFormat(
                          'd MMM, HH:mm',
                          'es',
                        ).format(createdAt.toLocal()),
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(c['text'] as String? ?? ''),
              ],
            ),
          ),
          if (canDelete)
            InkWell(
              onTap: () => _deleteComment(c['id'].toString()),
              child: const Padding(
                padding: EdgeInsets.all(4),
                child: Icon(
                  Icons.close,
                  size: 16,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
