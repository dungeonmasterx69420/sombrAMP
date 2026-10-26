import 'package:audio_service/audio_service.dart';
import 'package:flutter/services.dart';
import 'package:logging/logging.dart';

/// The Jellyfin account Sombrio's film and TV side is signed in to.
class SombrioAccount {
  const SombrioAccount({required this.baseUrl, required this.userName, required this.serverName});

  final String baseUrl;
  final String userName;
  final String serverName;
}

/// What Sombrio does for sombrAMP when sombrAMP runs inside it, as its Music tab.
abstract interface class SombrioHostDelegate {
  /// The account Sombrio is signed in to, if it's signed in to a Jellyfin server.
  Future<SombrioAccount?> account();

  /// Authorizes the Quick Connect request with [code] with Sombrio's session.
  Future<void> authorizeQuickConnect(String code);

  /// Plays sombrAMP's music through Sombrio's audio service, which there is one of for the whole app: the notification,
  /// the lock screen and Android Auto control whichever of the two players played last.
  Future<void> attachAudioHandler(AudioHandler handler);

  /// Goes back to Sombrio's films and shows. The music keeps playing.
  void leave();
}

/// sombrAMP inside Sombrio, the Sombra app that also plays films and shows.
///
/// Sombrio is a Flutter app too, and has sombrAMP as a package: it runs sombrAMP next to its own screens, in the same
/// engine, and switches between the two. It's built with `--dart-define=SOMBRIO=true`, and sets [delegate] before
/// starting sombrAMP. The standalone app never talks to the host.
abstract final class SombrioHost {
  static const isEmbedded = bool.fromEnvironment("SOMBRIO");

  /// The product the music player is part of, as named to the user.
  static const hostName = "Sombrio";

  /// Inside Sombrio, sombrAMP is the `finamp` package, whose assets and fonts the app has under its name.
  static const _packagePrefix = isEmbedded ? "packages/finamp/" : "";

  /// The name of the font [family] declared in pubspec.yaml.
  static const fontPrefix = _packagePrefix;

  /// The key of the asset at [path], as declared in pubspec.yaml.
  static String asset(String path) => "$_packagePrefix$path";

  /// The package of sombrAMP's assets, for widgets that take it separately.
  static const assetPackage = isEmbedded ? "finamp" : null;

  static SombrioHostDelegate? delegate;

  static final _logger = Logger("SombrioHost");

  /// The account Sombrio is signed in to, if it's signed in to a Jellyfin server.
  static Future<SombrioAccount?> account() async {
    if (!isEmbedded) return null;
    try {
      return await delegate?.account();
    } catch (e) {
      _logger.warning("Couldn't get Sombrio's account", e);
      return null;
    }
  }

  /// Has Sombrio, which is signed in, authorize the Quick Connect request with [code], so sombrAMP gets its own
  /// session for the same account without asking for the password.
  static Future<void> authorizeQuickConnect(String code) async {
    final delegate = SombrioHost.delegate;
    if (delegate == null) throw StateError("Not running inside Sombrio");
    await delegate.authorizeQuickConnect(code);
  }

  /// Leaves the music player: back to films and shows inside Sombrio, out of the app otherwise.
  static void leave() {
    final delegate = SombrioHost.delegate;
    if (delegate != null) {
      delegate.leave();
    } else {
      SystemNavigator.pop();
    }
  }
}
