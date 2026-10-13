import 'package:flutter/material.dart';
import '../services/auth_service.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});
  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  bool isLogin = true;
  final email = TextEditingController();
  final password = TextEditingController();
  final username = TextEditingController();
  final displayName = TextEditingController();
  String? error;
  bool loading = false;

  Future<void> submit() async {
    setState(() { loading = true; error = null; });
    String? err;
    if (isLogin) {
      err = await AuthService.signIn(email: email.text, password: password.text);
    } else {
      if (username.text.trim().length < 3) {
        err = 'Имя пользователя — минимум 3 символа (латиницей)';
      } else {
        err = await AuthService.signUp(
          email: email.text,
          password: password.text,
          username: username.text,
          displayName: displayName.text.isEmpty ? username.text : displayName.text,
        );
      }
    }
    setState(() { loading = false; error = err; });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF17212B),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 380),
            child: Column(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: Image.asset(
                    'assets/logo/luxe_logo.png',
                    width: 88,
                    height: 88,
                    fit: BoxFit.cover,
                  ),
                ),
                const SizedBox(height: 14),
                const Text('Luxe Messenger',
                    style: TextStyle(
                        fontSize: 26, color: Colors.white, fontWeight: FontWeight.bold)),
                const Text('Быстрый мессенджер', style: TextStyle(color: Colors.white54)),
                const SizedBox(height: 24),
                _field(email, 'Эл. почта', false),
                const SizedBox(height: 12),
                _field(password, 'Пароль', true),
                if (!isLogin) ...[
                  const SizedBox(height: 12),
                  _field(username, 'Имя пользователя (для поиска)', false),
                  const SizedBox(height: 12),
                  _field(displayName, 'Отображаемое имя', false),
                ],
                if (error != null) ...[
                  const SizedBox(height: 12),
                  Text(error!, style: const TextStyle(color: Colors.redAccent)),
                ],
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: loading ? null : submit,
                    child: Text(loading ? '...' : (isLogin ? 'Войти' : 'Создать аккаунт')),
                  ),
                ),
                TextButton(
                  onPressed: () => setState(() => isLogin = !isLogin),
                  child: Text(isLogin ? 'Нет аккаунта? Регистрация' : 'Есть аккаунт? Войти',
                      style: const TextStyle(color: Color(0xFF6AB2E7))),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _field(TextEditingController c, String hint, bool obscure) {
    return TextField(
      controller: c,
      obscureText: obscure,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: Colors.white38),
        filled: true,
        fillColor: const Color(0xFF242F3D),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
      ),
    );
  }
}
