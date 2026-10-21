import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../services/call_service.dart';
import '../theme/luxe_theme.dart';
import '../widgets/luxe_widgets.dart';

/// Экран звонка в стиле Telegram: аватар по центру, имя, таймер,
/// панель кнопок с подписями.
class CallScreen extends StatefulWidget {
  final String chatId;
  final String calleeId; // пусто если входящий
  final String title;
  final String? avatarUrl;
  final bool video;
  final Map<String, dynamic>? incomingOffer;

  const CallScreen({
    super.key,
    required this.chatId,
    required this.calleeId,
    this.title = '',
    this.avatarUrl,
    this.video = true,
    this.incomingOffer,
  });

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  late CallService call;
  bool muted = false;
  bool cameraOff = false;
  bool speaker = false;
  bool inCall = false;
  bool failed = false;
  String status = 'Соединение...';
  DateTime? _connectedAt;
  Timer? _ticker;
  Timer? _closeTimer;

  String get name =>
      widget.title.isNotEmpty ? widget.title : 'Звонок';

  bool get isVideo {
    final offer = widget.incomingOffer;
    if (offer != null) {
      final p = offer['payload'];
      return p is Map && p['video'] == true;
    }
    return widget.video;
  }

  @override
  void initState() {
    super.initState();
    call = CallService(
      onRemoteStream: _markConnected,
      // Собеседник нажал «Ответить». Экран должен сказать об этом
      // сразу: раньше он до самого соединения писал «Вызов...», и
      // звонящему казалось, что звонок не приняли.
      onAnswered: () {
        if (!mounted || inCall) return;
        setState(() => status = 'Соединяем…');
      },
      // Экран закрывает только onCallEnded. Если закрывать ещё и в
      // onSignal, при сбросе вызывается Navigator.pop дважды — экран
      // вылетает или остаётся чёрным.
      onSignal: (_) {},
      onError: (error) {
        if (!mounted) return;
        setState(() {
          inCall = false;
          failed = true;
          status = error;
        });
        _ticker?.cancel();
        _closeTimer?.cancel();
        // Причину сбоя показываем пару секунд, потом закрываем экран.
        // Раньше закрытие шло сразу и сообщение не успевало показаться.
        _closeTimer = Timer(const Duration(milliseconds: 1800), _closeOnce);
      },
      onCallEnded: _closeOnce,
    );
    _start();
  }

  /// Закрыть экран звонка. Гарантирует один pop за вызовы.
  void _closeOnce() {
    _closeTimer?.cancel();
    _closeTimer = null;
    if (!mounted) return;
    final nav = Navigator.of(context);
    if (nav.canPop()) nav.pop();
  }

  void _markConnected() {
    // Защита от повторного вызова: иначе тикер запускался бы дважды
    // и таймер шёл бы вдвое быстрее.
    if (!mounted || inCall) return;
    _closeTimer?.cancel();
    setState(() {
      inCall = true;
      failed = false;
      _connectedAt = DateTime.now();
    });
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  Future<void> _start() async {
    await call.initRenderers();
    if (mounted) setState(() {});
    try {
      if (widget.incomingOffer != null) {
        setState(() => status = 'Принимаем звонок');
        await call.answerCall(widget.incomingOffer!);
        if (mounted && !inCall) setState(() => status = 'Соединяем…');
      } else {
        setState(() => status = 'Вызов...');
        await call.startCall(
          calleeId: widget.calleeId,
          chatId: widget.chatId,
          video: isVideo,
        );
      }
      // Статус дальше меняет только реальное соединение или сбой.
      // Раньше тут безусловно писалось «В эфире» сразу после отправки
      // offer — звонок ещё не был соединён, но экран врал.
    } catch (e) {
      if (!mounted) return;
      setState(() {
        inCall = false;
        failed = true;
        status = 'Не удалось соединиться';
      });
    }
  }

  String get _timer {
    final from = _connectedAt;
    if (from == null) return '';
    final d = DateTime.now().difference(from);
    return '${d.inMinutes.toString().padLeft(2, '0')}:'
        '${(d.inSeconds % 60).toString().padLeft(2, '0')}';
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _closeTimer?.cancel();
    call.hangup();
    call.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hasRemoteVideo =
        isVideo && call.remoteRenderer.srcObject != null;

    return Scaffold(
      backgroundColor: const Color(0xFF212121),
      body: SafeArea(
        child: Stack(
          children: [
            // Видео собеседника на весь экран
            if (hasRemoteVideo)
              Positioned.fill(
                child: RTCVideoView(
                  call.remoteRenderer,
                  objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                ),
              ),
            // Затемнение сверху и снизу, чтобы текст читался поверх видео
            if (hasRemoteVideo)
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withValues(alpha: 0.6),
                        Colors.transparent,
                        Colors.black.withValues(alpha: 0.7),
                      ],
                      stops: const [0, 0.45, 1],
                    ),
                  ),
                ),
              ),
            Column(
              children: [
                // Аватар, имя и статус
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 148,
                        height: 148,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white10,
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.08),
                          ),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: GradientAvatar(
                          name: name,
                          radius: 74,
                          imageUrl: widget.avatarUrl,
                        ),
                      ),
                      const SizedBox(height: 22),
                      Text(
                        name,
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        inCall ? _timer : status,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: failed
                              ? LuxeColors.danger
                              : Colors.white.withValues(alpha: 0.7),
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
                ),
                // Своё видео
                if (isVideo && call.localRenderer.srcObject != null)
                  Align(
                    alignment: Alignment.topRight,
                    child: Container(
                      margin: const EdgeInsets.only(top: 12, right: 12),
                      width: 108,
                      height: 152,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white24, width: 2),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: RTCVideoView(call.localRenderer, mirror: true),
                    ),
                  ),
                // Панель управления с подписями
                Container(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 20),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _btn(
                        icon: Icons.phone_in_talk_rounded,
                        label: 'Динамик',
                        active: speaker,
                        onTap: () async {
                          // Состояние берём у сервиса, иначе экран и
                          // сам звонок решали по разным копиям флага и
                          // кнопка показывала не то, что реально включено.
                          await call.toggleSpeaker();
                          if (mounted) setState(() => speaker = call.speakerOn);
                        },
                      ),
                      _btn(
                        icon: cameraOff
                            ? Icons.videocam_off_rounded
                            : Icons.videocam_rounded,
                        label: 'Видео',
                        active: cameraOff,
                        onTap: () {
                          setState(() => cameraOff = !cameraOff);
                          call.toggleCamera(!cameraOff);
                        },
                      ),
                      _endBtn(),
                      _btn(
                        icon: muted
                            ? Icons.mic_off_rounded
                            : Icons.mic_rounded,
                        label: 'Звук',
                        active: muted,
                        onTap: () {
                          setState(() => muted = !muted);
                          call.toggleMute(muted);
                        },
                      ),
                      _btn(
                        icon: Icons.screen_share_rounded,
                        label: 'Экран',
                        active: false,
                        onTap: () => _showHint('Демонстрация экрана пока недоступна'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showHint(String text) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(text)));
  }

  /// Круглая кнопка с подписью под ней.
  Widget _btn({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool active = false,
  }) {
    return SizedBox(
      width: 68,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Material(
            color: active ? Colors.white : Colors.white24,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: onTap,
              child: SizedBox(
                width: 54,
                height: 54,
                child: Icon(
                  icon,
                  color: active ? const Color(0xFF212121) : Colors.white,
                  size: 23,
                ),
              ),
            ),
          ),
          const SizedBox(height: 7),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }

  /// Красная кнопка завершения с подписью.
  Widget _endBtn() {
    return SizedBox(
      width: 68,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Material(
            color: LuxeColors.danger,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: () async {
                await call.hangup();
                if (mounted) Navigator.pop(context);
              },
              child: const SizedBox(
                width: 54,
                height: 54,
                child: Icon(Icons.call_end_rounded, color: Colors.white, size: 24),
              ),
            ),
          ),
          const SizedBox(height: 7),
          const Text(
            'Завершить',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white70, fontSize: 11),
          ),
        ],
      ),
    );
  }
}