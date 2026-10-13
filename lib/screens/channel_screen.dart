import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:timeago/timeago.dart' as timeago;
import '../main.dart';
import '../services/auth_service.dart';
import '../services/chat_service.dart';
import '../theme/luxe_theme.dart';
import '../widgets/luxe_widgets.dart';

/// Канал в стиле Telegram: аватарка, описание, подписчики.
/// Постит только админ (создатель), остальные читают и подписываются.
class ChannelScreen extends StatefulWidget {
  final String chatId;
  final String title;
  const ChannelScreen({super.key, required this.chatId, required this.title});

  @override
  State<ChannelScreen> createState() => _ChannelScreenState();
}

class _ChannelScreenState extends State<ChannelScreen> {
  List<Map<String, dynamic>> posts = [];
  final input = TextEditingController();
  final scroll = ScrollController();
  RealtimeChannel? sub;
  Map<String, dynamic>? channel;
  int subs = 0;
  bool subscribed = true;
  bool loading = true;

  bool get isAdmin => channel != null && channel!['created_by'] == AuthService.myId;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final row = await supabase
        .from('chats')
        .select()
        .eq('id', widget.chatId)
        .maybeSingle();
    if (row != null) channel = Map<String, dynamic>.from(row as Map);
    posts = await ChatService.messages(widget.chatId);
    subs = await ChatService.memberCount(widget.chatId);
    subscribed = await ChatService.isSubscribed(widget.chatId);
    if (mounted) setState(() => loading = false);
    _scrollDown();
    sub = supabase.channel('chan:${widget.chatId}');
    sub!
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'messages',
          callback: (payload) {
            if (payload.newRecord['chat_id'] == widget.chatId) {
              setState(() => posts.add(payload.newRecord));
              _scrollDown();
            }
          },
        )
        .subscribe();
  }

  void _scrollDown() {
    Future.delayed(const Duration(milliseconds: 200), () {
      if (scroll.hasClients) {
        scroll.animateTo(scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOut);
      }
    });
  }

  @override
  void dispose() {
    sub?.unsubscribe();
    input.dispose();
    scroll.dispose();
    super.dispose();
  }

  Future<void> _post() async {
    final text = input.text;
    input.clear();
    await ChatService.sendText(widget.chatId, text);
  }

  Future<void> _toggleSub() async {
    if (subscribed) {
      await ChatService.removeMember(widget.chatId, AuthService.myId);
      if (mounted) Navigator.pop(context);
    } else {
      await ChatService.addMember(widget.chatId, AuthService.myId);
      setState(() {
        subscribed = true;
        subs += 1;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final avatar = channel?['avatar_url'] as String?;
    final desc = (channel?['description'] ?? '') as String;
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Row(
          children: [
            avatar != null && avatar.isNotEmpty
                ? CircleAvatar(radius: 19, backgroundImage: NetworkImage(avatar))
                : Container(
                    width: 38,
                    height: 38,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(colors: [
                        LuxeColors.tgBlue,
                        Color(0xFF7A5AF8)
                      ]),
                    ),
                    child: const Icon(Icons.campaign_rounded,
                        color: Colors.white, size: 20),
                  ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.title,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 17)),
                  Text('$subs ${_plural(subs)}',
                      style: const TextStyle(
                          fontSize: 12, color: Colors.white70)),
                ],
              ),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          if (desc.isNotEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              color: dark ? LuxeColors.darkCard : Colors.white,
              child: Text(desc,
                  style: TextStyle(
                      color: dark ? Colors.white70 : Colors.black87)),
            ),
          Expanded(
            child: Container(
              color: dark ? LuxeColors.darkBg : const Color(0xFFE7EBF0),
              child: loading
                  ? const Center(child: CircularProgressIndicator())
                  : posts.isEmpty
                      ? Center(
                          child: Text('Пока нет постов 📢',
                              style: TextStyle(
                                  color: dark
                                      ? Colors.white54
                                      : Colors.black54)))
                      : ListView.builder(
                          controller: scroll,
                          padding: const EdgeInsets.all(10),
                          itemCount: posts.length,
                          itemBuilder: (context, i) {
                            final p = posts[i];
                            return Card(
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14)),
                              color: dark ? LuxeColors.bubbleIn : Colors.white,
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        const Icon(Icons.campaign_rounded,
                                            size: 16,
                                            color: LuxeColors.tgBlue),
                                        const SizedBox(width: 6),
                                        Expanded(
                                            child: Text(widget.title,
                                                style: const TextStyle(
                                                    fontWeight:
                                                        FontWeight.bold,
                                                    color:
                                                        LuxeColors.tgBlue))),
                                      ],
                                    ),
                                    const SizedBox(height: 6),
                                    Text(p['content'] ?? '',
                                        style: TextStyle(
                                            fontSize: 15,
                                            color: dark
                                                ? Colors.white
                                                : Colors.black87)),
                                    const SizedBox(height: 4),
                                    Align(
                                      alignment: Alignment.centerRight,
                                      child: Text(
                                        timeago.format(
                                            DateTime.parse(p['created_at'])
                                                .toLocal(),
                                            locale: 'ru'),
                                        style: TextStyle(
                                            fontSize: 11,
                                            color: dark
                                                ? Colors.white54
                                                : Colors.black45),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
            ),
          ),
          SafeArea(
            child: Container(
              color: dark ? LuxeColors.darkCard : Colors.white,
              padding: const EdgeInsets.all(10),
              child: isAdmin
                  ? Row(
                      children: [
                        Expanded(
                          child: Container(
                            decoration: BoxDecoration(
                              color: dark
                                  ? LuxeColors.darkField
                                  : Colors.grey.shade200,
                              borderRadius: BorderRadius.circular(26),
                            ),
                            child: TextField(
                              controller: input,
                              decoration: const InputDecoration(
                                hintText: 'Новый пост...',
                                border: InputBorder.none,
                                contentPadding: EdgeInsets.symmetric(
                                    horizontal: 18, vertical: 12),
                              ),
                              onSubmitted: (_) => _post(),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        SendButton(onTap: _post),
                      ],
                    )
                  : SizedBox(
                      width: double.infinity,
                      child: CoolButton(
                        icon: subscribed
                            ? Icons.notifications_off_outlined
                            : Icons.notifications_active_rounded,
                        label: subscribed
                            ? 'Отписаться'
                            : 'Подписаться',
                        color: subscribed ? Colors.grey.shade600 : LuxeColors.tgBlue,
                        onTap: _toggleSub,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  String _plural(int n) {
    if (n % 10 == 1 && n % 100 != 11) return 'подписчик';
    if ([2, 3, 4].contains(n % 10) && ![12, 13, 14].contains(n % 100)) {
      return 'подписчика';
    }
    return 'подписчиков';
  }
}
