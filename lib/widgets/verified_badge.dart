import 'package:flutter/material.dart';

import '../theme/luxe_theme.dart';

/// Значок верифицированного аккаунта.
///
/// Показывается рядом с именем пользователя. Статус хранится в
/// profiles.verified и выставляется администратором
/// (AuthService.verifyUser).
class VerifiedBadge extends StatelessWidget {
  final double size;
  final bool verified;

  const VerifiedBadge({
    super.key,
    this.verified = true,
    this.size = 17,
  });

  @override
  Widget build(BuildContext context) {
    if (!verified) return const SizedBox.shrink();
    // Без Tooltip: всплывающая подсказка перекрывала сам значок
    return Padding(
      padding: const EdgeInsets.only(left: 5),
      child: Icon(
        Icons.verified_rounded,
        size: size,
        color: LuxeColors.tgBlue,
      ),
    );
  }
}

/// Имя пользователя вместе со значком верификации.
class UserName extends StatelessWidget {
  final String name;
  final bool verified;
  final TextStyle? style;
  final double badgeSize;

  const UserName(
    this.name, {
    super.key,
    this.verified = false,
    this.style,
    this.badgeSize = 17,
  });

  @override
  Widget build(BuildContext context) {
    if (!verified) {
      return Text(name, overflow: TextOverflow.ellipsis, style: style);
    }
    // Без Flexible: значок всегда получает свой размер и не схлопывается
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: Text(name, overflow: TextOverflow.ellipsis, style: style),
        ),
        VerifiedBadge(size: badgeSize),
      ],
    );
  }
}