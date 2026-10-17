import 'package:collection/collection.dart';
import 'package:finamp/models/jellyfin_models.dart';
import 'package:path/path.dart' as path_helper;

import 'subsonic_api.dart';
import 'subsonic_ids.dart';

typedef SubsonicJson = Map<String, dynamic>;

/// Converts Subsonic API responses into the Jellyfin models used throughout Finamp.
///
/// Images: Subsonic identifies cover art by a separate "coverArt" id, which we store as the image tag.  Items with
/// their own image put it in [BaseItemDto.imageTags], while tracks point to their album with
/// [BaseItemDto.albumPrimaryImageTag], so that all tracks of an album share one cached/downloaded image.
abstract final class SubsonicMapper {
  static const ticksPerSecond = 10000000;
  static const ticksPerMillisecond = 10000;

  /// The cover art id of the image [BaseItemDto.imageId] refers to.
  static String? coverArtId(BaseItemDto item) {
    if (item.hasOwnImage) {
      return item.imageTags?["Primary"];
    } else if (item.parentPrimaryImageItemId != null) {
      return item.parentPrimaryImageTag;
    } else if (item.albumId != null) {
      return item.albumPrimaryImageTag;
    }
    return null;
  }

  static BaseItemDto track(SubsonicJson song, {String? playlistEntryId}) {
    final id = song["id"] as String;
    final albumId = song["albumId"] as String?;
    final coverArt = song["coverArt"] as String?;
    final artists = _artists(song["artists"], fallbackId: song["artistId"], fallbackName: song["artist"]);
    var albumArtists = _artists(song["albumArtists"]);
    if (albumArtists.isEmpty) {
      // Plain Subsonic servers don't tell us the album artist of a track
      albumArtists = artists;
    }
    final replayGain = SubsonicApi.asMap(song["replayGain"]);
    final duration = (song["duration"] as num?)?.toInt();
    return BaseItemDto(
      id: SubsonicIds.track(id),
      name: song["title"] as String? ?? song["name"] as String?,
      type: "Audio",
      mediaType: "Audio",
      isFolder: false,
      sortName: song["sortName"] as String?,
      album: song["album"] as String?,
      albumId: albumId == null ? null : SubsonicIds.album(albumId),
      parentId: albumId == null ? null : SubsonicIds.album(albumId),
      albumPrimaryImageTag: albumId == null ? null : coverArt,
      imageTags: albumId == null && coverArt != null ? {"Primary": coverArt} : null,
      artists: artists.map((artist) => artist.name).nonNulls.toList(),
      artistItems: artists,
      albumArtist:
          song["displayAlbumArtist"] as String? ?? albumArtists.map((artist) => artist.name).nonNulls.join(", "),
      albumArtists: albumArtists,
      indexNumber: (song["track"] as num?)?.toInt(),
      parentIndexNumber: (song["discNumber"] as num?)?.toInt(),
      productionYear: _year(song["year"]),
      premiereDate: _yearDate(song["year"]),
      runTimeTicks: duration == null ? null : duration * ticksPerSecond,
      dateCreated: song["created"] as String?,
      genres: _genreNames(song),
      genreItems: _genreNames(song).map((name) => NameLongIdPair(name: name, id: SubsonicIds.genre(name))).toList(),
      userData: _userData(song),
      communityRating: (song["userRating"] as num?)?.toDouble() ?? (song["averageRating"] as num?)?.toDouble(),
      officialRating: song["explicitStatus"] == "explicit" ? "Explicit" : null,
      normalizationGain: (replayGain?["trackGain"] as num?)?.toDouble(),
      albumNormalizationGain: (replayGain?["albumGain"] as num?)?.toDouble(),
      playlistItemId: playlistEntryId,
      path: song["path"] as String?,
      container: song["suffix"] as String?,
      mediaSources: [mediaSource(song)],
    );
  }

  static MediaSourceInfo mediaSource(SubsonicJson song, {List<MediaStream> extraStreams = const []}) {
    final duration = (song["duration"] as num?)?.toInt();
    final bitRateKbps = (song["bitRate"] as num?)?.toInt();
    final songPath = song["path"] as String?;
    return MediaSourceInfo(
      id: SubsonicIds.track(song["id"] as String),
      protocol: "Http",
      type: "Default",
      path: songPath,
      // Used for human readable download file names
      name: songPath == null ? null : path_helper.basenameWithoutExtension(songPath),
      container: song["suffix"] as String?,
      size: (song["size"] as num?)?.toInt(),
      bitrate: bitRateKbps == null ? null : bitRateKbps * 1000,
      runTimeTicks: duration == null ? null : duration * ticksPerSecond,
      isRemote: true,
      supportsTranscoding: true,
      supportsDirectStream: true,
      supportsDirectPlay: true,
      isInfiniteStream: false,
      requiresOpening: false,
      requiresClosing: false,
      requiresLooping: false,
      supportsProbing: false,
      readAtNativeFramerate: false,
      ignoreDts: false,
      ignoreIndex: false,
      genPtsInput: false,
      mediaStreams: [
        MediaStream(
          index: 0,
          type: "Audio",
          codec: _codec(song),
          bitRate: bitRateKbps == null ? null : bitRateKbps * 1000,
          sampleRate: (song["samplingRate"] as num?)?.toInt(),
          bitDepth: (song["bitDepth"] as num?)?.toInt(),
          channels: (song["channelCount"] as num?)?.toInt(),
          isInterlaced: false,
          isDefault: true,
          isForced: false,
          isExternal: false,
          isTextSubtitleStream: false,
          supportsExternalStream: false,
        ),
        ...extraStreams,
      ],
    );
  }

  /// The media stream that tells Finamp a track has lyrics.
  static MediaStream lyricsStream() => MediaStream(
    index: 1,
    type: "Lyric",
    isInterlaced: false,
    isDefault: false,
    isForced: false,
    isExternal: false,
    isTextSubtitleStream: false,
    supportsExternalStream: false,
  );

  static BaseItemDto album(SubsonicJson album, {List<SubsonicJson>? songs}) {
    final id = album["id"] as String;
    final coverArt = album["coverArt"] as String?;
    final artists = _artists(album["artists"], fallbackId: album["artistId"], fallbackName: album["artist"]);
    final duration = (album["duration"] as num?)?.toInt();
    final releaseDate = _date(album["originalReleaseDate"]) ?? _date(album["releaseDate"]);
    final albumGain = songs
        ?.map((song) => (SubsonicApi.asMap(song["replayGain"])?["albumGain"] as num?)?.toDouble())
        .nonNulls
        .firstOrNull;
    return BaseItemDto(
      id: SubsonicIds.album(id),
      name: album["name"] as String? ?? album["title"] as String?,
      type: "MusicAlbum",
      isFolder: true,
      sortName: album["sortName"] as String?,
      imageTags: coverArt == null ? null : {"Primary": coverArt},
      albumArtist: album["displayArtist"] as String? ?? album["artist"] as String?,
      albumArtists: artists,
      artists: artists.map((artist) => artist.name).nonNulls.toList(),
      artistItems: artists,
      productionYear: _year(album["year"]) ?? releaseDate?.year,
      premiereDate: releaseDate?.toIso8601String() ?? _yearDate(album["year"]),
      childCount: (album["songCount"] as num?)?.toInt(),
      songCount: (album["songCount"] as num?)?.toInt(),
      runTimeTicks: duration == null ? null : duration * ticksPerSecond,
      dateCreated: album["created"] as String?,
      dateLastMediaAdded: album["created"] as String?,
      genres: _genreNames(album),
      genreItems: _genreNames(album).map((name) => NameLongIdPair(name: name, id: SubsonicIds.genre(name))).toList(),
      userData: _userData(album),
      communityRating: (album["userRating"] as num?)?.toDouble(),
      officialRating: album["explicitStatus"] == "explicit" ? "Explicit" : null,
      normalizationGain: albumGain,
    );
  }

  static BaseItemDto artist(SubsonicJson artist, {SubsonicJson? info}) {
    final id = artist["id"] as String;
    final coverArt = artist["coverArt"] as String?;
    return BaseItemDto(
      id: SubsonicIds.artist(id),
      name: artist["name"] as String?,
      type: "MusicArtist",
      isFolder: true,
      sortName: artist["sortName"] as String?,
      imageTags: coverArt == null ? null : {"Primary": coverArt},
      albumCount: (artist["albumCount"] as num?)?.toInt(),
      childCount: (artist["albumCount"] as num?)?.toInt(),
      userData: _userData(artist),
      overview: _stripHtml(info?["biography"] as String?),
    );
  }

  static BaseItemDto playlist(SubsonicJson playlist, {required String username}) {
    final id = playlist["id"] as String;
    final coverArt = playlist["coverArt"] as String?;
    final duration = (playlist["duration"] as num?)?.toInt();
    final owner = playlist["owner"] as String?;
    return BaseItemDto(
      id: SubsonicIds.playlist(id),
      name: playlist["name"] as String?,
      type: "Playlist",
      mediaType: "Audio",
      isFolder: true,
      imageTags: coverArt == null ? null : {"Primary": coverArt},
      childCount: (playlist["songCount"] as num?)?.toInt(),
      runTimeTicks: duration == null ? null : duration * ticksPerSecond,
      dateCreated: playlist["created"] as String?,
      dateLastMediaAdded: playlist["changed"] as String?,
      overview: playlist["comment"] as String?,
      canDelete: owner == null || owner == username,
      userData: _userData(playlist),
    );
  }

  static BaseItemDto genre(SubsonicJson genre) {
    final name = genre["value"] as String? ?? genre["name"] as String? ?? "";
    return BaseItemDto(
      id: SubsonicIds.genre(name),
      name: name,
      type: "MusicGenre",
      isFolder: true,
      albumCount: (genre["albumCount"] as num?)?.toInt(),
      songCount: (genre["songCount"] as num?)?.toInt(),
      childCount: (genre["albumCount"] as num?)?.toInt(),
    );
  }

  /// A genre we only know by name, e.g. from a track's tags.
  static BaseItemDto genreByName(String name) => genre({"value": name});

  /// Music folders are what Jellyfin calls libraries (or views).
  static BaseItemDto library(SubsonicJson folder) {
    final id = folder["id"].toString();
    return BaseItemDto(
      id: SubsonicIds.library(id),
      name: folder["name"] as String? ?? "Music",
      type: "CollectionFolder",
      collectionType: "music",
      isFolder: true,
    );
  }

  static UserDto user(String username, {SubsonicJson? user, String? serverId}) => UserDto(
    id: username,
    name: user?["username"] as String? ?? username,
    serverId: serverId,
    hasPassword: true,
    hasConfiguredPassword: true,
    hasConfiguredEasyPassword: false,
  );

  /// Converts OpenSubsonic structured lyrics, preferring synced lyrics.  Returns null if there are no lyrics.
  static LyricDto? structuredLyrics(List<SubsonicJson> lyricsList) {
    final lyrics =
        lyricsList.firstWhereOrNull((lyrics) => lyrics["synced"] == true && _lines(lyrics).isNotEmpty) ??
        lyricsList.firstWhereOrNull((lyrics) => _lines(lyrics).isNotEmpty);
    if (lyrics == null) {
      return null;
    }
    final synced = lyrics["synced"] == true;
    final offsetMs = (lyrics["offset"] as num?)?.toInt();
    return LyricDto(
      metadata: LyricMetadata(
        artist: lyrics["displayArtist"] as String?,
        title: lyrics["displayTitle"] as String?,
        offset: offsetMs == null ? null : offsetMs * ticksPerMillisecond,
        isSynced: synced,
      ),
      lyrics: _lines(lyrics).map((line) {
        final startMs = (line["start"] as num?)?.toInt();
        return LyricLine(
          text: line["value"] as String? ?? "",
          start: synced && startMs != null ? startMs * ticksPerMillisecond : null,
        );
      }).toList(),
    );
  }

  /// Converts the plain lyrics returned by the original getLyrics endpoint.  Returns null if there are no lyrics.
  static LyricDto? plainLyrics(SubsonicJson? lyrics) {
    final text = lyrics?["value"] as String?;
    if (text == null || text.trim().isEmpty) {
      return null;
    }
    return LyricDto(
      metadata: LyricMetadata(
        artist: lyrics?["artist"] as String?,
        title: lyrics?["title"] as String?,
        isSynced: false,
      ),
      lyrics: text.split(RegExp(r"\r?\n")).map((line) => LyricLine(text: line)).toList(),
    );
  }

  static List<SubsonicJson> _lines(SubsonicJson lyrics) => SubsonicApi.asList(lyrics["line"]);

  static UserItemDataDto _userData(SubsonicJson json) {
    final playCount = (json["playCount"] as num?)?.toInt() ?? 0;
    return UserItemDataDto(
      isFavorite: json["starred"] != null,
      playCount: playCount,
      played: playCount > 0 || json["played"] != null,
      lastPlayedDate: json["played"] as String?,
      playbackPositionTicks: 0,
      rating: (json["userRating"] as num?)?.toDouble(),
    );
  }

  static UserItemDataDto favoriteUserData({required bool isFavorite}) =>
      UserItemDataDto(isFavorite: isFavorite, playCount: 0, played: false, playbackPositionTicks: 0);

  /// Reads the OpenSubsonic list of artists, falling back to the single artist of the original API.
  static List<NameIdPair> _artists(Object? artists, {Object? fallbackId, Object? fallbackName}) {
    final list = SubsonicApi.asList(artists)
        .where((artist) => artist["id"] is String)
        .map((artist) => NameIdPair(name: artist["name"] as String?, id: SubsonicIds.artist(artist["id"] as String)))
        .toList();
    if (list.isEmpty && fallbackId is String) {
      list.add(NameIdPair(name: fallbackName as String?, id: SubsonicIds.artist(fallbackId)));
    }
    return list;
  }

  static List<String> _genreNames(SubsonicJson json) {
    final genres = SubsonicApi.asList(json["genres"]).map((genre) => genre["name"] as String?).nonNulls.toList();
    final genre = json["genre"] as String?;
    if (genres.isEmpty && genre != null && genre.isNotEmpty) {
      genres.add(genre);
    }
    return genres;
  }

  static String? _codec(SubsonicJson song) {
    final contentType = song["contentType"] as String?;
    final suffix = (song["suffix"] as String?)?.toLowerCase();
    return switch (suffix) {
      "m4a" || "mp4" => (contentType?.contains("alac") ?? false) ? "alac" : "aac",
      "ogg" || "oga" => "vorbis",
      _ => suffix,
    };
  }

  static int? _year(Object? year) {
    final value = (year as num?)?.toInt();
    return value == null || value == 0 ? null : value;
  }

  static String? _yearDate(Object? year) {
    final value = _year(year);
    return value == null ? null : DateTime.utc(value).toIso8601String();
  }

  /// Parses an OpenSubsonic ItemDate ({year, month, day}).
  static DateTime? _date(Object? date) {
    final json = SubsonicApi.asMap(date);
    final year = _year(json?["year"]);
    if (year == null) return null;
    return DateTime.utc(year, (json?["month"] as num?)?.toInt() ?? 1, (json?["day"] as num?)?.toInt() ?? 1);
  }

  static String? _stripHtml(String? text) {
    if (text == null) return null;
    final stripped = text.replaceAll(RegExp(r"<[^>]*>"), "").trim();
    return stripped.isEmpty ? null : stripped;
  }
}
