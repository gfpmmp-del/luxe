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
  final Set<String> _addedIce = <String>{};

  final void Function()? onRemoteStream;
  final void Function(String type)? onSignal;
  final void Function(String)? onError;
  final void Function()? onCallEnded;

  Timer? _callTimer;
  bool _callEnded = false;
  bool _connectedNotified = false;

  /// Сообщить экрану, что звонок состоялся. Только один раз: иначе
  /// таймер в интерфейсе запускался бы повторно и текал в 2 раза быстрее.
  void _markConnected() {
    if (_callEnded || _connectedNotified) return;
    _connectedNotified = true;
    _stopCallTimer();
    onRemoteStream?.call();
  }

  void _resetConnected() {
    _connectedNotified = false;
  }

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
      // Рендерер предназначен только для видео. Раньше ему отдавался
      // первый попавшийся поток, и для аудиозвонка он получал воду,
      // а экран так и оставался в статусе «Вызов...».
      if (event.track.kind == 'video' && event.streams.isNotEmpty) {
        remoteRenderer.srcObject = event.streams.first;
      }
      // Аудио играет системой автоматически, трек только убеждаемся, что он включён
      if (event.track.kind == 'audio') {
        event.track.enabled = true;
        debugPrint('Пришёл звук от собеседника (трек ${event.track.id})');
      }
      _markConnected();
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
      debugPrint('ICE: $state');
      switch (state) {
        case RTCIceConnectionState.RTCIceConnectionStateConnected:
        case RTCIceConnectionState.RTCIceConnectionStateCompleted:
          _stopCallTimer();
          // Соединение по ICE — надёжный признак, что звонок состоялся.
          // Для аудиозвонков onTrack может не сработать вовсе.
          _markConnected();
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

  /// Завершить звонок.
  ///
  /// [notify] — отправлять ли сигнал собеседнику. При сбросе по
  /// инициативе второй стороны сигнал не нужен: он и так знает.
  void _endCall({String? reason, bool notify = true}) {
    if (_callEnded) return;
    _stopCallTimer();
    if (reason != null) {
      onError?.call(reason);
    }
    onCallEnded?.call();
    // Флаг выставит сам hangup(): выставить его заранее нельзя —
    // hangup() решит, что звонок уже завершён, и сигнал о сбое
    // не уйдёт второй стороне.
    hangup(notify: notify);
  }

  Future<void> _openMic({required bool video}) async {
    videoCall = video;
    localStream = await navigator.mediaDevices.getUserMedia({
      'audio': true,
      'video': video ? {'facingMode': 'user'} : false,
    });
    localRenderer.srcObject = localStream;
    // Только теперь аудиотрек существует — до этого момента плагин
    // считает, что записывать нечего, и Voice Processing не включается.
    await _activateVoiceProcessing();
  }

  /// По умолчанию звук идёт в разговорный динамик телефона (режим
  /// inCommunication), громкая связь включается кнопкой.
  bool _speakerOn = false;

  bool get speakerOn => _speakerOn;

  /// Голосовой режим средствами самого flutter_webrtc.
  ///
  /// Раньше здесь использовался пакет audio_session — и это ломало звонки.
  /// У flutter_webrtc собственный аудио-модуль: он сам поднимает сессию
  /// и держит маршрут вывода. Внешний audio_session перебивал его
  /// настройки, из-за чего пропадал звук, а переключение динамика
  /// перекрывалось его собственным состоянием.
  Future<void> _configureCallAudio() async {
    if (kIsWeb) return;
    try {
      if (defaultTargetPlatform == TargetPlatform.android) {
        // inCommunication + voiceCall: без этого Android играет звонок
        // в обычном режиме медиа, собеседника почти не слышно.
        await Helper.setAndroidAudioConfiguration(AndroidAudioConfiguration(
          manageAudioFocus: true,
          androidAudioMode: AndroidAudioMode.inCommunication,
          androidAudioFocusMode: AndroidAudioFocusMode.gain,
          androidAudioStreamType: AndroidAudioStreamType.voiceCall,
          androidAudioAttributesUsageType:
              AndroidAudioAttributesUsageType.voiceCommunication,
          androidAudioAttributesContentType:
              AndroidAudioAttributesContentType.speech,
          // На части телефонов маршрутизация выключается сама —
          // без этого флага динамик не переключается.
          forceHandleAudioRouting: true,
        ));
      } else if (defaultTargetPlatform == TargetPlatform.iOS) {
        // Режим voiceChat включает у Яблока аппаратную обработку
        // голоса (Voice Processing I/O): шумоподавление, эхоподавление
        // и нормализация громкости на уровне железа. Именно она даёт
        // звук как при обычном звонке, а не как в приложении записи.
        await Helper.setAppleAudioConfiguration(AppleAudioConfiguration(
          appleAudioCategory: AppleAudioCategory.playAndRecord,
          appleAudioCategoryOptions: {
            AppleAudioCategoryOption.allowBluetooth,
            AppleAudioCategoryOption.defaultToSpeaker,
          },
          appleAudioMode: AppleAudioMode.voiceChat,
        ));
        // Без этого микрофон отключается системным щелчком, который
        // в мессенджере только раздражает.
        await Helper.setMicrophoneMuteMode(MicrophoneMuteMode.inputMixer);
      }
    } catch (e) {
      // Аудио-настройка не должна ронять звонок
      debugPrint('Голосовой режим не настроен: $e');
    }
  }

  /// Включает аппаратную обработку голоса. Вызывается после
  /// getUserMedia: до появления аудиотрека плагин считает, что
  /// записывать нечего, и Voice Processing остаётся выключенным.
  Future<void> _activateVoiceProcessing() async {
    if (kIsWeb) return;
    try {
      if (defaultTargetPlatform == TargetPlatform.iOS) {
        await Helper.ensureAudioSession();
        // Если обработка обойдена, WebRTC работает «сырым» звуком:
        // слышно эхо и фоновый шум. Возвращаем её обратно.
        if (await NativeAudioManagement.isVoiceProcessingBypassed()) {
          await NativeAudioManagement.setIsVoiceProcessingBypassed(false);
        }
        debugPrint('Аппаратная обработка голоса: '
            '${await NativeAudioManagement.isVoiceProcessingEnabled()}');
      }
    } catch (e) {
      debugPrint('Обработку голоса включить не удалось: $e');
    }
  }

  /// Переключить звук: наушник ⇄ громкая связь.
  ///
  /// Переключение делает нативный код flutter_webrtc: на Android это
  /// включение speakerphone, на iOS — выбор между разговорным динамиком
  /// и ухом. Прежний audio_session тут был бессилен — он лишь просил
  /// систему, а WebRTC её тут же переключал обратно.
  Future<void> toggleSpeaker() async {
    _speakerOn = !_speakerOn;
    if (kIsWeb) return;
    try {
      if (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS) {
        await Helper.setSpeakerphoneOn(_speakerOn);
        debugPrint('Звук: ${_speakerOn ? 'динамик' : 'наушник'}');
      }
    } catch (e) {
      debugPrint('Не удалось переключить звук: $e');
    }
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
    _resetConnected();
    try {
      // Голосовой режим — до захвата микрофона и до создания соединения
      await _configureCallAudio();
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
    _resetConnected();
    final payload = Map<String, dynamic>.from(offerRow['payload'] as Map);
    try {
      await _configureCallAudio();
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
  ///
  /// Ошибка одного кандидата не должна обрывать разбор остальных —
  /// иначе связь просто не поднимется. Повторы отбрасываются: один и тот
  /// же кандидат может прийти и через Realtime, и из таблицы.
  Future<void> _addCandidateFromMap(Map<String, dynamic> m) async {
    if (pc == null) return;
    final idx = m['sdpMLineIndex'];
    final key = '${m['candidate']}|${m['sdpMid']}|$idx';
    if (_addedIce.contains(key)) return;
    _addedIce.add(key);
    try {
      await pc!.addCandidate(RTCIceCandidate(
        m['candidate'] as String?,
        m['sdpMid'] as String?,
        idx is int ? idx : (idx is num ? idx.toInt() : null),
      ));
    } catch (e) {
      debugPrint('Кандидат отброшен: $e');
    }
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
            // Свои сигналы игнорируем. Realtime присылает и вставки,
            // сделанные этим же клиентом: иначе звонящий получал бы свои
            // же ICE-кандидаты, клал в _pendingIce и затем добавлял их
            // как удалённые — соединение не поднималось, звука не было.
            final mine = row['caller_id'] == AuthService.myId &&
                row['callee_id'] != AuthService.myId;
            if (mine) return;
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
    // onSignal больше не закрывает экран: это делает onCallEnded
    // через _endCall. Раньше закрытие срабатывало дважды — двойной
    // Navigator.pop ронял экран звонка.
    onSignal?.call(type);
    switch (type) {
      case 'answer':
        if (pc != null) {
          await pc!.setRemoteDescription(RTCSessionDescription(
            payload['sdp'] as String,
            payload['type'] as String,
          ));
          for (final ice in _pendingIce) {
            await _addCandidateFromMap(ice);
          }
          _pendingIce.clear();
        }
        break;
      case 'ice':
        // Каст as int? на данных из JSON мог уронить весь разбор
        // сигналов — из-за одного поля переставали приходить кандидаты.
        if (pc == null || (await pc!.getRemoteDescription()) == null) {
          _pendingIce.add(payload);
        } else {
          await _addCandidateFromMap(payload);
        }
        break;
      case 'hangup':
      case 'reject':
        // Отвечать сигналом на сигнал не нужно — второй и так ушёл.
        _endCall(
          reason: type == 'reject' ? 'Звонок отклонён' : 'Собеседник повесил трубку',
          notify: false,
        );
        break;
    }
  }

  Future<void> hangup({bool notify = true}) async {
    // Если звонок уже завершён (собеседник повесил трубку, сеть отвалилась),
    // повторно слать сигнал не нужно: dispose() вызывает hangup() ещё раз,
    // и в таблице копились бесполезные строки.
    final alreadyEnded = _callEnded;
    _callEnded = true;
    _stopCallTimer();
    if (!alreadyEnded && notify && _calleeId != null && _chatId != null) {
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

  /// Выключить микрофон.
  ///
  /// Через нативный API, а не только флагом трека: при отключении
  /// одним лишь track.enabled микрофон продолжает работать на аппаратном
  /// уровне, Voice Processing это замечает и подкручивает усиление —
  /// собеседник слышит шум и рычание. Helper.setMicrophoneMute гасит
  /// сам аудио-модуль и только затем снимает флаг трека.
  void toggleMute(bool muted) {
    final tracks = localStream?.getAudioTracks() ?? const [];
    for (final t in tracks) {
      t.enabled = !muted;
      if (!kIsWeb) {
        Helper.setMicrophoneMute(muted, t).catchError((e) {
          debugPrint('Микрофон не отключился: $e');
          return Future<void>.value();
        });
      }
    }
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
