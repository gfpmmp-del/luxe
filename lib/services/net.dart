import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

import '../config/supabase_config.dart';

/// Сеть: таймауты, проверка доступности и повторы.
///
/// Без этого приложение на закрытой или «сложной» сети просто висит:
/// запрос уходит и не возвращается, а пользователь видит белый экран.
class Net {
  /// Сколько ждём установления соединения.
  static const Duration connectTimeout = Duration(seconds: 8);

  /// Сколько ждём данных после подключения.
  static const Duration idleTimeout = Duration(seconds: 20);

  /// HTTP-клиент с вменяемыми таймаутами.
  ///
  /// Без них HttpClient на телефоне висит до системного таймаута —
  /// это две минуты немого белого экрана.
  static http.Client buildClient() {
    final inner = HttpClient()
      ..connectionTimeout = connectTimeout
      ..idleTimeout = idleTimeout
      // Одно соединение на хост. Dart держит пул живых сокетов и
      // переиспользует их; на мобильной сети с прокси переподключение
      // случается незаметно, и следующий запрос уходит в мёртвый сокет
      // и висит до таймаута. Одно соединение заставляет клиент
      // вовремя заметить, что сокет мёртв, и открыть новый.
      ..maxConnectionsPerHost = 1
      // Доверяем обычным сертификатам. Смысла ослаблять проверку нет:
      // нашим сертификатам это не поможет, а защиту сломает.
      ..badCertificateCallback = (cert, host, port) => false;
    return IOClient(inner);
  }

  /// Проверить, что сервер вообще отвечает.
  ///
  /// Спрашиваем health Supabase — он не требует авторизации и отвечает
  /// быстро, поэтому годится как «есть ли связь».
  ///
  /// Ключ кладём и в заголовок, и в адрес: при пробросе через Worker
  /// заголовок теоретически может потеряться, а Supabase принимает и
  /// query-параметр. Так проверка не врёт из-за одной потерянной строчки.
  static Future<bool> reachable() async {
    final client = buildClient();
    try {
      final res = await client
          .get(
            Uri.parse('${SupabaseConfig.url}/auth/v1/health'
                '?apikey=${SupabaseConfig.anonKey}'),
            headers: {'apikey': SupabaseConfig.anonKey},
          )
          .timeout(connectTimeout);
      // 4xx тоже считаем успехом: значит сервер на месте и ключ виден.
      return res.statusCode < 500;
    } catch (_) {
      return false;
    } finally {
      client.close();
    }
  }

  /// Сработало ли соединение по прокси.
  ///
  /// Проверяем не только вход, но и запрос к базе. Раньше проверялся
  /// только /auth/v1 — он отвечал, а /rest/v1 висел, и приложение
  /// считало сеть исправной.
  static Future<bool> probeRest() => probeBase(SupabaseConfig.url);

  /// Проверить конкретный адрес: и вход, и запрос к базе.
  ///
  /// Нужен оба: /auth/v1 отвечает быстро даже там, где /rest/v1
  /// зависает, и по нему одному судить о сети нельзя.
  static Future<bool> probeBase(String base) async {
    final client = buildClient();
    try {
      final auth = await client
          .get(
            Uri.parse('$base/auth/v1/health?apikey=${SupabaseConfig.anonKey}'),
            headers: {'apikey': SupabaseConfig.anonKey},
          )
          .timeout(connectTimeout);
      if (auth.statusCode >= 500) return false;

      final rest = await client
          .get(
            Uri.parse('$base/rest/v1/chat_members'
                '?select=chat_id&limit=1'
                '&apikey=${SupabaseConfig.anonKey}'),
            headers: {'apikey': SupabaseConfig.anonKey},
          )
          .timeout(connectTimeout);
      // Пустой массив — это успех: база ответила, просто строк нет.
      return rest.statusCode < 500;
    } catch (_) {
      return false;
    } finally {
      client.close();
    }
  }

  /// Выбрать адрес, который реально работает в этой сети.
  ///
  /// Сначала пробуем прямой адрес Supabase: он надёжнее, быстрее и
  /// не гонит трафик через посредника. Cloudflare оставляем запасным
  /// путём для сетей, которые режут сам Supabase — там прямой адрес
  /// не ответит, и воркер выручит.
  static Future<String?> pickUrl() async {
    if (!SupabaseConfig.viaProxy) return SupabaseConfig.url;

    if (await probeBase(SupabaseConfig.directUrl)) {
      debugPrint('Работает напрямую: ${SupabaseConfig.directUrl}');
      return SupabaseConfig.directUrl;
    }
    debugPrint('Прямой адрес не отвечает, пробуем прокси');
    if (await probeBase(SupabaseConfig.workerUrl)) {
      debugPrint('Работает через прокси: ${SupabaseConfig.workerUrl}');
      return SupabaseConfig.workerUrl;
    }
    return null;
  }

  /// Повторить операцию с нарастающей паузой.
  ///
  /// [attempts] — сколько раз пробуем всего, вместе с первым.
  static Future<T> retry<T>(
    Future<T> Function() action, {
    int attempts = 3,
    Duration baseDelay = const Duration(milliseconds: 400),
  }) async {
    var last = '';
    for (var i = 0; i < attempts; i++) {
      try {
        return await action();
      } catch (e) {
        last = e.toString();
        if (i == attempts - 1) rethrow;
        debugPrint('Попытка ${i + 1} не удалась, повторяем: $e');
        await Future.delayed(baseDelay * (1 << i));
      }
    }
    throw Exception(last);
  }

  /// Понятный текст вместо технического сообщения PostgREST.
  ///
  /// Пользователю не нужны слова «SocketException» — ему нужно знать,
  /// что делать.
  static String humanError(Object e) {
    final s = e.toString().toLowerCase();
    if (s.contains('socketexception') ||
        s.contains('failed host lookup') ||
        s.contains('no address associated') ||
        s.contains('connection refused') ||
        s.contains('network is unreachable')) {
      return 'Нет связи с сервером. Проверьте интернет и попробуйте снова.';
    }
    if (s.contains('timeout') || s.contains('timed out')) {
      return 'Сервер не отвечает. Возможно, сеть его блокирует — '
          'попробуйте другую сеть или мобильный интернет.';
    }
    if (s.contains('failed to fetch') ||
        s.contains('handshake') ||
        s.contains('certificate')) {
      return 'Защищённое соединение не устанавливается. '
          'Сеть, похоже, фильтрует трафик.';
    }
    return e.toString();
  }
}
