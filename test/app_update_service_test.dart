import 'dart:convert';

import 'package:finamp/services/app_update_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:package_info_plus/package_info_plus.dart';

Map<String, dynamic> release(String tag, {List<String> assets = const ["sombrAMP-build-1010-android.apk"]}) => {
  "tag_name": tag,
  "body": "Draw the names under album covers in the phosphor",
  "assets": [
    for (final name in assets)
      {"name": name, "size": 1234, "browser_download_url": "https://github.com/o/r/releases/download/$tag/$name"},
  ],
};

void main() {
  group("updateFromRelease", () {
    test("offers newer builds", () {
      final update = AppUpdateService.updateFromRelease(release("build-1010"), 1005);
      expect(update?.buildNumber, 1010);
      expect(update?.notes, "Draw the names under album covers in the phosphor");
      expect(
        update?.apkUrl.toString(),
        "https://github.com/o/r/releases/download/build-1010/sombrAMP-build-1010-android.apk",
      );
      expect(update?.apkSize, 1234);
    });

    test("picks the APK among the other platforms' files", () {
      final update = AppUpdateService.updateFromRelease(
        release(
          "build-1010",
          assets: [
            "sombrAMP-build-1010-ios.ipa",
            "sombrAMP-build-1010-windows.zip",
            "sombrAMP-build-1010-android.apk",
            "sombrAMP-build-1010-windows.msix",
          ],
        ),
        1005,
      );
      expect(
        update?.apkUrl.toString(),
        "https://github.com/o/r/releases/download/build-1010/sombrAMP-build-1010-android.apk",
      );
    });

    test("ignores the running build and older ones", () {
      expect(AppUpdateService.updateFromRelease(release("build-1010"), 1010), isNull);
      expect(AppUpdateService.updateFromRelease(release("build-1003"), 1010), isNull);
    });

    test("ignores other releases and releases without an APK", () {
      expect(AppUpdateService.updateFromRelease(release("1.0.1"), 0), isNull);
      expect(AppUpdateService.updateFromRelease(release("build-1010", assets: ["sombrAMP.zip"]), 0), isNull);
    });
  });

  group("findUpdate", () {
    setUp(() {
      PackageInfo.setMockInitialValues(
        appName: "sombrAMP",
        packageName: "com.unicornsonlsd.finamp",
        version: "1.0.1",
        buildNumber: "1005",
        buildSignature: "",
      );
    });

    test("compares the latest release with the running build", () async {
      final client = MockClient((request) async {
        expect(request.url, AppUpdateService.latestReleaseUrl);
        return http.Response(jsonEncode(release("build-1010")), 200);
      });
      expect((await AppUpdateService(httpClient: client).findUpdate())?.buildNumber, 1010);
    });

    test("finds nothing before the first release", () async {
      final client = MockClient((_) async => http.Response('{"message":"Not Found"}', 404));
      expect(await AppUpdateService(httpClient: client).findUpdate(), isNull);
    });

    test("reports other errors", () async {
      final client = MockClient((_) async => http.Response('{"message":"API rate limit exceeded"}', 403));
      expect(AppUpdateService(httpClient: client).findUpdate(), throwsA(isA<http.ClientException>()));
    });
  });
}
