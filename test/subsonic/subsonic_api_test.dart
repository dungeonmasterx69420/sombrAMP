import 'package:finamp/services/subsonic/subsonic_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'fake_subsonic_server.dart';

void main() {
  group("SubsonicCredentials", () {
    test("token authentication uses md5(password + salt)", () {
      // Example from the Subsonic API documentation
      final credentials = SubsonicCredentials.token(username: "admin", password: "sesame", salt: "c19b2d");
      expect(credentials.authQuery, "t=26719a1196d2a940705a59634eb18eab&s=c19b2d");
    });

    test("token authentication generates a random salt", () {
      final first = SubsonicCredentials.token(username: "admin", password: "sesame");
      final second = SubsonicCredentials.token(username: "admin", password: "sesame");
      expect(first.authQuery, isNot(second.authQuery));
    });

    test("password authentication hex encodes the password", () {
      final credentials = SubsonicCredentials.password(username: "admin", password: "sesame");
      expect(credentials.authQuery, "p=enc:736573616d65");
    });
  });

  group("buildUri", () {
    final server = SubsonicServer(
      baseUrl: Uri.parse("https://example.com/music/"),
      credentials: const SubsonicCredentials(username: "jane doe", authQuery: "t=abc&s=def"),
    );

    test("keeps the base path and adds credentials", () {
      final uri = SubsonicApi.buildUri(server, "getAlbum", {"id": "al-1"});
      expect(uri.path, "/music/rest/getAlbum.view");
      expect(uri.queryParameters, {
        "u": "jane doe",
        "t": "abc",
        "s": "def",
        "v": SubsonicApi.apiVersion,
        "c": SubsonicApi.clientName,
        "f": "json",
        "id": "al-1",
      });
    });

    test("skips null parameters and repeats lists", () {
      final uri = SubsonicApi.buildUri(server, "updatePlaylist", {
        "playlistId": "1",
        "name": null,
        "songIdToAdd": ["a", "b&c"],
      });
      expect(uri.queryParametersAll["songIdToAdd"], ["a", "b&c"]);
      expect(uri.queryParametersAll.containsKey("name"), isFalse);
    });

    test("streams are transcoded with a format and bit rate", () {
      final uri = SubsonicApi.streamUri(server, "1", format: "opus", maxBitRate: 128);
      expect(uri.queryParameters, containsPair("format", "opus"));
      expect(uri.queryParameters, containsPair("maxBitRate", "128"));
      // Estimated lengths don't match the transcoded stream, which breaks players and downloads
      expect(uri.queryParameters, isNot(contains("estimateContentLength")));
    });
  });

  group("parseResponse", () {
    test("unwraps successful responses", () {
      final response = http.Response(
        '{"subsonic-response":{"status":"ok","version":"1.16.1","album":{"id":"1"}}}',
        200,
      );
      expect(SubsonicApi.parseResponse(response)["album"], {"id": "1"});
    });

    test("throws server errors", () {
      final response = http.Response(
        '{"subsonic-response":{"status":"failed","version":"1.16.1","error":{"code":40,"message":"Wrong username or password"}}}',
        200,
      );
      expect(
        () => SubsonicApi.parseResponse(response),
        throwsA(isA<SubsonicException>().having((e) => e.code, "code", SubsonicException.wrongCredentials)),
      );
    });

    test("rejects responses from other servers", () {
      expect(
        () => SubsonicApi.parseResponse(http.Response("<html></html>", 404)),
        throwsA(isA<http.ClientException>()),
      );
    });
  });

  test("network errors don't contain credentials", () async {
    final api = SubsonicApi(
      httpClient: MockClient((request) async => throw http.ClientException("Connection refused", request.url)),
    );
    final server = SubsonicServer(
      baseUrl: FakeSubsonicServer.baseUrl,
      credentials: SubsonicCredentials.password(username: "admin", password: "secret"),
    );
    await expectLater(
      api.ping(server),
      throwsA(
        isA<http.ClientException>()
            .having((e) => e.uri.toString(), "uri", isNot(contains("enc:")))
            .having((e) => e.uri?.path, "path", "/navidrome/rest/ping.view"),
      ),
    );
  });

  test("probe detects Subsonic servers without credentials", () async {
    final fake = FakeSubsonicServer({
      "ping": (_) => throw const SubsonicException(SubsonicException.missingParameter, "Missing parameter: 'u'"),
    });
    final info = await SubsonicApi(httpClient: fake.client).probe(FakeSubsonicServer.baseUrl);
    expect(info?.displayName, "Navidrome");
    expect(info?.openSubsonic, isTrue);
    expect(fake.requests.single.queryParameters.containsKey("u"), isFalse);
  });

  test("probe rejects other servers", () async {
    final api = SubsonicApi(httpClient: MockClient((_) async => http.Response("Not found", 404)));
    expect(await api.probe(FakeSubsonicServer.baseUrl), isNull);
  });

  test("lists with a single element may be objects", () {
    expect(SubsonicApi.asList({"id": "1"}), [
      {"id": "1"},
    ]);
    expect(SubsonicApi.asList(null), isEmpty);
  });
}
