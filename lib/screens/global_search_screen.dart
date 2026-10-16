import 'dart:async';

import 'package:flutter/material.dart';
import '../services/chat_service.dart';
import '../theme/luxe_theme.dart';
import '../widgets/luxe_widgets.dart';
import '../widgets/verified_badge.dart';

/// Глобальный поиск: люди, группы и каналы в одном месте.
///
/// Раньше чтобы найти человека, надо было идти во вкладку «Контакты».
/// Теперь поиск один и на виду — в поле над списком чатов.
class GlobalSearchScreen extends StatefulWidget {
  final void Function(String chatId) onOpenChat;

  const GlobalSearchScreen({super.key, required this.onOpenChat});

  @override
  State<GlobalSearchScreen> createState() => _GlobalSearchScreenState();
}

/// Подсказка, пока в строке поиска ничего не набрано.
class _SearchHint extends StatelessWidget {
  const _SearchHint();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget row(IconData icon, String title, String sub) => Padding(
          padding: const EdgeInsets.only(bottom: 18),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 20, color: scheme.onSurfaceVariant),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w600,
                          color: scheme.onSurface,
                        )),
                    const SizedBox(height: 2),
                    Text(sub,
                        style: TextStyle(
                            fontSize: 13, color: scheme.onSurfaceVariant)),
                  ],
                ),
              ),
            ],
          ),
        );

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(32, 24, 32, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Кого ищем?',
                style: TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w700,
                  color: scheme.onSurface,
                )),
            const SizedBox(height: 18),
            row(Icons.person_outline_rounded, 'Человека',
                'По имени или @username. Например: Макс или @max'),
            row(Icons.group_outlined, 'Группу', 'По названию группы.'),
            row(Icons.campaign_outlined, 'Канал', 'По названию канала.'),
          ],
        ),
      ),
    );
  }
}

class _GlobalSearchScreenState extends State<GlobalSearchScreen> {
  final _search = TextEditingController();
  List<Map<String, dynamic>> _people = [];
  List<Map<String, dynamic>> _groups = [];
  bool _loading = false;
  bool _searched = false;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _search.addListener(_onText);
  }

  void _onText() {
    setState(() {});
    _debounce?.cancel();
    // Пустая строка — запрос не нужен, сразу показываем подсказку
    if (_search.text.trim().isEmpty) {
      setState(() {
        _people = [];
        _groups = [];
        _loading = false;
        _searched = false;
      });
      return;
    }
    // Пауза перед запросом: иначе на каждую букву летит в сеть
    _debounce = Timer(
        const Duration(milliseconds: 350), () => _run(_search.text));
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> _run(String q) async {
    setState(() => _loading = true);
    final people = await ChatService.searchUsers(q);
    final groups = await ChatService.searchGroups(q);
    if (!mounted) return;
    setState(() {
      _people = people;
      _groups = groups;
      _loading = false;
      _searched = true;
    });
  }

  Future<void> _openWith(String username) async {
    _search.clear();
    final chatId = await ChatService.openDirectChat(username);
    if (!mounted) return;
    if (chatId == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Не удалось открыть диалог')));
      return;
    }
    Navigator.pop(context);
    widget.onOpenChat(chatId);
  }

  @override
  Widget build(BuildContext context) {
    final asked = _search.text.trim().isNotEmpty;
    final empty =
        _searched && !_loading && _people.isEmpty && _groups.isEmpty;

    return Scaffold(
      appBar: AppBar(title: const Text('Поиск')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: TextField(
              controller: _search,
              autofocus: true,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: 'Имя, username, группа или канал',
                prefixIcon: const Icon(Icons.search_rounded, size: 20),
                suffixIcon: !asked
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close_rounded, size: 18),
                        onPressed: _search.clear,
                      ),
              ),
            ),
          ),
          if (_loading)
            const LinearProgressIndicator(minHeight: 2)
          else
            const SizedBox(height: 2),
          Expanded(
            child: empty
                ? EmptyState(
                    icon: Icons.search_off_rounded,
                    title: 'Ничего не найдено',
                    subtitle: 'Попробуйте другое имя или название группы.',
                    accent: LuxeColors.tgBlue,
                  )
                : !asked
                    // Пока ничего не введено — не пугаем «ничего не
                    // найдено», а показываем, что искать и как.
                    ? const _SearchHint()
                    : ListView(
                        padding: const EdgeInsets.fromLTRB(8, 8, 8, 24),
                        children: [
                          if (_people.isNotEmpty) ...[
                            _section('Люди', _people.length),
                            ..._people.map(_personTile),
                          ],
                          if (_groups.isNotEmpty) ...[
                            _section('Группы и каналы', _groups.length),
                            ..._groups.map(_groupTile),
                          ],
                        ],
                      ),
          ),
        ],
      ),
    );
  }

  Widget _section(String title, int count) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 14, 8, 6),
      child: Row(
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.4,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: 6),
          Text('$count',
              style: TextStyle(
                  fontSize: 12.5,
                  color: Theme.of(context).colorScheme.onSurfaceVariant)),
        ],
      ),
    );
  }

  Widget _personTile(Map<String, dynamic> u) {
    final name = (u['display_name'] ?? u['username'] ?? '?') as String;
    final username = (u['username'] ?? '') as String;
    final online = u['status'] == 'online';
    final verified = u['verified'] == true;

    return ListTile(
      leading: GradientAvatar(
        name: name,
        radius: 21,
        imageUrl: u['avatar_url'] as String?,
        showOnline: online,
      ),
      title: Row(
        children: [
          Flexible(
            child: Text(name,
                maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
          if (verified) ...[
            const SizedBox(width: 5),
            const VerifiedBadge(size: 15),
          ],
        ],
      ),
      subtitle: Text('@$username', maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: FilledButton(
        onPressed: () => _openWith(username),
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        ),
        child: const Text('Написать'),
      ),
      onTap: () => _openWith(username),
    );
  }

  Widget _groupTile(Map<String, dynamic> g) {
    final title = (g['title'] ?? 'Без названия') as String;
    final kind = (g['kind'] ?? 'group') as String;
    return ListTile(
      leading: GradientAvatar(
        name: title,
        radius: 21,
        imageUrl: g['avatar_url'] as String?,
      ),
      title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(kind == 'channel' ? 'Канал' : 'Группа'),
      trailing: Icon(
        kind == 'channel' ? Icons.campaign_rounded : Icons.group_rounded,
        size: 18,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
      onTap: () {
        Navigator.pop(context);
        widget.onOpenChat(g['id'] as String);
      },
    );
  }
}
