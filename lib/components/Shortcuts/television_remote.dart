import 'dart:async';

import 'package:finamp/sombra/system_s.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
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
/// - What has the focus is ringed in the phosphor.
/// - Up and down leave one-line text fields, instead of moving their cursor.
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
    if (key == LogicalKeyboardKey.arrowUp || key == LogicalKeyboardKey.arrowDown) {
      // A one-line text field takes up and down to move its cursor, which would leave a remote no way out of it.
      final focused = FocusManager.instance.primaryFocus;
      final editable = focused?.context?.findAncestorStateOfType<EditableTextState>();
      if (focused == null || editable == null || editable.widget.maxLines != 1) return KeyEventResult.ignored;
      if (event is! KeyUpEvent) {
        focused.focusInDirection(key == LogicalKeyboardKey.arrowUp ? TraversalDirection.up : TraversalDirection.down);
      }
      return KeyEventResult.handled;
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
      child: Focus(
        canRequestFocus: false,
        skipTraversal: true,
        onKeyEvent: _onKeyEvent,
        child: _FocusRing(child: widget.child),
      ),
    );
  }
}

/// Rings whatever has the focus in the phosphor, over everything else. Widgets show their focus themselves too, but
/// some only faintly, and a TV is watched from across the room.
class _FocusRing extends StatefulWidget {
  const _FocusRing({required this.child});

  final Widget child;

  @override
  State<_FocusRing> createState() => _FocusRingState();
}

class _FocusRingState extends State<_FocusRing> {
  final _rect = ValueNotifier<Rect?>(null);
  bool _disposed = false;

  @override
  void initState() {
    super.initState();
    // After every frame the app draws, so the ring follows the focus as it scrolls and moves, without drawing frames
    // of its own. Persistent callbacks can't be removed, so this one stops doing anything once disposed.
    SchedulerBinding.instance.addPersistentFrameCallback((_) {
      if (!_disposed) _update();
    });
  }

  @override
  void dispose() {
    _disposed = true;
    _rect.dispose();
    super.dispose();
  }

  void _update() {
    final node = FocusManager.instance.primaryFocus;
    final focused = node is FocusScopeNode || FocusManager.instance.highlightMode == FocusHighlightMode.touch
        ? null
        : node?.context?.findRenderObject();
    final ring = context.findRenderObject();
    Rect? rect;
    if (focused is RenderBox && focused.attached && focused.hasSize && ring is RenderBox && ring.hasSize) {
      rect = MatrixUtils.transformRect(
        focused.getTransformTo(null),
        Offset.zero & focused.size,
      ).shift(-ring.localToGlobal(Offset.zero));
    }
    _rect.value = rect;
  }

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      foregroundPainter: _FocusRingPainter(_rect, SystemSTheme.of(context).phosphorInk),
      child: RepaintBoundary(child: widget.child),
    );
  }
}

class _FocusRingPainter extends CustomPainter {
  _FocusRingPainter(this.rect, this.color) : super(repaint: rect);

  final ValueListenable<Rect?> rect;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = this.rect.value;
    if (rect == null) return;
    // Like the ring of a default button: a 1px gap, then 2px.
    canvas.drawRect(
      rect.inflate(2),
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(_FocusRingPainter oldDelegate) => oldDelegate.rect != rect || oldDelegate.color != color;
}
