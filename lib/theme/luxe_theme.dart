import 'package:flutter/material.dart';

/// Фирменные цвета Luxe.
class LuxeColors {
  static const tgBlue = Color(0xFF229ED9);
  static const tgBlueDark = Color(0xFF1A8BC2);
  static const accent = Color(0xFF6AB2E7);
  static const online = Color(0xFF4CCD5E);
  static const danger = Color(0xFFE5484D);

  // Тёмная тема
  static const darkBg = Color(0xFF0E1621);
  static const darkCard = Color(0xFF17212B);
  static const darkField = Color(0xFF242F3D);
  static const bubbleOut = Color(0xFF2B5278);
  static const bubbleIn = Color(0xFF182533);

  // Трёхколоночный интерфейс
  static const sideBar = Color(0xFF17212B); // левая тёмная колонка
  static const sideBarActive = Color(0xFF2B5278); // выбранный пункт
  static const listPanel = Color(0xFFFFFFFF); // список чатов (светлый)
  static const listPanelDark = Color(0xFF0E1621);
  static const infoPanel = Color(0xFFFFFFFF); // правая панель
  static const infoPanelDark = Color(0xFF17212B);
  static const channelPattern = Color(0xFFDCF8CD); // фон-паттерн канала
  static const channelPatternDark = Color(0xFF1B2C22);

  // Оформление пузырей сообщений (как в Telegram)
  static const bubbleInLight = Color(0xFFFFFFFF);
  static const bubbleOutLight = Color(0xFFEEFFDE);
  static const checkIn = Color(0xFF8A8A8A); // одна галочка — серым
  static const checkOut = Color(0xFF3EA6F0); // две галочки — синим
  static const checkOutLight = Color(0xFF4FAE4F); // в светлом пузыре

  static const premiumGold = Color(0xFFE8B84B);
  static const premiumDark = Color(0xFF3B2E1A);

  static const avatarGradients = [
    [Color(0xFFD08A6E), Color(0xFFB87A5F)],
    [Color(0xFF7C8CA8), Color(0xFF6B7A96)],
    [Color(0xFF5B9BA8), Color(0xFF4C8894)],
    [Color(0xFF8AA37E), Color(0xFF78906C)],
    [Color(0xFFA87C8C), Color(0xFF94697A)],
    [Color(0xFF7E8398), Color(0xFF6D7285)],
  ];
}

/// Переключатель темы.
class LuxeTheme {
  static final mode = ValueNotifier<ThemeMode>(ThemeMode.system);

  static ThemeData light() {
    final scheme = ColorScheme.fromSeed(
      seedColor: LuxeColors.tgBlue,
      brightness: Brightness.light,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: const Color(0xFFE7EBF0),
      appBarTheme: const AppBarTheme(
        backgroundColor: LuxeColors.tgBlue,
        foregroundColor: Colors.white,
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: LuxeColors.tgBlue,
        foregroundColor: Colors.white,
      ),
    );
  }

  static ThemeData dark() {
    final scheme = ColorScheme.fromSeed(
      seedColor: LuxeColors.tgBlue,
      brightness: Brightness.dark,
    ).copyWith(surface: LuxeColors.darkCard);
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: LuxeColors.darkBg,
      appBarTheme: const AppBarTheme(
        backgroundColor: LuxeColors.darkCard,
        foregroundColor: Colors.white,
      ),
      cardColor: LuxeColors.darkCard,
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: LuxeColors.tgBlue,
        foregroundColor: Colors.white,
      ),
    );
  }

  /// Фон правой панели (канала) — светлый сетчатый паттерн как у Telegram.
  static Color channelPattern(Brightness b) =>
      b == Brightness.dark ? LuxeColors.channelPatternDark : LuxeColors.channelPattern;
}