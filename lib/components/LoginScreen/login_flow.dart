import 'dart:async';

import 'package:finamp/components/LoginScreen/login_server_selection_page.dart';
import 'package:finamp/components/global_snackbar.dart';
import 'package:finamp/models/finamp_models.dart' show ServerType;
import 'package:finamp/models/jellyfin_models.dart';
import 'package:finamp/screens/view_selector.dart';
import 'package:finamp/services/client_certificate_installer.dart';
import 'package:finamp/services/jellyfin_api_helper.dart';
import 'package:finamp/services/server_client_discovery_service.dart';
import 'package:finamp/sombra/sombrio_host.dart';
import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'package:get_it/get_it.dart';
import 'package:logging/logging.dart';

import 'login_authentication_page.dart';
import 'login_splash_page.dart';
import 'login_user_selection_page.dart';

class LoginFlow extends StatefulWidget {
  const LoginFlow({super.key});

  @override
  State<LoginFlow> createState() => _LoginFlowState();
}

final loginNavigatorKey = GlobalKey<NavigatorState>();

final _loginFlowLogger = Logger("LoginFlow");

class _LoginFlowState extends State<LoginFlow> {
  ServerState serverState = ServerState(discoveredServers: {});
  ConnectionState connectionState = ConnectionState();

  @override
  void dispose() {
    serverState.clientDiscoveryHandler.dispose();
    serverState.connectionTestDebounceTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // handle going back inside the nested Navigator while not on the first page
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;

        if (context.mounted) {
          if (!loginNavigatorKey.currentState!.canPop()) {
            Navigator.of(context).pop();
          } else {
            loginNavigatorKey.currentState!.pop();
          }
        }
      },
      child: Navigator(
        key: loginNavigatorKey,
        initialRoute: LoginSplashPage.routeName,
        onGenerateRoute: (RouteSettings settings) {
          Route<void> route;

          Route<void> createRoute(Widget page) => PageRouteBuilder<void>(
            pageBuilder: (context, animation, secondaryAnimation) => page,
            transitionsBuilder: (context, animation, secondaryAnimation, child) {
              if (MediaQuery.disableAnimationsOf(context)) {
                return child;
              }
              final pushingNext = secondaryAnimation.status == AnimationStatus.forward;
              final poppingNext = secondaryAnimation.status == AnimationStatus.reverse;
              final pushingOrPoppingNext = pushingNext || poppingNext;
              late final Tween<Offset> offsetTween = pushingOrPoppingNext
                  ? Tween<Offset>(begin: const Offset(0.0, 0.0), end: const Offset(-1.0, 0.0))
                  : Tween<Offset>(begin: const Offset(1.0, 0.0), end: const Offset(0.0, 0.0));

              final curveOffsetTween = offsetTween.chain(CurveTween(curve: Curves.ease));

              late final Animation<Offset> slidingAnimation = pushingOrPoppingNext
                  ? curveOffsetTween.animate(secondaryAnimation)
                  : curveOffsetTween.animate(animation);
              return SlideTransition(position: slidingAnimation, child: child);
            },
          );

          switch (settings.name) {
            case LoginSplashPage.routeName:
              route = createRoute(
                LoginSplashPage(
                  onGetStartedPressed: () =>
                      loginNavigatorKey.currentState!.pushNamed(LoginServerSelectionPage.routeName),
                  onSombrioAccountPressed: SombrioHost.isEmbedded
                      ? (account) async {
                          try {
                            await GetIt.instance<JellyfinApiHelper>().authenticateWithSombrio(account);
                          } catch (e) {
                            _loginFlowLogger.warning("Couldn't sign in with Sombrio's account", e);
                            GlobalSnackbar.error(e);
                            return;
                          }
                          if (!context.mounted) return;
                          Navigator.of(context).pushReplacementNamed(ViewSelector.routeName);
                          _updateCapabilities();
                        }
                      : null,
                ),
              );
              break;
            case LoginServerSelectionPage.routeName:
              route = createRoute(
                LoginServerSelectionPage(
                  serverState: serverState,
                  onServerSelected: (PublicSystemInfoResult server, String baseUrl) {
                    serverState.selectedServer = server;
                    serverState.baseUrl = baseUrl;
                    serverState.clientDiscoveryHandler.stopDiscovery();
                    final jellyfinApiHelper = GetIt.instance<JellyfinApiHelper>();
                    final baseUri = Uri.parse(baseUrl);
                    if (jellyfinApiHelper.detectedServerType(baseUri.toString()) == ServerType.subsonic) {
                      // Subsonic servers don't list their users or support Quick Connect, so go straight to the login
                      jellyfinApiHelper.baseUrlTemp = baseUri;
                      connectionState.selectedUser = null;
                      loginNavigatorKey.currentState!.pushNamed(LoginAuthenticationPage.routeName);
                    } else {
                      loginNavigatorKey.currentState!.pushNamed(LoginUserSelectionPage.routeName);
                    }
                  },
                ),
              );
              break;
            case LoginUserSelectionPage.routeName:
              route = createRoute(
                LoginUserSelectionPage(
                  serverState: serverState,
                  connectionState: connectionState,
                  onUserSelected: (UserDto? user) {
                    connectionState.selectedUser = user;
                    loginNavigatorKey.currentState!.pushNamed(LoginAuthenticationPage.routeName);
                  },
                  onAuthenticated: () {
                    Navigator.of(context).pushReplacementNamed(ViewSelector.routeName);
                  },
                ),
              );
              break;
            case LoginAuthenticationPage.routeName:
              route = createRoute(
                LoginAuthenticationPage(
                  connectionState: connectionState,
                  onAuthenticated: () {
                    Navigator.of(context).popAndPushNamed(ViewSelector.routeName);
                    _updateCapabilities();
                  },
                ),
              );
              break;
            default:
              throw Exception('Invalid route: ${settings.name}');
          }
          // return MaterialPageRoute<void>(builder: builder, settings: settings);
          return route;
        },
      ),
    );
  }

  /// Tells the server what this client can do, once signed in.
  void _updateCapabilities() {
    GetIt.instance<JellyfinApiHelper>().updateCapabilities(
      ClientCapabilities(
        supportsMediaControl: true,
        supportsPersistentIdentifier: true,
        playableMediaTypes: ["Audio"],
        supportedCommands: [
          "MoveUp",
          "MoveDown",
          "MoveLeft",
          "MoveRight",
          "PageUp",
          "PageDown",
          "PreviousLetter",
          "NextLetter",
          "ToggleOsd",
          "ToggleContextMenu",
          "Select",
          "Back",
          "TakeScreenshot",
          "SendKey",
          "SendString",
          "GoHome",
          "GoToSettings",
          "VolumeUp",
          "VolumeDown",
          "Mute",
          "Unmute",
          "ToggleMute",
          "SetVolume",
          "SetAudioStreamIndex",
          "SetSubtitleStreamIndex",
          "ToggleFullscreen",
          "DisplayContent",
          "GoToSearch",
          "DisplayMessage",
          "SetRepeatMode",
          "ChannelUp",
          "ChannelDown",
          "Guide",
          "ToggleStats",
          "PlayMediaSource",
          "PlayTrailers",
          "SetShuffleQueue",
          "PlayState",
          "PlayNext",
          "ToggleOsdMenu",
          "Play",
          "SetMaxStreamingBitrate",
          "SetPlaybackOrder",
        ],
      ),
    );
  }
}

class ServerState {
  final jellyfinApiHelper = GetIt.instance<JellyfinApiHelper>();
  static final serverStateLogger = Logger("LoginServerState");

  PublicSystemInfoResult? manualServer;
  Map<Uri, PublicSystemInfoResult> discoveredServers;
  PublicSystemInfoResult? selectedServer;
  String? baseUrl;
  Timer? connectionTestDebounceTimer;
  String? baseUrlToTest;
  JellyfinServerClientDiscovery clientDiscoveryHandler;
  bool clientCertificateRequired = false;
  VoidCallback? updateCallback;

  ServerState({
    required this.discoveredServers,
    this.updateCallback,
    this.manualServer,
    this.selectedServer,
    this.baseUrl,
  }) : clientDiscoveryHandler = JellyfinServerClientDiscovery();

  void onBaseUrlChanged(String baseUrl) {
    if (connectionTestDebounceTimer?.isActive ?? false) {
      connectionTestDebounceTimer?.cancel();
    }
    connectionTestDebounceTimer = Timer(const Duration(milliseconds: 500), () async {
      updateCallback?.call();
      try {
        baseUrlToTest = baseUrl;
        updateCallback?.call();
        await testServerConnection(baseUrl);
        baseUrlToTest = null;
        updateCallback?.call();
      } catch (err) {
        // nop, make sure *not* to reset the baseUrlToTest
      }
    });
  }

  Future<void> testServerConnection(String baseUrl) async {
    if (baseUrl.isNotEmpty) {
      bool unspecifiedProtocol = false;
      bool unspecifiedPort = false;

      String baseUrlToTest = baseUrl;

      // We trim the base url in case the user accidentally added some trailing whitespace
      baseUrlToTest = baseUrlToTest.trim();

      if (!(baseUrlToTest.startsWith("http://") || baseUrlToTest.startsWith("https://"))) {
        // use https by default
        baseUrlToTest = "https://$baseUrlToTest";
        unspecifiedProtocol = true;
      }

      // use regex to check if a port is specified
      final portRegex = RegExp(r"[^\/]:\d+");
      if (!portRegex.hasMatch(baseUrlToTest)) {
        unspecifiedPort = true;
      }

      if (baseUrlToTest.endsWith("/")) {
        baseUrlToTest = baseUrlToTest.substring(0, baseUrlToTest.length - 1);
      }

      jellyfinApiHelper.baseUrlTemp = Uri.parse(baseUrlToTest);

      PublicSystemInfoResult? publicServerInfo;
      try {
        publicServerInfo = await jellyfinApiHelper.loadServerPublicInfo();
      } catch (error) {
        if (await ClientCertificateInstaller.isCertificateRequiredError(error, Uri.parse(baseUrlToTest))) {
          clientCertificateRequired = true;
          // Found server requiring mTLS certificate, no need to try other protocols/ports.
          return;
        } else {
          serverStateLogger.severe("Couldn't reach server at $baseUrlToTest (HTTPS): $error");
        }
      }
      if (this.baseUrlToTest != baseUrl) {
        throw Exception("Server URL changed while testing");
      }

      if (publicServerInfo == null && unspecifiedProtocol) {
        // try http
        Uri url = Uri.parse(baseUrlToTest).replace(scheme: "http");
        baseUrlToTest = url.toString(); // update the local url
        jellyfinApiHelper.baseUrlTemp = url;
        try {
          publicServerInfo = await jellyfinApiHelper.loadServerPublicInfo();
        } catch (error) {
          serverStateLogger.severe("Couldn't reach server at $baseUrlToTest (HTTP): $error");
        }
      }
      if (this.baseUrlToTest != baseUrl) {
        throw Exception("Server URL changed while testing");
      }

      if (publicServerInfo == null && unspecifiedPort) {
        // try default port 8096
        Uri url = Uri.parse(baseUrlToTest).replace(port: 8096);
        baseUrlToTest = url.toString(); // update the local url
        jellyfinApiHelper.baseUrlTemp = url;
        try {
          publicServerInfo = await jellyfinApiHelper.loadServerPublicInfo();
        } catch (error) {
          serverStateLogger.severe("Couldn't reach server at $baseUrlToTest (default port): $error");
        }
      }
      if (this.baseUrlToTest != baseUrl) {
        throw Exception("Server URL changed while testing");
      }

      if (publicServerInfo == null && unspecifiedPort) {
        // try Navidrome's default port 4533
        Uri url = Uri.parse(baseUrlToTest).replace(port: 4533);
        baseUrlToTest = url.toString(); // update the local url
        jellyfinApiHelper.baseUrlTemp = url;
        try {
          publicServerInfo = await jellyfinApiHelper.loadServerPublicInfo();
        } catch (error) {
          serverStateLogger.severe("Couldn't reach server at $baseUrlToTest (default Navidrome port): $error");
        }
      }
      if (this.baseUrlToTest != baseUrl) {
        throw Exception("Server URL changed while testing");
      }

      if (publicServerInfo != null) {
        manualServer = publicServerInfo;
        this.baseUrl = baseUrlToTest;
      }
    }
  }
}

class ConnectionState {
  bool isConnected;
  bool isAuthenticating;
  QuickConnectState? quickConnectState;
  UserDto? selectedUser;

  ConnectionState({this.isConnected = false, this.isAuthenticating = false, this.quickConnectState, this.selectedUser});
}
