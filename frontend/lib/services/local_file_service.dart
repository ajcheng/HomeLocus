import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

class LocalFileService {
  final _uuid = const Uuid();

  Future<String> saveImageFromPicker(String sourcePath) async {
    final bytes = await File(sourcePath).readAsBytes();
    final ext = p.extension(sourcePath);
    return saveImageBytes(bytes, ext: ext.isEmpty ? '.jpg' : ext);
  }

  Future<String> saveImageBytes(Uint8List bytes, {String ext = '.jpg'}) async {
    final dir = await _imagesDir();
    final dest = p.join(dir.path, '${_uuid.v4()}$ext');
    final file = File(dest);
    await file.writeAsBytes(bytes, flush: true);
    return dest;
  }

  Future<String> saveAudio(File source) async {
    final dir = await _audioDir();
    final ext = p.extension(source.path).isEmpty ? '.wav' : p.extension(source.path);
    final dest = p.join(dir.path, '${_uuid.v4()}$ext');
    await source.copy(dest);
    return dest;
  }

  Future<String> imagesRootPath() async {
    final base = await getApplicationDocumentsDirectory();
    return p.join(base.path, 'images');
  }

  Future<Directory> _imagesDir() async {
    final base = await getApplicationDocumentsDirectory();
    final now = DateTime.now();
    final dated = p.join(
      base.path,
      'images',
      now.year.toString(),
      now.month.toString().padLeft(2, '0'),
      now.day.toString().padLeft(2, '0'),
    );
    final dir = Directory(dated);
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  Future<Directory> _audioDir() async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(base.path, 'audio'));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }
}
