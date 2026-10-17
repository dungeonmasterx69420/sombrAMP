import 'package:finamp/services/feedback_helper.dart';
import 'package:flutter/material.dart';

class CTALarge extends StatelessWidget {
  final String text;
  final String? label;
  final IconData icon;
  final double? minWidth;
  final bool vertical;
  final void Function() onPressed;
  final bool disabled;

  const CTALarge({
    super.key,
    required this.text,
    this.label,
    required this.icon,
    this.minWidth,
    this.vertical = false,
    required this.onPressed,
    this.disabled = false,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: text,
      tooltip: label,
      button: true,
      focusable: true,
      onLongPressHint: label,
      excludeSemantics: true, // replace child semantics with custom semantics
      container: true,
      child: ConstrainedBox(
        constraints: BoxConstraints(minWidth: minWidth ?? 0),
        // Styled by the theme: a System S button.
        child: OutlinedButton(
          onPressed: disabled
              ? null
              : () {
                  FeedbackHelper.feedback(FeedbackType.selection);
                  onPressed();
                },
          style: const ButtonStyle(padding: WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 16, vertical: 12))),
          child: Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            direction: vertical ? Axis.vertical : Axis.horizontal,
            alignment: vertical ? WrapAlignment.center : WrapAlignment.start,
            children: [Icon(icon, size: 24, weight: 1.0), const SizedBox(width: 16, height: 8), Text(text)],
          ),
        ),
      ),
    );
  }
}
