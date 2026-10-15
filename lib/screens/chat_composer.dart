import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../services/media_service.dart';
import '../services/sticker_service.dart';
import '../services/voice_service.dart';
import '../theme/luxe_theme.dart';
import '../widgets/luxe_widgets.dart';
import 'circle_recorder_screen.dart';
import 'sticker_panel.dart';

/// Панель ввода с голосовыми, кружками и стикерами.
///
/// Вынесена отдельно от экранов чата, потому что нужна и в трёхколоночному
/// режиме, и в мобильном — иначе запись пришлось бы писать дважды.
class ChatComposer extends StatefulWidget {
  final TextEditingController controller;
  final bool dark;
  final bool isChannel;
  final VoidCallback onSend;
  final void Function(File file, int seconds, String waveform) onVoiceReady;
  final void Function(File file, int seconds) onCircleReady;
  final void Function(Sticker s) onSticker;
  final void Function() onAddSticker;
  final VoidCallback onOpenAllStickers;
  final VoidCallback onAttachPhoto;
  final VoidCallback onAttachVideo;
  final VoidCallback onAttachFile;

  const ChatComposer({
    super.key,
    required this.controller,
    required this.dark,
    required this.isChannel,
    required this.onSend,
    required this.onVoiceReady,
    required this.onCircleReady,
    required this.onSticker,
    required this.onAddSticker,
    required this.onOpenAllStickers,
    required this.onAttachPhoto,
    required this.onAttachVideo,
    required this.onAttachFile,
  });

  @override
  State<ChatComposer> createState() => ChatComposerState();
}

class ChatComposerState extends State<ChatComposer>
    with TickerProviderStateMixin {
  final VoiceService _voice = VoiceService();
  final List<Sticker> _stickers = [];

  bool _recording = false;
  bool _stickersOpen = false;
  Duration _elapsed = Duration.zero;
  double _level = 0;
  Timer? _uiTick;
  bool _stickersLoaded = false;

  /// Отмена записи голоса по свайпу вверх — как в Telegram.
  bool _cancelArmed = false;

  @override
  void initState() {
    super.initState();
    _loadStickers();
  }

  Future<void> _loadStickers() async {
    if (_stickersLoaded) return;
    _stickersLoaded = true;
    try {
      final list = await StickerService.mine();
      if (!mounted) return;
      setState(() => _stickers.addAll(list));
    } catch (_) {
      // Панель просто останется пустой — это не повод ломать чат
    }
  }

  @override
  void dispose() {
    _uiTick?.cancel();
    _voice.dispose();
    super.dispose();
  }

  // ---------------- Голосовые ----------------

  Future<void> _startVoice() async {
    final ok = await _voice.start();
    if (!ok || !mounted) return;
    setState(() {
      _recording = true;
      _cancelArmed = false;
      _elapsed = Duration.zero;
    });
    // Отдельный таймер: интерфейс должен обновляться ровно раз в 100 мс,
    // а не как получится — иначе цифры дёргаются.
    _uiTick = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (!mounted || !_recording) return;
      setState(() {
        _elapsed = _voice.elapsed;
        _level = _voice.liveLevel;
      });
    });
  }

  Future<void> _finishVoice() async {
    _uiTick?.cancel();
    _uiTick = null;
    final seconds = _voice.elapsed.inSeconds;
    final wave = VoiceService.packWaveform(_voice.waveform);
    final path = await _voice.stop();
    if (!mounted) return;
    setState(() => _recording = false);
    if (path == null) return;
    // Слишком короткое не отправляем — обычно это случайный тап.
    if (seconds < 1) {
      debugPrint('Голосовое слишком короткое, не отправляем');
      return;
    }
    widget.onVoiceReady(File(path), seconds, wave);
  }

  Future<void> _cancelVoice() async {
    _uiTick?.cancel();
    _uiTick = null;
    await _voice.cancel();
    if (!mounted) return;
    setState(() => _recording = false);
  }

  // ---------------- Сборка ----------------

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_stickersOpen)
          StickerPanel(
            stickers: _stickers,
            onPick: widget.onSticker,
            onOpenAll: widget.onOpenAllStickers,
            onAdd: () async {
              final ok = await showAddStickerDialog(context);
              if (ok) {
                _stickersLoaded = false;
                _loadStickers();
              }
            },
          ),
        if (_recording)
          _recordingBar()
        else
          _normalRow(),
      ],
    );
  }

  /// Строка записи голоса: таймер, уровень, кнопки.
  Widget _recordingBar() {
    final fg = Colors.white;
    return Container(
      color: widget.dark ? LuxeColors.darkCard : Colors.white,
      padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
      child: Row(
        children: [
          IconButton(
            onPressed: _cancelVoice,
            icon: Icon(Icons.delete_outline_rounded, color: fg, size: 22),
            tooltip: 'Удалить запись',
          ),
          Expanded(
            child: GestureDetector(
              onVerticalDragUpdate: (d) {
                // Свайп вверх над кнопкой отмены — привычное
                // «отпустил выше — запись удалится».
                if (d.delta.dy < -2 && !_cancelArmed) {
                  setState(() => _cancelArmed = true);
                } else if (d.delta.dy > 2 && _cancelArmed) {
                  setState(() => _cancelArmed = false);
                }
              },
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 9,
                        height: 9,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: LuxeColors.danger,
                        ),
                      ),
                      const SizedBox(width: 7),
                      Text(_clock(_elapsed),
                          style: TextStyle(
                              fontSize: 13,
                              color: fg,
                              fontFeatures: const [
                                FontFeature.tabularFigures()
                              ])),
                      const Spacer(),
                      if (_cancelArmed)
                        Text('Отпустите для отмены',
                            style: TextStyle(
                                fontSize: 12,
                                color: LuxeColors.danger.withValues(alpha: 0.9))),
                    ],
                  ),
                  const SizedBox(height: 7),
                  // Уровень в реальном времени
                  ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                      value: _level.clamp(0.02, 1.0),
                      minHeight: 4,
                      backgroundColor: fg.withValues(alpha: 0.15),
                      valueColor: const AlwaysStoppedAnimation(LuxeColors.tgBlue),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            onPressed: _finishVoice,
            icon: Container(
              padding: const EdgeInsets.all(8),
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: LuxeColors.tgBlue,
              ),
              child: const Icon(Icons.send_rounded, color: Colors.white, size: 18),
            ),
            tooltip: 'Отправить',
          ),
        ],
      ),
    );
  }

  Widget _normalRow() {
    final fg = widget.dark ? Colors.white : Colors.black87;
    return Container(
      color: widget.dark ? LuxeColors.darkCard : Colors.white,
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
      child: Row(
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: widget.dark ? LuxeColors.darkField : Colors.grey.shade200,
                borderRadius: BorderRadius.circular(26),
              ),
              child: TextField(
                controller: widget.controller,
                minLines: 1,
                maxLines: 4,
                decoration: InputDecoration(
                  hintText: widget.isChannel ? 'Новый пост...' : 'Сообщение...',
                  border: InputBorder.none,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                ),
                onSubmitted: (_) => widget.onSend(),
              ),
            ),
          ),
          const SizedBox(width: 4),
          StickerButton(onTap: () => _toggleStickers()),
          // Микрофон — только пока поле пустое: набранный текст важнее,
          // иначе кнопки начинают спорить с кнопкой отправки.
          if (!widget.isChannel && widget.controller.text.isEmpty)
            IconButton(
              onPressed: _startVoice,
              icon: Icon(Icons.mic_none_rounded, size: 22, color: fg),
              tooltip: 'Голосовое сообщение',
            ),
          // Вложения нужны и в каналах — кружок там лишний, потому
          // что это личная запись, а не пост.
          PopupMenuButton<String>(
            icon: const Icon(Icons.attach_file_rounded, size: 22),
            tooltip: 'Прикрепить',
            onSelected: (v) {
              switch (v) {
                case 'photo':
                  widget.onAttachPhoto();
                  break;
                case 'video':
                  widget.onAttachVideo();
                  break;
                case 'circle':
                  _recordCircle();
                  break;
                default:
                  widget.onAttachFile();
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'photo',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.image_rounded, color: LuxeColors.tgBlue),
                  title: Text('Фото'),
                ),
              ),
              const PopupMenuItem(
                value: 'video',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.movie_rounded, color: LuxeColors.tgBlue),
                  title: Text('Видео'),
                ),
              ),
              if (!widget.isChannel)
                const PopupMenuItem(
                  value: 'circle',
                  child: ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading:
                        Icon(Icons.circle_outlined, color: LuxeColors.tgBlue),
                    title: Text('Кружок'),
                  ),
                ),
              const PopupMenuItem(
                value: 'file',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.insert_drive_file_rounded,
                      color: LuxeColors.tgBlue),
                  title: Text('Файл'),
                ),
              ),
            ],
          ),
          const SizedBox(width: 4),
          SendButton(onTap: widget.onSend),
        ],
      ),
    );
  }

  Future<void> _recordCircle() async {
    final path = await CircleRecorder.record(context, maxSeconds: 60);
    if (path == null) return;
    final seconds = await MediaService.durationOf(path);
    widget.onCircleReady(File(path), seconds);
  }

  void _toggleStickers() {
    setState(() => _stickersOpen = !_stickersOpen);
    if (_stickersOpen) _loadStickers();
  }
}

/// Запись видеокружка внутри приложения.
///
/// Отдельный экран, а не системная камера: нужен круглый кадр и
/// ограничение по длине, как в Telegram.
class CircleRecorder {
  static Future<String?> record(
    BuildContext context, {
    int maxSeconds = 60,
  }) {
    return Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => CircleRecorderScreen(maxSeconds: maxSeconds)),
    );
  }

  /// Длительность уже записанного файла, секунды.
  static Future<int> durationOf(String path) async {
    try {
      final p = await MediaService.durationOf(path);
      return p;
    } catch (_) {
      return 0;
    }
  }
}

String _clock(Duration d) =>
    '${d.inMinutes.toString().padLeft(2, '0')}:'
    '${(d.inSeconds % 60).toString().padLeft(2, '0')}';
