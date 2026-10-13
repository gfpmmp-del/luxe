import 'package:flutter/material.dart';
import 'package:timeago/timeago.dart' as timeago;
import '../main.dart';
import '../services/auth_service.dart';
import '../theme/luxe_theme.dart';
import '../widgets/luxe_widgets.dart';
import 'call_screen.dart';
import 'chat_screen.dart';

/// Вкладка «Звонки» — история вызовов с кнопкой перезвонить.
class CallsTab extends StatefulWidget {
  const CallsTab({super.key});
  @override
  State<CallsTab> createState() => CallsTabState();
}

class CallsTabState extends State<CallsTab> {
  List<Map<String, dynamic>> calls = [];
  Map<String, String> names = {};
  bool loading = true;

  @override
  void initState() {
    super.initState();
    reload();
  }

  Future<void> reload() async {
    setState(() => loading = true);
    try {
      final rows = await supabase
          .from('call_signals')
          .select()
          .or('caller_id.eq.${AuthService.myId},callee_id.eq.${AuthService.myId}')
          .eq('type', 'offer')
          .order('created_at', ascending: false)
          .limit(30);
      calls = (rows as List).cast<Map<String, dynamic>>();
      final otherIds = calls
          .map((c) => c['caller_id'] == AuthService.myId
              ? c['callee_id'] as String
              : c['caller_id'] as String)
          .toSet()
          .toList();
      names = {};
      if (otherIds.isNotEmpty) {
        final profiles = await supabase
            .from('profiles')
            .select('id, display_name, username')
            .inFilter('id', otherIds);
        for (final p in (profiles as List).cast<Map<String, dynamic>>()) {
          names[p['id'] as String] =
              (p['display_name'] ?? p['username'] ?? '?') as String;
        }
      }
    } catch (e) {
      debugPrint('История звонков не загрузилась: $e');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (loading) return const Center(child: CircularProgressIndicator());
    if (calls.isEmpty) {
      return const EmptyState(
        icon: Icons.call_outlined,
        title: 'Звонков пока нет',
        subtitle: 'Откройте чат и нажмите трубку — здесь появится история вызовов.',
      );
    }
    return RefreshIndicator(
      onRefresh: reload,
      color: LuxeColors.tgBlue,
      child: ListView.separated(
        itemCount: calls.length,
        separatorBuilder: (_, __) => const Divider(height: 1, indent: 78),
        itemBuilder: (context, i) {
          final c = calls[i];
          final outgoing = c['caller_id'] == AuthService.myId;
          final otherId = (outgoing ? c['callee_id'] : c['caller_id']) as String;
          final name = names[otherId] ?? '...';
          final payload = Map<String, dynamic>.from(c['payload'] as Map? ?? {});
          final isVideo = payload['video'] == true;
          return ListTile(
            leading: GradientAvatar(name: name),
            title: Text(name,
                style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Row(
              children: [
                Icon(
                  outgoing ? Icons.call_made : Icons.call_received,
                  size: 16,
                  color: outgoing ? LuxeColors.online : LuxeColors.danger,
                ),
                const SizedBox(width: 4),
                Text(
                    '${isVideo ? 'Видео' : 'Аудио'} • ${timeago.format(DateTime.parse(c['created_at']).toLocal(), locale: 'ru')}'),
              ],
            ),
            trailing: IconButton(
              icon: Container(
                padding: const EdgeInsets.all(8),
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(colors: [
                    LuxeColors.online,
                    Color(0xFF8FE38F),
                  ]),
                ),
                child: const Icon(Icons.call, color: Colors.white, size: 18),
              ),
              onPressed: () => _callBack(c, otherId, isVideo, name),
            ),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => ChatScreen(
                      chatId: c['chat_id'] as String, title: name)),
            ).then((_) => reload()),
          );
        },
      ),
    );
  }

  void _callBack(Map<String, dynamic> row, String otherId, bool video,
      String name) {
    Navigator.push(
      context,
      MaterialPageRoute(
          builder: (_) => CallScreen(
              chatId: row['chat_id'] as String,
              calleeId: otherId,
              video: video)),
    ).then((_) => reload());
  }
}
