import 'dart:convert';

import 'package:finamp/services/subsonic/subsonic_api.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

typedef SubsonicHandler = Map<String, Object?> Function(Map<String, List<String>> parameters);

/// An in-memory Subsonic server for tests.  Each endpoint is answered by a handler returning the contents of the
/// `subsonic-response` envelope.  Handlers can throw a [SubsonicException] to return an error.
class FakeSubsonicServer {
  FakeSubsonicServer(this.handlers);

  final Map<String, SubsonicHandler> handlers;

  /// All requests received, in order
  final List<Uri> requests = [];

  static final baseUrl = Uri.parse("https://music.example.com/navidrome");

  Iterable<Uri> requestsTo(String endpoint) => requests.where((uri) => uri.pathSegments.last == "$endpoint.view");

  http.Client get client => MockClient((request) async {
    requests.add(request.url);
    final endpoint = request.url.pathSegments.last.replaceAll(".view", "");
    final handler = handlers[endpoint];
    try {
      if (handler == null) {
        throw SubsonicException(SubsonicException.notFound, "No handler for $endpoint");
      }
      return _response({"status": "ok", ...handler(request.url.queryParametersAll)});
    } on SubsonicException catch (e) {
      return _response({
        "status": "failed",
        "error": {"code": e.code, "message": e.message},
      });
    }
  });

  static http.Response _response(Map<String, Object?> envelope) => http.Response(
    jsonEncode({
      "subsonic-response": {
        "version": "1.16.1",
        "type": "navidrome",
        "serverVersion": "0.58.0",
        "openSubsonic": true,
        ...envelope,
      },
    }),
    200,
    headers: {"content-type": "application/json; charset=utf-8"},
  );
}

Map<String, Object?> song(
  String id, {
  required String title,
  String albumId = "al1",
  String album = "First Album",
  String artistId = "ar1",
  String artist = "The Artist",
  int track = 1,
  int disc = 1,
  int duration = 200,
  int? playCount,
  String? starred,
  String genre = "Rock",
  String created = "2024-01-01T00:00:00Z",
}) => {
  "id": id,
  "title": title,
  "album": album,
  "albumId": albumId,
  "artist": artist,
  "artistId": artistId,
  "track": track,
  "discNumber": disc,
  "duration": duration,
  "bitRate": 320,
  "suffix": "mp3",
  "contentType": "audio/mpeg",
  "size": 8000000,
  "coverArt": "mf-$id",
  "path": "$artist/$album/$track - $title.mp3",
  "genre": genre,
  "created": created,
  "playCount": playCount,
  "starred": starred,
}..removeWhere((_, value) => value == null);

Map<String, Object?> album(
  String id, {
  required String name,
  String artistId = "ar1",
  String artist = "The Artist",
  int year = 2020,
  int songCount = 2,
  String? starred,
  String genre = "Rock",
  String created = "2024-01-01T00:00:00Z",
}) => {
  "id": id,
  "name": name,
  "artist": artist,
  "artistId": artistId,
  "coverArt": "al-$id",
  "songCount": songCount,
  "duration": 400,
  "year": year,
  "genre": genre,
  "created": created,
  "starred": starred,
}..removeWhere((_, value) => value == null);
