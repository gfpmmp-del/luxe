import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'config/supabase_config.dart';
import 'screens/auth_screen.dart';import 'screens/home_screen.dart';
import 'services/net.dart';
import 'theme/luxe_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // runApp сразу: показываем экран подключения, а не белый фон.
  // Раньше инициализация шла до runApp, и на закрытой сети приложение
  // выглядело как зависшее.
  runApp(const LuxeApp());
}

final supabase = Supabase.instance.client;

class LuxeApp extends StatefulWidget {
  const LuxeApp({super.key});

  @override
  State<LuxeApp> createState() => _LuxeAppState();
}

class _LuxeAppState extends State<LuxeApp> {
  bool _ready = false;
  bool _checking = true;
  bool _offline = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _connect();
  }

  /// Подключиться к серверу с повторами.
  ///
  /// Часть сетей (особенно мобильный интернет без VPN) режет или душит
  /// домен *.supabase.co. Один неудачный запрос — и приложение лежит
  /// навсегда. Поэтому пробуем несколько раз и показываем, что делать.
  Future<void> _connect() async {
    setState(() {
      _checking = true;
      _error = null;
    });

    // Пробуем оба адреса и берём тот, что отвечает в этой сети.
    // Где-то режут прямой адрес Supabase, где-то душат Cloudflare —
    // приложение не должно гадать, оно просто находит рабочий путь.
    var picked = await Net.pickUrl();
    if (picked == null) {
      for (var i = 0; i < 2 && picked == null; i++) {
        await Future.delayed(Duration(milliseconds: 700 * (i + 1)));
        picked = await Net.pickUrl();
      }
    }

    if (picked == null) {
      if (!mounted) return;
      setState(() {
        _checking = false;
        _error = 'Не удаётся связаться с сервером.\n\n'
            'Сеть блокирует доступ или сильно его ограничивает. '
            'Попробуйте мобильный интернет или другую сеть.';
      });
      return;
    }
    SupabaseConfig.picked = picked;
    debugPrint('Рабочий адрес сервера: $picked');

    try {
      await Supabase.initialize(
        url: picked,
        publishableKey: SupabaseConfig.anonKey,
        // Клиент с таймаутами: запрос не должен висеть минутами.
        httpClient: Net.buildClient(),
      ).timeout(const Duration(seconds: 15));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _checking = false;
        _error = 'Сервер ответил, но данные не загрузились:\n'
            '${Net.humanError(e)}';
      });
      return;
    }

    if (!mounted) return;
    setState(() {
      _checking = false;
      _ready = true;
      _offline = picked == SupabaseConfig.workerUrl
          ? false
          : false; // адрес уже проверен, офлайн-полоса не нужна
    });
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: LuxeTheme.mode,
      builder: (context, mode, _) {
        return MaterialApp(
          title: 'Luxe Messenger',
          debugShowCheckedModeBanner: false,
          theme: LuxeTheme.light(),
          darkTheme: LuxeTheme.dark(),
          themeMode: mode,
          home: !_ready
              ? _ConnectScreen(
                  checking: _checking,
                  error: _error,
                  onRetry: _connect,
                )
              : Column(
                  children: [
                    // Полоса появляется, когда сервер недоступен, но
                    // приложение пустило внутрь: видно, что сообщения
                    // не придут, и не надо гадать, почему.
                    if (_offline) const _OfflineBar(),
                    Expanded(
                      child: StreamBuilder<AuthState>(
                        stream: supabase.auth.onAuthStateChange,
                        builder: (context, snapshot) {
                          final session = supabase.auth.currentSession;
                          if (session == null) return const AuthScreen();
                          return const HomeScreen();
                        },
                      ),
                    ),
                  ],
                ),
        );
      },
    );
  }
}

/// Тонкая полоса «нет связи» поверх приложения.
class _OfflineBar extends StatefulWidget {
  const _OfflineBar();

  @override
  State<_OfflineBar> createState() => _OfflineBarState();
}

class _OfflineBarState extends State<_OfflineBar> {
  bool _online = false;
  int _tries = 0;

  @override
  void initState() {
    super.initState();
    _check();
  }

  /// Проверяем связь, пока полоса видима. Как только сеть вернулась —
  /// убираем её сами, не дожидаясь перезапуска.
  Future<void> _check() async {
    while (mounted && !_online) {
      await Future.delayed(const Duration(seconds: 5));
      if (!mounted) return;
      _tries++;
      final ok = await Net.probeBase(SupabaseConfig.url);
      if (!mounted) return;
      if (ok) {
        setState(() => _online = true);
        return;
      }
      if (mounted) setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: LuxeColors.danger.withValues(alpha: 0.92),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          child: Row(
            children: [
              const Icon(Icons.wifi_off_rounded,
                  color: Colors.white, size: 15),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Нет связи с сервером',
                  style: TextStyle(color: Colors.white, fontSize: 12.5),
                ),
              ),
              Text(
                'проверка $_tries',
                style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.75), fontSize: 11),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Экран подключения: пока ждём — спиннер, если не вышло — внятный
/// текст и кнопка повтора.
class _ConnectScreen extends StatelessWidget {
  final bool checking;
  final String? error;
  final VoidCallback onRetry;

  const _ConnectScreen({
    required this.checking,
    required this.error,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: LuxeTheme.dark().scaffoldBackgroundColor,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Image.asset(
                'assets/logo/luxe_logo.png',
                width: 84,
                height: 84,
                errorBuilder: (_, __, ___) => const Icon(
                  Icons.chat_bubble_rounded,
                  size: 84,
                  color: LuxeColors.tgBlue,
                ),
              ),
              const SizedBox(height: 18),
              const Text(
                'Luxe Messenger',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 24),
              if (checking) ...[
                const SizedBox(
                  width: 26,
                  height: 26,
                  child: CircularProgressIndicator(
                      strokeWidth: 2.4, color: LuxeColors.tgBlue),
                ),
                const SizedBox(height: 14),
                const Text(
                  'Подключение...',
                  style: TextStyle(color: Colors.white70, fontSize: 14),
                ),
              ] else if (error != null) ...[
                const Icon(Icons.cloud_off_rounded,
                    color: LuxeColors.danger, size: 40),
                const SizedBox(height: 14),
                Text(
                  error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: Colors.white70, fontSize: 14, height: 1.4),
                ),
                const SizedBox(height: 22),
                FilledButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh_rounded, size: 20),
                  label: const Text('Повторить'),
                  style: FilledButton.styleFrom(
                    backgroundColor: LuxeColors.tgBlue,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 26, vertical: 12),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
