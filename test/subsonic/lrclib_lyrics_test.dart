import 'dart:convert';

import 'package:finamp/services/subsonic/lrclib_lyrics.dart';
import 'package:finamp/services/subsonic/subsonic_mapper.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

Map<String, Object?> record({
  String trackName = "Get Lucky",
  num duration = 369,
  bool instrumental = false,
  String? plainLyrics = "Like the legend of the phoenix",
  String? syncedLyrics = "[00:43.21] Like the legend of the phoenix",
}) => {
  "id": 1,
  "trackName": trackName,
  "artistName": "Daft Punk",
  "albumName": "Random Access Memories",
  "duration": duration,
  "instrumental": instrumental,
  "plainLyrics": plainLyrics,
  "syncedLyrics": syncedLyrics,
};

int ticks(int milliseconds) => milliseconds * SubsonicMapper.ticksPerMillisecond;

void main() {
  group("parseSyncedLyrics", () {
    test("reads timestamps with hundredths, thousandths and no fraction", () {
      final lines = LrclibLyrics.parseSyncedLyrics("[00:01.50] First\n[01:02.345] Second\r\n[02:03] Third");
      expect(lines.map((line) => line.text), ["First", "Second", "Third"]);
      expect(lines.map((line) => line.start), [ticks(1500), ticks(62345), ticks(123000)]);
    });

    test("repeats lines with several timestamps, in order, and skips tags", () {
      final lines = LrclibLyrics.parseSyncedLyrics(
        "[ar: Daft Punk]\n[ti: Get Lucky]\n[00:10.00][00:30.00] Chorus\n[00:20.00] Verse\n[00:25.00]\nUntimed",
      );
      expect(lines.map((line) => line.text), ["Chorus", "Verse", "", "Chorus"]);
      expect(lines.map((line) => line.start), [ticks(10000), ticks(20000), ticks(25000), ticks(30000)]);
    });
  });

  group("lyricsFromRecord", () {
    test("prefers synced lyrics", () {
      final lyrics = LrclibLyrics.lyricsFromRecord(record())!;
      expect(lyrics.metadata?.isSynced, isTrue);
      expect(lyrics.metadata?.title, "Get Lucky");
      expect(lyrics.lyrics?.single.start, ticks(43210));
    });

    test("falls back to plain lyrics", () {
      final lyrics = LrclibLyrics.lyricsFromRecord(record(syncedLyrics: null, plainLyrics: "One\nTwo\n"))!;
      expect(lyrics.metadata?.isSynced, isFalse);
      expect(lyrics.lyrics?.map((line) => line.text), ["One", "Two"]);
      expect(lyrics.lyrics?.first.start, isNull);
    });

    test("has nothing for instrumentals and empty records", () {
      expect(LrclibLyrics.lyricsFromRecord(record(instrumental: true)), isNull);
      expect(LrclibLyrics.lyricsFromRecord(record(plainLyrics: null, syncedLyrics: " ")), isNull);
    });
  });

  group("find", () {
    test("uses the exact match", () async {
      final requests = <http.Request>[];
      final lrclib = LrclibLyrics(
        httpClient: MockClient((request) async {
          requests.add(request);
          return http.Response(jsonEncode(record()), 200);
        }),
      );
      final lyrics = await lrclib.find(
        title: "Get Lucky",
        artist: "Daft Punk feat. Pharrell Williams",
        album: "Random Access Memories",
        duration: const Duration(seconds: 369),
      );
      expect(lyrics?.lyrics?.single.text, "Like the legend of the phoenix");
      expect(requests.single.url.path, "/api/get");
      expect(requests.single.headers["User-Agent"], startsWith("sombrAMP"));
    });

    test("searches by the primary artist when there's no exact match", () async {
      final requests = <Uri>[];
      final lrclib = LrclibLyrics(
        httpClient: MockClient((request) async {
          requests.add(request.url);
          if (request.url.path == "/api/get") {
            return http.Response('{"code":404,"name":"TrackNotFound"}', 404);
          }
          return http.Response(
            jsonEncode([
              record(duration: 248, syncedLyrics: "[00:01.00] Radio edit"),
              record(syncedLyrics: null, plainLyrics: "Plain"),
              record(duration: 368.5, syncedLyrics: "[00:02.00] Album version"),
            ]),
            200,
          );
        }),
      );
      final lyrics = await lrclib.find(
        title: "Get Lucky",
        artist: "Daft Punk feat. Pharrell Williams",
        primaryArtist: "Daft Punk",
        duration: const Duration(seconds: 369),
      );
      expect(lyrics?.lyrics?.single.text, "Album version");
      expect(requests.last.path, "/api/search");
      expect(requests.last.queryParameters, {"track_name": "Get Lucky", "artist_name": "Daft Punk"});
    });

    test("finds nothing without a title or artist, or without results", () async {
      final lrclib = LrclibLyrics(
        httpClient: MockClient(
          (request) async =>
              request.url.path == "/api/get" ? http.Response('{"code":404}', 404) : http.Response("[]", 200),
        ),
      );
      expect(await lrclib.find(title: "", artist: "Daft Punk"), isNull);
      expect(await lrclib.find(title: "Unknown", artist: "Nobody"), isNull);
    });

    test("reports errors", () async {
      final lrclib = LrclibLyrics(httpClient: MockClient((_) async => http.Response("Bad gateway", 502)));
      await expectLater(lrclib.find(title: "Get Lucky", artist: "Daft Punk"), throwsA(isA<http.ClientException>()));
    });
  });
}
