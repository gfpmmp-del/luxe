import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

import '../config/supabase_config.dart';
import '../main.dart';
import '../services/auth_service.dart';
import '../services/media_service.dart';
import '../services/update_service.dart';
import '../theme/luxe_theme.dart';

/// Проверка связи: показывает, куда приложение ходит и что отвечает
/// каждый адрес.
///
/// Экран появился после долгой истории с «файлы не грузятся»: на глаз
/// одинаково выглядят три разные поломки — закрытый прямой адрес,
/// сломанный прокси и битые ссылки в базе. Здесь видно, какая именно,
/// без чтения логов с телефона.
class DiagnosticsScreen extends StatefulWidget {
  const DiagnosticsScreen({super.key});

  @override
  State<DiagnosticsScreen> createState() => _DiagnosticsScreenState();
}

class _Probe {
  final String title;
  final String? detail;
  final bool? ok; // null — идёт проверка
  _Probe(this.title, {this.detail, this.ok});
  _Probe copy({String? detail, bool? ok}) =>
      _Probe(title, detail: detail ?? this.detail, ok: ok ?? this.ok);
}

class _DiagnosticsScreenState extends State<DiagnosticsScreen> {
  final List<_Probe> _results = [
    _Probe('Маршрут приложения'),
    _Probe('Прямой адрес Supabase'),
    _Probe('Адрес через прокси'),
    _Probe('Файл напрямую'),
    _Probe('Файл через прокси'),
  ];

  String _fileUrl = '';

  @override
  void initState() {
    super.initState();
    _run();
  }

  void _set(int i, {String? detail, bool? ok}) {
    if (!mounted) return;
    setState(() => _results[i] = _results[i].copy(detail: detail, ok: ok));
  }

  Future<void> _run() async {
    for (var i = 0; i < _results.length; i++) {
      setState(() => _results[i] = _Probe(_results[i].title));
    }

    _set(0,
        ok: true,
        detail: '${SupabaseConfig.routeName}\n${SupabaseConfig.url}\n'
            'Файлы: ${MediaService.proxyBuffered ? 'одним запросом' : 'кусками (прокси старый)'}');

    await Future.wait([
      _restCheck(1, SupabaseConfig.directUrl),
      _restCheck(2, SupabaseConfig.workerUrl),
    ]);

    final file = await _pickTestFile();
    _fileUrl = file;
    if (file.isEmpty) {
      _set(3, ok: false, detail: 'Не нашёл ни одного файла для проверки');
      _set(4, ok: false, detail: 'Не нашёл ни одного файла для проверки');
      return;
    }

    final viaProxy = file.contains(SupabaseConfig.workerUrl)
        ? file
        : file.replaceFirst(SupabaseConfig.directUrl, SupabaseConfig.workerUrl);
    final direct = file.contains(SupabaseConfig.workerUrl)
        ? file.replaceFirst(SupabaseConfig.workerUrl, SupabaseConfig.directUrl)
        : file;

    await Future.wait([
      _fileCheck(3, direct),
      _fileCheck(4, viaProxy),
    ]);
  }

  /// Взять реальный файл из хранилища: сначала свою аватарку, потом
  /// любую из папки avatars. Выдуманный адрес ничего не докажет.
  Future<String> _pickTestFile() async {
    try {
      final me = await supabase
          .from('profiles')
          .select('avatar_url')
          .eq('id', AuthService.myId)
          .maybeSingle();
      final av = me?['avatar_url'] as String?;
      if (av != null && av.isNotEmpty) return av;
    } catch (_) {}

    try {
      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 6);
      final req = await client.postUrl(
          Uri.parse('${SupabaseConfig.directUrl}/storage/v1/object/list/chat-media'));
      req.headers.set('apikey', SupabaseConfig.anonKey);
      req.headers.set('Authorization', 'Bearer ${SupabaseConfig.anonKey}');
      req.headers.contentType = ContentType.json;
      req.write(jsonEncode({'prefix': 'avatars', 'limit': 1, 'offset': 0}));
      final res = await req.close().timeout(const Duration(seconds: 8));
      final body = await res.transform(utf8.decoder).join();
      final list = jsonDecode(body);
      if (list is List && list.isNotEmpty) {
        final name = (list.first as Map)['name'];
        if (name != null) {
          return '${SupabaseConfig.directUrl}/storage/v1/object/public/'
              'chat-media/avatars/$name';
        }
      }
    } catch (_) {}
    return '';
  }

  Future<void> _restCheck(int index, String base) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    final sw = Stopwatch()..start();
    try {
      final req = await client.getUrl(
          Uri.parse('$base/rest/v1/chat_members?select=chat_id&limit=1'));
      req.headers.set('apikey', SupabaseConfig.anonKey);
      req.headers.set('Authorization', 'Bearer ${SupabaseConfig.anonKey}');
      final res = await req.close().timeout(const Duration(seconds: 10));
      await res.drain<void>();
      _set(index,
          ok: res.statusCode < 500,
          detail: 'HTTP ${res.statusCode} • ${sw.elapsedMilliseconds} мс');
    } catch (e) {
      _set(index, ok: false, detail: 'Не отвечает • ${_short(e)}');
    } finally {
      client.close();
    }
  }

  Future<void> _fileCheck(int index, String url) async {
    final sw = Stopwatch()..start();
    try {
      // Проверяем ровно тот путь, которым приложение качает файлы:
      // напрямую одним запросом или кусками через старый прокси.
      final bytes = await MediaService.fetchBytes(url);
      _set(index,
          ok: bytes.isNotEmpty,
          detail: '${bytes.length} байт • ${sw.elapsedMilliseconds} мс'
              '${MediaService.needsChunks(url) ? '\nкусками: прокси старый' : ''}');
    } catch (e) {
      _set(index,
          ok: false,
          detail: 'Не вышло через ${sw.elapsedMilliseconds} мс • ${_short(e)}');
    }
  }

  String _short(Object e) {
    final s = e.toString();
    return s.length > 90 ? '${s.substring(0, 90)}…' : s;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Проверка связи'),
        actions: [
          IconButton(
            tooltip: 'Повторить',
            onPressed: _run,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Проверка показывает, что видит именно это устройство '
            'в этой сети. Отправьте скриншот, если что-то не работает.',
            style: TextStyle(color: scheme.onSurface.withValues(alpha: 0.6)),
          ),
          const SizedBox(height: 16),
          Card(
            child: Column(
              children: [
                for (var i = 0; i < _results.length; i++) ...[
                  if (i > 0) const Divider(height: 1),
                  _row(_results[i]),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),
          SelectableText(
            'Версия: ${UpdateService.currentVersion}\n'
            '${_fileUrl.isEmpty ? '' : 'Проверочный файл:\n$_fileUrl'}',
            style: TextStyle(
                fontSize: 11,
                color: scheme.onSurface.withValues(alpha: 0.5)),
          ),
        ],
      ),
    );
  }

  Widget _row(_Probe p) {
    final scheme = Theme.of(context).colorScheme;
    final Widget icon;
    if (p.ok == null) {
      icon = const SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2));
    } else if (p.ok == true) {
      icon = const Icon(Icons.check_circle_rounded,
          color: LuxeColors.online, size: 22);
    } else {
      icon = const Icon(Icons.error_rounded, color: LuxeColors.danger, size: 22);
    }
    return ListTile(
      leading: icon,
      title: Text(p.title),
      subtitle: p.detail == null
          ? null
          : SelectableText(
              p.detail!,
              style: TextStyle(
                  fontSize: 12,
                  color: scheme.onSurface.withValues(alpha: 0.65)),
            ),
      isThreeLine: (p.detail ?? '').contains('\n'),
    );
  }
}
