import 'dart:async';

import 'package:flutter/material.dart';

import '../services/media_service.dart';
import '../services/voice_service.dart';
import '../theme/luxe_theme.dart';

  /// Голосовое сообщение: кнопка, звуковая волна, время и галочка
  /// прослушивания — как в Telegram.
  ///
  /// [url] чинится на лету: ссылки, записанные во времена прокси,
  /// указывают на адрес, который уже не обслуживает файлы.
  class VoiceMessage extends StatefulWidget {
  final String url;
  final String? waveform; // упакованная волна из БД
  final int durationSeconds;
  final bool mine;
  final bool dark;
  final bool played;
  final String? status;
  final VoidCallback? onPlayed;

  const VoiceMessage({
    super.key,
    required this.url,
    required this.waveform,
    required this.durationSeconds,
    required this.mine,
    required this.dark,
    this.played = false,
    this.status,
    this.onPlayed,
  });

  @override
  State<VoiceMessage> createState() => _VoiceMessageState();
}

class _VoiceMessageState extends State<VoiceMessage> {
  StreamSubscription<Duration>? _posSub;
  StreamSubscription<bool>? _stateSub;
  Duration _position = Duration.zero;
  Duration? _total;
  bool _playing = false;

  /// Ссылка, по которой реально качаем: старая, записанная во времена
  /// прокси, не работает.
  late final String _playable;

  @override
  void initState() {
    super.initState();
    _playable = MediaService.fixUrl(widget.url) ?? widget.url;
    final p = VoicePlayer.instance;
    _posSub = p.position.listen((v) {
      if (!mounted) return;
      setState(() => _position = v);
      // Дослушали — отмечаем прочитанным, иначе точка остаётся вечной.
      if (p.duration != null && v >= p.duration! - const Duration(milliseconds: 400)) {
        _markPlayed();
      }
    });
    _stateSub = p.playing.listen((v) {
      if (!mounted) return;
      setState(() => _playing = v);
    });
    if (widget.url.isEmpty) return;
    // Длительность из БД — до загрузки, чтобы таймер не прыгал.
    if (widget.durationSeconds > 0) {
      _total = Duration(seconds: widget.durationSeconds);
    }
  }

  @override
  void dispose() {
    _posSub?.cancel();
    _stateSub?.cancel();
    super.dispose();
  }

  Future<void> _markPlayed() async {
    // Отметку о прослушивании ставит вызывающий экран — здесь только
    // держим локально, чтобы точка исчезла сразу.
    if (widget.played) return;
    widget.onPlayed?.call();
  }

  String get _clock {
    final d = _playing || _position > Duration.zero ? _position : (_total ?? Duration.zero);
    final m = d.inMinutes.toString();
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  double get _progress {
    final total = _total ?? VoicePlayer.instance.duration;
    if (total == null || total.inMilliseconds == 0) return 0;
    return (_position.inMilliseconds / total.inMilliseconds).clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    final fg = widget.mine || widget.dark ? Colors.white : Colors.black87;
    final dim = widget.mine || widget.dark ? Colors.white54 : Colors.black45;
    final bars = VoiceService.unpackWaveform(widget.waveform);
    // Без сохранённой волны рисуем ровную полосу — так тоже узнаваемо.
    final showProgress = _playing || _position > Duration.zero;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _playButton(fg, dim),
        const SizedBox(width: 8),
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _wave(bars, fg, dim, showProgress),
              const SizedBox(height: 2),
              Text(_clock, style: TextStyle(fontSize: 11, color: dim)),
            ],
          ),
        ),
        if (!widget.played) ...[
          const SizedBox(width: 6),
          Icon(Icons.visibility_outlined, size: 14, color: dim),
        ],
      ],
    );
  }

  Widget _playButton(Color fg, Color dim) {
    final playing = VoicePlayer.instance.isPlaying(widget.url);
    return InkWell(
      customBorder: const CircleBorder(),
      onTap: widget.url.isEmpty
          ? null
          : () async {
              await VoicePlayer.instance.toggle(_playable);
              _markPlayed();
            },
      child: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: widget.mine || widget.dark
              ? Colors.white.withValues(alpha: 0.18)
              : LuxeColors.neonBlue.withValues(alpha: 0.14),
        ),
        child: widget.url.isEmpty
            ? Icon(Icons.hourglass_empty_rounded, size: 20, color: dim)
            : Icon(
                playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                color: fg,
                size: 24,
              ),
      ),
    );
  }

  Widget _wave(List<double> bars, Color fg, Color dim, bool showProgress) {
    const count = 34;
    // Без сохранённой волны рисуем ровную полосу — так тоже узнаваемо.
    final data = bars.isEmpty
        ? List<double>.filled(count, 0.12)
        : bars.length >= count
            ? bars
            : List<double>.generate(
                count,
                (i) => bars[(i * bars.length / count)
                    .floor()
                    .clamp(0, bars.length - 1)]);

    return LayoutBuilder(
      builder: (context, box) {
        return GestureDetector(
          onTapDown: (d) async {
            final total = _total ?? VoicePlayer.instance.duration;
            if (total == null || total.inMilliseconds == 0) return;
            final frac = (d.localPosition.dx / box.maxWidth).clamp(0.0, 1.0);
            await VoicePlayer.instance.seekFraction(_playable, frac);
            _markPlayed();
          },
          child: SizedBox(
            height: 26,
            width: box.maxWidth.isFinite ? box.maxWidth : 150,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: List.generate(data.length, (i) {
                final v = data[i].clamp(0.05, 1.0);
                final played = showProgress && (i / data.length) <= _progress;
                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 0.6),
                    child: Container(
                      height: 26 * v,
                      decoration: BoxDecoration(
                        color: played ? fg : dim,
                        borderRadius: BorderRadius.circular(1),
                      ),
                    ),
                  ),
                );
              }),
            ),
          ),
        );
      },
    );
  }
}
