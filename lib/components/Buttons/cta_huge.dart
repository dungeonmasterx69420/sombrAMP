import 'package:finamp/services/feedback_helper.dart';
import 'package:flutter/material.dart';

class CTAHuge extends StatelessWidget {
  final String text;
  final IconData icon;
  final bool vertical;
  final void Function() onPressed;
  final bool disabled;

  const CTAHuge({
    super.key,
    required this.text,
    required this.icon,
    this.vertical = false,
    required this.onPressed,
    this.disabled = false,
  });

  @override
  Widget build(BuildContext context) {
    // Styled by the theme: System S's default button, with the outer ring.
    return FilledButton(
      onPressed: disabled
          ? null
          : () {
              FeedbackHelper.feedback(FeedbackType.selection);
              onPressed();
            },
      style: const ButtonStyle(
        minimumSize: WidgetStatePropertyAll(Size(64, 48)),
        padding: WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 24, vertical: 12)),
      ),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        direction: vertical ? Axis.vertical : Axis.horizontal,
        alignment: vertical ? WrapAlignment.center : WrapAlignment.start,
        children: [Icon(icon, size: 22, weight: 1.5), const SizedBox(width: 12), Text(text)],
      ),
    );
  }
}
