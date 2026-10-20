import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';

/// Звонок входящего вызова: звук и вибрация, пока на экране висит
/// карточка.
///
/// Раньше входящий звонок не звучал вообще — просто появлялась
/// карточка в углу. Если человек в этот момент смотрел в чат, он
/// звонка не замечал, а через полминуты звонящий слышал «не отвечает».
class RingService {
  static final AudioPlayer _player = AudioPlayer();
  static Timer? _vibrate;
  static bool _on = false;

  /// Идёт ли звонок прямо сейчас.
  static bool get isRinging => _on;

  static Future<void> start() async {
    if (_on) return;
    _on = true;

    // Вибрация сразу, не дожидаясь загрузки файла: телефон в кармане
    // должен дать знать о звонке даже если звук почему-то не пошёл.
    _vibrate = Timer.periodic(const Duration(seconds: 2), (_) {
      HapticFeedback.heavyImpact();
    });
    HapticFeedback.heavyImpact();

    try {
      await _player.setAsset('assets/sound/ring.wav');
      await _player.setLoopMode(LoopMode.one);
      await _player.setVolume(1.0);
      await _player.play();
    } catch (e) {
      // Звук не критичен: вибрация уже идёт.
      debugPrint('Звонок не проигрался: $e');
    }
  }

  static Future<void> stop() async {
    if (!_on) return;
    _on = false;
    _vibrate?.cancel();
    _vibrate = null;
    try {
      await _player.stop();
    } catch (_) {
      // Плеер мог быть уже освобождён
    }
  }

  /// Полностью отпустить ресурсы. Вызывать при выходе из аккаунта.
  static Future<void> dispose() async {
    await stop();
    try {
      await _player.dispose();
    } catch (_) {}
  }
}
