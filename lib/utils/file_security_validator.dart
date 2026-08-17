import 'dart:typed_data';
import 'package:path/path.dart' as path;

class FileValidationResult {
  final bool isValid;
  final String? errorMessage;
  final String fileCategory; // Documento, Imagen, Audio, Video, Otro

  FileValidationResult({
    required this.isValid,
    this.errorMessage,
    this.fileCategory = 'Otro',
  });
}

class FileSecurityValidator {
  static const int maxFileSizeMb = 250;
  static const int maxFileSizeBytes = maxFileSizeMb * 1024 * 1024;

  static const Set<String> _allowedExtensions = {
    // Documentos
    'pdf', 'txt', 'rtf', 'csv', 'tsv', 'json', 'epub',
    'docx', 'xlsx', 'pptx',
    'odt', 'ods', 'odp',
    'pages', 'numbers', 'key',
    // Imágenes
    'jpg', 'jpeg', 'png', 'webp', 'gif', 'heic', 'bmp', 'tiff', 'svg',
    // Audio
    'mp3', 'm4a', 'wav', 'ogg', 'aac',
    // Video
    'mp4', 'webm', 'mov', 'mkv',
  };

  static const Set<String> _blockedExtensions = {
    'exe', 'bat', 'cmd', 'sh', 'vbs', 'js', 'apk', 'app', 'msi', 'jar',
    'zip', 'rar', '7z', 'tar', 'gz', 'iso', 'bin', 'scr', 'pif', 'chm',
  };

  /// Valida el nombre, extensión, tamaño y cabecera de bytes del archivo.
  ///
  /// [bytes] solo necesita los primeros bytes del archivo: la inspección de
  /// magic bytes nunca mira más allá del cuarto. No hay que pasarle el archivo
  /// completo — cargar en memoria un video de 250 MB es justamente lo que
  /// cerraba la app en Android.
  static FileValidationResult validateFile({
    required String fileName,
    required int sizeInBytes,
    required Uint8List bytes,
  }) {
    // 1. Validar tamaño
    if (sizeInBytes > maxFileSizeBytes) {
      return FileValidationResult(
        isValid: false,
        errorMessage:
            'El archivo supera el límite máximo permitido de $maxFileSizeMb MB.',
      );
    }

    if (sizeInBytes == 0) {
      return FileValidationResult(
        isValid: false,
        errorMessage: 'El archivo está vacío (0 bytes).',
      );
    }

    // 2. Extraer extensión
    final ext = path.extension(fileName).toLowerCase().replaceAll('.', '').trim();

    if (ext.isEmpty) {
      return FileValidationResult(
        isValid: false,
        errorMessage: 'El archivo debe tener una extensión válida (ej: .pdf, .docx, .png).',
      );
    }

    if (_blockedExtensions.contains(ext)) {
      return FileValidationResult(
        isValid: false,
        errorMessage: 'Por seguridad, no se permiten archivos ejecutables ni comprimidos (.$ext).',
      );
    }

    if (!_allowedExtensions.contains(ext)) {
      return FileValidationResult(
        isValid: false,
        errorMessage: 'El formato .$ext no está en la lista de formatos de estudio permitidos.',
      );
    }

    // 3. Inspección por Bytes Mágicos (Magic Bytes) para prevenir virus disfrazados
    if (bytes.length >= 2) {
      // Bloquear ejecutables Windows PE (.exe / .dll disfrazados) -> "MZ"
      if (bytes[0] == 0x4D && bytes[1] == 0x5A) {
        return FileValidationResult(
          isValid: false,
          errorMessage: 'Seguridad: Se detectó un archivo ejecutable binario de Windows disfrazado.',
        );
      }

      // Bloquear binarios ELF (Linux / Android) -> 0x7F 'E' 'L' 'F'
      if (bytes.length >= 4 &&
          bytes[0] == 0x7F &&
          bytes[1] == 0x45 &&
          bytes[2] == 0x4C &&
          bytes[3] == 0x46) {
        return FileValidationResult(
          isValid: false,
          errorMessage: 'Seguridad: Se detectó un binario ejecutable de Linux/Android disfrazado.',
        );
      }

      // Bloquear scripts de terminal Shell -> "#!"
      if (bytes[0] == 0x23 && bytes[1] == 0x21) {
        return FileValidationResult(
          isValid: false,
          errorMessage: 'Seguridad: Se detectó un script de terminal ejecutable.',
        );
      }

      // Bloquear Java bytecode -> 0xCA 0xFE 0xBA 0xBE
      if (bytes.length >= 4 &&
          bytes[0] == 0xCA &&
          bytes[1] == 0xFE &&
          bytes[2] == 0xBA &&
          bytes[3] == 0xBE) {
        return FileValidationResult(
          isValid: false,
          errorMessage: 'Seguridad: Se detectó un ejecutable Java bytecode disfrazado.',
        );
      }
    }

    // Determinar categoría
    String category = 'Documento';
    if (['jpg', 'jpeg', 'png', 'webp', 'gif', 'heic', 'bmp', 'tiff', 'svg'].contains(ext)) {
      category = 'Imagen';
    } else if (['mp3', 'm4a', 'wav', 'ogg', 'aac'].contains(ext)) {
      category = 'Audio';
    } else if (['mp4', 'webm', 'mov', 'mkv'].contains(ext)) {
      category = 'Video';
    }

    return FileValidationResult(
      isValid: true,
      fileCategory: category,
    );
  }
}
