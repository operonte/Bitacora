import 'package:flutter/material.dart';

import '../colors.dart';
import '../services/profile_service.dart';

/// Perfil público de otra persona de tu carrera: solo lectura. El servidor
/// (get_public_profile) ya exige que compartas una carrera con ella; acá
/// solo se pinta lo que llegó.
class PublicProfileScreen extends StatefulWidget {
  final String userId;
  final String fallbackName;

  const PublicProfileScreen({
    super.key,
    required this.userId,
    required this.fallbackName,
  });

  @override
  State<PublicProfileScreen> createState() => _PublicProfileScreenState();
}

class _PublicProfileScreenState extends State<PublicProfileScreen> {
  Map<String, dynamic>? _profile;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final profile = await ProfileService().getPublicProfile(widget.userId);
      if (mounted) setState(() => _profile = profile);
    } catch (e) {
      if (mounted) {
        setState(() => _error = e.toString().replaceAll('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
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
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 40),
              children: [
                Center(
                  child: CircleAvatar(
                    radius: 52,
                    backgroundColor: AppColors.primary.withValues(alpha: 0.15),
                    backgroundImage: (photoUrl != null && photoUrl.isNotEmpty)
                        ? NetworkImage(photoUrl)
                        : null,
                    child: (photoUrl == null || photoUrl.isEmpty)
                        ? const Icon(
                            Icons.person,
                            size: 48,
                            color: AppColors.primary,
                          )
                        : null,
                  ),
                ),
                const SizedBox(height: 12),
                Center(
                  child: Text(
                    name,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                if (bio != null && bio.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Text(bio, textAlign: TextAlign.center),
                ],
                if (extraPhotos.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  SizedBox(
                    height: 100,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: extraPhotos.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 10),
                      itemBuilder: (_, i) => ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.network(
                          extraPhotos[i],
                          width: 100,
                          height: 100,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
                            width: 100,
                            height: 100,
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
                  Container(
                    padding: const EdgeInsets.all(16),
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
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            child: Row(
                              children: [
                                Icon(d.$1, size: 20, color: AppColors.primary),
                                const SizedBox(width: 12),
                                Text(
                                  '${d.$2}: ',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                Expanded(child: Text(d.$3!)),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
                if (bio == null && extraPhotos.isEmpty && details.isEmpty) ...[
                  const SizedBox(height: 24),
                  const Center(
                    child: Text(
                      'Todavía no completó su perfil.',
                      style: TextStyle(color: AppColors.textSecondary),
                    ),
                  ),
                ],
              ],
            ),
    );
  }
}
