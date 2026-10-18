import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// What a long press does, for a remote: holding select, or pressing the menu key.
///
/// Widgets that do something on a long press offer it with [RemoteLongPress], and [TelevisionRemote] sends this
/// intent to the focused widget.
class LongPressIntent extends Intent {
  const LongPressIntent();
}

/// Lets a remote do [onLongPress] while the focus is on a widget inside [child].
class RemoteLongPress extends StatelessWidget {
  const RemoteLongPress({super.key, required this.onLongPress, required this.child});

  /// When null, the focused widget has no long press, and its ancestors' aren't used either.
  final VoidCallback? onLongPress;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Actions(actions: {LongPressIntent: _LongPressAction(onLongPress)}, child: child);
  }
}

class _LongPressAction extends Action<LongPressIntent> {
  _LongPressAction(this.onLongPress);

  final VoidCallback? onLongPress;

  @override
  bool isEnabled(LongPressIntent intent) => onLongPress != null;

  @override
  bool invoke(LongPressIntent intent) {
    onLongPress!();
    return true;
  }
}

/// Drives the app with a TV remote, which has a D-pad, select and back, and maybe a menu key.
///
/// - Navigation is [NavigationMode.directional]: sliders only take left and right, so up and down always move the
///   focus, and controls keep the focus when they're disabled.
/// - Select activates the focused widget when it's released, and holding it does what a long press does
///   ([LongPressIntent]). The menu key does that too. Without this, holding select would activate the widget again
///   with every key repeat.
class TelevisionRemote extends StatefulWidget {
  const TelevisionRemote({super.key, required this.child});

  final Widget child;

  /// How long select is held before it counts as a long press.
  static const longPressTimeout = kLongPressTimeout;

  @override
  State<TelevisionRemote> createState() => _TelevisionRemoteState();
}

class _TelevisionRemoteState extends State<TelevisionRemote> {
  static final _selectKeys = {
    LogicalKeyboardKey.select,
    LogicalKeyboardKey.enter,
    LogicalKeyboardKey.numpadEnter,
    LogicalKeyboardKey.gameButtonA,
  };

  /// The select key that's down, while this handles it.
  LogicalKeyboardKey? _held;
  Timer? _longPressTimer;
  bool _longPressed = false;

  @override
  void dispose() {
    _longPressTimer?.cancel();
    super.dispose();
  }

  static bool _longPress() {
    final context = FocusManager.instance.primaryFocus?.context;
    return context != null && Actions.maybeInvoke(context, const LongPressIntent()) == true;
  }

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.contextMenu) {
      return event is KeyDownEvent && _longPress() ? KeyEventResult.handled : KeyEventResult.ignored;
    }
    if (!_selectKeys.contains(key)) return KeyEventResult.ignored;

    switch (event) {
      case KeyDownEvent():
        // Text fields take enter themselves.
        final focused = FocusManager.instance.primaryFocus?.context;
        if (focused == null || focused.findAncestorStateOfType<EditableTextState>() != null) {
          _held = null;
          return KeyEventResult.ignored;
        }
        _held = key;
        _longPressed = false;
        _longPressTimer?.cancel();
        _longPressTimer = Timer(TelevisionRemote.longPressTimeout, () => _longPressed = _longPress());
        return KeyEventResult.handled;
      case KeyRepeatEvent():
        return key == _held ? KeyEventResult.handled : KeyEventResult.ignored;
      case KeyUpEvent():
        if (key != _held) return KeyEventResult.ignored;
        _held = null;
        _longPressTimer?.cancel();
        if (!_longPressed) {
          final focused = FocusManager.instance.primaryFocus?.context;
          if (focused != null) Actions.maybeInvoke(focused, const ActivateIntent());
        }
        return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return MediaQuery(
      data: MediaQuery.of(context).copyWith(navigationMode: NavigationMode.directional),
      child: Focus(canRequestFocus: false, skipTraversal: true, onKeyEvent: _onKeyEvent, child: widget.child),
    );
  }
}
