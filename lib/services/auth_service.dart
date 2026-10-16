import 'package:supabase_flutter/supabase_flutter.dart';

import '../main.dart';
import 'net.dart';
import 'push_service.dart';

class AuthService {
  /// Регистрация: создаёт auth.user + профиль
  static Future<String?> signUp({
    required String email,
    required String password,
    required String username,
    required String displayName,
  }) async {
    final res = await supabase.auth.signUp(email: email, password: password);
    final user = res.user;
    if (user == null) return 'Не удалось создать пользователя';
    try {
      await supabase.from('profiles').insert({
        'id': user.id,
        'username': username.trim().toLowerCase(),
        'display_name': displayName.trim(),
        'status': 'online',
      });
    } catch (e) {
      if (e.toString().contains('duplicate') ||
          e.toString().contains('unique')) {
        return 'Такое имя пользователя уже занято';
      }
      return 'Ошибка профиля: $e';
    }
    await PushService.init();
    return null;
  }

  static Future<String?> signIn({
    required String email,
    required String password,
  }) async {
    try {
      // Повторяем: сеть может отпустить со второй попытки.
      await Net.retry(
        () => supabase.auth
            .signInWithPassword(email: email, password: password),
      ).timeout(Net.connectTimeout * 2);
      await supabase.from('profiles').update({
        'status': 'online',
        'last_seen': DateTime.now().toIso8601String(),
      }).eq('id', supabase.auth.currentUser!.id);
      await PushService.init();
    } on AuthException {
      // Сервер ответил — значит дело в учётных данных.
      return 'Неверный логин или пароль';
    } catch (e) {
      // Сюда попадают обрывы сети и таймауты. Раньше здесь тоже
      // отвечали «неверный пароль», и человек зря искал ошибку в
      // пароле вместо того, чтобы проверить интернет.
      return Net.humanError(e);
    }
    return null;
  }

  static Future<void> signOut() async {
    final id = supabase.auth.currentUser?.id;
    if (id != null) {
      await supabase.from('profiles').update({'status': 'offline'}).eq('id', id);
    }
    await supabase.auth.signOut();
  }

  static String get myId => supabase.auth.currentUser!.id;

  static Future<bool> isAdmin() async {
    final row = await supabase.from('profiles').select('is_admin').eq('id', myId).maybeSingle();
    return row?['is_admin'] == true;
  }

  static Future<void> verifyUser(String userId) async {
    if (!await isAdmin()) {
      throw Exception('Выдать галочку может только администратор');
    }
    await supabase.from('profiles').update({'verified': true}).eq('id', userId);
  }

  /// Снять галочку (только для администратора).
  static Future<void> unverifyUser(String userId) async {
    if (!await isAdmin()) {
      throw Exception('Снять галочку может только администратор');
    }
    await supabase.from('profiles').update({'verified': false}).eq('id', userId);
  }

  /// Верифицирован ли пользователь.
  static Future<bool> isVerified(String userId) async {
    try {
      final row = await supabase
          .from('profiles')
          .select('verified')
          .eq('id', userId)
          .maybeSingle();
      return row?['verified'] == true;
    } catch (e) {
      return false;
    }
  }
}
