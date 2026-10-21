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

/// Ошибка обновления с текстом, который можно показать человеку.
///
/// Отдельный тип, потому что раньше любая ошибка молча уходила в
/// лог: человек видел, что ничего не происходит, и не понимал —
/// сеть виновата или обновление сломано.
class UpdateFailed implements Exception {
  final String message;
  const UpdateFailed(this.message);

  @override
  String toString() => message;
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
  /// Запасное значение обязано совпадать с `version:` в pubspec.yaml:
  /// на iOS Codemagic собирает без dart-define, и там считается оно.
  static const String _fromDefine = String.fromEnvironment('APP_VERSION');

  static const String _fallbackVersion = '1.1.7';

  static String get currentVersion =>
      _fromDefine.isNotEmpty ? _fromDefine : _fallbackVersion;

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
  ///
  /// Бросает [UpdateFailed] с понятным текстом. Раньше здесь был
  /// отдельный `listen` на поток ответа, а `sink.close()` вызывался
  /// сразу же — не дожидаясь конца файла. В результате на установщик
  /// уходил пустой APK: приложение показывало «Скачиваем…», через
  /// секунду возвращалось назад, и ничего не происходило. Ошибка при
  /// этом молча проглатывалась.
  static Future<String> download(
    ReleaseInfo info, {
    void Function(double)? onProgress,
  }) async {
    final url = info.url;
    if (url == null) throw const UpdateFailed('В файле обновления нет ссылки');

    final client = Net.buildClient();
    IOSink? sink;
    File? target;
    try {
      final res = await client
          .send(http.Request('GET', Uri.parse(url)))
          .timeout(const Duration(seconds: 30));
      if (res.statusCode != 200) {
        throw UpdateFailed('Сервер ответил кодом ${res.statusCode}');
      }

      final total = res.contentLength ?? 0;
      final dir = await getTemporaryDirectory();
      final f = File(
          '${dir.path}/updates/luxe_update${url.contains('.zip') ? '.zip' : '.apk'}');
      target = f;
      // Обрывок прошлой попытки дописался бы в новый файл, и Android
      // потом ругался бы на битый пакет.
      if (await f.exists()) await f.delete();
      await f.parent.create(recursive: true);

      sink = f.openWrite();
      var got = 0;
      // Ключевое отличие от прежней версии: ждём каждый кусок
      // ответа, а не подписываемся на него сбоку.
      await for (final chunk in res.stream) {
        sink.add(chunk);
        got += chunk.length;
        if (total > 0) onProgress?.call((got / total).clamp(0.0, 1.0));
      }
      await sink.flush();
      await sink.close();
      sink = null;

      // Оборванный файл Android поставит с непонятной ошибкой, а
      // человек решит, что обновление сломанное. Лучше сказать прямо.
      if (total > 0 && got != total) {
        throw UpdateFailed(
            'Файл докачался не полностью: $got из $total байт. Похоже, связь оборвалась.');
      }
      final size = await f.length();
      if (size == 0) throw const UpdateFailed('Скачался пустой файл');

      onProgress?.call(1);
      return f.path;
    } on UpdateFailed {
      rethrow;
    } catch (e) {
      debugPrint('Обновление не скачалось: $e');
      throw UpdateFailed(humanError(e));
    } finally {
      // Незакрытый sink держит файл: и он останется в кэше, и
      // следующая попытка упрётся в него.
      try {
        await sink?.close();
      } catch (_) {}
      client.close();
      // Недоскачанный файл убираем, чтобы он не занимал место.
      if (target != null && sink != null) {
        try {
          await target.delete();
        } catch (_) {}
      }
    }
  }

  /// Поставить скачанное обновление.
  ///
  /// Android — открыть системный установщик. Система спросит
  /// подтверждение, и это не обойти: так устроена защита Android.
  ///
  /// Бросает [UpdateFailed] с текстом от Android, если установщик
  /// не открылся. Раньше здесь стоял общий «Не удалось открыть
  /// установщик» — по нему нельзя понять, мешает ли разрешение
  /// на установку из неизвестных источников или битый файл.
  static Future<void> installAndroid(String path) async {
    try {
      await _android.invokeMethod('install', {'path': path});
    } on PlatformException catch (e) {
      debugPrint('Установщик не открылся: ${e.code} / ${e.message}');
      throw UpdateFailed(switch (e.code) {
        'no_file' => 'Файл обновления не найден на телефоне',
        'not_allowed' => 'Разрешите приложению ставить файлы из неизвестных '
            'источников — иначе телефон не поставит обновление',
        'no_installer' => 'На телефоне нет приложения для установки',
        'install_failed' =>
          'Система не открыла установщик. ${e.message ?? ''}'.trim(),
        _ => 'Не удалось начать установку: ${e.message ?? e.code}',
      });
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

    // Скрипт ждёт, пока процесс luxe.exe действительно завершится,
    // раскладывает новую версию поверх старой и запускает её.
    //
    // Раньше ожидание было поддельным: в цикле удалялся файл
    // «%TEMP%\luxe_update», которого там никогда не было, поэтому
    // подмена стартовала сразу, пока приложение ещё работало.
    // xcopy упирался в занятый luxe.exe и обновление не проходило.
    final script = '''
@echo off
setlocal
set "TARGET=$targetDir"
set "ZIP=${zipPath.replaceAll('/', '\\')}"
set "TEMP=${temp.path.replaceAll('/', '\\')}"

:wait
tasklist /FI "IMAGENAME eq luxe.exe" 2>nul | find /I "luxe.exe" >nul
if not errorlevel 1 (
  timeout /t 1 /nobreak >nul
  goto wait
)

tar -xf "%ZIP%" -C "%TEMP%" >nul 2>nul
xcopy "%TEMP%\\*" "%TARGET%" /E /Y /Q >nul 2>nul
del "%ZIP%" >nul 2>nul
start "" "%TARGET%\\luxe.exe"
rd /s /q "%TEMP%" >nul 2>nul
''';
    await cmd.writeAsString(script);
    await Process.start('cmd', ['/c', 'start', '', '/min', cmd.path]);
  }
}
