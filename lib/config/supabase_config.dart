/// Адреса сервера.
///
/// По умолчанию приложение ходит через Cloudflare Worker, потому что
/// часть мобильных сетей (LTE некоторых операторов, отдельные Wi-Fi)
/// режет домен *.supabase.co — без VPN приложение не грузится. Worker
/// пересылает запросы в Supabase, и заблокированный домен в цепочке
/// не появляется.
///
/// Прямой адрес остаётся запасным вариантом. Включить его при сборке:
///
/// ```
/// flutter build apk --release --dart-define=SUPABASE_URL=https://jdjgrczsnhroqjasipai.supabase.co
/// ```
///
/// Код Worker: cloudflare/worker.js, инструкция: cloudflare/README.md
class SupabaseConfig {
  /// Прокси. Основной адрес.
  static const String workerUrl = 'https://luxe-proxy.gfpmmp.workers.dev';

  /// Напрямую в Supabase. Работает не везде, оставлен как запасной путь.
  static const String directUrl =
      'https://jdjgrczsnhroqjasipai.supabase.co';

  /// Переопределение при сборке. Пусто — берётся workerUrl.
  static const String _override = String.fromEnvironment('SUPABASE_URL');

  static String get url => _override.isNotEmpty ? _override : workerUrl;

  /// Идём через прокси? От этого зависит текст ошибок в приложении.
  static bool get viaProxy => url == workerUrl;

  static const String anonKey = 'sb_publishable_AC4IUfDWKTpiqDForg49ig_KrJ2ZbAp';
}
