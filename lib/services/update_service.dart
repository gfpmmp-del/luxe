import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../config/supabase_config.dart';
import 'net.dart';

/// Что известно о свежей версии.
class ReleaseInfo {
  final String version;
  final String? apkUrl;
  final String? zipUrl;
  final String notes;

  const ReleaseInfo(this.version, this.apkUrl, this.zipUrl, this.notes);

  String? get url => defaultTargetPlatform == TargetPlatform.windows
      ? zipUrl
      : apkUrl;

  bool get isIos => defaultTargetPlatform == TargetPlatform.iOS;
}

/// Проверка и установка обновлений.
///
/// Системы разные и возможности тоже разные:
/// - **Windows**: файлы можно заменить самому, приложение перезапустится
/// - **Android**: система всё равно спросит подтверждение, но мы сведём
///   установку к одному нажатию, вместо пяти вручную
/// - **iOS**: обновиться самостоятельно нельзя в принципе, Apple это
///   запрещает; показываем ссылку на TestFlight и не выдумываем
class UpdateService {
  static const MethodChannel _android = MethodChannel('luxe/update');

  /// Куда смотрим за новой версией. Два адреса: если сеть режет один,
  /// второй может быть доступен.
  static const List<String> _sources = [
    // Файл лежит в репозитории — на нём домен совсем другой, чем у
    // Supabase, и потому переживает блокировки.
    'https://raw.githubusercontent.com/gfpmmp-del/luxe/master/latest.json',
    '${SupabaseConfig.directUrl}/storage/v1/object/public/chat-media/latest.json',
  ];

  /// Текущая версия приложения.
  ///
  /// Номер подставляет сборка через --dart-define=APP_VERSION=...
  /// Без него показываем то, что записано в pubspec по умолчанию.
  static const String _fromDefine = String.fromEnvironment('APP_VERSION');

  static String get currentVersion => _fromDefine.isNotEmpty ? _fromDefine : '1.0.0';

  /// Прочитать описание новой версии.
  static Future<ReleaseInfo?> check() async {
    final client = Net.buildClient();
    for (final src in _sources) {
      try {
        final res = await client
            .get(Uri.parse(src))
            .timeout(const Duration(seconds: 10));
        if (res.statusCode != 200) continue;
        final data = _decode(res.body);
        if (data == null) continue;
        final info = ReleaseInfo(
          (data['version'] ?? '').toString(),
          _abs(data['apk_url'], data['url']),
          _abs(data['zip_url'], data['url']),
          (data['notes'] ?? '').toString(),
        );
        if (info.version.isEmpty) continue;
        if (_compare(info.version, currentVersion) > 0) return info;
        return null; // обновлений нет, и адрес рабочий — дальше не идём
      } catch (_) {
        // Этот адрес недоступен, пробуем следующий
      }
    }
    client.close();
    return null;
  }

  static Map<String, dynamic>? _decode(String body) {
    try {
      final m = jsonDecode(body);
      return m is Map<String, dynamic> ? m : null;
    } catch (_) {
      return null;
    }
  }

  /// Дописать основной адрес, если в файле относительный путь.
  static String? _abs(dynamic primary, dynamic fallback) {
    final v = (primary ?? fallback)?.toString();
    if (v == null || v.isEmpty) return null;
    if (v.startsWith('http')) return v;
    return '${SupabaseConfig.directUrl}/storage/v1/object/public/chat-media/$v';
  }

  /// Понятный текст ошибки для пользователя.
  static String humanError(Object e) => Net.humanError(e);

  /// Сравнить версии: 1 — новее, 0 — равна, -1 — старее.
  static int _compare(String a, String b) {
    final pa = a.split('+').first.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    final pb = b.split('+').first.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    for (var i = 0; i < 3; i++) {
      final x = i < pa.length ? pa[i] : 0;
      final y = i < pb.length ? pb[i] : 0;
      if (x != y) return x > y ? 1 : -1;
    }
    return 0;
  }

  /// Скачать файл и вернуть путь к нему. Показывает ход загрузки.
  static Future<String?> download(
    ReleaseInfo info, {
    void Function(double)? onProgress,
  }) async {
    final url = info.url;
    if (url == null) return null;
    final client = Net.buildClient();
    StreamSubscription<List<int>>? sub;
    try {
      final req = http.Request('GET', Uri.parse(url));
      final res = await client.send(req).timeout(const Duration(seconds: 30));
      if (res.statusCode != 200) return null;

      final total = res.contentLength ?? 0;
      final dir = await getTemporaryDirectory();
      final f = File('${dir.path}/updates/luxe_update'
          '${url.contains('.zip') ? '.zip' : '.apk'}');
      await f.parent.create(recursive: true);
      final sink = f.openWrite();
      var got = 0;
      sub = res.stream.listen(
        (chunk) {
          got += chunk.length;
          if (total > 0) onProgress?.call(got / total);
        },
        onError: (Object e) => sink.close(),
        onDone: () => sink.close(),
        cancelOnError: true,
      );
      await sink.flush();
      await sink.close();
      onProgress?.call(1);
      return f.path;
    } catch (e) {
      debugPrint('Обновление не скачалось: $e');
      return null;
    } finally {
      await sub?.cancel();
      client.close();
    }
  }

  /// Поставить скачанное обновление.
  ///
  /// Android — открыть системный установщик. Система спросит
  /// подтверждение, и это не обойти: так устроена защита Android.
  static Future<bool> installAndroid(String path) async {
    try {
      await _android.invokeMethod('install', {'path': path});
      return true;
    } on PlatformException catch (e) {
      debugPrint('Установщик не открылся: ${e.message}');
      return false;
    }
  }

  /// Открыть настройки приложения — туда, где разрешают ставить
  /// файлы из неизвестных источников.
  static Future<void> openAndroidSettings() async {
    try {
      await _android.invokeMethod('openAppSettings');
    } catch (_) {}
  }

  /// Обновление на Windows: файлы заняты запущенной программой,
  /// поэтому подмену делает маленький скрипт после выхода.
  static Future<void> installWindows(String zipPath, String targetDir) async {
    final temp = Directory.systemTemp.createTempSync('luxe_update');
    final cmd = File('${temp.path}/update.cmd');

    // Скрипт ждёт, пока процесс освободит файлы, раскладывает новую
    // версию поверх старой и запускает её.
    final script = '''
@echo off
setlocal
set "TARGET=$targetDir"
set "ZIP=${zipPath.replaceAll('/', '\\')}"
set "TEMP=${temp.path.replaceAll('/', '\\')}"
timeout /t 2 /nobreak >nul
:wait
timeout /t 1 /nobreak >nul
del "%TEMP%\\luxe_update" >nul 2>nul
if exist "%TEMP%\\luxe_update" goto wait
del "%TARGET%\\update_done.txt" >nul 2>nul
tar -xf "%ZIP%" -C "%TEMP%" >nul 2>nul
xcopy "%TEMP%\\*" "%TARGET%" /E /Y /Q >nul 2>nul
start "" "%TARGET%\\luxe.exe"
del "%ZIP%" >nul 2>nul
rd /s /q "%TEMP%" >nul 2>nul
''';
    await cmd.writeAsString(script);
    await Process.start('cmd', ['/c', 'start', '', '/min', cmd.path]);
  }
}
