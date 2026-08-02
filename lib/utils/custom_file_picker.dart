import 'dart:typed_data';

import 'picker_stub.dart'
    if (dart.library.html) 'picker_web.dart' as impl;

class PickedFileData {
  final String name;
  final Uint8List bytes;
  final int size;
  final String extension;

  PickedFileData({
    required this.name,
    required this.bytes,
    required this.size,
    required this.extension,
  });
}

class CustomFilePicker {
  static Future<PickedFileData?> pickFile() async {
    return await impl.pickFilePlatform();
  }
}
