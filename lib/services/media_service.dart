import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../main.dart';

/// Выбор, загрузка и скачивание медиа в Storage bucket 'chat-media'.
class MediaService {
  static final _picker = ImagePicker();

  /// Картинка из галереи (для отправки фото в чат).
  static Future<XFile?> pickPhoto() {
    return _picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1920,
      imageQuality: 90,
    );
  }

  /// Картинка для аватара — уменьшенная.
  static Future<XFile?> pickImage() {
    return _picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1024,
      imageQuality: 85,
    );
  }

  /// Видео из галереи.
  static Future<XFile?> pickVideo() {
    return _picker.pickVideo(
      source: ImageSource.gallery,
      maxDuration: const Duration(minutes: 5),
    );
  }

  /// Любой файл (в т.ч. фото/видео) через системный диалог.
  static Future<PlatformFile?> pickAnyFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.any,
      allowMultiple: false,
    );
    return result?.files.first;
  }

  static const _imageExt = ['jpg', 'jpeg', 'png', 'webp', 'gif', 'bmp'];
  static const _videoExt = ['mp4', 'mov', 'webm', 'mkv', 'avi', '3gp'];

  static String _ext(String name) {
    final i = name.lastIndexOf('.');
    return i < 0 ? '' : name.substring(i + 1).toLowerCase();
  }

  static bool isImage(String name) => _imageExt.contains(_ext(name));
  static bool isVideo(String name) => _videoExt.contains(_ext(name));

  /// Тип сообщения по имени файла: image | video | file
  static String kindOf(String name) {
    if (isImage(name)) return 'image';
    if (isVideo(name)) return 'video';
    return 'file';
  }

  static String _contentType(String name) {
    switch (_ext(name)) {
      case 'png':
        return 'image/png';
      case 'webp':
        return 'image/webp';
      case 'gif':
        return 'image/gif';
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'mp4':
        return 'video/mp4';
      case 'webm':
        return 'video/webm';
      case 'mov':
        return 'video/quicktime';
      case 'mp3':
        return 'audio/mpeg';
      case 'wav':
        return 'audio/wav';
      case 'ogg':
        return 'audio/ogg';
      case 'pdf':
        return 'application/pdf';
      case 'txt':
        return 'text/plain';
      case 'zip':
        return 'application/zip';
      case 'doc':
        return 'application/msword';
      case 'docx':
        return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
      default:
        return 'application/octet-stream';
    }
  }

  static Future<String> _uploadFile(
      String path, File file, String contentType) async {
    await supabase.storage.from('chat-media').upload(
          path,
          file,
          fileOptions:
              FileOptions(contentType: contentType, upsert: true),
        );
    return supabase.storage.from('chat-media').getPublicUrl(path);
  }

  /// Загрузить произвольный файл. Возвращает публичный URL.
  static Future<String> uploadFile(PlatformFile file) async {
    final ts = DateTime.now().millisecondsSinceEpoch;
    final name = file.name;
    final path = 'files/$ts-$name';
    return _uploadFile(path, File(file.path!), _contentType(name));
  }

  /// Загрузить фото/видео из галереи (XFile). Возвращает публичный URL.
  static Future<String> uploadMedia(XFile file, String folder) async {
    final ts = DateTime.now().millisecondsSinceEpoch;
    final name = file.name.isEmpty ? 'file.bin' : file.name;
    final path = '$folder/$ts-$name';
    return _uploadFile(path, File(file.path), _contentType(name));
  }

  static Future<String> uploadPhoto(XFile file) => uploadMedia(file, 'photos');
  static Future<String> uploadVideo(XFile file) => uploadMedia(file, 'videos');

  /// Аватарка профиля. Возвращает публичный URL.
  static Future<String> uploadAvatar(String userId, XFile file) {
    final ts = DateTime.now().millisecondsSinceEpoch;
    return _uploadFile(
        'avatars/$userId-$ts.jpg', File(file.path), 'image/jpeg');
  }

  /// Аватарка группы/канала.
  static Future<String> uploadChatAvatar(String chatId, XFile file) {
    final ts = DateTime.now().millisecondsSinceEpoch;
    return _uploadFile(
        'groups/$chatId-$ts.jpg', File(file.path), 'image/jpeg');
  }

  /// Размер файла по публичному URL (байты). 0 — если не удалось определить.
  static Future<int> remoteSize(String url) async {
    try {
      final client = HttpClient();
      final req = await client.getUrl(Uri.parse(url));
      final res = await req.close();
      final len = res.contentLength;
      res.drain<void>();
      client.close();
      return len;
    } catch (e) {
      debugPrint('Не удалось получить размер файла: $e');
      return 0;
    }
  }

  /// Скачать файл на устройство. Возвращает путь к сохранённому файлу.
  static Future<String> download(String url, String fileName) async {
    final client = HttpClient();
    final req = await client.getUrl(Uri.parse(url));
    final res = await req.close();
    if (res.statusCode != 200) {
      client.close();
      throw Exception('Сервер ответил кодом ${res.statusCode}');
    }

    // Android — публичная папка «Загрузки», остальные — «Загрузки» пользователя
    final dir = Platform.isAndroid
        ? await getExternalStorageDirectory()
        : await getDownloadsDirectory();
    final base = dir ??
        await getApplicationDocumentsDirectory();

    // Имя файла без служебного префикса загрузки
    var name = fileName;
    final i = name.lastIndexOf('-');
    if (i > 0 && i < name.length - 1) {
      final tail = name.substring(i + 1);
      if (RegExp(r'^\d+\.').hasMatch(tail)) name = tail;
    }
    final target = File('${base.path}/$name');

    final sink = target.openWrite();
    await res.pipe(sink);
    await sink.flush();
    await sink.close();
    client.close();

    return target.path;
  }

  /// Человекочитаемый размер файла: 1.2 МБ
  static String humanSize(int bytes) {
    if (bytes <= 0) return '';
    const units = ['Б', 'КБ', 'МБ', 'ГБ'];
    var v = bytes.toDouble();
    var u = 0;
    while (v >= 1024 && u < units.length - 1) {
      v /= 1024;
      u++;
    }
    final s = v >= 100 || v == v.roundToDouble()
        ? v.toStringAsFixed(0)
        : v.toStringAsFixed(1);
    return '$s ${units[u]}';
  }
}