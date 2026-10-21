import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../services/media_service.dart';
import '../theme/luxe_theme.dart';

/// Картинка из сети, которая умеет сдаваться и пробовать другой адрес.
///
/// У `Image.network` нет ни таймаута, ни запасного варианта: если
/// соединение не рвётся, а просто висит, спиннер крутится вечно.
/// Здесь адрес перебирается по очереди — сначала тот, через который
/// приложение сейчас ходит на сервер, затем второй. Если не вышло
/// ни там, ни там, показывается понятная заглушка с повтором.
class NetImage extends StatefulWidget {
  final String url;

  /// Готовый список адресов. Если не задан, берётся из
  /// [MediaService.candidates].
  final List<String>? urls;

  final BoxFit fit;
  final double? width;
  final double? height;
  final int timeoutSeconds;

  /// Что показать, когда не открылось ничего. Например, букву
  /// на месте аватарки.
  final Widget? fallback;

  const NetImage(
    this.url, {
    super.key,
    this.urls,
    this.fit = BoxFit.cover,
    this.width,
    this.height,
    this.timeoutSeconds = 9,
    this.fallback,
  });

  @override
  State<NetImage> createState() => _NetImageState();
}

class _NetImageState extends State<NetImage> {
  late List<String> _urls;
  int _index = 0;
  int _attempt = 0;
  bool _slow = false;
  bool _failed = false;
  Timer? _timer;
  Timer? _grace;

  @override
  void initState() {
    super.initState();
    _urls = _buildList();
    _arm();
  }

  List<String> _buildList() {
    final given = widget.urls;
    final list = (given != null && given.isNotEmpty)
        ? given
        : MediaService.candidates(widget.url);
    return list.isEmpty ? [widget.url] : list;
  }

  @override
  void didUpdateWidget(NetImage old) {
    super.didUpdateWidget(old);
    if (old.url != widget.url || old.urls != widget.urls) {
      _index = 0;
      _attempt++;
      _slow = false;
      _failed = false;
      _urls = _buildList();
      _arm();
    }
  }

  void _arm() {
    _grace?.cancel();
    _timer?.cancel();
    // Сначала просто предупреждение: файл может быть большим и идти
    // медленно, ругаться раньше времени незачем.
    _grace = Timer(const Duration(seconds: 6), () {
      if (mounted && !_failed) setState(() => _slow = true);
    });
    // Через старый прокси файл тянут кусками — это дольше обычного,
    // поэтому даём больше времени, чем одному запросу.
    final seconds = MediaService.needsChunks(_urls[_index])
        ? 60
        : widget.timeoutSeconds;
    _timer = Timer(Duration(seconds: seconds), _nextOrFail);
  }

  /// Следующий адрес, а если их больше нет — заглушка.
  void _nextOrFail() {
    if (!mounted) return;
    if (_index < _urls.length - 1) {
      setState(() {
        _index++;
        _attempt++;
        _slow = false;
      });
      _arm();
    } else {
      setState(() {
        _failed = true;
        _slow = false;
      });
    }
  }

  void _retry() {
    if (!mounted) return;
    setState(() {
      _index = 0;
      _attempt++;
      _failed = false;
      _slow = false;
    });
    _arm();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _grace?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = scheme.brightness == Brightness.dark;
    final bg = dark ? Colors.white10 : Colors.black12;

    if (_failed) {
      final custom = widget.fallback;
      if (custom != null) return custom;
      return GestureDetector(
        onTap: _retry,
        child: Container(
          width: widget.width,
          height: widget.height,
          color: bg,
          alignment: Alignment.center,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.cloud_off_rounded,
                  size: 24, color: dark ? Colors.white38 : Colors.black38),
              const SizedBox(height: 4),
              Text('Не открылось',
                  style: TextStyle(
                      fontSize: 11,
                      color: dark ? Colors.white54 : Colors.black54)),
              Text('Нажмите, чтобы повторить',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 9,
                      color: dark ? Colors.white38 : Colors.black45)),
            ],
          ),
        ),
      );
    }

    final current = _urls[_index];

    // Через старый прокси одним запросом файл не доезжает — качаем
    // кусками и показываем уже готовые байты.
    if (MediaService.needsChunks(current)) {
      return _BytesImage(
        key: ValueKey('$current#$_attempt'),
        url: current,
        width: widget.width,
        height: widget.height,
        fit: widget.fit,
        bg: bg,
        dark: dark,
        onLoaded: () {
          _timer?.cancel();
          _grace?.cancel();
          if (mounted && _slow) setState(() => _slow = false);
        },
        onError: () {
          _timer?.cancel();
          _grace?.cancel();
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _nextOrFail();
          });
        },
      );
    }

    return Image.network(
      current,
      key: ValueKey('$current#$_attempt'),
      width: widget.width,
      height: widget.height,
      fit: widget.fit,
      gaplessPlayback: true,
      loadingBuilder: (c, child, progress) {
        // Пошли байты — снимаем все таймеры: загрузка живая.
        if (progress != null && (_slow || _failed)) {
          _timer?.cancel();
          _grace?.cancel();
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              setState(() {
                _slow = false;
                _failed = false;
              });
            }
          });
        }
        if (progress == null) return child;
        return _spinner(bg, dark, warning: _slow);
      },
      errorBuilder: (c, e, s) {
        _timer?.cancel();
        _grace?.cancel();
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _nextOrFail();
        });
        return Container(
          width: widget.width,
          height: widget.height,
          color: bg,
          alignment: Alignment.center,
          child: Icon(Icons.image_outlined,
              size: 22, color: dark ? Colors.white24 : Colors.black26),
        );
      },
    );
  }

  Widget _spinner(Color bg, bool dark, {required bool warning}) {
    return Container(
      width: widget.width,
      height: widget.height,
      color: bg,
      alignment: Alignment.center,
      child: warning
          ? Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2)),
                const SizedBox(height: 4),
                Text('Сеть не отвечает…',
                    style: TextStyle(
                        fontSize: 10, color: LuxeColors.danger)),
              ],
            )
          : const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
    );
  }
}

/// Картинка, которую сначала целиком скачали в память.
///
/// Нужна только для адреса через старый прокси: он отдаёт файл
/// обрезанным, а `Image.network` не умеет добирать остаток. Здесь байты
/// приходят кусками и склеиваются в [MediaService].
class _BytesImage extends StatefulWidget {
  final String url;
  final double? width;
  final double? height;
  final BoxFit fit;
  final Color bg;
  final bool dark;
  final VoidCallback onLoaded;
  final VoidCallback onError;

  const _BytesImage({
    super.key,
    required this.url,
    required this.width,
    required this.height,
    required this.fit,
    required this.bg,
    required this.dark,
    required this.onLoaded,
    required this.onError,
  });

  @override
  State<_BytesImage> createState() => _BytesImageState();
}

class _BytesImageState extends State<_BytesImage> {
  Uint8List? _bytes;
  bool _failed = false;
  bool _slow = false;
  Timer? _grace;

  @override
  void initState() {
    super.initState();
    _grace = Timer(const Duration(seconds: 6), () {
      if (mounted) setState(() => _slow = true);
    });
    _load();
  }

  Future<void> _load() async {
    try {
      final bytes = await MediaService.imageBytes(widget.url);
      if (!mounted) return;
      _grace?.cancel();
      setState(() => _bytes = bytes);
      widget.onLoaded();
    } catch (_) {
      if (!mounted) return;
      _grace?.cancel();
      setState(() => _failed = true);
      widget.onError();
    }
  }

  @override
  void dispose() {
    _grace?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_bytes != null) {
      return Image.memory(
        _bytes!,
        width: widget.width,
        height: widget.height,
        fit: widget.fit,
        gaplessPlayback: true,
        errorBuilder: (c, e, s) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) widget.onError();
          });
          return _box(icon: Icons.image_outlined);
        },
      );
    }

    if (_failed) return _box(icon: Icons.image_outlined);

    return Container(
      width: widget.width,
      height: widget.height,
      color: widget.bg,
      alignment: Alignment.center,
      child: _slow
          ? Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2)),
                const SizedBox(height: 4),
                const Text('Загружаем…',
                    style: TextStyle(fontSize: 10, color: LuxeColors.danger)),
              ],
            )
          : const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
    );
  }

  Widget _box({required IconData icon}) {
    return Container(
      width: widget.width,
      height: widget.height,
      color: widget.bg,
      alignment: Alignment.center,
      child: Icon(icon,
          size: 22,
          color: widget.dark ? Colors.white24 : Colors.black26),
    );
  }
}
