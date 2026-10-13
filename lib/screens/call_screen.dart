import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../services/call_service.dart';

class CallScreen extends StatefulWidget {
  final String chatId;
  final String calleeId; // пусто если входящий
  final bool video;
  final Map<String, dynamic>? incomingOffer;
  const CallScreen({super.key, required this.chatId, required this.calleeId, this.video = true, this.incomingOffer});

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  late CallService call;
  bool muted = false;
  bool cameraOff = false;
  String status = 'Соединение...';

  @override
  void initState() {
    super.initState();
    call = CallService(
      onRemoteStream: () => setState(() => status = 'В эфире'),
      onSignal: (t) {
        if (t == 'hangup' || t == 'reject') {
          if (mounted) Navigator.pop(context);
        }
      },
      onError: (error) {
        if (mounted) {
          setState(() => status = 'Ошибка: $error');
          Future.delayed(const Duration(seconds: 2), () {
            if (mounted) Navigator.pop(context);
          });
        }
      },
      onCallEnded: () {
        if (mounted) {
          Navigator.pop(context);
        }
      },
    );
    _start();
  }

  Future<void> _start() async {
    await call.initRenderers();
    setState(() {});
    try {
      if (widget.incomingOffer != null) {
        setState(() => status = 'Принимаем...');
        await call.answerCall(widget.incomingOffer!);
      } else {
        setState(() => status = 'Вызов...');
        await call.startCall(calleeId: widget.calleeId, chatId: widget.chatId, video: widget.video);
      }
      setState(() => status = 'В эфире');
    } catch (e) {
      setState(() => status = 'Ошибка: $e');
    }
  }

  @override
  void dispose() {
    call.hangup();
    call.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isVideo = widget.incomingOffer != null
        ? (widget.incomingOffer!['payload']?['video'] == true)
        : widget.video;
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            // Удаленное видео
            if (isVideo)
              RTCVideoView(call.remoteRenderer, objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover)
            else
              const Center(child: Icon(Icons.account_circle, size: 120, color: Colors.white24)),
            // Локальное видео
            if (isVideo)
              Positioned(
                top: 16, right: 16, width: 110, height: 150,
                child: Container(
                  decoration: BoxDecoration(border: Border.all(color: Colors.white30), borderRadius: BorderRadius.circular(8)),
                  child: RTCVideoView(call.localRenderer, mirror: true),
                ),
              ),
            Positioned(
              top: 16, left: 16,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(16)),
                child: Text(status, style: const TextStyle(color: Colors.white)),
              ),
            ),
            Positioned(
              bottom: 32, left: 0, right: 0,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _btn(muted ? Icons.mic_off : Icons.mic, () {
                    setState(() => muted = !muted);
                    call.toggleMute(muted);
                  }),
                  _btn(Icons.call_end, () async {
                    await call.hangup();
                    if (mounted) Navigator.pop(context);
                  }, red: true),
                  if (isVideo) _btn(cameraOff ? Icons.videocam_off : Icons.videocam, () {
                    setState(() => cameraOff = !cameraOff);
                    call.toggleCamera(!cameraOff);
                  }),
                  if (isVideo) _btn(Icons.switch_camera, () => call.switchCamera()),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _btn(IconData icon, VoidCallback onTap, {bool red = false}) {
    return CircleAvatar(
      radius: 26,
      backgroundColor: red ? Colors.red : Colors.white24,
      child: IconButton(icon: Icon(icon, color: Colors.white), onPressed: onTap),
    );
  }
}
