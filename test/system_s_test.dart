import 'package:finamp/sombra/system_s.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('System S theme', () {
    test('dark is ink on black with amber for what is live', () {
      final theme = systemSThemeData(Brightness.dark);
      final s = theme.extension<SystemSTheme>()!;
      expect(theme.colorScheme.surface, const Color(0xFF0A0A0A));
      expect(theme.colorScheme.onSurface, const Color(0xFFEDEDED));
      expect(theme.colorScheme.primary, const Color(0xFFEDEDED));
      expect(s.phosphor, SystemSPhosphor.amber.glow);
      expect(theme.progressIndicatorTheme.color, SystemSPhosphor.amber.glow);
    });

    test('light uses the paper palette and the darker phosphor ink', () {
      final theme = systemSThemeData(Brightness.light, accent: SystemSPhosphor.cyan.glow);
      final s = theme.extension<SystemSTheme>()!;
      expect(theme.colorScheme.surface, const Color(0xFFCFCFCF));
      expect(s.palette.pane, const Color(0xFFFFFFFF));
      expect(s.phosphor, SystemSPhosphor.cyan.glow);
      expect(s.phosphorInk, SystemSPhosphor.cyan.inkOnLight);
    });

    test('the focus is shown in the phosphor', () {
      final theme = systemSThemeData(Brightness.dark);
      final s = theme.extension<SystemSTheme>()!;
      const focused = {WidgetState.focused};
      expect(theme.focusColor, s.focus);
      expect(theme.outlinedButtonTheme.style!.side!.resolve(focused), BorderSide(color: s.phosphorInk, width: 2));
      expect(theme.filledButtonTheme.style!.side!.resolve({...focused, WidgetState.disabled})?.color, s.phosphorInk);
      expect(theme.textButtonTheme.style!.backgroundColor!.resolve(focused), s.focus);
      expect(theme.iconButtonTheme.style!.overlayColor!.resolve(focused), s.focus);
      expect(theme.iconButtonTheme.style!.overlayColor!.resolve({WidgetState.hovered}), isNull);
    });

    test('AMOLED only blackens the dark theme', () {
      expect(SystemSTheme.resolve(Brightness.dark, amoled: true).palette.pane, const Color(0xFF000000));
      expect(SystemSTheme.resolve(Brightness.light, amoled: true).palette.pane, const Color(0xFFFFFFFF));
    });
  });
}
