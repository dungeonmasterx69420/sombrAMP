import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/widgets.dart';

bool get isDesktop => Platform.isWindows || Platform.isLinux || Platform.isMacOS;

/// Whether the app runs on Android TV or Google TV, and so is driven with a remote. Set by [detectTelevision].
bool get isTelevision => _isTelevision;
bool _isTelevision = false;

/// Finds out whether the app runs on a TV, before the app starts.
Future<void> detectTelevision() async {
  if (Platform.isAndroid) {
    _isTelevision = (await DeviceInfoPlugin().androidInfo).systemFeatures.contains('android.software.leanback');
  }
}

/// A focus node for sliders that the keyboard skips. On TVs there's no other way to reach them, so they stay
/// reachable: the remote moves them with left and right (see [NavigationMode.directional]).
FocusNode? keyboardSkippedSliderFocusNode() =>
    isTelevision ? null : FocusNode(skipTraversal: true, canRequestFocus: false);

class ShortcutKeyDisplay {
  static String get primaryModifier => Platform.isIOS || Platform.isMacOS ? '⌘' : 'Ctrl';
  static String get shift => Platform.isIOS || Platform.isMacOS ? '⇧' : 'Shift';
  static String get alt => Platform.isIOS || Platform.isMacOS ? '⌥' : 'Alt';
  static String get enter => Platform.isIOS || Platform.isMacOS ? '⏎' : 'Enter';
  static String get backspace => Platform.isIOS || Platform.isMacOS ? '⌫' : 'Backspace';
}
