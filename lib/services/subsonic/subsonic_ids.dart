import 'dart:convert';

import 'package:finamp/models/jellyfin_models.dart';

/// The kinds of Subsonic entities we map to [BaseItemDto]s.
enum SubsonicItemKind { track, album, artist, playlist, genre, library }

/// A Subsonic entity, identified by its kind and its id on the server.
typedef SubsonicRef = ({SubsonicItemKind kind, String id});

/// Converts between Subsonic ids and Finamp item ids.
///
/// Subsonic only guarantees ids to be unique per kind of entity (some servers use plain integers), and Finamp often
/// looks up items by id alone, so all ids except track ids carry a prefix naming their kind.  Track ids are kept as-is,
/// because they are used as file names for downloads and are by far the most common.  Genres don't have ids in
/// Subsonic, so their name is used, base64 encoded to avoid characters like "," and "/".
abstract final class SubsonicIds {
  static const _albumPrefix = "album-";
  static const _artistPrefix = "artist-";
  static const _playlistPrefix = "playlist-";
  static const _genrePrefix = "genre-";
  static const _libraryPrefix = "library-";

  static BaseItemId track(String id) => BaseItemId(id);
  static BaseItemId album(String id) => BaseItemId("$_albumPrefix$id");
  static BaseItemId artist(String id) => BaseItemId("$_artistPrefix$id");
  static BaseItemId playlist(String id) => BaseItemId("$_playlistPrefix$id");
  static BaseItemId genre(String name) =>
      BaseItemId("$_genrePrefix${base64Url.encode(utf8.encode(name)).replaceAll("=", "")}");
  static BaseItemId library(String id) => BaseItemId("$_libraryPrefix$id");

  static SubsonicRef parse(String id) {
    if (id.startsWith(_albumPrefix)) {
      return (kind: SubsonicItemKind.album, id: id.substring(_albumPrefix.length));
    } else if (id.startsWith(_artistPrefix)) {
      return (kind: SubsonicItemKind.artist, id: id.substring(_artistPrefix.length));
    } else if (id.startsWith(_playlistPrefix)) {
      return (kind: SubsonicItemKind.playlist, id: id.substring(_playlistPrefix.length));
    } else if (id.startsWith(_genrePrefix)) {
      final encoded = id.substring(_genrePrefix.length);
      return (kind: SubsonicItemKind.genre, id: utf8.decode(base64Url.decode(base64Url.normalize(encoded))));
    } else if (id.startsWith(_libraryPrefix)) {
      return (kind: SubsonicItemKind.library, id: id.substring(_libraryPrefix.length));
    }
    return (kind: SubsonicItemKind.track, id: id);
  }

  /// Parses a comma-separated list of ids, as used in Jellyfin query parameters.
  static List<SubsonicRef> parseList(String? ids) =>
      ids?.split(",").where((id) => id.isNotEmpty).map(parse).toList() ?? [];

  /// Playlist entries are identified by their position, since Subsonic removes entries by index.  The track id is
  /// included so we can verify the entry before removing it, in case the playlist changed in the meantime.
  static String playlistEntry(int index, String trackId) => "$index:$trackId";

  static ({int index, String trackId})? parsePlaylistEntry(String entryId) {
    final separator = entryId.indexOf(":");
    final index = separator == -1 ? null : int.tryParse(entryId.substring(0, separator));
    if (index == null) return null;
    return (index: index, trackId: entryId.substring(separator + 1));
  }
}
