import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../main.dart';
import '../services/auth_service.dart';
import '../services/call_service.dart';
import '../services/chat_service.dart';
import '../services/media_service.dart';
import '../services/ring_service.dart';
import '../theme/luxe_theme.dart';
import '../widgets/channel_info_panel.dart';
import '../widgets/luxe_sidebar.dart';
import '../widgets/luxe_widgets.dart';
import 'call_screen.dart';
import 'calls_tab.dart';
import 'chats_tab.dart';
import 'global_search_screen.dart';
import 'settings_tab.dart';
import 'split_chat_screen.dart';

/// Трёхколоночный главный экран Luxe (как Telegram Desktop):
/// тёмная навигация | список чатов | открытый чат | панель канала.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  int index = 0;
  final GlobalKey<ScaffoldState> scaffoldKey = GlobalKey<ScaffoldState>();

  final chatsKey = GlobalKey<ChatsTabState>();
  final callsKey = GlobalKey<CallsTabState>();

  RealtimeChannel? incomingCh;
  Map<String, dynamic>? incomingOffer;
  Map<String, dynamic>? myProfile;

  /// Уже отклонённые или отработанные предложения — чтобы карточка
  /// не всплывала повторно при догоняющей проверке.
  final Set<String> _dismissedOffers = {};

  /// Страховка на случай, если Realtime отвалился: раз в 12 секунд
  /// смотрим, нет ли свежего входящего.
  Timer? _pollTimer;

  /// Через сколько убрать карточку, если на неё так и не ответили.
  Timer? _autoHide;

  // Открытый чат
  String? chatId;
  String? chatTitle;
  String? chatKind;
  String? chatAvatar;
  bool infoOpen = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadProfile();
    incomingCh = CallServiceListen.listenIncoming(_showIncoming);
    // Ключи ретрансляции грузим заранее — к первому звонку они уже
    // будут, и звонок не станет ждать сеть.
    CallService.warmTurn();
    // Подписка Realtime могла не успеть к моменту вызова, а пока
    // приложение было свёрнуто — не работала вовсе. Сразу смотрим,
    // не звонили ли только что.
    _checkMissedCall();
    _pollTimer = Timer.periodic(
        const Duration(seconds: 12), (_) => _checkMissedCall());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // На iOS свёрнутое приложение приостанавливают, сокет Realtime
      // умирает, а пропущенные события никто не повторяет. Поэтому
      // при возврате проверяем звонки руками.
      _checkMissedCall();
      _pollTimer ??= Timer.periodic(
          const Duration(seconds: 12), (_) => _checkMissedCall());
    } else if (state == AppLifecycleState.paused) {
      _pollTimer?.cancel();
      _pollTimer = null;
    }
  }

  /// Показать карточку входящего и включить звонок.
  void _showIncoming(Map<String, dynamic> offer) {
    if (!mounted || incomingOffer != null) return;
    setState(() => incomingOffer = offer);
    RingService.start();
    // Звонящий сдаётся через 30 секунд. Держать карточку дольше
    // незачем: ответить на звонок, которого уже нет, нельзя.
    _autoHide?.cancel();
    _autoHide = Timer(const Duration(seconds: 35), () {
      if (mounted) _dismissIncoming();
    });
  }

  /// Скрыть карточку: ответили, отклонили, или звонок сам кончился.
  void _dismissIncoming() {
    _autoHide?.cancel();
    _autoHide = null;
    final id = incomingOffer?['id']?.toString();
    if (id != null && id.isNotEmpty) _dismissedOffers.add(id);
    RingService.stop();
    if (mounted) setState(() => incomingOffer = null);
  }

  /// Догнать звонок, который пришёл, пока Realtime молчал.
  Future<void> _checkMissedCall() async {
    if (!mounted || incomingOffer != null) return;
    try {
      final since = DateTime.now()
          .subtract(const Duration(seconds: 35))
          .toUtc()
          .toIso8601String();
      final rows = await supabase
          .from('call_signals')
          .select()
          .eq('callee_id', AuthService.myId)
          .eq('type', 'offer')
          .gte('created_at', since)
          .order('created_at', ascending: false)
          .limit(3);
      for (final r in (rows as List)) {
        final offer = Map<String, dynamic>.from(r as Map);
        final id = offer['id']?.toString() ?? '';
        if (id.isEmpty || _dismissedOffers.contains(id)) continue;

        // Если после предложения уже был ответ или сброс — звонок
        // неактуален, показывать его нельзя.
        final later = await supabase
            .from('call_signals')
            .select('type')
            .eq('chat_id', offer['chat_id'])
            .gt('created_at', offer['created_at'])
            .inFilter('type', ['answer', 'reject', 'hangup'])
            .limit(1);
        if ((later as List).isNotEmpty) {
          _dismissedOffers.add(id);
          continue;
        }
        _showIncoming(offer);
        return;
      }
    } catch (e) {
      // Тихо: проверка повторяется сама, шуметь в интерфейсе не о чем.
      debugPrint('Проверка входящих: $e');
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pollTimer?.cancel();
    _autoHide?.cancel();
    RingService.stop();
    incomingCh?.unsubscribe();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    final row = await supabase
        .from('profiles')
        .select('display_name, username, avatar_url')
        .eq('id', AuthService.myId)
        .maybeSingle();
    if (row != null && mounted) {
      setState(() => myProfile = Map<String, dynamic>.from(row as Map));
    }
  }

  Future<void> _openChat(Map<String, dynamic> chat) async {
    final id = chat['id'] as String;
    final display = await ChatService.chatDisplay(chat);
    final kind = display['kind'] ?? 'direct';
    if (!mounted) return;
    setState(() {
      chatId = id;
      chatTitle = display['title'] ?? 'Чат';
      chatKind = kind;
      chatAvatar = display['avatar'];
      infoOpen = false;
    });
  }

  void _closeChat() => setState(() {
        chatId = null;
        infoOpen = false;
      });

  /// Открыть чат по id — из поиска, где полной строки чата нет.
  Future<void> _openChatById(String id) async {
    try {
      final rows = await supabase
          .from('chats')
          .select('id, kind, title, avatar_url, is_group, created_at')
          .eq('id', id)
          .maybeSingle();
      if (rows == null) {
        _toast('Чат не найден');
        return;
      }
      await _openChat(Map<String, dynamic>.from(rows as Map));
    } catch (e) {
      _toast('Не удалось открыть чат');
    }
  }

  void _toast(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      final wide = box.maxWidth > 760;
      return wide ? _desktop() : _mobile();
    });
  }

  // ---------- Десктоп: три колонки ----------
  Widget _desktop() {
    return Scaffold(
      key: scaffoldKey,
      drawer: LuxeDrawer(
        profile: myProfile,
        index: index,
        onSelect: (i) => setState(() => index = i),
      ),
      body: SafeArea(
        child: Row(
          children: [
            LuxeSidebar(
              index: index,
              onSelect: (i) => setState(() => index = i),
              onMenu: () => scaffoldKey.currentState?.openDrawer(),
            ),
            _divider(),
            SizedBox(width: 400, child: _listColumn()),
            _divider(),
            Expanded(child: _chatColumn()),
            if (infoOpen && chatId != null)
              _dividerVertical()
            else
              const SizedBox.shrink(),
            if (infoOpen && chatId != null)
              _ChannelInfoHost(
                chatId: chatId!,
                title: chatTitle ?? '',
                kind: chatKind ?? 'channel',
                onClose: () => setState(() => infoOpen = false),
                onChanged: () => chatsKey.currentState?.reload(),
              ),
          ],
        ),
      ),
    );
  }

  Widget _divider() => Container(
        width: 1,
        color: Theme.of(context).dividerColor,
      );

  Widget _dividerVertical() => const SizedBox.shrink();

  // ---------- Список (вторая колонка) ----------
  Widget _listColumn() {
    switch (index) {
      case 1:
        // Поиск людей и групп. Отдельной вкладки «Контакты» больше нет:
        // искать можно прямо из списка чатов, это быстрее.
        return GlobalSearchScreen(onOpenChat: (id) => _openChatById(id));
      case 2:
        return ChannelsTab(onOpen: _openChat);
      case 3:
        return CallsTab(key: callsKey);
      case 4:
        return const SettingsTab();
      default:
        return ChatsTab(
          key: chatsKey,
          onOpenChat: _openChat,
          openChatId: chatId,
          onNewChat: () => setState(() => index = 1),
        );
    }
  }

  // ---------- Чат (третья колонка) ----------
  Widget _chatColumn() {
    if (chatId == null) {
      return EmptyState(
        icon: Icons.forum_outlined,
        title: 'Выберите чат',
        subtitle: 'Откройте диалог слева или создайте новый.',
        accent: LuxeColors.tgBlue,
      );
    }
    return SplitChatScreen(
      chatId: chatId!,
      title: chatTitle ?? '',
      kind: chatKind ?? 'direct',
      avatarUrl: chatAvatar,
      onClose: _closeChat,
      onToggleInfo: () => setState(() => infoOpen = !infoOpen),
      onChanged: () => chatsKey.currentState?.reload(),
    );
  }

  // ---------- Мобильный режим ----------
  Widget _mobile() {
    return Scaffold(
      key: scaffoldKey,
      drawer: LuxeDrawer(
        profile: myProfile,
        index: index,
        onSelect: (i) => setState(() => index = i),
      ),
      appBar: index == 0 && chatId != null
          ? null
          : AppBar(title: Text(_titleFor(index))),
      body: Stack(
        children: [
          if (index == 0 && chatId != null)
            SplitChatScreen(
              chatId: chatId!,
              title: chatTitle ?? '',
              kind: chatKind ?? 'direct',
              avatarUrl: chatAvatar,
              onClose: _closeChat,
              onToggleInfo: () {},
              onChanged: () => chatsKey.currentState?.reload(),
            )
          else
            _listColumn(),
          if (incomingOffer != null)
            IncomingCallCard(
              offer: incomingOffer!,
              onDismiss: _dismissIncoming,
            ),
        ],
      ),
    );
  }

  String _titleFor(int i) => switch (i) {
        1 => 'Контакты',
        2 => 'Каналы',
        3 => 'Звонки',
        4 => 'Настройки',
        _ => 'Luxe',
      };
}

/// Панель канала с логикой подписки и смены аватара.
class _ChannelInfoHost extends StatefulWidget {
  final String chatId;
  final String title;
  final String kind;
  final VoidCallback onClose;
  final VoidCallback onChanged;

  const _ChannelInfoHost({
    required this.chatId,
    required this.title,
    required this.kind,
    required this.onClose,
    required this.onChanged,
  });

  @override
  State<_ChannelInfoHost> createState() => _ChannelInfoHostState();
}

class _ChannelInfoHostState extends State<_ChannelInfoHost> {
  String? avatar;
  String description = '';
  int subs = 0;
  bool subscribed = false;
  bool isCreator = false;

  @override
  void initState() {
    super.initState();
    avatar = widget.kind == 'channel' ? null : null;
    _load();
  }

  @override
  void didUpdateWidget(covariant _ChannelInfoHost old) {
    super.didUpdateWidget(old);
    if (old.chatId != widget.chatId) _load();
  }

  Future<void> _load() async {
    final row = await supabase
        .from('chats')
        .select('created_by, description, avatar_url')
        .eq('id', widget.chatId)
        .maybeSingle();
    subs = await ChatService.memberCount(widget.chatId);
    subscribed = await ChatService.isSubscribed(widget.chatId);
    if (!mounted) return;
    final m = row == null ? null : Map<String, dynamic>.from(row as Map);
    setState(() {
      isCreator = m?['created_by'] == AuthService.myId;
      description = (m?['description'] ?? '') as String;
      avatar = m?['avatar_url'] as String?;
    });
  }

  Future<void> _changeAvatar() async {
    final f = await MediaService.pickImage();
    if (f == null) return;
    final url = await MediaService.uploadChatAvatar(widget.chatId, f);
    await ChatService.updateChat(widget.chatId, {'avatar_url': url});
    setState(() => avatar = url);
    widget.onChanged();
  }

  Future<void> _toggleSub() async {
    if (subscribed) {
      await ChatService.removeMember(widget.chatId, AuthService.myId);
      setState(() {
        subscribed = false;
        subs = (subs - 1).clamp(0, 99999);
      });
    } else {
      await ChatService.addMember(widget.chatId, AuthService.myId);
      setState(() {
        subscribed = true;
        subs += 1;
      });
    }
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    return ChannelInfoPanel(
      title: widget.title,
      subscribers: subs,
      avatarUrl: avatar,
      description: description,
      isChannel: widget.kind == 'channel',
      subscribed: subscribed,
      isCreator: isCreator,
      onClose: widget.onClose,
      onToggleSub: _toggleSub,
      onAvatarTap: isCreator ? _changeAvatar : null,
    );
  }
}

/// Подписка на входящие звонки через Realtime.
class CallServiceListen {
  static RealtimeChannel listenIncoming(
      void Function(Map<String, dynamic>) onOffer) {
    final ch = supabase.channel(
        'incoming:${AuthService.myId}_${DateTime.now().millisecondsSinceEpoch}');
    ch
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'call_signals',
          callback: (payload) {
            final row = payload.newRecord;
            if (row['callee_id'] == AuthService.myId &&
                row['type'] == 'offer') {
              onOffer(row);
            }
          },
        )
        .subscribe();
    return ch;
  }
}

/// Карточка входящего звонка поверх экрана.
class IncomingCallCard extends StatelessWidget {
  final Map<String, dynamic> offer;
  final VoidCallback onDismiss;
  const IncomingCallCard(
      {super.key, required this.offer, required this.onDismiss});

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Positioned(
      top: 8,
      left: 12,
      right: 12,
      child: Material(
        elevation: 8,
        borderRadius: BorderRadius.circular(20),
        color: dark ? LuxeColors.darkCard : Colors.white,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(colors: [
                    LuxeColors.online,
                    Color(0xFF8FE38F),
                  ]),
                ),
                child: const Icon(Icons.call, color: Colors.white, size: 22),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Входящий звонок',
                        style: TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 16)),
                    Text('Нажмите «Ответить», чтобы принять'),
                  ],
                ),
              ),
              IconButton(
                // Отклонение должно уйти звонящему, иначе он висит
                // до таймаута в 30 секунд, думая, что звонок ещё идёт.
                onPressed: () async {
                  try {
                    await supabase.from('call_signals').insert({
                      'caller_id': AuthService.myId,
                      'callee_id': offer['caller_id'] as String,
                      'chat_id': offer['chat_id'] as String,
                      'type': 'reject',
                      'payload': {},
                    });
                  } catch (_) {}
                  onDismiss();
                },
                icon: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(colors: [
                      LuxeColors.danger,
                      Color(0xFFFF8A5C),
                    ]),
                  ),
                  child:
                      const Icon(Icons.call_end, color: Colors.white, size: 20),
                ),
              ),
              const SizedBox(width: 4),
              CoolButton(
                icon: Icons.call_rounded,
                label: 'Ответить',
                onTap: () async {
                  final id = offer['chat_id'] as String;
                  // Навигатор захватываем ДО onDismiss: после скрытия
                  // карточки её context отсоединяется от дерева, и
                  // проверка mounted ниже всегда даёт false — экран
                  // звонка просто не открывался.
                  final nav = Navigator.of(context);

                  var title = '';
                  String? avatar;
                  try {
                    final row = await supabase
                        .from('profiles')
                        .select('display_name, username, avatar_url')
                        .eq('id', offer['caller_id'] as String)
                        .maybeSingle();
                    if (row != null) {
                      final m = Map<String, dynamic>.from(row as Map);
                      title = (m['display_name'] ?? m['username'] ?? '')
                          as String;
                      avatar = m['avatar_url'] as String?;
                    }
                  } catch (_) {}

                  onDismiss();
                  nav.push(
                    MaterialPageRoute(
                        builder: (_) => CallScreen(
                              chatId: id,
                              calleeId: '',
                              title: title,
                              avatarUrl: avatar,
                              incomingOffer: offer,
                              video: true,
                            )),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}