import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'custom_file_picker.dart';

Future<PickedFileData?> pickFilePlatform() async {
  try {
    // withData: false a propósito. Con `true`, el plugin reserva del lado
    // Android un arreglo del tamaño completo del archivo
    // (FileUtils.loadData): con un video de 250 MB eso supera el techo de
    // memoria que Android le da a la app y la cierra sin mensaje, porque
    // OutOfMemoryError es un Error y el plugin solo atrapa Exception.
    final result = await FilePicker.platform.pickFiles(
      type: FileType.any,
      withData: false,
      allowMultiple: false,
    );
    if (result == null || result.files.isEmpty) return null;
    final file = result.files.first;

    final path = file.path;
    if (path == null || path.isEmpty) return null;

    final head = await _readHead(path);
    if (head == null) return null;

    return PickedFileData(
      name: file.name,
      size: file.size,
      extension: file.extension ?? '',
      path: path,
      head: head,
    );
  } catch (e) {
    return null;
  }
}

/// Lee solo el principio del archivo, para validar la cabecera.
Future<Uint8List?> _readHead(String path) async {
  RandomAccessFile? handle;
  try {
    handle = await File(path).open();
    return await handle.read(CustomFilePicker.headBytes);
  } catch (e) {
    return null;
  } finally {
    await handle?.close();
  }
}

Future<void> clearTemporaryFilesPlatform() async {
  try {
    await FilePicker.platform.clearTemporaryFiles();
  } catch (e) {
    // Es limpieza best-effort: si falla, solo queda el archivo en la caché.
  }
}
