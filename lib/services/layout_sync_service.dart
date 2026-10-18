import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:finamp/models/finamp_models.dart';
import 'package:finamp/models/jellyfin_models.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:hive_ce/hive.dart';
// hive_ce doesn't export its binary reader and writer.  They're what it stores every box with, so the format they read
// and write can't change without breaking every box.
// ignore: implementation_imports
import 'package:hive_ce/src/binary/binary_reader_impl.dart';
// ignore: implementation_imports
import 'package:hive_ce/src/binary/binary_writer_impl.dart';
import 'package:logging/logging.dart';

import 'finamp_settings_helper.dart';

/// A setting that's part of the layout, and so follows the user to their other devices.
class LayoutSetting<T> {
  const LayoutSetting(this.name, this._get, this._set, [this._cast]);

  /// Identifies the setting in the stored layout.  Never rename it, or it stops syncing with older versions.
  final String name;
  final T Function(FinampSettings settings) _get;
  final void Function(FinampSettings settings, T value) _set;

  /// Converts the value Hive reads into [T], for collections, which Hive reads without their type arguments.
  final T Function(Object? value)? _cast;

  Object? read(FinampSettings settings) => _get(settings);

  void write(FinampSettings settings, Object? value) {
    final cast = _cast;
    _set(settings, cast == null ? value as T : cast(value));
  }
}

/// The settings that make up the layout: those of Layout & Theme and its screens, the tabs, the home screen, and how
/// each tab is sorted.  Settings that depend on the device, like downloads, playback or the volume, aren't included.
final layoutSettings = <LayoutSetting<Object?>>[
  // Theme
  LayoutSetting<ThemeMode>("themeMode", (s) => s.themeMode, (s, v) => s.themeMode = v),
  LayoutSetting<bool>("amoledTheme", (s) => s.amoledTheme, (s, v) => s.amoledTheme = v),
  LayoutSetting<Color?>("accentColor", (s) => s.accentColor, (s, v) => s.accentColor = v),
  LayoutSetting<bool>("useSystemAccentColor", (s) => s.useSystemAccentColor, (s, v) => s.useSystemAccentColor = v),
  // Layout & Theme
  LayoutSetting<Map<ContentType, ContentViewType>>(
    "perTabContentViewType",
    (s) => s.perTabContentViewType,
    (s, v) => s.perTabContentViewType = v,
    (v) => (v as Map).cast<ContentType, ContentViewType>(),
  ),
  LayoutSetting<int>("gridImageSize", (s) => s.gridImageSize, (s, v) => s.gridImageSize = v),
  LayoutSetting<int>("homeScreenImageSize", (s) => s.homeScreenImageSize, (s, v) => s.homeScreenImageSize = v),
  LayoutSetting<bool>("showTextOnGridView", (s) => s.showTextOnGridView, (s, v) => s.showTextOnGridView = v),
  LayoutSetting<bool>("useCoverAsBackground", (s) => s.useCoverAsBackground, (s, v) => s.useCoverAsBackground = v),
  LayoutSetting<bool>("showArtistChipImage", (s) => s.showArtistChipImage, (s, v) => s.showArtistChipImage = v),
  LayoutSetting<bool>("allowSplitScreen", (s) => s.allowSplitScreen, (s, v) => s.allowSplitScreen = v),
  LayoutSetting<bool>(
    "showProgressOnNowPlayingBar",
    (s) => s.showProgressOnNowPlayingBar,
    (s, v) => s.showProgressOnNowPlayingBar = v,
  ),
  LayoutSetting<bool>(
    "autoSwitchItemCurationType",
    (s) => s.autoSwitchItemCurationType,
    (s, v) => s.autoSwitchItemCurationType = v,
  ),
  // Customization
  LayoutSetting<PlaybackSpeedVisibility>(
    "playbackSpeedVisibility",
    (s) => s.playbackSpeedVisibility,
    (s, v) => s.playbackSpeedVisibility = v,
  ),
  LayoutSetting<bool>(
    "oneLineMarqueeTextButton",
    (s) => s.oneLineMarqueeTextButton,
    (s, v) => s.oneLineMarqueeTextButton = v,
  ),
  LayoutSetting<Map<ContentType, TileAdditionalInfoType>>(
    "tileAdditionalInfoType",
    (s) => s.tileAdditionalInfoType,
    (s, v) => s.tileAdditionalInfoType = v,
    (v) => (v as Map).cast<ContentType, TileAdditionalInfoType>(),
  ),
  LayoutSetting<ReleaseDateFormat>("releaseDateFormat", (s) => s.releaseDateFormat, (s, v) => s.releaseDateFormat = v),
  LayoutSetting<bool>(
    "showAlbumReleaseDateOnPlayerScreen",
    (s) => s.showAlbumReleaseDateOnPlayerScreen,
    (s, v) => s.showAlbumReleaseDateOnPlayerScreen = v,
  ),
  LayoutSetting<bool>(
    "showStopButtonOnMediaNotification",
    (s) => s.showStopButtonOnMediaNotification,
    (s, v) => s.showStopButtonOnMediaNotification = v,
  ),
  LayoutSetting<bool>(
    "showShuffleButtonOnMediaNotification",
    (s) => s.showShuffleButtonOnMediaNotification,
    (s, v) => s.showShuffleButtonOnMediaNotification = v,
  ),
  LayoutSetting<bool>(
    "showFavoriteButtonOnMediaNotification",
    (s) => s.showFavoriteButtonOnMediaNotification,
    (s, v) => s.showFavoriteButtonOnMediaNotification = v,
  ),
  LayoutSetting<bool>(
    "showSeekControlsOnMediaNotification",
    (s) => s.showSeekControlsOnMediaNotification,
    (s, v) => s.showSeekControlsOnMediaNotification = v,
  ),
  // Player screen
  LayoutSetting<FinampFeatureChipsConfiguration>(
    "featureChipsConfiguration",
    (s) => s.featureChipsConfiguration,
    (s, v) => s.featureChipsConfiguration = v,
  ),
  LayoutSetting<double>(
    "playerScreenCoverMinimumPadding",
    (s) => s.playerScreenCoverMinimumPadding,
    (s, v) => s.playerScreenCoverMinimumPadding = v,
  ),
  LayoutSetting<bool>("suppressPlayerPadding", (s) => s.suppressPlayerPadding, (s, v) => s.suppressPlayerPadding = v),
  LayoutSetting<double>("prioritizeCoverFactor", (s) => s.prioritizeCoverFactor, (s, v) => s.prioritizeCoverFactor = v),
  LayoutSetting<bool>(
    "hidePlayerBottomActions",
    (s) => s.hidePlayerBottomActions,
    (s, v) => s.hidePlayerBottomActions = v,
  ),
  // Lyrics
  LayoutSetting<bool>("showLyricsTimestamps", (s) => s.showLyricsTimestamps, (s, v) => s.showLyricsTimestamps = v),
  LayoutSetting<bool>(
    "showLyricsScreenAlbumPrelude",
    (s) => s.showLyricsScreenAlbumPrelude,
    (s, v) => s.showLyricsScreenAlbumPrelude = v,
  ),
  LayoutSetting<LyricsAlignment>("lyricsAlignment", (s) => s.lyricsAlignment, (s, v) => s.lyricsAlignment = v),
  LayoutSetting<LyricsFontSize>("lyricsFontSize", (s) => s.lyricsFontSize, (s, v) => s.lyricsFontSize = v),
  LayoutSetting<bool>("lookUpLyricsOnline", (s) => s.lookUpLyricsOnline, (s, v) => s.lookUpLyricsOnline = v),
  // Album, artist and genre screens
  LayoutSetting<bool>(
    "showCoversOnAlbumScreen",
    (s) => s.showCoversOnAlbumScreen,
    (s, v) => s.showCoversOnAlbumScreen = v,
  ),
  LayoutSetting<List<ArtistItemSections>>(
    "artistItemSectionsOrder",
    (s) => s.artistItemSectionsOrder,
    (s, v) => s.artistItemSectionsOrder = v,
    (v) => (v as List).cast<ArtistItemSections>(),
  ),
  LayoutSetting<bool>(
    "showArtistsTracksSection",
    (s) => s.showArtistsTracksSection,
    (s, v) => s.showArtistsTracksSection = v,
  ),
  LayoutSetting<List<CuratedItemSelectionType>>(
    "artistItemSectionFilterChipOrder",
    (s) => s.artistItemSectionFilterChipOrder,
    (s, v) => s.artistItemSectionFilterChipOrder = v,
    (v) => (v as List).cast<CuratedItemSelectionType>(),
  ),
  LayoutSetting<List<GenreItemSections>>(
    "genreItemSectionsOrder",
    (s) => s.genreItemSectionsOrder,
    (s, v) => s.genreItemSectionsOrder = v,
    (v) => (v as List).cast<GenreItemSections>(),
  ),
  LayoutSetting<List<CuratedItemSelectionType>>(
    "genreItemSectionFilterChipOrder",
    (s) => s.genreItemSectionFilterChipOrder,
    (s, v) => s.genreItemSectionFilterChipOrder = v,
    (v) => (v as List).cast<CuratedItemSelectionType>(),
  ),
  LayoutSetting<bool>(
    "genreFilterArtistScreens",
    (s) => s.genreFilterArtistScreens,
    (s, v) => s.genreFilterArtistScreens = v,
  ),
  LayoutSetting<bool>("genreFilterPlaylists", (s) => s.genreFilterPlaylists, (s, v) => s.genreFilterPlaylists = v),
  LayoutSetting<bool>(
    "genreListsInheritSorting",
    (s) => s.genreListsInheritSorting,
    (s, v) => s.genreListsInheritSorting = v,
  ),
  // Tabs, the home screen, and the music screen
  LayoutSetting<List<ContentType>>(
    "tabOrder",
    (s) => s.tabOrder,
    (s, v) => s.tabOrder = v,
    (v) => (v as List).cast<ContentType>(),
  ),
  LayoutSetting<Map<ContentType, bool>>(
    "showTabs",
    (s) => s.showTabs,
    (s, v) => s.showTabs = v,
    (v) => (v as Map).cast<ContentType, bool>(),
  ),
  LayoutSetting<FinampHomeScreenConfiguration>(
    "homeScreenConfiguration",
    (s) => s.homeScreenConfiguration,
    (s, v) => s.homeScreenConfiguration = v,
  ),
  LayoutSetting<Map<ContentType, SortBy>>(
    "tabSortBy",
    (s) => s.tabSortBy,
    (s, v) => s.tabSortBy = v,
    (v) => (v as Map).cast<ContentType, SortBy>(),
  ),
  LayoutSetting<Map<ContentType, SortOrder>>(
    "tabSortOrder",
    (s) => s.tabSortOrder,
    (s, v) => s.tabSortOrder = v,
    (v) => (v as Map).cast<ContentType, SortOrder>(),
  ),
  LayoutSetting<ArtistType>("defaultArtistType", (s) => s.defaultArtistType, (s, v) => s.defaultArtistType = v),
];

/// A layout, as the value of each of its settings by [LayoutSetting.name].  Each value is stored the way Hive stores it
/// in the settings box, base64-encoded, so that every kind of setting is kept exactly and layouts can be compared
/// setting by setting.
typedef LayoutValues = Map<String, String>;

abstract final class LayoutCodec {
  static final _logger = Logger("LayoutCodec");

  static LayoutValues read(FinampSettings settings) => {
    for (final setting in layoutSettings) setting.name: encode(setting.read(settings)),
  };

  /// Writes [values] into [settings].  Values this version can't read, like those of settings or types added in a
  /// newer version, are skipped.
  static void write(FinampSettings settings, LayoutValues values) {
    for (final setting in layoutSettings) {
      final value = values[setting.name];
      if (value == null) continue;
      try {
        setting.write(settings, decode(value));
      } catch (e) {
        _logger.warning("Couldn't read the synced value of ${setting.name}: $e");
      }
    }
  }

  static String encode(Object? value) => base64.encode((BinaryWriterImpl(Hive)..write(value)).toBytes());

  static Object? decode(String value) => BinaryReaderImpl(base64.decode(value), Hive).read();
}

/// Merges the layout of this device ([local]) with the one stored with the account ([remote]), given the layout both
/// had when they last agreed ([base]).  A setting changed on only one side keeps that change, and a setting changed on
/// both takes the account's.  Settings only one side knows, from different versions of the app, are kept.
LayoutValues mergeLayouts({required LayoutValues base, required LayoutValues local, required LayoutValues remote}) {
  String merge(String name) {
    final localValue = local[name];
    final remoteValue = remote[name];
    if (localValue == null) return remoteValue!;
    if (remoteValue == null || remoteValue == base[name]) return localValue;
    return remoteValue;
  }

  return {
    for (final name in {...local.keys, ...remote.keys}) name: merge(name),
  };
}

/// Whether every setting in [layout] has the same value in [other].
bool layoutMatches(LayoutValues layout, LayoutValues other) =>
    layout.entries.every((entry) => !other.containsKey(entry.key) || other[entry.key] == entry.value);

/// A layout as it's stored with the user's account.
class SavedLayout {
  SavedLayout({required this.values, required this.savedAt, required this.savedBy});

  static const formatVersion = 1;

  final LayoutValues values;
  final DateTime savedAt;

  /// The name of the device that saved it.
  final String savedBy;

  String encode() => jsonEncode({
    "version": formatVersion,
    "savedAt": savedAt.toUtc().toIso8601String(),
    "savedBy": savedBy,
    "settings": values,
  });

  /// Reads a stored layout, returning null if it can't be read.
  static SavedLayout? decode(String? encoded) {
    if (encoded == null || encoded.isEmpty) return null;
    try {
      final json = jsonDecode(encoded) as Map<String, dynamic>;
      return SavedLayout(
        values: (json["settings"] as Map<String, dynamic>).cast<String, String>(),
        savedAt: DateTime.tryParse(json["savedAt"] as String? ?? "") ?? DateTime.fromMillisecondsSinceEpoch(0),
        savedBy: json["savedBy"] as String? ?? "",
      );
    } catch (e) {
      Logger("SavedLayout").warning("Couldn't read the layout saved with the account: $e");
      return null;
    }
  }
}

/// Where the layout of the account is stored.
abstract interface class LayoutStore {
  /// The layout stored with the current user's account, or null if none was stored.
  Future<String?> load();

  Future<void> save(String layout);
}

/// What this device remembers about syncing its layout, in the LayoutSync box.
class LayoutSyncState {
  LayoutSyncState(this._box);

  static const boxName = "LayoutSync";
  static const _pristineKey = "pristine";

  final Box<String> _box;

  /// The layout this device and the account of [userKey] last agreed on.
  LayoutValues? baseFor(String userKey) => _decode(_box.get("base/$userKey"));

  Future<void> setBaseFor(String userKey, LayoutValues values) async {
    await _box.put("base/$userKey", jsonEncode(values));
    // Once the layout has synced, it may have been changed, so it isn't the one of a new install anymore
    await _box.delete(_pristineKey);
  }

  /// The layout of this device when it was installed, until it agrees on one with an account.  Lets a new install
  /// take the account's layout without asking.
  LayoutValues? get pristine => _decode(_box.get(_pristineKey));

  Future<void> setPristine(LayoutValues values) => _box.put(_pristineKey, jsonEncode(values));

  static LayoutValues? _decode(String? json) =>
      json == null ? null : (jsonDecode(json) as Map<String, dynamic>).cast<String, String>();
}

/// Which layout to keep when this device's and the account's differ the first time they're synced.
enum LayoutChoice {
  /// Use the layout saved with the account on this device too
  saved,

  /// Keep this device's layout, and save it with the account
  device,
}

/// Keeps the layout the same on all of the user's devices, by storing it with their account on the server.
///
/// Each device remembers the layout it last agreed on with the account, which tells which side changed a setting
/// since.  Layout changes on this device are saved shortly after they're made, and the account's layout is fetched
/// when the app starts or comes back to the foreground.  The first time a device that was already set up syncs, and
/// its layout differs from the account's, the user is asked which one to keep.
class LayoutSyncService with WidgetsBindingObserver {
  LayoutSyncService({
    required LayoutStore store,
    required LayoutSyncState state,
    required String? Function() userKey,
    required Future<LayoutChoice?> Function(SavedLayout saved) askWhichLayout,
    Future<String> Function()? deviceName,
    this.saveDelay = const Duration(seconds: 3),
  }) : _store = store,
       _state = state,
       _userKey = userKey,
       _askWhichLayout = askWhichLayout,
       _deviceName = deviceName ?? (() async => Platform.operatingSystem);

  static final _logger = Logger("LayoutSync");

  /// How often the account's layout is fetched at most, when the app is opened or comes back to the foreground.
  static const _refreshInterval = Duration(seconds: 30);

  final LayoutStore _store;
  final LayoutSyncState _state;
  final String? Function() _userKey;
  final Future<LayoutChoice?> Function(SavedLayout saved) _askWhichLayout;
  final Future<String> Function() _deviceName;

  /// How long after a layout change it's saved, so that a slider or a series of changes are saved once.
  final Duration saveDelay;

  Future<void> _lastSync = Future.value();
  StreamSubscription<BoxEvent>? _settingsChanges;
  Timer? _saveTimer;
  DateTime? _lastRefresh;

  bool get _enabled => FinampSettingsHelper.finampSettings.syncLayoutWithAccount;

  /// Starts saving layout changes, and fetching the account's layout when the app comes back to the foreground.
  void start() {
    _settingsChanges ??= Hive.box<FinampSettings>("FinampSettings").watch(key: "FinampSettings").listen((_) {
      _saveTimer?.cancel();
      _saveTimer = Timer(saveDelay, _saveIfChanged);
    });
    WidgetsBinding.instance.addObserver(this);
  }

  Future<void> dispose() async {
    WidgetsBinding.instance.removeObserver(this);
    _saveTimer?.cancel();
    await _settingsChanges?.cancel();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(refresh());
    }
  }

  /// Fetches the account's layout, unless that was just done.  May ask which layout to keep, so only call this while
  /// the app is in use.
  Future<void> refresh() {
    final now = DateTime.now();
    final lastRefresh = _lastRefresh;
    if (lastRefresh != null && now.difference(lastRefresh) < _refreshInterval) {
      return _lastSync;
    }
    _lastRefresh = now;
    return sync(interactive: true);
  }

  /// Saves the layout with the account if it changed since they last agreed.
  void _saveIfChanged() {
    final userKey = _userKey();
    if (userKey == null || !_enabled || FinampSettingsHelper.finampSettings.isOffline) return;
    // Until this device has agreed on a layout with the account, it only syncs when asked to.
    final base = _state.baseFor(userKey) ?? _state.pristine;
    if (base != null && !layoutMatches(LayoutCodec.read(FinampSettingsHelper.finampSettings), base)) {
      unawaited(sync());
    }
  }

  /// Merges this device's layout with the account's, applies the result here and saves it with the account.  If this
  /// device and the account have never agreed on a layout and theirs differ, the user is asked which to keep when
  /// [interactive], and nothing is synced otherwise.
  Future<void> sync({bool interactive = false}) {
    // Syncs run one after the other
    return _lastSync = _lastSync.then((_) async {
      try {
        await _sync(interactive: interactive);
      } catch (e) {
        _logger.warning("Couldn't sync the layout: $e");
      }
    });
  }

  Future<void> _sync({required bool interactive}) async {
    final userKey = _userKey();
    if (userKey == null || !_enabled || FinampSettingsHelper.finampSettings.isOffline) return;

    final saved = SavedLayout.decode(await _store.load());
    final local = LayoutCodec.read(FinampSettingsHelper.finampSettings);
    final agreed = _state.baseFor(userKey);
    final pristine = agreed == null ? _state.pristine : null;

    if (saved == null) {
      if (pristine != null && layoutMatches(local, pristine)) {
        // A new install that wasn't changed has nothing worth saving: the first device that has a layout saves it.
        _logger.info("Neither the account nor this device have a layout yet");
        return;
      }
      _logger.info("Saving this device's layout with the account, which had none");
      await _save(userKey, local);
      return;
    }

    var base = agreed ?? pristine;
    if (base == null) {
      if (layoutMatches(local, saved.values)) {
        base = saved.values;
      } else {
        if (!interactive) return;
        final choice = await _askWhichLayout(saved);
        _logger.info("Asked which layout to keep: ${choice?.name ?? "no answer"}");
        if (choice == null) return;
        // Pretending the other side didn't change makes the merge take this side's settings.
        base = choice == LayoutChoice.saved ? local : saved.values;
      }
    }

    final merged = mergeLayouts(base: base, local: local, remote: saved.values);
    // Settings applied from the account aren't changes of this device, while those to save still are until saved.
    await _state.setBaseFor(userKey, saved.values);
    _apply(merged, local);
    if (mapEquals(merged, saved.values)) {
      await _state.setBaseFor(userKey, merged);
    } else {
      await _save(userKey, merged);
    }
  }

  void _apply(LayoutValues merged, LayoutValues local) {
    final changes = {
      for (final MapEntry(:key, :value) in merged.entries)
        if (local.containsKey(key) && local[key] != value) key: value,
    };
    if (changes.isEmpty) return;
    _logger.info("Applying the account's layout: ${changes.keys.join(", ")}");
    final settings = FinampSettingsHelper.finampSettings;
    LayoutCodec.write(settings, changes);
    FinampSettingsHelper.overwriteFinampSettings(settings);
  }

  Future<void> _save(String userKey, LayoutValues values) async {
    String deviceName;
    try {
      deviceName = await _deviceName();
    } catch (_) {
      deviceName = Platform.operatingSystem;
    }
    await _store.save(SavedLayout(values: values, savedAt: DateTime.now(), savedBy: deviceName).encode());
    await _state.setBaseFor(userKey, values);
  }

  /// Remembers the layout of a new install, after the settings were created and migrated.
  static Future<void> rememberPristineLayout(LayoutSyncState state) =>
      state.setPristine(LayoutCodec.read(FinampSettingsHelper.finampSettings));

  /// Identifies a user's account, to keep what was synced with each account apart.
  static String keyFor(FinampUser user) => "${user.serverId}/${user.id}";
}
