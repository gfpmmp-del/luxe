import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../main.dart';
import '../config/supabase_config.dart';

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

  /// Голосовое сообщение. Файл уже лежит на диске после записи.
  ///
  /// Расширение и content-type берём из самого файла: Android и iOS пишут
  /// AAC в контейнер m4a, а Windows — в сырой ADTS (.aac). Если назвать
  /// файл .m4a при потоке ADTS, часть плееров откажется его читать.
  static Future<String> uploadVoice(File file) async {
    final ts = DateTime.now().millisecondsSinceEpoch;
    final ext = _ext(file.path);
    final realExt = ext.isEmpty ? 'm4a' : ext;
    final type = realExt == 'aac' ? 'audio/aac' : 'audio/mp4';
    return _uploadFile('voice/$ts.$realExt', file, type);
  }

  /// Кружок: записанный видеофайл с диска.
  static Future<String> uploadCircle(File file) async {
    final ts = DateTime.now().millisecondsSinceEpoch;
    return _uploadFile('circles/$ts.mp4', file, 'video/mp4');
  }

  /// Стикер: картинка, GIF или Lottie.
  static Future<String> uploadSticker(XFile file, String kind) async {
    final ts = DateTime.now().millisecondsSinceEpoch;
    final src = file.name.isEmpty ? file.path : file.name;
    final ext = _ext(src);
    final name = ext.isEmpty
        ? (kind == 'lottie' ? 'sticker.json' : 'sticker.gif')
        : ext;
    final type = switch (kind) {
      'gif' => 'image/gif',
      'lottie' => 'application/json',
      'webp' => 'image/webp',
      _ => 'image/jpeg',
    };
    return _uploadFile('stickers/$ts.$name', File(file.path), type);
  }

  /// Выбрать файл стикера. Разрешены GIF, Lottie (json) и картинки.
  static Future<PlatformFile?> pickStickerFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const [
        'gif',
        'json',
        'tgs',
        'png',
        'jpg',
        'jpeg',
        'webp'
      ],
      allowMultiple: false,
    );
    return result?.files.first;
  }

  /// Тип стикера по расширению: static | gif | lottie
  static String stickerKind(String name) {
    final e = _ext(name);
    if (e == 'json' || e == 'tgs') return 'lottie';
    if (e == 'gif') return 'gif';
    return 'static';
  }

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

  /// Починить ссылку, сохранённую во времена прокси.
  ///
  /// Пока приложение ходило через Cloudflare Worker, в базу писались
  /// ссылки на него. Такие ссылки до сих пор лежат в аватарках, файлах
  /// и голосовых — и они не работают, потому что потоковая отдача
  /// файлов у воркера ломается. Адрес не менялся, поэтому достаточно
  /// подставить настоящий.
  static String? fixUrl(String? url) {
    if (url == null || url.isEmpty) return url;
    if (!url.contains('workers.dev')) return url;
    return url.replaceAll(SupabaseConfig.workerUrl, SupabaseConfig.directUrl);
  }

  /// Починить ссылку в готовой строке сообщения или профиля.
  ///
  /// Так починятся и те сообщения, что уже лежат в памяти на телефоне,
  /// без всякой перезаливки базы.
  static Map<String, dynamic> fixRow(Map<String, dynamic> row) {
    final keys = ['file_url', 'avatar_url'];
    var changed = false;
    for (final k in keys) {
      final v = row[k];
      if (v is String && v.isNotEmpty) {
        final fixed = fixUrl(v);
        if (fixed != v) {
          row[k] = fixed;
          changed = true;
        }
      }
    }
    return changed ? row : row;
  }

  /// Размер файла по публичному URL (байты). 0 — если не удалось определить.
  static Future<int> remoteSize(String url) async {
    final target = fixUrl(url);
    if (target == null) return 0;
    try {
      final client = HttpClient();
      final req = await client.getUrl(Uri.parse(target));
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
    final req = await client.getUrl(Uri.parse(fixUrl(url) ?? url));
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

  /// Длительность аудио/видео файла в секундах. 0 — определить не удалось.
  ///
  /// Считается по размеру контейнера: у mp4 это поле лежит в заголовке
  /// и не требует подключения video_player на этапе отправки.
  static Future<int> durationOf(String path) async {
    try {
      final f = File(path);
      if (!f.existsSync()) return 0;
      final bytes = await f.readAsBytes();
      final d = _mp4Duration(bytes) ?? _wavDuration(bytes);
      return (d ?? 0).ceil();
    } catch (e) {
      debugPrint('Длительность не определилась: $e');
      return 0;
    }
  }

  /// Длительность из атома mvhd бокса moov в mp4/m4a/mov.
  static double? _mp4Duration(List<int> b) {
    // mvhd: версия 0 — 4-байтные поля, версия 1 — 8-байтные.
    for (var i = 0; i + 24 < b.length; i++) {
      if (b[i] == 0x6D && b[i + 1] == 0x76 &&
          b[i + 2] == 0x68 && b[i + 3] == 0x64) {
        final version = b[i + 4];
        if (version == 1) {
          if (i + 32 >= b.length) return null;
          final ts = _u32(b, i + 20);
          final dur = _u64(b, i + 24);
          if (ts == 0) return null;
          return dur / ts;
        }
        final ts = _u32(b, i + 12);
        final dur = _u32(b, i + 16);
        if (ts == 0) return null;
        return dur / ts;
      }
    }
    return null;
  }

  /// Длительность wav по заголовку RIFF.
  static double? _wavDuration(List<int> b) {
    if (b.length < 44) return null;
    if (b[0] != 0x52 || b[1] != 0x49 || b[2] != 0x46 || b[3] != 0x46) {
      return null;
    }
    final byteRate = _u32(b, 40);
    if (byteRate == 0) return null;
    return (b.length - 44) / byteRate;
  }

  static int _u32(List<int> b, int i) =>
      b[i] << 24 | b[i + 1] << 16 | b[i + 2] << 8 | b[i + 3];

  static int _u64(List<int> b, int i) {
    var v = 0;
    for (var k = 0; k < 8; k++) {
      v = v * 256 + b[i + k];
    }
    return v;
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