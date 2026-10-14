import 'dart:io';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';

Future<String?> saveBytes(String name, List<int> bytes) async {
  final path = await FilePicker.platform.saveFile(
    dialogTitle: 'Salvar arquivo',
    fileName: name,
    type: FileType.custom,
    allowedExtensions: [name.split('.').last],
    bytes: Uint8List.fromList(bytes),
  );
  // Desktop picker only supplies a path. Android writes the supplied bytes through SAF.
  if (path != null &&
      (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
    await File(path).writeAsBytes(bytes, flush: true);
  }
  return path;
}
