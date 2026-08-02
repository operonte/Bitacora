// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:async';
import 'dart:html' as html;
import 'dart:typed_data';
import 'custom_file_picker.dart';

Future<PickedFileData?> pickFilePlatform() async {
  final completer = Completer<PickedFileData?>();
  final uploadInput = html.FileUploadInputElement();
  uploadInput.accept = '*/*';
  uploadInput.click();

  uploadInput.onChange.listen((e) async {
    final files = uploadInput.files;
    if (files == null || files.isEmpty) {
      if (!completer.isCompleted) completer.complete(null);
      return;
    }
    final file = files.first;
    final reader = html.FileReader();
    reader.readAsArrayBuffer(file);
    await reader.onLoadEnd.first;

    final res = reader.result;
    Uint8List? bytes;
    if (res is Uint8List) {
      bytes = res;
    } else if (res is ByteBuffer) {
      bytes = Uint8List.view(res);
    }

    if (bytes != null && !completer.isCompleted) {
      completer.complete(PickedFileData(
        name: file.name,
        bytes: bytes,
        size: file.size,
        extension: file.name.contains('.') ? file.name.split('.').last : '',
      ));
    } else {
      if (!completer.isCompleted) completer.complete(null);
    }
  });

  return completer.future;
}
