import 'dart:async';

import 'package:flutter/material.dart';

import '../main.dart';
import '../services/auth_service.dart';
import '../services/chat_service.dart';
import '../services/media_service.dart';
import '../services/net.dart';
import '../theme/luxe_theme.dart';
import '../widgets/luxe_widgets.dart';
import '../widgets/verified_badge.dart';
import 'global_search_screen.dart';
import 'new_group_screen.dart';

/// Строка списка чатов.
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

/// Вкладка списка чатов: поиск, фильтры, строки диалогов.
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

  /// Счётчик непрочитанных для иконки «Чаты» в боковой колонке.
  ///
  /// Раньше там стояла захардкоженная пятёрка: человек видел «5»
  /// независимо от того, сколько непрочитанных на самом деле.
  static final unread = ValueNotifier<int>(0);

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
    ('all', 'Все', Icons.forum_outlined),
    ('personal', 'Личные', Icons.person_outline),
    ('groups', 'Группы', Icons.group_outlined),
    ('channels', 'Каналы', Icons.campaign_outlined),
  ];

  @override
  void initState() {
    super.initState();
    reload();
  }

  @override
  void dispose() {
    searchCtrl.dispose();
    super.dispose();
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
        loadError = _describe(e);
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

  /// Понятный текст ошибки.
  ///
  /// Свой текст из сервиса важно показать как есть: там названо, какой
  /// именно запрос не ответил. Через Net.humanError это имя потерялось бы,
  /// и мы бы снова гадали, где затык.
  String _describe(Object e) {
    final raw = e.toString();
    final named = RegExp(r'«(.+?)»').firstMatch(raw);
    if (named != null) return 'Не отвечает запрос: ${named.group(1)}';
    return Net.humanError(e);
  }

  Future<void> _loadRows() async {
    final data = await ChatService.chatListData();
    final chats = data.chats;
    final out = <_Row>[];
    if (chats.isNotEmpty) {
      final ids = chats.map((c) => c['id'] as String).toList();
      // Свежие сообщения одним запросом на все чаты.
      List<Map<String, dynamic>> msgRows = const [];
      try {
        final r = await supabase
            .from('messages')
            .select('chat_id, content, created_at, sender_id, type, status')
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
    ChatsTab.unread.value =
        out.where((r) => r.last != null && _unread(r.last!)).length;
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
                color: Theme.of(context).colorScheme.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.group_add_rounded,
                  color: LuxeColors.tgBlue),
              title: const Text('Создать группу'),
              onTap: () {
                Navigator.pop(sheet);
                _open(NewGroupScreen(mode: 'group', onCreated: reload));
              },
            ),
            ListTile(
              leading:
                  const Icon(Icons.campaign_rounded, color: LuxeColors.tgBlue),
              title: const Text('Создать канал'),
              onTap: () {
                Navigator.pop(sheet);
                _open(NewGroupScreen(mode: 'channel', onCreated: reload));
              },
            ),
            ListTile(
              leading: const Icon(Icons.person_search_rounded,
                  color: LuxeColors.tgBlue),
              title: const Text('Найти человека'),
              subtitle: const Text('Поиск по всем пользователям'),
              onTap: () {
                Navigator.pop(sheet);
                _openSearch();
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _open(NewGroupScreen s) {
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => s))
        .then((_) => reload());
  }

  /// Глобальный поиск: люди, группы, каналы.
  void _openSearch() {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => GlobalSearchScreen(
        onOpenChat: (id) => _openChatById(id),
      ),
    ));
  }

  /// Открыть чат по id. Если его нет в загруженном списке — сначала
  /// перезагружаем список: чат могли только что создать или найти.
  Future<void> _openChatById(String chatId) async {
    final found = rows.where((r) => r.chat['id'] == chatId).firstOrNull;
    if (found != null) {
      widget.onOpenChat(found.chat);
      return;
    }
    await reload();
    if (!mounted) return;
    final again = rows.where((r) => r.chat['id'] == chatId).firstOrNull;
    if (again != null) widget.onOpenChat(again.chat);
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
    final scheme = Theme.of(context).colorScheme;
    final list = _visible();

    return Container(
      color: scheme.surface,
      child: Column(
        children: [
          // Поиск ведёт в общий поиск, а не фильтрует текущий список
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
            child: Row(
              children: [
                Expanded(
                  child: _searchBox(scheme),
                ),
                const SizedBox(width: 8),
                _createButton(scheme),
              ],
            ),
          ),
          _filterRow(scheme),
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
                            icon: searchCtrl.text.isEmpty
                                ? Icons.forum_outlined
                                : Icons.search_off_rounded,
                            title: searchCtrl.text.isEmpty
                                ? 'Здесь появятся ваши чаты'
                                : 'Ничего не найдено',
                            subtitle: searchCtrl.text.isEmpty
                                ? 'Найдите человека в поиске или создайте группу.'
                                : 'Попробуйте другое слово.',
                            accent: LuxeColors.tgBlue,
                          )
                        : RefreshIndicator(
                            onRefresh: reload,
                            color: LuxeColors.tgBlue,
                            child: ListView.builder(
                              itemCount: list.length,
                              itemBuilder: (context, i) =>
                                  _tile(list[i], i),
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

  /// Поле поиска. По нажатию открывается общий поиск по людям и группам.
  Widget _searchBox(ColorScheme scheme) {
    return Material(
      color: Theme.of(context).colorScheme.brightness == Brightness.dark
          ? LuxeColors.darkField
          : LuxeColors.lightField,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: _openSearch,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          child: Row(
            children: [
              Icon(Icons.search_rounded, size: 19, color: scheme.onSurfaceVariant),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  'Поиск людей и групп',
                  style: TextStyle(fontSize: 14, color: scheme.onSurfaceVariant),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _createButton(ColorScheme scheme) {
    return Material(
      color: LuxeColors.brand,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: _createMenu,
        child: const SizedBox(
          width: 42,
          height: 42,
          child: Icon(Icons.add_rounded, color: Colors.white, size: 22),
        ),
      ),
    );
  }

  /// Фильтры: спокойные сегменты вместо пёстрых чипов.
  Widget _filterRow(ColorScheme scheme) {
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 6),
        itemCount: filters.length,
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (_, i) {
          final f = filters[i];
          final on = filter == f.$1;
          return GestureDetector(
            onTap: () => setState(() => filter = f.$1),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: on ? LuxeColors.brand : scheme.outlineVariant.withValues(alpha: 0.45),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  Icon(
                    f.$3,
                    size: 14,
                    color: on ? Colors.white : scheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    f.$2,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: on ? FontWeight.w600 : FontWeight.w500,
                      color: on ? Colors.white : scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _tile(_Row r, int index) {
    final selected = widget.openChatId == r.chat['id'];
    final mine = r.last != null && r.last!['sender_id'] == AuthService.myId;
    final scheme = Theme.of(context).colorScheme;
    final dark = scheme.brightness == Brightness.dark;

    // Превью сообщения: у медиа вместо текста приходит ссылка,
    // её показывать нельзя — читатель видит «Начните переписку».
    final raw = r.last == null
        ? null
        : (mine ? 'Вы: ${r.last!['content']}' : r.last!['content']).toString();
    final text = _preview(raw, r);
    final unreadCount = _unread(r.last!) ? 1 : 0;

    return InkWell(
      onTap: () => widget.onOpenChat(r.chat),
      child: Container(
        decoration: BoxDecoration(
          color: selected
              ? LuxeColors.brand.withValues(alpha: dark ? 0.12 : 0.08)
              : null,
          borderRadius: BorderRadius.circular(14),
        ),
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
                            color: scheme.onSurface,
                          ),
                        ),
                      ),
                      if (r.last != null)
                        Text(
                          _when(r.last!['created_at']),
                          style: TextStyle(
                              fontSize: 11, color: scheme.onSurfaceVariant),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      if (r.kind != 'direct')
                        Container(
                          width: 18,
                          height: 18,
                          decoration: BoxDecoration(
                            color: _kindChipColor(r.kind, scheme)
                                .withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          alignment: Alignment.center,
                          child: Icon(
                            r.kind == 'channel'
                                ? Icons.campaign_rounded
                                : Icons.group_rounded,
                            size: 10,
                            color: _kindChipColor(r.kind, scheme),
                          ),
                        ),
                      if (r.kind != 'direct') const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          text,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13.5,
                            color: raw == null
                                ? scheme.onSurfaceVariant
                                : scheme.onSurface.withValues(alpha: 0.78),
                            fontWeight: raw == null ? FontWeight.w500 : FontWeight.w400,
                          ),
                        ),
                      ),
                      if (unreadCount > 0) ...[
                        const SizedBox(width: 8),
                        Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: LinearGradient(
                              colors: [LuxeColors.neonPink, LuxeColors.neonPurple],
                            ),
                          ),
                        ),
                      ],
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

  /// Новое сообщение, ещё не прочитанное.
  bool _unread(Map<String, dynamic> last) =>
      last['sender_id'] != AuthService.myId && last['status'] != 'read';

  /// Цвет чиппика типа чата.
  Color _kindChipColor(String kind, ColorScheme scheme) {
    switch (kind) {
      case 'channel':
        return LuxeColors.neonPurple;
      case 'group':
        return scheme.onSurfaceVariant;
      default:
        return scheme.onSurfaceVariant;
    }
  }

  /// Превью строки списка.
  ///
  /// У медиа вместо нормального текста в базе лежит имя файла или
  /// ссылка. Раньше в списке это выглядело как «Вы: scaled_10000.webp»
  /// или вовсе «Вы: .» — отсюда пустые строки у картинок.
  String _preview(String? raw, _Row r) {
    final type = r.last?['type'];
    if (type != null && type != 'text') {
      return switch (type) {
        'image' => 'Фотография',
        'video' => 'Видео',
        'voice' => 'Голосовое сообщение',
        'circle' => 'Кружок',
        'sticker' => 'Стикер',
        'file' => _fileName(raw),
        _ => raw ?? '',
      };
    }
    final t = raw?.trim() ?? '';
    if (t.isEmpty || t.length < 2) {
      return r.kind == 'channel'
          ? 'Канал'
          : r.kind == 'group'
              ? 'Группа'
              : 'Начните переписку';
    }
    return t;
  }

  /// Понятное название вместо служебного «scaled_1000047539.webp».
  String _fileName(String? raw) {
    if (raw == null || raw.isEmpty || raw.startsWith('http')) return 'Файл';
    if (!RegExp(r'^(scaled|image_picker|file_picker|media)_').hasMatch(raw)) {
      return raw;
    }
    final dot = raw.lastIndexOf('.');
    if (dot <= 0) return 'Файл';
    return switch (raw.substring(dot + 1).toLowerCase()) {
      'jpg' || 'jpeg' || 'png' || 'webp' || 'gif' => 'Фотография',
      'mp4' || 'mov' => 'Видео',
      'm4a' || 'mp3' || 'wav' || 'aac' => 'Голосовое',
      _ => 'Файл',
    };
  }

  /// Время в строке списка: сегодня — часами, вчера — «вчера»,
/// дальше — датой.
///
/// Раньше здесь стоял timeago, но он печатал английское «3 days ago» —
/// в русском интерфейсе это выглядело как недоделка.
  String _when(String iso) {
    final d = DateTime.parse(iso).toLocal();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(d.year, d.month, d.day);
    final diff = today.difference(day).inDays;
    if (diff == 0) {
      return '${d.hour.toString().padLeft(2, '0')}:'
          '${d.minute.toString().padLeft(2, '0')}';
    }
    if (diff == 1) return 'вчера';
    if (d.year == now.year) {
      return '${d.day.toString().padLeft(2, '0')}.'
          '${d.month.toString().padLeft(2, '0')}';
    }
    return '${d.day.toString().padLeft(2, '0')}.'
        '${d.month.toString().padLeft(2, '0')}.${d.year % 100}';
  }

  Widget _avatar(_Row r) {
    final url = MediaService.fixUrl(r.avatar);
    if (url != null && url.isNotEmpty) {
      return GradientAvatar(name: r.title, radius: 23, imageUrl: r.avatar);
    }
    if (r.kind == 'channel') {
      return Container(
        width: 46,
        height: 46,
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          color: LuxeColors.brand,
        ),
        child: const Icon(Icons.campaign_rounded, color: Colors.white, size: 21),
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
        child: const Icon(Icons.group_rounded, color: Colors.white, size: 21),
      );
    }
    return GradientAvatar(name: r.title, radius: 23);
  }
}
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
