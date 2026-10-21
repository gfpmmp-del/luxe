import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../main.dart';
import '../config/supabase_config.dart';
import 'net.dart';

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

  /// Понятная причина, если сеть зависла.
  ///
  /// Раньше загрузка файла не имела таймаута вообще. На сети, где
  /// хранилище недоступно, соединение не рвётся, а просто висит —
  /// и человек часами смотрел на «Загрузка…», не понимая, что
  /// сломано. Теперь ждём недолго и говорим, что делать.
  static String _hungError(String what) =>
      '$what не отвечает. Похоже, сеть не даёт доступ к хранилищу. '
      'Попробуйте ещё раз или откройте при работающей сети.';

  static Future<String> _uploadFile(
      String path, File file, String contentType) async {
    await supabase.storage
        .from('chat-media')
        .upload(
          path,
          file,
          fileOptions: FileOptions(contentType: contentType, upsert: true),
        )
        // Крупные файлы на медленной сети шлют дольше минуты, поэтому
        // потолок generous; но он конечен.
        .timeout(const Duration(seconds: 120));
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

  /// Все возможные адреса файла, в порядке предпочтения.
  ///
  /// Первым идёт тот, через который приложение **сейчас** ходит на
  /// сервер. Раньше ссылка всегда переписывалась на прямой адрес
  /// Supabase — и у всех, кто сидел на сети с заблокированным
  /// Supabase, файлы и аватарки не грузились, хотя чаты работали:
  /// чаты шли через воркер, а картинки принудительно — напрямую,
  /// то есть в заблокированный адрес.
  static List<String> candidates(String? url) {
    if (url == null || url.isEmpty) return const [];
    final isWorker = url.contains('workers.dev');
    final isDirect = url.contains(SupabaseConfig.directUrl);
    if (!isWorker && !isDirect) return [url];

    final direct = isWorker
        ? url.replaceAll(SupabaseConfig.workerUrl, SupabaseConfig.directUrl)
        : url;
    final viaWorker = isDirect
        ? url.replaceAll(SupabaseConfig.directUrl, SupabaseConfig.workerUrl)
        : url;

    final preferWorker = SupabaseConfig.url == SupabaseConfig.workerUrl;
    final list = preferWorker ? [viaWorker, direct] : [direct, viaWorker];
    // toSet сохраняет порядок — дубликаты убираются, приоритет остаётся.
    return list.toSet().toList();
  }

  /// Первый (самый вероятный) адрес файла.
  static String? fixUrl(String? url) {
    final list = candidates(url);
    return list.isEmpty ? url : list.first;
  }

  // ── Обход старого прокси ────────────────────────────────────────────
  //
  // У воркера, который сейчас развёрнут на Cloudflare, есть беда: файл
  // больше ~22 КБ он отдаёт не целиком. Заголовки приходят правильные
  // (Content-Length 193933), а тело обрывается на 22 168 байтах и
  // клиент ждёт остаток до таймаута. Именно из-за этого у людей с
  // заблокированным Supabase не открывались ни аватарки, ни фото, ни
  // голосовые: чаты шли через воркер, а файлы через него не доезжали.
  //
  // Новый worker.js собирает файл в памяти и отдаёт целиком, но пока
  // его не перезалили на Cloudflare — работаем в обход: просим файл
  // кусками по 16 КБ. Каждый такой кусок доезжает полностью, а вместе
  // они складываются в целый файл. Как только воркер обновят, флаг
  // [proxyBuffered] станет true и приложение вернётся к обычной
  // загрузке одним запросом.

  /// Обновлён ли воркер и умеет ли он отдавать файлы целиком.
  static bool proxyBuffered = false;

  /// Размер куска. 22 КБ — предел, после которого старый воркер рвёт
  /// соединение; берём с запасом.
  static const int chunkSize = 16 * 1024;

  /// Идёт ли приложение через воркер.
  static bool get viaProxy => SupabaseConfig.viaProxy;

  /// Нужно ли тянуть этот адрес кусками.
  static bool needsChunks(String? url) {
    if (url == null || url.isEmpty) return false;
    if (proxyBuffered) return false;
    return url.contains('workers.dev');
  }

  /// Спросить у воркера, обновлён ли он.
  ///
  /// Новый воркер отвечает на /health строкой «buffered». Старый такого
  /// адреса не знает и отдаёт 404 от Supabase — значит, куски.
  static Future<void> probeProxy() async {
    if (!SupabaseConfig.viaProxy) {
      proxyBuffered = false;
      return;
    }
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 4)
      ..idleTimeout = const Duration(seconds: 4);
    try {
      final req = await client
          .getUrl(Uri.parse('${SupabaseConfig.workerUrl}/health'))
          .timeout(const Duration(seconds: 4));
      final res = await req.close().timeout(const Duration(seconds: 4));
      final body =
          await res.transform(const Utf8Decoder()).join().timeout(const Duration(seconds: 4));
      proxyBuffered = res.statusCode == 200 && body.contains('buffered');
      debugPrint('Прокси: ${proxyBuffered ? 'обновлён' : 'старый, качаем кусками'}');
    } catch (e) {
      proxyBuffered = false;
      debugPrint('Прокси не ответил на проверку: $e');
    } finally {
      client.close();
    }
  }

  static final Map<String, Uint8List> _images = {};
  static final Map<String, Future<Uint8List>> _loading = {};
  static int _imagesBytes = 0;
  /// Больше 32 МБ картинок в памяти не держим: на телефоне это уже
  /// заметно, а листать чат с сотней фотографий никто не станет.
  static const int _imagesLimit = 32 * 1024 * 1024;

  /// Байты картинки с кэшем в памяти: один и тот же аватар не качается
  /// заново при каждой перерисовке списка.
  static Future<Uint8List> imageBytes(String url) {
    final hit = _images[url];
    if (hit != null) return Future.value(hit);
    final running = _loading[url];
    if (running != null) return running;

    final future = fetchBytes(url).then((bytes) {
      _imagesBytes += bytes.length;
      _images[url] = bytes;
      while (_imagesBytes > _imagesLimit && _images.length > 1) {
        final key = _images.keys.first;
        final old = _images.remove(key);
        _imagesBytes -= old?.length ?? 0;
      }
      return bytes;
    }).whenComplete(() => _loading.remove(url));
    _loading[url] = future;
    return future;
  }

  /// Прочитать файл целиком. Сам выбирает способ: обычный запрос или
  /// куски, если прокси старый.
  static Future<Uint8List> fetchBytes(String url, {bool? chunked}) async {
    final targets = candidates(url);
    Object? last;
    for (final target in (targets.isEmpty ? [url] : targets)) {
      final byChunks = chunked ?? needsChunks(target);
      try {
        return byChunks
            ? await _rangedBytes(target)
            : await _plainBytes(target);
      } catch (e) {
        last = e;
        debugPrint('Не удалось прочитать $target: $e');
      }
    }
    throw Exception(last?.toString() ?? 'Не удалось загрузить файл');
  }

  static Future<Uint8List> _plainBytes(String url) async {
    final client = HttpClient()
      ..connectionTimeout = Net.connectTimeout
      ..idleTimeout = Net.idleTimeout;
    try {
      final req = await client.getUrl(Uri.parse(url)).timeout(Net.connectTimeout);
      final res = await req.close().timeout(Net.connectTimeout);
      if (res.statusCode != 200) {
        throw Exception('Сервер ответил кодом ${res.statusCode}');
      }
      final bytes = await _readAll(res).timeout(const Duration(seconds: 60));
      final expected = res.contentLength;
      if (expected > 0 && bytes.length < expected) {
        throw Exception('Пришло ${bytes.length} из $expected байт');
      }
      return bytes;
    } finally {
      client.close();
    }
  }

  static Future<Uint8List> _rangedBytes(String url) async {
    final first = await _rangeOnce(url, 0, chunkSize - 1);
    final total = first.total;
    if (total <= 0) return first.bytes;
    // Очень крупные файлы кусками тянуть бессмысленно: тысячи запросов.
    if (total > 80 * 1024 * 1024) {
      throw Exception('Файл слишком большой для загрузки кусками');
    }
    if (first.bytes.length >= total) return first.bytes;

    final out = Uint8List(total);
    out.setRange(0, first.bytes.length, first.bytes);

    final starts = <int>[];
    for (var s = chunkSize; s < total; s += chunkSize) {
      starts.add(s);
    }
    var next = 0;
    Future<void> worker() async {
      while (true) {
        final i = next++;
        if (i >= starts.length) return;
        final from = starts[i];
        final to = min(from + chunkSize, total) - 1;
        final part = await _rangeOnce(url, from, to);
        final want = to - from + 1;
        if (part.bytes.length != want) {
          throw Exception('Кусок пришёл не целиком');
        }
        out.setRange(from, from + part.bytes.length, part.bytes);
      }
    }

    // Четыре потока: и быстро, и Cloudflare не заваливаем.
    await Future.wait(List.generate(4, (_) => worker()));
    return out;
  }

  static Future<({Uint8List bytes, int total})> _rangeOnce(
      String url, int from, int to) async {
    // Клиент на каждый кусок — не прихоть. Cloudflare после ответа
    // оставляет соединение в таком состоянии, что следующий запрос по
    // нему уходит в никуда и висит до таймаута. С новым соединением
    // каждый кусок приходит за сотые доли секунды.
    final client = HttpClient()
      ..connectionTimeout = Net.connectTimeout
      ..idleTimeout = const Duration(seconds: 10);
    try {
      final req =
          await client.getUrl(Uri.parse(url)).timeout(Net.connectTimeout);
      req.headers.set('Range', 'bytes=$from-$to');
      // Сжатие на этом пути только мешает: заголовок длины относится
      // к исходному файлу, а байты приходят упакованными.
      req.headers.set('Accept-Encoding', 'identity');
      final res = await req.close().timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) {
        // Прокси не понял Range и пытается отдать всё целиком — на нём
        // это всё равно оборвётся.
        throw Exception('Прокси не поддерживает Range');
      }
      if (res.statusCode != 206) {
        throw Exception('Сервер ответил кодом ${res.statusCode}');
      }
      final bytes = await _readAll(res).timeout(const Duration(seconds: 15));

      var total = res.contentLength;
      final range = res.headers.value('content-range');
      if (range != null) {
        final slash = range.lastIndexOf('/');
        if (slash > 0) {
          total = int.tryParse(range.substring(slash + 1)) ?? total;
        }
      }
      return (bytes: bytes, total: total);
    } finally {
      client.close(force: true);
    }
  }

  static Future<Uint8List> _readAll(HttpClientResponse res) async {
    final builder = BytesBuilder(copy: false);
    await for (final chunk in res) {
      builder.add(chunk);
    }
    return builder.takeBytes();
  }

  /// Скачать файл во временную папку и вернуть путь.
  ///
  /// Нужно плеерам: они не умеют тянуть кусками, а через старый воркер
  /// целый файл не приходит.
  static final Map<String, Future<String>> _copying = {};

  static Future<String> localCopy(String url) {
    final running = _copying[url];
    if (running != null) return running;
    final job = _localCopyOne(url).whenComplete(() => _copying.remove(url));
    _copying[url] = job;
    return job;
  }

  static Future<String> _localCopyOne(String url) async {
    final dir = await getTemporaryDirectory();
    final name = 'luxe-${url.hashCode}-${url.split('/').last}';
    final file = File('${dir.path}/$name');
    if (file.existsSync() && file.lengthSync() > 0) return file.path;
    final bytes = await fetchBytes(url);
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
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
    final targets = candidates(url);
    for (final target in (targets.isEmpty ? [url] : targets)) {
      final client = HttpClient()
        ..connectionTimeout = Net.connectTimeout
        ..idleTimeout = Net.idleTimeout;
      try {
        final req = await client.getUrl(Uri.parse(target));
        final res = await req.close().timeout(Net.connectTimeout);
        final len = res.contentLength;
        res.drain<void>();
        return len;
      } catch (e) {
        debugPrint('Не удалось получить размер файла: $e');
      } finally {
        client.close();
      }
    }
    return 0;
  }

  /// Скачать файл на устройство. Возвращает путь к сохранённому файлу.
  ///
  /// Пробуем по очереди все адреса: сеть может резать один и пускать
  /// другой. Раньше брался ровно один адрес, и при отказе человек
  /// видел только «не скачалось».
  static Future<String> download(String url, String fileName) async {
    final targets = candidates(url);
    Object? last;
    for (final target in (targets.isEmpty ? [url] : targets)) {
      try {
        return await _downloadOne(target, fileName);
      } catch (e) {
        last = e;
        debugPrint('Скачать не вышло с $target: $e');
      }
    }
    throw Exception(last?.toString() ?? 'Не удалось скачать файл');
  }

  static Future<String> _downloadOne(String url, String fileName) async {
    final target = await _downloadTarget(fileName);

    // Старый прокси присылает файл обрезанным — тянем кусками.
    if (needsChunks(url)) {
      final bytes = await _rangedBytes(url);
      await target.writeAsBytes(bytes, flush: true);
      return target.path;
    }

    final client = HttpClient()
      ..connectionTimeout = Net.connectTimeout
      ..idleTimeout = Net.idleTimeout;
    try {
      final req = await client
          .getUrl(Uri.parse(url))
          .timeout(Net.connectTimeout);
      final res = await req.close().timeout(Net.connectTimeout);
      if (res.statusCode != 200) {
        throw Exception('Сервер ответил кодом ${res.statusCode}');
      }

      final sink = target.openWrite();
      // Файл может качаться долго, поэтому потолок на поток данных
      // общий, а не на соединение.
      await res.pipe(sink).timeout(const Duration(minutes: 5));
      await sink.flush();
      await sink.close();
      return target.path;
    } on TimeoutException {
      throw Exception(_hungError('Файл не скачивается'));
    } finally {
      client.close();
    }
  }

  static Future<File> _downloadTarget(String fileName) async {
    // Android — публичная папка «Загрузки», остальные — «Загрузки» пользователя
    final dir = Platform.isAndroid
        ? await getExternalStorageDirectory()
        : await getDownloadsDirectory();
    final base = dir ?? await getApplicationDocumentsDirectory();

    // Имя файла без служебного префикса загрузки
    var name = fileName;
    final i = name.lastIndexOf('-');
    if (i > 0 && i < name.length - 1) {
      final tail = name.substring(i + 1);
      if (RegExp(r'^\d+\.').hasMatch(tail)) name = tail;
    }
    return File('${base.path}/$name');
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