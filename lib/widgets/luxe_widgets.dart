import 'package:flutter/material.dart';
import '../services/media_service.dart';
import '../theme/luxe_theme.dart';

/// Градиент по имени — стабильный цвет аватарки как в Telegram.
LinearGradient avatarGradient(String seed) {
  final i = seed.hashCode.abs() % LuxeColors.avatarGradients.length;
  final pair = LuxeColors.avatarGradients[i];
  return LinearGradient(
    colors: pair,
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}

class GradientAvatar extends StatelessWidget {
  final String name;
  final double radius;
  final bool showOnline;
  final bool isOnline;
  final String? imageUrl;
  const GradientAvatar({
    super.key,
    required this.name,
    this.radius = 26,
    this.showOnline = false,
    this.isOnline = false,
    this.imageUrl,
  });

  @override
  Widget build(BuildContext context) {
    final letter = name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase();
    // Ссылки, записанные во времена прокси, надо чинить: сам адрес
    // сменился, а в базе остался старый.
    final photo = MediaService.fixUrl(imageUrl);
    final hasPhoto = photo != null && photo.isNotEmpty;
    return Stack(
      children: [
        Container(
          width: radius * 2,
          height: radius * 2,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: hasPhoto ? null : avatarGradient(name),
            image: hasPhoto
                ? DecorationImage(
                    image: NetworkImage(photo), fit: BoxFit.cover)
                : null,
          ),
          alignment: Alignment.center,
          child: hasPhoto
              ? null
              : Text(
                  letter,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: radius * 0.9,
                    fontWeight: FontWeight.bold,
                  ),
                ),
        ),
        if (showOnline)
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              width: radius * 0.55,
              height: radius * 0.55,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isOnline ? LuxeColors.online : Colors.grey,
                border: Border.all(
                  color: Theme.of(context).scaffoldBackgroundColor,
                  width: 2,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Кнопка-пилюля с однотонной заливкой.
class CoolButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;
  const CoolButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final bg = color ?? LuxeColors.tgBlue;
    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: Colors.white, size: 19),
              const SizedBox(width: 8),
              Text(label,
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w500,
                      fontSize: 15)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Кнопка отправки.
class SendButton extends StatelessWidget {
  final VoidCallback onTap;
  const SendButton({super.key, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: LuxeColors.tgBlue,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: const SizedBox(
          width: 46,
          height: 46,
          child: Icon(Icons.send_rounded, color: Colors.white, size: 21),
        ),
      ),
    );
  }
}

class SectionHeader extends StatelessWidget {
  final String text;
  const SectionHeader(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          color: Theme.of(context).colorScheme.primary,
          fontWeight: FontWeight.bold,
          fontSize: 13,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color accent;
  const EmptyState(
      {super.key,
      required this.icon,
      required this.title,
      required this.subtitle,
      this.accent = LuxeColors.tgBlue});

  @override
  Widget build(BuildContext context) {
    final grey = Theme.of(context).brightness == Brightness.dark
        ? Colors.white54
        : Colors.black54;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [
                    accent.withValues(alpha: 0.25),
                    LuxeColors.accent.withValues(alpha: 0.25),
                  ],
                ),
              ),
              child: Icon(icon, size: 44, color: accent),
            ),
            const SizedBox(height: 16),
            Text(title,
                style:
                    const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            Text(subtitle,
                textAlign: TextAlign.center,
                style: TextStyle(color: grey, fontSize: 14)),
          ],
        ),
      ),
    );
  }
}
