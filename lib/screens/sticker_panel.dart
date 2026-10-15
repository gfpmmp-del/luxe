import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../services/sticker_service.dart';
import '../theme/luxe_theme.dart';
import '../widgets/sticker_view.dart';

/// Панель стикеров над полем ввода — как в Telegram.
class StickerPanel extends StatelessWidget {
  final List<Sticker> stickers;
  final ValueChanged<Sticker> onPick;
  final VoidCallback onOpenAll;
  final VoidCallback onAdd;

  const StickerPanel({
    super.key,
    required this.stickers,
    required this.onPick,
    required this.onOpenAll,
    required this.onAdd,
  });

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      height: 132,
      color: dark ? LuxeColors.darkCard : Colors.white,
      child: Row(
        children: [
          Expanded(
            child: stickers.isEmpty
                ? Center(
                    child: Text(
                      'Стикеров пока нет. Добавьте свои — нажмите «+».',
                      style: TextStyle(
                        fontSize: 13,
                        color: dark ? Colors.white54 : Colors.black45,
                      ),
                    ),
                  )
                : ListView.builder(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 8),
                    itemCount: stickers.length,
                    itemBuilder: (_, i) {
                      final s = stickers[i];
                      return InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () => onPick(s),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              StickerView(
                                  url: s.url,
                                  kind: s.kind,
                                  size: 76),
                              if (s.emoji.isNotEmpty)
                                Text(s.emoji,
                                    style: const TextStyle(fontSize: 11)),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
          Column(
            children: [
              IconButton(
                onPressed: onOpenAll,
                icon: const Icon(Icons.grid_view_rounded,
                    size: 20, color: LuxeColors.tgBlue),
                tooltip: 'Все стикеры',
              ),
              IconButton(
                onPressed: onAdd,
                icon: const Icon(Icons.add_circle_outline_rounded,
                    size: 22, color: LuxeColors.tgBlue),
                tooltip: 'Добавить стикер',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Диалог добавления стикера: файл, эмодзи, сохранение.
Future<bool> showAddStickerDialog(BuildContext context) async {
  PlatformFile? file;
  var kind = 'static';
  var emoji = '';
  var busy = false;

  return await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setLocal) {
        return AlertDialog(
          title: const Text('Новый стикер'),
          content: SizedBox(
            width: 300,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  height: 140,
                  child: file == null
                      ? Center(
                          child: Text(
                            'Форматы: GIF, Lottie (.json), PNG, WebP',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 12,
                              color: Theme.of(ctx)
                                      .brightness ==
                                      Brightness.dark
                                  ? Colors.white54
                                  : Colors.black45,
                            ),
                          ),
                        )
                      : StickerView(
                          url: file!.path == null
                              ? ''
                              : _previewUrl(file!.path!),
                          kind: kind,
                          size: 130,
                        ),
                ),
                const SizedBox(height: 8),
                if (busy)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                else
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () async {
                            final f =
                                await StickerService.pickStickerSource();
                            if (f == null) return;
                            setLocal(() {
                              file = f;
                              kind = StickerService.kindOf(f.name);
                            });
                          },
                          icon: const Icon(Icons.image_outlined, size: 18),
                          label: const Text('Выбрать файл'),
                        ),
                      ),
                    ],
                  ),
                const SizedBox(height: 8),
                TextField(
                  maxLength: 8,
                  decoration: const InputDecoration(
                    labelText: 'Эмодзи (необязательно)',
                    hintText: 'например 🎉',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (v) => emoji = v,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Отмена')),
            FilledButton(
              onPressed: file == null || busy
                  ? null
                  : () async {
                      setLocal(() => busy = true);
                      final ok = await StickerService.createSticker(
                        file: file!,
                        kind: kind,
                        emoji: emoji.trim(),
                      );
                      if (ctx.mounted) Navigator.pop(ctx, ok);
                    },
              child: const Text('Сохранить'),
            ),
          ],
        );
      },
    ),
  ) ??
      false;
}

/// file:// для локального превью внутри Image.network.
String _previewUrl(String path) {
  final enc = Uri.encodeComponent(path.replaceAll('\\', '/'));
  return 'file:///$enc';
}

/// Кнопка «Стикеры» для композера.
class StickerButton extends StatelessWidget {
  final VoidCallback onTap;
  const StickerButton({super.key, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onTap,
      tooltip: 'Стикеры',
      icon: const Icon(Icons.emoji_emotions_outlined,
          size: 22, color: LuxeColors.tgBlue),
    );
  }
}
