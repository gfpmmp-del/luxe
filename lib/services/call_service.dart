import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../main.dart';
import 'auth_service.dart';

/// WebRTC звонки 1-на-1. Сигналинг — таблица call_signals через Supabase Realtime.
class CallService {
  static const int _callTimeoutSeconds = 30;
  RTCPeerConnection? pc;
  MediaStream? localStream;
  final RTCVideoRenderer localRenderer = RTCVideoRenderer();
  final RTCVideoRenderer remoteRenderer = RTCVideoRenderer();

  String? _calleeId;
  String? _chatId;
  bool videoCall = true;
  RealtimeChannel? _channel;
  final List<Map<String, dynamic>> _pendingIce = [];

  final void Function()? onRemoteStream;
  final void Function(String type)? onSignal;
  final void Function(String)? onError;
  final void Function()? onCallEnded;

  Timer? _callTimer;
  bool _callEnded = false;

  CallService({this.onRemoteStream, this.onSignal, this.onError, this.onCallEnded});

  final Map<String, dynamic> _rtcConfig = {
    'iceServers': [
      {'urls': 'stun:stun.l.google.com:19302'},
      {'urls': 'stun:stun1.l.google.com:19302'},
    ]
  };

  Future<void> initRenderers() async {
    await localRenderer.initialize();
    await remoteRenderer.initialize();
  }

  void dispose() {
    _callEnded = true;
    _stopCallTimer();
    _channel?.unsubscribe();
    _channel = null;
    localStream?.getTracks().forEach((t) => t.stop());
    localStream?.dispose();
    localStream = null;
    pc?.close();
    pc = null;
    localRenderer.dispose();
    remoteRenderer.dispose();
  }

  Future<void> _ensurePeerConnection() async {
    if (pc != null) return;
    pc = await createPeerConnection(_rtcConfig);
    pc!.onTrack = (event) {
      if (event.streams.isNotEmpty) {
        remoteRenderer.srcObject = event.streams[0];
        onRemoteStream?.call();
      }
    };
    pc!.onIceCandidate = (candidate) async {
      if (_calleeId == null || _callEnded) return;
      await supabase.from('call_signals').insert({
        'caller_id': AuthService.myId,
        'callee_id': _calleeId,
        'chat_id': _chatId,
        'type': 'ice',
        'payload': {
          'candidate': candidate.candidate,
          'sdpMid': candidate.sdpMid,
          'sdpMLineIndex': candidate.sdpMLineIndex,
        },
      });
    };
    pc!.onIceConnectionState = (state) {
      if (_callEnded) return;
      switch (state) {
        case RTCIceConnectionState.RTCIceConnectionStateConnected:
        case RTCIceConnectionState.RTCIceConnectionStateCompleted:
          _stopCallTimer();
          break;
        case RTCIceConnectionState.RTCIceConnectionStateFailed:
          // Только failed означает реальный обрыв.
          // disconnected — это временное состояние (сеть моргнула, сеть
          // переключилась с Wi-Fi на LTE): убивать по нему звонок нельзя,
          // WebRTC сам восстановит соединение.
          if (!_callEnded) {
            _endCall(reason: 'Не удалось соединиться');
          }
          break;
        default:
          break;
      }
    };
    pc!.onConnectionState = (state) {
      if (_callEnded) return;
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
        _endCall(reason: 'Не удалось соединиться');
      }
    };
    if (localStream != null) {
      for (final track in localStream!.getTracks()) {
        await pc!.addTrack(track, localStream!);
      }
    }
  }

  void _startCallTimer() {
    _callTimer?.cancel();
    _callTimer = Timer(Duration(seconds: _callTimeoutSeconds), () {
      if (!_callEnded) {
        _endCall(reason: 'Таймаут соединения');
      }
    });
  }

  void _stopCallTimer() {
    _callTimer?.cancel();
    _callTimer = null;
  }

  void _endCall({String? reason}) {
    if (_callEnded) return;
    _callEnded = true;
    _stopCallTimer();
    if (reason != null) {
      onError?.call(reason);
    }
    onCallEnded?.call();
    hangup();
  }

  Future<void> _openMic({required bool video}) async {
    videoCall = video;
    localStream = await navigator.mediaDevices.getUserMedia({
      'audio': true,
      'video': video ? {'facingMode': 'user'} : false,
    });
    localRenderer.srcObject = localStream;
  }

  /// Исходящий звонок
  Future<void> startCall({
    required String calleeId,
    required String chatId,
    required bool video,
  }) async {
    _calleeId = calleeId;
    _chatId = chatId;
    _callEnded = false;
    try {
      await _openMic(video: video);
      await _ensurePeerConnection();
      _listenSignals(chatId);
      _startCallTimer();
      final offer = await pc!.createOffer(video ? {} : {'offerToReceiveVideo': false});
      await pc!.setLocalDescription(offer);
      await supabase.from('call_signals').insert({
        'caller_id': AuthService.myId,
        'callee_id': calleeId,
        'chat_id': chatId,
        'type': 'offer',
        'payload': {'sdp': offer.sdp, 'type': offer.type, 'video': video},
      });
    } catch (e) {
      _endCall(reason: 'Ошибка запуска звонка: $e');
      rethrow;
    }
  }

  /// Входящий: принять offer
  Future<void> answerCall(Map<String, dynamic> offerRow) async {
    _calleeId = offerRow['caller_id'] as String;
    _chatId = offerRow['chat_id'] as String;
    _callEnded = false;
    final payload = Map<String, dynamic>.from(offerRow['payload'] as Map);
    try {
      await _openMic(video: payload['video'] == true);
      await _ensurePeerConnection();
      _listenSignals(_chatId!);
      _startCallTimer();
      await pc!.setRemoteDescription(
        RTCSessionDescription(payload['sdp'] as String, payload['type'] as String),
      );

      // Кандидаты звонящего могли уйти в БД ДО того, как мы подписались
      // на Realtime — тогда они потерялись навсегда и P2P не соединялся.
      // Поэтому забираем из таблицы всё, что накопилось до подписки.
      await _applyStoredCandidates();

      for (final ice in _pendingIce) {
        await _addCandidateFromMap(ice);
      }
      _pendingIce.clear();
      final answer = await pc!.createAnswer();
      await pc!.setLocalDescription(answer);
      await supabase.from('call_signals').insert({
        'caller_id': AuthService.myId,
        'callee_id': _calleeId,
        'chat_id': _chatId,
        'type': 'answer',
        'payload': {'sdp': answer.sdp, 'type': answer.type},
      });
    } catch (e) {
      _endCall(reason: 'Ошибка принятия звонка: $e');
      rethrow;
    }
  }

  /// Забрать ICE-кандидаты звонящего, отправленные до нашей подписки.
  Future<void> _applyStoredCandidates() async {
    try {
      final rows = await supabase
          .from('call_signals')
          .select('payload')
          .eq('chat_id', _chatId!)
          .eq('type', 'ice')
          .eq('caller_id', _calleeId!)
          .order('created_at', ascending: true);
      for (final r in (rows as List)) {
        final p = (r as Map)['payload'];
        if (p is Map) await _addCandidateFromMap(Map<String, dynamic>.from(p));
      }
    } catch (e) {
      debugPrint('Не удалось получить сохранённые кандидаты: $e');
    }
  }

  /// Безопасное добавление кандидата: типы из JSON не всегда int.
  Future<void> _addCandidateFromMap(Map<String, dynamic> m) async {
    if (pc == null) return;
    final idx = m['sdpMLineIndex'];
    await pc!.addCandidate(RTCIceCandidate(
      m['candidate'] as String?,
      m['sdpMid'] as String?,
      idx is int ? idx : (idx is num ? idx.toInt() : null),
    ));
  }

  void _listenSignals(String chatId) {
    _channel?.unsubscribe();
    _channel = supabase.channel('call:$chatId');
    _channel!
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'call_signals',
          callback: (payload) async {
            final row = payload.newRecord;
            if (row['chat_id'] != chatId) return;
            final toMe = row['callee_id'] == AuthService.myId ||
                row['caller_id'] == AuthService.myId;
            if (!toMe) return;
            await _handleSignal(row);
          },
        )
        .subscribe();
  }

  /// Слушать входящие звонки глобально (для экрана Home)
  static RealtimeChannel listenIncoming(
    void Function(Map<String, dynamic> offer) onOffer,
  ) {
    final ch = supabase.channel('incoming:${AuthService.myId}');
    ch
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'call_signals',
          callback: (payload) {
            final row = payload.newRecord;
            if (row['callee_id'] == AuthService.myId && row['type'] == 'offer') {
              onOffer(row);
            }
          },
        )
        .subscribe();
    return ch;
  }

  Future<void> _handleSignal(Map<String, dynamic> row) async {
    if (_callEnded) return;
    
    final type = row['type'] as String;
    final payload = Map<String, dynamic>.from(row['payload'] as Map? ?? {});
    onSignal?.call(type);
    switch (type) {
      case 'answer':
        if (pc != null) {
          await pc!.setRemoteDescription(RTCSessionDescription(
            payload['sdp'] as String,
            payload['type'] as String,
          ));
          for (final ice in _pendingIce) {
            await pc!.addCandidate(RTCIceCandidate(
              ice['candidate'] as String?,
              ice['sdpMid'] as String?,
              ice['sdpMLineIndex'] as int?,
            ));
          }
          _pendingIce.clear();
        }
        break;
      case 'ice':
        final cand = RTCIceCandidate(
          payload['candidate'] as String?,
          payload['sdpMid'] as String?,
          payload['sdpMLineIndex'] as int?,
        );
        if (pc == null || (await pc!.getRemoteDescription()) == null) {
          _pendingIce.add(payload);
        } else {
          await pc!.addCandidate(cand);
        }
        break;
      case 'hangup':
      case 'reject':
        _endCall(reason: type == 'reject' ? 'Звонок отклонён' : 'Собеседник повесил трубку');
        break;
    }
  }

  Future<void> hangup() async {
    _callEnded = true;
    _stopCallTimer();
    if (_calleeId != null && _chatId != null) {
      try {
        await supabase.from('call_signals').insert({
          'caller_id': AuthService.myId,
          'callee_id': _calleeId,
          'chat_id': _chatId,
          'type': 'hangup',
          'payload': {},
        });
      } catch (_) {}
    }
    _channel?.unsubscribe();
    _channel = null;
    localStream?.getTracks().forEach((t) => t.stop());
    localStream?.dispose();
    localStream = null;
    await pc?.close();
    pc = null;
  }

  void toggleMute(bool muted) {
    localStream?.getAudioTracks().forEach((t) => t.enabled = !muted);
  }

  void toggleCamera(bool enabled) {
    localStream?.getVideoTracks().forEach((t) => t.enabled = enabled);
  }

  Future<void> switchCamera() async {
    if (localStream == null) return;
    final videoTracks = localStream!.getVideoTracks();
    if (videoTracks.isEmpty) return;
    
    // Use the flutter_webrtc native method to switch camera
    try {
      final oldTrack = videoTracks.first;
      final newStream = await navigator.mediaDevices.getUserMedia({
        'audio': false,
        'video': {'facingMode': oldTrack.getSettings()['facingMode'] == 'user' ? 'environment' : 'user'},
      });
      final newTrack = newStream.getVideoTracks().first;
      
      if (pc != null) {
        final senders = await pc!.getSenders();
        final videoSenders = senders.where((s) => s.track?.kind == 'video').toList();
        if (videoSenders.isNotEmpty) {
          await videoSenders.first.replaceTrack(newTrack);
        }
      }
      
      oldTrack.stop();
      localStream!.removeTrack(oldTrack);
      localStream!.addTrack(newTrack);
      localRenderer.srcObject = localStream;
    } catch (e) {
      // Fallback: just toggle camera
      toggleCamera(false);
      await Future.delayed(const Duration(milliseconds: 100));
      toggleCamera(true);
    }
  }
}
