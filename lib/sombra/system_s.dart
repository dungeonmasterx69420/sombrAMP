import 'package:finamp/extensions/color_extensions.dart';
import 'package:finamp/sombra/sombrio_host.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// sombra System S, the design system behind sombra.wtf, ported to Flutter.
///
/// A 1-bit desktop: ink on black (dark, the default) or on paper white (light), hard edges, extruded
/// shadows taken from the S mark, and one phosphor colour that marks whatever is live. Every token here is
/// copied from System S; change it there first and mirror it here.

abstract final class SystemSFonts {
  /// Titles, labels, buttons and menus (`--pixel`).
  static const pixel = '${SombrioHost.fontPrefix}PixelifySans';

  /// Pixelify Sans's "fi" and "fl" ligatures draw as broken glyphs ("Jellyfin" reads "JellyÆn"), so every
  /// Pixelify style turns them off.
  static const pixelFeatures = [FontFeature.disable('liga')];

  /// Body text and figures (`--mono`).
  static const mono = '${SombrioHost.fontPrefix}IBMPlexMono';
}

@immutable
class SystemSPalette {
  const SystemSPalette._({
    required this.brightness,
    required this.desk,
    required this.deskDot,
    required this.pane,
    required this.well,
    required this.ink,
    required this.muted,
    required this.faint,
    required this.idle,
    required this.inset,
    required this.hover,
    required this.scrim,
  });

  final Brightness brightness;

  /// The desktop behind every window.
  final Color desk;

  /// The dot grid on the desktop.
  final Color deskDot;

  /// Windows, menus and the menu bar.
  final Color pane;

  /// Text fields and address boxes.
  final Color well;

  /// Text, borders and the shadow of the active window.
  final Color ink;
  final Color muted;
  final Color faint;

  /// The shadow of inactive windows.
  final Color idle;

  /// The inner shadow of text fields.
  final Color inset;
  final Color hover;
  final Color scrim;

  static const dark = SystemSPalette._(
    brightness: Brightness.dark,
    desk: Color(0xFF0A0A0A),
    deskDot: Color(0xFF242424),
    pane: Color(0xFF0E0E0E),
    well: Color(0xFF070707),
    ink: Color(0xFFEDEDED),
    muted: Color(0xFFA3A3A3),
    faint: Color(0xFF6A6A6A),
    idle: Color(0xFF4A4A4A),
    inset: Color(0xFF2A2A2A),
    hover: Color(0xFF1B1B1B),
    scrim: Color(0x8C000000),
  );

  static const light = SystemSPalette._(
    brightness: Brightness.light,
    desk: Color(0xFFCFCFCF),
    deskDot: Color(0xFF9E9E9E),
    pane: Color(0xFFFFFFFF),
    well: Color(0xFFFFFFFF),
    ink: Color(0xFF111111),
    muted: Color(0xFF555555),
    faint: Color(0xFF8A8A8A),
    idle: Color(0xFF8C8C8C),
    inset: Color(0xFFDADADA),
    hover: Color(0xFFEFEFEF),
    scrim: Color(0x8CFFFFFF),
  );

  static SystemSPalette of(Brightness brightness) => brightness == Brightness.dark ? dark : light;

  /// The dark palette with true-black backgrounds, for the AMOLED setting.
  SystemSPalette get amoled => brightness == Brightness.light
      ? this
      : SystemSPalette._(
          brightness: brightness,
          desk: const Color(0xFF000000),
          deskDot: deskDot,
          pane: const Color(0xFF000000),
          well: const Color(0xFF000000),
          ink: ink,
          muted: muted,
          faint: faint,
          idle: idle,
          inset: inset,
          hover: hover,
          scrim: scrim,
        );
}

/// The phosphor colours System S offers. Amber is the default.
enum SystemSPhosphor {
  amber(Color(0xFFFFB000), Color(0xFF8A5A00)),
  green(Color(0xFF7CFF6B), Color(0xFF1F7A12)),
  cyan(Color(0xFF6BD6FF), Color(0xFF00698F)),
  pink(Color(0xFFFF7AB6), Color(0xFFB0246A));

  const SystemSPhosphor(this.glow, this.inkOnLight);

  /// The phosphor itself (`--phosphor`), and its ink on the dark theme.
  final Color glow;

  /// Its ink on the light theme (`--phosphor-ink`), dark enough to read on paper white.
  final Color inkOnLight;
}

/// System S values that don't fit in a [ColorScheme], available via `SystemSTheme.of(context)`.
@immutable
class SystemSTheme extends ThemeExtension<SystemSTheme> {
  const SystemSTheme({
    required this.palette,
    required this.phosphor,
    required this.phosphorInk,
    required this.onPhosphor,
  });

  factory SystemSTheme.resolve(Brightness brightness, {Color? accent, bool amoled = false}) {
    var palette = SystemSPalette.of(brightness);
    if (amoled) palette = palette.amoled;
    final preset = SystemSPhosphor.values.where((each) => each.glow == accent).firstOrNull;
    final glow = accent ?? SystemSPhosphor.amber.glow;
    final Color ink;
    if (brightness == Brightness.dark) {
      ink = glow;
    } else {
      // A custom phosphor gets darkened until it reads on paper white, like System S's own light inks.
      ink =
          preset?.inkOnLight ??
          (accent == null ? SystemSPhosphor.amber.inkOnLight : glow.atContrast(4.5, palette.pane, false));
    }
    return SystemSTheme(
      palette: palette,
      phosphor: glow,
      phosphorInk: ink,
      onPhosphor: brightness == Brightness.dark ? const Color(0xFF0A0A0A) : const Color(0xFF111111),
    );
  }

  final SystemSPalette palette;

  /// The phosphor as a fill: progress, live chips, the menu bar square (`--phosphor`).
  final Color phosphor;

  /// The phosphor as text, icons and outlines on a pane (`--phosphor-ink`).
  final Color phosphorInk;

  /// Text on a phosphor fill (`--on-phosphor`).
  final Color onPhosphor;

  /// The tint over what has the keyboard or remote focus: the focus is live too, so it's the phosphor.
  Color get focus => phosphor.withValues(alpha: 0.3);

  static SystemSTheme of(BuildContext context) =>
      Theme.of(context).extension<SystemSTheme>() ?? SystemSTheme.resolve(Theme.brightnessOf(context));

  @override
  SystemSTheme copyWith({SystemSPalette? palette, Color? phosphor, Color? phosphorInk, Color? onPhosphor}) =>
      SystemSTheme(
        palette: palette ?? this.palette,
        phosphor: phosphor ?? this.phosphor,
        phosphorInk: phosphorInk ?? this.phosphorInk,
        onPhosphor: onPhosphor ?? this.onPhosphor,
      );

  // 1-bit: no in-between colours.
  @override
  SystemSTheme lerp(SystemSTheme? other, double t) => other == null || t < 0.5 ? this : other;
}

/// The [ColorScheme] System S maps onto Material.
///
/// Controls are ink on pane, so `primary` is ink. The phosphor only marks what is live (playing,
/// downloading, focused) and lives in `secondary`/`tertiary`. System S has no red: problems are shown
/// inverted, ink on pane, so `error` is ink too.
ColorScheme systemSColorScheme(SystemSTheme s) {
  final p = s.palette;
  return ColorScheme(
    brightness: p.brightness,
    primary: p.ink,
    onPrimary: p.pane,
    primaryContainer: p.hover,
    onPrimaryContainer: p.ink,
    secondary: s.phosphorInk,
    onSecondary: s.onPhosphor,
    secondaryContainer: p.ink,
    onSecondaryContainer: p.pane,
    tertiary: s.phosphorInk,
    onTertiary: s.onPhosphor,
    tertiaryContainer: p.hover,
    onTertiaryContainer: p.ink,
    error: p.ink,
    onError: p.pane,
    errorContainer: p.ink,
    onErrorContainer: p.pane,
    surface: p.desk,
    onSurface: p.ink,
    onSurfaceVariant: p.muted,
    surfaceDim: p.well,
    surfaceBright: p.hover,
    surfaceContainerLowest: p.pane,
    surfaceContainerLow: p.pane,
    surfaceContainer: p.pane,
    surfaceContainerHigh: p.pane,
    surfaceContainerHighest: p.pane,
    outline: p.ink,
    outlineVariant: p.faint,
    shadow: Colors.transparent,
    scrim: p.scrim.withValues(alpha: 1.0),
    inverseSurface: p.ink,
    onInverseSurface: p.pane,
    inversePrimary: p.pane,
    surfaceTint: Colors.transparent,
  );
}

TextTheme _systemSTextTheme() {
  TextStyle pixel(double size, FontWeight weight) => TextStyle(
    fontFamily: SystemSFonts.pixel,
    fontFeatures: SystemSFonts.pixelFeatures,
    fontSize: size,
    fontWeight: weight,
    letterSpacing: 0,
  );
  TextStyle mono(double size, FontWeight weight) =>
      TextStyle(fontFamily: SystemSFonts.mono, fontSize: size, fontWeight: weight, letterSpacing: 0);
  return TextTheme(
    // The big library count.
    displayLarge: pixel(57, FontWeight.w600),
    displayMedium: pixel(45, FontWeight.w600),
    displaySmall: pixel(36, FontWeight.w600),
    // "Welcome back."
    headlineLarge: pixel(32, FontWeight.w400),
    headlineMedium: pixel(28, FontWeight.w400),
    headlineSmall: pixel(24, FontWeight.w400),
    // App names, step titles, group headings.
    titleLarge: pixel(22, FontWeight.w400),
    titleMedium: pixel(17, FontWeight.w500),
    titleSmall: pixel(14, FontWeight.w500),
    // Buttons, field labels, tags.
    labelLarge: pixel(15, FontWeight.w400),
    labelMedium: pixel(14, FontWeight.w400),
    labelSmall: pixel(12, FontWeight.w400),
    // Field text, body, row details.
    bodyLarge: mono(15, FontWeight.w400),
    bodyMedium: mono(13, FontWeight.w400),
    bodySmall: mono(12, FontWeight.w400),
  );
}

/// System S's buttons: ink-outlined panes that invert while pressed. The default button of a group gets
/// the extra ring.
ButtonStyle systemSButtonStyle(SystemSTheme s, {bool isDefault = false}) {
  final p = s.palette;
  return ButtonStyle(
    textStyle: const WidgetStatePropertyAll(
      TextStyle(
        fontFamily: SystemSFonts.pixel,
        fontFeatures: SystemSFonts.pixelFeatures,
        fontSize: 15,
        fontWeight: FontWeight.w400,
        height: 1,
      ),
    ),
    minimumSize: const WidgetStatePropertyAll(Size(64, 40)),
    padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 18)),
    elevation: const WidgetStatePropertyAll(0),
    shadowColor: const WidgetStatePropertyAll(Colors.transparent),
    surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
    overlayColor: const WidgetStatePropertyAll(Colors.transparent),
    splashFactory: NoSplash.splashFactory,
    backgroundColor: WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.disabled)) return p.pane;
      if (states.contains(WidgetState.pressed)) return p.ink;
      if (states.contains(WidgetState.hovered)) return p.hover;
      return p.pane;
    }),
    foregroundColor: WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.disabled)) return p.faint;
      if (states.contains(WidgetState.pressed)) return p.pane;
      return p.ink;
    }),
    iconColor: WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.disabled)) return p.faint;
      if (states.contains(WidgetState.pressed)) return p.pane;
      return p.ink;
    }),
    side: WidgetStateProperty.resolveWith((states) {
      // The focus edges a button in the phosphor, like a focused text field. A remote can focus disabled buttons too.
      if (states.contains(WidgetState.focused)) return BorderSide(color: s.phosphorInk, width: 2);
      return BorderSide(color: states.contains(WidgetState.disabled) ? p.faint : p.ink);
    }),
    shape: WidgetStatePropertyAll(
      SystemSButtonBorder(radius: 10, ringGap: isDefault ? p.pane : null, ring: isDefault ? p.ink : null),
    ),
  );
}

/// Borderless buttons, like System S's menu bar items and disclosure rows: a hover tint, and a darker
/// one while pressed (callers often set their own text colour, so it doesn't invert).
ButtonStyle systemSTextButtonStyle(SystemSTheme s) {
  final p = s.palette;
  return ButtonStyle(
    textStyle: const WidgetStatePropertyAll(
      TextStyle(
        fontFamily: SystemSFonts.pixel,
        fontFeatures: SystemSFonts.pixelFeatures,
        fontSize: 15,
        fontWeight: FontWeight.w400,
        height: 1,
      ),
    ),
    elevation: const WidgetStatePropertyAll(0),
    shadowColor: const WidgetStatePropertyAll(Colors.transparent),
    surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
    overlayColor: const WidgetStatePropertyAll(Colors.transparent),
    splashFactory: NoSplash.splashFactory,
    backgroundColor: WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.focused)) return s.focus;
      if (states.contains(WidgetState.disabled)) return Colors.transparent;
      if (states.contains(WidgetState.pressed)) return p.inset;
      if (states.contains(WidgetState.hovered)) return p.hover;
      return Colors.transparent;
    }),
    foregroundColor: WidgetStateProperty.resolveWith(
      (states) => states.contains(WidgetState.disabled) ? p.faint : p.ink,
    ),
    iconColor: WidgetStateProperty.resolveWith((states) => states.contains(WidgetState.disabled) ? p.faint : p.ink),
    shape: const WidgetStatePropertyAll(RoundedRectangleBorder()),
  );
}

/// Builds the app's [ThemeData] from System S.
///
/// [accent] is the user's chosen phosphor (one of [SystemSPhosphor], or a custom colour); null means amber.
ThemeData systemSThemeData(
  Brightness brightness, {
  Color? accent,
  bool amoled = false,
  PageTransitionsTheme? pageTransitionsTheme,
}) {
  final s = SystemSTheme.resolve(brightness, accent: accent, amoled: amoled);
  final p = s.palette;
  final scheme = systemSColorScheme(s);
  final text = _systemSTextTheme();
  final button = systemSButtonStyle(s);
  final isDark = brightness == Brightness.dark;

  final pixel15 = TextStyle(
    fontFamily: SystemSFonts.pixel,
    fontFeatures: SystemSFonts.pixelFeatures,
    fontSize: 15,
    height: 1.35,
    color: p.ink,
  );

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    fontFamily: SystemSFonts.mono,
    textTheme: text,
    extensions: [s],
    scaffoldBackgroundColor: p.desk,
    canvasColor: p.pane,
    cardColor: p.pane,
    dividerColor: p.faint,
    disabledColor: p.faint,
    hoverColor: p.hover,
    highlightColor: p.inset,
    focusColor: s.focus,
    splashColor: Colors.transparent,
    splashFactory: NoSplash.splashFactory,
    applyElevationOverlayColor: false,
    pageTransitionsTheme: pageTransitionsTheme,
    // The menu bar: a pane with an ink rule under it.
    appBarTheme: AppBarThemeData(
      backgroundColor: p.pane,
      foregroundColor: p.ink,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      shape: Border(bottom: BorderSide(color: p.ink)),
      titleTextStyle: text.titleLarge!.copyWith(color: p.ink),
      systemOverlayStyle: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarBrightness: brightness,
        statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
        systemNavigationBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
      ),
    ),
    iconTheme: IconThemeData(color: p.ink),
    elevatedButtonTheme: ElevatedButtonThemeData(style: button),
    outlinedButtonTheme: OutlinedButtonThemeData(style: button),
    textButtonTheme: TextButtonThemeData(style: systemSTextButtonStyle(s)),
    // Icon buttons have no edge of their own, so the focus tints them like a list row. Other states keep Material's.
    iconButtonTheme: IconButtonThemeData(
      style: ButtonStyle(
        overlayColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.focused) ? s.focus : null,
        ),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(style: systemSButtonStyle(s, isDefault: true)),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: p.pane,
      foregroundColor: p.ink,
      elevation: 0,
      focusElevation: 0,
      hoverElevation: 0,
      highlightElevation: 0,
      disabledElevation: 0,
      splashColor: Colors.transparent,
      shape: SystemSButtonBorder(radius: 10, side: BorderSide(color: p.ink)),
      extendedTextStyle: pixel15,
    ),
    cardTheme: CardThemeData(
      color: p.pane,
      elevation: 0,
      shadowColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      shape: SystemSWindowBorder(side: BorderSide(color: p.ink)),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: p.pane,
      elevation: 0,
      shadowColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      barrierColor: p.scrim,
      shape: SystemSWindowBorder(
        side: BorderSide(color: p.ink),
        shadow: p.ink,
        depth: 6,
        ring: p.ink,
      ),
      titleTextStyle: TextStyle(
        fontFamily: SystemSFonts.pixel,
        fontFeatures: SystemSFonts.pixelFeatures,
        fontSize: 18,
        fontWeight: FontWeight.w500,
        color: p.ink,
      ),
      contentTextStyle: text.bodyMedium!.copyWith(color: p.ink),
    ),
    // Toasts.
    snackBarTheme: SnackBarThemeData(
      //TODO get rid of floating action buttons and re-enable the floating behavior and insetPadding
      backgroundColor: p.pane,
      contentTextStyle: pixel15,
      actionTextColor: p.ink,
      elevation: 0,
      shape: SystemSWindowBorder(
        side: BorderSide(color: p.ink),
        shadow: p.ink,
        depth: 3,
        stepped: false,
      ),
      dismissDirection: DismissDirection.horizontal,
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: p.pane,
      elevation: 0,
      shadowColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      shape: SystemSWindowBorder(
        side: BorderSide(color: p.ink),
        shadow: p.ink,
        depth: 2,
        stepped: false,
      ),
      textStyle: pixel15,
      labelTextStyle: WidgetStatePropertyAll(pixel15),
      menuPadding: const EdgeInsets.symmetric(vertical: 4),
      iconColor: p.ink,
    ),
    menuTheme: MenuThemeData(
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(p.pane),
        elevation: const WidgetStatePropertyAll(0),
        shadowColor: const WidgetStatePropertyAll(Colors.transparent),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        shape: WidgetStatePropertyAll(
          SystemSWindowBorder(
            side: BorderSide(color: p.ink),
            shadow: p.ink,
            depth: 2,
            stepped: false,
          ),
        ),
        padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(vertical: 4)),
      ),
    ),
    tooltipTheme: TooltipThemeData(
      waitDuration: const Duration(milliseconds: 800),
      preferBelow: false,
      textStyle: text.bodySmall!.copyWith(color: p.ink),
      decoration: BoxDecoration(
        color: p.pane,
        border: Border.all(color: p.ink),
        boxShadow: [BoxShadow(color: p.ink, offset: const Offset(2, 2))],
      ),
    ),
    inputDecorationTheme: InputDecorationThemeData(
      filled: true,
      fillColor: p.well,
      hoverColor: p.well,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      border: SystemSFieldBorder(
        borderSide: BorderSide(color: p.ink),
        inset: p.inset,
      ),
      enabledBorder: SystemSFieldBorder(
        borderSide: BorderSide(color: p.ink),
        inset: p.inset,
      ),
      focusedBorder: SystemSFieldBorder(
        borderSide: BorderSide(color: s.phosphorInk, width: 2),
        inset: p.inset,
      ),
      errorBorder: SystemSFieldBorder(
        borderSide: BorderSide(color: p.ink, width: 2),
        inset: p.inset,
      ),
      focusedErrorBorder: SystemSFieldBorder(
        borderSide: BorderSide(color: s.phosphorInk, width: 2),
        inset: p.inset,
      ),
      disabledBorder: SystemSFieldBorder(borderSide: BorderSide(color: p.faint)),
      labelStyle: text.labelMedium!.copyWith(color: p.muted),
      floatingLabelStyle: text.labelMedium!.copyWith(color: p.ink),
      hintStyle: text.bodyLarge!.copyWith(color: p.faint),
      helperStyle: text.bodySmall!.copyWith(color: p.muted),
      errorStyle: text.bodySmall!.copyWith(color: p.ink, fontWeight: FontWeight.w600),
      prefixIconColor: p.ink,
      suffixIconColor: p.ink,
    ),
    radioTheme: RadioThemeData(
      fillColor: WidgetStateProperty.resolveWith((states) => states.contains(WidgetState.disabled) ? p.faint : p.ink),
      overlayColor: const WidgetStatePropertyAll(Colors.transparent),
      backgroundColor: WidgetStatePropertyAll(p.pane),
      side: BorderSide(color: p.ink),
      innerRadius: const WidgetStatePropertyAll(3.5),
    ),
    checkboxTheme: CheckboxThemeData(
      shape: const RoundedRectangleBorder(),
      side: WidgetStateBorderSide.resolveWith(
        (states) => BorderSide(color: states.contains(WidgetState.disabled) ? p.faint : p.ink),
      ),
      fillColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return states.contains(WidgetState.disabled) ? p.faint : p.ink;
        return p.pane;
      }),
      checkColor: WidgetStatePropertyAll(p.pane),
      overlayColor: const WidgetStatePropertyAll(Colors.transparent),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.disabled)) return p.faint;
        return states.contains(WidgetState.selected) ? p.pane : p.ink;
      }),
      trackColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return states.contains(WidgetState.disabled) ? p.faint : p.ink;
        return p.pane;
      }),
      trackOutlineColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.disabled) ? p.faint : p.ink,
      ),
      trackOutlineWidth: const WidgetStatePropertyAll(1),
      overlayColor: const WidgetStatePropertyAll(Colors.transparent),
    ),
    sliderTheme: SliderThemeData(
      activeTrackColor: p.ink,
      inactiveTrackColor: p.inset,
      thumbColor: p.ink,
      overlayColor: Colors.transparent,
      valueIndicatorColor: p.pane,
      valueIndicatorTextStyle: pixel15,
    ),
    // Progress is live, so it glows.
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: s.phosphor,
      linearTrackColor: p.inset,
      circularTrackColor: Colors.transparent,
    ),
    chipTheme: ChipThemeData(
      backgroundColor: p.pane,
      selectedColor: p.ink,
      disabledColor: p.pane,
      checkmarkColor: p.pane,
      side: BorderSide(color: p.ink),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(8))),
      elevation: 0,
      pressElevation: 0,
      shadowColor: Colors.transparent,
      selectedShadowColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      // Chips resolve state on the label colour, not on the whole style.
      labelStyle: TextStyle(
        fontFamily: SystemSFonts.pixel,
        fontFeatures: SystemSFonts.pixelFeatures,
        fontSize: 14,
        color: WidgetStateColor.resolveWith((states) => states.contains(WidgetState.selected) ? p.pane : p.ink),
      ),
      iconTheme: IconThemeData(color: p.ink, size: 18),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: button.copyWith(
        backgroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return p.ink;
          if (states.contains(WidgetState.hovered)) return p.hover;
          return p.pane;
        }),
        foregroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) return p.faint;
          return states.contains(WidgetState.selected) ? p.pane : p.ink;
        }),
        iconColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) return p.faint;
          return states.contains(WidgetState.selected) ? p.pane : p.ink;
        }),
        shape: const WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(8)))),
      ),
    ),
    // Tabs read like the menu bar: the current one is inverted.
    tabBarTheme: TabBarThemeData(
      labelColor: p.pane,
      unselectedLabelColor: p.ink,
      labelStyle: pixel15,
      unselectedLabelStyle: pixel15,
      indicator: BoxDecoration(color: p.ink),
      indicatorSize: TabBarIndicatorSize.tab,
      dividerColor: p.ink,
      dividerHeight: 1,
      overlayColor: const WidgetStatePropertyAll(Colors.transparent),
      splashFactory: NoSplash.splashFactory,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: p.pane,
      indicatorColor: p.ink,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      indicatorShape: const RoundedRectangleBorder(),
      labelTextStyle: WidgetStatePropertyAll(text.labelMedium!.copyWith(color: p.ink)),
    ),
    drawerTheme: DrawerThemeData(
      backgroundColor: p.pane,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrimColor: p.scrim,
      shape: Border(right: BorderSide(color: p.ink)),
      endShape: Border(left: BorderSide(color: p.ink)),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: p.pane,
      modalBackgroundColor: p.pane,
      surfaceTintColor: Colors.transparent,
      shadowColor: Colors.transparent,
      elevation: 0,
      modalElevation: 0,
      modalBarrierColor: p.scrim,
      dragHandleColor: p.ink,
      shape: Border(top: BorderSide(color: p.ink)),
    ),
    listTileTheme: ListTileThemeData(
      iconColor: p.ink,
      textColor: p.ink,
      selectedColor: s.phosphorInk,
      subtitleTextStyle: text.bodyMedium!.copyWith(color: p.muted),
    ),
    dividerTheme: DividerThemeData(color: p.faint, thickness: 1),
    badgeTheme: BadgeThemeData(backgroundColor: s.phosphor, textColor: s.onPhosphor),
    scrollbarTheme: ScrollbarThemeData(thumbColor: WidgetStatePropertyAll(p.faint)),
    textSelectionTheme: TextSelectionThemeData(cursorColor: p.ink, selectionHandleColor: p.ink),
  );
}

/// A window edge: a 1px ink border, and optionally the hard shadow System S puts under windows.
///
/// [stepped] draws the extruded shadow of windows and dialogs (`--ext-on`: copies offset 1px at a time);
/// otherwise one solid offset copy, as under toasts and menus. [ring] adds the inner double border of
/// alert dialogs.
class SystemSWindowBorder extends OutlinedBorder {
  const SystemSWindowBorder({super.side, this.radius = 0, this.shadow, this.depth = 0, this.stepped = true, this.ring});

  final double radius;
  final Color? shadow;
  final double depth;
  final bool stepped;
  final Color? ring;

  RRect _shape(Rect rect) => RRect.fromRectAndRadius(rect, Radius.circular(radius));

  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.all(side.strokeInset);

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) =>
      Path()..addRRect(_shape(rect).deflate(side.strokeInset));

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) => Path()..addRRect(_shape(rect));

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {
    final shadow = this.shadow;
    if (shadow != null && depth > 0) {
      var cast = Path()..addRRect(_shape(rect.shift(Offset(depth, depth))));
      if (stepped) {
        for (var step = 1; step < depth; step++) {
          cast = Path.combine(
            PathOperation.union,
            cast,
            Path()..addRRect(_shape(rect.shift(Offset(step * 1.0, step * 1.0)))),
          );
        }
      }
      // Painted over the window's content, so only the part outside the window is drawn.
      canvas.drawPath(Path.combine(PathOperation.difference, cast, getOuterPath(rect)), Paint()..color = shadow);
    }
    if (side.style != BorderStyle.none && side.width > 0) {
      canvas.drawRRect(_shape(rect).deflate(side.strokeInset / 2), side.toPaint());
    }
    final ring = this.ring;
    if (ring != null) {
      // A 3px pane gap inside the border, then a 2px ink ring.
      canvas.drawRRect(
        _shape(rect).deflate(side.strokeInset + 4),
        Paint()
          ..color = ring
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }
  }

  @override
  ShapeBorder scale(double t) => SystemSWindowBorder(
    side: side.scale(t),
    radius: radius * t,
    shadow: shadow,
    depth: depth * t,
    stepped: stepped,
    ring: ring,
  );

  @override
  SystemSWindowBorder copyWith({BorderSide? side}) => SystemSWindowBorder(
    side: side ?? this.side,
    radius: radius,
    shadow: shadow,
    depth: depth,
    stepped: stepped,
    ring: ring,
  );

  @override
  bool operator ==(Object other) =>
      other is SystemSWindowBorder &&
      other.side == side &&
      other.radius == radius &&
      other.shadow == shadow &&
      other.depth == depth &&
      other.stepped == stepped &&
      other.ring == ring;

  @override
  int get hashCode => Object.hash(side, radius, shadow, depth, stepped, ring);
}

/// A button edge, with the default button's outer ring (a 2px gap, then a 2px ink ring) when [ring] is set.
class SystemSButtonBorder extends OutlinedBorder {
  const SystemSButtonBorder({super.side, this.radius = 10, this.ringGap, this.ring});

  final double radius;
  final Color? ringGap;
  final Color? ring;

  RRect _shape(Rect rect) => RRect.fromRectAndRadius(rect, Radius.circular(radius));

  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.all(side.strokeInset);

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) =>
      Path()..addRRect(_shape(rect).deflate(side.strokeInset));

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) => Path()..addRRect(_shape(rect));

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {
    if (side.style != BorderStyle.none && side.width > 0) {
      canvas.drawRRect(_shape(rect).deflate(side.strokeInset / 2), side.toPaint());
    }
    Paint stroke(Color color) => Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    final ringGap = this.ringGap;
    final ring = this.ring;
    if (ringGap != null) canvas.drawRRect(_shape(rect).inflate(1), stroke(ringGap));
    if (ring != null) canvas.drawRRect(_shape(rect).inflate(3), stroke(ring));
  }

  @override
  ShapeBorder scale(double t) =>
      SystemSButtonBorder(side: side.scale(t), radius: radius * t, ringGap: ringGap, ring: ring);

  @override
  SystemSButtonBorder copyWith({BorderSide? side}) =>
      SystemSButtonBorder(side: side ?? this.side, radius: radius, ringGap: ringGap, ring: ring);

  @override
  bool operator ==(Object other) =>
      other is SystemSButtonBorder &&
      other.side == side &&
      other.radius == radius &&
      other.ringGap == ringGap &&
      other.ring == ring;

  @override
  int get hashCode => Object.hash(side, radius, ringGap, ring);
}

/// A text field edge: square, 1px, with System S's 2px inner shadow along the top and left.
class SystemSFieldBorder extends OutlineInputBorder {
  const SystemSFieldBorder({super.borderSide, this.inset}) : super(borderRadius: BorderRadius.zero);

  final Color? inset;

  @override
  SystemSFieldBorder copyWith({BorderSide? borderSide, BorderRadius? borderRadius, double? gapPadding}) =>
      SystemSFieldBorder(borderSide: borderSide ?? this.borderSide, inset: inset);

  // 1-bit: borders switch rather than fade.
  @override
  ShapeBorder? lerpFrom(ShapeBorder? a, double t) => a is InputBorder && t < 0.5 ? a : this;

  @override
  ShapeBorder? lerpTo(ShapeBorder? b, double t) => b is InputBorder && t >= 0.5 ? b : this;

  @override
  void paint(
    Canvas canvas,
    Rect rect, {
    double? gapStart,
    double gapExtent = 0.0,
    double gapPercentage = 0.0,
    TextDirection? textDirection,
  }) {
    final inset = this.inset;
    if (inset != null) {
      final inner = rect.deflate(borderSide.width);
      final paint = Paint()..color = inset;
      canvas.drawRect(Rect.fromLTWH(inner.left, inner.top, inner.width, 2), paint);
      canvas.drawRect(Rect.fromLTWH(inner.left, inner.top, 2, inner.height), paint);
    }
    super.paint(
      canvas,
      rect,
      gapStart: gapStart,
      gapExtent: gapExtent,
      gapPercentage: gapPercentage,
      textDirection: textDirection,
    );
  }

  @override
  bool operator ==(Object other) => other is SystemSFieldBorder && super == other && other.inset == inset;

  @override
  int get hashCode => Object.hash(super.hashCode, inset);
}
