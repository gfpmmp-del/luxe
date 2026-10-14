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
import '../widgets/ticks.dart';
import '../widgets/verified_badge.dart';
import 'call_screen.dart';
import 'group_info_screen.dart';

/// Центральная колонка: открытый чат / группа / канал.
class SplitChatScreen extends StatefulWidget {
  final String chatId;
  final String title;
  final String kind;
  final String? avatarUrl;
  final VoidCallback onClose;
  final VoidCallback onToggleInfo;
  final VoidCallback onChanged;

  const SplitChatScreen({
    super.key,
    required this.chatId,
    required this.title,
    required this.kind,
    required this.onClose,
    required this.onToggleInfo,
    required this.onChanged,
    this.avatarUrl,
  });

  @override
  State<SplitChatScreen> createState() => _SplitChatScreenState();
}

class _SplitChatScreenState extends State<SplitChatScreen> {
  List<Map<String, dynamic>> msgs = [];
  final input = TextEditingController();
  final scroll = ScrollController();
  RealtimeChannel? msgCh;
  String otherId = '';
  String otherStatus = '';
  String? _avatar;
  String? _description;
  int memberCount = 0;
  bool canPost = true;
  bool otherVerified = false;

  @override
  void initState() {
    super.initState();
    _avatar = widget.avatarUrl;
    _init();
  }

  @override
  void didUpdateWidget(covariant SplitChatScreen old) {
    super.didUpdateWidget(old);
    if (old.chatId != widget.chatId) {
      _avatar = widget.avatarUrl;
      _init();
    }
  }

  Future<void> _init() async {
    // Старая подписка должна быть закрыта, иначе события дублируются
    // (баг: сообщения приходили по 2-3 раза при смене чата)
    await msgCh?.unsubscribe();
    msgCh = null;

    try {
      await _loadChat();
    } catch (e) {
      debugPrint('Чат не загрузился: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Не удалось загрузить чат: $e')),
        );
      }
      _listen();
    }
  }

  Future<void> _loadChat() async {
    msgs = await ChatService.messages(widget.chatId);
    otherId = await ChatService.otherUserId(widget.chatId);
    if (otherId.isNotEmpty) {
      final p = await supabase
          .from('profiles')
          .select('status, avatar_url, verified')
          .eq('id', otherId)
          .maybeSingle();
      if (p != null) {
        final m = Map<String, dynamic>.from(p as Map);
        otherStatus = m['status'] ?? '';
        otherVerified = m['verified'] == true;
        if (_avatar == null) _avatar = m['avatar_url'] as String?;
      }
    } else {
      final row = await supabase
          .from('chats')
          .select('created_by, description, avatar_url, kind')
          .eq('id', widget.chatId)
          .maybeSingle();
      if (row != null) {
        final m = Map<String, dynamic>.from(row as Map);
        _description = m['description'] as String?;
        if (_avatar == null) _avatar = m['avatar_url'] as String?;
        canPost = widget.kind != 'channel' ||
            m['created_by'] == AuthService.myId;
      }
      if (widget.kind == 'group') {
        memberCount = await ChatService.memberCount(widget.chatId);
      }
    }
    if (mounted) setState(() {});
    _scrollDown();
    try {
      await ChatService.markAsRead(widget.chatId);
    } catch (e) {
      debugPrint('Не удалось отметить прочитанным: $e');
    }
    _listen();
  }

  /// Подписка на сообщения: INSERT — новое сообщение, UPDATE — прочитано/доставлено.
  void _listen() {
    final chatId = widget.chatId;
    msgCh = supabase.channel('msg:$chatId:${DateTime.now().microsecondsSinceEpoch}')
      ..onPostgresChanges(
        event: PostgresChangeEvent.insert,
        schema: 'public',
        table: 'messages',
        callback: (payload) {
          if (payload.newRecord['chat_id'] != chatId) return;
          if (!mounted) return;
          // Защита от дублей: сверяемся с уже загруженными по id
          final id = payload.newRecord['id'];
          if (msgs.any((m) => m['id'] == id)) return;
          setState(() => msgs.add(Map<String, dynamic>.from(payload.newRecord)));
          _scrollDown();
        },
      )
      ..onPostgresChanges(
        event: PostgresChangeEvent.update,
        schema: 'public',
        table: 'messages',
        callback: (payload) {
          if (payload.newRecord['chat_id'] != chatId) return;
          if (!mounted) return;
          final id = payload.newRecord['id'];
          setState(() {
            for (final m in msgs) {
              if (m['id'] == id) {
                m['status'] = payload.newRecord['status'];
              }
            }
          });
        },
      )
      ..subscribe();
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
    final text = input.text.trim();
    if (text.isEmpty) return;
    input.clear();
    final pending = _addPending('text', text, null);
    try {
      final saved = await ChatService.sendText(widget.chatId, text);
      if (saved != null) _replacePending(pending, saved);
    } catch (e) {
      _markPendingFailed(pending);
    }
  }

  Future<void> _attachFile() async {
    final file = await MediaService.pickAnyFile();
    if (file == null) return;
    // Фото и видео отправляем с соответствующим типом, чтобы показывались сразу
    final type = MediaService.kindOf(file.name);
    final pending = _addPending(type, file.name, null);
    try {
      final url = await MediaService.uploadFile(file);
      final saved = await ChatService.sendFile(widget.chatId, url, file.name,
          type: type, caption: file.name);
      if (saved != null) {
        final size = await MediaService.remoteSize(url);
        if (size > 0) {
          try {
            await supabase
                .from('messages')
                .update({'file_size': size})
                .eq('id', saved['id']);
          } catch (_) {
            // Колонки file_size может не быть — не критично
          }
        }
        _replacePending(pending, {...saved, 'file_size': size});
      }
    } catch (e) {
      debugPrint('Не удалось отправить файл: $e');
      _markPendingFailed(pending);
      _showError('Не удалось отправить файл', e);
    }
  }

  /// Отправить фото из галереи — показывается сразу картинкой.
  Future<void> _attachPhoto() async {
    final f = await MediaService.pickPhoto();
    if (f == null) return;
    final name = f.name.isEmpty ? 'photo.jpg' : f.name;
    final pending = _addPending('image', name, null);
    try {
      final url = await MediaService.uploadPhoto(f);
      final caption = input.text.trim();
      input.clear();
      final saved = await ChatService.sendFile(widget.chatId, url, name,
          type: 'image', caption: caption);
      if (saved != null) _replacePending(pending, saved);
    } catch (e) {
      debugPrint('Не удалось отправить фото: $e');
      _markPendingFailed(pending);
      _showError('Не удалось отправить фото', e);
    }
  }

  /// Отправить видео из галереи.
  Future<void> _attachVideo() async {
    final f = await MediaService.pickVideo();
    if (f == null) return;
    final name = f.name.isEmpty ? 'video.mp4' : f.name;
    final pending = _addPending('video', name, null);
    try {
      final url = await MediaService.uploadVideo(f);
      final saved = await ChatService.sendFile(widget.chatId, url, name,
          type: 'video', caption: name);
      if (saved != null) _replacePending(pending, saved);
    } catch (e) {
      debugPrint('Не удалось отправить видео: $e');
      _markPendingFailed(pending);
      _showError('Не удалось отправить видео', e);
    }
  }

  /// Оптимистичное сообщение: показывается сразу со статусом 'sending'.
  Map<String, dynamic> _addPending(String type, String content, String? url) {
    final id = 'pending-${DateTime.now().microsecondsSinceEpoch}';
    final msg = <String, dynamic>{
      'id': id,
      'chat_id': widget.chatId,
      'sender_id': AuthService.myId,
      'content': content,
      'type': type,
      'file_url': url,
      'status': 'sending',
      'created_at': DateTime.now().toIso8601String(),
    };
    setState(() => msgs.add(msg));
    _scrollDown();
    return msg;
  }

  /// Заменяем временное сообщение настоящим (Realtime его тоже пришлёт — дедупликация по id).
  void _replacePending(Map<String, dynamic> pending, Map<String, dynamic> saved) {
    if (!mounted) return;
    setState(() {
      final i = msgs.indexWhere((m) => m['id'] == pending['id']);
      if (i != -1) msgs[i] = saved;
    });
  }

  void _markPendingFailed(Map<String, dynamic> pending) {
    if (!mounted) return;
    setState(() {
      final i = msgs.indexWhere((m) => m['id'] == pending['id']);
      if (i != -1) msgs[i]['status'] = 'failed';
    });
  }

  /// Показать причину ошибки — иначе в release она теряется в логах.
  void _showError(String title, Object e) {
    if (!mounted) return;
    final msg = e.toString();
    // Убираем технический префикс PostgREST, оставляем суть
    final clean = msg
        .replaceAll('Exception: ', '')
        .replaceAll('PostgrestException', '')
        .trim();
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('$title: $clean')));
  }

  void openCall(bool video) {
    if (otherId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Звонки доступны только в личных чатах')));
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(
          builder: (_) => CallScreen(
              chatId: widget.chatId,
              calleeId: otherId,
              title: widget.title,
              avatarUrl: _avatar,
              video: video)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final myId = AuthService.myId;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final isChannel = widget.kind == 'channel';
    final bg = LuxeTheme.channelPattern(Theme.of(context).brightness);

    return Scaffold(
      backgroundColor: dark ? LuxeColors.darkBg : const Color(0xFFE7EBF0),
      body: Column(
        children: [
          // Шапка
          Container(
            height: 58,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            color: dark ? LuxeColors.darkCard : Colors.white,
            child: Row(
              children: [
                IconButton(
                    onPressed: widget.onClose,
                    icon: const Icon(Icons.arrow_back)),
                GradientAvatar(
                    name: widget.title,
                    radius: 20,
                    imageUrl: _avatar),
                const SizedBox(width: 12),
                Expanded(
                  child: GestureDetector(
                    onTap: widget.onToggleInfo,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: UserName(
                                widget.title,
                                verified:
                                    widget.kind == 'direct' && otherVerified,
                                style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600),
                              ),
                            ),
                            if (widget.kind == 'direct')
                              _adminVerifyButton(),
                          ],
                        ),
                        Text(_subtitle(),
                            style: TextStyle(
                                fontSize: 12,
                                color: otherStatus == 'online'
                                    ? LuxeColors.online
                                    : Colors.grey)),
                      ],
                    ),
                  ),
                ),
                if (widget.kind == 'direct') ...[
                  IconButton(
                      tooltip: 'Аудиозвонок',
                      icon: const Icon(Icons.call_rounded),
                      onPressed: () => openCall(false)),
                  IconButton(
                      tooltip: 'Видеозвонок',
                      icon: const Icon(Icons.videocam_rounded),
                      onPressed: () => openCall(true)),
                ] else ...[
                  IconButton(
                    tooltip: 'Настройки',
                    icon: const Icon(Icons.tune_rounded),
                    onPressed: widget.onToggleInfo,
                  ),
                  IconButton(
                      tooltip: 'Информация',
                      icon: const Icon(Icons.info_outline_rounded),
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => GroupInfoScreen(
                                  chatId: widget.chatId,
                                  onChanged: () {
                                    _init();
                                    widget.onChanged();
                                  })),
                        ).then((_) {
                          _init();
                          widget.onChanged();
                        });
                      }),
                ],
              ],
            ),
          ),
          // Описание чата — только если оно реально задано
          if (_description != null && _description!.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: dark ? LuxeColors.darkCard : Colors.white,
              child: Row(
                children: [
                  Icon(isChannel
                      ? Icons.campaign_outlined
                      : Icons.info_outline_rounded,
                      size: 15,
                      color: LuxeColors.tgBlue),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _description!,
                      style: TextStyle(
                          fontSize: 13,
                          color: dark ? Colors.white70 : Colors.black87),
                    ),
                  ),
                ],
              ),
            ),
          // Сообщения
          Expanded(
            child: Container(
              color: isChannel
                  ? bg
                  : (dark ? LuxeColors.darkBg : const Color(0xFFE7EBF0)),
              child: LayoutBuilder(
                builder: (context, box) => ListView.builder(
                controller: scroll,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                itemCount: msgs.length,
                itemBuilder: (context, i) {
                  final m = msgs[i];
                  final mine = m['sender_id'] == myId;

                  // Разделитель даты перед каждым новым днём
                  final prev = i == 0 ? null : msgs[i - 1];
                  final newDay = prev == null ||
                      !_sameDay(_dateOf(prev), _dateOf(m));

                  Widget bubble = isChannel && !mine
                      ? _channelPost(context, m)
                      : Align(
                          alignment: mine
                              ? Alignment.centerRight
                              : Alignment.centerLeft,
                          child: _bubble(context, m, mine, dark,
                              box.maxWidth),
                        );

                  if (!newDay) return bubble;
                  return Column(
                    children: [
                      _dateSeparator(_dateOf(m), dark),
                      bubble,
                    ],
                  );
                },
              ),
              ),
            ),
          ),
          // Поле ввода (только если canPost) или кнопка подписки
          SafeArea(
            child: Container(
              color: dark ? LuxeColors.darkCard : Colors.white,
              padding: const EdgeInsets.all(10),
              child: canPost ? _inputRow(dark) : _subscribeRow(),
            ),
          ),
        ],
      ),
    );
  }

  /// Кнопка «сделать верифицированным» рядом с именем собеседника.
  Widget _adminVerifyButton() {
    if (otherId.isEmpty) return const SizedBox.shrink();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final active = otherVerified;
    return Padding(
      padding: const EdgeInsets.only(left: 8),
      child: InkWell(
        onTap: _toggleVerify,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            color: active
                ? LuxeColors.tgBlue
                : (isDark ? Colors.white10 : Colors.black12),
            border: Border.all(
              color: active
                  ? LuxeColors.tgBlue
                  : (isDark ? Colors.white24 : Colors.black26),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                active ? Icons.verified_rounded : Icons.verified_outlined,
                size: 14,
                color: active
                    ? Colors.white
                    : (isDark ? Colors.white70 : Colors.black54),
              ),
              const SizedBox(width: 4),
              Text(
                active ? 'Верифицирован' : 'Верифицировать',
                style: TextStyle(
                  fontSize: 11,
                  color: active
                      ? Colors.white
                      : (isDark ? Colors.white70 : Colors.black54),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _toggleVerify() async {
    try {
      final giving = !otherVerified;
      if (giving) {
        await AuthService.verifyUser(otherId);
      } else {
        await AuthService.unverifyUser(otherId);
      }
      if (!mounted) return;
      setState(() => otherVerified = giving);
      // Обновляем список чатов, чтобы галочка появилась и там
      widget.onChanged();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(giving
              ? '${widget.title} теперь верифицирован'
              : 'Галочка снята'),
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      final msg = e
          .toString()
          .replaceAll('Exception: ', '')
          .replaceAll('Bad state: ', '');
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  String _subtitle() {
    if (widget.kind == 'group') return '$memberCount участников';
    if (widget.kind == 'channel') return 'канал';
    if (otherStatus == 'online') return 'в сети';
    if (otherStatus == 'busy') return 'занят(а)';
    return 'был(а) недавно';
  }

  Widget _bubble(BuildContext context, Map<String, dynamic> m, bool mine,
      bool dark, double available) {
    final status = m['status'] as String?;
    final failed = status == 'failed';
    final type = m['type'] as String? ?? 'text';
    final url = m['file_url'] as String?;
    // Пока файл грузится на сервер, ссылки ещё нет — рисуем заглушку,
    // а не падаем на url! (раньше из-за этого весь список сообщений исчезал)
    final uploading = (type == 'image' || type == 'video') &&
        (url == null || url.isEmpty);
    final hasMedia = url != null && url.isNotEmpty && type != 'text';

    // Светлая тема — пузыри как в Telegram: исходящий зелёный, входящий белый
    final bg = failed
        ? (dark ? const Color(0xFF5C2B2B) : const Color(0xFFFBE3E4))
        : mine
            ? (dark ? LuxeColors.bubbleOut : LuxeColors.bubbleOutLight)
            : (dark ? LuxeColors.bubbleIn : LuxeColors.bubbleInLight);
    final fg = dark || mine ? Colors.white : Colors.black87;
    // Ширина считается от реальной ширины колонки, а не от ширины окна:
    // в трёхколоночном режиме колонка чата намного уже окна
    final maxW = (available * 0.82).clamp(160.0, available - 24);

    // Фото/видео: подпись сверху, само изображение ниже (как в Telegram)
    final caption = (m['content'] ?? '') as String;
    final fileName = (m['file_name'] ?? caption) as String;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 2),
      padding: type == 'image'
          ? const EdgeInsets.fromLTRB(3, 3, 3, 5)
          : const EdgeInsets.fromLTRB(11, 6, 11, 6),
      constraints: BoxConstraints(maxWidth: maxW),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(16),
          topRight: const Radius.circular(16),
          bottomLeft: Radius.circular(mine ? 16 : 5),
          bottomRight: Radius.circular(mine ? 5 : 16),
        ),
        boxShadow: [
          if (!failed)
            BoxShadow(
              color: Colors.black.withValues(alpha: dark ? 0.25 : 0.08),
              blurRadius: 3,
              offset: const Offset(0, 1),
            ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (uploading)
            _uploadPlaceholder(maxW, failed, dark, fileName)
          else if (type == 'image' && url != null)
            _imageAttachment(context, m, url, mine, dark, maxW)
          else if (type == 'video' && url != null)
            _videoAttachment(context, m, url, fileName, dark, maxW)
          else if (type == 'file')
            _fileAttachment(context, m, fg),
          // Подпись: для медиа показываем только если она не совпадает с именем файла
          if (!hasMedia ||
              (type != 'file' && caption.isNotEmpty && caption != fileName)) ...[
            if (hasMedia) const SizedBox(height: 5),
            Text(caption,
                style: TextStyle(fontSize: 15, height: 1.25, color: fg)),
          ],
          const SizedBox(height: 2),
          Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Text(
                _time(m),
                style: TextStyle(
                    fontSize: 10,
                    color: mine || dark ? Colors.white54 : Colors.black45),
              ),
              if (mine) Ticks(status: status, lightBubble: !dark && mine),
            ],
          ),
        ],
      ),
    );
  }

  /// Заглушка на время загрузки файла на сервер.
  Widget _uploadPlaceholder(
      double maxW, bool failed, bool dark, String name) {
    return Container(
      height: 150,
      width: maxW - 6,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(13),
        color: dark ? Colors.white10 : Colors.black12,
      ),
      alignment: Alignment.center,
      child: failed
          ? Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.error_outline_rounded,
                    size: 18, color: LuxeColors.danger),
                const SizedBox(width: 6),
                Flexible(
                  child: Text('Не удалось отправить',
                      style: TextStyle(
                          fontSize: 12,
                          color: dark ? Colors.white70 : Colors.black54)),
                ),
              ],
            )
          : Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(height: 8),
                Text('Загрузка…',
                    style: TextStyle(
                        fontSize: 12,
                        color: dark ? Colors.white54 : Colors.black45)),
              ],
            ),
    );
  }

  /// Фото — показывается сразу картинкой, тап открывает во весь экран,
  /// долгий тап даёт «Сохранить».
  Widget _imageAttachment(BuildContext context, Map<String, dynamic> m,
      String url, bool mine, bool dark, double maxW) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(13),
      child: Stack(
        children: [
          GestureDetector(
            onTap: () => _openImage(context, url),
            onLongPress: () => _saveFile(context, url, m),
            child: Image.network(
              url,
              width: maxW - 6,
              fit: BoxFit.cover,
              loadingBuilder: (c, child, progress) {
                if (progress == null) return child;
                return Container(
                  height: 180,
                  width: maxW - 6,
                  color: dark ? Colors.white10 : Colors.black12,
                  alignment: Alignment.center,
                  child: const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                );
              },
              errorBuilder: (c, e, s) => Container(
                height: 140,
                width: maxW - 6,
                color: dark ? Colors.white10 : Colors.black12,
                alignment: Alignment.center,
                child: Icon(Icons.broken_image_rounded,
                    color: dark ? Colors.white38 : Colors.black38, size: 34),
              ),
            ),
          ),
          Positioned(
            right: 6,
            bottom: 6,
            child: _downloadChip(context, url, m, dark),
          ),
        ],
      ),
    );
  }

  /// Видео — карточка с превью-заглушкой и кнопкой открытия.
  Widget _videoAttachment(BuildContext context, Map<String, dynamic> m,
      String url, String name, bool dark, double maxW) {
    final fg = dark ? Colors.white : Colors.black87;
    return GestureDetector(
      onTap: () => _openUrl(url),
      onLongPress: () => _saveFile(context, url, m),
      child: Container(
        height: 150,
        width: maxW - 6,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(13),
          color: dark ? Colors.white10 : Colors.black87,
        ),
        alignment: Alignment.center,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white24,
              ),
              child: const Icon(Icons.play_arrow_rounded,
                  color: Colors.white, size: 34),
            ),
            const SizedBox(height: 8),
            Text(name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: fg.withValues(alpha: 0.9), fontSize: 12)),
          ],
        ),
      ),
    );
  }

  /// Кнопка «скачать» поверх изображения.
  Widget _downloadChip(
      BuildContext context, String url, Map<String, dynamic> m, bool dark) {
    return GestureDetector(
      onTap: () => _saveFile(context, url, m),
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.black.withValues(alpha: 0.45),
        ),
        child: const Icon(Icons.download_rounded, color: Colors.white, size: 18),
      ),
    );
  }

  /// Карточка файла: иконка, имя, размер, кнопка скачивания.
  Widget _fileAttachment(
      BuildContext context, Map<String, dynamic> m, Color fg) {
    final url = m['file_url'] as String?;
    final name = (m['file_name'] ?? m['content'] ?? 'Файл') as String;
    final size = (m['file_size'] ?? 0) as int;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: url == null ? null : () => _openUrl(url),
          child: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: fg.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(_fileIcon(name), size: 22, color: fg),
          ),
        ),
        const SizedBox(width: 10),
        Flexible(
          child: GestureDetector(
            onTap: url == null ? null : () => _openUrl(url),
            onLongPress: url == null ? null : () => _saveFile(context, url, m),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w500, color: fg)),
                if (size > 0)
                  Text(MediaService.humanSize(size),
                      style: TextStyle(
                          fontSize: 11, color: fg.withValues(alpha: 0.65)))
                else
                  Text('Нажмите, чтобы открыть',
                      style: TextStyle(
                          fontSize: 11, color: fg.withValues(alpha: 0.65))),
              ],
            ),
          ),
        ),
        if (url != null) ...[
          const SizedBox(width: 8),
          _downloadButton(context, url, m),
        ],
      ],
    );
  }

  Widget _downloadButton(
      BuildContext context, String url, Map<String, dynamic> m) {
    final fg = Theme.of(context).brightness == Brightness.dark
        ? Colors.white
        : Colors.black87;
    return GestureDetector(
      onTap: () => _saveFile(context, url, m),
      child: Container(
        padding: const EdgeInsets.all(7),
        decoration: BoxDecoration(
          color: fg.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(Icons.download_rounded, size: 19, color: fg),
      ),
    );
  }

  /// Иконка по расширению файла.
  IconData _fileIcon(String name) {
    final n = name.toLowerCase();
    if (n.endsWith('.pdf')) return Icons.picture_as_pdf_rounded;
    if (n.endsWith('.apk')) return Icons.android_rounded;
    if (n.endsWith('.zip') || n.endsWith('.rar') || n.endsWith('.7z')) {
      return Icons.folder_zip_rounded;
    }
    if (n.endsWith('.mp3') ||
        n.endsWith('.wav') ||
        n.endsWith('.flac') ||
        n.endsWith('.m4a')) {
      return Icons.music_note_rounded;
    }
    if (n.endsWith('.mp4') || n.endsWith('.mov') || n.endsWith('.webm')) {
      return Icons.movie_rounded;
    }
    if (n.endsWith('.doc') || n.endsWith('.docx')) {
      return Icons.description_rounded;
    }
    if (n.endsWith('.xls') || n.endsWith('.xlsx')) {
      return Icons.table_chart_rounded;
    }
    return Icons.insert_drive_file_rounded;
  }

  /// Скачать файл на устройство.
  Future<void> _saveFile(
      BuildContext context, String url, Map<String, dynamic> m) async {
    final name = (m['file_name'] ?? m['content'] ?? 'file') as String;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Скачиваем...'), duration: Duration(seconds: 1)),
    );
    try {
      final path = await MediaService.download(url, name);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Сохранено: ${path.split(RegExp(r'[/\\]')).last}'),
          duration: const Duration(seconds: 4),
        ),
      );
    } catch (e) {
      debugPrint('Не удалось скачать файл: $e');
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Не удалось скачать: $e')));
    }
  }

  /// Открыть файл системным приложением.
  Future<void> _openUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  /// Фото во весь экран.
  void _openImage(BuildContext context, String url) {
    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.black87,
        pageBuilder: (_, __, ___) => Scaffold(
          backgroundColor: Colors.transparent,
          body: Stack(
            children: [
              Center(
                child: InteractiveViewer(
                  maxScale: 5,
                  child: Image.network(url),
                ),
              ),
              Positioned(
                top: 40,
                right: 16,
                child: IconButton(
                  icon: const Icon(Icons.close_rounded, color: Colors.white),
                  onPressed: () => Navigator.pop(context),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Время: для сегодня — HH:MM, иначе с датой.
  String _time(Map<String, dynamic> m) {
    final dt = _dateOf(m);
    final now = DateTime.now();
    final sameDay =
        dt.year == now.year && dt.month == now.month && dt.day == now.day;
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    return sameDay ? '$hh:$mm' : '${dt.day}.${dt.month}.${dt.year}, $hh:$mm';
  }

  /// Один ли день?
  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  /// Безопасное чтение даты: битые данные не должны ронять весь список.
  DateTime _dateOf(Map<String, dynamic> m) {
    final raw = m['created_at'];
    if (raw is String) {
      final parsed = DateTime.tryParse(raw);
      if (parsed != null) return parsed.toLocal();
    }
    if (raw is DateTime) return raw.toLocal();
    return DateTime.fromMillisecondsSinceEpoch(0);
  }

  /// Разделитель дат между сообщениями.
  Widget _dateSeparator(DateTime dt, bool dark) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(dt.year, dt.month, dt.day);
    final diff = today.difference(day).inDays;
    final label = switch (diff) {
      0 => 'Сегодня',
      1 => 'Вчера',
      _ => '${day.day}.${day.month}.${day.year}',
    };
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 10),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          color: dark
              ? Colors.black.withValues(alpha: 0.35)
              : Colors.white.withValues(alpha: 0.75),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: dark ? Colors.white70 : Colors.black54)),
      ),
    );
  }

  Widget _channelPost(BuildContext context, Map<String, dynamic> m) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: dark ? const Color(0xFF20302A) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                      colors: [LuxeColors.tgBlue, Color(0xFF7A5AF8)]),
                ),
                child: const Icon(Icons.campaign_rounded,
                    color: Colors.white, size: 15),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(widget.title,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: LuxeColors.tgBlue,
                        fontSize: 14)),
              ),
              Text(
                timeago.format(
                    DateTime.parse(m['created_at']).toLocal(),
                    locale: 'ru'),
                style: TextStyle(
                    fontSize: 11,
                    color: dark ? Colors.white54 : Colors.black45),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
              m['type'] == 'file' ? (m['content'] ?? 'Файл') : (m['content'] ?? ''),
              style: TextStyle(
                  fontSize: 15,
                  height: 1.35,
                  color: dark ? Colors.white : Colors.black87)),
        ],
      ),
    );
  }

  Widget _inputRow(bool dark) {
    return Row(
      children: [
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: dark ? LuxeColors.darkField : Colors.grey.shade200,
              borderRadius: BorderRadius.circular(26),
            ),
            child: TextField(
              controller: input,
              minLines: 1,
              maxLines: 4,
              decoration: InputDecoration(
                hintText: widget.kind == 'channel' ? 'Новый пост...' : 'Сообщение...',
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 18, vertical: 12),
              ),
              onSubmitted: (_) => send(),
            ),
          ),
        ),
        const SizedBox(width: 6),
        PopupMenuButton<String>(
          icon: const Icon(Icons.attach_file_rounded, size: 22),
          tooltip: 'Прикрепить',
          onSelected: (v) {
            switch (v) {
              case 'photo':
                _attachPhoto();
                break;
              case 'video':
                _attachVideo();
                break;
              default:
                _attachFile();
            }
          },
          itemBuilder: (context) => const [
            PopupMenuItem(
              value: 'photo',
              child: ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.image_rounded, color: LuxeColors.tgBlue),
                title: Text('Фото'),
              ),
            ),
            PopupMenuItem(
              value: 'video',
              child: ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.movie_rounded, color: LuxeColors.tgBlue),
                title: Text('Видео'),
              ),
            ),
            PopupMenuItem(
              value: 'file',
              child: ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.insert_drive_file_rounded,
                    color: LuxeColors.tgBlue),
                title: Text('Файл'),
              ),
            ),
          ],
        ),
        const SizedBox(width: 4),
        SendButton(onTap: send),
      ],
    );
  }

  Widget _subscribeRow() {
    return Center(
      child: CoolButton(
        icon: Icons.notifications_active_rounded,
        label: 'Включить уведомления',
        onTap: widget.onToggleInfo,
      ),
    );
  }
}