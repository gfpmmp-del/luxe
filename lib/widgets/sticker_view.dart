import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';

import '../services/media_service.dart';
import '../theme/luxe_theme.dart';
import 'net_image.dart';

/// Показ стикера: Lottie, GIF или статичная картинка.
///
/// Три формата живут в одном виджете, потому что отправка и хранение
/// у них одинаковые, а различается только отрисовка.
class StickerView extends StatelessWidget {
  final String url;
  final String kind;
  final double size;
  final bool animate;

  const StickerView({
    super.key,
    required this.url,
    required this.kind,
    this.size = 120,
    this.animate = true,
  });

  @override
  Widget build(BuildContext context) {
    // Ссылки, записанные во времена прокси, надо чинить: адрес сменился,
    // а в базе остался старый.
    final fixed = MediaService.fixUrl(url) ?? '';
    switch (kind) {
      case 'lottie':
        // tgs — это zip с json внутри, Lottie его не читает.
        // Поддерживаем только голый json; tts-файл покажем заглушкой.
        if (fixed.toLowerCase().endsWith('.tgs')) {
          return _fallback(context, Icons.animation_rounded, 'TGS');
        }
        return ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: MediaService.needsChunks(fixed)
              ? _LottieBytes(url: fixed, size: size, animate: animate)
              : Lottie.network(
                  fixed,
                  width: size,
                  height: size,
                  repeat: animate,
                  fit: BoxFit.contain,
                  // Сеть может не ответить — показываем пустое место,
                  // а не ошибку на весь экран.
                  errorBuilder: (_, __, ___) =>
                      SizedBox(width: size, height: size),
                ),
        );
      default:
        return NetImage(
          fixed,
          width: size,
          height: size,
          fit: BoxFit.contain,
          // GIF и WebP с анимацией играют сами по себе.
          timeoutSeconds: 15,
          fallback: SizedBox(
            width: size,
            height: size,
            child: _fallback(context, Icons.broken_image_outlined, ''),
          ),
        );
    }
  }

  Widget _fallback(BuildContext context, IconData icon, String label) {
    return SizedBox(
      width: size,
      height: size,
      child: Container(
        decoration: BoxDecoration(
          color: LuxeColors.tgBlue.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Center(
          child: label.isEmpty
              ? Icon(icon, color: Colors.white54, size: size * 0.35)
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, color: Colors.white54, size: size * 0.3),
                    const SizedBox(height: 4),
                    Text(label,
                        style: TextStyle(
                            color: Colors.white54, fontSize: size * 0.12)),
                  ],
                ),
        ),
      ),
    );
  }
}

/// Lottie, скачанный кусками: `Lottie.network` не умеет добирать
/// оборванный ответ, а через старый прокси JSON приходит не целиком.
class _LottieBytes extends StatefulWidget {
  final String url;
  final double size;
  final bool animate;

  const _LottieBytes({
    required this.url,
    required this.size,
    required this.animate,
  });

  @override
  State<_LottieBytes> createState() => _LottieBytesState();
}

class _LottieBytesState extends State<_LottieBytes> {
  Uint8List? _bytes;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final bytes = await MediaService.imageBytes(widget.url);
      if (mounted) setState(() => _bytes = bytes);
    } catch (_) {
      // Останется пустое место — как и при ошибке сети.
    }
  }

  @override
  Widget build(BuildContext context) {
    final bytes = _bytes;
    if (bytes == null) {
      return SizedBox(width: widget.size, height: widget.size);
    }
    return Lottie.memory(
      bytes,
      width: widget.size,
      height: widget.size,
      repeat: widget.animate,
      fit: BoxFit.contain,
      errorBuilder: (_, __, ___) =>
          SizedBox(width: widget.size, height: widget.size),
    );
  }
}

/// Превью стикера в наборе — компактная плитка.
class StickerThumb extends StatelessWidget {
  final StickerView sticker;
  const StickerThumb({super.key, required this.sticker});

  @override
  Widget build(BuildContext context) {
    return sticker;
  }
}
