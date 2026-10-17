import 'package:finamp/models/jellyfin_models.dart';
import 'package:finamp/services/subsonic/subsonic_ids.dart';
import 'package:finamp/services/subsonic/subsonic_mapper.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_subsonic_server.dart';

void main() {
  group("SubsonicIds", () {
    test("only tracks keep their id unchanged", () {
      expect(SubsonicIds.track("123").raw, "123");
      expect(SubsonicIds.album("123").raw, "album-123");
      expect(SubsonicIds.parse("123"), (kind: SubsonicItemKind.track, id: "123"));
    });

    test("round trips all kinds", () {
      expect(SubsonicIds.parse(SubsonicIds.album("1").raw), (kind: SubsonicItemKind.album, id: "1"));
      expect(SubsonicIds.parse(SubsonicIds.artist("1").raw), (kind: SubsonicItemKind.artist, id: "1"));
      expect(SubsonicIds.parse(SubsonicIds.playlist("1").raw), (kind: SubsonicItemKind.playlist, id: "1"));
      expect(SubsonicIds.parse(SubsonicIds.library("1").raw), (kind: SubsonicItemKind.library, id: "1"));
    });

    test("genre ids are safe to use in comma separated lists", () {
      const name = "Rock, Pop & Ünïcode/Other";
      final id = SubsonicIds.genre(name).raw;
      expect(id, isNot(contains(",")));
      expect(id, isNot(contains("/")));
      expect(SubsonicIds.parse(id), (kind: SubsonicItemKind.genre, id: name));
    });

    test("playlist entries", () {
      expect(SubsonicIds.parsePlaylistEntry(SubsonicIds.playlistEntry(3, "abc")), (index: 3, trackId: "abc"));
      expect(SubsonicIds.parsePlaylistEntry("garbage"), isNull);
    });
  });

  group("tracks", () {
    test("map basic Subsonic fields", () {
      final item = SubsonicMapper.track(song("s1", title: "Song", track: 3, disc: 2, playCount: 4, starred: "x"));
      expect(item.id.raw, "s1");
      expect(item.type, "Audio");
      expect(item.name, "Song");
      expect(item.album, "First Album");
      expect(item.albumId?.raw, "album-al1");
      expect(item.indexNumber, 3);
      expect(item.parentIndexNumber, 2);
      expect(item.runTimeTicksDuration(), const Duration(seconds: 200));
      expect(item.artists, ["The Artist"]);
      expect(item.artistItems?.single.id.raw, "artist-ar1");
      // Without OpenSubsonic album artists, the track artist is the best guess
      expect(item.albumArtists?.single.id.raw, "artist-ar1");
      expect(item.genreItems?.single.id, SubsonicIds.genre("Rock"));
      expect(item.userData?.isFavorite, isTrue);
      expect(item.userData?.playCount, 4);
      expect(item.mediaSources?.single.container, "mp3");
      expect(item.mediaSources?.single.bitrate, 320000);
      expect(item.mediaSources?.single.name, "3 - Song");
    });

    test("tracks share the image of their album", () {
      final item = SubsonicMapper.track(song("s1", title: "Song"));
      expect(item.hasOwnImage, isFalse);
      expect(item.imageId, "album-al1");
      expect(SubsonicMapper.coverArtId(item), "mf-s1");
    });

    test("map OpenSubsonic fields", () {
      final item = SubsonicMapper.track({
        ...song("s1", title: "Song"),
        "artists": [
          {"id": "ar1", "name": "One"},
          {"id": "ar2", "name": "Two"},
        ],
        "albumArtists": [
          {"id": "ar3", "name": "Three"},
        ],
        "displayAlbumArtist": "Three",
        "genres": [
          {"name": "Jazz"},
          {"name": "Blues"},
        ],
        "replayGain": {"trackGain": -6.5, "albumGain": -7.0},
        "explicitStatus": "explicit",
        "samplingRate": 44100,
        "bitDepth": 16,
        "channelCount": 2,
      });
      expect(item.artists, ["One", "Two"]);
      expect(item.albumArtist, "Three");
      expect(item.albumArtists?.single.id.raw, "artist-ar3");
      expect(item.genres, ["Jazz", "Blues"]);
      expect(item.normalizationGain, -6.5);
      expect(item.albumNormalizationGain, -7.0);
      expect(item.isExplicit, isTrue);
      expect(item.mediaStreams?.single.sampleRate, 44100);
    });

    test("survive a JSON round trip without being marked offline", () {
      final item = SubsonicMapper.track(song("s1", title: "Song"));
      final copy = BaseItemDto.fromJson(item.toJson(setOffline: false));
      expect(copy.finampOffline, isNull);
      expect(copy.id, item.id);
      expect(copy.mediaSources?.single.mediaStreams.single.type, "Audio");
    });
  });

  test("albums use their own cover art", () {
    final item = SubsonicMapper.album(album("al1", name: "First Album", year: 1999, starred: "x"));
    expect(item.id.raw, "album-al1");
    expect(item.type, "MusicAlbum");
    expect(item.hasOwnImage, isTrue);
    expect(SubsonicMapper.coverArtId(item), "al-al1");
    expect(item.productionYear, 1999);
    expect(item.premiereDate, startsWith("1999-01-01"));
    expect(item.childCount, 2);
    expect(item.userData?.isFavorite, isTrue);
  });

  test("albums use the album gain of their tracks", () {
    final item = SubsonicMapper.album(
      album("al1", name: "First Album"),
      songs: [
        {
          ...song("s1", title: "Song"),
          "replayGain": {"albumGain": -3.25},
        },
      ],
    );
    expect(item.normalizationGain, -3.25);
  });

  test("artists include their biography", () {
    final item = SubsonicMapper.artist(
      {"id": "ar1", "name": "The Artist", "albumCount": 3, "coverArt": "ar-ar1"},
      info: {"biography": "A <a href='x'>band</a>."},
    );
    expect(item.id.raw, "artist-ar1");
    expect(item.type, "MusicArtist");
    expect(item.albumCount, 3);
    expect(item.overview, "A band.");
  });

  test("playlists can only be deleted by their owner", () {
    final playlist = {"id": "p1", "name": "Mix", "owner": "jane", "songCount": 5, "duration": 900};
    expect(SubsonicMapper.playlist(playlist, username: "jane").canDelete, isTrue);
    expect(SubsonicMapper.playlist(playlist, username: "joe").canDelete, isFalse);
    expect(SubsonicMapper.playlist(playlist, username: "joe").childCount, 5);
  });

  group("lyrics", () {
    test("prefer synced lyrics", () {
      final lyrics = SubsonicMapper.structuredLyrics([
        {
          "synced": false,
          "line": [
            {"value": "Unsynced"},
          ],
        },
        {
          "synced": true,
          "offset": 100,
          "line": [
            {"start": 1000, "value": "First"},
            {"start": 2500, "value": "Second"},
          ],
        },
      ])!;
      expect(lyrics.metadata?.isSynced, isTrue);
      expect(lyrics.metadata?.offset, 100 * SubsonicMapper.ticksPerMillisecond);
      expect(lyrics.lyrics?.map((line) => line.text), ["First", "Second"]);
      expect(lyrics.lyrics?.last.startMicros, 2500000);
    });

    test("unsynced lyrics have no timestamps", () {
      final lyrics = SubsonicMapper.structuredLyrics([
        {
          "synced": false,
          "line": [
            {"value": "Only line"},
          ],
        },
      ])!;
      expect(lyrics.lyrics?.single.start, isNull);
    });

    test("missing lyrics", () {
      expect(SubsonicMapper.structuredLyrics([]), isNull);
      expect(SubsonicMapper.plainLyrics({"value": "  "}), isNull);
      expect(SubsonicMapper.plainLyrics({"value": "One\nTwo"})?.lyrics?.length, 2);
    });
  });
}
