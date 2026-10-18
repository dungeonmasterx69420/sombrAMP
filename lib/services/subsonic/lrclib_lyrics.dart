import 'dart:convert';

import 'package:collection/collection.dart';
import 'package:finamp/models/jellyfin_models.dart';
import 'package:finamp/sombra/system_s_widgets.dart';
import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';

import 'subsonic_mapper.dart';

/// Looks up lyrics on [LRCLIB](https://lrclib.net), a free database of synced and plain lyrics, for tracks a server
/// has none for.
class LrclibLyrics {
  LrclibLyrics({http.Client? httpClient}) : _httpClient = httpClient ?? http.Client();

  static final _logger = Logger("LrclibLyrics");

  /// LRCLIB asks clients to identify themselves.
  static const _headers = {
    "User-Agent": "${Sombra.productName} (${Sombra.sourceCode})",
    "Lrclib-Client": "${Sombra.productName} (${Sombra.sourceCode})",
  };

  /// How far a search result's duration may be from the track's, in seconds.
  static const _durationTolerance = 3;

  final http.Client _httpClient;

  /// Finds the lyrics of a track, preferring synced lyrics.  Returns null if LRCLIB has none, or if the track is an
  /// instrumental.
  ///
  /// The exact match on all of the track's details is tried first, then a search on its title and [primaryArtist],
  /// which also finds tracks released on other albums or credited to more artists.
  Future<LyricDto?> find({
    required String title,
    required String artist,
    String? primaryArtist,
    String? album,
    Duration? duration,
  }) async {
    if (title.trim().isEmpty || artist.trim().isEmpty) {
      return null;
    }
    final exact = await _get(
      Uri.https("lrclib.net", "/api/get", {
        "track_name": title,
        "artist_name": artist,
        if (album != null && album.isNotEmpty) "album_name": album,
        if (duration != null) "duration": duration.inSeconds.toString(),
      }),
    );
    if (exact != null) {
      return lyricsFromRecord(exact as Map<String, dynamic>);
    }

    final results = await _get(
      Uri.https("lrclib.net", "/api/search", {"track_name": title, "artist_name": primaryArtist ?? artist}),
    );
    final record = bestSearchResult((results as List<dynamic>? ?? []).cast<Map<String, dynamic>>(), duration);
    _logger.fine(
      record == null ? "LRCLIB has no lyrics for '$title' by $artist" : "Found the lyrics for '$title' on LRCLIB",
    );
    return record == null ? null : lyricsFromRecord(record);
  }

  /// Returns the decoded response, or null if LRCLIB has nothing.
  Future<Object?> _get(Uri url) async {
    final response = await _httpClient.get(url, headers: _headers).timeout(const Duration(seconds: 15));
    if (response.statusCode == 404) {
      return null;
    }
    if (response.statusCode != 200) {
      throw http.ClientException("LRCLIB answered with status ${response.statusCode}", url);
    }
    return jsonDecode(utf8.decode(response.bodyBytes));
  }

  /// Picks the search result whose duration matches [duration], preferring synced lyrics.
  static Map<String, dynamic>? bestSearchResult(List<Map<String, dynamic>> results, Duration? duration) {
    final matching = results.where((record) {
      if (lyricsFromRecord(record) == null) return false;
      final recordDuration = (record["duration"] as num?)?.toDouble();
      return duration == null ||
          recordDuration == null ||
          (recordDuration - duration.inSeconds).abs() <= _durationTolerance;
    });
    return matching.firstWhereOrNull((record) => _hasText(record["syncedLyrics"])) ?? matching.firstOrNull;
  }

  /// Converts an LRCLIB record to lyrics, preferring its synced lyrics.  Returns null if it has none.
  static LyricDto? lyricsFromRecord(Map<String, dynamic> record) {
    if (record["instrumental"] == true) {
      return null;
    }
    LyricMetadata metadata(bool isSynced) => LyricMetadata(
      artist: record["artistName"] as String?,
      album: record["albumName"] as String?,
      title: record["trackName"] as String?,
      isSynced: isSynced,
    );
    final synced = record["syncedLyrics"];
    if (synced is String) {
      final lines = parseSyncedLyrics(synced);
      if (lines.isNotEmpty) {
        return LyricDto(metadata: metadata(true), lyrics: lines);
      }
    }
    final plain = record["plainLyrics"];
    if (_hasText(plain)) {
      return LyricDto(
        metadata: metadata(false),
        lyrics: (plain as String).trim().split(RegExp(r"\r?\n")).map((line) => LyricLine(text: line)).toList(),
      );
    }
    return null;
  }

  static final _timestamp = RegExp(r"\[(\d+):(\d{1,2})(?:[.:](\d{1,3}))?\]");

  /// Parses lyrics in the LRC format, where each line starts with one or more `[minutes:seconds.fraction]`
  /// timestamps.  Lines without one, like `[ar: Artist]` tags, are left out.
  static List<LyricLine> parseSyncedLyrics(String lrc) {
    final lines = <(int, String)>[];
    for (final line in lrc.split(RegExp(r"\r?\n"))) {
      final timestamps = _timestamp.allMatches(line).toList();
      if (timestamps.isEmpty) continue;
      final text = line.replaceAll(_timestamp, "").trim();
      for (final timestamp in timestamps) {
        final fraction = (timestamp.group(3) ?? "0").padRight(3, "0");
        final milliseconds =
            int.parse(timestamp.group(1)!) * 60000 + int.parse(timestamp.group(2)!) * 1000 + int.parse(fraction);
        lines.add((milliseconds, text));
      }
    }
    // A stable sort, so lines with the same timestamp keep their order
    mergeSort(lines, compare: (a, b) => a.$1.compareTo(b.$1));
    return [
      for (final (milliseconds, text) in lines)
        LyricLine(text: text, start: milliseconds * SubsonicMapper.ticksPerMillisecond),
    ];
  }

  static bool _hasText(Object? value) => value is String && value.trim().isNotEmpty;
}
