import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import '../main.dart';
import '../config/supabase_config.dart';
import '../services/auth_service.dart';
import '../services/media_service.dart';
import '../services/premium_service.dart';
import '../services/update_service.dart';
import '../theme/luxe_theme.dart';
import '../widgets/luxe_widgets.dart';
import 'premium_screen.dart';
import 'stickers_screen.dart';
import 'update_screen.dart';

/// Вкладка «Настройки» — профиль, тема, выход.
class SettingsTab extends StatefulWidget {
  const SettingsTab({super.key});
  @override
  State<SettingsTab> createState() => SettingsTabState();
}

class SettingsTabState extends State<SettingsTab> {
  Map<String, dynamic>? profile;
  bool notifications = true;
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final row = await supabase
          .from('profiles')
          .select()
          .eq('id', AuthService.myId)
          .maybeSingle();
      profile = row == null ? null : Map<String, dynamic>.from(row as Map);
    } catch (e) {
      debugPrint('Профиль не загрузился: $e');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _changeAvatar() async {
    final XFile? f = await MediaService.pickImage();
    if (f == null) return;
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Загружаю фото...')));
    }
    try {
      final url = await MediaService.uploadAvatar(AuthService.myId, f);
      await supabase
          .from('profiles')
          .update({'avatar_url': url})
          .eq('id', AuthService.myId);
      _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Ошибка: $e')));
      }
    }
  }

  Future<void> _editName() async {
    final ctrl = TextEditingController(text: profile?['display_name'] ?? '');
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Ваше имя'),
        content: TextField(
            controller: ctrl,
            decoration: const InputDecoration(hintText: 'Как вас зовут?')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Отмена')),
          FilledButton(
              onPressed: () => Navigator.pop(context, ctrl.text.trim()),
              child: const Text('Сохранить')),
        ],
      ),
    );
    if (result != null && result.isNotEmpty) {
      await supabase
          .from('profiles')
          .update({'display_name': result})
          .eq('id', AuthService.myId);
      _load();
    }
  }

  /// Ссылка на разработчика в Telegram.
  static const creatorLink = 'https://t.me/dontwantgetrip';

  Future<void> _openCreatorLink() async {
    final uri = Uri.parse(creatorLink);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Открой ссылку вручную: $creatorLink')),
      );
    }
  }

  Future<void> _setStatus(String status) async {
    await supabase
        .from('profiles')
        .update({'status': status})
        .eq('id', AuthService.myId);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    if (loading) return const Center(child: CircularProgressIndicator());
    final name = (profile?['display_name'] ?? '...') as String;
    final username = (profile?['username'] ?? '') as String;
    final email = supabase.auth.currentUser?.email ?? '';
    final dark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = dark ? LuxeColors.darkCard : Colors.white;

    return ListView(
      children: [
        // Профиль
        Container(
          margin: const EdgeInsets.all(16),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            gradient: const LinearGradient(
              colors: [LuxeColors.tgBlue, Color(0xFF7A5AF8)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            boxShadow: [
              BoxShadow(
                  color: LuxeColors.tgBlue.withOpacity(0.35),
                  blurRadius: 20,
                  offset: const Offset(0, 8)),
            ],
          ),
          child: Row(
            children: [
              GestureDetector(
                onTap: _changeAvatar,
                child: Stack(
                  children: [
                    () {
                      final av = profile?['avatar_url'] as String?;
                      if (av != null && av.isNotEmpty) {
                        return GradientAvatar(
                            name: name == '...' ? '' : name,
                            radius: 32,
                            imageUrl: av);
                      }
                      return Container(
                        width: 64,
                        height: 64,
                        decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white24),
                        alignment: Alignment.center,
                        child: Text(
                          name.isEmpty ? '?' : name[0].toUpperCase(),
                          style: const TextStyle(
                              fontSize: 30,
                              color: Colors.white,
                              fontWeight: FontWeight.bold),
                        ),
                      );
                    }(),
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: Container(
                        padding: const EdgeInsets.all(5),
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white,
                        ),
                        child: const Icon(Icons.camera_alt_rounded,
                            size: 14, color: LuxeColors.tgBlue),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.bold)),
                    Text('@$username',
                        style: const TextStyle(color: Colors.white70)),
                    Text(email,
                        style: const TextStyle(
                            color: Colors.white70, fontSize: 12)),
                  ],
                ),
              ),
              IconButton(
                onPressed: _editName,
                icon: const Icon(Icons.edit_rounded, color: Colors.white),
              ),
            ],
          ),
        ),
        const SectionHeader('Статус'),
        Card(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          color: cardColor,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Column(
            children: [
              for (final s in ['online', 'busy', 'offline'])
                ListTile(
                  leading: Icon(
                    s == 'online'
                        ? Icons.circle
                        : s == 'busy'
                            ? Icons.do_not_disturb_on
                            : Icons.circle_outlined,
                    color: s == 'online'
                        ? LuxeColors.online
                        : s == 'busy'
                            ? LuxeColors.danger
                            : Colors.grey,
                  ),
                  title: Text(s == 'online'
                      ? 'В сети'
                      : s == 'busy'
                          ? 'Занят'
                          : 'Невидимка'),
                  trailing: profile?['status'] == s
                      ? const Icon(Icons.check, color: LuxeColors.tgBlue)
                      : null,
                  onTap: () => _setStatus(s),
                ),
            ],
          ),
        ),
        const SectionHeader('Luxe Premium'),
        Card(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          color: PremiumFeatures.isActive(profile)
              ? LuxeColors.premiumGold.withValues(alpha: 0.14)
              : cardColor,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: ListTile(
            leading: const PremiumBadge(size: 26),
            title: const Text('Luxe Premium',
                style: TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text(PremiumFeatures.isActive(profile)
                ? 'Подписка активна'
                : 'Большие файлы, безлимит пересылок, без рекламы'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () async {
              final changed = await Navigator.push<bool>(
                context,
                MaterialPageRoute(
                  builder: (_) => PremiumScreen(
                    active: PremiumFeatures.isActive(profile),
                    until: profile?['premium_until'] as String?,
                  ),
                ),
              );
              if (changed == true) _load();
            },
          ),
        ),
        const SectionHeader('Оформление'),
        ValueListenableBuilder<ThemeMode>(
          valueListenable: LuxeTheme.mode,
          builder: (context, mode, _) => Card(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            color: cardColor,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Column(
              children: [
                for (final e in [
                  (ThemeMode.system, 'Как в системе', Icons.settings_suggest),
                  (ThemeMode.light, 'Светлая', Icons.light_mode),
                  (ThemeMode.dark, 'Тёмная', Icons.dark_mode),
                ])
                  ListTile(
                    leading: Icon(e.$3, color: LuxeColors.tgBlue),
                    title: Text(e.$2),
                    trailing: mode == e.$1
                        ? const Icon(Icons.check, color: LuxeColors.tgBlue)
                        : null,
                    onTap: () => LuxeTheme.mode.value = e.$1,
                  ),
              ],
            ),
          ),
        ),
        const SectionHeader('Прочее'),
        Card(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          color: cardColor,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Column(
            children: [
              SwitchListTile(
                secondary:
                    const Icon(Icons.notifications, color: LuxeColors.tgBlue),
                title: const Text('Уведомления'),
                value: notifications,
                onChanged: (v) => setState(() => notifications = v),
              ),
              ListTile(
                leading: const Icon(Icons.code_rounded, color: LuxeColors.tgBlue),
                title: const Text('Creator'),
                subtitle: const Text('Связаться с разработчиком'),
                onTap: _openCreatorLink,
              ),
              ListTile(
                leading: const Icon(Icons.system_update_alt_rounded,
                    color: LuxeColors.tgBlue),
                title: const Text('Обновления'),
                subtitle: const Text('Проверить новую версию'),
                onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const UpdateScreen())),
              ),
              ListTile(
                leading: const Icon(Icons.emoji_emotions_outlined,
                    color: LuxeColors.tgBlue),
                title: const Text('Стикеры'),
                subtitle: const Text('Мои наборы, добавление и удаление'),
                onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const StickersScreen())),
              ),
              ListTile(
                leading:
                    const Icon(Icons.info_outline, color: LuxeColors.tgBlue),
                title: const Text('О Luxe'),
                subtitle: Text(
                    // Версию берём ту же, что и проверка обновлений.
                    // Раньше тут было зашитое «1.0.0»: после выпуска
                    // обновлений человек не мог понять, какая у него.
                    'Версия ${UpdateService.currentVersion} • Flutter + Supabase\n'
                    'Сервер: ${SupabaseConfig.routeName}'),
                onTap: () => showAboutDialog(
                  context: context,
                  applicationName: 'Luxe',
                  applicationVersion: UpdateService.currentVersion,
                  children: const [
                    Text('Мессенджер с чатами и звонками.')
                  ],
                ),
              ),
              ListTile(
                leading: const Icon(Icons.logout, color: LuxeColors.danger),
                title: const Text('Выйти',
                    style: TextStyle(color: LuxeColors.danger)),
                onTap: () => AuthService.signOut(),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }
}
