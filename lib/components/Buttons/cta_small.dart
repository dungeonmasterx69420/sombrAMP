import 'package:finamp/services/feedback_helper.dart';
import 'package:finamp/sombra/system_s.dart';
import 'package:flutter/material.dart';

class CTASmall extends StatelessWidget {
  final String text;
  final IconData icon;
  final bool vertical;
  final bool disabled;
  final void Function() onPressed;

  const CTASmall({
    super.key,
    required this.text,
    required this.icon,
    this.vertical = false,
    this.disabled = false,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    // Styled by the theme: System S's small button.
    return OutlinedButton(
      onPressed: disabled
          ? null
          : () {
              FeedbackHelper.feedback(FeedbackType.selection);
              onPressed();
            },
      style: const ButtonStyle(
        minimumSize: WidgetStatePropertyAll(Size(48, 34)),
        shape: WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(8)))),
        padding: WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 12, vertical: 8)),
        textStyle: WidgetStatePropertyAll(
          TextStyle(fontFamily: SystemSFonts.pixel, fontFeatures: SystemSFonts.pixelFeatures, fontSize: 14, height: 1),
        ),
      ),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        direction: vertical ? Axis.vertical : Axis.horizontal,
        alignment: vertical ? WrapAlignment.center : WrapAlignment.start,
        children: [Icon(icon, size: 20, weight: 1.0), const SizedBox(width: 8, height: 4), Text(text)],
      ),
    );
  }
}
