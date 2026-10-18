import 'package:finamp/sombra/system_s.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// The product, as it is named in the app.
abstract final class Sombra {
  static const productName = 'sombrAMP';
  static const website = 'https://sombra.wtf';
  static const domain = 'sombra.wtf';
  static const sourceCode = 'https://github.com/dungeonmasterx69420/sombrAMP';

  /// The project sombrAMP is built on.
  static const finampSourceCode = 'https://github.com/finamp-app/finamp';
}

/// The S mark, drawn in [color] (the text colour by default), as on sombra.wtf.
class SombraMark extends StatelessWidget {
  const SombraMark({super.key, this.height = 116, this.color});

  final double height;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final color = this.color ?? DefaultTextStyle.of(context).style.color ?? SystemSTheme.of(context).palette.ink;
    return SvgPicture.asset(
      'images/sombra_s_mark.svg',
      height: height,
      width: height * 61 / 116,
      colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
      excludeFromSemantics: true,
    );
  }
}

/// The sombra.wtf wordmark.
class SombraWordmark extends StatelessWidget {
  const SombraWordmark({super.key, this.width = 120, this.color});

  final double width;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final color = this.color ?? DefaultTextStyle.of(context).style.color ?? SystemSTheme.of(context).palette.ink;
    return SvgPicture.asset(
      'images/sombra_wordmark.svg',
      width: width,
      height: width * 110 / 621,
      colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
      semanticsLabel: Sombra.domain,
    );
  }
}

/// The desktop: [SystemSPalette.desk] with its 4px dot grid.
class SystemSDesk extends StatelessWidget {
  const SystemSDesk({super.key, this.child});

  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final palette = SystemSTheme.of(context).palette;
    return CustomPaint(painter: _DeskPainter(palette.desk, palette.deskDot), child: child ?? const SizedBox.expand());
  }
}

class _DeskPainter extends CustomPainter {
  _DeskPainter(this.desk, this.dot);

  final Color desk;
  final Color dot;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = desk);
    final dots = Paint()..color = dot;
    for (var y = 2.0; y < size.height; y += 4) {
      for (var x = 2.0; x < size.width; x += 4) {
        canvas.drawCircle(Offset(x, y), 1.2, dots);
      }
    }
  }

  @override
  bool shouldRepaint(_DeskPainter old) => old.desk != desk || old.dot != dot;
}

/// A System S window: a pane with an ink edge, a title bar (pinstriped while active) and the extruded
/// shadow, deep and ink while active, shallower and grey while not.
class SystemSWindow extends StatelessWidget {
  const SystemSWindow({
    super.key,
    required this.title,
    required this.child,
    this.active = true,
    this.titleHeading = true,
  });

  final String title;
  final Widget child;
  final bool active;

  /// Whether the title is announced as a heading.
  final bool titleHeading;

  @override
  Widget build(BuildContext context) {
    final palette = SystemSTheme.of(context).palette;
    return Padding(
      // Room for the shadow, so it isn't clipped by whatever holds the window.
      padding: EdgeInsets.only(right: active ? 6 : 5, bottom: active ? 6 : 5),
      child: DecoratedBox(
        decoration: ShapeDecoration(
          color: palette.pane,
          shape: SystemSWindowBorder(
            side: BorderSide(color: palette.ink),
            shadow: active ? palette.ink : palette.idle,
            depth: active ? 6 : 5,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(1),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SystemSTitleBar(title: title, active: active, heading: titleHeading),
              Divider(height: 1, thickness: 1, color: palette.ink),
              child,
            ],
          ),
        ),
      ),
    );
  }
}

class SystemSTitleBar extends StatelessWidget {
  const SystemSTitleBar({super.key, required this.title, this.active = true, this.heading = true});

  final String title;
  final bool active;
  final bool heading;

  @override
  Widget build(BuildContext context) {
    final palette = SystemSTheme.of(context).palette;
    return SizedBox(
      height: 21,
      child: CustomPaint(
        painter: active ? _PinstripePainter(palette.ink) : null,
        child: Center(
          child: Semantics(
            header: heading,
            child: Container(
              color: palette.pane,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: SystemSFonts.pixel,
                  fontFeatures: SystemSFonts.pixelFeatures,
                  fontSize: 15,
                  height: 21 / 15,
                  fontWeight: active ? FontWeight.w600 : FontWeight.w500,
                  color: active ? palette.ink : palette.muted,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Five 1px lines, 3px apart, starting 4px down: the active title bar.
class _PinstripePainter extends CustomPainter {
  _PinstripePainter(this.ink);

  final Color ink;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = ink;
    for (var y = 4.0; y < 17; y += 3) {
      canvas.drawRect(Rect.fromLTWH(0, y, size.width, 1), paint);
    }
  }

  @override
  bool shouldRepaint(_PinstripePainter old) => old.ink != ink;
}
