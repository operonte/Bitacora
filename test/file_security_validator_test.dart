import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:bitacora/utils/file_security_validator.dart';

void main() {
  group('FileSecurityValidator.validateFile', () {
    test('accepts a plain document with an allowed extension', () {
      final result = FileSecurityValidator.validateFile(
        fileName: 'apuntes.pdf',
        sizeInBytes: 1024,
        bytes: Uint8List.fromList([0x25, 0x50, 0x44, 0x46]), // "%PDF"
      );

      expect(result.isValid, isTrue);
      expect(result.fileCategory, 'Documento');
    });

    test('categorizes images, audio and video correctly', () {
      final harmlessBytes = Uint8List.fromList([1, 2, 3, 4]);

      expect(
        FileSecurityValidator.validateFile(
          fileName: 'foto.png',
          sizeInBytes: 10,
          bytes: harmlessBytes,
        ).fileCategory,
        'Imagen',
      );
      expect(
        FileSecurityValidator.validateFile(
          fileName: 'clase.mp3',
          sizeInBytes: 10,
          bytes: harmlessBytes,
        ).fileCategory,
        'Audio',
      );
      expect(
        FileSecurityValidator.validateFile(
          fileName: 'clase.mp4',
          sizeInBytes: 10,
          bytes: harmlessBytes,
        ).fileCategory,
        'Video',
      );
    });

    test('rejects files over the 50 MB limit', () {
      final result = FileSecurityValidator.validateFile(
        fileName: 'grande.pdf',
        sizeInBytes: FileSecurityValidator.maxFileSizeBytes + 1,
        bytes: Uint8List.fromList([1, 2, 3]),
      );

      expect(result.isValid, isFalse);
    });

    test('accepts files right at the limit', () {
      final result = FileSecurityValidator.validateFile(
        fileName: 'justo.pdf',
        sizeInBytes: FileSecurityValidator.maxFileSizeBytes,
        bytes: Uint8List.fromList([1, 2, 3]),
      );

      expect(result.isValid, isTrue);
    });

    test('rejects empty files', () {
      final result = FileSecurityValidator.validateFile(
        fileName: 'vacio.pdf',
        sizeInBytes: 0,
        bytes: Uint8List.fromList([]),
      );

      expect(result.isValid, isFalse);
    });

    test('rejects files without an extension', () {
      final result = FileSecurityValidator.validateFile(
        fileName: 'sinextension',
        sizeInBytes: 10,
        bytes: Uint8List.fromList([1, 2, 3]),
      );

      expect(result.isValid, isFalse);
    });

    test('rejects blocklisted extensions like .exe regardless of content', () {
      final result = FileSecurityValidator.validateFile(
        fileName: 'instalador.exe',
        sizeInBytes: 10,
        bytes: Uint8List.fromList([1, 2, 3]),
      );

      expect(result.isValid, isFalse);
    });

    test('rejects extensions outside the allowlist', () {
      final result = FileSecurityValidator.validateFile(
        fileName: 'script.py',
        sizeInBytes: 10,
        bytes: Uint8List.fromList([1, 2, 3]),
      );

      expect(result.isValid, isFalse);
    });

    test('rejects a Windows executable disguised with a .pdf extension', () {
      final result = FileSecurityValidator.validateFile(
        fileName: 'inocente.pdf',
        sizeInBytes: 100,
        bytes: Uint8List.fromList([0x4D, 0x5A, 0x00, 0x00]), // "MZ"
      );

      expect(result.isValid, isFalse);
      expect(result.errorMessage, contains('Windows'));
    });

    test('rejects an ELF binary disguised with a .png extension', () {
      final result = FileSecurityValidator.validateFile(
        fileName: 'imagen.png',
        sizeInBytes: 100,
        bytes: Uint8List.fromList([0x7F, 0x45, 0x4C, 0x46]),
      );

      expect(result.isValid, isFalse);
      expect(result.errorMessage, contains('Linux'));
    });

    test('rejects a shell script disguised with a .txt extension', () {
      final result = FileSecurityValidator.validateFile(
        fileName: 'notas.txt',
        sizeInBytes: 100,
        bytes: Uint8List.fromList([0x23, 0x21, 0x2F, 0x62]), // "#!/b..."
      );

      expect(result.isValid, isFalse);
      expect(result.errorMessage, contains('script'));
    });

    test('rejects Java bytecode disguised with a .docx extension', () {
      final result = FileSecurityValidator.validateFile(
        fileName: 'informe.docx',
        sizeInBytes: 100,
        bytes: Uint8List.fromList([0xCA, 0xFE, 0xBA, 0xBE]),
      );

      expect(result.isValid, isFalse);
      expect(result.errorMessage, contains('Java'));
    });
  });
}
