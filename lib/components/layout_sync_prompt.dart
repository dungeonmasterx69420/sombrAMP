import 'package:finamp/components/global_snackbar.dart';
import 'package:finamp/l10n/app_localizations.dart';
import 'package:finamp/services/layout_sync_service.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Asks whether to use the layout [saved] with the account on this device, or to keep this device's.  Returns null if
/// the question was dismissed, or couldn't be asked.
Future<LayoutChoice?> askWhichLayout(SavedLayout saved) async {
  final context = GlobalSnackbar.navigatorState?.context;
  if (context == null || !context.mounted) return null;
  return showDialog<LayoutChoice>(
    context: context,
    builder: (context) => _LayoutChoiceDialog(saved: saved),
  );
}

class _LayoutChoiceDialog extends StatelessWidget {
  const _LayoutChoiceDialog({required this.saved});

  final SavedLayout saved;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final locale = Localizations.localeOf(context).toString();
    final savedAt = DateFormat.yMMMd(locale).add_jm().format(saved.savedAt.toLocal());
    return AlertDialog(
      title: Text(l10n.layoutSyncPromptTitle),
      content: SingleChildScrollView(child: Text(l10n.layoutSyncPromptMessage(saved.savedBy, savedAt))),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(LayoutChoice.device),
          child: Text(l10n.layoutSyncKeepDeviceLayout),
        ),
        TextButton(
          autofocus: true,
          onPressed: () => Navigator.of(context).pop(LayoutChoice.saved),
          child: Text(l10n.layoutSyncUseSavedLayout),
        ),
      ],
    );
  }
}
