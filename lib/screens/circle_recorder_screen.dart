import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../theme/luxe_theme.dart';

/// Запись видеокружка: круглое превью, максимум 60 секунд.
///
/// Запись идёт через flutter_webrtc, а не системной камерой: нужен
/// круглый кадр и своя кнопка остановки внутри приложения.
class CircleRecorderScreen extends StatefulWidget {
  final int maxSeconds;
  const CircleRecorderScreen({super.key, required this.maxSeconds});

  @override
  State<CircleRecorderScreen> createState() => _CircleRecorderScreenState();
}

class _CircleRecorderScreenState extends State<CircleRecorderScreen> {
  final RTCVideoRenderer _renderer = RTCVideoRenderer();
  MediaStream? _stream;
  MediaRecorder? _recorder;
  String? _outPath;
  Timer? _timer;

  bool _ready = false;
  int _seconds = 0;
  bool _stopping = false;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    try {
      await _renderer.initialize();
      // Портретная камера — кружок снимают обычно «от себя».
      final stream = await navigator.mediaDevices.getUserMedia({
        'video': {
          'facingMode': 'user',
          'width': {'ideal': 480},
          'height': {'ideal': 480},
          'frameRate': {'ideal': 30},
        },
        'audio': true,
      });
      if (!mounted) {
        stream.getTracks().forEach((t) => t.stop());
        return;
      }
      _stream = stream;
      _renderer.srcObject = stream;
      setState(() => _ready = true);
      _beginRecording();
    } catch (e) {
      if (mounted) _fail('Не удалось включить камеру');
    }
  }

  Future<void> _beginRecording() async {
    final dir = Directory.systemTemp.createTempSync('luxe_circle');
    final file = File('${dir.path}/circle.mp4');
    final videoTrack = _stream?.getVideoTracks().firstOrNull;
    try {
      final rec = MediaRecorder();
      // INPUT — писать звук с микрофона. Без аудиоканала кружок
      // выйдет немым, а в Telegram кружки говорят.
      await rec.start(
        file.path,
        videoTrack: videoTrack,
        audioChannel: RecorderAudioChannel.INPUT,
      );
      _recorder = rec;
      _outPath = file.path;
      setState(() {});
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        setState(() => _seconds++);
        // Останавливаем сами: длинные кружки в Telegram не держат.
        if (_seconds >= widget.maxSeconds) _stop();
      });
    } catch (e) {
      if (mounted) _fail('Не удалось начать запись');
    }
  }

  void _fail(String msg) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
    Navigator.pop(context);
  }

  Future<void> _stop() async {
    if (_stopping) return;
    _stopping = true;
    _timer?.cancel();
    _timer = null;
    String? result;
    try {
      result = await _recorder?.stop() as String?;
    } catch (_) {
      result = null;
    }
    if (!mounted) return;
    // На части платформ возвращается путь, на части — void
    final path = result ?? _outPath;
    if (path == null || !File(path).existsSync()) {
      Navigator.pop(context);
      return;
    }
    Navigator.pop(context, path);
  }

  void _cancel() {
    _timer?.cancel();
    // Метода cancel у MediaRecorder нет: останавливаем и удаляем файл.
    _recorder?.stop().catchError((_) {});
    final p = _outPath;
    if (p != null) {
      final f = File(p);
      if (f.existsSync()) {
        try {
          f.deleteSync();
        } catch (_) {}
      }
    }
    Navigator.pop(context);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _stream?.getTracks().forEach((t) => t.stop());
    _stream?.dispose();
    _renderer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            // Круглое превью по центру
            Center(
              child: _ready
                  ? Container(
                      width: 300,
                      height: 300,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                            color: Colors.white.withValues(alpha: 0.18),
                            width: 3),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: RTCVideoView(
                        _renderer,
                        mirror: true,
                        objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                      ),
                    )
                  : const SizedBox(
                      width: 300,
                      height: 300,
                      child: CircularProgressIndicator(color: Colors.white54),
                    ),
            ),
            // Таймер сверху
            Positioned(
              top: 18,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                            shape: BoxShape.circle, color: LuxeColors.danger),
                      ),
                      const SizedBox(width: 7),
                      Text('${_seconds.toString().padLeft(2, '0')}с',
                          style: const TextStyle(
                              color: Colors.white, fontSize: 14)),
                    ],
                  ),
                ),
              ),
            ),
            // Управление снизу
            Positioned(
              bottom: 36,
              left: 0,
              right: 0,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    onPressed: _cancel,
                    iconSize: 30,
                    icon: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white.withValues(alpha: 0.15),
                      ),
                      child:
                          const Icon(Icons.close_rounded, color: Colors.white),
                    ),
                    tooltip: 'Отмена',
                  ),
                  const SizedBox(width: 36),
                  GestureDetector(
                    onTap: _stop,
                    child: Container(
                      width: 76,
                      height: 76,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 4),
                      ),
                      child: Container(
                        margin: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: LuxeColors.danger.withValues(alpha: 0.9),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
