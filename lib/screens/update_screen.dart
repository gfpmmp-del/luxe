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
    });
    try {
      final path = await UpdateService.download(
        info,
        onProgress: (v) {
          if (mounted) setState(() => _progress = v);
        },
      );
      if (!mounted) return;
      if (path == null) {
        setState(() {
          _downloading = false;
          _status = 'Не удалось скачать обновление';
        });
        return;
      }
      setState(() => _downloading = false);

      if (Platform.isAndroid) {
        final ok = await UpdateService.installAndroid(path);
        if (!ok && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Не удалось открыть установщик'),
          ));
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
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _downloading = false;
        _status = 'Ошибка обновления: $e';
      });
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
          ] else if (_status != null)
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
