import 'package:finamp/models/jellyfin_models.dart';
import 'package:finamp/services/subsonic/subsonic_api.dart';
import 'package:finamp/services/subsonic/subsonic_ids.dart';
import 'package:finamp/services/subsonic/subsonic_jellyfin_api.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_subsonic_server.dart';

/// A small library: two albums by one artist, and one album by another artist featuring the first.
final _songs = {
  "s1": song("s1", title: "Alpha", track: 1, playCount: 5, created: "2024-01-01T00:00:00Z"),
  "s2": song("s2", title: "Bravo", track: 2, starred: "2024-02-01T00:00:00Z"),
  "s3": song("s3", title: "Charlie", albumId: "al2", album: "Second Album", track: 1, playCount: 1),
  "s4": song("s4", title: "Delta", albumId: "al2", album: "Second Album", track: 2, genre: "Jazz"),
  "s5": {
    ...song("s5", title: "Echo", albumId: "al3", album: "Guest Album", artistId: "ar2", artist: "Other Artist"),
    "artists": [
      {"id": "ar2", "name": "Other Artist"},
      {"id": "ar1", "name": "The Artist"},
    ],
  },
};

final _albums = {
  "al1": album("al1", name: "First Album", year: 2010, created: "2024-03-01T00:00:00Z"),
  "al2": album("al2", name: "Second Album", year: 2015, starred: "2024-01-01T00:00:00Z"),
  "al3": album("al3", name: "Guest Album", artistId: "ar2", artist: "Other Artist", year: 2005, songCount: 1),
};

List<Map<String, Object?>> _songsOf(String albumId) =>
    _songs.values.where((song) => song["albumId"] == albumId).toList();

Map<String, SubsonicHandler> _libraryHandlers() => {
  "ping": (_) => {},
  "getOpenSubsonicExtensions": (_) => {
    "openSubsonicExtensions": [
      {
        "name": "songLyrics",
        "versions": [1],
      },
    ],
  },
  "getMusicFolders": (_) => {
    "musicFolders": {
      "musicFolder": [
        {"id": 1, "name": "Music"},
      ],
    },
  },
  "getAlbumList2": (parameters) {
    final offset = int.parse(parameters["offset"]?.first ?? "0");
    final albums = parameters["type"]?.first == "byGenre"
        ? _albums.values.where((album) => album["genre"] == parameters["genre"]?.first)
        : _albums.values;
    return {
      "albumList2": {"album": albums.skip(offset).toList()},
    };
  },
  "getAlbum": (parameters) {
    final album = _albums[parameters["id"]!.first];
    if (album == null) throw const SubsonicException(SubsonicException.notFound, "Album not found");
    return {
      "album": {...album, "song": _songsOf(album["id"] as String)},
    };
  },
  "getSong": (parameters) {
    final song = _songs[parameters["id"]!.first];
    if (song == null) throw const SubsonicException(SubsonicException.notFound, "Song not found");
    return {"song": song};
  },
  "getArtist": (parameters) {
    final id = parameters["id"]!.first;
    return {
      "artist": {
        "id": id,
        "name": id == "ar1" ? "The Artist" : "Other Artist",
        "album": _albums.values.where((album) => album["artistId"] == id).toList(),
      },
    };
  },
  "getArtistInfo2": (_) => {"artistInfo2": <String, Object?>{}},
  "getArtists": (_) => {
    "artists": {
      "index": [
        {
          "name": "O",
          "artist": [
            {"id": "ar2", "name": "Other Artist", "albumCount": 1},
          ],
        },
        {
          "name": "T",
          "artist": [
            {"id": "ar1", "name": "The Artist", "albumCount": 2},
          ],
        },
      ],
    },
  },
  "search3": (parameters) {
    final query = parameters["query"]!.first.toLowerCase();
    final offset = int.parse(parameters["songOffset"]?.first ?? "0");
    bool matches(Map<String, Object?> item) =>
        query.isEmpty ||
        [
          ...item.values.whereType<String>(),
          for (final artist in (item["artists"] as List<Map<String, Object?>>?) ?? []) artist["name"] as String,
        ].any((value) => value.toLowerCase().contains(query));
    return {
      "searchResult3": {
        "song": _songs.values.where(matches).skip(offset).toList(),
        if (parameters["albumCount"]?.first != "0") "album": _albums.values.where(matches).toList(),
      },
    };
  },
  "getStarred2": (_) => {
    "starred2": {
      "song": _songs.values.where((song) => song["starred"] != null).toList(),
      "album": _albums.values.where((album) => album["starred"] != null).toList(),
    },
  },
  "getGenres": (_) => {
    "genres": {
      "genre": [
        {"value": "Rock", "songCount": 4, "albumCount": 3},
        {"value": "Jazz", "songCount": 1, "albumCount": 1},
      ],
    },
  },
  "getRandomSongs": (parameters) => {
    "randomSongs": {
      "song": _songs.values
          .where((song) => parameters["genre"] == null || song["genre"] == parameters["genre"]!.first)
          .toList(),
    },
  },
  "getSimilarSongs": (_) => throw const SubsonicException(SubsonicException.genericError, "No agents configured"),
  "getLyricsBySongId": (parameters) => {
    "lyricsList": {
      "structuredLyrics": parameters["id"]!.first == "s1"
          ? [
              {
                "synced": true,
                "line": [
                  {"start": 0, "value": "La la la"},
                ],
              },
            ]
          : <Map<String, Object?>>[],
    },
  },
  "scrobble": (_) => {},
  "star": (_) => {},
};

void main() {
  late FakeSubsonicServer server;
  late SubsonicJellyfinApi api;
  final credentials = SubsonicCredentials.token(username: "jane", password: "secret");

  SubsonicJellyfinApi createApi({SubsonicCredentials? withCredentials}) => SubsonicJellyfinApi(
    baseUrl: () => FakeSubsonicServer.baseUrl,
    credentials: () => withCredentials ?? credentials,
    api: SubsonicApi(httpClient: server.client),
  );

  setUp(() {
    server = FakeSubsonicServer(_libraryHandlers());
    api = createApi();
  });

  Future<QueryResult_BaseItemDto> getItems({
    String? includeItemTypes,
    BaseItemId? parentId,
    String? albumArtistIds,
    String? artistIds,
    String? albumIds,
    String? genreIds,
    String? ids,
    String? sortBy,
    String? sortOrder,
    String? searchTerm,
    String? filters,
    int? startIndex,
    int? limit,
    String? nameStartsWith,
    String? nameLessThan,
  }) async {
    final response = await api.getItems(
      userId: "jane",
      includeItemTypes: includeItemTypes,
      parentId: parentId,
      albumArtistIds: albumArtistIds,
      artistIds: artistIds,
      albumIds: albumIds,
      genreIds: genreIds,
      ids: ids,
      sortBy: sortBy,
      sortOrder: sortOrder,
      searchTerm: searchTerm,
      filters: filters,
      startIndex: startIndex,
      limit: limit,
      nameStartsWith: nameStartsWith,
      nameLessThan: nameLessThan,
    );
    return QueryResult_BaseItemDto.fromJson(response as Map<String, dynamic>);
  }

  List<String?> names(QueryResult_BaseItemDto result) => result.items!.map((item) => item.name).toList();

  group("login", () {
    test("public server info identifies the server", () async {
      final info = PublicSystemInfoResult.fromJson(await api.getPublicServerInfo() as Map<String, dynamic>);
      expect(info.serverName, "Navidrome");
      expect(info.version, "0.58.0");
      expect(info.id, SubsonicJellyfinApi.serverIdFor(FakeSubsonicServer.baseUrl));
    });

    test("prefers token authentication", () async {
      final result = AuthenticationResult.fromJson(
        await api.authenticateViaName({"Username": "jane", "Pw": "secret"}) as Map<String, dynamic>,
      );
      expect(result.user?.id, "jane");
      expect(result.accessToken, startsWith("t="));
      expect(server.requestsTo("ping").single.queryParameters, containsPair("u", "jane"));
    });

    test("falls back to password authentication", () async {
      server.handlers["ping"] = (parameters) {
        if (parameters.containsKey("t")) {
          throw const SubsonicException(SubsonicException.tokenAuthNotSupported, "Token auth not supported for LDAP");
        }
        return {};
      };
      final result = AuthenticationResult.fromJson(
        await api.authenticateViaName({"Username": "jane", "Pw": "secret"}) as Map<String, dynamic>,
      );
      expect(result.accessToken, "p=enc:736563726574");
    });

    test("reports wrong passwords", () async {
      server.handlers["ping"] = (_) =>
          throw const SubsonicException(SubsonicException.wrongCredentials, "Wrong username or password");
      await expectLater(
        api.authenticateViaName({"Username": "jane", "Pw": "wrong"}),
        throwsA(isA<SubsonicException>()),
      );
    });

    test("there are no public users or Quick Connect", () async {
      expect(await api.getPublicUsers(), isEmpty);
      expect(await api.getQuickConnectState(), isFalse);
    });
  });

  test("music folders are libraries", () async {
    final views = QueryResult_BaseItemDto.fromJson(await api.getViews("jane") as Map<String, dynamic>);
    expect(views.items?.single.id.raw, "library-1");
    expect(views.items?.single.collectionType, "music");
  });

  group("getItems", () {
    test("lists albums sorted and paged", () async {
      final firstPage = await getItems(includeItemTypes: "MusicAlbum", sortBy: "SortName", limit: 2);
      expect(names(firstPage), ["First Album", "Guest Album"]);
      expect(firstPage.totalRecordCount, 3);
      final secondPage = await getItems(includeItemTypes: "MusicAlbum", sortBy: "SortName", startIndex: 2, limit: 2);
      expect(names(secondPage), ["Second Album"]);
    });

    test("sorts albums by year, descending", () async {
      final result = await getItems(
        includeItemTypes: "MusicAlbum",
        sortBy: "ProductionYear,PremiereDate,SortName",
        sortOrder: "Descending",
      );
      expect(names(result), ["Second Album", "First Album", "Guest Album"]);
    });

    test("filters albums by first letter", () async {
      expect(names(await getItems(includeItemTypes: "MusicAlbum", nameStartsWith: "S")), ["Second Album"]);
      expect(names(await getItems(includeItemTypes: "MusicAlbum", nameLessThan: "A")), isEmpty);
    });

    test("lists all tracks with an empty search", () async {
      final result = await getItems(includeItemTypes: "Audio", sortBy: "PlayCount,SortName", sortOrder: "Descending");
      expect(names(result).first, "Alpha");
      expect(result.totalRecordCount, 5);
    });

    test("filters favorites", () async {
      expect(names(await getItems(includeItemTypes: "Audio", filters: "IsFavorite")), ["Bravo"]);
      expect(names(await getItems(includeItemTypes: "MusicAlbum", filters: "IsFavorite")), ["Second Album"]);
    });

    test("lists the tracks of an album in order", () async {
      final result = await getItems(
        parentId: SubsonicIds.album("al1"),
        includeItemTypes: "Audio",
        sortBy: "ParentIndexNumber,IndexNumber,SortName",
      );
      expect(names(result), ["Alpha", "Bravo"]);
    });

    test("lists albums of an album artist", () async {
      final result = await getItems(albumArtistIds: SubsonicIds.artist("ar1").raw, includeItemTypes: "MusicAlbum");
      expect(names(result), unorderedEquals(["First Album", "Second Album"]));
    });

    test("includes tracks the artist only performs on", () async {
      final result = await getItems(artistIds: SubsonicIds.artist("ar1").raw, includeItemTypes: "Audio");
      expect(names(result), unorderedEquals(["Alpha", "Bravo", "Charlie", "Delta", "Echo"]));
      final albums = await getItems(artistIds: SubsonicIds.artist("ar1").raw, includeItemTypes: "MusicAlbum");
      expect(names(albums), unorderedEquals(["First Album", "Second Album", "Guest Album"]));
    });

    test("lists items of a genre", () async {
      final result = await getItems(genreIds: SubsonicIds.genre("Rock").raw, includeItemTypes: "MusicAlbum");
      expect(result.totalRecordCount, 3);
    });

    test("lists artists, ignoring articles when sorting", () async {
      final result = await getItems(includeItemTypes: "MusicArtist", sortBy: "SortName");
      expect(names(result), ["The Artist", "Other Artist"]);
    });

    test("lists genres", () async {
      final result = QueryResult_BaseItemDto.fromJson(await api.getGenres(sortBy: "SortName") as Map<String, dynamic>);
      expect(names(result), ["Jazz", "Rock"]);
    });

    test("there are no tracks outside of albums", () async {
      final response = await api.getItems(
        userId: "jane",
        parentId: SubsonicIds.library("1"),
        includeItemTypes: "Audio",
        recursive: false,
      );
      expect(QueryResult_BaseItemDto.fromJson(response as Map<String, dynamic>).items, isEmpty);
    });

    test("searches genres in a library", () async {
      final response = await api.getItems(
        userId: "jane",
        parentId: SubsonicIds.library("1"),
        includeItemTypes: "MusicGenre",
        recursive: false,
        searchTerm: "jaz",
      );
      expect(names(QueryResult_BaseItemDto.fromJson(response as Map<String, dynamic>)), ["Jazz"]);
    });

    test("searches", () async {
      final result = await getItems(includeItemTypes: "MusicAlbum,Audio", searchTerm: "echo", limit: 30);
      expect(names(result), ["Echo"]);
    });

    test("fetches items by id, keeping their order and skipping missing items", () async {
      final ids = [SubsonicIds.album("al2"), SubsonicIds.track("missing"), SubsonicIds.track("s1")];
      final result = await getItems(ids: ids.map((id) => id.raw).join(","));
      expect(names(result), ["Second Album", "Alpha"]);
    });

    test("track lists survive the trip through JSON", () async {
      final result = await getItems(includeItemTypes: "Audio", limit: 1);
      final track = result.items!.single;
      expect(track.finampOffline, isNull);
      expect(track.mediaSources, isNotEmpty);
    });
  });

  test("gets single items", () async {
    final item = BaseItemDto.fromJson(
      await api.getItemById(userId: "jane", itemId: SubsonicIds.artist("ar1")) as Map<String, dynamic>,
    );
    expect(item.name, "The Artist");
    expect(item.type, "MusicArtist");
  });

  test("latest albums", () async {
    final latest = await api.getLatestItems(userId: "jane", includeItemTypes: "MusicAlbum", limit: 5) as List<dynamic>;
    expect(latest.length, 3);
    expect(server.requestsTo("getAlbumList2").single.queryParameters["type"], "newest");
  });

  group("playback", () {
    test("playback info reports lyrics", () async {
      final withLyrics = PlaybackInfoResponse.fromJson(
        await api.getPlaybackInfo(id: SubsonicIds.track("s1"), userId: "jane") as Map<String, dynamic>,
      );
      expect(withLyrics.mediaSources?.single.mediaStreams.map((stream) => stream.type), ["Audio", "Lyric"]);
      final withoutLyrics = PlaybackInfoResponse.fromJson(
        await api.getPlaybackInfo(id: SubsonicIds.track("s2"), userId: "jane") as Map<String, dynamic>,
      );
      expect(withoutLyrics.mediaSources?.single.mediaStreams.map((stream) => stream.type), ["Audio"]);
    });

    test("lyrics", () async {
      final lyrics = LyricDto.fromJson(await api.getLyrics(itemId: SubsonicIds.track("s1")) as Map<String, dynamic>);
      expect(lyrics.lyrics?.single.text, "La la la");
      await expectLater(api.getLyrics(itemId: SubsonicIds.track("s2")), throwsA(isA<SubsonicException>()));
    });

    PlaybackProgressInfo progress(Duration position) => PlaybackProgressInfo(
      itemId: SubsonicIds.track("s1"),
      isPaused: false,
      isMuted: false,
      repeatMode: "RepeatNone",
      positionTicks: position.inMicroseconds * 10,
      playbackStartTimeTicks: DateTime.utc(2024).millisecondsSinceEpoch * 10000,
    );

    test("reports now playing", () async {
      await api.startPlayback(progress(Duration.zero));
      expect(server.requestsTo("scrobble").single.queryParameters, containsPair("submission", "false"));
    });

    test("scrobbles tracks that were played for at least half their duration", () async {
      // The track is 200 seconds long
      await api.playbackStatusStopped(progress(const Duration(seconds: 30)));
      expect(server.requestsTo("scrobble"), isEmpty);
      await api.playbackStatusStopped(progress(const Duration(seconds: 120)));
      final scrobble = server.requestsTo("scrobble").single.queryParameters;
      expect(scrobble["submission"], "true");
      expect(scrobble["time"], DateTime.utc(2024).millisecondsSinceEpoch.toString());
    });
  });

  test("instant mixes fall back to random tracks of the same genre", () async {
    final mix = QueryResult_BaseItemDto.fromJson(
      await api.getInstantMix(id: SubsonicIds.track("s4"), userId: "jane", limit: 10) as Map<String, dynamic>,
    );
    // The seed track comes first, followed by the other jazz tracks (there are none)
    expect(names(mix), ["Delta"]);
    expect(server.requestsTo("getRandomSongs").first.queryParameters["genre"], "Jazz");
  });

  test("favorites", () async {
    final userData = UserItemDataDto.fromJson(
      await api.addFavorite(userId: "jane", itemId: SubsonicIds.album("al1")) as Map<String, dynamic>,
    );
    expect(userData.isFavorite, isTrue);
    expect(server.requestsTo("star").single.queryParameters["albumId"], "al1");
    await expectLater(
      api.addFavorite(userId: "jane", itemId: SubsonicIds.genre("Rock")),
      throwsA(isA<SubsonicUnsupportedException>()),
    );
  });

  group("playlists", () {
    var entries = <String>[];

    setUp(() {
      entries = ["s1", "s2", "s1", "s3"];
      server.handlers.addAll({
        "getPlaylists": (_) => {
          "playlists": {
            "playlist": [
              {"id": "p1", "name": "Mix", "owner": "jane", "songCount": entries.length},
            ],
          },
        },
        "getPlaylist": (_) => {
          "playlist": {
            "id": "p1",
            "name": "Mix",
            "owner": "jane",
            "public": true,
            "entry": entries.map((id) => _songs[id]).toList(),
          },
        },
        "createPlaylist": (parameters) => {
          "playlist": {"id": "p2", "name": parameters["name"]?.first},
        },
        "updatePlaylist": (parameters) {
          for (final index in (parameters["songIndexToRemove"] ?? []).map(int.parse).toList()..sort((a, b) => b - a)) {
            entries.removeAt(index);
          }
          entries.addAll(parameters["songIdToAdd"] ?? []);
          return {};
        },
      });
    });

    test("lists entries in order with entry ids", () async {
      final result = QueryResult_BaseItemDto.fromJson(
        await api.getPlaylistItems(playlistId: SubsonicIds.playlist("p1"), userId: "jane") as Map<String, dynamic>,
      );
      expect(names(result), ["Alpha", "Bravo", "Alpha", "Charlie"]);
      expect(result.items![2].playlistItemId, SubsonicIds.playlistEntry(2, "s1"));
    });

    test("removes the right entry even if the playlist changed", () async {
      // The entry was loaded at index 2, but an entry before it was removed in the meantime
      final entryId = SubsonicIds.playlistEntry(2, "s1");
      entries.removeAt(1);
      await api.removeItemsFromPlaylist(playlistId: SubsonicIds.playlist("p1"), entryIds: entryId);
      expect(server.requestsTo("updatePlaylist").single.queryParameters["songIndexToRemove"], "1");
      expect(entries, ["s1", "s3"]);
    });

    test("creating a playlist adds the tracks of albums", () async {
      final response = NewPlaylistResponse.fromJson(
        await api.createNewPlaylist(
              newPlaylist: NewPlaylist(name: "New", ids: [SubsonicIds.album("al2"), SubsonicIds.track("s1")]),
            )
            as Map<String, dynamic>,
      );
      expect(response.id?.raw, "playlist-p2");
      expect(server.requestsTo("createPlaylist").single.queryParametersAll["songId"], ["s3", "s4", "s1"]);
    });

    test("only the owner can edit", () async {
      final user = PlaylistUser.fromJson(
        await api.getPlaylistUser(userId: "jane", playlistId: SubsonicIds.playlist("p1")) as Map<String, dynamic>,
      );
      expect(user.canEdit, isTrue);
      final otherApi = createApi(
        withCredentials: SubsonicCredentials.token(username: "joe", password: "x"),
      );
      final otherUser = PlaylistUser.fromJson(
        await otherApi.getPlaylistUser(userId: "joe", playlistId: SubsonicIds.playlist("p1")) as Map<String, dynamic>,
      );
      expect(otherUser.canEdit, isFalse);
    });

    test("replacing all tracks", () async {
      await api.updatePlaylist(
        playlistId: SubsonicIds.playlist("p1"),
        playlist: NewPlaylist(ids: [SubsonicIds.track("s4"), SubsonicIds.track("s2")]),
      );
      final request = server.requestsTo("createPlaylist").single;
      expect(request.queryParameters["playlistId"], "p1");
      expect(request.queryParametersAll["songId"], ["s4", "s2"]);
    });
  });
}
