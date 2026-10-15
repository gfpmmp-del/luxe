import 'package:flutter/material.dart';

import '../services/sticker_service.dart';
import '../theme/luxe_theme.dart';
import '../widgets/luxe_widgets.dart';
import '../widgets/sticker_view.dart';
import 'sticker_panel.dart';

/// Экран «Стикеры»: свой набор, добавление, удаление, эмодзи.
class StickersScreen extends StatefulWidget {
  /// null — показать только свои.
  final String? ownerId;
  final String? ownerName;
  final String? ownerAvatar;
  /// Вызывается при отправке стикера из чужого набора.
  final void Function(Sticker s)? onPick;

  const StickersScreen({
    super.key,
    this.ownerId,
    this.ownerName,
    this.ownerAvatar,
    this.onPick,
  });

  @override
  State<StickersScreen> createState() => _StickersScreenState();
}

class _StickersScreenState extends State<StickersScreen> {
  List<Sticker> _stickers = [];
  bool _loading = true;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final list = widget.ownerId == null
          ? await StickerService.mine()
          : (await StickerService.others())[widget.ownerId] ?? <Sticker>[];
      if (!mounted) return;
      setState(() {
        _stickers = list;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _failed = true;
      });
    }
  }

  Future<void> _add() async {
    final ok = await showAddStickerDialog(context);
    if (ok == true) _load();
  }

  Future<void> _edit(Sticker s) async {
    final ctrl = TextEditingController(text: s.emoji);
    final emoji = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Эмодзи стикера'),
        content: TextField(
          controller: ctrl,
          maxLength: 8,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'например 🎉',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Отмена')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
              child: const Text('Сохранить')),
        ],
      ),
    );
    if (emoji != null) {
      await StickerService.rename(s.id, emoji);
      _load();
    }
  }

  Future<void> _confirmDelete(Sticker s) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Удалить стикер?'),
        content: const Text('Он исчезнет из вашего набора.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Отмена')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Удалить',
                style: TextStyle(color: LuxeColors.danger)),
          ),
        ],
      ),
    );
    if (yes == true) {
      await StickerService.remove(s.id);
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final mine = widget.ownerId == null;

    return Scaffold(
      appBar: AppBar(
        title: Text(mine ? 'Мои стикеры' : (widget.ownerName ?? 'Стикеры')),
        actions: [
          if (mine)
            IconButton(
              onPressed: _add,
              icon: const Icon(Icons.add_rounded),
              tooltip: 'Добавить стикер',
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _failed
              ? EmptyState(
                  icon: Icons.cloud_off_rounded,
                  title: 'Не удалось загрузить стикеры',
                  subtitle: 'Проверьте подключение к интернету.',
                  accent: LuxeColors.tgBlue,
                )
              : _stickers.isEmpty
                  ? EmptyState(
                      icon: Icons.emoji_emotions_outlined,
                      title: mine ? 'Стикеров пока нет' : 'Набор пуст',
                      subtitle: mine
                          ? 'Нажмите «+» и выберите GIF, Lottie или картинку.'
                          : 'Этот пользователь пока не добавил ни одного стикера.',
                      accent: LuxeColors.tgBlue,
                    )
                  : GridView.builder(
                      padding: const EdgeInsets.all(10),
                      gridDelegate:
                          const SliverGridDelegateWithMaxCrossAxisExtent(
                        maxCrossAxisExtent: 110,
                        mainAxisSpacing: 8,
                        crossAxisSpacing: 8,
                      ),
                      itemCount: _stickers.length,
                      itemBuilder: (_, i) {
                        final s = _stickers[i];
                        return GestureDetector(
                          onTap: () {
                            if (mine) {
                              _edit(s);
                            } else {
                              widget.onPick?.call(s);
                              Navigator.pop(context);
                            }
                          },
                          onLongPress: mine ? () => _confirmDelete(s) : null,
                          child: Container(
                            decoration: BoxDecoration(
                              color: dark
                                  ? LuxeColors.darkField
                                  : Colors.grey.shade100,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                Center(
                                    child:
                                        StickerView(url: s.url, kind: s.kind, size: 84)),
                                if (s.emoji.isNotEmpty)
                                  Positioned(
                                    bottom: 4,
                                    right: 6,
                                    child: Text(s.emoji,
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: dark
                                              ? Colors.white70
                                              : Colors.black54,
                                        )),
                                  ),
                                if (s.isAnimated)
                                  Positioned(
                                    top: 4,
                                    left: 4,
                                    child: Icon(Icons.play_circle_outline,
                                        size: 14,
                                        color: Colors.white.withValues(alpha: 0.5)),
                                  ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
    );
  }
}
