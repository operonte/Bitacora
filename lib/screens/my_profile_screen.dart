import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../colors.dart';
import '../services/profile_service.dart';
import '../utils/custom_file_picker.dart';
import '../utils/file_security_validator.dart';
import '../utils/input_sanitizer.dart';

/// Mi perfil: lo que antes era un diálogo con nombre y una URL de foto
/// pegada a mano, ahora una pantalla propia con foto subida de verdad, bio
/// y datos personales opcionales. Cada campo lo llena quien es dueño del
/// perfil — nada se completa solo.
class MyProfileScreen extends StatefulWidget {
  const MyProfileScreen({super.key});

  @override
  State<MyProfileScreen> createState() => _MyProfileScreenState();
}

class _MyProfileScreenState extends State<MyProfileScreen> {
  final _service = ProfileService();
  final _nameController = TextEditingController();
  final _bioController = TextEditingController();
  final _ageController = TextEditingController();
  final _genderController = TextEditingController();
  final _relationshipController = TextEditingController();
  final _religionController = TextEditingController();

  Map<String, dynamic>? _profile;
  bool _loading = true;
  bool _saving = false;
  bool _uploadingPhoto = false;
  double _uploadProgress = 0;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _bioController.dispose();
    _ageController.dispose();
    _genderController.dispose();
    _relationshipController.dispose();
    _religionController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final profile = await _service.getMyProfile();
      if (!mounted) return;
      setState(() {
        _profile = profile;
        _nameController.text = (profile?['display_name'] as String?) ?? '';
        _bioController.text = (profile?['bio'] as String?) ?? '';
        _ageController.text = profile?['age']?.toString() ?? '';
        _genderController.text = (profile?['gender'] as String?) ?? '';
        _relationshipController.text =
            (profile?['relationship_status'] as String?) ?? '';
        _religionController.text = (profile?['religion'] as String?) ?? '';
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceAll('Exception: ', '');
        _loading = false;
      });
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final name = InputSanitizer.sanitizeText(_nameController.text);
      if (name.isNotEmpty) {
        await Supabase.instance.client.auth.updateUser(
          UserAttributes(data: {'full_name': name}),
        );
      }
      final ageText = _ageController.text.trim();
      await _service.updateMyProfile(
        bio: InputSanitizer.sanitizeText(_bioController.text),
        age: ageText.isEmpty ? null : int.tryParse(ageText),
        gender: InputSanitizer.sanitizeText(_genderController.text),
        relationshipStatus: InputSanitizer.sanitizeText(
          _relationshipController.text,
        ),
        religion: InputSanitizer.sanitizeText(_religionController.text),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Perfil actualizado'),
          backgroundColor: AppColors.success,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('No se pudo guardar: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _pickAndUpload({required bool asMainPhoto}) async {
    try {
      final file = await CustomFilePicker.pickFile();
      if (file == null) return;
      if (file.head.isEmpty) return;

      final validation = FileSecurityValidator.validateFile(
        fileName: file.name,
        sizeInBytes: file.size,
        bytes: file.head,
      );
      if (!validation.isValid || validation.fileCategory != 'Imagen') {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                validation.isValid
                    ? 'Elegí una imagen (jpg, png, webp).'
                    : (validation.errorMessage ?? 'Archivo no permitido.'),
              ),
            ),
          );
        }
        return;
      }

      setState(() {
        _uploadingPhoto = true;
        _uploadProgress = 0;
      });

      final url = await _service.uploadPhoto(
        fileName: file.name,
        sizeBytes: file.size,
        extension: file.extension,
        filePath: file.path,
        bytes: file.bytes,
        onProgress: (p) {
          if (mounted) setState(() => _uploadProgress = p);
        },
      );

      if (asMainPhoto) {
        await _service.setMainPhoto(url);
      } else {
        await _service.addExtraPhoto(url);
      }
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceAll('Exception: ', ''))),
        );
      }
    } finally {
      if (mounted) setState(() => _uploadingPhoto = false);
    }
  }

  Future<void> _removeExtraPhoto(String url) async {
    try {
      await _service.removeExtraPhoto(url);
      await _load();
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mi perfil'),
        actions: [
          if (!_loading)
            TextButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text(
                      'Guardar',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
            ),
        ],
      ),
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
                Center(child: _avatarPicker()),
                const SizedBox(height: 24),
                _card(
                  title: 'Sobre mí',
                  children: [
                    TextField(
                      controller: _nameController,
                      decoration: const InputDecoration(
                        labelText: 'Nombre',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _bioController,
                      maxLines: 3,
                      maxLength: 300,
                      decoration: const InputDecoration(
                        labelText: 'Bio (opcional)',
                        hintText: 'Contá algo sobre vos',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _card(
                  title: 'Fotos',
                  subtitle:
                      'Hasta ${ProfileService.maxExtraPhotos} fotos además de tu foto principal.',
                  children: [_extraPhotosStrip()],
                ),
                const SizedBox(height: 16),
                _card(
                  title: 'Información personal',
                  subtitle:
                      'Todo opcional, y visible para el resto de tu carrera.',
                  children: [
                    TextField(
                      controller: _ageController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Edad (opcional)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _genderController,
                      decoration: const InputDecoration(
                        labelText: 'Género (opcional)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _relationshipController,
                      decoration: const InputDecoration(
                        labelText: 'Situación sentimental (opcional)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _religionController,
                      decoration: const InputDecoration(
                        labelText: 'Creencias / religión (opcional)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ],
                ),
              ],
            ),
    );
  }

  Widget _avatarPicker() {
    final photoUrl = _profile?['photo_url'] as String?;
    return GestureDetector(
      onTap: _uploadingPhoto ? null : () => _pickAndUpload(asMainPhoto: true),
      child: Stack(
        children: [
          CircleAvatar(
            radius: 52,
            backgroundColor: AppColors.primary.withValues(alpha: 0.15),
            backgroundImage: (photoUrl != null && photoUrl.isNotEmpty)
                ? NetworkImage(photoUrl)
                : null,
            child: (photoUrl == null || photoUrl.isEmpty)
                ? const Icon(Icons.person, size: 48, color: AppColors.primary)
                : null,
          ),
          if (_uploadingPhoto)
            Positioned.fill(
              child: CircleAvatar(
                backgroundColor: Colors.black.withValues(alpha: 0.4),
                child: Text(
                  '${(_uploadProgress * 100).round()}%',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            )
          else
            Positioned(
              right: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: const BoxDecoration(
                  color: AppColors.primary,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.camera_alt,
                  size: 16,
                  color: Colors.white,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _extraPhotosStrip() {
    final photos = List<String>.from(
      (_profile?['extra_photo_urls'] as List?) ?? [],
    );
    return SizedBox(
      height: 84,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          for (final url in photos)
            Padding(
              padding: const EdgeInsets.only(right: 10),
              child: Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.network(
                      url,
                      width: 84,
                      height: 84,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        width: 84,
                        height: 84,
                        color: AppColors.primary.withValues(alpha: 0.1),
                        child: const Icon(Icons.broken_image_outlined),
                      ),
                    ),
                  ),
                  Positioned(
                    right: 2,
                    top: 2,
                    child: GestureDetector(
                      onTap: () => _removeExtraPhoto(url),
                      child: const CircleAvatar(
                        radius: 11,
                        backgroundColor: Colors.black54,
                        child: Icon(Icons.close, size: 14, color: Colors.white),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          if (photos.length < ProfileService.maxExtraPhotos)
            InkWell(
              onTap: _uploadingPhoto
                  ? null
                  : () => _pickAndUpload(asMainPhoto: false),
              borderRadius: BorderRadius.circular(12),
              child: Container(
                width: 84,
                height: 84,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: AppColors.primary.withValues(alpha: 0.4),
                  ),
                ),
                child: const Icon(
                  Icons.add_a_photo_outlined,
                  color: AppColors.primary,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _card({
    required String title,
    String? subtitle,
    required List<Widget> children,
  }) {
    return Container(
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
            ),
          ],
          const SizedBox(height: 14),
          ...children,
        ],
      ),
    );
  }
}
