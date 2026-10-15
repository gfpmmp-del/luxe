import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:record/record.dart';

/// Голосовые сообщения: запись с микрофона и воспроизведение.
///
/// Запись и воспроизведение разведены по разным объектам намеренно:
/// в ленте сообщений одновременно могут играть несколько голосовых,
/// но записывать можно только один.
class VoiceService {
  /// Максимальная длительность голосового — как в Telegram, одна минута.
  static const Duration maxLength = Duration(minutes: 1);

  /// Шаг измерения амплитуды. Чаще брать незачем: волна всё равно
  /// ужимается до полосок, а строк в базе становится больше.
  static const Duration _tick = Duration(milliseconds: 80);

  final AudioRecorder _rec = AudioRecorder();

  StreamSubscription<Amplitude>? _ampSub;
  Timer? _timer;
  DateTime? _startedAt;

  Duration _elapsed = Duration.zero;
  List<double> _waveform = [];
  bool _recording = false;

  /// Запись идёт прямо сейчас.
  bool get isRecording => _recording;

  /// Сколько записано.
  Duration get elapsed => _elapsed;

  /// Волна для отрисовки и сохранения в БД.
  List<double> get waveform => List.unmodifiable(_waveform);

  /// Текущая амплитуда 0..1 — для «живого» индикатора при записи.
  double liveLevel = 0;

  /// Начать запись. Повторный вызов игнорируется.
  Future<bool> start({bool video = false}) async {
    if (_recording) return true;
    try {
      if (!await _rec.hasPermission()) return false;

      await _rec.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          sampleRate: 44100,
          numChannels: 1,
          // Битрейт повыше: на тихом голосе стандартный даёт кашу.
          bitRate: 64000,
        ),
        path: '',
      );

      _recording = true;
      _elapsed = Duration.zero;
      _waveform = [];
      liveLevel = 0;
      _startedAt = DateTime.now();

      // Амплитуда идёт чаще, чем таймер: нужен ровный ряд значений,
      // из которого потом выбираются пики для полосок.
      _ampSub = _rec.onAmplitudeChanged(const Duration(milliseconds: 100))
          .listen(_onAmplitude, onError: (Object e) {
        debugPrint('Амплитуда недоступна: $e');
      });

      _timer = Timer.periodic(_tick, (_) {
        if (!_recording) return;
        final d = DateTime.now().difference(_startedAt!);
        _elapsed = d > maxLength ? maxLength : d;
      });

      return true;
    } catch (e) {
      debugPrint('Не удалось начать запись: $e');
      _reset();
      return false;
    }
  }

  void _onAmplitude(Amplitude a) {
    // current — текущий пик, max — пик в окне. max ровнее рисует речь.
    final db = a.max > 0 ? a.max : a.current;
    // -60 дБ — порог тишины. Ниже голоса нет, но волна не должна
    // скакать от наводок.
    final level = (db + 60) / 60;
    liveLevel = level.clamp(0.0, 1.0);
    if (level > 0.02) _waveform.add(level);
  }

  /// Остановить запись и вернуть путь к файлу. null — если нечего слать.
  Future<String?> stop() async {
    if (!_recording) return null;
    _recording = false;
    _timer?.cancel();
    _timer = null;
    await _ampSub?.cancel();
    _ampSub = null;

    String? path;
    try {
      path = await _rec.stop();
    } catch (e) {
      debugPrint('Не удалось остановить запись: $e');
      _reset();
      return null;
    }
    if (path == null || !File(path).existsSync()) {
      _reset();
      return null;
    }
    final length = File(path).lengthSync();
    _reset();
    // Пустой файл не отправляем: это обычное «передумал».
    if (length == 0) return null;
    return path;
  }

  /// Бросить запись, ничего не сохраняя.
  Future<void> cancel() async {
    if (!_recording) return;
    _recording = false;
    _timer?.cancel();
    _timer = null;
    await _ampSub?.cancel();
    _ampSub = null;
    try {
      final p = await _rec.stop();
      if (p != null) {
        final f = File(p);
        if (f.existsSync()) f.deleteSync();
      }
    } catch (_) {}
    _reset();
  }

  void _reset() {
    _elapsed = Duration.zero;
    _waveform = [];
    liveLevel = 0;
    _startedAt = null;
  }

  Future<void> dispose() async {
    await cancel();
    try {
      await _rec.dispose();
    } catch (_) {}
  }

  /// Волна для хранения: 48 значений вместо сотен исходных.
  /// Сжатая строка вместо JSON-массива — колонка text остаётся лёгкой.
  static String packWaveform(List<double> src) {
    const buckets = 48;
    if (src.isEmpty) return '';
    final out = StringBuffer();
    for (var i = 0; i < buckets; i++) {
      final from = (i * src.length / buckets).floor();
      final to = ((i + 1) * src.length / buckets).ceil().clamp(from + 1, src.length);
      var peak = 0.0;
      for (var j = from; j < to && j < src.length; j++) {
        if (src[j] > peak) peak = src[j];
      }
      out.write((peak * 9).round().clamp(0, 9));
    }
    return out.toString();
  }

  /// Разбор сохранённой волны обратно в значения 0..1.
  static List<double> unpackWaveform(String? packed) {
    if (packed == null || packed.isEmpty) return const [];
    return packed.codeUnits
        .map((c) => c.toDouble().clamp(0, 9) / 9)
        .toList(growable: false);
  }
}

/// Воспроизведение голосовых. Один плеер на всё приложение: если
/// пользователь ткнул второе сообщение, первое замолкает само.
class VoicePlayer {
  static final VoicePlayer instance = VoicePlayer._();
  VoicePlayer._();

  final AudioPlayer _player = AudioPlayer();

  String? _currentUrl;

  Stream<Duration> get position => _player.positionStream;
  /// Идёт ли воспроизведение. Отдаём bool, а не PlayerState —
  /// чтобы виджет не зависел от just_audio.
  Stream<bool> get playing => _player.playingStream;
  Duration? get duration => _player.duration;

  bool isPlaying(String url) =>
      _currentUrl == url && _player.playing;

  /// Начать воспроизведение. Повторное нажатие на то же — пауза.
  Future<void> toggle(String url) async {
    if (_currentUrl == url) {
      if (_player.playing) {
        await pause();
      } else {
        await _player.play();
      }
      return;
    }
    await stop();
    try {
      _currentUrl = url;
      await _player.setUrl(url);
      await _player.play();
    } catch (e) {
      debugPrint('Не удалось воспроизвести голосовое: $e');
      _currentUrl = null;
    }
  }

  Future<void> pause() => _player.pause();

  Future<void> stop() async {
    try {
      await _player.stop();
    } catch (_) {}
    _currentUrl = null;
  }

  /// Перемотка по нажатой полоске волны. 0..1 — доля от длительности.
  Future<void> seekFraction(String url, double fraction) async {
    if (_currentUrl != url) return;
    final total = _player.duration;
    if (total == null) return;
    await _player.seek(total * fraction.clamp(0.0, 1.0));
  }
}
