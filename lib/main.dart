import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'config/supabase_config.dart';
import 'screens/auth_screen.dart';
import 'screens/home_screen.dart';
import 'theme/luxe_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(
    url: SupabaseConfig.url,
    anonKey: SupabaseConfig.anonKey,
  );
  runApp(const LuxeApp());
}

final supabase = Supabase.instance.client;

class LuxeApp extends StatelessWidget {
  const LuxeApp({super.key});

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
          home: StreamBuilder<AuthState>(
            stream: supabase.auth.onAuthStateChange,
            builder: (context, snapshot) {
              final session = supabase.auth.currentSession;
              if (session == null) return const AuthScreen();
              return const HomeScreen();
            },
          ),
        );
      },
    );
  }
}