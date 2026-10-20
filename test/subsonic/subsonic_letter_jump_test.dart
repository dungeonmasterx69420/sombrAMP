import 'package:finamp/components/MusicScreen/music_screen_tab_view.dart';
import 'package:finamp/models/finamp_models.dart';
import 'package:finamp/models/jellyfin_models.dart';
import 'package:finamp/services/subsonic/subsonic_api.dart';
import 'package:finamp/services/subsonic/subsonic_jellyfin_api.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_subsonic_server.dart';

/// Artists like Navidrome lists them: with its sort names (lower case, without accents or leading articles), except
/// for the last few, which have none like on servers without OpenSubsonic.
final _artists = [
  {"id": "a1", "name": "The Beatles", "sortName": "beatles"},
  {"id": "a2", "name": "ABBA", "sortName": "abba"},
  {"id": "a3", "name": "Die Ärzte", "sortName": "die arzte"},
  {"id": "a4", "name": "2Pac", "sortName": "2pac"},
  {"id": "a5", "name": "!!!", "sortName": "!!!"},
  {"id": "a6", "name": "Björk", "sortName": "bjork"},
  {"id": "a7", "name": "deadmau5", "sortName": "deadmau5"},
  {"id": "a8", "name": "Los Lobos", "sortName": "lobos"},
  {"id": "a9", "name": "Éric Serra", "sortName": "eric serra"},
  {"id": "a10", "name": "a-ha", "sortName": "a-ha"},
  {"id": "a11", "name": "Zebra"},
  {"id": "a12", "name": "The Who"},
  {"id": "a13", "name": "Massive Attack"},
  {"id": "a14", "name": "queen"},
];

final _albums = [
  album("al1", name: "Abbey Road", artistId: "a1", artist: "The Beatles"),
  album("al2", name: "Homogenic", artistId: "a6", artist: "Björk"),
  album("al3", name: "Mezzanine", artistId: "a13", artist: "Massive Attack"),
  {
    ...album("al4", name: "Heroes & Villains", artistId: "m1", artist: "Metro Boomin & Future"),
    "artists": [
      {"id": "m1", "name": "Metro Boomin"},
      {"id": "f1", "name": "Future"},
    ],
  },
  album("al5", name: "Voulez-Vous", artistId: "a2", artist: "ABBA"),
];

final _songs = [
  song("s1", title: "Alpha"),
  song("s2", title: "bravo"),
  song("s3", title: "Échec"),
  song("s4", title: "The End"),
  song("s5", title: "99 Problems"),
  song("s6", title: "Zoo"),
];

void main() {
  late SubsonicJellyfinApi api;

  setUp(() {
    final server = FakeSubsonicServer({
      "getArtists": (_) => {
        "artists": {
          "index": [
            {"name": "#", "artist": _artists},
          ],
        },
      },
      "getAlbumList2": (parameters) => {
        "albumList2": {"album": _albums.skip(int.parse(parameters["offset"]?.first ?? "0")).toList()},
      },
      "search3": (parameters) => {
        "searchResult3": {"song": _songs.skip(int.parse(parameters["songOffset"]?.first ?? "0")).toList()},
      },
    });
    api = SubsonicJellyfinApi(
      baseUrl: () => FakeSubsonicServer.baseUrl,
      credentials: () => SubsonicCredentials.token(username: "jane", password: "secret"),
      api: SubsonicApi(httpClient: server.client),
    );
  });

  /// Lists [tab] sorted by [sortBy] like the music screen does, and returns the name of the item each letter jumps to.
  Future<Map<String, String?>> jumps(
    ContentType tab,
    SortBy sortBy, {
    required List<String> letters,
    String Function(BaseItemDto item)? label,
    bool descending = false,
  }) async {
    final response = await api.getItems(
      userId: "jane",
      includeItemTypes: tab.itemType!.jellyfinName,
      sortBy: sortBy.jellyfinName(tab),
      sortOrder: descending ? "Descending" : "Ascending",
    );
    final items = QueryResult_BaseItemDto.fromJson(response as Map<String, dynamic>).items!;
    final keys = items.map((item) => sortKeyForLetterJump(item, sortBy)).toList();
    return {
      for (final letter in letters)
        letter: switch (indexForLetter(keys, letter, descending: descending)) {
          null => null,
          final index => (label ?? (item) => item.name!)(items[index]),
        },
    };
  }

  test("artists tab", () async {
    expect(
      await jumps(
        ContentType.albumArtists,
        SortBy.sortName,
        letters: ["#", "A", "B", "C", "E", "L", "Q", "W", "X", "Z"],
      ),
      {
        "#": "!!!",
        "A": "a-ha",
        "B": "The Beatles",
        // No artists start with C, so it's the next one
        "C": "deadmau5",
        "E": "Éric Serra",
        "L": "Los Lobos",
        "Q": "queen",
        "W": "The Who",
        "X": "Zebra",
        "Z": "Zebra",
      },
    );
  });

  test("artists tab, sorted descending", () async {
    expect(await jumps(ContentType.albumArtists, SortBy.sortName, letters: ["Z", "C", "A", "#"], descending: true), {
      "Z": "Zebra",
      "C": "Björk",
      "A": "ABBA",
      "#": "2Pac",
    });
  });

  test("albums tab, sorted by album artist", () async {
    expect(
      await jumps(
        ContentType.albums,
        SortBy.albumArtist,
        letters: ["A", "B", "F", "M", "T"],
        label: (album) => "${album.name} by ${album.albumArtist}",
      ),
      {
        "A": "Voulez-Vous by ABBA",
        "B": "Homogenic by Björk",
        // Sorted by its first artist, so not under F
        "F": "Mezzanine by Massive Attack",
        "M": "Mezzanine by Massive Attack",
        "T": "Abbey Road by The Beatles",
      },
    );
  });

  test("tracks tab", () async {
    expect(await jumps(ContentType.tracks, SortBy.sortName, letters: ["#", "A", "B", "E", "T", "Z"]), {
      "#": "99 Problems",
      "A": "Alpha",
      "B": "bravo",
      "E": "Échec",
      "T": "The End",
      "Z": "Zoo",
    });
  });
}
