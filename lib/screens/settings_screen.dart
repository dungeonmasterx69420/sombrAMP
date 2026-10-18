import 'package:finamp/components/SettingsScreen/logout_list_tile.dart';
import 'package:finamp/components/app_update.dart';
import 'package:finamp/components/finamp_app_bar_back_button.dart';
import 'package:finamp/components/finamp_icon.dart';
import 'package:finamp/l10n/app_localizations.dart';
import 'package:finamp/menus/client_certificate_authentication_menu.dart';
import 'package:finamp/menus/quick_connect_authorization_menu.dart';
import 'package:finamp/menus/server_sharing_menu.dart';
import 'package:finamp/screens/accessibility_settings_screen.dart';
import 'package:finamp/screens/audio_service_settings_screen.dart';
import 'package:finamp/screens/downloads_settings_screen.dart';
import 'package:finamp/screens/home_screen_settings_screen.dart';
import 'package:finamp/screens/interaction_settings_screen.dart';
import 'package:finamp/screens/language_selection_screen.dart';
import 'package:finamp/screens/layout_settings_screen.dart';
import 'package:finamp/screens/network_settings_screen.dart';
import 'package:finamp/screens/playback_reporting_settings_screen.dart';
import 'package:finamp/screens/quick_settings_screen.dart';
import 'package:finamp/screens/transcoding_settings_screen.dart';
import 'package:finamp/screens/view_selector.dart';
import 'package:finamp/screens/volume_normalization_settings_screen.dart';
import 'package:finamp/services/app_update_service.dart';
import 'package:finamp/services/client_certificate_installer.dart';
import 'package:finamp/services/finamp_settings_helper.dart';
import 'package:finamp/services/finamp_user_helper.dart';
import 'package:finamp/sombra/system_s.dart';
import 'package:finamp/sombra/system_s_widgets.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';
import 'package:locale_names/locale_names.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  static const routeName = "/settings";

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(AppLocalizations.of(context)!.settings),
        leading: FinampAppBarBackButton(),
        actions: [
          FinampSettingsHelper.makeSettingsResetButtonWithDialog(
            context,
            FinampSettingsHelper.resetAllSettings,
            isGlobal: true,
          ),
          Semantics.fromProperties(
            properties: SemanticsProperties(label: AppLocalizations.of(context)!.about, button: true),
            excludeSemantics: true,
            container: true,
            child: IconButton(
              icon: const Icon(Icons.info),
              onPressed: () async {
                final localizations = AppLocalizations.of(context)!;
                final applicationLegalese = AppLocalizations.of(context)!.applicationLegalese(Sombra.sourceCode);
                PackageInfo packageInfo = await PackageInfo.fromPlatform();

                if (!context.mounted) return;

                final palette = SystemSTheme.of(context).palette;
                // System S links: ink, underlined.
                final linkStyle = TextStyle(color: palette.ink, decoration: TextDecoration.underline);
                TextSpan link(String url) => TextSpan(
                  text: url,
                  style: linkStyle,
                  recognizer: TapGestureRecognizer()..onTap = () async => await launchUrl(Uri.parse(url)),
                );

                showAboutDialog(
                  context: context,
                  applicationName: Sombra.productName,
                  applicationVersion: packageInfo.version,
                  applicationIcon: Padding(padding: const EdgeInsets.only(top: 8.0), child: FinampIcon(56, 56)),
                  applicationLegalese: applicationLegalese,
                  children: [
                    const SizedBox(height: 20),
                    RichText(
                      textAlign: TextAlign.center,
                      text: TextSpan(
                        style: TextTheme.of(context).bodyMedium!.copyWith(color: palette.ink),
                        children: [
                          TextSpan(
                            text: localizations.finampTagline,
                            style: const TextStyle(fontWeight: FontWeight.w500),
                          ),
                          const TextSpan(text: '\n\n'),
                          TextSpan(text: '${localizations.aboutBuiltOnFinamp}\n'),
                          link(Sombra.finampSourceCode),
                          const TextSpan(text: '\n\n'),
                          TextSpan(text: localizations.aboutContributionPrompt),
                          const TextSpan(text: '\n\n'),
                          TextSpan(text: '${localizations.aboutContributionLink}\n'),
                          link(Sombra.sourceCode),
                          const TextSpan(text: '\n\n\n'),
                          TextSpan(
                            text: localizations.aboutThanks,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    Center(
                      child: Semantics(
                        link: true,
                        child: GestureDetector(
                          onTap: () async => await launchUrl(Uri.parse(Sombra.website)),
                          child: SombraWordmark(width: 120, color: palette.ink),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 200.0),
        children: [
          ListTile(
            leading: const Icon(TablerIcons.sparkles),
            title: Text(AppLocalizations.of(context)!.quickSettingsScreen),
            onTap: () => Navigator.of(
              context,
            ).pushNamed(QuickSettingsScreen.routeName, arguments: QuickSettingsScreen.fromSettingsScreen),
          ),
          ListTile(
            leading: const Icon(TablerIcons.home),
            title: Text(AppLocalizations.of(context)!.homeScreenSettingsTitle),
            onTap: () => Navigator.of(context).pushNamed(HomeScreenSettingsScreen.routeName),
          ),
          ListTile(
            leading: const Icon(Icons.compress),
            title: Text(AppLocalizations.of(context)!.transcoding),
            onTap: () => Navigator.of(context).pushNamed(TranscodingSettingsScreen.routeName),
          ),
          ListTile(
            leading: const Icon(Icons.download),
            title: Text(AppLocalizations.of(context)!.downloadSettings),
            onTap: () => Navigator.of(context).pushNamed(DownloadsSettingsScreen.routeName),
          ),
          ListTile(
            leading: const Icon(Icons.wifi),
            title: Text(AppLocalizations.of(context)!.networkSettingsTitle),
            onTap: () => Navigator.of(context).pushNamed(NetworkSettingsScreen.routeName),
          ),
          ListTile(
            leading: const Icon(Icons.music_note),
            title: Text(AppLocalizations.of(context)!.audioService),
            onTap: () => Navigator.of(context).pushNamed(AudioServiceSettingsScreen.routeName),
          ),
          ListTile(
            leading: const Icon(TablerIcons.cast),
            title: Text(AppLocalizations.of(context)!.playbackReportingSettingsTitle),
            onTap: () => Navigator.of(context).pushNamed(PlaybackReportingSettingsScreen.routeName),
          ),
          ListTile(
            leading: const Icon(Icons.equalizer_rounded),
            title: Text(AppLocalizations.of(context)!.volumeNormalizationSettingsTitle),
            onTap: () => Navigator.of(context).pushNamed(VolumeNormalizationSettingsScreen.routeName),
          ),
          ListTile(
            leading: const Icon(Icons.gesture),
            title: Text(AppLocalizations.of(context)!.interactions),
            onTap: () => Navigator.of(context).pushNamed(InteractionSettingsScreen.routeName),
          ),
          ListTile(
            leading: const Icon(Icons.widgets),
            title: Text(AppLocalizations.of(context)!.layoutAndTheme),
            onTap: () => Navigator.of(context).pushNamed(LayoutSettingsScreen.routeName),
          ),
          ListTile(
            leading: const Icon(TablerIcons.accessible),
            title: Text(AppLocalizations.of(context)!.accessibility),
            onTap: () => Navigator.of(context).pushNamed(AccessibilitySettingsScreen.routeName),
          ),
          ListTile(
            leading: const Icon(Icons.library_music),
            title: Text(AppLocalizations.of(context)!.selectMusicLibraries),
            subtitle: ref.watch(finampSettingsProvider.isOffline)
                ? Text(AppLocalizations.of(context)!.notAvailableInOfflineMode)
                : null,
            enabled: !ref.watch(finampSettingsProvider.isOffline),
            onTap: () => Navigator.of(context).pushNamed(ViewSelector.routeName),
          ),
          ListTile(
            leading: const Icon(Icons.language),
            title: Text(AppLocalizations.of(context)!.language),
            subtitle: Text(
              ref.watch(finampSettingsProvider.locale)?.nativeDisplayLanguage ?? AppLocalizations.of(context)!.system,
            ),
            onTap: () => Navigator.of(context).pushNamed(LanguageSelectionScreen.routeName),
          ),
          if (AppUpdateService.isSupported)
            ListTile(
              leading: const Icon(TablerIcons.download),
              title: Text(AppLocalizations.of(context)!.appUpdates),
              subtitle: FutureBuilder(
                future: PackageInfo.fromPlatform(),
                builder: (context, snapshot) => Text(
                  snapshot.data == null
                      ? ""
                      : AppLocalizations.of(
                          context,
                        )!.appUpdatesSubtitle(snapshot.data!.version, snapshot.data!.buildNumber),
                ),
              ),
              onTap: () => checkForAppUpdate(),
            ),
          Divider(),
          ListTile(
            leading: Icon(TablerIcons.access_point),
            title: Text(AppLocalizations.of(context)!.serverSharingMenuButtonTitle),
            onTap: () => showServerSharingPanel(context: context),
          ),
          // Quick Connect is a Jellyfin feature
          if (!(ref.watch(FinampUserHelper.finampCurrentUserProvider)?.isSubsonic ?? false))
            ListTile(
              leading: Icon(TablerIcons.lock_bolt),
              title: Text(AppLocalizations.of(context)!.quickConnectAuthorizationMenuButtonTitle),
              onTap: () => showQuickConnectAuthorizationMenu(context: context),
            ),
          ListTile(
            leading: Icon(TablerIcons.certificate),
            title: Text(AppLocalizations.of(context)!.clientCertificate),
            subtitle: Text(
              !ClientCertificateInstaller.isSupported
                  ? AppLocalizations.of(context)!.clientCertificatesUnsupported
                  : ref.watch(finampSettingsProvider.clientCertificate) != null
                  ? AppLocalizations.of(context)!.clientCertificateInstalled
                  : AppLocalizations.of(context)!.clientCertificateUnavailable,
            ),
            enabled: ClientCertificateInstaller.isSupported,
            onTap: () => showClientCertificateMenu(context: context),
          ),
          const LogoutListTile(),
        ],
      ),
    );
  }
}
