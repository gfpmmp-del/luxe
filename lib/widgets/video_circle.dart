import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../theme/luxe_theme.dart';

/// Видеокружок: запись, отправленная круглым значком.
///
/// Пока не открыт — это тихий превью, как в Telegram: играет без звука
/// и только когда попадает в поле зрения. По нажатию открывается на весь
/// экран со звуком.
class VideoCircle extends StatefulWidget {
  final String url;
  final int durationSeconds;
  final bool mine;

  const VideoCircle({
    super.key,
    required this.url,
    required this.durationSeconds,
    required this.mine,
  });

  @override
  State<VideoCircle> createState() => _VideoCircleState();
}

class _VideoCircleState extends State<VideoCircle> {
  VideoPlayerController? _c;
  bool _ready = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      final c = VideoPlayerController.networkUrl(Uri.parse(widget.url));
      await c.initialize();
      await c.setLooping(true);
      await c.setVolume(0); // превью всегда без звука
      await c.play();
      if (!mounted) {
        await c.dispose();
        return;
      }
      setState(() {
        _c = c;
        _ready = true;
      });
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  @override
  void dispose() {
    _c?.dispose();
    super.dispose();
  }

  /// Открыть кружок на весь экран со звуком.
  Future<void> _open() async {
    await Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.black,
        pageBuilder: (_, __, ___) => _CircleViewer(url: widget.url),
        transitionsBuilder: (_, anim, __, child) =>
            FadeTransition(opacity: anim, child: child),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const size = 168.0;
    return GestureDetector(
      onTap: _open,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.black.withValues(alpha: 0.55),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.12),
            width: 2,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (_ready && _c != null)
              FittedBox(
                fit: BoxFit.cover,
                child: SizedBox(
                  width: _c!.value.size.width,
                  height: _c!.value.size.height,
                  child: VideoPlayer(_c!),
                ),
              )
            else if (_error != null)
              Center(
                child: Icon(Icons.videocam_off_rounded,
                    color: Colors.white54, size: 30),
              )
            else
              const Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white54),
                ),
              ),
            // Длительность внизу, как у Телеграма
            if (widget.durationSeconds > 0)
              Positioned(
                bottom: 10,
                left: 0,
                right: 0,
                child: Center(
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.45),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '${widget.durationSeconds}с',
                      style: const TextStyle(
                          fontSize: 11, color: Colors.white, height: 1.2),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Полноэкранный просмотр кружка со звуком.
class _CircleViewer extends StatefulWidget {
  final String url;
  const _CircleViewer({required this.url});

  @override
  State<_CircleViewer> createState() => _CircleViewerState();
}

class _CircleViewerState extends State<_CircleViewer> {
  VideoPlayerController? _c;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      final c = VideoPlayerController.networkUrl(Uri.parse(widget.url));
      await c.initialize();
      await c.setLooping(true);
      await c.play(); // здесь со звуком
      if (!mounted) {
        await c.dispose();
        return;
      }
      setState(() {
        _c = c;
        _ready = true;
      });
    } catch (_) {
      // закрыть по тапу
    }
  }

  @override
  void dispose() {
    _c?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.pop(context),
      child: Container(
        color: Colors.black,
        child: Center(
          child: _ready && _c != null
              ? AspectRatio(
                  aspectRatio: _c!.value.aspectRatio,
                  child: VideoPlayer(_c!),
                )
              : const CircularProgressIndicator(color: Colors.white54),
        ),
      ),
    );
  }
}

/// Превью кружка на месте отправки — заглушка с камерой.
class VideoCirclePlaceholder extends StatelessWidget {
  const VideoCirclePlaceholder({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 168,
      height: 168,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.black.withValues(alpha: 0.55),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12), width: 2),
      ),
      child: const Center(
        child: Icon(Icons.hourglass_empty_rounded, color: Colors.white54, size: 26),
      ),
    );
  }
}

/// Значок «запись кружка» в композере.
class CircleRecordIcon extends StatelessWidget {
  const CircleRecordIcon({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: LuxeColors.tgBlue, width: 2.5),
      ),
      child: Container(
        margin: const EdgeInsets.all(3),
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          color: LuxeColors.tgBlue,
        ),
      ),
    );
  }
}
