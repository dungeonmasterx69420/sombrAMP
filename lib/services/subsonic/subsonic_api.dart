import 'dart:async';
import 'dart:convert';
import 'dart:io' show HttpClient;
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart' as http_io;
import 'package:logging/logging.dart';

/// Credentials used to authenticate against a Subsonic server.
///
/// Subsonic has no sessions, so every request carries the credentials as query parameters.  [authQuery] is the
/// pre-encoded query fragment carrying them, and is what gets stored as the access token of a Subsonic user.
class SubsonicCredentials {
  const SubsonicCredentials({required this.username, required this.authQuery});

  /// Token authentication (Subsonic API 1.13.0+), which avoids storing the password.  The token is the md5 hash of
  /// the password and a random salt.  We keep using the same salt for the lifetime of the login, which every server
  /// we know of accepts (Navidrome's own web client does the same).
  factory SubsonicCredentials.token({required String username, required String password, String? salt}) {
    salt ??= _randomSalt();
    final token = md5.convert(utf8.encode(password + salt)).toString();
    return SubsonicCredentials(username: username, authQuery: "t=$token&s=$salt");
  }

  /// Legacy authentication, sending the hex-encoded password with every request.  Only used for servers or users
  /// that don't support token authentication (e.g. LDAP users), since it requires keeping the password.
  factory SubsonicCredentials.password({required String username, required String password}) {
    final hexPassword = utf8.encode(password).map((byte) => byte.toRadixString(16).padLeft(2, "0")).join();
    return SubsonicCredentials(username: username, authQuery: "p=enc:$hexPassword");
  }

  final String username;

  /// Either `t=<token>&s=<salt>` or `p=enc:<hex password>`.  Only contains characters that are valid as-is in a URL
  /// query, so it can be used verbatim, and censored verbatim in logs.
  final String authQuery;

  static String _randomSalt() {
    final random = Random.secure();
    return List.generate(16, (_) => random.nextInt(16).toRadixString(16)).join();
  }
}

/// A Subsonic server, plus the credentials to talk to it.
class SubsonicServer {
  const SubsonicServer({required this.baseUrl, required this.credentials});

  final Uri baseUrl;
  final SubsonicCredentials credentials;
}

/// Error returned by a Subsonic server in its `subsonic-response` envelope.
class SubsonicException implements Exception {
  const SubsonicException(this.code, this.message);

  final int code;
  final String message;

  static const genericError = 0;
  static const missingParameter = 10;
  static const clientTooOld = 20;
  static const serverTooOld = 30;
  static const wrongCredentials = 40;
  static const tokenAuthNotSupported = 41;
  static const notAuthorized = 50;
  static const notFound = 70;

  @override
  String toString() => "Subsonic error $code: $message";
}

/// What a server tells us about itself in every response.
class SubsonicServerInfo {
  const SubsonicServerInfo({required this.apiVersion, this.type, this.serverVersion, this.openSubsonic = false});

  factory SubsonicServerInfo.fromResponse(Map<String, dynamic> response) => SubsonicServerInfo(
    apiVersion: response["version"] as String? ?? "",
    type: response["type"] as String?,
    serverVersion: response["serverVersion"] as String?,
    openSubsonic: response["openSubsonic"] as bool? ?? false,
  );

  /// The Subsonic API version, like "1.16.1"
  final String apiVersion;

  /// The server software, like "navidrome".  Only provided by OpenSubsonic servers.
  final String? type;

  /// The version of the server software.  Only provided by OpenSubsonic servers.
  final String? serverVersion;

  final bool openSubsonic;

  /// A human-readable name for the server software.
  String get displayName {
    final type = this.type;
    if (type == null || type.isEmpty) {
      return "Subsonic";
    }
    return type[0].toUpperCase() + type.substring(1);
  }
}

/// A thin client for the Subsonic REST API (http://www.subsonic.org/pages/api.jsp), including the OpenSubsonic
/// extensions (https://opensubsonic.netlify.app).  All methods return the raw JSON of the response, conversion into
/// Finamp's models happens in [SubsonicMapper].
class SubsonicApi {
  SubsonicApi({http.Client? httpClient})
    : _httpClient = httpClient ?? http_io.IOClient(HttpClient()..connectionTimeout = const Duration(seconds: 10));

  static final _logger = Logger("SubsonicApi");

  /// The API version we're written against.  1.16.1 is the last version of the original Subsonic API, and is what
  /// OpenSubsonic servers like Navidrome implement.
  static const apiVersion = "1.16.1";
  static const clientName = "Finamp";

  /// Maximum page size the API allows for list endpoints
  static const maxPageSize = 500;

  final http.Client _httpClient;

  /// Builds a URL for [endpoint].  Parameters with a null value are skipped, and iterable values are repeated, which
  /// is how Subsonic expects lists.
  static Uri buildUri(SubsonicServer server, String endpoint, [Map<String, Object?> parameters = const {}]) {
    final query = StringBuffer()
      ..write("u=${Uri.encodeQueryComponent(server.credentials.username)}")
      ..write("&${server.credentials.authQuery}")
      ..write("&v=$apiVersion&c=$clientName&f=json");
    void writeParameter(String key, Object value) {
      query.write("&$key=${Uri.encodeQueryComponent(value.toString())}");
    }

    for (final MapEntry(:key, :value) in parameters.entries) {
      if (value == null) continue;
      if (value is Iterable<Object?>) {
        for (final element in value.nonNulls) {
          writeParameter(key, element);
        }
      } else {
        writeParameter(key, value);
      }
    }
    return server.baseUrl.replace(
      pathSegments: [...server.baseUrl.pathSegments.where((segment) => segment.isNotEmpty), "rest", "$endpoint.view"],
      query: query.toString(),
    );
  }

  /// Sends a request and returns the contents of the `subsonic-response` envelope, throwing a [SubsonicException] if
  /// the server reports a failure.
  Future<Map<String, dynamic>> request(
    SubsonicServer server,
    String endpoint, [
    Map<String, Object?> parameters = const {},
  ]) async {
    final uri = buildUri(server, endpoint, parameters);
    _logger.finer("GET $endpoint ${parameters.isEmpty ? "" : parameters}");
    final http.Response response;
    try {
      response = await _httpClient.get(uri);
    } on http.ClientException catch (e) {
      // The URL contains the credentials, which must not end up in error messages or logs
      throw http.ClientException(e.message, redact(uri));
    }
    return parseResponse(response);
  }

  /// Removes the query, and with it the credentials, from a Subsonic URL.
  static Uri redact(Uri uri) =>
      Uri(scheme: uri.scheme, host: uri.host, port: uri.hasPort ? uri.port : null, path: uri.path);

  /// Unwraps the `subsonic-response` envelope of [response].
  static Map<String, dynamic> parseResponse(http.Response response) {
    Map<String, dynamic>? envelope;
    try {
      final body = jsonDecode(utf8.decode(response.bodyBytes));
      if (body is Map<String, dynamic>) {
        envelope = body["subsonic-response"] as Map<String, dynamic>?;
      }
    } on FormatException {
      envelope = null;
    }
    if (envelope == null) {
      final url = response.request?.url;
      throw http.ClientException(
        "Server did not return a Subsonic response (HTTP ${response.statusCode})",
        url == null ? null : redact(url),
      );
    }
    if (envelope["status"] != "ok") {
      final error = envelope["error"] as Map<String, dynamic>?;
      throw SubsonicException(
        (error?["code"] as num?)?.toInt() ?? SubsonicException.genericError,
        error?["message"] as String? ?? "Unknown error",
      );
    }
    return envelope;
  }

  /// Checks whether [baseUrl] points to a Subsonic server, without needing credentials.  Returns null if it doesn't.
  Future<SubsonicServerInfo?> probe(Uri baseUrl) async {
    final uri = baseUrl.replace(
      pathSegments: [...baseUrl.pathSegments.where((segment) => segment.isNotEmpty), "rest", "ping.view"],
      queryParameters: {"v": apiVersion, "c": clientName, "f": "json"},
    );
    final response = await _httpClient.get(uri);
    try {
      final body = jsonDecode(utf8.decode(response.bodyBytes));
      if (body is Map<String, dynamic> && body["subsonic-response"] is Map<String, dynamic>) {
        // An unauthenticated ping fails with a "missing parameter" or "wrong credentials" error, but still tells us
        // we're talking to a Subsonic server.
        return SubsonicServerInfo.fromResponse(body["subsonic-response"] as Map<String, dynamic>);
      }
    } on FormatException {
      // Not JSON, so not a Subsonic server
    }
    return null;
  }

  void close() => _httpClient.close();

  // System

  Future<SubsonicServerInfo> ping(SubsonicServer server) async =>
      SubsonicServerInfo.fromResponse(await request(server, "ping"));

  /// The OpenSubsonic extensions supported by the server, by name.  Empty for plain Subsonic servers.
  Future<Set<String>> getOpenSubsonicExtensions(SubsonicServer server) async {
    try {
      final response = await request(server, "getOpenSubsonicExtensions");
      return asList(response["openSubsonicExtensions"]).map((extension) => extension["name"] as String).toSet();
    } on SubsonicException {
      return {};
    }
  }

  // Browsing

  Future<List<Map<String, dynamic>>> getMusicFolders(SubsonicServer server) async {
    final response = await request(server, "getMusicFolders");
    return asList(asMap(response["musicFolders"])?["musicFolder"]);
  }

  /// All artists in the library, flattened out of the alphabetical index the API groups them in.
  Future<List<Map<String, dynamic>>> getArtists(SubsonicServer server, {String? musicFolderId}) async {
    final response = await request(server, "getArtists", {"musicFolderId": musicFolderId});
    return asList(asMap(response["artists"])?["index"]).expand((index) => asList(index["artist"])).toList();
  }

  /// An artist, including its albums in "album"
  Future<Map<String, dynamic>> getArtist(SubsonicServer server, String id) async =>
      asMap((await request(server, "getArtist", {"id": id}))["artist"])!;

  /// An album, including its tracks in "song"
  Future<Map<String, dynamic>> getAlbum(SubsonicServer server, String id) async =>
      asMap((await request(server, "getAlbum", {"id": id}))["album"])!;

  Future<Map<String, dynamic>> getSong(SubsonicServer server, String id) async =>
      asMap((await request(server, "getSong", {"id": id}))["song"])!;

  Future<List<Map<String, dynamic>>> getGenres(SubsonicServer server) async {
    final response = await request(server, "getGenres");
    return asList(asMap(response["genres"])?["genre"]);
  }

  Future<Map<String, dynamic>?> getArtistInfo2(SubsonicServer server, String id) async =>
      asMap((await request(server, "getArtistInfo2", {"id": id}))["artistInfo2"]);

  Future<Map<String, dynamic>?> getAlbumInfo2(SubsonicServer server, String id) async =>
      asMap((await request(server, "getAlbumInfo2", {"id": id}))["albumInfo"]);

  // Lists

  /// A page of albums.  [type] is one of random, newest, highest, frequent, recent, alphabeticalByName,
  /// alphabeticalByArtist, starred, byYear or byGenre.
  Future<List<Map<String, dynamic>>> getAlbumList2(
    SubsonicServer server, {
    required String type,
    int size = 10,
    int offset = 0,
    int? fromYear,
    int? toYear,
    String? genre,
    String? musicFolderId,
  }) async {
    final response = await request(server, "getAlbumList2", {
      "type": type,
      "size": size,
      "offset": offset,
      "fromYear": fromYear,
      "toYear": toYear,
      "genre": genre,
      "musicFolderId": musicFolderId,
    });
    return asList(asMap(response["albumList2"])?["album"]);
  }

  Future<List<Map<String, dynamic>>> getRandomSongs(
    SubsonicServer server, {
    int size = 10,
    String? genre,
    String? musicFolderId,
  }) async {
    final response = await request(server, "getRandomSongs", {
      "size": size,
      "genre": genre,
      "musicFolderId": musicFolderId,
    });
    return asList(asMap(response["randomSongs"])?["song"]);
  }

  Future<List<Map<String, dynamic>>> getSongsByGenre(
    SubsonicServer server, {
    required String genre,
    int count = 10,
    int offset = 0,
    String? musicFolderId,
  }) async {
    final response = await request(server, "getSongsByGenre", {
      "genre": genre,
      "count": count,
      "offset": offset,
      "musicFolderId": musicFolderId,
    });
    return asList(asMap(response["songsByGenre"])?["song"]);
  }

  /// The starred artists, albums and songs, in "artist", "album" and "song".
  Future<Map<String, dynamic>> getStarred2(SubsonicServer server, {String? musicFolderId}) async =>
      asMap((await request(server, "getStarred2", {"musicFolderId": musicFolderId}))["starred2"]) ?? {};

  /// Searches artists, albums and songs, returned in "artist", "album" and "song".  Most servers, including Navidrome,
  /// return everything for an empty [query], which is how we list all tracks.
  Future<Map<String, dynamic>> search3(
    SubsonicServer server, {
    required String query,
    int artistCount = 0,
    int artistOffset = 0,
    int albumCount = 0,
    int albumOffset = 0,
    int songCount = 0,
    int songOffset = 0,
    String? musicFolderId,
  }) async {
    final response = await request(server, "search3", {
      "query": query,
      "artistCount": artistCount,
      "artistOffset": artistOffset,
      "albumCount": albumCount,
      "albumOffset": albumOffset,
      "songCount": songCount,
      "songOffset": songOffset,
      "musicFolderId": musicFolderId,
    });
    return asMap(response["searchResult3"]) ?? {};
  }

  /// Songs similar to the given artist, album or song.
  Future<List<Map<String, dynamic>>> getSimilarSongs(SubsonicServer server, String id, {int count = 50}) async {
    final response = await request(server, "getSimilarSongs", {"id": id, "count": count});
    return asList(asMap(response["similarSongs"])?["song"]);
  }

  /// Songs by the given artist and similar artists.
  Future<List<Map<String, dynamic>>> getSimilarSongs2(SubsonicServer server, String artistId, {int count = 50}) async {
    final response = await request(server, "getSimilarSongs2", {"id": artistId, "count": count});
    return asList(asMap(response["similarSongs2"])?["song"]);
  }

  Future<List<Map<String, dynamic>>> getTopSongs(SubsonicServer server, String artistName, {int count = 50}) async {
    final response = await request(server, "getTopSongs", {"artist": artistName, "count": count});
    return asList(asMap(response["topSongs"])?["song"]);
  }

  // Playlists

  Future<List<Map<String, dynamic>>> getPlaylists(SubsonicServer server) async {
    final response = await request(server, "getPlaylists");
    return asList(asMap(response["playlists"])?["playlist"]);
  }

  /// A playlist, including its tracks in "entry"
  Future<Map<String, dynamic>> getPlaylist(SubsonicServer server, String id) async =>
      asMap((await request(server, "getPlaylist", {"id": id}))["playlist"])!;

  /// Creates a playlist, returning it if the server supports that (API 1.14.0+).  If [playlistId] is given, the
  /// tracks of that playlist are replaced instead.
  Future<Map<String, dynamic>?> createPlaylist(
    SubsonicServer server, {
    String? name,
    String? playlistId,
    List<String> songIds = const [],
  }) async {
    final response = await request(server, "createPlaylist", {
      "name": name,
      "playlistId": playlistId,
      "songId": songIds,
    });
    return asMap(response["playlist"]);
  }

  Future<void> updatePlaylist(
    SubsonicServer server, {
    required String playlistId,
    String? name,
    String? comment,
    bool? public,
    List<String> songIdsToAdd = const [],
    List<int> songIndexesToRemove = const [],
  }) async {
    await request(server, "updatePlaylist", {
      "playlistId": playlistId,
      "name": name,
      "comment": comment,
      "public": public,
      "songIdToAdd": songIdsToAdd,
      "songIndexToRemove": songIndexesToRemove,
    });
  }

  Future<void> deletePlaylist(SubsonicServer server, String id) async {
    await request(server, "deletePlaylist", {"id": id});
  }

  // Annotation

  Future<void> star(SubsonicServer server, {String? id, String? albumId, String? artistId}) async {
    await request(server, "star", {"id": id, "albumId": albumId, "artistId": artistId});
  }

  Future<void> unstar(SubsonicServer server, {String? id, String? albumId, String? artistId}) async {
    await request(server, "unstar", {"id": id, "albumId": albumId, "artistId": artistId});
  }

  /// Reports a song as now playing ([submission] false) or as played ([submission] true).
  Future<void> scrobble(SubsonicServer server, String id, {DateTime? time, bool submission = true}) async {
    await request(server, "scrobble", {"id": id, "time": time?.millisecondsSinceEpoch, "submission": submission});
  }

  // Lyrics

  /// Lyrics for a song, using the OpenSubsonic songLyrics extension.  Returns the "structuredLyrics" list.
  Future<List<Map<String, dynamic>>> getLyricsBySongId(SubsonicServer server, String id) async {
    final response = await request(server, "getLyricsBySongId", {"id": id});
    return asList(asMap(response["lyricsList"])?["structuredLyrics"]);
  }

  /// Unsynced lyrics, looked up by artist and title.  Supported by all Subsonic servers.
  Future<Map<String, dynamic>?> getLyrics(SubsonicServer server, {String? artist, String? title}) async =>
      asMap((await request(server, "getLyrics", {"artist": artist, "title": title}))["lyrics"]);

  // User

  Future<Map<String, dynamic>?> getUser(SubsonicServer server, String username) async =>
      asMap((await request(server, "getUser", {"username": username}))["user"]);

  // Media

  /// The stream format that disables transcoding, returning the original file
  static const originalFormat = "raw";

  /// URL to stream a song.  If [format] is given, the server transcodes the song.  [maxBitRate] is in kbps.
  static Uri streamUri(SubsonicServer server, String id, {String? format, int? maxBitRate}) {
    final transcoding = format != null && format != originalFormat;
    return buildUri(server, "stream", {
      "id": id,
      "format": format,
      "maxBitRate": maxBitRate,
      // Lets the player know the length of transcoded streams, which is needed for seeking
      if (transcoding) "estimateContentLength": true,
    });
  }

  /// URL to download the original file of a song.
  static Uri downloadUri(SubsonicServer server, String id) => buildUri(server, "download", {"id": id});

  /// URL of a cover art image.  [size] is the maximum width/height in pixels.
  static Uri coverArtUri(SubsonicServer server, String coverArtId, {int? size}) =>
      buildUri(server, "getCoverArt", {"id": coverArtId, "size": size});

  // JSON helpers.  The original Subsonic API's JSON output was auto-generated from XML, so a list with a single
  // element may be returned as a plain object.

  static List<Map<String, dynamic>> asList(Object? value) => switch (value) {
    List<dynamic> list => list.whereType<Map<String, dynamic>>().toList(),
    Map<String, dynamic> map => [map],
    _ => [],
  };

  static Map<String, dynamic>? asMap(Object? value) => value is Map<String, dynamic> ? value : null;
}
