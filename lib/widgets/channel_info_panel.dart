import 'package:flutter/material.dart';
import '../theme/luxe_theme.dart';

/// Правая панель канала: аватар, название, кнопки, описание, статистика.
class ChannelInfoPanel extends StatelessWidget {
  final String title;
  final int subscribers;
  final String? avatarUrl;
  final String description;
  final bool isChannel;
  final bool subscribed;
  final bool isCreator;
  final VoidCallback onClose;
  final VoidCallback onToggleSub;
  final VoidCallback? onAvatarTap;

  const ChannelInfoPanel({
    super.key,
    required this.title,
    required this.subscribers,
    required this.description,
    required this.isChannel,
    required this.subscribed,
    required this.isCreator,
    required this.onClose,
    required this.onToggleSub,
    this.avatarUrl,
    this.onAvatarTap,
  });

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final pattern = LuxeTheme.channelPattern(Theme.of(context).brightness);
    final panelColor = dark ? LuxeColors.infoPanelDark : LuxeColors.infoPanel;

    return Container(
      width: 340,
      color: panelColor,
      child: Column(
        children: [
          Align(
            alignment: Alignment.centerRight,
            child: IconButton(
              icon: const Icon(Icons.close_rounded),
              onPressed: onClose,
            ),
          ),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(color: dark ? panelColor : pattern),
            child: Column(
              children: [
                GestureDetector(
                  onTap: onAvatarTap,
                  child: Stack(
                    children: [
                      if (avatarUrl != null && avatarUrl!.isNotEmpty)
                        CircleAvatar(
                            radius: 52,
                            backgroundImage: NetworkImage(avatarUrl!))
                      else
                        Container(
                          width: 104,
                          height: 104,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: LinearGradient(colors: [
                              LuxeColors.tgBlue,
                              Color(0xFF7A5AF8),
                            ]),
                          ),
                          child: Icon(
                            isChannel
                                ? Icons.campaign_rounded
                                : Icons.group_rounded,
                            color: Colors.white,
                            size: 46,
                          ),
                        ),
                      if (onAvatarTap != null)
                        Positioned(
                          right: 0,
                          bottom: 0,
                          child: Container(
                            padding: const EdgeInsets.all(6),
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              color: LuxeColors.tgBlue,
                            ),
                            child: const Icon(Icons.camera_alt_rounded,
                                color: Colors.white, size: 14),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Text(title,
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.bold)),
                Text('$subscribers ${_plural(subscribers)}',
                    style: TextStyle(
                        fontSize: 13,
                        color: dark ? Colors.white54 : Colors.black54)),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            child: Row(
              children: [
                _action(Icons.volume_off_rounded, 'Звук'),
                const SizedBox(width: 8),
                _action(Icons.card_giftcard_rounded, 'Подарок'),
                const SizedBox(width: 8),
                _action(
                  subscribed
                      ? Icons.notifications_active_rounded
                      : Icons.notifications_off_outlined,
                  subscribed ? 'Уведомления' : 'Выключить',
                  onTap: onToggleSub,
                  active: subscribed,
                ),
              ],
            ),
          ),
          if (description.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(description,
                    style: TextStyle(
                        height: 1.4,
                        fontSize: 13,
                        color: dark ? Colors.white70 : Colors.black87)),
              ),
            ),
          const Divider(height: 20),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 4),
              children: [
                _stat(Icons.emoji_emotions_rounded, '${subscribers * 2} подарков 🎁🎉🎊',
                    LuxeColors.tgBlue),
                _stat(Icons.photo_camera_rounded, '38 фотографий'),
                _stat(Icons.videocam_rounded, '12 видео'),
                _stat(Icons.description_rounded, '54 файла'),
                _stat(Icons.headphones_rounded, '1 аудиофайл'),
                _stat(Icons.link_rounded, '314 ссылки'),
                _stat(Icons.bar_chart_rounded, '16 опросов'),
                _stat(Icons.mic_rounded, '7 голосовых сообщений'),
                _stat(Icons.gif_rounded, '6 GIF'),
                const Divider(height: 20),
                _stat(
                  subscribed
                      ? Icons.logout_rounded
                      : Icons.add_circle_outline_rounded,
                  subscribed ? 'Покинуть канал' : 'Вступить в канал',
                  LuxeColors.tgBlue,
                  onToggleSub,
                ),
                _stat(Icons.block_rounded, 'Пожаловаться', LuxeColors.danger),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _action(IconData icon, String label,
      {VoidCallback? onTap, bool active = false}) {
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          margin: const EdgeInsets.symmetric(horizontal: 2),
          decoration: BoxDecoration(
            color: active
                ? LuxeColors.tgBlue.withValues(alpha: 0.12)
                : Colors.grey.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: [
              Icon(icon, size: 20, color: active ? LuxeColors.tgBlue : null),
              const SizedBox(height: 4),
              Text(label,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 10, color: active ? LuxeColors.tgBlue : null)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _stat(IconData icon, String label, [Color? color, VoidCallback? onTap]) {
    return ListTile(
      dense: true,
      onTap: onTap,
      leading: Icon(icon, size: 22, color: color),
      title: Text(label, style: TextStyle(fontSize: 14, color: color)),
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