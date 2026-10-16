import 'package:flutter/material.dart';
import '../main.dart';
import '../services/auth_service.dart';
import '../services/media_service.dart';
import '../services/premium_service.dart';
import '../theme/luxe_theme.dart';
import '../screens/chats_tab.dart';
import '../widgets/luxe_widgets.dart';

/// Тёмная левая колонка с навигацией (как в Telegram Desktop).
class LuxeSidebar extends StatelessWidget {
  final int index;
  final ValueChanged<int> onSelect;
  final VoidCallback onMenu;
  const LuxeSidebar({
    super.key,
    required this.index,
    required this.onSelect,
    required this.onMenu,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // Раньше панель была всегда чёрной: в светлой теме она выглядела
    // как дыра рядом со спокойным белым списком чатов.
    final isDark = scheme.brightness == Brightness.dark;
    return Container(
      width: 68,
      color: isDark ? LuxeColors.darkCard : LuxeColors.lightPanel,
      child: ValueListenableBuilder<int>(
        valueListenable: ChatsTab.unread,
        builder: (_, count, __) => Column(
          children: [
            _sbItem(Icons.menu_rounded,
                scheme: scheme, selected: false, onTap: onMenu),
            Divider(color: scheme.outlineVariant, height: 1),
            // Чаты с числом непрочитанных
            _sbItem(
              Icons.chat_bubble_rounded,
              scheme: scheme,
              selected: index == 0,
              badge: count == 0 ? null : '$count',
              onTap: () => onSelect(0),
            ),
            _sbItem(Icons.campaign_rounded,
                scheme: scheme,
                selected: index == 2,
                onTap: () => onSelect(2)),
            // Поиск людей и групп. Отдельная вкладка «Контакты» больше
            // не нужна: искать людей удобнее прямо из списка чатов.
            _sbItem(Icons.search_rounded,
                scheme: scheme,
                selected: index == 1,
                onTap: () => onSelect(1)),
            _sbItem(Icons.call_rounded,
                scheme: scheme,
                selected: index == 3,
                onTap: () => onSelect(3)),
            const Spacer(),
            _sbItem(Icons.settings_rounded,
                scheme: scheme,
                selected: index == 4,
                onTap: () => onSelect(4)),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  Widget _sbItem(IconData icon,
      {required ColorScheme scheme,
      required bool selected,
      required VoidCallback onTap,
      String? badge}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 8),
      child: Material(
        color: selected
            ? LuxeColors.brand.withValues(alpha: 0.14)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: SizedBox(
            height: 48,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Icon(icon,
                    color: selected
                        ? LuxeColors.brand
                        : scheme.onSurfaceVariant,
                    size: 24),
                if (badge != null)
                  Positioned(
                    top: 8,
                    right: 12,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                        color: LuxeColors.tgBlue,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(badge,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.bold)),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Шторка-меню (профиль, пункты, выход).
class LuxeDrawer extends StatelessWidget {
  final Map<String, dynamic>? profile;
  final int index;
  final ValueChanged<int> onSelect;
  const LuxeDrawer({
    super.key,
    required this.profile,
    required this.index,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final name = (profile?['display_name'] ?? '...') as String;
    final username = (profile?['username'] ?? '') as String;
    final avatar = MediaService.fixUrl(profile?['avatar_url'] as String?);
    final email = supabase.auth.currentUser?.email ?? '';
    final scheme = Theme.of(context).colorScheme;

    final items = [
      (Icons.chat_bubble_rounded, 'Чаты', 0),
      (Icons.search_rounded, 'Поиск', 1),
      (Icons.call_rounded, 'Звонки', 3),
      (Icons.settings_rounded, 'Настройки', 4),
    ];

    return Drawer(
      backgroundColor: scheme.surface,
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                GradientAvatar(
                    name: name, radius: 26, imageUrl: avatar),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(name,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    color: scheme.onSurface,
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold)),
                          ),
                          if (profile?['premium'] == true) ...[
                            const SizedBox(width: 4),
                            const PremiumBadge(size: 14),
                          ],
                        ],
                      ),
                      Text('@$username',
                          style: TextStyle(
                              color: scheme.onSurfaceVariant, fontSize: 13)),
                      Text(email,
                          style: TextStyle(
                              color: scheme.onSurfaceVariant
                                  .withValues(alpha: 0.7),
                              fontSize: 11)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Divider(color: Colors.white12),
          ...items.map((it) {
            final selected = index == it.$3;
            return ListTile(
              leading: Icon(it.$1,
                  color: selected
                      ? LuxeColors.brand
                      : scheme.onSurfaceVariant),
              title: Text(it.$2,
                  style: TextStyle(
                      color: selected ? LuxeColors.brand : scheme.onSurface,
                      fontWeight:
                          selected ? FontWeight.w600 : FontWeight.normal)),
              selected: selected,
              onTap: () {
                onSelect(it.$3);
                Navigator.pop(context);
              },
            );
          }),
          Divider(color: scheme.outlineVariant),
          ListTile(
            leading: const Icon(Icons.person_add_alt_1,
                color: LuxeColors.brand),
            title: Text('Пригласить друзей',
                style: TextStyle(color: scheme.onSurface)),
            onTap: () => Navigator.pop(context),
          ),
          ListTile(
            leading: const Icon(Icons.logout, color: LuxeColors.danger),
            title:
                const Text('Выйти', style: TextStyle(color: LuxeColors.danger)),
            onTap: () => AuthService.signOut(),
          ),
        ],
      ),
    );
  }
}