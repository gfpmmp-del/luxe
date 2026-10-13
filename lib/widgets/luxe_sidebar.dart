import 'package:flutter/material.dart';
import '../main.dart';
import '../services/auth_service.dart';
import '../services/premium_service.dart';
import '../theme/luxe_theme.dart';
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
    return Container(
      width: 68,
      color: LuxeColors.sideBar,
      child: Column(
        children: [
          // Бургер
          _sbItem(Icons.menu_rounded, selected: false, onTap: onMenu),
          const Divider(color: Colors.white12, height: 1),
          // Чаты с бейджем
          _sbItem(
            Icons.chat_bubble_rounded,
            selected: index == 0,
            badge: '5',
            onTap: () => onSelect(0),
          ),
          // Каналы
          _sbItem(Icons.campaign_rounded,
              selected: index == 2, onTap: () => onSelect(2)),
          // Контакты
          _sbItem(Icons.contacts_rounded,
              selected: index == 1, onTap: () => onSelect(1)),
          // Звонки
          _sbItem(Icons.call_rounded,
              selected: index == 3, onTap: () => onSelect(3)),
          const Spacer(),
          // Настройки
          _sbItem(Icons.settings_rounded,
              selected: index == 4, onTap: () => onSelect(4)),
          const SizedBox(height: 12),
        ],
      ),
    );
  }

  Widget _sbItem(IconData icon,
      {required bool selected,
      required VoidCallback onTap,
      String? badge}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 8),
      child: Material(
        color: selected ? LuxeColors.sideBarActive : Colors.transparent,
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
                    color: selected ? Colors.white : Colors.white70,
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
    final avatar = profile?['avatar_url'] as String?;
    final email = supabase.auth.currentUser?.email ?? '';

    final items = [
      (Icons.chat_bubble_rounded, 'Чаты', 0),
      (Icons.contacts_rounded, 'Контакты', 1),
      (Icons.call_rounded, 'Звонки', 3),
      (Icons.settings_rounded, 'Настройки', 4),
    ];

    return Drawer(
      backgroundColor: LuxeColors.sideBar,
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
                                style: const TextStyle(
                                    color: Colors.white,
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
                          style:
                              const TextStyle(color: Colors.white60, fontSize: 13)),
                      Text(email,
                          style: const TextStyle(
                              color: Colors.white38, fontSize: 11)),
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
                  color: selected ? LuxeColors.tgBlue : Colors.white70),
              title: Text(it.$2,
                  style: TextStyle(
                      color: selected ? LuxeColors.tgBlue : Colors.white,
                      fontWeight:
                          selected ? FontWeight.bold : FontWeight.normal)),
              selected: selected,
              onTap: () {
                onSelect(it.$3);
                Navigator.pop(context);
              },
            );
          }),
          const Divider(color: Colors.white12),
          ListTile(
            leading: const Icon(Icons.person_add_alt_1,
                color: LuxeColors.tgBlue),
            title: const Text('Пригласить друзей',
                style: TextStyle(color: Colors.white)),
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