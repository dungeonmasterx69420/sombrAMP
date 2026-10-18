import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:chopper/chopper.dart';
import 'package:collection/collection.dart';
import 'package:crypto/crypto.dart';
import 'package:finamp/models/finamp_models.dart';
import 'package:finamp/models/jellyfin_models.dart';
import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';
import 'package:uuid/uuid.dart';

import '../jellyfin_api.dart';
import 'lrclib_lyrics.dart';
import 'subsonic_api.dart';
import 'subsonic_ids.dart';
import 'subsonic_layout_playlist.dart';
import 'subsonic_library.dart';
import 'subsonic_mapper.dart';

extension SubsonicFinampUser on FinampUser {
  /// The credentials of a Subsonic user.  Subsonic users are identified by their username, which is stored as their
  /// id, and their access token is the authentication query (see [SubsonicCredentials.authQuery]).
  SubsonicCredentials? get subsonicCredentials =>
      isSubsonic ? SubsonicCredentials(username: id, authQuery: accessToken) : null;

  /// The server of a Subsonic user.  Uses the active address, or the public address if [forcePublicAddress] is set.
  SubsonicServer? subsonicServer({bool forcePublicAddress = false}) {
    final credentials = subsonicCredentials;
    if (credentials == null) return null;
    return SubsonicServer(baseUrl: Uri.parse(forcePublicAddress ? publicAddress : baseURL), credentials: credentials);
  }
}

/// Thrown for features that Subsonic servers don't offer.
class SubsonicUnsupportedException implements Exception {
  const SubsonicUnsupportedException(this.feature);

  final String feature;

  @override
  String toString() => "$feature isn't supported by Subsonic servers";
}

/// Implements the Jellyfin API used by Finamp on top of a Subsonic server (e.g. Navidrome).
///
/// Every request is translated into Subsonic API calls, and the responses are converted into the JSON a Jellyfin
/// server would have returned, so the rest of Finamp can treat Subsonic servers just like Jellyfin servers.
class SubsonicJellyfinApi implements JellyfinApi {
  SubsonicJellyfinApi({
    required Uri Function() baseUrl,
    required SubsonicCredentials? Function() credentials,
    SubsonicApi? api,
    this.lookUpLyricsOnline,
    LrclibLyrics? onlineLyrics,
  }) : _baseUrl = baseUrl,
       _credentials = credentials,
       _api = api ?? SubsonicApi(),
       _onlineLyrics = onlineLyrics ?? LrclibLyrics() {
    library = SubsonicLibrary(_api);
  }

  /// Whether lyrics the server doesn't have are looked up on LRCLIB.  Never, if not given.
  final bool Function()? lookUpLyricsOnline;
  final LrclibLyrics _onlineLyrics;

  static final _logger = Logger("SubsonicJellyfinApi");

  /// Maximum number of tracks added or removed per request, to keep URLs short enough for any server or proxy.
  static const _playlistBatchSize = 50;

  final Uri Function() _baseUrl;
  final SubsonicCredentials? Function() _credentials;
  final SubsonicApi _api;
  late final SubsonicLibrary library;

  /// Recently fetched lyrics, so checking for lyrics and then showing them doesn't fetch them twice.
  final Map<String, Future<LyricDto?>> _lyrics = {};

  SubsonicServer get server {
    final credentials = _credentials();
    if (credentials == null) {
      throw StateError("Not logged in to a Subsonic server");
    }
    return SubsonicServer(baseUrl: _baseUrl(), credentials: credentials);
  }

  /// A stable id for the server at [baseUrl], since Subsonic servers don't have one.
  static String serverIdFor(Uri baseUrl) => md5.convert(utf8.encode(baseUrl.toString())).toString();

  @override
  ChopperClient get client => throw UnsupportedError("Subsonic servers aren't accessed through Chopper");

  @override
  set client(ChopperClient client) {}

  @override
  Type get definitionType => JellyfinApi;

  // Server & authentication

  @override
  Future<dynamic> getPublicServerInfo() async {
    final baseUrl = _baseUrl();
    final info = await publicServerInfoFor(baseUrl);
    if (info == null) {
      throw http.ClientException("Not a Subsonic server", baseUrl);
    }
    return info.toJson();
  }

  /// Checks whether there's a Subsonic server at [baseUrl], and describes it like a Jellyfin server would.  Doesn't
  /// need credentials.
  Future<PublicSystemInfoResult?> publicServerInfoFor(Uri baseUrl) async {
    final info = await _api.probe(baseUrl);
    if (info == null) {
      return null;
    }
    return PublicSystemInfoResult(
      serverName: info.displayName,
      version: info.serverVersion ?? info.apiVersion,
      productName: "${info.displayName} (Subsonic API ${info.apiVersion})",
      id: serverIdFor(baseUrl),
      localAddress: baseUrl.toString(),
      startupWizardCompleted: true,
    );
  }

  /// Whether a Subsonic server responds at [baseUrl].
  Future<bool> isReachable(Uri baseUrl) async => await _api.probe(baseUrl) != null;

  /// Subsonic servers don't list their users publicly.
  @override
  Future<dynamic> getPublicUsers() async => <dynamic>[];

  @override
  Future<dynamic> getQuickConnectState() async => false;

  @override
  Future<dynamic> initiateQuickConnect() => throw const SubsonicUnsupportedException("Quick Connect");

  @override
  Future<dynamic> updateQuickConnect({required String secret}) =>
      throw const SubsonicUnsupportedException("Quick Connect");

  @override
  Future<Response<dynamic>> authorizeQuickConnect({required String code, String? userId}) =>
      throw const SubsonicUnsupportedException("Quick Connect");

  @override
  Future<dynamic> authenticateWithQuickConnect(Map<String, String> quickConnectInfo) =>
      throw const SubsonicUnsupportedException("Quick Connect");

  /// Verifies the credentials with a ping.  Token authentication is preferred, since it means we don't have to store
  /// the password, but some servers or users (e.g. LDAP users) only support password authentication.
  @override
  Future<dynamic> authenticateViaName(Map<String, String> usernameAndPassword) async {
    final baseUrl = _baseUrl();
    final username = usernameAndPassword["Username"] ?? "";
    final password = usernameAndPassword["Pw"] ?? "";
    var credentials = SubsonicCredentials.token(username: username, password: password);
    try {
      await _api.ping(SubsonicServer(baseUrl: baseUrl, credentials: credentials));
    } on SubsonicException catch (e) {
      if (![
        SubsonicException.tokenAuthNotSupported,
        SubsonicException.wrongCredentials,
        SubsonicException.serverTooOld,
      ].contains(e.code)) {
        rethrow;
      }
      _logger.info("Token authentication failed ($e), trying password authentication");
      credentials = SubsonicCredentials.password(username: username, password: password);
      await _api.ping(SubsonicServer(baseUrl: baseUrl, credentials: credentials));
    }
    final serverId = serverIdFor(baseUrl);
    return AuthenticationResult(
      user: SubsonicMapper.user(username, serverId: serverId),
      accessToken: credentials.authQuery,
      serverId: serverId,
    ).toJson();
  }

  /// Subsonic has no sessions, so there's nothing to log out of.
  @override
  Future<Response<dynamic>> logout() async => _emptyResponse();

  @override
  Future<Response<dynamic>> pingServer() async {
    await _api.ping(server);
    return _emptyResponse(statusCode: 200);
  }

  @override
  Future<dynamic> getDisplayPreferences({
    required String displayPreferencesId,
    required String userId,
    required String clientName,
  }) => throw const SubsonicUnsupportedException("Display preferences");

  @override
  Future<Response<dynamic>> updateDisplayPreferences({
    required String displayPreferencesId,
    required String userId,
    required String clientName,
    required Map<String, dynamic> displayPreferences,
  }) => throw const SubsonicUnsupportedException("Display preferences");

  @override
  Future<dynamic> updateCapabilities({
    required String playableMediaTypes,
    required String supportedCommands,
    required bool supportsMediaControl,
    required bool supportsPersistentIdentifier,
  }) async => "";

  @override
  Future<dynamic> updateCapabilitiesFull(ClientCapabilities clientCapabilities) async => "";

  // Users

  @override
  Future<dynamic> getUser() => getUserById(server.credentials.username);

  @override
  Future<dynamic> getUserById(String id) async {
    final server = this.server;
    SubsonicJson? user;
    try {
      user = await _api.getUser(server, id);
    } on SubsonicException catch (e) {
      // Servers may only allow admins to look up users
      _logger.fine("Couldn't fetch user $id: $e");
    }
    return SubsonicMapper.user(id, user: user, serverId: serverIdFor(server.baseUrl)).toJson();
  }

  @override
  Future<dynamic> getViews(String id) async {
    final folders = await library.musicFolders(server);
    return _queryResultJson(folders.map(SubsonicMapper.library).toList());
  }

  // Items

  @override
  Future<dynamic> getItems({
    required String userId,
    String? includeItemTypes,
    BaseItemId? parentId,
    String? albumArtistIds,
    String? artistIds,
    String? contributingArtistIds,
    String? albumIds,
    String? genreIds,
    String? ids,
    bool? recursive,
    String? sortBy,
    String? sortOrder,
    String? fields = defaultFields,
    String? searchTerm,
    String? filters,
    bool? isFavorite,
    String? excludeItemIds,
    int? startIndex,
    int? limit,
    bool? collapseMultiDiscAlbums,
    String? nameStartsWith,
    String? nameStartsWithOrGreater,
    String? nameLessThan,
  }) async {
    final result = await library.query(
      server,
      SubsonicItemQuery(
        includeItemTypes: includeItemTypes,
        parentId: parentId?.raw,
        albumArtistIds: albumArtistIds,
        artistIds: [artistIds, contributingArtistIds].nonNulls.join(","),
        albumIds: albumIds,
        genreIds: genreIds,
        ids: ids,
        recursive: recursive,
        sortBy: sortBy,
        sortOrder: sortOrder,
        searchTerm: searchTerm,
        filters: filters,
        isFavorite: isFavorite,
        excludeItemIds: excludeItemIds,
        startIndex: startIndex,
        limit: limit,
        nameStartsWith: nameStartsWith,
        nameStartsWithOrGreater: nameStartsWithOrGreater,
        nameLessThan: nameLessThan,
      ),
    );
    return _queryResultJson(result.items ?? [], total: result.totalRecordCount, startIndex: result.startIndex);
  }

  @override
  Future<dynamic> getArtists({
    BaseItemId? parentId,
    String? sortBy,
    String? sortOrder,
    String? fields = defaultFields,
    String? searchTerm,
    String? filters,
    String? genreIds,
    int? startIndex,
    int? limit,
    bool? isFavorite,
    String? nameStartsWith,
    String? nameLessThan,
  }) => getItems(
    userId: server.credentials.username,
    includeItemTypes: "MusicArtist",
    parentId: parentId,
    sortBy: sortBy,
    sortOrder: sortOrder,
    searchTerm: searchTerm,
    filters: filters,
    genreIds: genreIds,
    startIndex: startIndex,
    limit: limit,
    isFavorite: isFavorite,
    nameStartsWith: nameStartsWith,
    nameLessThan: nameLessThan,
  );

  @override
  Future<dynamic> getAlbumArtists({
    String? includeItemTypes,
    BaseItemId? parentId,
    bool? recursive,
    String? sortBy,
    String? sortOrder,
    String? fields = defaultFields,
    String? searchTerm,
    bool enableUserData = true,
    String? filters,
    String? genreIds,
    int? startIndex,
    int? limit,
    required String userId,
    bool? isFavorite,
    String? nameStartsWith,
    String? nameLessThan,
  }) => getArtists(
    parentId: parentId,
    sortBy: sortBy,
    sortOrder: sortOrder,
    searchTerm: searchTerm,
    filters: filters,
    genreIds: genreIds,
    startIndex: startIndex,
    limit: limit,
    isFavorite: isFavorite,
    nameStartsWith: nameStartsWith,
    nameLessThan: nameLessThan,
  );

  @override
  Future<dynamic> getGenres({
    String? includeItemTypes,
    BaseItemId? parentId,
    String? fields = defaultFields,
    String? sortBy,
    String? sortOrder,
    bool? isFavorite,
    String? searchTerm,
    int? startIndex,
    int? limit,
    String? nameStartsWith,
    String? nameLessThan,
  }) => getItems(
    userId: server.credentials.username,
    includeItemTypes: "MusicGenre",
    parentId: parentId,
    sortBy: sortBy,
    sortOrder: sortOrder,
    isFavorite: isFavorite,
    searchTerm: searchTerm,
    startIndex: startIndex,
    limit: limit,
    nameStartsWith: nameStartsWith,
    nameLessThan: nameLessThan,
  );

  @override
  Future<dynamic> getLatestItems({
    required String userId,
    String? includeItemTypes,
    BaseItemId? parentId,
    String? fields = defaultFields,
    int? limit,
    bool? groupItems,
  }) async {
    final parent = parentId == null ? null : SubsonicIds.parse(parentId.raw);
    final albums = await _api.getAlbumList2(
      server,
      type: "newest",
      size: min(limit ?? 20, SubsonicApi.maxPageSize),
      musicFolderId: parent?.kind == SubsonicItemKind.library ? parent!.id : null,
    );
    return albums.map((album) => _itemJson(SubsonicMapper.album(album))).toList();
  }

  @override
  Future<dynamic> getItemById({required String userId, required BaseItemId itemId}) async =>
      _itemJson(await library.itemById(server, SubsonicIds.parse(itemId.raw)));

  @override
  Future<dynamic> getInstantMix({
    required BaseItemId id,
    required String userId,
    required int limit,
    bool? enableImages = true,
    List<String>? enableImageTypes = const ["Primary", "Disc", "Thumb", "Art"],
  }) async => _queryResultJson(await _instantMix(SubsonicIds.parse(id.raw), limit));

  Future<List<BaseItemDto>> _instantMix(SubsonicRef seed, int limit) async {
    final server = this.server;
    final count = min(limit, SubsonicApi.maxPageSize);
    var songs = <SubsonicJson>[];
    var genres = <String>[];
    SubsonicJson? seedSong;
    try {
      switch (seed.kind) {
        case SubsonicItemKind.track:
          seedSong = await _api.getSong(server, seed.id);
          genres = SubsonicMapper.track(seedSong).genres ?? [];
          songs = await _api.getSimilarSongs(server, seed.id, count: count);
        case SubsonicItemKind.album:
          genres = SubsonicMapper.album(await library.albumDetail(server, seed.id)).genres ?? [];
          songs = await _api.getSimilarSongs(server, seed.id, count: count);
        case SubsonicItemKind.artist:
          songs = await _api.getSimilarSongs2(server, seed.id, count: count);
          if (songs.isEmpty) {
            final artist = await library.artistDetail(server, seed.id);
            genres = SubsonicApi.asList(
              artist["album"],
            ).expand((album) => SubsonicMapper.album(album).genres ?? <String>[]).toSet().toList();
          }
        case SubsonicItemKind.genre:
          genres = [seed.id];
        case SubsonicItemKind.playlist:
          songs = SubsonicApi.asList((await _api.getPlaylist(server, seed.id))["entry"])..shuffle();
        case SubsonicItemKind.library:
          break;
      }
    } on SubsonicException catch (e) {
      // Similar songs rely on external services like Last.fm, which might not be configured
      _logger.info("Couldn't get similar songs for ${seed.kind.name} ${seed.id}: $e");
    }
    // Fall back to random tracks of the same genre, or random tracks from the whole library
    for (final genre in genres) {
      if (songs.length >= count) break;
      songs.addAll(await _api.getRandomSongs(server, size: count, genre: genre));
    }
    if (songs.isEmpty) {
      songs = await _api.getRandomSongs(server, size: count);
    }
    // Start with the seed track, like Jellyfin does
    final mix = seedSong == null ? songs : [seedSong, ...songs];
    final seen = <String>{};
    return mix.where((song) => seen.add(song["id"] as String)).take(limit).map(SubsonicMapper.track).toList();
  }

  /// Subsonic has no similar albums, so use albums of the same genre.
  @override
  Future<dynamic> getSimilarAlbums({
    required BaseItemId id,
    String? userId,
    List<String>? excludeArtistIds,
    int? limit,
    List<String>? fields,
  }) async {
    final server = this.server;
    final album = SubsonicMapper.album(await library.albumDetail(server, SubsonicIds.parse(id.raw).id));
    final genre = album.genres?.firstOrNull;
    var candidates = genre == null
        ? <SubsonicJson>[]
        : await _api.getAlbumList2(server, type: "byGenre", genre: genre, size: SubsonicApi.maxPageSize);
    if (candidates.length < 2) {
      candidates = await _api.getAlbumList2(server, type: "random", size: limit ?? 20);
    }
    final excludedArtists = excludeArtistIds?.toSet() ?? {};
    final similar = candidates
        .map(SubsonicMapper.album)
        .where(
          (candidate) =>
              candidate.id != album.id &&
              !(candidate.albumArtists?.any((artist) => excludedArtists.contains(artist.id.raw)) ?? false),
        )
        .toList();
    return _queryResultJson((similar..shuffle()).take(limit ?? similar.length).toList());
  }

  @override
  Future<dynamic> deleteItem(BaseItemId id) async {
    final ref = SubsonicIds.parse(id.raw);
    if (ref.kind != SubsonicItemKind.playlist) {
      throw const SubsonicUnsupportedException("Deleting items other than playlists");
    }
    await _api.deletePlaylist(server, ref.id);
    library.invalidatePlaylists();
    return "";
  }

  @override
  Future<dynamic> updateItem({required BaseItemId itemId, required BaseItemDto newItem}) =>
      throw const SubsonicUnsupportedException("Editing metadata");

  @override
  Future<dynamic> getAlbumPrimaryImage({required BaseItemId id, String format = "webp"}) =>
      throw const SubsonicUnsupportedException("Downloading images through the API");

  @override
  Future<Response<dynamic>> setItemPrimaryImage({
    String contentType = "image/jpeg",
    required BaseItemId itemId,
    required String base64Image,
  }) => throw const SubsonicUnsupportedException("Changing images");

  // Favorites

  @override
  Future<dynamic> addFavorite({required String userId, required BaseItemId itemId}) => _setFavorite(itemId, true);

  @override
  Future<dynamic> removeFavorite({required String userId, required BaseItemId itemId}) => _setFavorite(itemId, false);

  Future<dynamic> _setFavorite(BaseItemId itemId, bool isFavorite) async {
    final ref = SubsonicIds.parse(itemId.raw);
    final setStarred = isFavorite ? _api.star : _api.unstar;
    switch (ref.kind) {
      case SubsonicItemKind.track:
        await setStarred(server, id: ref.id);
      case SubsonicItemKind.album:
        await setStarred(server, albumId: ref.id);
      case SubsonicItemKind.artist:
        await setStarred(server, artistId: ref.id);
      case SubsonicItemKind.playlist || SubsonicItemKind.genre || SubsonicItemKind.library:
        throw SubsonicUnsupportedException("Marking ${ref.kind.name}s as favorite");
    }
    library.invalidateFavorites();
    return SubsonicMapper.favoriteUserData(isFavorite: isFavorite).toJson();
  }

  // Playback

  @override
  Future<dynamic> getPlaybackInfo({required BaseItemId id, required String userId}) async {
    final song = await _api.getSong(server, SubsonicIds.parse(id.raw).id);
    final hasLyrics = await _lyricsFor(song) != null;
    return PlaybackInfoResponse(
      mediaSources: [
        SubsonicMapper.mediaSource(song, extraStreams: [if (hasLyrics) SubsonicMapper.lyricsStream()]),
      ],
      playSessionId: const Uuid().v4(),
    ).toJson();
  }

  @override
  Future<dynamic> submitPlaybackInfo({required BaseItemId id, required PlaybackInfoRequest playbackInfoRequest}) =>
      getPlaybackInfo(id: id, userId: server.credentials.username);

  /// Reports the track as "now playing".
  @override
  Future<dynamic> startPlayback(PlaybackProgressInfo playbackProgressInfo) async {
    await _api.scrobble(server, SubsonicIds.parse(playbackProgressInfo.itemId.raw).id, submission: false);
    return "";
  }

  /// Subsonic doesn't track playback progress.
  @override
  Future<dynamic> playbackStatusUpdate(PlaybackProgressInfo playbackProgressInfo) async => "";

  /// Scrobbles the track if it was played long enough, using the same rules as Last.fm: tracks longer than 30 seconds
  /// that were played for at least half their duration, or for 4 minutes.
  @override
  Future<dynamic> playbackStatusStopped(PlaybackProgressInfo playbackProgressInfo) async {
    final server = this.server;
    final id = SubsonicIds.parse(playbackProgressInfo.itemId.raw).id;
    final position = Duration(microseconds: (playbackProgressInfo.positionTicks ?? 0) ~/ 10);
    final durationTicks =
        playbackProgressInfo.item?.runTimeTicks ??
        SubsonicMapper.track(await _api.getSong(server, id)).runTimeTicks ??
        0;
    final duration = Duration(microseconds: durationTicks ~/ 10);
    if (duration > const Duration(seconds: 30) &&
        (position >= duration * 0.5 || position >= const Duration(minutes: 4))) {
      final startTicks = playbackProgressInfo.playbackStartTimeTicks;
      await _api.scrobble(
        server,
        id,
        time: startTicks == null ? null : DateTime.fromMillisecondsSinceEpoch(startTicks ~/ 10000),
      );
    }
    return "";
  }

  @override
  Future<dynamic> getLyrics({required BaseItemId itemId}) async {
    final server = this.server;
    final song = await _api.getSong(server, SubsonicIds.parse(itemId.raw).id);
    final lyrics = await _lyricsFor(song);
    if (lyrics == null) {
      throw const SubsonicException(SubsonicException.notFound, "No lyrics found");
    }
    return lyrics.toJson();
  }

  Future<LyricDto?> _lyricsFor(SubsonicJson song) {
    final id = song["id"] as String;
    if (_lyrics.length > 20) {
      _lyrics.remove(_lyrics.keys.first);
    }
    return _lyrics[id] ??= Future.sync(() async {
      try {
        final lyrics = await _serverLyricsFor(song);
        if (lyrics != null || !(lookUpLyricsOnline?.call() ?? false)) {
          return lyrics;
        }
        final artists = SubsonicApi.asList(song["artists"]);
        final durationSeconds = (song["duration"] as num?)?.toInt();
        return await _onlineLyrics.find(
          title: song["title"] as String? ?? "",
          artist: song["artist"] as String? ?? "",
          primaryArtist: artists.firstOrNull?["name"] as String?,
          album: song["album"] as String?,
          duration: durationSeconds == null ? null : Duration(seconds: durationSeconds),
        );
      } catch (e) {
        _logger.warning("Couldn't fetch lyrics for $id", e);
        // Don't remember failures, so the lyrics are fetched again next time
        unawaited(_lyrics.remove(id));
        return null;
      }
    });
  }

  Future<LyricDto?> _serverLyricsFor(SubsonicJson song) async {
    final server = this.server;
    if ((await library.openSubsonicExtensions(server)).contains("songLyrics")) {
      return SubsonicMapper.structuredLyrics(await _api.getLyricsBySongId(server, song["id"] as String));
    }
    final lyrics = await _api.getLyrics(server, artist: song["artist"] as String?, title: song["title"] as String?);
    return SubsonicMapper.plainLyrics(lyrics);
  }

  // Playlists

  @override
  Future<dynamic> getPlaylistItems({
    required BaseItemId playlistId,
    required String userId,
    String? includeItemTypes,
    BaseItemId? parentId,
    bool? recursive,
    String? fields = defaultFields,
  }) => getItems(userId: userId, parentId: playlistId, includeItemTypes: includeItemTypes);

  @override
  Future<dynamic> getPlaylist({required BaseItemId playlistId}) async {
    final playlist = await _api.getPlaylist(server, SubsonicIds.parse(playlistId.raw).id);
    return PlaylistInfo(
      openAccess: playlist["public"] as bool? ?? false,
      shares: [],
      itemIds: SubsonicApi.asList(playlist["entry"]).map((song) => SubsonicIds.track(song["id"] as String)).toList(),
    ).toJson();
  }

  @override
  Future<dynamic> getPlaylistUser({required String userId, required BaseItemId playlistId}) async {
    final playlist = await _api.getPlaylist(server, SubsonicIds.parse(playlistId.raw).id);
    final owner = playlist["owner"] as String?;
    return PlaylistUser(userId: userId, canEdit: owner == null || owner == server.credentials.username).toJson();
  }

  @override
  Future<dynamic> getPlaylistUsers({required String userId, required BaseItemId playlistId}) async {
    final playlist = await _api.getPlaylist(server, SubsonicIds.parse(playlistId.raw).id);
    final owner = playlist["owner"] as String? ?? userId;
    return PlaylistUsers(users: [PlaylistUser(userId: owner, canEdit: true)]).toJson();
  }

  @override
  Future<dynamic> createNewPlaylist({required NewPlaylist newPlaylist}) async {
    final server = this.server;
    final name = newPlaylist.name ?? "";
    final songIds = await _trackIdsOf(newPlaylist.ids ?? []);
    final created = await _api.createPlaylist(server, name: name, songIds: songIds.take(_playlistBatchSize).toList());
    var playlistId = created?["id"] as String?;
    if (playlistId == null) {
      // Servers implementing API versions before 1.14.0 don't return the new playlist
      final playlists = await _api.getPlaylists(server);
      playlistId =
          playlists
                  .where((playlist) => playlist["name"] == name)
                  .sortedBy((playlist) => playlist["created"] as String? ?? "")
                  .lastOrNull?["id"]
              as String?;
      if (playlistId == null) {
        throw const SubsonicException(SubsonicException.notFound, "Couldn't find the new playlist");
      }
    }
    await _addTracks(playlistId, songIds.skip(_playlistBatchSize).toList());
    if (newPlaylist.isPublic != null) {
      await _api.updatePlaylist(server, playlistId: playlistId, public: newPlaylist.isPublic);
    }
    library.invalidatePlaylists();
    return NewPlaylistResponse(id: SubsonicIds.playlist(playlistId)).toJson();
  }

  @override
  Future<Response<dynamic>> addItemsToPlaylist({required BaseItemId playlistId, String? ids, String? userId}) async {
    final itemIds = ids?.split(",").where((id) => id.isNotEmpty).map(BaseItemId.new).toList() ?? [];
    await _addTracks(SubsonicIds.parse(playlistId.raw).id, await _trackIdsOf(itemIds));
    library.invalidatePlaylists();
    return _emptyResponse();
  }

  @override
  Future<Response<dynamic>> removeItemsFromPlaylist({required BaseItemId playlistId, String? entryIds}) async {
    final server = this.server;
    final id = SubsonicIds.parse(playlistId.raw).id;
    final entries = SubsonicApi.asList((await _api.getPlaylist(server, id))["entry"]);
    // Entries are identified by their index when the playlist was loaded.  Make sure the index still points to the
    // same track, otherwise pick the closest occurrence of the track.
    final indexes = <int>{};
    for (final entryId in entryIds?.split(",") ?? <String>[]) {
      final entry = SubsonicIds.parsePlaylistEntry(entryId);
      if (entry == null) continue;
      final candidates = [
        for (final (index, song) in entries.indexed)
          if (song["id"] == entry.trackId && !indexes.contains(index)) index,
      ];
      final index = candidates.sortedBy<num>((index) => (index - entry.index).abs()).firstOrNull;
      if (index == null) {
        throw const SubsonicException(SubsonicException.notFound, "Track not found in playlist");
      }
      indexes.add(index);
    }
    await _removeIndexes(id, indexes);
    library.invalidatePlaylists();
    return _emptyResponse();
  }

  @override
  Future<dynamic> updatePlaylist({required BaseItemId playlistId, required NewPlaylist playlist}) async {
    final server = this.server;
    final id = SubsonicIds.parse(playlistId.raw).id;
    if (playlist.name != null || playlist.isPublic != null) {
      await _api.updatePlaylist(server, playlistId: id, name: playlist.name, public: playlist.isPublic);
    }
    final ids = playlist.ids;
    if (ids != null) {
      final songIds = await _trackIdsOf(ids);
      if (songIds.length <= _playlistBatchSize) {
        // Replace all tracks in one request
        await _api.createPlaylist(server, playlistId: id, songIds: songIds);
      } else {
        final entryCount = SubsonicApi.asList((await _api.getPlaylist(server, id))["entry"]).length;
        await _removeIndexes(id, List.generate(entryCount, (index) => index));
        await _addTracks(id, songIds);
      }
    }
    library.invalidatePlaylists();
    return "";
  }

  /// Resolves items to the tracks they contain, in order.
  Future<List<String>> _trackIdsOf(List<BaseItemId> itemIds) async {
    final server = this.server;
    final trackIds = <String>[];
    for (final itemId in itemIds) {
      final ref = SubsonicIds.parse(itemId.raw);
      switch (ref.kind) {
        case SubsonicItemKind.track:
          trackIds.add(ref.id);
        case SubsonicItemKind.album:
          final album = await library.albumDetail(server, ref.id);
          trackIds.addAll(SubsonicApi.asList(album["song"]).map((song) => song["id"] as String));
        case SubsonicItemKind.playlist:
          final playlist = await _api.getPlaylist(server, ref.id);
          trackIds.addAll(SubsonicApi.asList(playlist["entry"]).map((song) => song["id"] as String));
        case SubsonicItemKind.artist:
          final artist = await library.artistDetail(server, ref.id);
          for (final album in SubsonicApi.asList(artist["album"])) {
            final albumDetail = await library.albumDetail(server, album["id"] as String);
            trackIds.addAll(SubsonicApi.asList(albumDetail["song"]).map((song) => song["id"] as String));
          }
        case SubsonicItemKind.genre || SubsonicItemKind.library:
          throw SubsonicUnsupportedException("Adding ${ref.kind.name}s to playlists");
      }
    }
    return trackIds;
  }

  Future<void> _addTracks(String playlistId, List<String> songIds) async {
    for (final batch in songIds.slices(_playlistBatchSize)) {
      await _api.updatePlaylist(server, playlistId: playlistId, songIdsToAdd: batch);
    }
  }

  Future<void> _removeIndexes(String playlistId, Iterable<int> indexes) async {
    // Remove from the end, so the indexes of the remaining batches stay valid
    final sorted = indexes.sorted((a, b) => b.compareTo(a));
    for (final batch in sorted.slices(_playlistBatchSize)) {
      await _api.updatePlaylist(server, playlistId: playlistId, songIndexesToRemove: batch);
    }
  }

  // Layout

  /// The layout saved with the account, in the playlist that keeps it (see [SubsonicLayoutPlaylist]).
  Future<String?> loadLayout() async =>
      SubsonicLayoutPlaylist.layoutIn((await _layoutPlaylist())?["comment"] as String?);

  Future<void> saveLayout(String layout) async {
    final server = this.server;
    var playlistId = (await _layoutPlaylist())?["id"] as String?;
    if (playlistId == null) {
      final created = await _api.createPlaylist(server, name: SubsonicLayoutPlaylist.name);
      // Servers implementing API versions before 1.14.0 don't return the new playlist
      playlistId = created?["id"] as String? ?? (await _layoutPlaylist())?["id"] as String?;
      if (playlistId == null) {
        throw const SubsonicException(SubsonicException.notFound, "Couldn't find the new layout playlist");
      }
    }
    await _api.updatePlaylist(
      server,
      playlistId: playlistId,
      comment: SubsonicLayoutPlaylist.commentFor(layout),
      public: false,
    );
  }

  /// The user's playlist keeping the layout, the most recently changed one if a race created several.
  Future<Map<String, dynamic>?> _layoutPlaylist() async {
    final username = server.credentials.username;
    return (await _api.getPlaylists(server))
        .where((playlist) => SubsonicLayoutPlaylist.isOwnedBy(playlist, username: username))
        .sortedBy((playlist) => playlist["changed"] as String? ?? "")
        .lastOrNull;
  }

  // Helpers

  static Map<String, dynamic> _itemJson(BaseItemDto item) => item.toJson(setOffline: false);

  static Map<String, dynamic> _queryResultJson(List<BaseItemDto> items, {int? total, int startIndex = 0}) => {
    "Items": items.map(_itemJson).toList(),
    "TotalRecordCount": total ?? items.length,
    "StartIndex": startIndex,
  };

  static Response<dynamic> _emptyResponse({int statusCode = 204}) =>
      Response<dynamic>(http.Response("", statusCode), "");
}
