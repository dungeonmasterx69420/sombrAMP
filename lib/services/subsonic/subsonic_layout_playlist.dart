import 'dart:convert';
import 'dart:io' show gzip;

import 'package:finamp/sombra/system_s_widgets.dart';

/// Subsonic servers don't store anything for clients, so the layout saved with the account is kept in the comment of a
/// private playlist, which is left out of the playlists the app shows.
///
/// Subsonic requests carry everything in the URL, which proxies limit to a few kilobytes, so the layout is compressed.
abstract final class SubsonicLayoutPlaylist {
  static const name = "${Sombra.productName} layout";

  static const _marker = "${Sombra.productName}-layout:";

  /// Whether [playlist] is the one of [username] that keeps the layout.  It's found by name, so that a playlist whose
  /// comment wasn't saved yet is reused.
  static bool isOwnedBy(Map<String, dynamic> playlist, {required String username}) =>
      playlist["name"] == name && (playlist["owner"] == null || playlist["owner"] == username);

  /// Whether [playlist] keeps a layout, and so isn't one of the user's playlists.
  static bool keepsLayout(Map<String, dynamic> playlist) =>
      playlist["name"] == name && (playlist["comment"] as String? ?? "").contains(_marker);

  static String commentFor(String layout) =>
      "Keeps the layout of ${Sombra.productName}, so that it's the same on all of your devices. "
      "Deleting this playlist only forgets it.\n"
      "$_marker${base64Url.encode(gzip.encode(utf8.encode(layout)))}";

  /// The layout kept in [comment], or null if it has none or it can't be read.
  static String? layoutIn(String? comment) {
    final start = comment?.lastIndexOf(_marker) ?? -1;
    if (start < 0) return null;
    try {
      return utf8.decode(gzip.decode(base64Url.decode(comment!.substring(start + _marker.length).trim())));
    } on FormatException {
      return null;
    }
  }
}
