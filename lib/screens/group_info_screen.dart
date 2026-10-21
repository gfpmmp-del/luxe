import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../services/auth_service.dart';
import '../services/chat_service.dart';
import '../services/media_service.dart';
import '../theme/luxe_theme.dart';
import '../widgets/luxe_widgets.dart';

/// Информация о группе: аватарка, название, участники.
/// Создатель может менять всё и удалять людей, остальные — выйти.
class GroupInfoScreen extends StatefulWidget {
  final String chatId;
  final VoidCallback? onChanged;
  const GroupInfoScreen({super.key, required this.chatId, this.onChanged});

  @override
  State<GroupInfoScreen> createState() => _GroupInfoScreenState();
}

class _GroupInfoScreenState extends State<GroupInfoScreen> {
  Map<String, dynamic>? chat;
  List<Map<String, dynamic>> members = [];
  bool loading = true;
  final searchCtrl = TextEditingController();
  List<Map<String, dynamic>> found = [];

  bool get isCreator =>
      chat != null && chat!['created_by'] == AuthService.myId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final rows = await ChatService.myChats();
    try {
      chat = rows.firstWhere((c) => c['id'] == widget.chatId);
    } catch (_) {
      chat = null;
    }
    members = await ChatService.groupMembers(widget.chatId);
    if (mounted) setState(() => loading = false);
  }

  Future<void> _changeAvatar() async {
    final XFile? f = await MediaService.pickImage();
    if (f == null) return;
    final url =
        await MediaService.uploadChatAvatar(widget.chatId, f);
    await ChatService.updateChat(widget.chatId, {'avatar_url': url});
    widget.onChanged?.call();
    _load();
  }

  Future<void> _rename() async {
    final ctrl = TextEditingController(text: chat?['title'] ?? '');
    final res = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Название группы'),
        content: TextField(controller: ctrl),
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
    if (res != null && res.isNotEmpty) {
      await ChatService.updateChat(widget.chatId, {'title': res});
      widget.onChanged?.call();
      _load();
    }
  }

  Future<void> _search() async {
    found = await ChatService.searchUsers(searchCtrl.text);
    found.removeWhere(
        (u) => members.any((m) => m['user_id'] == u['id']));
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return Scaffold(
          appBar: AppBar(), body: const Center(child: CircularProgressIndicator()));
    }
    if (chat == null) {
      return Scaffold(
          appBar: AppBar(), body: const Center(child: Text('Группа удалена')));
    }
    final title = (chat!['title'] ?? 'Группа') as String;
    final avatar = chat!['avatar_url'] as String?;
    return Scaffold(
      appBar: AppBar(title: const Text('Информация')),
      body: ListView(
        children: [
          const SizedBox(height: 20),
          Center(
            child: GestureDetector(
              onTap: isCreator ? _changeAvatar : null,
              child: avatar != null && avatar.isNotEmpty
                  ? GradientAvatar(name: title, radius: 50, imageUrl: avatar)
                  : GradientAvatar(name: title, radius: 50),
            ),
          ),
          const SizedBox(height: 10),
          Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title,
                    style: const TextStyle(
                        fontSize: 22, fontWeight: FontWeight.bold)),
                if (isCreator)
                  IconButton(
                      onPressed: _rename, icon: const Icon(Icons.edit, size: 18)),
              ],
            ),
          ),
          Center(
              child: Text('${members.length} ${_plural(members.length)}',
                  style: const TextStyle(color: Colors.grey))),
          const SectionHeader('Участники'),
          ...members.map((m) {
            final name = (m['display_name'] ?? '?') as String;
            final isMe = m['user_id'] == AuthService.myId;
            return ListTile(
              leading: GradientAvatar(
                  name: name,
                  radius: 22,
                  imageUrl: m['avatar_url'] as String?,
                  showOnline: true,
                  isOnline: m['status'] == 'online'),
              title: Text('${isMe ? '$name (вы)' : name}'),
              subtitle: Text('@${m['username']}'),
              trailing: isCreator && !isMe
                  ? IconButton(
                      icon: const Icon(Icons.person_remove,
                          color: LuxeColors.danger),
                      onPressed: () async {
                        await ChatService.removeMember(
                            widget.chatId, m['user_id']);
                        widget.onChanged?.call();
                        _load();
                      },
                    )
                  : null,
            );
          }),
          if (isCreator) ...[
            const SectionHeader('Добавить участника'),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: searchCtrl,
                      decoration: const InputDecoration(
                          hintText: 'Имя пользователя...',
                          border: OutlineInputBorder()),
                      onSubmitted: (_) => _search(),
                    ),
                  ),
                  IconButton(
                      onPressed: _search, icon: const Icon(Icons.search)),
                ],
              ),
            ),
            ...found.map((u) => ListTile(
                  title: Text('@${u['username']}'),
                  trailing: const Icon(Icons.add, color: LuxeColors.tgBlue),
                  onTap: () async {
                    await ChatService.addMember(
                        widget.chatId, u['id'] as String);
                    searchCtrl.clear();
                    found = [];
                    widget.onChanged?.call();
                    _load();
                  },
                )),
            const SizedBox(height: 8),
            Center(
              child: CoolButton(
                icon: Icons.delete_forever_rounded,
                label: 'Удалить группу',
                color: LuxeColors.danger,
                onTap: () async {
                  await ChatService.deleteChat(widget.chatId);
                  if (mounted) Navigator.pop(context);
                },
              ),
            ),
          ] else ...[
            const SizedBox(height: 8),
            Center(
              child: CoolButton(
                icon: Icons.exit_to_app_rounded,
                label: 'Выйти из группы',
                color: Colors.grey.shade600,
                onTap: () async {
                  await ChatService.removeMember(
                      widget.chatId, AuthService.myId);
                  if (mounted) Navigator.pop(context);
                },
              ),
            ),
          ],
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  String _plural(int n) {
    if (n % 10 == 1 && n % 100 != 11) return 'участник';
    if ([2, 3, 4].contains(n % 10) && ![12, 13, 14].contains(n % 100)) {
      return 'участника';
    }
    return 'участников';
  }
}
