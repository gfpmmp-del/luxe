import 'package:flutter/material.dart';

import '../main.dart';
import '../theme/luxe_theme.dart';
import 'auth_service.dart';

/// Возможности Luxe Premium.
/// Часть функций включается флагом, часть — заглушки под будущую реализацию.
class PremiumFeature {
  final String title;
  final String description;
  final IconData icon;
  final bool premiumOnly;

  const PremiumFeature({
    required this.title,
    required this.description,
    required this.icon,
    this.premiumOnly = true,
  });
}

class PremiumFeatures {
  static const List<PremiumFeature> all = [
    PremiumFeature(
      title: 'Большие файлы — до 2 ГБ',
      description: 'Без Premium лимит 50 МБ на файл',
      icon: Icons.folder_zip_rounded,
    ),
    PremiumFeature(
      title: 'Безлимит пересылок',
      description: 'Пересылайте сколько угодно сообщений',
      icon: Icons.forward_rounded,
    ),
    PremiumFeature(
      title: 'Анимированные эмодзи',
      description: 'Эксклюзивные анимации в чате',
      icon: Icons.emoji_emotions_rounded,
    ),
    PremiumFeature(
      title: 'Значок у канала',
      description: 'Рядом с именем канала — звезда Premium',
      icon: Icons.workspace_premium_rounded,
    ),
    PremiumFeature(
      title: 'Увеличенные лимиты',
      description: 'Больше участников в группе и канале',
      icon: Icons.groups_rounded,
    ),
    PremiumFeature(
      title: 'Без рекламы',
      description: 'Никаких промо-вставок в интерфейсе',
      icon: Icons.block_rounded,
    ),
    PremiumFeature(
      title: 'Премиум-реакции',
      description: 'Набор редких реакций на сообщения',
      icon: Icons.auto_awesome_rounded,
    ),
    PremiumFeature(
      title: 'Приоритетная поддержка',
      description: 'Ответ в приоритетном порядке',
      icon: Icons.support_agent_rounded,
    ),
  ];

  /// Есть ли у пользователя активный Premium.
  static bool isActive(Map<String, dynamic>? profile) {
    if (profile == null) return false;
    if (profile['premium'] != true) return false;
    final until = profile['premium_until'] as String?;
    if (until == null || until.isEmpty) return true;
    final d = DateTime.tryParse(until);
    return d == null || d.isAfter(DateTime.now());
  }

  /// Активировать Premium (демо-режим: помечаем на год).
  static Future<void> activate() async {
    final until = DateTime.now().add(const Duration(days: 365));
    await supabase.from('profiles').update({
      'premium': true,
      'premium_until': until.toIso8601String(),
    }).eq('id', AuthService.myId);

    await supabase.from('premium_orders').insert({
      'user_id': AuthService.myId,
      'plan': 'year',
      'price': 299,
      'expires_at': until.toIso8601String(),
    });
  }

  static Future<void> deactivate() async {
    await supabase
        .from('profiles')
        .update({'premium': false, 'premium_until': null})
        .eq('id', AuthService.myId);
  }
}

/// Бейдж Premium (золотая звезда).
class PremiumBadge extends StatelessWidget {
  final double size;
  const PremiumBadge({super.key, this.size = 14});

  @override
  Widget build(BuildContext context) => Icon(
        Icons.workspace_premium_rounded,
        size: size,
        color: LuxeColors.premiumGold,
      );
}