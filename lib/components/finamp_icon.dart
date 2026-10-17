import 'package:finamp/sombra/system_s_widgets.dart';
import 'package:flutter/material.dart';

/// The app's logo: the sombra S mark, fitted into [width] x [height].
class FinampIcon extends StatelessWidget {
  final double height;
  final double width;
  final Color? overrideColor;
  const FinampIcon(this.width, this.height, {this.overrideColor, super.key});

  @override
  Widget build(BuildContext context) {
    // The mark is 61 x 116; fit it by whichever side runs out first.
    final markHeight = height < width * 116 / 61 ? height : width * 116 / 61;
    return SizedBox(
      width: width,
      height: height,
      child: Center(
        child: SombraMark(height: markHeight, color: overrideColor ?? Theme.of(context).colorScheme.onSurface),
      ),
    );
  }
}
