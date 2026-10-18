import 'dart:convert';

import 'package:finamp/models/jellyfin_models.dart';
import 'package:finamp/services/subsonic/subsonic_api.dart';
import 'package:finamp/services/subsonic/subsonic_jellyfin_api.dart';
import 'package:finamp/services/subsonic/subsonic_layout_playlist.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_subsonic_server.dart';

void main() {
  const credentials = SubsonicCredentials(username: "jane", authQuery: "t=token&s=salt");

  late List<Map<String, Object?>> playlists;
  late FakeSubsonicServer server;
  late SubsonicJellyfinApi api;

  setUp(() {
    playlists = [
      {"id": "p1", "name": "Mix", "owner": "jane", "comment": "Songs I like"},
    ];
    var nextId = 2;
    server = FakeSubsonicServer({
      "getPlaylists": (_) => {
        "playlists": {"playlist": playlists},
      },
      "createPlaylist": (parameters) {
        final playlist = <String, Object?>{"id": "p${nextId++}", "name": parameters["name"]!.single, "owner": "jane"};
        playlists.add(playlist);
        return {"playlist": playlist};
      },
      "updatePlaylist": (parameters) {
        final playlist = playlists.singleWhere((playlist) => playlist["id"] == parameters["playlistId"]!.single);
        playlist["comment"] = parameters["comment"]?.single ?? playlist["comment"];
        playlist["public"] = parameters["public"]?.single == "true";
        return {};
      },
    });
    api = SubsonicJellyfinApi(
      baseUrl: () => FakeSubsonicServer.baseUrl,
      credentials: () => credentials,
      api: SubsonicApi(httpClient: server.client),
    );
  });

  /// A layout about the size of a real one, whose values are base64 like real ones
  final layout = jsonEncode({
    "version": 1,
    "settings": {for (var i = 0; i < 50; i++) "setting$i": base64.encode(List.generate(i * 4, (j) => (i + j) % 7))},
  });

  test("there's no layout until one is saved", () async {
    expect(await api.loadLayout(), isNull);
  });

  test("saves the layout in a private playlist, and loads it back", () async {
    await api.saveLayout(layout);

    expect(await api.loadLayout(), layout);
    final playlist = playlists.singleWhere((playlist) => playlist["name"] == SubsonicLayoutPlaylist.name);
    expect(playlist["public"], isFalse);
    expect(playlist["comment"], startsWith("Keeps the layout of sombrAMP"));
  });

  test("saving again updates the same playlist", () async {
    await api.saveLayout(layout);
    await api.saveLayout("newer");

    expect(await api.loadLayout(), "newer");
    expect(playlists.where((playlist) => playlist["name"] == SubsonicLayoutPlaylist.name), hasLength(1));
    expect(server.requestsTo("createPlaylist"), hasLength(1));
  });

  test("keeps the requests short enough for proxies", () async {
    await api.saveLayout(layout);

    expect(server.requestsTo("updatePlaylist").single.toString().length, lessThan(4096));
  });

  test("ignores other users' playlists of the same name", () async {
    playlists.add({
      "id": "p9",
      "name": SubsonicLayoutPlaylist.name,
      "owner": "john",
      "comment": SubsonicLayoutPlaylist.commentFor("john's"),
    });

    expect(await api.loadLayout(), isNull);
    await api.saveLayout(layout);
    expect(await api.loadLayout(), layout);
    expect(playlists.firstWhere((playlist) => playlist["id"] == "p9")["comment"], contains("sombrAMP-layout:"));
  });

  test("leaves the layout out of the playlists", () async {
    await api.saveLayout(layout);

    final result = QueryResult_BaseItemDto.fromJson(
      await api.getItems(userId: "jane", includeItemTypes: "Playlist", recursive: true) as Map<String, dynamic>,
    );
    expect(result.items!.map((playlist) => playlist.name), ["Mix"]);
  });

  test("doesn't hide a playlist that only has the same name", () {
    expect(SubsonicLayoutPlaylist.keepsLayout({"name": SubsonicLayoutPlaylist.name, "comment": "My own"}), isFalse);
  });

  test("reads no layout from a damaged comment", () {
    expect(SubsonicLayoutPlaylist.layoutIn(null), isNull);
    expect(SubsonicLayoutPlaylist.layoutIn("Songs I like"), isNull);
    expect(SubsonicLayoutPlaylist.layoutIn("sombrAMP-layout:not base64!"), isNull);
    expect(SubsonicLayoutPlaylist.layoutIn("sombrAMP-layout:${base64Url.encode(utf8.encode("not gzip"))}"), isNull);
  });
}
