import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import '../main.dart';
import 'auth_service.dart';
import 'media_service.dart';

/// Всё нужное для списка чатов, собранное фиксированным числом запросов.
class ChatListData {
  final List<Map<String, dynamic>> chats;
  final Map<String, List<String>> membersByChat;
  final Map<String, Map<String, dynamic>> profiles;
  const ChatListData(this.chats, this.membersByChat, this.profiles);
}

class ChatService {
  /// Мои чаты с последним сообщением
  static Future<List<Map<String, dynamic>>> myChats() async {
    final memberRows = await supabase
        .from('chat_members')
        .select('chat_id')
        .eq('user_id', AuthService.myId);
    final chatIds = (memberRows as List).map((e) => e['chat_id']).toList();
    if (chatIds.isEmpty) return [];
    final chats = await supabase
        .from('chats')
        .select()
        .inFilter('id', chatIds)
        .order('created_at', ascending: false);
    return (chats as List).cast<Map<String, dynamic>>();
  }

  /// Данные для списка чатов: четыре запроса независимо от количества
  /// чатов.
  ///
  /// Раньше на каждый личный чат уходило четыре последовательных запроса
  /// (участники, профиль, участники ещё раз, верификация). На пятнадцати
  /// диалогах это шестьдесят запросов подряд, и на слабом телефоне список
  /// грузился минутами либо зависал навсегда.
  static Future<ChatListData> chatListData() async {
    final myId = AuthService.myId;
    final memberRows = await supabase
        .from('chat_members')
        .select('chat_id')
        .eq('user_id', myId);
    final chatIds = (memberRows as List)
        .map((e) => e['chat_id'] as String)
        .toSet()
        .toList();
    if (chatIds.isEmpty) {
      return const ChatListData([], {}, {});
    }

    final chats = await supabase
        .from('chats')
        .select('id, kind, title, avatar_url, is_group, created_at')
        .inFilter('id', chatIds)
        .order('created_at', ascending: false);

    // Все участники моих чатов одним запросом: отсюда же считаем
    // количество участников и находим собеседника в личном чате.
    final membersByChat = <String, List<String>>{};
    final allUserIds = <String>{};
    final memberAll = await supabase
        .from('chat_members')
        .select('chat_id, user_id')
        .inFilter('chat_id', chatIds);
    for (final r in (memberAll as List).cast<Map<String, dynamic>>()) {
      final cid = r['chat_id'] as String;
      final uid = r['user_id'] as String;
      (membersByChat[cid] ??= <String>[]).add(uid);
      allUserIds.add(uid);
    }

    final profiles = await profilesByIds(allUserIds.toList());
    return ChatListData(
        (chats as List).cast<Map<String, dynamic>>(), membersByChat, profiles);
  }

  /// Профили пользователей по списку id. Запросы режутся порциями,
  /// иначе длинный список упирается в лимит длины URL у PostgREST.
  static Future<Map<String, Map<String, dynamic>>> profilesByIds(
      List<String> ids) async {
    final out = <String, Map<String, dynamic>>{};
    if (ids.isEmpty) return out;
    const chunkSize = 100;
    for (var i = 0; i < ids.length; i += chunkSize) {
      final end =
          (i + chunkSize) > ids.length ? ids.length : (i + chunkSize);
      try {
        final rows = await supabase
            .from('profiles')
            .select('id, display_name, username, avatar_url, verified, status')
            .inFilter('id', ids.sublist(i, end));
        for (final r in (rows as List).cast<Map<String, dynamic>>()) {
          out[r['id'] as String] = r;
        }
      } catch (e) {
        debugPrint('Профили не загрузились: $e');
      }
    }
    return out;
  }

  /// Тип чата: direct | group | channel (старые строки без kind — по is_group)
  static String chatKind(Map<String, dynamic> chat) {
    final kind = chat['kind'] as String?;
    if (kind != null && kind.isNotEmpty) return kind;
    return chat['is_group'] == true ? 'group' : 'direct';
  }

  /// Название + аватарка для списка чатов.
  static Future<Map<String, String?>> chatDisplay(
      Map<String, dynamic> chat) async {
    final kind = chatKind(chat);
    if (kind == 'direct') {
      final members = await supabase
          .from('chat_members')
          .select('user_id')
          .eq('chat_id', chat['id']);
      final otherId = (members as List)
          .map((e) => e['user_id'])
          .firstWhere((id) => id != AuthService.myId, orElse: () => null);
      if (otherId == null) {
        return {'title': 'Избранное', 'avatar': null, 'kind': kind};
      }
      final profile = await supabase
          .from('profiles')
          .select('display_name, username, avatar_url')
          .eq('id', otherId)
          .maybeSingle();
      final p = profile == null ? null : Map<String, dynamic>.from(profile as Map);
      return {
        'title': (p?['display_name'] ?? p?['username'] ?? 'Чат') as String?,
        'avatar': p?['avatar_url'] as String?,
        'kind': kind,
      };
    }
    return {
      'title': ((chat['title'] ?? (kind == 'channel' ? 'Канал' : 'Группа')))
          as String?,
      'avatar': chat['avatar_url'] as String?,
      'kind': kind,
    };
  }

  /// Название чата для отображения (для лички — имя собеседника)
  static Future<String> chatTitle(Map<String, dynamic> chat) async {
    return (await chatDisplay(chat))['title'] ?? 'Чат';
  }

  static Future<String> otherUserId(String chatId) async {
    final members = await supabase
        .from('chat_members')
        .select('user_id')
        .eq('chat_id', chatId);
    return (members as List)
        .map((e) => e['user_id'] as String)
        .firstWhere((id) => id != AuthService.myId, orElse: () => '');
  }

  static Future<List<Map<String, dynamic>>> messages(String chatId) async {
    final rows = await supabase
        .from('messages')
        .select()
        .eq('chat_id', chatId)
        .order('created_at', ascending: true)
        .limit(200);
    return (rows as List).cast<Map<String, dynamic>>();
  }

  /// Отправить текст. Возвращает вставленную строку или null.
  static Future<Map<String, dynamic>?> sendText(String chatId, String text) async {
    if (text.trim().isEmpty) return null;
    final row = await supabase
        .from('messages')
        .insert({
          'chat_id': chatId,
          'sender_id': AuthService.myId,
          'content': text.trim(),
          'type': 'text',
          'status': 'sent',
        })
        .select()
        .single();
    return Map<String, dynamic>.from(row as Map);
  }

  /// Удаление сообщения
  static Future<void> deleteMessage(String messageId) async {
    await supabase.from('messages').delete().eq('id', messageId);
  }

  /// Отправить файл. Возвращает вставленную строку или null.
  ///
  /// [type]: 'image' | 'video' | 'file' — определяет вид вложения в чате.
  ///
  /// Важно: колонки file_name/file_size могут отсутствовать в БД, поэтому
  /// они не входят в INSERT — иначе отправка падает целиком. Дописываем
  /// их отдельным UPDATE, ошибку которого игнорируем.
  static Future<Map<String, dynamic>?> sendFile(
      String chatId, String fileUrl, String fileName,
      {String type = 'file', String caption = ''}) async {
    final row = await supabase
        .from('messages')
        .insert({
          'chat_id': chatId,
          'sender_id': AuthService.myId,
          'content': caption.trim().isEmpty ? fileName : caption.trim(),
          'type': type,
          'file_url': fileUrl,
          'status': 'sent',
        })
        .select()
        .single();
    final saved = Map<String, dynamic>.from(row as Map);

    try {
      await supabase
          .from('messages')
          .update({'file_name': fileName, 'file_size': 0})
          .eq('id', saved['id']);
    } catch (_) {
      // Колонки не добавлены — работаем без них, имя берём из content
    }
    saved['file_name'] = fileName;
    saved['file_size'] = 0;
    return saved;
  }

  /// Голосовое сообщение.
  ///
  /// Колонки duration/waveform могут отсутствовать в БД (миграция не
  /// применена), поэтому они пишутся отдельным UPDATE — как file_name.
  /// Иначе голосовое вообще не отправилось бы.
  static Future<Map<String, dynamic>?> sendVoice(
    String chatId,
    String url,
    int durationSeconds,
    String waveform,
  ) async {
    final row = await supabase
        .from('messages')
        .insert({
          'chat_id': chatId,
          'sender_id': AuthService.myId,
          'content': 'Голосовое сообщение',
          'type': 'voice',
          'file_url': url,
          'status': 'sent',
        })
        .select()
        .single();
    final saved = Map<String, dynamic>.from(row as Map);
    try {
      await supabase
          .from('messages')
          .update({'duration': durationSeconds, 'waveform': waveform})
          .eq('id', saved['id']);
    } catch (e) {
      debugPrint('Длительность голосового не сохранилась: $e');
    }
    saved['duration'] = durationSeconds;
    saved['waveform'] = waveform;
    return saved;
  }

  /// Видеокружок.
  static Future<Map<String, dynamic>?> sendCircle(
    String chatId,
    String url,
    int durationSeconds, {
    String caption = '',
  }) async {
    final row = await supabase
        .from('messages')
        .insert({
          'chat_id': chatId,
          'sender_id': AuthService.myId,
          'content': caption.trim(),
          'type': 'circle',
          'file_url': url,
          'status': 'sent',
        })
        .select()
        .single();
    final saved = Map<String, dynamic>.from(row as Map);
    try {
      await supabase
          .from('messages')
          .update({'duration': durationSeconds})
          .eq('id', saved['id']);
    } catch (_) {}
    saved['duration'] = durationSeconds;
    return saved;
  }

  /// Найти пользователя по username и создать/вернуть личную переписку
  static Future<String?> openDirectChat(String username) async {
    final profile = await supabase
        .from('profiles')
        .select('id')
        .ilike('username', username.trim().toLowerCase())
        .maybeSingle();
    if (profile == null) return null;
    final otherId = profile['id'] as String;
    if (otherId == AuthService.myId) return null;

    // Ищем существующую личку: чат из 2 участников (группы и каналы пропускаем)
    final existing = await ChatService.myChats();
    for (final c in existing) {
      if (c['is_group'] == true || chatKind(c) != 'direct') continue;
      final members = await supabase
          .from('chat_members')
          .select('user_id')
          .eq('chat_id', c['id']);
      final ids = (members as List).map((e) => e['user_id']).toSet();
      if (ids.length == 2 && ids.contains(otherId)) return c['id'] as String;
    }
    // Создаём новый
    final chat = await supabase
        .from('chats')
        .insert({
          'is_group': false,
          'kind': 'direct',
          'created_by': AuthService.myId
        })
        .select()
        .single();
    await supabase.from('chat_members').insert([
      {'chat_id': chat['id'], 'user_id': AuthService.myId},
      {'chat_id': chat['id'], 'user_id': otherId},
    ]);
    return chat['id'] as String;
  }

  /// Создать группу. Возвращает id чата.
  static Future<String> createGroup({
    required String title,
    required List<String> memberIds,
    XFile? avatar,
  }) async {
    final chat = await supabase
        .from('chats')
        .insert({
          'is_group': true,
          'kind': 'group',
          'title': title.trim(),
          'created_by': AuthService.myId,
        })
        .select()
        .single();
    final id = chat['id'] as String;
    final members = {AuthService.myId, ...memberIds}
        .map((u) => {'chat_id': id, 'user_id': u})
        .toList();
    await supabase.from('chat_members').insert(members);
    if (avatar != null) {
      final url = await MediaService.uploadChatAvatar(id, avatar);
      await supabase.from('chats').update({'avatar_url': url}).eq('id', id);
    }
    return id;
  }

  /// Создать канал. Постят только админы (создатель), остальные читают.
  static Future<String> createChannel({
    required String title,
    required String description,
    required List<String> memberIds,
    XFile? avatar,
  }) async {
    final chat = await supabase
        .from('chats')
        .insert({
          'is_group': true,
          'kind': 'channel',
          'title': title.trim(),
          'description': description.trim(),
          'created_by': AuthService.myId,
        })
        .select()
        .single();
    final id = chat['id'] as String;
    final members = {AuthService.myId, ...memberIds}
        .map((u) => {'chat_id': id, 'user_id': u})
        .toList();
    await supabase.from('chat_members').insert(members);
    if (avatar != null) {
      final url = await MediaService.uploadChatAvatar(id, avatar);
      await supabase.from('chats').update({'avatar_url': url}).eq('id', id);
    }
    return id;
  }

  static Future<int> memberCount(String chatId) async {
    final rows = await supabase
        .from('chat_members')
        .select('user_id')
        .eq('chat_id', chatId);
    return (rows as List).length;
  }

  /// Участники с профилями.
  static Future<List<Map<String, dynamic>>> groupMembers(String chatId) async {
    final rows = await supabase
        .from('chat_members')
        .select('user_id, profiles(display_name, username, avatar_url, status)')
        .eq('chat_id', chatId);
    return (rows as List).map((e) {
      final m = Map<String, dynamic>.from(e as Map);
      final p = m['profiles'] == null
          ? <String, dynamic>{}
          : Map<String, dynamic>.from(m['profiles'] as Map);
      return {
        'user_id': m['user_id'],
        'display_name': p['display_name'] ?? p['username'] ?? '?',
        'username': p['username'] ?? '',
        'avatar_url': p['avatar_url'],
        'status': p['status'] ?? '',
      };
    }).toList();
  }

  static Future<void> addMember(String chatId, String userId) {
    return supabase
        .from('chat_members')
        .insert({'chat_id': chatId, 'user_id': userId});
  }

  static Future<void> removeMember(String chatId, String userId) {
    return supabase
        .from('chat_members')
        .delete()
        .eq('chat_id', chatId)
        .eq('user_id', userId);
  }

  static Future<void> updateChat(String chatId, Map<String, dynamic> fields) {
    return supabase.from('chats').update(fields).eq('id', chatId);
  }

  static Future<void> deleteChat(String chatId) {
    return supabase.from('chats').delete().eq('id', chatId);
  }

  static Future<bool> isSubscribed(String chatId) async {
    final row = await supabase
        .from('chat_members')
        .select('user_id')
        .eq('chat_id', chatId)
        .eq('user_id', AuthService.myId)
        .maybeSingle();
    return row != null;
  }

  /// Пометить сообщения от собеседника как прочитанные
  static Future<void> markAsRead(String chatId) async {
    await supabase.from('messages').update({'status': 'read'})
      .eq('chat_id', chatId)
      .neq('sender_id', AuthService.myId)
      .neq('status', 'read');
  }

  static Future<List<Map<String, dynamic>>> searchUsers(String query) async {
    if (query.trim().isEmpty) return [];
    final rows = await supabase
        .from('profiles')
        .select('id, username, display_name, status, avatar_url, verified')
        .ilike('username', '%${query.trim().toLowerCase()}%')
        .limit(20);
    return ((rows as List).cast<Map<String, dynamic>>())
        .where((u) => u['id'] != AuthService.myId)
        .toList();
  }
}
