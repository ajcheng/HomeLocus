import 'dart:io';
import 'dart:typed_data';

import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

class LocalFileService {
  final _uuid = const Uuid();

  /// 从相机/相册 XFile 保存到应用私有目录（无需外部存储权限）
  Future<String> saveImageFromPicker(XFile picked) async {
    final bytes = await picked.readAsBytes();
    final ext = p.extension(picked.path);
    return saveImageBytes(bytes, ext: ext.isEmpty ? '.jpg' : ext);
  }

  Future<String> saveImageBytes(Uint8List bytes, {String ext = '.jpg'}) async {
    final dir = await _imagesDir();
    final dest = p.join(dir.path, '${_uuid.v4()}$ext');
    final file = File(dest);
    await file.writeAsBytes(bytes, flush: true);
    if (!await file.exists() || await file.length() == 0) {
      throw Exception('图片写入失败: $dest');
    }
    return dest;
  }

  Future<String> saveImage(File source) async {
    if (!await source.exists()) {
      throw Exception('源图片不存在: ${source.path}');
    }
    final bytes = await source.readAsBytes();
    final ext = p.extension(source.path);
    return saveImageBytes(bytes, ext: ext.isEmpty ? '.jpg' : ext);
  }

  Future<String> imagesRootPath() async {
    final base = await getApplicationDocumentsDirectory();
    return p.join(base.path, 'images');
  }

  Future<bool> imageExists(String? path) async {
    if (path == null || path.isEmpty) return false;
    return File(path).exists();
  }

  Future<String> saveAudio(File source) async {
    final dir = await _audioDir();
    final ext = p.extension(source.path).isEmpty ? '.wav' : p.extension(source.path);
    final dest = p.join(dir.path, '${_uuid.v4()}$ext');
    await source.copy(dest);
    return dest;
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
