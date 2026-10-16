import 'package:flutter/material.dart';

/// Оформление Luxe.
///
/// Цвета заданы явно, а не через ColorScheme.fromSeed: тот разбрасывает
/// оттенки по всему кубику и даёт кислотные акценты. Здесь всё подобрано
/// вручную, поэтому интерфейс выглядит одинаково спокойно в обоих темах.
class LuxeColors {
  // Акцент — спокойный сине-индиговый. Не «кричит», но заметен.
  static const brand = Color(0xFF4F6BED);
  static const brandDark = Color(0xFF3D57CE);
  static const brandSoft = Color(0xFFEEF1FE);

  // Историческое имя оставлено: на него ссылается весь интерфейс.
  static const tgBlue = brand;
  static const tgBlueDark = brandDark;
  static const accent = brand;

  static const online = Color(0xFF2FA96B);
  static const danger = Color(0xFFD14343);

  // Светлая тема
  static const lightBg = Color(0xFFF3F4F7);
  static const lightPanel = Color(0xFFFFFFFF);
  static const lightField = Color(0xFFEAECF1);
  static const lightLine = Color(0xFFE2E5EB);
  static const lightText = Color(0xFF14161A);
  static const lightTextDim = Color(0xFF6B7280);

  // Тёмная тема — не синеватая, а честно тёмная
  static const darkBg = Color(0xFF0F1115);
  static const darkCard = Color(0xFF171A21);
  static const darkField = Color(0xFF222630);
  static const darkLine = Color(0xFF2A2F3A);
  static const darkText = Color(0xFFEDEFF3);
  static const darkTextDim = Color(0xFF9AA1AD);

  // Совместимость со старыми именами
  static const bubbleOut = Color(0xFF2E3A5C);
  static const bubbleIn = Color(0xFF1B1F27);
  static const sideBar = darkCard;
  static const sideBarActive = bubbleOut;
  static const listPanel = lightPanel;
  static const listPanelDark = darkBg;
  static const infoPanel = lightPanel;
  static const infoPanelDark = darkCard;
  static const channelPattern = Color(0xFFEFF2F7);
  static const channelPatternDark = Color(0xFF14171D);

  // Пузыри сообщений
  static const bubbleInLight = Color(0xFFFFFFFF);
  static const bubbleOutLight = Color(0xFFE4EBFD);
  static const checkIn = Color(0xFF8A919E);
  static const checkOut = Color(0xFF4F6BED);
  static const checkOutLight = Color(0xFF4F6BED);

  static const premiumGold = Color(0xFFD4A032);
  static const premiumDark = Color(0xFF33291A);

  /// Приглушённые градиенты аватарок: раньше были кислотными.
  static const avatarGradients = [
    [Color(0xFFB08968), Color(0xFF9C7B5E)],
    [Color(0xFF6B7A99), Color(0xFF5E6C88)],
    [Color(0xFF5B8C99), Color(0xFF4F7D89)],
    [Color(0xFF7D9A72), Color(0xFF6E8A64)],
    [Color(0xFF9B7286), Color(0xFF8A6477)],
    [Color(0xFF737A8C), Color(0xFF646B7C)],
  ];
}

/// Плотности и скругления — единые для всего приложения.
class LuxeSpacing {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;

  static const radiusSm = BorderRadius.all(Radius.circular(8));
  static const radiusMd = BorderRadius.all(Radius.circular(12));
  static const radiusLg = BorderRadius.all(Radius.circular(16));
  static const radiusXl = BorderRadius.all(Radius.circular(20));
}

class LuxeTheme {
  static final mode = ValueNotifier<ThemeMode>(ThemeMode.system);

  /// Светлая схема.
  static ColorScheme _lightScheme() {
    return const ColorScheme(
      brightness: Brightness.light,
      primary: LuxeColors.brand,
      onPrimary: Colors.white,
      primaryContainer: LuxeColors.brandSoft,
      onPrimaryContainer: LuxeColors.brandDark,
      secondary: LuxeColors.lightTextDim,
      onSecondary: Colors.white,
      error: LuxeColors.danger,
      onError: Colors.white,
      surface: LuxeColors.lightPanel,
      onSurface: LuxeColors.lightText,
      onSurfaceVariant: LuxeColors.lightTextDim,
      outline: LuxeColors.lightLine,
      outlineVariant: LuxeColors.lightLine,
      shadow: Color(0x14000000),
      scrim: Color(0x99000000),
      inverseSurface: LuxeColors.darkCard,
      onInverseSurface: LuxeColors.darkText,
      inversePrimary: Color(0xFF8E9FF0),
      surfaceTint: Colors.transparent,
    );
  }

  /// Тёмная схема.
  static ColorScheme _darkScheme() {
    return const ColorScheme(
      brightness: Brightness.dark,
      primary: Color(0xFF8E9FF0),
      onPrimary: Color(0xFF11142A),
      primaryContainer: Color(0xFF2A3050),
      onPrimaryContainer: Color(0xFFD7DEFF),
      secondary: LuxeColors.darkTextDim,
      onSecondary: Color(0xFF14161A),
      error: Color(0xFFE06C6C),
      onError: Color(0xFF2A1010),
      surface: LuxeColors.darkCard,
      onSurface: LuxeColors.darkText,
      onSurfaceVariant: LuxeColors.darkTextDim,
      outline: LuxeColors.darkLine,
      outlineVariant: LuxeColors.darkLine,
      shadow: Colors.black,
      scrim: Color(0xB3000000),
      inverseSurface: LuxeColors.lightPanel,
      onInverseSurface: LuxeColors.lightText,
      inversePrimary: LuxeColors.brand,
      surfaceTint: Colors.transparent,
    );
  }

  static ThemeData light() {
    final scheme = _lightScheme();
    return _base(scheme).copyWith(
      scaffoldBackgroundColor: LuxeColors.lightBg,
    );
  }

  static ThemeData dark() {
    final scheme = _darkScheme();
    return _base(scheme).copyWith(
      scaffoldBackgroundColor: LuxeColors.darkBg,
    );
  }

  /// Общая часть обеих тем: шрифты, скругления, плотность компонентов.
  static ThemeData _base(ColorScheme scheme) {
    final isLight = scheme.brightness == Brightness.light;
    final fieldFill = isLight ? LuxeColors.lightField : LuxeColors.darkField;

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor:
          isLight ? LuxeColors.lightBg : LuxeColors.darkBg,
      // Шрифтовая шкала: плотнее и ровнее, чем умолчание Material
      textTheme: Typography.blackMountainView.apply(
        bodyColor: scheme.onSurface,
        displayColor: scheme.onSurface,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: isLight ? LuxeColors.lightPanel : LuxeColors.darkCard,
        foregroundColor: scheme.onSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: scheme.onSurface,
          fontSize: 17,
          fontWeight: FontWeight.w600,
        ),
      ),
      cardTheme: CardThemeData(
        color: scheme.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: const RoundedRectangleBorder(borderRadius: LuxeSpacing.radiusMd),
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant,
        thickness: 1,
        space: 1,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: fieldFill,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: LuxeSpacing.md, vertical: 10),
        border: const OutlineInputBorder(
          borderRadius: LuxeSpacing.radiusMd,
          borderSide: BorderSide.none,
        ),
        enabledBorder: const OutlineInputBorder(
          borderRadius: LuxeSpacing.radiusMd,
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: LuxeSpacing.radiusMd,
          borderSide: BorderSide(color: scheme.primary, width: 1.4),
        ),
        hintStyle: TextStyle(color: scheme.onSurfaceVariant, fontSize: 14),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: const RoundedRectangleBorder(borderRadius: LuxeSpacing.radiusMd),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: scheme.onSurface,
          side: BorderSide(color: scheme.outline),
          shape: const RoundedRectangleBorder(borderRadius: LuxeSpacing.radiusMd),
        ),
      ),
      listTileTheme: ListTileThemeData(
        shape: const RoundedRectangleBorder(borderRadius: LuxeSpacing.radiusMd),
        iconColor: scheme.onSurfaceVariant,
        titleTextStyle: TextStyle(
          color: scheme.onSurface,
          fontSize: 15,
          fontWeight: FontWeight.w500,
        ),
        subtitleTextStyle: TextStyle(
          color: scheme.onSurfaceVariant,
          fontSize: 13,
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: fieldFill,
        side: BorderSide.none,
        labelStyle: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
        shape: const RoundedRectangleBorder(borderRadius: LuxeSpacing.radiusSm),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(borderRadius: LuxeSpacing.radiusLg),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: isLight ? Color(0xFF23262E) : Color(0xFF2B303B),
        contentTextStyle: const TextStyle(color: Colors.white, fontSize: 13.5),
        shape: const RoundedRectangleBorder(borderRadius: LuxeSpacing.radiusMd),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        elevation: 1,
        highlightElevation: 3,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: scheme.primary,
        linearTrackColor: fieldFill,
        circularTrackColor: fieldFill,
      ),
      iconTheme: IconThemeData(color: scheme.onSurfaceVariant, size: 22),
    );
  }

  /// Фон правой панели (канала).
  static Color channelPattern(Brightness b) => b == Brightness.dark
      ? LuxeColors.channelPatternDark
      : LuxeColors.channelPattern;
}
