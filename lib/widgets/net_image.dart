import 'dart:async';

import 'package:flutter/material.dart';

import '../theme/luxe_theme.dart';

/// Картинка из сети, которая умеет сдаваться.
///
/// У `Image.network` нет таймаута: если соединение не рвётся, а просто
/// висит, спиннер крутится вечно и человек не понимает, что картинку
/// не грузит сеть. Здесь появляется обратный отсчёт и кнопка
/// «Не открылось — повторить».
class NetImage extends StatefulWidget {
  final String url;
  final BoxFit fit;
  final double? width;
  final double? height;
  final int timeoutSeconds;

  const NetImage(
    this.url, {
    super.key,
    this.fit = BoxFit.cover,
    this.width,
    this.height,
    this.timeoutSeconds = 15,
  });

  @override
  State<NetImage> createState() => _NetImageState();
}

class _NetImageState extends State<NetImage> {
  /// Пока хоть какие-то байты идут, показываем обычную загрузку:
  /// пугать человека раньше времени незачем.
  bool _slow = false;
  bool _failed = false;
  Timer? _timer;
  Timer? _grace;

  @override
  void initState() {
    super.initState();
    _arm();
  }

  @override
  void didUpdateWidget(NetImage old) {
    super.didUpdateWidget(old);
    if (old.url != widget.url) {
      _slow = false;
      _failed = false;
      _arm();
    }
  }

  void _arm() {
    _grace?.cancel();
    _timer?.cancel();
    // Сначала просто предупреждение: вдруг файл большой и идёт
    // медленно, ругаться рано.
    _grace = Timer(const Duration(seconds: 8), () {
      if (mounted) setState(() => _slow = true);
    });
    _timer = Timer(Duration(seconds: widget.timeoutSeconds), () {
      if (mounted) setState(() => _failed = true);
    });
  }

  void _retry() {
    _slow = false;
    _failed = false;
    _arm();
    // Ключ меняется — виджет перезапрашивает файл заново.
    setState(() => _attempt++);
  }

  int _attempt = 0;

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
                  size: 26, color: dark ? Colors.white38 : Colors.black38),
              const SizedBox(height: 6),
              const Text('Не открылось',
                  style: TextStyle(fontSize: 12)),
              const SizedBox(height: 2),
              Text('Нажмите, чтобы повторить',
                  style: TextStyle(
                      fontSize: 11,
                      color: dark ? Colors.white38 : Colors.black45)),
            ],
          ),
        ),
      );
    }

    return Image.network(
      widget.url,
      key: ValueKey('${widget.url}#$_attempt'),
      width: widget.width,
      height: widget.height,
      fit: widget.fit,
      gaplessPlayback: true,
      loadingBuilder: (c, child, progress) {
        // Получили хоть какие-то байты — снимаем таймер.
        if (progress != null && (_slow || _failed)) {
          _timer?.cancel();
          _grace?.cancel();
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) setState(() { _slow = false; _failed = false; });
          });
        }
        if (progress == null) return child;
        if (!_slow) return _spinner(bg, dark, warning: false);
        return _spinner(bg, dark, warning: true);
      },
      errorBuilder: (c, e, s) {
        _timer?.cancel();
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) setState(() => _failed = true);
        });
        return Container(
          width: widget.width,
          height: widget.height,
          color: bg,
          alignment: Alignment.center,
          child: Icon(Icons.broken_image_rounded,
              size: 28, color: dark ? Colors.white38 : Colors.black38),
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
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2)),
                const SizedBox(height: 6),
                Text('Сеть не отвечает…',
                    style: TextStyle(
                        fontSize: 11, color: LuxeColors.danger)),
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