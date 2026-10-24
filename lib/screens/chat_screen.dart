import 'dart:io';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../main.dart';
import '../services/auth_service.dart';
import '../services/chat_service.dart';
import '../services/media_service.dart';
import '../services/sticker_service.dart';
import '../theme/luxe_theme.dart';
import '../widgets/luxe_widgets.dart';
import '../widgets/sticker_view.dart';
import '../widgets/video_circle.dart';
import '../widgets/voice_message.dart';
import 'call_screen.dart';
import 'chat_composer.dart';
import 'group_info_screen.dart';
import 'sticker_panel.dart';
import 'stickers_screen.dart';

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
                    title: widget.title,
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

  Future<void> _attachPhoto() async {
    final f = await MediaService.pickPhoto();
    if (f == null) return;
    final name = f.name.isEmpty ? 'photo.jpg' : f.name;
    final url = await MediaService.uploadPhoto(f);
    await ChatService.sendFile(widget.chatId, url, name, type: 'image');
  }

  Future<void> _attachVideo() async {
    final f = await MediaService.pickVideo();
    if (f == null) return;
    final name = f.name.isEmpty ? 'video.mp4' : f.name;
    final url = await MediaService.uploadVideo(f);
    await ChatService.sendFile(widget.chatId, url, name, type: 'video');
  }

  /// Отправить записанное голосовое.
  Future<void> _sendVoice(File file, int seconds, String waveform) async {
    try {
      final url = await MediaService.uploadVoice(file);
      await ChatService.sendVoice(widget.chatId, url, seconds, waveform);
    } catch (e) {
      if (mounted) _toast('Не удалось отправить голосовое');
    }
  }

  /// Отправить записанный кружок.
  Future<void> _sendCircle(File file, int seconds) async {
    try {
      final url = await MediaService.uploadCircle(file);
      await ChatService.sendCircle(widget.chatId, url, seconds);
    } catch (e) {
      if (mounted) _toast('Не удалось отправить кружок');
    }
  }

  /// Отправить стикер из панели.
  Future<void> _sendSticker(Sticker s) async {
    final saved = await StickerService.send(widget.chatId, s);
    if (!mounted) return;
    if (saved == null) _toast('Не удалось отправить стикер');
  }

  Future<void> _markVoicePlayed(Map<String, dynamic> m) async {
    if (m['id'] == null) return;
    setState(() => m['heard'] = true);
    try {
      await supabase
          .from('messages')
          .update({'status': 'read'})
          .eq('id', m['id']);
    } catch (_) {}
  }

  void _toast(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
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
          builder: (_) => CallScreen(
              chatId: widget.chatId,
              calleeId: otherId,
              title: widget.title,
              video: video)),
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
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        elevation: 0,
        backgroundColor: dark ? LuxeColors.darkCard : Colors.white,
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
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(widget.title,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w600)),
                    if (kind == 'group')
                      Text('$memberCount ${_plural(memberCount)}',
                          style: TextStyle(
                              fontSize: 12, color: scheme.onSurfaceVariant))
                    else if (otherStatus.isNotEmpty)
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
                                : scheme.onSurfaceVariant),
                      ),
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
          const SizedBox(width: 4),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Container(
              color: dark ? LuxeColors.deepDark : const Color(0xFFE7EBF0),
              child: msgs.isEmpty
                  ? Center(
                      child: Text('Сообщений пока нет',
                          style: TextStyle(color: scheme.onSurfaceVariant)))
                  : ListView.builder(
                      controller: scroll,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 12),
                      itemCount: msgs.length,
                      itemBuilder: (context, i) {
                        final m = msgs[i];
                        final isMine = m['sender_id'] == myId;
                        final date = DateTime.parse(m['created_at']).toLocal();

                        var showDate = true;
                        if (i > 0) {
                          final prev =
                              DateTime.parse(msgs[i - 1]['created_at']).toLocal();
                          if (date.year == prev.year &&
                              date.month == prev.month &&
                              date.day == prev.day) {
                            showDate = false;
                          }
                        }

                        return Column(
                          children: [
                            if (showDate) _DateSeparator(date: date, dark: dark),
                            _MessageBubble(
                              message: m,
                              isMine: isMine,
                              dark: dark,
                              onLongPress: isMine ? () => _confirmDelete(m) : null,
                              onVoicePlayed: () => _markVoicePlayed(m),
                            ),
                          ],
                        );
                      },
                    ),
            ),
          ),
          _buildComposer(dark),
        ],
      ),
    );
  }

  // Подтверждение удаления своего сообщения (долгое нажатие).
  Future<void> _confirmDelete(Map<String, dynamic> m) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Удалить сообщение?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Отмена')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child:
                  const Text('Удалить', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (confirm == true && m['id'] != null) {
      await ChatService.deleteMessage(m['id'] as String);
      setState(() => msgs.removeWhere((msg) => msg['id'] == m['id']));
    }
  }

  // Нижняя панель ввода: контейнер с тенью, «парящий» над фоном.
  Widget _buildComposer(bool dark) {
    return Container(
      decoration: BoxDecoration(
        color: dark ? LuxeColors.darkCard : Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(dark ? 0.25 : 0.08),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        child: ChatComposer(
          controller: input,
          dark: dark,
          isChannel: false,
          onSend: send,
          onVoiceReady: _sendVoice,
          onCircleReady: _sendCircle,
          onSticker: _sendSticker,
          onAddSticker: () async {
            final ok = await showAddStickerDialog(context);
            if (ok && mounted) setState(() {});
          },
          onOpenAllStickers: () {
            Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const StickersScreen()));
          },
          onAttachPhoto: _attachPhoto,
          onAttachVideo: _attachVideo,
          onAttachFile: _attachFile,
        ),
      ),
    );
  }
}

// ------------------- Вспомогательные виджеты -------------------

// Плашка с датой между группами сообщений: «Сегодня», «Вчера», «24 октября».
class _DateSeparator extends StatelessWidget {
  final DateTime date;
  final bool dark;
  const _DateSeparator({required this.date, required this.dark});

  static const _months = [
    'января', 'февраля', 'марта', 'апреля', 'мая', 'июня',
    'июля', 'августа', 'сентября', 'октября', 'ноября', 'декабря',
  ];

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    String label;
    if (_sameDay(date, now)) {
      label = 'Сегодня';
    } else if (_sameDay(date, now.subtract(const Duration(days: 1)))) {
      label = 'Вчера';
    } else {
      label = '${date.day} ${_months[date.month - 1]}';
      if (date.year != now.year) label += ' ${date.year}';
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: dark
                ? Colors.white.withOpacity(0.07)
                : Colors.black.withOpacity(0.06),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: dark ? Colors.white60 : Colors.black54,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}

// Пузырь сообщения: свои — с неоновым градиентом, чужие — тёмные/белые.
class _MessageBubble extends StatelessWidget {
  final Map<String, dynamic> message;
  final bool isMine;
  final bool dark;
  final VoidCallback? onLongPress;
  final VoidCallback? onVoicePlayed;

  const _MessageBubble({
    required this.message,
    required this.isMine,
    required this.dark,
    this.onLongPress,
    this.onVoicePlayed,
  });

  @override
  Widget build(BuildContext context) {
    final type = message['type'] as String?;
    final content = message['content'] as String?;
    final createdAt = DateTime.parse(message['created_at']).toLocal();
    final time =
        '${createdAt.hour.toString().padLeft(2, '0')}:${createdAt.minute.toString().padLeft(2, '0')}';
    // Ссылки, записанные во времена прокси, чиним на лету: адрес
    // сменился, а в базе остался старый.
    final fileUrl = MediaService.fixUrl(message['file_url'] as String?);
    final hasFile = fileUrl != null && fileUrl.isNotEmpty;

    Widget bubble;
    if (type == 'sticker' && hasFile) {
      // Стикер показываем без пузыря, как в Telegram.
      bubble = StickerView(
          url: fileUrl, kind: MediaService.stickerKind(fileUrl), size: 124);
    } else {
      bubble = Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          gradient: isMine ? LuxeColors.bubbleOutGradient : null,
          color: isMine ? null : (dark ? LuxeColors.bubbleIn : Colors.white),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(18),
            topRight: const Radius.circular(18),
            bottomLeft: Radius.circular(isMine ? 18 : 4),
            bottomRight: Radius.circular(isMine ? 4 : 18),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(dark ? 0.3 : 0.12),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: _content(context, type, content, fileUrl),
      );
    }

    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onLongPress: onLongPress,
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 2, horizontal: 4),
          constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.75),
          child: Column(
            crossAxisAlignment:
                isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: [
              bubble,
              const SizedBox(height: 2),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(time,
                      style: TextStyle(
                          fontSize: 10,
                          color: dark ? Colors.white38 : Colors.black38)),
                  if (isMine) ...[
                    const SizedBox(width: 3),
                    Icon(
                      message['status'] == 'read'
                          ? Icons.done_all_rounded
                          : Icons.done_rounded,
                      size: 13,
                      color: message['status'] == 'read'
                          ? LuxeColors.neonBlue
                          : (dark ? Colors.white38 : Colors.black38),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _content(
      BuildContext context, String? type, String? content, String? fileUrl) {
    if (type == 'voice' && fileUrl != null && fileUrl.isNotEmpty) {
      return VoiceMessage(
        url: fileUrl,
        waveform: message['waveform'] as String?,
        durationSeconds: (message['duration'] as num?)?.toInt() ?? 0,
        mine: isMine,
        dark: dark,
        played: message['heard'] == true || message['status'] == 'read',
        onPlayed: onVoicePlayed,
      );
    }

    if (type == 'circle' && fileUrl != null && fileUrl.isNotEmpty) {
      return VideoCircle(
        url: fileUrl,
        durationSeconds: (message['duration'] as num?)?.toInt() ?? 0,
        mine: isMine,
      );
    }

    if (type == 'file' && fileUrl != null && fileUrl.isNotEmpty) {
      return InkWell(
        onTap: () async {
          final uri = Uri.parse(fileUrl);
          if (await canLaunchUrl(uri)) {
            await launchUrl(uri, mode: LaunchMode.externalApplication);
          } else if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Не удалось открыть: $fileUrl')));
          }
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.insert_drive_file_rounded,
                    size: 18,
                    color: isMine ? Colors.white70 : LuxeColors.neonBlue),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    content ?? 'Файл',
                    style: TextStyle(
                        color: isMine || dark ? Colors.white : Colors.black87,
                        fontSize: 15),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text('Открыть файл →',
                style: TextStyle(
                    fontSize: 12,
                    color: isMine
                        ? Colors.white70
                        : (dark ? Colors.white60 : Colors.black54))),
          ],
        ),
      );
    }

    return Text(
      content ?? '',
      style: TextStyle(
          color: isMine || dark ? Colors.white : Colors.black87, fontSize: 15),
    );
  }
}
