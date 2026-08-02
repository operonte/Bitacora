import 'package:file_picker/file_picker.dart';
import 'custom_file_picker.dart';

Future<PickedFileData?> pickFilePlatform() async {
  try {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.any,
      withData: true,
      allowMultiple: false,
    );
    if (result == null || result.files.isEmpty) return null;
    final file = result.files.first;
    final bytes = file.bytes;
    if (bytes == null) return null;
    return PickedFileData(
      name: file.name,
      bytes: bytes,
      size: file.size,
      extension: file.extension ?? '',
    );
  } catch (e) {
    return null;
  }
}
