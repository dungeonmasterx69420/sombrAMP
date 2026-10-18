import 'dart:async';
import 'dart:math';

import 'package:collection/collection.dart';
import 'package:diacritic/diacritic.dart';
import 'package:finamp/models/jellyfin_models.dart';
import 'package:logging/logging.dart';

import 'subsonic_api.dart';
import 'subsonic_ids.dart';
import 'subsonic_layout_playlist.dart';
import 'subsonic_mapper.dart';

/// The parameters of a Jellyfin item query (Jellyfin's /Items endpoint) that Finamp uses.
class SubsonicItemQuery {
  SubsonicItemQuery({
    String? includeItemTypes,
    String? parentId,
    String? albumArtistIds,
    String? artistIds,
    String? albumIds,
    String? genreIds,
    String? ids,
    this.recursive,
    String? sortBy,
    String? sortOrder,
    String? searchTerm,
    String? filters,
    this.isFavorite,
    String? excludeItemIds,
    this.startIndex,
    this.limit,
    this.nameStartsWith,
    this.nameStartsWithOrGreater,
    this.nameLessThan,
  }) : types = _split(includeItemTypes).toSet(),
       parent = parentId == null || parentId.isEmpty ? null : SubsonicIds.parse(parentId),
       albumArtistIds = SubsonicIds.parseList(albumArtistIds),
       artistIds = SubsonicIds.parseList(artistIds),
       albumIds = SubsonicIds.parseList(albumIds),
       genreIds = SubsonicIds.parseList(genreIds),
       ids = SubsonicIds.parseList(ids),
       sortBy = _split(sortBy),
       sortOrders = _split(sortOrder),
       searchTerm = searchTerm == null || searchTerm.trim().isEmpty ? null : searchTerm.trim(),
       filters = _split(filters).toSet(),
       excludeItemIds = _split(excludeItemIds).toSet();

  final Set<String> types;
  final SubsonicRef? parent;
  final List<SubsonicRef> albumArtistIds;
  final List<SubsonicRef> artistIds;
  final List<SubsonicRef> albumIds;
  final List<SubsonicRef> genreIds;
  final List<SubsonicRef> ids;
  final bool? recursive;
  final List<String> sortBy;
  final List<String> sortOrders;
  final String? searchTerm;
  final Set<String> filters;
  final bool? isFavorite;
  final Set<String> excludeItemIds;
  final int? startIndex;
  final int? limit;
  final String? nameStartsWith;
  final String? nameStartsWithOrGreater;
  final String? nameLessThan;

  bool get onlyFavorites => (isFavorite ?? false) || filters.contains("IsFavorite");
  bool get isRandom => sortBy.any((key) => key.toLowerCase() == "random");
  bool get notFolders => filters.contains("IsNotFolder");

  /// The music folder (library) the query is limited to, if any.
  String? get musicFolderId => parent?.kind == SubsonicItemKind.library ? parent!.id : null;

  bool get wantsTracks => types.contains("Audio") || (types.isEmpty && notFolders);
  bool get wantsAlbums => types.contains("MusicAlbum") || (types.isEmpty && !notFolders);
  bool get wantsArtists => types.contains("MusicArtist");
  bool get wantsPlaylists => types.contains("Playlist");
  bool get wantsGenres => types.contains("MusicGenre");
  bool get wantsLibraries => types.contains("CollectionFolder");

  /// Identifies the query results regardless of paging, used to cache sorted results while scrolling.
  String get cacheKey => [
    types,
    parent,
    albumArtistIds,
    artistIds,
    albumIds,
    genreIds,
    ids,
    recursive,
    sortBy,
    sortOrders,
    searchTerm,
    filters,
    isFavorite,
    excludeItemIds,
    nameStartsWith,
    nameStartsWithOrGreater,
    nameLessThan,
  ].join("|");

  static List<String> _split(String? value) =>
      value?.split(",").map((part) => part.trim()).where((part) => part.isNotEmpty && part != "null").toList() ?? [];
}

/// Resolves Jellyfin style queries against a Subsonic server.
///
/// The Subsonic API offers far fewer ways to query a library than Jellyfin, so most queries are answered by fetching
/// the relevant items and filtering, sorting and paging them locally.  Responses are cached for a few minutes to keep
/// scrolling through large libraries fast.  Note that each isolate has its own instance, so changes made in one
/// isolate only invalidate that isolate's cache, which is why the first page of every query uses fresher data.
class SubsonicLibrary {
  SubsonicLibrary(this._api);

  static final _logger = Logger("SubsonicLibrary");

  static const _cacheDuration = Duration(minutes: 5);

  /// How old cached data may be when the first page of a query is requested, i.e. when a screen is (re)loaded
  static const _refreshAge = Duration(minutes: 1);

  /// Lists that are cheap to fetch and change through Finamp itself are only kept to combine simultaneous requests
  static const _shortCacheDuration = Duration(seconds: 5);

  /// How long the full, sorted result of a query is kept around for paging through it
  static const _queryCacheDuration = Duration(minutes: 1);

  final SubsonicApi _api;
  String? _cacheOwner;

  final _albumDetails = _Cache<String, SubsonicJson>(_cacheDuration);
  final _artistDetails = _Cache<String, SubsonicJson>(_cacheDuration);
  final _allAlbums = _Cache<String, List<BaseItemDto>>(_cacheDuration);
  final _allSongs = _Cache<String, List<BaseItemDto>>(_cacheDuration);
  final _allArtists = _Cache<String, List<SubsonicJson>>(_cacheDuration);
  final _genreAlbums = _Cache<String, List<SubsonicJson>>(_cacheDuration);
  final _genreSongs = _Cache<String, List<BaseItemDto>>(_cacheDuration);
  final _genres = _Cache<String, List<SubsonicJson>>(_cacheDuration);
  final _musicFolders = _Cache<String, List<SubsonicJson>>(_cacheDuration);
  final _playlists = _Cache<String, List<SubsonicJson>>(_shortCacheDuration);
  final _starred = _Cache<String, SubsonicJson>(_shortCacheDuration);
  final _extensions = _Cache<String, Set<String>>(const Duration(hours: 1));
  final _queryResults = _Cache<String, List<BaseItemDto>>(_queryCacheDuration);

  List<_Cache<String, Object>> get _caches => [
    _albumDetails,
    _artistDetails,
    _allAlbums,
    _allSongs,
    _allArtists,
    _genreAlbums,
    _genreSongs,
    _genres,
    _musicFolders,
    _playlists,
    _starred,
    _extensions,
    _queryResults,
  ];

  /// Drops all cached data, e.g. after something was changed on the server.
  void invalidate() {
    for (final cache in _caches) {
      cache.clear();
    }
  }

  /// Drops cached playlists, after a playlist was created or changed.
  void invalidatePlaylists() {
    _playlists.clear();
    _queryResults.clear();
  }

  /// Drops cached data containing favorite states, after an item was (un)marked as favorite.  The full lists of albums
  /// and tracks are kept, since they're expensive to load and favorite filters always check the server.
  void invalidateFavorites() {
    _starred.clear();
    _albumDetails.clear();
    _artistDetails.clear();
    _queryResults.clear();
  }

  /// Starts a request against [server], making sure cached data of a previous server or user is never used.
  _Request _request(SubsonicServer server, Duration maxAge) {
    final owner = "${server.baseUrl}|${server.credentials.username}";
    if (owner != _cacheOwner) {
      _cacheOwner = owner;
      invalidate();
    }
    return _Request(this, server, maxAge);
  }

  /// Answers a Jellyfin style item query.
  Future<QueryResult_BaseItemDto> query(SubsonicServer server, SubsonicItemQuery query) async {
    final start = query.startIndex ?? 0;
    final List<BaseItemDto> items;
    if (query.isRandom) {
      // Random results must not be cached, every request should get a new selection
      items = await _request(server, _cacheDuration).resolve(query);
    } else if (start == 0) {
      // The first page is what gets loaded when a screen is opened or refreshed, so it should reflect recent changes
      final request = _request(server, _refreshAge);
      items = await _queryResults.refresh(query.cacheKey, () => request.resolve(query));
    } else {
      final request = _request(server, _cacheDuration);
      items = await _queryResults.get(query.cacheKey, () => request.resolve(query));
    }
    final page = items.skip(start).take(query.limit ?? items.length).toList();
    return QueryResult_BaseItemDto(items: page, totalRecordCount: items.length, startIndex: start);
  }

  /// Fetches the given items, skipping ones that don't exist (anymore).  Keeps the order of [refs].
  Future<List<BaseItemDto>> itemsByIds(SubsonicServer server, List<SubsonicRef> refs) =>
      _request(server, _refreshAge).itemsByIds(refs);

  Future<BaseItemDto> itemById(SubsonicServer server, SubsonicRef ref) => _request(server, _refreshAge).itemById(ref);

  /// An album, including its tracks in "song".
  Future<SubsonicJson> albumDetail(SubsonicServer server, String id) => _request(server, _refreshAge).albumDetail(id);

  /// An artist, including its albums in "album".
  Future<SubsonicJson> artistDetail(SubsonicServer server, String id) => _request(server, _refreshAge).artistDetail(id);

  /// The tracks of a playlist, in order, identified as playlist entries.
  Future<List<BaseItemDto>> playlistTracks(SubsonicServer server, String playlistId) =>
      _request(server, _refreshAge).playlistTracks(playlistId);

  Future<List<SubsonicJson>> musicFolders(SubsonicServer server) => _request(server, _cacheDuration).musicFolders();

  Future<List<SubsonicJson>> genres(SubsonicServer server) => _request(server, _cacheDuration).genres();

  Future<Set<String>> openSubsonicExtensions(SubsonicServer server) {
    _request(server, _cacheDuration);
    return _extensions.get("", () => _api.getOpenSubsonicExtensions(server));
  }
}

/// A single request to the library, with the server to use and how old cached data may be.
class _Request {
  _Request(this._library, this.server, this.maxAge);

  final SubsonicLibrary _library;
  final SubsonicServer server;
  final Duration maxAge;

  SubsonicApi get _api => _library._api;

  Future<List<BaseItemDto>> resolve(SubsonicItemQuery query) async {
    var (items, alreadyFiltered) = await _source(query);
    if (!alreadyFiltered) {
      // Starred state in cached items may be outdated, so always check favorites against the server
      final favoriteIds = query.onlyFavorites ? await _starredIds(query.musicFolderId) : null;
      items = _filter(items, query, favoriteIds: favoriteIds);
    }
    return _sort(items, query);
  }

  /// Fetches the candidate items for [query], using the most specific source available.  Returns whether the items
  /// were already filtered completely.
  Future<(List<BaseItemDto>, bool)> _source(SubsonicItemQuery query) async {
    final musicFolderId = query.musicFolderId;
    final parent = query.parent;

    if (query.ids.isNotEmpty) {
      return (await itemsByIds(query.ids), false);
    }

    if (parent != null && parent.kind != SubsonicItemKind.library) {
      return switch (parent.kind) {
        SubsonicItemKind.album => (await _albumTracks([parent.id]), false),
        SubsonicItemKind.playlist => (await playlistTracks(parent.id), false),
        SubsonicItemKind.artist => (await _artistItems(query, albumArtistIds: [parent.id], artistIds: []), false),
        SubsonicItemKind.genre => (await _genreItems(query, parent.id), false),
        SubsonicItemKind.track || SubsonicItemKind.library => (<BaseItemDto>[], true),
      };
    }

    // Tracks directly inside a library, that aren't part of an album.  Subsonic doesn't have these.
    if (parent != null && query.recursive == false && query.types.length == 1 && query.types.contains("Audio")) {
      return (<BaseItemDto>[], true);
    }

    final albumArtistIds = _idsOfKind(query.albumArtistIds, SubsonicItemKind.artist);
    final artistIds = _idsOfKind(query.artistIds, SubsonicItemKind.artist);
    if (albumArtistIds.isNotEmpty || artistIds.isNotEmpty) {
      return (await _artistItems(query, albumArtistIds: albumArtistIds, artistIds: artistIds), false);
    }

    if (query.albumIds.isNotEmpty) {
      if (query.wantsTracks) {
        return (await _albumTracks(_idsOfKind(query.albumIds, SubsonicItemKind.album)), false);
      }
      return (await itemsByIds(query.albumIds), false);
    }

    final genres = _idsOfKind(query.genreIds, SubsonicItemKind.genre);
    if (genres.isNotEmpty) {
      return (await _genreItems(query, genres.first), false);
    }

    final searchTerm = query.searchTerm;
    if (searchTerm != null) {
      return (await _search(query, searchTerm), false);
    }

    final items = <BaseItemDto>[];
    if (query.wantsLibraries) {
      items.addAll((await musicFolders()).map(SubsonicMapper.library));
    }
    if (query.wantsAlbums) {
      if (query.onlyFavorites) {
        items.addAll(SubsonicApi.asList((await _getStarred(musicFolderId))["album"]).map(SubsonicMapper.album));
      } else {
        items.addAll(await allAlbums(musicFolderId));
      }
    }
    if (query.wantsTracks) {
      if (query.onlyFavorites) {
        items.addAll(SubsonicApi.asList((await _getStarred(musicFolderId))["song"]).map(SubsonicMapper.track));
      } else if (query.isRandom && query.filters.difference({"IsNotFolder"}).isEmpty) {
        // Random selections don't need the whole library
        final songs = await _api.getRandomSongs(
          server,
          size: min(query.limit ?? 100, SubsonicApi.maxPageSize),
          musicFolderId: musicFolderId,
        );
        items.addAll(songs.map(SubsonicMapper.track));
      } else {
        items.addAll(await allSongs(musicFolderId));
      }
    }
    if (query.wantsArtists) {
      final artists = query.onlyFavorites
          ? SubsonicApi.asList((await _getStarred(musicFolderId))["artist"])
          : await allArtists(musicFolderId);
      items.addAll(artists.map(SubsonicMapper.artist));
    }
    if (query.wantsPlaylists) {
      items.addAll(await playlists());
    }
    if (query.wantsGenres && !query.onlyFavorites) {
      // Genres can't be favorited in Subsonic, so there are never any favorite genres
      items.addAll((await this.genres()).map(SubsonicMapper.genre));
    }
    return (items, false);
  }

  Future<List<BaseItemDto>> _artistItems(
    SubsonicItemQuery query, {
    required List<String> albumArtistIds,
    required List<String> artistIds,
  }) async {
    final items = <BaseItemDto>[];
    if (query.wantsAlbums) {
      for (final artistId in albumArtistIds) {
        items.addAll((await _artistAlbums(artistId)).map(SubsonicMapper.album));
      }
      for (final artistId in artistIds) {
        items.addAll(await _performingArtistAlbums(artistId));
      }
    }
    if (query.wantsTracks) {
      for (final artistId in albumArtistIds) {
        final albums = await _artistAlbums(artistId);
        items.addAll(await _albumTracks(albums.map((album) => album["id"] as String).toList()));
      }
      for (final artistId in artistIds) {
        items.addAll((await _performingArtistSongs(artistId)).map(SubsonicMapper.track));
      }
    }
    return _distinct(items);
  }

  Future<List<BaseItemDto>> _genreItems(SubsonicItemQuery query, String genre) async {
    final musicFolderId = query.musicFolderId;
    final items = <BaseItemDto>[];
    if (query.wantsAlbums) {
      items.addAll((await _albumsOfGenre(genre, musicFolderId)).map(SubsonicMapper.album));
    }
    if (query.wantsTracks) {
      if (query.isRandom && query.limit != null) {
        final songs = await _api.getRandomSongs(
          server,
          size: min(query.limit!, SubsonicApi.maxPageSize),
          genre: genre,
          musicFolderId: musicFolderId,
        );
        items.addAll(songs.map(SubsonicMapper.track));
      } else {
        items.addAll(
          await _library._genreSongs.get("$genre|$musicFolderId", maxAge: maxAge, () async {
            final songs = await _fetchAllPages(
              (offset) => _api.getSongsByGenre(
                server,
                genre: genre,
                count: SubsonicApi.maxPageSize,
                offset: offset,
                musicFolderId: musicFolderId,
              ),
            );
            return songs.map(SubsonicMapper.track).toList();
          }),
        );
      }
    }
    if (query.wantsArtists) {
      // Subsonic can't list artists by genre, so use the artists of the genre's albums
      final artistsById = {for (final artist in await allArtists(musicFolderId)) artist["id"]: artist};
      final genreArtists = <String, SubsonicJson>{};
      for (final album in await _albumsOfGenre(genre, musicFolderId)) {
        for (final artist in SubsonicMapper.album(album).albumArtists ?? <NameIdPair>[]) {
          final artistId = SubsonicIds.parse(artist.id.raw).id;
          genreArtists[artistId] ??= artistsById[artistId] ?? {"id": artistId, "name": artist.name};
        }
      }
      items.addAll(genreArtists.values.map(SubsonicMapper.artist));
    }
    return items;
  }

  Future<List<BaseItemDto>> _search(SubsonicItemQuery query, String searchTerm) async {
    final items = <BaseItemDto>[];
    if (query.wantsAlbums || query.wantsTracks || query.wantsArtists) {
      final count = min((query.startIndex ?? 0) + (query.limit ?? 100), SubsonicApi.maxPageSize);
      final result = await _api.search3(
        server,
        query: searchTerm,
        artistCount: query.wantsArtists ? count : 0,
        albumCount: query.wantsAlbums ? count : 0,
        songCount: query.wantsTracks ? count : 0,
        musicFolderId: query.musicFolderId,
      );
      items.addAll(SubsonicApi.asList(result["artist"]).map(SubsonicMapper.artist));
      items.addAll(SubsonicApi.asList(result["album"]).map(SubsonicMapper.album));
      items.addAll(SubsonicApi.asList(result["song"]).map(SubsonicMapper.track));
    }
    if (query.wantsPlaylists) {
      items.addAll((await playlists()).where((playlist) => _matchesSearch(playlist, searchTerm)));
    }
    if (query.wantsGenres) {
      items.addAll((await genres()).map(SubsonicMapper.genre).where((genre) => _matchesSearch(genre, searchTerm)));
    }
    return items;
  }

  // Lookups

  Future<List<BaseItemDto>> itemsByIds(List<SubsonicRef> refs) async {
    final items = await _mapConcurrently(refs, (ref) async {
      try {
        return await itemById(ref);
      } on SubsonicException catch (e) {
        if (e.code == SubsonicException.notFound) {
          SubsonicLibrary._logger.fine("Item ${ref.kind.name} ${ref.id} not found on server");
          return null;
        }
        rethrow;
      }
    });
    return items.nonNulls.toList();
  }

  Future<BaseItemDto> itemById(SubsonicRef ref) async {
    switch (ref.kind) {
      case SubsonicItemKind.track:
        return SubsonicMapper.track(await _api.getSong(server, ref.id));
      case SubsonicItemKind.album:
        final album = await albumDetail(ref.id);
        return SubsonicMapper.album(album, songs: SubsonicApi.asList(album["song"]));
      case SubsonicItemKind.artist:
        final artist = await artistDetail(ref.id);
        SubsonicJson? info;
        try {
          // Servers may look up artist info on external services, so don't wait for too long
          info = await _api.getArtistInfo2(server, ref.id).timeout(const Duration(seconds: 5));
        } catch (e) {
          SubsonicLibrary._logger.fine("Couldn't fetch artist info for ${ref.id}: $e");
        }
        return SubsonicMapper.artist(artist, info: info);
      case SubsonicItemKind.playlist:
        return SubsonicMapper.playlist(await _api.getPlaylist(server, ref.id), username: server.credentials.username);
      case SubsonicItemKind.genre:
        final genre = (await genres()).firstWhereOrNull((genre) => genre["value"] == ref.id);
        return genre == null ? SubsonicMapper.genreByName(ref.id) : SubsonicMapper.genre(genre);
      case SubsonicItemKind.library:
        final folder = (await musicFolders()).firstWhereOrNull((folder) => folder["id"].toString() == ref.id);
        if (folder == null) {
          throw SubsonicException(SubsonicException.notFound, "Library ${ref.id} not found");
        }
        return SubsonicMapper.library(folder);
    }
  }

  Future<SubsonicJson> albumDetail(String id) =>
      _library._albumDetails.get(id, maxAge: maxAge, () => _api.getAlbum(server, id));

  Future<SubsonicJson> artistDetail(String id) =>
      _library._artistDetails.get(id, maxAge: maxAge, () => _api.getArtist(server, id));

  Future<List<BaseItemDto>> playlistTracks(String playlistId) async {
    final playlist = await _api.getPlaylist(server, playlistId);
    return SubsonicApi.asList(playlist["entry"])
        .mapIndexed(
          (index, song) =>
              SubsonicMapper.track(song, playlistEntryId: SubsonicIds.playlistEntry(index, song["id"] as String)),
        )
        .toList();
  }

  Future<List<SubsonicJson>> musicFolders() =>
      _library._musicFolders.get("", maxAge: maxAge, () => _api.getMusicFolders(server));

  Future<List<SubsonicJson>> genres() => _library._genres.get("", maxAge: maxAge, () => _api.getGenres(server));

  Future<List<BaseItemDto>> playlists() async {
    final playlists = await _library._playlists.get("", () => _api.getPlaylists(server));
    return playlists
        .whereNot(SubsonicLayoutPlaylist.keepsLayout)
        .map((playlist) => SubsonicMapper.playlist(playlist, username: server.credentials.username))
        .toList();
  }

  Future<SubsonicJson> _getStarred(String? musicFolderId) =>
      _library._starred.get(musicFolderId ?? "", () => _api.getStarred2(server, musicFolderId: musicFolderId));

  Future<Set<BaseItemId>> _starredIds(String? musicFolderId) async {
    final starred = await _getStarred(musicFolderId);
    return {
      ...SubsonicApi.asList(starred["artist"]).map((artist) => SubsonicIds.artist(artist["id"] as String)),
      ...SubsonicApi.asList(starred["album"]).map((album) => SubsonicIds.album(album["id"] as String)),
      ...SubsonicApi.asList(starred["song"]).map((song) => SubsonicIds.track(song["id"] as String)),
    };
  }

  Future<List<SubsonicJson>> allArtists(String? musicFolderId) => _library._allArtists.get(
    musicFolderId ?? "",
    maxAge: maxAge,
    () => _api.getArtists(server, musicFolderId: musicFolderId),
  );

  Future<List<BaseItemDto>> allAlbums(String? musicFolderId) =>
      _library._allAlbums.get(musicFolderId ?? "", maxAge: maxAge, () async {
        final albums = await _fetchAllPages(
          (offset) => _api.getAlbumList2(
            server,
            type: "alphabeticalByName",
            size: SubsonicApi.maxPageSize,
            offset: offset,
            musicFolderId: musicFolderId,
          ),
        );
        return albums.map(SubsonicMapper.album).toList();
      });

  Future<List<BaseItemDto>> allSongs(String? musicFolderId) =>
      _library._allSongs.get(musicFolderId ?? "", maxAge: maxAge, () async {
        // Most servers return everything for an empty search, which is the only way to page through all tracks
        final songs = await _fetchAllPages((offset) async {
          final result = await _api.search3(
            server,
            query: "",
            songCount: SubsonicApi.maxPageSize,
            songOffset: offset,
            musicFolderId: musicFolderId,
          );
          return SubsonicApi.asList(result["song"]);
        });
        if (songs.isNotEmpty) {
          return songs.map(SubsonicMapper.track).toList();
        }
        SubsonicLibrary._logger.info("Server returned no tracks for an empty search, collecting tracks from albums");
        final albums = await allAlbums(musicFolderId);
        return _albumTracks(albums.map((album) => SubsonicIds.parse(album.id.raw).id).toList());
      });

  Future<List<SubsonicJson>> _artistAlbums(String artistId) async =>
      SubsonicApi.asList((await artistDetail(artistId))["album"]);

  Future<List<BaseItemDto>> _albumTracks(List<String> albumIds) async {
    final albums = await _mapConcurrently(albumIds, albumDetail);
    return albums.expand((album) => SubsonicApi.asList(album["song"])).map(SubsonicMapper.track).toList();
  }

  /// Tracks the artist performs on: tracks on their own albums, plus tracks on other albums that a search finds.
  Future<List<SubsonicJson>> _performingArtistSongs(String artistId) async {
    final artist = await artistDetail(artistId);
    final albums = await _mapConcurrently(
      SubsonicApi.asList(artist["album"]),
      (album) => albumDetail(album["id"] as String),
    );
    final songs = {
      for (final song in albums.expand((album) => SubsonicApi.asList(album["song"]))) song["id"] as String: song,
    };
    final name = artist["name"] as String?;
    if (name != null && name.isNotEmpty) {
      final result = await _api.search3(server, query: name, songCount: SubsonicApi.maxPageSize);
      for (final song in SubsonicApi.asList(result["song"])) {
        songs.putIfAbsent(song["id"] as String, () => song);
      }
    }
    return songs.values.where((song) => _songHasArtist(song, artistId)).toList();
  }

  Future<List<BaseItemDto>> _performingArtistAlbums(String artistId) async {
    final albumIds = {for (final album in await _artistAlbums(artistId)) album["id"] as String};
    for (final song in await _performingArtistSongs(artistId)) {
      final albumId = song["albumId"] as String?;
      if (albumId != null) albumIds.add(albumId);
    }
    final albums = await _mapConcurrently(albumIds.toList(), albumDetail);
    return albums.map(SubsonicMapper.album).toList();
  }

  Future<List<SubsonicJson>> _albumsOfGenre(String genre, String? musicFolderId) => _library._genreAlbums.get(
    "$genre|$musicFolderId",
    maxAge: maxAge,
    () => _fetchAllPages(
      (offset) => _api.getAlbumList2(
        server,
        type: "byGenre",
        genre: genre,
        size: SubsonicApi.maxPageSize,
        offset: offset,
        musicFolderId: musicFolderId,
      ),
    ),
  );

  static List<String> _idsOfKind(List<SubsonicRef> refs, SubsonicItemKind kind) =>
      refs.where((ref) => ref.kind == kind).map((ref) => ref.id).toList();

  static bool _songHasArtist(SubsonicJson song, String artistId) {
    final artists = SubsonicApi.asList(song["artists"]);
    if (artists.isNotEmpty) {
      return artists.any((artist) => artist["id"] == artistId);
    }
    return song["artistId"] == artistId;
  }

  // Filtering and sorting

  static List<BaseItemDto> _filter(List<BaseItemDto> items, SubsonicItemQuery query, {Set<BaseItemId>? favoriteIds}) {
    final genreNames = _idsOfKind(query.genreIds, SubsonicItemKind.genre).toSet();
    final nameStartsWith = _normalize(query.nameStartsWith);
    final nameStartsWithOrGreater = _normalize(query.nameStartsWithOrGreater);
    final nameLessThan = _normalize(query.nameLessThan);
    final searchTerm = query.searchTerm;
    return items.where((item) {
      final isFavorite = favoriteIds?.contains(item.id) ?? item.userData?.isFavorite ?? false;
      if (query.types.isNotEmpty && !query.types.contains(item.type)) return false;
      if (query.onlyFavorites && !isFavorite) return false;
      if (query.isFavorite == false && isFavorite) return false;
      if (query.notFolders && (item.isFolder ?? false)) return false;
      if (query.filters.contains("IsFolder") && !(item.isFolder ?? false)) return false;
      if (query.filters.contains("IsPlayed") && !(item.userData?.played ?? false)) return false;
      if (query.filters.contains("IsUnplayed") && (item.userData?.played ?? false)) return false;
      if (query.excludeItemIds.contains(item.id.raw)) return false;
      if (genreNames.isNotEmpty &&
          !const {"MusicGenre", "MusicArtist"}.contains(item.type) &&
          !(item.genres?.any(genreNames.contains) ?? false)) {
        return false;
      }
      if (searchTerm != null && !_matchesSearch(item, searchTerm)) return false;
      final name = _nameKey(item);
      if (nameStartsWith != null && !name.startsWith(nameStartsWith)) return false;
      if (nameStartsWithOrGreater != null && name.compareTo(nameStartsWithOrGreater) < 0) return false;
      if (nameLessThan != null && name.compareTo(nameLessThan) >= 0) return false;
      return true;
    }).toList();
  }

  static List<BaseItemDto> _sort(List<BaseItemDto> items, SubsonicItemQuery query) {
    if (query.isRandom) {
      return items..shuffle();
    }
    // Sort orders apply to the sort keys at the same position, or all keys if only one order is given
    final keys = [
      for (final (index, key) in query.sortBy.indexed)
        if (_sortKeys.contains(key.toLowerCase()))
          (
            key: key.toLowerCase(),
            descending:
                (index < query.sortOrders.length ? query.sortOrders[index] : query.sortOrders.firstOrNull)
                    ?.toLowerCase()
                    .startsWith("desc") ??
                false,
          ),
    ];
    if (keys.isEmpty) {
      return items;
    }
    // Merge sort is stable, so items that compare equal keep the order the server returned them in
    mergeSort(
      items,
      compare: (a, b) {
        for (final (:key, :descending) in keys) {
          final result = _compareValues(_sortValue(a, key), _sortValue(b, key));
          if (result != 0) {
            return descending ? -result : result;
          }
        }
        return 0;
      },
    );
    return items;
  }

  static const _sortKeys = {
    "sortname",
    "name",
    "album",
    "albumartist",
    "artist",
    "datecreated",
    "dateplayed",
    "playcount",
    "premieredate",
    "productionyear",
    "communityrating",
    "criticrating",
    "runtime",
    "parentindexnumber",
    "indexnumber",
  };

  static Object? _sortValue(BaseItemDto item, String key) => switch (key) {
    "sortname" || "name" => _nameKey(item),
    "album" => _normalize(item.album),
    "albumartist" => _normalize(item.albumArtist),
    "artist" => _normalize(item.artists?.firstOrNull),
    "datecreated" => item.dateCreated,
    "dateplayed" => item.userData?.lastPlayedDate,
    "playcount" => item.userData?.playCount,
    "premieredate" => item.premiereDate,
    "productionyear" => item.productionYear,
    "communityrating" || "criticrating" => item.communityRating,
    "runtime" => item.runTimeTicks,
    "parentindexnumber" => item.parentIndexNumber,
    "indexnumber" => item.indexNumber,
    _ => null,
  };

  /// Compares sort values, putting missing values first like Jellyfin does.
  static int _compareValues(Object? a, Object? b) {
    if (a == null || b == null) {
      return a == null ? (b == null ? 0 : -1) : 1;
    }
    if (a is num && b is num) return a.compareTo(b);
    if (a is String && b is String) return a.compareTo(b);
    return 0;
  }

  static String _nameKey(BaseItemDto item) => _normalize(item.nameForSorting) ?? "";

  static String? _normalize(String? value) => value == null ? null : removeDiacritics(value).toLowerCase();

  static bool _matchesSearch(BaseItemDto item, String searchTerm) =>
      _normalize(item.name)?.contains(_normalize(searchTerm)!) ?? false;

  static List<BaseItemDto> _distinct(List<BaseItemDto> items) {
    final seen = <BaseItemId>{};
    return items.where((item) => seen.add(item.id)).toList();
  }

  /// Fetches all pages of a list endpoint, a few pages at a time.
  static Future<List<T>> _fetchAllPages<T>(
    Future<List<T>> Function(int offset) fetchPage, {
    int pageSize = SubsonicApi.maxPageSize,
    int parallelPages = 4,
  }) async {
    final results = <T>[];
    var offset = 0;
    while (true) {
      final pages = await Future.wait([for (var i = 0; i < parallelPages; i++) fetchPage(offset + i * pageSize)]);
      for (final page in pages) {
        results.addAll(page);
      }
      if (pages.any((page) => page.length < pageSize)) {
        return results;
      }
      offset += parallelPages * pageSize;
    }
  }

  /// Like [Future.wait] on [inputs] mapped with [convert], but with at most [concurrency] requests at a time.
  static Future<List<R>> _mapConcurrently<T, R>(
    List<T> inputs,
    Future<R> Function(T input) convert, {
    int concurrency = 6,
  }) async {
    final results = List<R?>.filled(inputs.length, null);
    var next = 0;
    Future<void> worker() async {
      while (next < inputs.length) {
        final index = next++;
        results[index] = await convert(inputs[index]);
      }
    }

    await Future.wait([for (var i = 0; i < min(concurrency, inputs.length); i++) worker()]);
    return results.cast<R>();
  }
}

/// Caches the results of async loads for a limited time, and shares in-flight loads.  Failed loads aren't cached.
class _Cache<K, V extends Object> {
  _Cache(this._duration);

  final Duration _duration;
  final Map<K, (DateTime, Future<V>)> _entries = {};

  /// Returns the cached value for [key] if it's younger than [maxAge] (or the cache duration), otherwise [load]s it.
  Future<V> get(K key, Future<V> Function() load, {Duration? maxAge}) {
    final entry = _entries[key];
    final age = maxAge == null || maxAge > _duration ? _duration : maxAge;
    if (entry != null && DateTime.now().difference(entry.$1) < age) {
      return entry.$2;
    }
    return refresh(key, load);
  }

  /// Loads the value for [key], replacing any cached value.
  Future<V> refresh(K key, Future<V> Function() load) {
    final future = load();
    _entries[key] = (DateTime.now(), future);
    unawaited(
      future.then(
        (_) {},
        onError: (Object _) {
          if (identical(_entries[key]?.$2, future)) {
            _entries.remove(key);
          }
        },
      ),
    );
    return future;
  }

  void clear() => _entries.clear();
}
