import 'package:flutter/services.dart';
import 'package:logging/logging.dart';

/// The Jellyfin account Sombrio's film and TV side is signed in to.
class SombrioAccount {
  const SombrioAccount({required this.baseUrl, required this.userName, required this.serverName});

  final String baseUrl;
  final String userName;
  final String serverName;
}

/// sombrAMP inside Sombrio, the Sombra app that also plays films and shows.
///
/// Sombrio builds sombrAMP as a Flutter module and opens it from its Music tab. The module is built with
/// `--dart-define=SOMBRIO=true`; the standalone app never talks to the host.
abstract final class SombrioHost {
  static const isEmbedded = bool.fromEnvironment("SOMBRIO");

  /// The product the music player is part of, as named to the user.
  static const hostName = "Sombrio";

  static const _channel = MethodChannel("wtf.sombra.sombrio/host");
  static final _logger = Logger("SombrioHost");

  /// The account Sombrio is signed in to, if it's signed in to a Jellyfin server.
  static Future<SombrioAccount?> account() async {
    if (!isEmbedded) return null;
    try {
      final account = await _channel.invokeMapMethod<String, Object?>("getAccount");
      final baseUrl = account?["baseUrl"] as String?;
      final userName = account?["userName"] as String?;
      if (baseUrl == null || userName == null) return null;
      return SombrioAccount(
        baseUrl: baseUrl,
        userName: userName,
        serverName: account?["serverName"] as String? ?? Uri.tryParse(baseUrl)?.host ?? baseUrl,
      );
    } on PlatformException catch (e) {
      _logger.warning("Couldn't get Sombrio's account", e);
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  /// Has Sombrio, which is signed in, authorize the Quick Connect request with [code], so sombrAMP gets its own
  /// session for the same account without asking for the password.
  static Future<void> authorizeQuickConnect(String code) async {
    await _channel.invokeMethod<void>("authorizeQuickConnect", {"code": code});
  }
}
