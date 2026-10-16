/// Адреса сервера.
///
/// Базовый адрес можно переопределить при сборке:
/// ```
/// flutter build apk --release --dart-define=SUPABASE_URL=https://luxe-proxy.твой-ник.workers.dev
/// ```
/// Это нужно, потому что часть мобильных сетей режет домен
/// *.supabase.co. Тогда перед Supabase ставится Cloudflare Worker
/// (см. cloudflare/worker.js) и клиент ходит на обычный домен.
class SupabaseConfig {
  /// Адрес Supabase напрямую — рабочий вариант на нормальных сетях.
  static const String directUrl =
      'https://jdjgrczsnhroqjasipai.supabase.co';

  /// Прокси. По умолчанию — прямой адрес, пока воркер не настроен.
  /// Впиши сюда адрес своего воркера, чтобы включить его раз и навсегда,
  /// либо передай SUPABASE_URL при сборке.
  static const String _proxyUrl = String.fromEnvironment('SUPABASE_URL');

  static String get url => _proxyUrl.isNotEmpty ? _proxyUrl : directUrl;

  /// Прокси включён? Иначе часть функций можно чинить иначе.
  static bool get viaProxy => _proxyUrl.isNotEmpty;

  static const String anonKey = 'sb_publishable_AC4IUfDWKTpiqDForg49ig_KrJ2ZbAp';
}
