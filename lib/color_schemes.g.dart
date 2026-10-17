import 'package:finamp/sombra/system_s.dart';
import 'package:flutter/material.dart';

// The app's colours come from sombra System S, see lib/sombra/system_s.dart.

final lightColorScheme = systemSColorScheme(SystemSTheme.resolve(Brightness.light));

final darkColorScheme = systemSColorScheme(SystemSTheme.resolve(Brightness.dark));

/// The System S scheme for [brightness]. [color] is the user's phosphor; null means amber.
ColorScheme getColorScheme(Color? color, Brightness brightness, bool amoledTheme) =>
    systemSColorScheme(SystemSTheme.resolve(brightness, accent: color, amoled: amoledTheme));

extension WarningColorScheme on ColorScheme {
  /// System S has no warning colour; warnings are ink and rely on their wording and icon.
  Color get warning => onSurface;
}
