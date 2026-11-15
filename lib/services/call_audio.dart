import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Нативная аудиосессия iOS для звонков.
///
/// flutter_webrtc выставляет категорию `.playAndRecord` и режим
/// `.voiceChat`, но не активирует AVAudioSession: это делает его
/// аудио-модуль, и на iPhone активация иногда не происходит вовсе.
/// Звонок при этом «соединяется» без звука в обе стороны.
///
/// Канал `luxe/call_audio` живёт в `ios/Runner/AppDelegate.swift`.
/// На других платформах все методы — заглушки.
class CallAudio {
  static const MethodChannel _channel = MethodChannel('luxe/call_audio');

  static bool get _ios =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  /// Поднять сессию до захвата микрофона.
  ///
  /// [speaker] — сразу вывести звук на динамик (видеозвонок), иначе
  /// останется разговорный динамик телефона.
  static Future<void> start({required bool speaker}) async {
    if (!_ios) return;
    try {
      await _channel.invokeMethod<void>('start', {'speaker': speaker});
    } catch (e) {
      debugPrint('Аудиосессия iOS не поднялась: $e');
    }
  }

  /// Повторная активация после `getUserMedia`: WebRTC мог пересоздать
  /// сессию, пока поднимал аудио-модуль.
  static Future<void> activate() async {
    if (!_ios) return;
    try {
      await _channel.invokeMethod<void>('activate');
    } catch (e) {
      debugPrint('Аудиосессия iOS не активировалась: $e');
    }
  }

  /// Переключить маршрут: динамик ⇄ разговорный динамик телефона.
  static Future<void> setSpeaker(bool on) async {
    if (!_ios) return;
    try {
      await _channel.invokeMethod<void>('speaker', {'on': on});
    } catch (e) {
      debugPrint('Маршрут звука iOS не переключился: $e');
    }
  }

  /// Отпустить сессию после звонка, чтобы звук вернулся другим
  /// приложениям и рингтону.
  static Future<void> end() async {
    if (!_ios) return;
    try {
      await _channel.invokeMethod<void>('end');
    } catch (e) {
      debugPrint('Аудиосессия iOS не закрылась: $e');
    }
  }
}
