import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../services/chat_service.dart';
import '../services/media_service.dart';
import '../theme/luxe_theme.dart';
import '../widgets/luxe_widgets.dart';
import 'channel_screen.dart';
import 'chat_screen.dart';

/// Создание группы или канала в стиле Telegram:
/// большая аватарка с камерой, название, описание, участники.
class NewGroupScreen extends StatefulWidget {
  final String mode; // 'group' | 'channel'
  final VoidCallback? onCreated;
  const NewGroupScreen({super.key, required this.mode, this.onCreated});

  @override
  State<NewGroupScreen> createState() => _NewGroupScreenState();
}

class _NewGroupScreenState extends State<NewGroupScreen> {
  final titleCtrl = TextEditingController();
  final descCtrl = TextEditingController();
  final searchCtrl = TextEditingController();
  XFile? avatar;
  List<Map<String, dynamic>> found = [];
  final List<Map<String, dynamic>> selected = [];
  bool busy = false;
  bool searching = false;

  bool get isChannel => widget.mode == 'channel';

  Future<void> _pickAvatar() async {
    final f = await MediaService.pickImage();
    if (f != null) setState(() => avatar = f);
  }

  Future<void> _search() async {
    setState(() => searching = true);
    found = await ChatService.searchUsers(searchCtrl.text);
    found.removeWhere((u) => selected.any((s) => s['id'] == u['id']));
    if (mounted) setState(() => searching = false);
  }

  Future<void> _create() async {
    if (titleCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Введите название')));
      return;
    }
    setState(() => busy = true);
    try {
      final ids = selected.map((s) => s['id'] as String).toList();
      final id = isChannel
          ? await ChatService.createChannel(
              title: titleCtrl.text,
              description: descCtrl.text,
              memberIds: ids,
              avatar: avatar)
          : await ChatService.createGroup(
              title: titleCtrl.text, memberIds: ids, avatar: avatar);
      widget.onCreated?.call();
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
            builder: (_) => isChannel
                ? ChannelScreen(chatId: id, title: titleCtrl.text.trim())
                : ChatScreen(chatId: id, title: titleCtrl.text.trim())),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Ошибка: $e')));
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      appBar: AppBar(
          title: Text(isChannel ? 'Новый канал' : 'Новая группа')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // Аватарка
          Center(
            child: GestureDetector(
              onTap: _pickAvatar,
              child: Stack(
                children: [
                  Container(
                    width: 110,
                    height: 110,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: const LinearGradient(colors: [
                        LuxeColors.tgBlue,
                        Color(0xFF7A5AF8)
                      ]),
                      image: avatar == null
                          ? null
                          : DecorationImage(
                              image: FileImage(File(avatar!.path)),
                              fit: BoxFit.cover),
                    ),
                    child: avatar == null
                        ? Icon(
                            isChannel
                                ? Icons.campaign_rounded
                                : Icons.group_rounded,
                            color: Colors.white,
                            size: 48)
                        : null,
                  ),
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: LuxeColors.tgBlue,
                      ),
                      child: const Icon(Icons.camera_alt_rounded,
                          color: Colors.white, size: 18),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          const Center(child: Text('Нажмите, чтобы выбрать фото')),
          const SizedBox(height: 20),
          TextField(
            controller: titleCtrl,
            decoration: InputDecoration(
              labelText: isChannel ? 'Название канала' : 'Название группы',
              border: const OutlineInputBorder(),
              prefixIcon: Icon(isChannel
                  ? Icons.campaign_outlined
                  : Icons.group_outlined),
            ),
          ),
          if (isChannel) ...[
            const SizedBox(height: 12),
            TextField(
              controller: descCtrl,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Описание канала',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.description_outlined),
              ),
            ),
          ],
          const SectionHeader('Участники'),
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
                    controller: searchCtrl,
                    decoration: const InputDecoration(
                      hintText: 'Найти по имени пользователя...',
                      border: InputBorder.none,
                      prefixIcon: Icon(Icons.search),
                    ),
                    onSubmitted: (_) => _search(),
                  ),
                ),
                searching
                    ? const Padding(
                        padding: EdgeInsets.all(8),
                        child: SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2)))
                    : IconButton(
                        onPressed: _search,
                        icon: const Icon(Icons.arrow_forward_rounded,
                            color: LuxeColors.tgBlue)),
              ],
            ),
          ),
          if (selected.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: selected
                  .map((u) => Chip(
                        avatar: GradientAvatar(
                            name: (u['display_name'] ?? '?') as String,
                            radius: 12),
                        label: Text('@${u['username']}'),
                        deleteIcon: const Icon(Icons.close, size: 16),
                        onDeleted: () =>
                            setState(() => selected.remove(u)),
                      ))
                  .toList(),
            ),
          ],
          const SizedBox(height: 8),
          ...found.map((u) {
            final name = (u['display_name'] ?? u['username'] ?? '?') as String;
            return ListTile(
              leading: GradientAvatar(
                  name: name,
                  radius: 20,
                  imageUrl: u['avatar_url'] as String?),
              title: Text(name),
              subtitle: Text('@${u['username']}'),
              trailing: const Icon(Icons.add_circle,
                  color: LuxeColors.tgBlue),
              onTap: () => setState(() {
                selected.add(u);
                found.remove(u);
              }),
            );
          }),
          const SizedBox(height: 24),
          Center(
            child: busy
                ? const CircularProgressIndicator()
                : CoolButton(
                    icon: isChannel
                        ? Icons.campaign_rounded
                        : Icons.group_add_rounded,
                    label: isChannel
                        ? 'Создать канал'
                        : 'Создать группу (${selected.length})',
                    onTap: _create,
                  ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
