import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:url_launcher/url_launcher.dart';
import '../main.dart';
import '../services/auth_service.dart';
import '../services/chat_service.dart';
import '../services/media_service.dart';
import '../theme/luxe_theme.dart';
import '../widgets/luxe_widgets.dart';
import 'call_screen.dart';
import 'group_info_screen.dart';

class ChatScreen extends StatefulWidget {
  final String chatId;
  final String title;
  final Map<String, dynamic>? incomingOffer;
  const ChatScreen(
      {super.key,
      required this.chatId,
      required this.title,
      this.incomingOffer});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  List<Map<String, dynamic>> msgs = [];
  final input = TextEditingController();
  final scroll = ScrollController();
  RealtimeChannel? msgCh;
  String otherId = '';
  String otherStatus = '';
  String kind = 'direct';
  int memberCount = 0;

  @override
  void initState() {
    super.initState();
    _init();
    if (widget.incomingOffer != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
              builder: (_) => CallScreen(
                    chatId: widget.chatId,
                    calleeId: '',
                    incomingOffer: widget.incomingOffer,
                    video: true,
                  )),
        );
      });
    }
  }

  Future<void> _init() async {
    msgs = await ChatService.messages(widget.chatId);
    otherId = await ChatService.otherUserId(widget.chatId);
    if (otherId.isNotEmpty) {
      final p = await supabase
          .from('profiles')
          .select('status')
          .eq('id', otherId)
          .maybeSingle();
      if (p != null) otherStatus = (p as Map)['status'] ?? '';
    } else {
      final row = await supabase
          .from('chats')
          .select('is_group, kind')
          .eq('id', widget.chatId)
          .maybeSingle();
      if (row != null) {
        final m = Map<String, dynamic>.from(row as Map);
        kind = ChatService.chatKind(m);
        if (kind == 'group') {
          memberCount = await ChatService.memberCount(widget.chatId);
        }
      }
    }
    if (mounted) setState(() {});
    _scrollDown();
    await ChatService.markAsRead(widget.chatId);
    msgCh = supabase.channel('msg:${widget.chatId}');
    msgCh!
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'messages',
          callback: (payload) {
            if (payload.newRecord['chat_id'] == widget.chatId) {
              setState(() => msgs.add(payload.newRecord));
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
    msgCh?.unsubscribe();
    input.dispose();
    scroll.dispose();
    super.dispose();
  }

  Future<void> send() async {
    final text = input.text;
    input.clear();
    await ChatService.sendText(widget.chatId, text);
  }

  Future<void> _attachFile() async {
    final file = await MediaService.pickAnyFile();
    if (file == null) return;
    final url = await MediaService.uploadFile(file);
    await ChatService.sendFile(widget.chatId, url, file.name);
  }

  void openCall(bool video) {
    if (otherId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Это групповой чат, звонки только в личке')));
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(
          builder: (_) =>
              CallScreen(chatId: widget.chatId, calleeId: otherId, video: video)),
    );
  }

  String _plural(int n) {
    if (n % 10 == 1 && n % 100 != 11) return 'участник';
    if ([2, 3, 4].contains(n % 10) && ![12, 13, 14].contains(n % 100)) {
      return 'участника';
    }
    return 'участников';
  }

  @override
  Widget build(BuildContext context) {
    final myId = AuthService.myId;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: GestureDetector(
          onTap: kind == 'group'
              ? () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => GroupInfoScreen(
                            chatId: widget.chatId,
                            onChanged: () => _init())),
                  ).then((_) => _init())
              : null,
          child: Row(
            children: [
              GradientAvatar(name: widget.title, radius: 19),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.title,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 17)),
                    if (otherStatus.isNotEmpty)
                      Text(
                        otherStatus == 'online'
                            ? 'в сети'
                            : otherStatus == 'busy'
                                ? 'занят(а)'
                                : 'был(а) недавно',
                        style: TextStyle(
                          fontSize: 12,
                          color: otherStatus == 'online'
                              ? LuxeColors.online
                              : Colors.white70,
                        ),
                      ),
                    if (kind == 'group')
                      Text('$memberCount ${_plural(memberCount)} • нажмите для инфо',
                          style: const TextStyle(
                              fontSize: 12, color: Colors.white70)),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          IconButton(
              tooltip: 'Аудиозвонок',
              icon: const Icon(Icons.call_rounded),
              onPressed: () => openCall(false)),
          IconButton(
              tooltip: 'Видеозвонок',
              icon: const Icon(Icons.videocam_rounded),
              onPressed: () => openCall(true)),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Container(
              color: dark ? LuxeColors.darkBg : const Color(0xFFE7EBF0),
              child: msgs.isEmpty
                  ? Center(
                      child: Text('Сообщений пока нет',
                          style: TextStyle(
                              color: dark
                                  ? Colors.white54
                                  : Colors.black54)))
                  : ListView.builder(
                      controller: scroll,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 8),
                      itemCount: msgs.length,
                      itemBuilder: (context, i) {
                        final m = msgs[i];
                        final mine = m['sender_id'] == myId;
                        return GestureDetector(
                          onLongPress: mine ? () async {
                            final confirm = await showDialog<bool>(
                              context: context,
                              builder: (_) => AlertDialog(
                                title: const Text('Удалить сообщение?'),
                                actions: [
                                  TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Отмена')),
                                  TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Удалить', style: TextStyle(color: Colors.red))),
                                ],
                              ),
                            );
                            if (confirm == true && m['id'] != null) {
                              await ChatService.deleteMessage(m['id'] as String);
                              setState(() => msgs.removeWhere((msg) => msg['id'] == m['id']));
                            }
                          } : null,
                          child: Align(
                            alignment: mine
                              ? Alignment.centerRight
                              : Alignment.centerLeft,
                          child: Container(
                            margin: const EdgeInsets.symmetric(vertical: 2),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 8),
                            constraints: BoxConstraints(
                                maxWidth:
                                    MediaQuery.of(context).size.width * 0.75),
                            decoration: BoxDecoration(
                              color: mine
                                  ? LuxeColors.bubbleOut
                                  : (dark
                                      ? LuxeColors.bubbleIn
                                      : Colors.white),
                              borderRadius: BorderRadius.only(
                                topLeft: const Radius.circular(16),
                                topRight: const Radius.circular(16),
                                bottomLeft: Radius.circular(mine ? 16 : 4),
                                bottomRight: Radius.circular(mine ? 4 : 16),
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.15),
                                  blurRadius: 3,
                                  offset: const Offset(0, 1),
                                ),
                              ],
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (m['type'] == 'file' && m['file_url'] != null)
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          const Icon(Icons.insert_drive_file, size: 18, color: Colors.white70),
                                          const SizedBox(width: 6),
                                          Expanded(
                                            child: Text(
                                              m['content'] ?? 'Файл',
                                              style: TextStyle(
                                                color: mine || dark ? Colors.white : Colors.black87,
                                                fontSize: 15,
                                                decoration: TextDecoration.underline,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 4),
                                      InkWell(
                                        onTap: () async {
                                          final url = m['file_url'] as String;
                                          if (await canLaunchUrl(Uri.parse(url))) {
                                            await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
                                          } else {
                                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Не удалось открыть: $url')));
                                          }
                                        },
                                        child: Text('Открыть файл →',
                                            style: TextStyle(
                                                color: mine || dark ? Colors.white70 : Colors.black54,
                                                fontSize: 12,
                                                decoration: TextDecoration.underline)),
                                      ),
                                    ],
                                  )
                                else
                                  Text(m['content'] ?? '',
                                      style: TextStyle(
                                          color: mine || dark
                                              ? Colors.white
                                              : Colors.black87,
                                          fontSize: 15)),
                                 const SizedBox(height: 2),
                                 Text(
                                   timeago.format(DateTime.parse(m['created_at']).toLocal(), locale: 'ru'),
                                   style: TextStyle(
                                       color: mine || dark ? Colors.white54 : Colors.black45,
                                       fontSize: 10),
                                 ),
                               ],
                             ),
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
              padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
              child: Row(
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
                        minLines: 1,
                        maxLines: 4,
                        decoration: const InputDecoration(
                          hintText: 'Сообщение...',
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.symmetric(
                              horizontal: 18, vertical: 12),
                        ),
                        onSubmitted: (_) => send(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.attach_file_rounded, size: 22),
                    onPressed: _attachFile,
                    tooltip: 'Прикрепить файл',
                  ),
                  const SizedBox(width: 4),
                  SendButton(onTap: send),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
