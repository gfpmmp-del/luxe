import 'dart:io';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/update_service.dart';
import '../theme/luxe_theme.dart';

/// Экран обновлений: показывает текущую версию и предлагает обновиться.
class UpdateScreen extends StatefulWidget {
  const UpdateScreen({super.key});

  @override
  State<UpdateScreen> createState() => _UpdateScreenState();
}

class _UpdateScreenState extends State<UpdateScreen> {
  bool _checking = false;
  bool _downloading = false;
  double _progress = 0;
  String? _foundVersion;
  String _notes = '';
  String? _status;

  /// Что скачивали последний раз — нужно для запасной ссылки
  /// «Скачать браузером», если внутри приложения не вышло.
  ReleaseInfo? _lastInfo;

  /// Что пошло не так при попытке обновления.
  String? _error;

  @override
  void initState() {
    super.initState();
    _check(silent: true);
  }

  /// Проверка обновлений.
  ///
  /// [silent] — при запуске приложения: не мешаем пользователю окном,
  /// если обновлений нет. Спросим, только когда он сам нажал кнопку.
  Future<void> _check({bool silent = false}) async {
    if (_checking) return;
    setState(() {
      _checking = true;
      _status = null;
      _error = null;
    });
    try {
      final info = await UpdateService.check();
      if (!mounted) return;
      setState(() {
        _checking = false;
        if (info == null) {
          _status = 'Установлена последняя версия';
          _foundVersion = null;
        } else {
          _foundVersion = info.version;
          _notes = info.notes;
        }
      });
      if (info != null && silent) {
        _askUpdate(info);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _checking = false;
        _status = 'Не удалось проверить: ${UpdateService.humanError(e)}';
      });
    }
  }

  /// Диалог с предложением обновиться.
  Future<void> _askUpdate(ReleaseInfo info) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Доступно обновление ${info.version}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (info.notes.isNotEmpty) Text(info.notes),
            if (info.isIos) ...[
              const SizedBox(height: 12),
              const Text(
                'Установить новое приложение на iPhone можно только через '
                'TestFlight или App Store — система не разрешает обновлять '
                'приложение самостоятельно.',
                style: TextStyle(fontSize: 13),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Позже')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(info.isIos ? 'Открыть TestFlight' : 'Обновить'),
          ),
        ],
      ),
    );
    if (yes == true) _install(info);
  }

  /// Скачать и поставить.
  Future<void> _install(ReleaseInfo info) async {
    _lastInfo = info;
    if (info.isIos) {
      // Система не даёт приложению поставить себя. Открываем
      // TestFlight, если он есть, иначе честно говорим, что делать.
      final opened = await _openTestFlight();
      if (!opened && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Открой TestFlight вручную и установи обновление'),
        ));
      }
      return;
    }

    setState(() {
      _downloading = true;
      _progress = 0;
      _error = null;
    });
    try {
      final path = await UpdateService.download(
        info,
        onProgress: (v) {
          if (mounted) setState(() => _progress = v);
        },
      );
      if (!mounted) return;
      setState(() => _downloading = false);

      if (Platform.isAndroid) {
        try {
          await UpdateService.installAndroid(path);
        } on UpdateFailed catch (e) {
          if (mounted) _showError(e.message);
        }
        return;
      }

      // Windows: подменяем файлы скриптом после выхода из программы
      final dir = File(Platform.resolvedExecutable).parent.path;
      await UpdateService.installWindows(path, dir);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Обновление установится и приложение перезапустится'),
        ));
        await Future.delayed(const Duration(seconds: 2));
        exit(0);
      }
    } on UpdateFailed catch (e) {
      if (!mounted) return;
      setState(() => _downloading = false);
      _showError(e.message);
    } catch (e) {
      if (!mounted) return;
      setState(() => _downloading = false);
      _showError('Ошибка обновления: $e');
    }
  }

  /// Показать, что пошло не так.
  ///
  /// Раньше здесь просто возвращались к экрану без единого слова:
  /// человек нажимал «Скачать и установить», видел мелькнувшую
  /// полоску и ничего больше. Непонятно — сеть, телефон или обновление.
  void _showError(String text) {
    setState(() {
      _error = text;
      _foundVersion = null;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text),
        duration: const Duration(seconds: 6),
        action: SnackBarAction(
          label: 'Скачать браузером',
          onPressed: _openInBrowser,
        ),
      ),
    );
  }

  /// Запасной путь: открыть файл в браузере.
  ///
  /// Если внутри приложения почему-то не скачивается, человек не
  /// должен остаться без обновления — ссылка ведёт на тот же файл.
  Future<void> _openInBrowser() async {
    final url = _lastInfo?.url;
    if (url == null) return;
    try {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Не удалось открыть ссылку')),
        );
      }
    }
  }

  Future<bool> _openTestFlight() async {
    const urls = [
      'https://testflight.apple.com/join/luxe',
      'itms-apps://testflight.apple.com',
    ];
    for (final u in urls) {
      try {
        final uri = Uri.parse(u);
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
          return true;
        }
      } catch (_) {}
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      appBar: AppBar(title: const Text('Обновления')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: ListTile(
              leading: const Icon(Icons.info_outline, color: LuxeColors.tgBlue),
              title: const Text('Установленная версия'),
              subtitle: Text(UpdateService.currentVersion),
            ),
          ),
          const SizedBox(height: 12),
          if (_downloading) ...[
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Скачиваем обновление...'),
                    const SizedBox(height: 10),
                    LinearProgressIndicator(value: _progress),
                  ],
                ),
              ),
            ),
          ] else if (_foundVersion != null) ...[
            Card(
              color: LuxeColors.tgBlue.withValues(alpha: 0.12),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Доступна версия $_foundVersion',
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                    if (_notes.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(_notes),
                    ],
                    const SizedBox(height: 14),
                    FilledButton.icon(
                      onPressed: () async {
                        final info = await UpdateService.check();
                        if (info != null) _install(info);
                      },
                      icon: const Icon(Icons.download_rounded),
                      label: const Text('Скачать и установить'),
                    ),
                  ],
                ),
              ),
            ),
          ] else if (_error != null)
            Card(
              color: LuxeColors.danger.withValues(alpha: 0.10),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.error_outline,
                            color: LuxeColors.danger, size: 20),
                        const SizedBox(width: 8),
                        Text('Обновление не установилось',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: dark
                                  ? LuxeColors.danger
                                  : const Color(0xFF9B1C1C),
                            )),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(_error!,
                        style: TextStyle(
                            fontSize: 13.5,
                            color: dark ? Colors.white70 : Colors.black87)),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        OutlinedButton.icon(
                          onPressed: _openInBrowser,
                          icon: const Icon(Icons.open_in_browser, size: 18),
                          label: const Text('Скачать браузером'),
                        ),
                        const SizedBox(width: 8),
                        if (Platform.isAndroid)
                          OutlinedButton.icon(
                            onPressed: UpdateService.openAndroidSettings,
                            icon: const Icon(Icons.settings, size: 18),
                            label: const Text('Разрешения'),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            )
          else if (_status != null)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(_status!),
              ),
            ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _checking || _downloading
                ? null
                : () async {
                    setState(() => _foundVersion = null);
                    await _check();
                    if (_foundVersion != null && mounted) {
                      final info = await UpdateService.check();
                      if (info != null) _askUpdate(info);
                    }
                  },
            icon: _checking
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.refresh_rounded),
            label: Text(_checking ? 'Проверяем...' : 'Проверить обновления'),
          ),
          const SizedBox(height: 24),
          Text(
            'Как это работает\n\n'
            'Приложение сверяет свою версию с сервером и, если вышла '
            'новая, предлагает обновиться.\n\n'
            'На Android и Windows новая версия скачивается и ставится '
            'почти без вашего участия. Система всё равно спросит '
            'подтверждение установки — обойти это нельзя, так устроена '
            'защита.\n\n'
            'На iPhone обновление ставится только через TestFlight или '
            'App Store: система не разрешает приложению обновляться '
            'самостоятельно.',
            style: TextStyle(
              fontSize: 13,
              height: 1.45,
              color: dark ? Colors.white70 : Colors.black54,
            ),
          ),
        ],
      ),
    );
  }
}
