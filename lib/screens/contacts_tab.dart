import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../services/chat_service.dart';
import '../theme/luxe_theme.dart';
import '../widgets/luxe_widgets.dart';
import '../widgets/verified_badge.dart';
import 'chat_screen.dart';

/// Вкладка «Контакты» — поиск по username.
class ContactsTab extends StatefulWidget {
  const ContactsTab({super.key, this.onChanged});
  final VoidCallback? onChanged;
  @override
  State<ContactsTab> createState() => ContactsTabState();
}

class ContactsTabState extends State<ContactsTab> {
  List<Map<String, dynamic>> found = [];
  final search = TextEditingController();
  bool searching = false;

  Future<void> _search() async {
    setState(() => searching = true);
    try {
      final r = await ChatService.searchUsers(search.text)
          .timeout(const Duration(seconds: 15));
      found = r;
    } catch (e) {
      debugPrint('Поиск не отработал: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Поиск не удался, проверьте сеть')),
        );
      }
    } finally {
      // Без finally индикатор поиска остался бы крутиться вечно
      if (mounted) setState(() => searching = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          Container(
            decoration: BoxDecoration(
              color: dark ? LuxeColors.darkField : Colors.grey.shade200,
              borderRadius: BorderRadius.circular(24),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: search,
                    decoration: const InputDecoration(
                      hintText: 'Поиск по имени пользователя...',
                      border: InputBorder.none,
                      prefixIcon: Icon(Icons.search),
                    ),
                    onSubmitted: (_) => _search(),
                  ),
                ),
                if (searching)
                  const Padding(
                    padding: EdgeInsets.all(8),
                    child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2)),
                  )
                else
                  IconButton(
                      onPressed: _search,
                      icon: const Icon(Icons.arrow_forward_rounded,
                          color: LuxeColors.tgBlue)),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: found.isEmpty
                ? const EmptyState(
                    icon: Icons.person_search_outlined,
                    title: 'Найдите друзей',
                    subtitle: 'Введите имя пользователя — например, друга — и начните чат.',
                  )
                : ListView.builder(
                    itemCount: found.length,
                    itemBuilder: (context, i) {
                      final u = found[i];
                      final name =
                          (u['display_name'] ?? u['username'] ?? '?') as String;
                      final verified = u['verified'] == true;
                      return Card(
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        // Правый клик мышью открывает меню админа
                        child: GestureDetector(
                          onSecondaryTap: () =>
                              _adminMenu(context, u, name, verified),
                          child: ListTile(
                          leading: GradientAvatar(
                              name: name,
                              imageUrl: u['avatar_url'] as String?),
                          title: UserName(
                            name,
                            verified: verified,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          subtitle: Text('@${u['username']} • ${_statusText(u['status'] as String?)}'),
                          onLongPress: () => _adminMenu(context, u, name, verified),
                          trailing: PopupMenuButton<String>(
                            icon: const Icon(Icons.more_vert_rounded, size: 20),
                            tooltip: 'Действия',
                            onSelected: (v) => _onMenuAction(context, v, u, name, verified),
                            itemBuilder: (menu) => [
                              const PopupMenuItem(
                                value: 'chat',
                                child: ListTile(
                                  dense: true,
                                  contentPadding: EdgeInsets.zero,
                                  leading:
                                      Icon(Icons.chat_bubble_outline_rounded, size: 20),
                                  title: Text('Написать'),
                                ),
                              ),
                              const PopupMenuItem(
                                value: 'verify',
                                child: ListTile(
                                  dense: true,
                                  contentPadding: EdgeInsets.zero,
                                  leading: Icon(Icons.verified_outlined, size: 20),
                                  title: Text('Галочка'),
                                ),
                              ),
                            ],
                          ),
                          onTap: () async {
                            final chatId = await ChatService.openDirectChat(
                                u['username']);
                            if (chatId == null || !context.mounted) return;
                            widget.onChanged?.call();
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) => ChatScreen(
                                      chatId: chatId, title: name)),
                            );
                          },
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  /// Статус пользователя по-русски.
  String _statusText(String? status) => switch (status) {
        'online' => 'в сети',
        'busy' => 'занят(а)',
        'offline' => 'был(а) недавно',
        _ => 'не в сети',
      };

  /// Обработка пунктов меню контакта.
  Future<void> _onMenuAction(BuildContext context, String action,
      Map<String, dynamic> user, String name, bool verified) async {
    if (action == 'verify') {
      await _adminMenu(context, user, name, verified);
      return;
    }
    if (!context.mounted) return;
    final chatId = await ChatService.openDirectChat(user['username'] as String);
    if (chatId == null || !context.mounted) return;
    widget.onChanged?.call();
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ChatScreen(chatId: chatId, title: name)),
    );
  }

  /// Меню администратора: выдать или снять галочку верификации.
  Future<void> _adminMenu(BuildContext context, Map<String, dynamic> user,
      String name, bool verified) async {
    final isAdmin = await AuthService.isAdmin();
    if (!context.mounted) return;
    if (!isAdmin) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Галочку может выдать только администратор')),
      );
      return;
    }

    final id = user['id'] as String;
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: GradientAvatar(name: name, radius: 20),
              title: UserName(name,
                  verified: verified,
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text('@${user['username']}'),
            ),
            const Divider(height: 1),
            ListTile(
              leading: Icon(
                verified ? Icons.gpp_maybe_rounded : Icons.verified_rounded,
                color: verified ? Colors.grey : LuxeColors.tgBlue,
              ),
              title: Text(verified ? 'Снять галочку' : 'Выдать галочку'),
              onTap: () => Navigator.pop(sheet, verified ? 'off' : 'on'),
            ),
          ],
        ),
      ),
    );
    if (action == null) return;

    try {
      if (action == 'on') {
        await AuthService.verifyUser(id);
      } else {
        await AuthService.unverifyUser(id);
      }
      if (!mounted) return;
      setState(() {});
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Не удалось: $e')));
    }
  }
}
