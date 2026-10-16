import 'dart:async';

import 'package:flutter/material.dart';
import 'package:timeago/timeago.dart' as timeago;
import '../main.dart';
import '../services/auth_service.dart';
import '../services/chat_service.dart';
import '../services/net.dart';
import '../theme/luxe_theme.dart';
import '../widgets/luxe_widgets.dart';
import '../widgets/verified_badge.dart';
import 'new_group_screen.dart';

class _Row {
  final Map<String, dynamic> chat;
  final String title;
  final String? avatar;
  final String kind;
  final Map<String, dynamic>? last;
  final int members;
  final bool verified;
  _Row(this.chat, this.title, this.avatar, this.kind, this.last, this.members,
      {this.verified = false});
}

/// Колонка списка чатов: поиск, фильтры, строки диалогов.
class ChatsTab extends StatefulWidget {
  final void Function(Map<String, dynamic> chat) onOpenChat;
  final String? openChatId;
  final VoidCallback onNewChat;
  const ChatsTab({
    super.key,
    required this.onOpenChat,
    required this.openChatId,
    required this.onNewChat,
  });

  @override
  State<ChatsTab> createState() => ChatsTabState();
}

class ChatsTabState extends State<ChatsTab> {
  List<_Row> rows = [];
  String filter = 'all';
  bool loading = true;
  bool loadFailed = false;
  String? loadError;
  final searchCtrl = TextEditingController();

  static const filters = [
    ('all', 'Все чаты', Icons.forum_outlined),
    ('personal', 'Личные', Icons.person_outline),
    ('groups', 'Группы', Icons.group_outlined),
    ('channels', 'Каналы', Icons.campaign_outlined),
  ];

  @override
  void initState() {
    super.initState();
    reload();
  }

  Future<void> reload() async {
    setState(() {
      loading = true;
      loadFailed = false;
      loadError = null;
    });
    try {
      // Короткий потолок: пользователь не должен минуту смотреть
      // на спиннер и считать приложение сломанным. Лучше быстро
      // показать ошибку и дать кнопку «Повторить».
      await _loadRows().timeout(const Duration(seconds: 18));
    } on TimeoutException {
      debugPrint('Список чатов не успел загрузиться');
      if (mounted) {
        loadError = 'Сервер не отвечает. Сеть, похоже, его душит.';
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Сервер не отвечает. Нажмите «Повторить»')),
        );
      }
    } catch (e) {
      debugPrint('Список чатов не загрузился: $e');
      if (mounted) {
        // Текст ошибки показываем на экране: иначе по телефону
        // невозможно понять, сеть виновата или сама база.
        loadError = Net.humanError(e);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(loadError!)));
      }
    } finally {
      // Без finally спиннер крутился бы вечно при любой ошибке сети
      if (mounted) {
        setState(() {
          loading = false;
          loadFailed = rows.isEmpty;
        });
      }
    }
  }

  Future<void> _loadRows() async {
    final data = await ChatService.chatListData();
    final chats = data.chats;
    final out = <_Row>[];
    if (chats.isNotEmpty) {
      final ids = chats.map((c) => c['id'] as String).toList();
      // Забираем свежие сообщения одним запросом на все чаты.
      // Раньше лимит был ids.length * 3, и активный чат «съедал»
      // почти всю выборку — у остальных чатов превью пропадало.
      List<Map<String, dynamic>> msgRows = const [];
      try {
        final r = await supabase
            .from('messages')
            .select('chat_id, content, created_at, sender_id')
            .inFilter('chat_id', ids)
            .order('created_at', ascending: false)
            .limit(400);
        msgRows = (r as List).cast<Map<String, dynamic>>();
      } catch (e) {
        debugPrint('Сообщения не загрузились: $e');
      }
      final lasts = <String, Map<String, dynamic>>{};
      for (final r in msgRows) {
        lasts.putIfAbsent(r['chat_id'] as String, () => r);
      }
      for (final c in chats) {
        final id = c['id'] as String;
        final kind = ChatService.chatKind(c);
        final ids2 = data.membersByChat[id] ?? const <String>[];
        final members = kind == 'direct' ? 0 : ids2.length;

        String title;
        String? avatar;
        var verified = false;
        if (kind == 'direct') {
          final otherId =
              ids2.firstWhere((u) => u != AuthService.myId, orElse: () => '');
          final p = otherId.isEmpty ? null : data.profiles[otherId];
          title = (p?['display_name'] ?? p?['username'] ?? 'Чат') as String;
          avatar = p?['avatar_url'] as String?;
          verified = p?['verified'] == true;
        } else {
          title = ((c['title'] ??
                  (kind == 'channel' ? 'Канал' : 'Группа')) as String?) ??
              'Чат';
          avatar = c['avatar_url'] as String?;
        }

        out.add(_Row(c, title, avatar, kind, lasts[id], members,
            verified: verified));
      }
    }
    // Свежие сверху
    out.sort((a, b) {
      final ta = a.last == null ? 0 : 1;
      final tb = b.last == null ? 0 : 1;
      if (ta != tb) return tb - ta;
      final da = a.last == null
          ? DateTime(2000)
          : DateTime.parse(a.last!['created_at']);
      final db = b.last == null
          ? DateTime(2000)
          : DateTime.parse(b.last!['created_at']);
      return db.compareTo(da);
    });
    rows = out;
  }

  /// Меню создания: группа, канал или поиск человека.
  void _createMenu() {
    showModalBottomSheet<void>(
      context: context,
      builder: (sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            ListTile(
              leading:
                  const Icon(Icons.group_add_rounded, color: LuxeColors.tgBlue),
              title: const Text('Создать группу'),
              onTap: () {
                Navigator.pop(sheet);
                _open(NewGroupScreen(mode: 'group', onCreated: reload));
              },
            ),
            ListTile(
              leading: const Icon(Icons.campaign_rounded, color: LuxeColors.tgBlue),
              title: const Text('Создать канал'),
              onTap: () {
                Navigator.pop(sheet);
                _open(NewGroupScreen(mode: 'channel', onCreated: reload));
              },
            ),
            ListTile(
              leading:
                  const Icon(Icons.person_add_alt_rounded, color: LuxeColors.tgBlue),
              title: const Text('Найти человека по имени'),
              onTap: () {
                Navigator.pop(sheet);
                widget.onNewChat();
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _open(Widget screen) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
  }

  List<_Row> _visible() {
    final q = searchCtrl.text.trim().toLowerCase();
    return rows.where((r) {
      final matchFilter = switch (filter) {
        'personal' => r.kind == 'direct',
        'groups' => r.kind == 'group',
        'channels' => r.kind == 'channel',
        _ => true,
      };
      final matchQuery =
          q.isEmpty || r.title.toLowerCase().contains(q) ||
              (r.last?['content']?.toString().toLowerCase().contains(q) ??
                  false);
      return matchFilter && matchQuery;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final bg = dark ? LuxeColors.darkBg : const Color(0xFFFFFFFF);
    final list = _visible();

    return Container(
      color: bg,
      child: Column(
        children: [
          // Поиск + кнопка создания
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
            child: Row(
              children: [
                Expanded(
                  child: Container(
              decoration: BoxDecoration(
                color: dark ? LuxeColors.darkField : const Color(0xFFF1F3F5),
                borderRadius: BorderRadius.circular(20),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  Icon(Icons.search,
                      size: 20,
                      color: dark ? Colors.white54 : Colors.black45),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: searchCtrl,
                      style: const TextStyle(fontSize: 15),
                      decoration: const InputDecoration(
                        hintText: 'Поиск',
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(vertical: 12),
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  if (searchCtrl.text.isNotEmpty)
                    GestureDetector(
                      onTap: () {
                        searchCtrl.clear();
                        setState(() {});
                      },
                      child: Icon(Icons.close,
                          size: 18,
                          color: dark ? Colors.white54 : Colors.black45),
                    ),
                ],
              ),
                  ),
                ),
                const SizedBox(width: 8),
                // Кнопка создания группы / канала
                Tooltip(
                  message: 'Создать',
                  child: InkWell(
                    onTap: _createMenu,
                    borderRadius: BorderRadius.circular(22),
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: LuxeColors.tgBlue,
                        borderRadius: BorderRadius.circular(22),
                      ),
                      child: const Icon(Icons.add_rounded,
                          color: Colors.white, size: 22),
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Фильтры
          SizedBox(
            height: 34,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: filters
                  .map((f) => Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: FilterChip(
                          label: Text(f.$2),
                          avatar: Icon(f.$3, size: 15),
                          selected: filter == f.$1,
                          showCheckmark: false,
                          visualDensity: VisualDensity.compact,
                          labelStyle: TextStyle(
                            fontSize: 12,
                            color: filter == f.$1
                                ? Colors.white
                                : (dark ? Colors.white70 : Colors.black87),
                          ),
                          selectedColor: LuxeColors.tgBlue,
                          backgroundColor: dark
                              ? LuxeColors.darkField
                              : const Color(0xFFF1F3F5),
                          onSelected: (_) => setState(() => filter = f.$1),
                        ),
                      ))
                  .toList(),
            ),
          ),
          const SizedBox(height: 4),
          Expanded(
            child: loading
                ? const Center(child: CircularProgressIndicator())
                : loadFailed && list.isEmpty
                    // Раньше при сбое просто показывалось «Ничего не
                    // найдено» — выглядело как пустой аккаунт, и
                    // повторить загрузку было нечем.
                    ? EmptyState(
                        icon: Icons.cloud_off_rounded,
                        title: 'Не удалось загрузить чаты',
                        subtitle: loadError ??
                            'Проверьте подключение к интернету.',
                        accent: LuxeColors.tgBlue,
                      )
                    : list.isEmpty
                        ? EmptyState(
                            icon: Icons.chat_bubble_outline,
                            title: 'Ничего не найдено',
                            subtitle:
                                'Измените фильтр или создайте новый чат.',
                            accent: LuxeColors.tgBlue,
                          )
                        : RefreshIndicator(
                            onRefresh: reload,
                            color: LuxeColors.tgBlue,
                            child: ListView.builder(
                              itemCount: list.length,
                              itemBuilder: (context, i) =>
                                  _tile(list[i], dark, list.length),
                            ),
                          ),
          ),
          if (loadFailed && !loading)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: CoolButton(
                icon: Icons.refresh_rounded,
                label: 'Повторить',
                onTap: reload,
              ),
            ),
        ],
      ),
    );
  }

  Widget _tile(_Row r, bool dark, int index) {
    final selected = widget.openChatId == r.chat['id'];
    final mine = r.last != null &&
        r.last!['sender_id'] == AuthService.myId;
    final text = r.last == null
        ? (r.kind == 'channel'
            ? 'Канал'
            : r.kind == 'group'
                ? 'Группа'
                : 'Начните переписку')
        : (mine ? 'Вы: ${r.last!['content']}' : r.last!['content']);

    return InkWell(
      onTap: () => widget.onOpenChat(r.chat),
      child: Container(
        color: selected
            ? LuxeColors.tgBlue.withValues(alpha: dark ? 0.25 : 0.12)
            : (index.isOdd
                ? (dark
                    ? const Color(0xFF0E1621)
                    : const Color(0xFFFAFAFA))
                : Colors.transparent),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            _avatar(r),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: UserName(
                          r.title,
                          verified: r.verified,
                          style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: selected && !dark
                                  ? LuxeColors.tgBlueDark
                                  : null),
                        ),
                      ),
                      if (r.last != null)
                        Text(
                          timeago.format(
                              DateTime.parse(r.last!['created_at'])
                                  .toLocal(),
                              locale: 'ru'),
                          style: TextStyle(
                              fontSize: 11,
                              color: dark ? Colors.white38 : Colors.black45),
                        ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      if (r.kind == 'channel')
                        const Padding(
                          padding: EdgeInsets.only(right: 4),
                          child: Icon(Icons.campaign_rounded,
                              size: 13, color: LuxeColors.tgBlue),
                        )
                      else if (r.kind == 'group')
                        const Padding(
                          padding: EdgeInsets.only(right: 4),
                          child: Icon(Icons.group_rounded,
                              size: 13, color: Colors.grey),
                        ),
                      Expanded(
                        child: Text(text,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 13,
                                color: dark ? Colors.white54 : Colors.black54)),
                      ),
                      if (r.kind != 'direct')
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(
                            color: dark
                                ? Colors.white12
                                : Colors.grey.shade300,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text('${r.members}',
                              style: TextStyle(
                                  fontSize: 10,
                                  color: dark
                                      ? Colors.white70
                                      : Colors.black54)),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _avatar(_Row r) {
    if (r.avatar != null && r.avatar!.isNotEmpty) {
      return CircleAvatar(radius: 23, backgroundImage: NetworkImage(r.avatar!));
    }
    if (r.kind == 'channel') {
      return Container(
        width: 46,
        height: 46,
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
              colors: [LuxeColors.tgBlue, Color(0xFF7A5AF8)]),
        ),
        child: const Icon(Icons.campaign_rounded,
            color: Colors.white, size: 22),
      );
    }
    if (r.kind == 'group') {
      return Container(
        width: 46,
        height: 46,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: avatarGradient(r.title),
        ),
        child: const Icon(Icons.group_rounded,
            color: Colors.white, size: 22),
      );
    }
    return GradientAvatar(name: r.title, radius: 23);
  }
}

/// Колонка «Каналы»: только каналы из списка чатов.
class ChannelsTab extends StatelessWidget {
  final void Function(Map<String, dynamic> chat) onOpen;
  const ChannelsTab({super.key, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    return ChatsTab(
      onOpenChat: onOpen,
      openChatId: null,
      onNewChat: () {},
    );
  }
}