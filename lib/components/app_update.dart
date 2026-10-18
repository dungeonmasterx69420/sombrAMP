import 'package:finamp/components/global_snackbar.dart';
import 'package:finamp/l10n/app_localizations.dart';
import 'package:finamp/services/app_update_service.dart';
import 'package:finamp/services/finamp_settings_helper.dart';
import 'package:finamp/sombra/system_s_widgets.dart';
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:logging/logging.dart';

final _appUpdateLogger = Logger("AppUpdate");

/// Checks GitHub for a newer build of the app.  When [quiet], as on startup, nothing is shown unless an update is
/// available, and then only a snackbar offering it.
Future<void> checkForAppUpdate({bool quiet = false}) async {
  if (!AppUpdateService.isSupported || (quiet && FinampSettingsHelper.finampSettings.isOffline)) {
    return;
  }
  try {
    final update = await GetIt.instance<AppUpdateService>().findUpdate();
    if (update == null) {
      if (!quiet) {
        GlobalSnackbar.message(
          (scaffold) => AppLocalizations.of(scaffold)!.appUpdateUpToDate(Sombra.productName),
          isConfirmation: true,
        );
      }
    } else if (quiet) {
      GlobalSnackbar.message(
        (scaffold) => AppLocalizations.of(scaffold)!.appUpdateAvailable(Sombra.productName),
        action: (scaffold) => SnackBarAction(
          label: AppLocalizations.of(scaffold)!.appUpdateAction,
          onPressed: () => showAppUpdateDialog(update),
        ),
      );
    } else {
      await showAppUpdateDialog(update);
    }
  } catch (e) {
    _appUpdateLogger.warning("Couldn't check for updates: $e");
    if (!quiet) {
      GlobalSnackbar.error(e);
    }
  }
}

/// Offers [update], and downloads and opens it in Android's installer if accepted.
Future<void> showAppUpdateDialog(AppUpdate update) async {
  final context = GlobalSnackbar.navigatorState?.context;
  if (context == null || !context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (context) => _AppUpdateDialog(update: update),
  );
}

class _AppUpdateDialog extends StatefulWidget {
  const _AppUpdateDialog({required this.update});

  final AppUpdate update;

  @override
  State<_AppUpdateDialog> createState() => _AppUpdateDialogState();
}

class _AppUpdateDialogState extends State<_AppUpdateDialog> {
  bool _downloading = false;
  double? _progress;

  Future<void> _install() async {
    setState(() => _downloading = true);
    try {
      await GetIt.instance<AppUpdateService>().install(
        widget.update,
        onProgress: (progress) {
          if (mounted) setState(() => _progress = progress);
        },
      );
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      _appUpdateLogger.severe("Couldn't install build ${widget.update.buildNumber}", e);
      GlobalSnackbar.error(e);
      if (mounted) setState(() => _downloading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return AlertDialog(
      title: Text(l10n.appUpdateDialogTitle(widget.update.buildNumber)),
      content: _downloading
          ? Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l10n.appUpdateDownloading),
                const SizedBox(height: 12),
                LinearProgressIndicator(value: _progress),
              ],
            )
          : SingleChildScrollView(
              child: Text(widget.update.notes.isEmpty ? l10n.appUpdateNoNotes : widget.update.notes),
            ),
      actions: [
        TextButton(
          onPressed: _downloading ? null : () => Navigator.of(context).pop(),
          child: Text(l10n.appUpdateLater),
        ),
        TextButton(onPressed: _downloading ? null : _install, child: Text(l10n.appUpdateInstall)),
      ],
    );
  }
}
