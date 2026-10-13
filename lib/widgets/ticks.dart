import 'package:flutter/material.dart';

import '../theme/luxe_theme.dart';

/// Галочки прочтения в стиле Telegram.
///
/// [status]:
///   null / 'sending' → часы (⏳, сообщение отправляется)
///   'sent'           → одна галочка (сообщение доставлено, но не прочитано)
///   'read'           → две галочки (прочитано)
class Ticks extends StatelessWidget {
  final String? status;
  final bool lightBubble;

  const Ticks({super.key, this.status, this.lightBubble = false});

  @override
  Widget build(BuildContext context) {
    final read = status == 'read';
    final sending = status == 'sending';

    Color color;
    IconData icon;
    if (sending) {
      color = lightBubble ? LuxeColors.checkIn : Colors.white54;
      icon = Icons.schedule_rounded;
    } else if (read) {
      color = lightBubble ? LuxeColors.checkOutLight : LuxeColors.checkOut;
      icon = Icons.done_all_rounded;
    } else {
      color = lightBubble ? LuxeColors.checkIn : Colors.white70;
      icon = Icons.done_rounded;
    }

    return Padding(
      padding: const EdgeInsets.only(left: 5, top: 1),
      child: Icon(icon, size: 14, color: color),
    );
  }
}