import 'package:finamp/components/finamp_icon.dart';
import 'package:finamp/l10n/app_localizations.dart';
import 'package:finamp/sombra/sombrio_host.dart';
import 'package:finamp/sombra/system_s.dart';
import 'package:finamp/sombra/system_s_widgets.dart';
import 'package:flutter/material.dart';

/// The first screen, laid out like System S's sign-in: the S mark, one fixed window, the wordmark.
///
/// Inside Sombrio, the window offers the account Sombrio is signed in to first.
class LoginSplashPage extends StatefulWidget {
  static const routeName = "login/splash";

  final VoidCallback onGetStartedPressed;

  /// Signs in to Sombrio's account.  Completes once signed in, or throws.
  final Future<void> Function(SombrioAccount account)? onSombrioAccountPressed;

  const LoginSplashPage({super.key, required this.onGetStartedPressed, this.onSombrioAccountPressed});

  @override
  State<LoginSplashPage> createState() => _LoginSplashPageState();
}

class _LoginSplashPageState extends State<LoginSplashPage> {
  late final Future<SombrioAccount?> _sombrioAccount = SombrioHost.account();
  bool _signingIn = false;

  Future<void> _continueWith(SombrioAccount account) async {
    setState(() => _signingIn = true);
    try {
      await widget.onSombrioAccountPressed!(account);
    } finally {
      if (mounted) setState(() => _signingIn = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final palette = SystemSTheme.of(context).palette;
    final textTheme = TextTheme.of(context);
    final topGap = (MediaQuery.heightOf(context) * 0.06).clamp(16.0, 64.0);
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(16, topGap, 16, 40),
      child: Center(
        child: Column(
          children: [
            Hero(
              tag: "finamp_logo",
              child: FinampIcon(61, 116, overrideColor: palette.ink),
            ),
            const SizedBox(height: 40),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: SystemSWindow(
                title: Sombra.productName,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(18, 20, 18, 22),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        l10n.loginFlowWelcomeHeading(Sombra.productName),
                        style: textTheme.headlineSmall!.copyWith(color: palette.ink, height: 1.15),
                      ),
                      const SizedBox(height: 6),
                      Text(l10n.loginFlowSlogan, style: textTheme.bodyMedium!.copyWith(color: palette.muted)),
                      const SizedBox(height: 20),
                      FutureBuilder(
                        future: _sombrioAccount,
                        builder: (context, snapshot) {
                          final account = snapshot.data;
                          if (account == null || widget.onSombrioAccountPressed == null) {
                            return Padding(
                              // Room for the default button's ring.
                              padding: const EdgeInsets.all(4),
                              child: FilledButton(
                                onPressed: widget.onGetStartedPressed,
                                child: Text(l10n.loginFlowGetStarted),
                              ),
                            );
                          }
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                l10n.loginFlowHostAccount(SombrioHost.hostName, account.serverName),
                                style: textTheme.bodySmall!.copyWith(color: palette.muted),
                              ),
                              const SizedBox(height: 10),
                              Padding(
                                padding: const EdgeInsets.all(4),
                                child: FilledButton(
                                  onPressed: _signingIn ? null : () => _continueWith(account),
                                  child: _signingIn
                                      ? const SizedBox.square(
                                          dimension: 16,
                                          child: CircularProgressIndicator(strokeWidth: 2),
                                        )
                                      : Text(l10n.loginFlowContinueAs(account.userName)),
                                ),
                              ),
                              const SizedBox(height: 8),
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 4),
                                child: OutlinedButton(
                                  onPressed: _signingIn ? null : widget.onGetStartedPressed,
                                  child: Text(l10n.loginFlowUseAnotherServer),
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 40),
            SombraWordmark(width: 120, color: palette.ink),
          ],
        ),
      ),
    );
  }
}
