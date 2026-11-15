import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/luxe_theme.dart';

/// Что выбрал пользователь в меню сообщения.
enum MessageAction { copy, save, deleteForMe, deleteForAll }

/// Текст, который кладём в буфер обмена.
///
/// Для обычного сообщения — сам текст, для медиа без подписи — ссылка на
/// файл. Служебную подпись голосового копировать бессмысленно.
String messageCopyText(Map<String, dynamic> message) {
  final content = (message['content'] as String? ?? '').trim();
  if (content.isNotEmpty && content != 'Голосовое сообщение') return content;
  final url = (message['file_url'] as String? ?? '').trim();
  if (url.isNotEmpty) return url;
  return content;
}

/// Меню по долгому нажатию на сообщение.
///
/// Возвращает выбранное действие, а копирование выполняет само: буфер
/// обмена и подсказка «Скопировано» одинаковы в обоих экранах чата.
Future<MessageAction?> showMessageActions(
  BuildContext context, {
  required Map<String, dynamic> message,
  required bool mine,
  bool canSave = false,
}) async {
  final text = messageCopyText(message);
  final id = message['id'] as String? ?? '';
  // Временное сообщение ещё не существует на сервере — удалять нечего.
  final pending = id.startsWith('pending-');

  final action = await showModalBottomSheet<MessageAction>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) {
      final dark = Theme.of(sheetContext).brightness == Brightness.dark;
      return SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (text.isNotEmpty)
              ListTile(
                leading: const Icon(Icons.copy_rounded),
                title: const Text('Копировать'),
                onTap: () => Navigator.pop(sheetContext, MessageAction.copy),
              ),
            if (canSave)
              ListTile(
                leading: const Icon(Icons.download_rounded),
                title: const Text('Сохранить'),
                onTap: () => Navigator.pop(sheetContext, MessageAction.save),
              ),
            if (!pending)
              ListTile(
                leading: const Icon(Icons.visibility_off_outlined),
                title: const Text('Удалить у себя'),
                subtitle: const Text('Исчезнет только для вас'),
                onTap: () =>
                    Navigator.pop(sheetContext, MessageAction.deleteForMe),
              ),
            if (mine && !pending)
              ListTile(
                leading: const Icon(
                  Icons.delete_forever_rounded,
                  color: LuxeColors.danger,
                ),
                title: const Text(
                  'Удалить у всех',
                  style: TextStyle(color: LuxeColors.danger),
                ),
                subtitle: Text(
                  'Сообщение исчезнет у всех участников',
                  style: TextStyle(
                    color: dark ? Colors.white54 : Colors.black54,
                  ),
                ),
                onTap: () =>
                    Navigator.pop(sheetContext, MessageAction.deleteForAll),
              ),
          ],
        ),
      );
    },
  );

  if (action == MessageAction.copy && text.isNotEmpty) {
    await Clipboard.setData(ClipboardData(text: text));
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Скопировано'),
          duration: Duration(seconds: 1),
        ),
      );
    }
  }
  return action;
}

/// Подтверждение перед удалением у всех: отменить уже нельзя.
Future<bool> confirmDeleteForAll(BuildContext context) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Удалить у всех?'),
      content: const Text('Сообщение исчезнет у всех участников чата.'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text('Отмена'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, true),
          child: const Text('Удалить', style: TextStyle(color: Colors.red)),
        ),
      ],
    ),
  );
  return ok == true;
}
