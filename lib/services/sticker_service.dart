import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';

import '../main.dart';
import 'auth_service.dart';
import 'media_service.dart';

/// Стикер в наборе пользователя.
class Sticker {
  final String id;
  final String url;
  final String emoji;
  final String kind; // static | gif | lottie
  const Sticker(this.id, this.url, this.emoji, this.kind);

  bool get isAnimated => kind == 'gif' || kind == 'lottie';
}

/// Наборы стикеров: свои и чужие.
class StickerService {
  /// Стикеры пользователя, новые сверху.
  static Future<List<Sticker>> mine() async {
    final rows = await supabase
        .from('stickers')
        .select('id, url, emoji, kind')
        .eq('owner_id', AuthService.myId)
        .order('created_at', ascending: false);
    return (rows as List)
        .map((e) => Sticker(
              e['id'] as String,
              e['url'] as String,
              (e['emoji'] ?? '') as String,
              (e['kind'] ?? 'static') as String,
            ))
        .toList();
  }

  /// Наборы всех, кроме моего — по одному «последнему» стикеру.
  /// Используется для показа «стикеры от пользователя» в чате.
  static Future<Map<String, List<Sticker>>> others() async {
    final rows = await supabase
        .from('stickers')
        .select('owner_id, url, emoji, kind')
        .order('created_at', ascending: false)
        .limit(300);
    final out = <String, List<Sticker>>{};
    for (final r in (rows as List).cast<Map<String, dynamic>>()) {
      final owner = r['owner_id'] as String;
      if (owner == AuthService.myId) continue;
      final list = out.putIfAbsent(owner, () => <Sticker>[]);
      // По одному набору на автора достаточно для показа в чате.
      if (list.length < 30) {
        list.add(Sticker(
          '', r['url'] as String, (r['emoji'] ?? '') as String,
          (r['kind'] ?? 'static') as String,
        ));
      }
    }
    return out;
  }

  /// Добавить стикер в свой набор.
  static Future<bool> add({
    required String emoji,
    required String kind,
    required String url,
  }) async {
    try {
      await supabase.from('stickers').insert({
        'owner_id': AuthService.myId,
        'emoji': emoji,
        'url': url,
        'kind': kind,
      });
      return true;
    } catch (e) {
      debugPrint('Стикер не добавился: $e');
      return false;
    }
  }

  static Future<void> remove(String id) async {
    try {
      await supabase.from('stickers').delete().eq('id', id);
    } catch (e) {
      debugPrint('Стикер не удалился: $e');
    }
  }

  static Future<void> rename(String id, String emoji) async {
    try {
      await supabase
          .from('stickers')
          .update({'emoji': emoji})
          .eq('id', id);
    } catch (e) {
      debugPrint('Эмодзи не сохранился: $e');
    }
  }

  /// Отправить стикер в чат.
  static Future<Map<String, dynamic>?> send(String chatId, Sticker s) async {    try {
      final row = await supabase
          .from('messages')
          .insert({
            'chat_id': chatId,
            'sender_id': AuthService.myId,
            'content': s.emoji,
            'type': 'sticker',
            'file_url': s.url,
            'status': 'sent',
          })
          .select()
          .single();
      return Map<String, dynamic>.from(row as Map);
    } catch (e) {
      debugPrint('Стикер не отправился: $e');
      return null;
    }
  }

  /// Открыть системный выбор файла стикера.
  static Future<PlatformFile?> pickStickerSource() =>
      MediaService.pickStickerFile();

  /// Тип стикера по имени файла.
  static String kindOf(String name) => MediaService.stickerKind(name);

  /// Загрузить файл и положить стикер в свой набор.
  static Future<bool> createSticker({
    required PlatformFile file,
    required String kind,
    required String emoji,
  }) async {
    try {
      final url = await MediaService.uploadSticker(
          XFile(file.path!, name: file.name), kind);
      return await add(emoji: emoji, kind: kind, url: url);
    } catch (e) {
      debugPrint('Стикер не сохранился: $e');
      return false;
    }
  }

  /// Превью набора по одной строке — для аватара и подписи набора.
  static String? coverOf(List<Sticker> list) =>
      list.isEmpty ? null : list.first.url;
}
