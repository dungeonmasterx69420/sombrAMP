import 'dart:convert';
import 'dart:io';

import 'package:finamp/sombra/system_s_widgets.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as path_helper;
import 'package:path_provider/path_provider.dart';

/// A newer build of sombrAMP, published as a release on GitHub.
class AppUpdate {
  const AppUpdate({required this.buildNumber, required this.notes, required this.apkUrl, required this.apkSize});

  final int buildNumber;

  /// What changed, as written in the release.
  final String notes;

  final Uri apkUrl;
  final int? apkSize;
}

/// Updates the Android app from the releases the sombrAMP builds workflow publishes for each build of the main
/// branch.  Their tags are `build-<versionCode>`, and their APKs are all signed with the same key, so Android
/// installs them over the running app.
class AppUpdateService {
  AppUpdateService({http.Client? httpClient}) : _httpClient = httpClient ?? http.Client();

  static final isSupported = Platform.isAndroid;

  static final _logger = Logger("AppUpdateService");
  static const _channel = MethodChannel("com.unicornsonlsd.finamp/app_updates");
  static final latestReleaseUrl = Uri.https("api.github.com", "/repos/${Sombra.repository}/releases/latest");
  static final _releaseTag = RegExp(r"^build-(\d+)$");

  final http.Client _httpClient;

  /// The build number of the running app, which is its Android versionCode.
  static Future<int> currentBuildNumber() async => int.tryParse((await PackageInfo.fromPlatform()).buildNumber) ?? 0;

  /// Returns the latest release, if it's newer than the running app.
  Future<AppUpdate?> findUpdate() async {
    final response = await _httpClient.get(latestReleaseUrl, headers: {"Accept": "application/vnd.github+json"});
    if (response.statusCode == 404) {
      // Nothing has been released yet
      return null;
    }
    if (response.statusCode != 200) {
      throw http.ClientException("GitHub answered with status ${response.statusCode}", latestReleaseUrl);
    }
    final update = updateFromRelease(jsonDecode(response.body) as Map<String, dynamic>, await currentBuildNumber());
    _logger.info(update == null ? "sombrAMP is up to date" : "Build ${update.buildNumber} is available");
    return update;
  }

  /// Reads a release from GitHub's API, returning it if it's newer than [currentBuildNumber] and has an APK.
  static AppUpdate? updateFromRelease(Map<String, dynamic> release, int currentBuildNumber) {
    final buildNumber = int.tryParse(_releaseTag.firstMatch(release["tag_name"] as String? ?? "")?.group(1) ?? "");
    if (buildNumber == null || buildNumber <= currentBuildNumber) {
      return null;
    }
    final assets = (release["assets"] as List<dynamic>? ?? []).cast<Map<String, dynamic>>();
    final apk = assets.where((asset) => (asset["name"] as String? ?? "").endsWith(".apk")).firstOrNull;
    final apkUrl = Uri.tryParse(apk?["browser_download_url"] as String? ?? "");
    if (apkUrl == null || !apkUrl.hasScheme) {
      return null;
    }
    return AppUpdate(
      buildNumber: buildNumber,
      notes: (release["body"] as String? ?? "").trim(),
      apkUrl: apkUrl,
      apkSize: apk!["size"] as int?,
    );
  }

  /// Downloads [update] and opens Android's installer for it.  [onProgress] receives the downloaded fraction, or
  /// null while it isn't known.
  Future<void> install(AppUpdate update, {void Function(double? progress)? onProgress}) async {
    // Android's installer reads it through the app's file provider, which shares the updates folder of the cache.
    final directory = Directory(path_helper.join((await getTemporaryDirectory()).path, "updates"));
    await directory.create(recursive: true);
    final file = File(path_helper.join(directory.path, "sombrAMP.apk"));

    _logger.info("Downloading build ${update.buildNumber} from ${update.apkUrl}");
    final response = await _httpClient.send(http.Request("GET", update.apkUrl));
    if (response.statusCode != 200) {
      throw http.ClientException("GitHub answered with status ${response.statusCode}", update.apkUrl);
    }
    final total = response.contentLength ?? update.apkSize;
    var received = 0;
    final sink = file.openWrite();
    try {
      await for (final chunk in response.stream) {
        sink.add(chunk);
        received += chunk.length;
        onProgress?.call(total == null || total == 0 ? null : received / total);
      }
    } finally {
      await sink.close();
    }

    await _channel.invokeMethod<void>("installApk", {"path": file.path});
  }
}
