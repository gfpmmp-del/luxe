import 'package:flutter/material.dart';

import '../services/premium_service.dart';
import '../theme/luxe_theme.dart';

/// Экран «Luxe Premium» — список возможностей и кнопка активации.
class PremiumScreen extends StatefulWidget {
  final bool active;
  final String? until;

  const PremiumScreen({super.key, required this.active, this.until});

  @override
  State<PremiumScreen> createState() => _PremiumScreenState();
}

class _PremiumScreenState extends State<PremiumScreen> {
  bool _busy = false;

  String get _untilText {
    final d = widget.until == null ? null : DateTime.tryParse(widget.until!);
    if (d == null) return '';
    return '${d.day}.${d.month}.${d.year}';
  }

  Future<void> _toggle() async {
    setState(() => _busy = true);
    try {
      if (widget.active) {
        await PremiumFeatures.deactivate();
      } else {
        await PremiumFeatures.activate();
      }
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Не удалось изменить подписку: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Luxe Premium'),
        backgroundColor: LuxeColors.premiumGold,
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Шапка
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              gradient: const LinearGradient(
                colors: [LuxeColors.premiumGold, Color(0xFFC9962F)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              boxShadow: [
                BoxShadow(
                  color: LuxeColors.premiumGold.withValues(alpha: 0.4),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              children: [
                const Icon(Icons.workspace_premium_rounded,
                    size: 64, color: Colors.white),
                const SizedBox(height: 12),
                const Text('Luxe Premium',
                    style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.bold,
                        color: Colors.white)),
                const SizedBox(height: 6),
                Text(
                  widget.active
                      ? 'Подписка активна${_untilText.isEmpty ? '' : ' до $_untilText'}'
                      : 'Больше возможностей для вашего общения',
                  style: const TextStyle(color: Colors.white70, fontSize: 14),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Text('Возможности',
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: dark ? Colors.white : Colors.black87)),
          const SizedBox(height: 8),
          for (final f in PremiumFeatures.all)
            Card(
              elevation: 0,
              margin: const EdgeInsets.only(bottom: 8),
              color: dark ? LuxeColors.darkCard : Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
              child: ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(9),
                  decoration: BoxDecoration(
                    color: LuxeColors.premiumGold.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(f.icon, color: LuxeColors.premiumGold, size: 20),
                ),
                title: Text(f.title,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text(f.description, style: const TextStyle(fontSize: 12)),
                trailing: widget.active
                    ? const Icon(Icons.check_circle, color: LuxeColors.online)
                    : const Icon(Icons.lock_outline,
                        color: LuxeColors.premiumGold, size: 20),
              ),
            ),
          const SizedBox(height: 16),
          if (_busy)
            const Center(child: CircularProgressIndicator())
          else
            FilledButton(
              onPressed: _toggle,
              style: FilledButton.styleFrom(
                backgroundColor: LuxeColors.premiumGold,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
              ),
              child: Text(
                widget.active
                    ? 'Отменить подписку'
                    : 'Активировать Premium — 299 ₽/год',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ),
          const SizedBox(height: 12),
          const Text(
            'Демонстрационный режим: оплата не производится, подписка активируется сразу.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11, color: Colors.grey),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}