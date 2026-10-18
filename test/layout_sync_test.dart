import 'dart:io';

import 'package:finamp/hive_registrar.g.dart';
import 'package:finamp/models/finamp_models.dart';
import 'package:finamp/models/jellyfin_models.dart' show SortBy, SortOrder, currentLibraryPlaceholder;
import 'package:finamp/models/locale_adapter.dart';
import 'package:finamp/models/theme_mode_adapter.dart';
import 'package:finamp/services/finamp_settings_helper.dart';
import 'package:finamp/services/layout_sync_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce_flutter/adapters.dart';

FinampSettings _newSettings() => FinampSettings(
  downloadLocations: [],
  downloadLocationsMap: {},
  tabSortBy: {},
  tabSortOrder: {},
  homeScreenConfiguration: DefaultSettings.homeScreenConfiguration,
  gridImageSize: DefaultSettings.gridImageSize,
  homeScreenImageSize: DefaultSettings.homeScreenImageSize,
  deviceId: "test",
);

/// A layout with every kind of setting changed
FinampSettings _customizedSettings() => _newSettings()
  ..themeMode = ThemeMode.light
  ..accentColor = const Color(0xFF00FF66)
  ..gridImageSize = 210
  ..prioritizeCoverFactor = 3.5
  ..lyricsAlignment = LyricsAlignment.center
  ..tabOrder = [ContentType.tracks, ContentType.home, ContentType.albums]
  ..showTabs = {ContentType.tracks: true, ContentType.home: true, ContentType.albums: false}
  ..tabSortBy = {ContentType.albums: SortBy.dateCreated, ContentType.tracks: SortBy.random}
  ..perTabContentViewType = {ContentType.albums: ContentViewType.list}
  ..featureChipsConfiguration = const FinampFeatureChipsConfiguration(
    enabled: false,
    features: [FinampFeatureChipType.codec],
    migrated: true,
  )
  ..homeScreenConfiguration = FinampHomeScreenConfiguration(
    actions: [QuickActionConfig(action: FinampQuickActions.surpriseMe)],
    sections: [
      HomeScreenSectionConfiguration(
        base: TabsHomeSection(libraryId: currentLibraryPlaceholder, contentType: ContentType.albums),
        sortConfig: SortAndFilterConfiguration(
          sortBy: SortBy.random,
          sortOrder: SortOrder.ascending,
          filters: {ItemFilter(type: ItemFilterType.isFavorite)},
        ),
        customSectionTitle: "Favorites, at random",
      ),
      HomeScreenSectionConfiguration.fromPreset(HomeScreenSectionPresetType.recentQueues),
    ],
  );

class _FakeStore implements LayoutStore {
  String? layout;
  int saves = 0;
  bool failSaves = false;

  @override
  Future<String?> load() async => layout;

  @override
  Future<void> save(String layout) async {
    if (failSaves) throw const SocketException("Server unreachable");
    saves++;
    this.layout = layout;
  }
}

/// A device logged into the account whose layout is in [store].  Only one device uses the settings box at a time.
class _Device {
  _Device(this.name, this.settings, _FakeStore store, Box<String> stateBox)
    : state = LayoutSyncState(stateBox),
      asked = [] {
    service = LayoutSyncService(
      store: store,
      state: state,
      userKey: () => "server/jane",
      askWhichLayout: (saved) async {
        asked.add(saved);
        return answer;
      },
      deviceName: () async => name,
      saveDelay: const Duration(milliseconds: 1),
    );
  }

  final String name;
  final FinampSettings settings;
  final LayoutSyncState state;
  late final LayoutSyncService service;
  final List<SavedLayout> asked;
  LayoutChoice? answer;

  LayoutValues get layout => LayoutCodec.read(settings);

  /// Makes this the device using the settings box
  Future<void> use() => Hive.box<FinampSettings>("FinampSettings").put("FinampSettings", settings);

  Future<void> sync({bool interactive = true}) async {
    await use();
    await service.sync(interactive: interactive);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory directory;
  late _FakeStore store;
  var boxes = 0;

  setUpAll(() async {
    directory = await Directory.systemTemp.createTemp("finamp_layout_sync");
    Hive.init(directory.path);
    Hive.registerAdapters();
    Hive.registerAdapter(ThemeModeAdapter());
    Hive.registerAdapter(ColorAdapter());
    Hive.registerAdapter(LocaleAdapter());
    await Hive.openBox<FinampSettings>("FinampSettings");
  });

  tearDownAll(() async {
    await Hive.close();
    await directory.delete(recursive: true);
  });

  setUp(() {
    store = _FakeStore();
  });

  Future<_Device> device(String name, FinampSettings settings, {bool newInstall = false}) async {
    final device = _Device(name, settings, store, await Hive.openBox<String>("LayoutSync${boxes++}"));
    if (newInstall) {
      await device.use();
      await LayoutSyncService.rememberPristineLayout(device.state);
    }
    return device;
  }

  group("codec", () {
    test("reads back every setting exactly", () {
      final original = LayoutCodec.read(_customizedSettings());
      final copy = _newSettings();
      LayoutCodec.write(copy, original);

      expect(LayoutCodec.read(copy), original);
      expect(copy.themeMode, ThemeMode.light);
      expect(copy.accentColor, const Color(0xFF00FF66));
      expect(copy.tabOrder, [ContentType.tracks, ContentType.home, ContentType.albums]);
      expect(copy.tabSortBy[ContentType.albums], SortBy.dateCreated);
      final section = copy.homeScreenConfiguration.sections.first;
      expect(section.customSectionTitle, "Favorites, at random");
      expect(section.sortConfig.filters.single.type, ItemFilterType.isFavorite);
    });

    test("covers only layout settings", () {
      final settings = _newSettings();
      final layout = LayoutCodec.read(settings);
      settings
        ..currentVolume = 0.2
        ..isOffline = true
        ..transcodeBitrate = 64000;
      expect(LayoutCodec.read(settings), layout);
    });

    test("skips settings it doesn't know or can't read", () {
      final settings = _newSettings();
      LayoutCodec.write(settings, {
        "fromANewerVersion": LayoutCodec.encode(true),
        "themeMode": "not hive",
        "gridImageSize": LayoutCodec.encode(321),
      });
      expect(settings.themeMode, DefaultSettings.themeMode);
      expect(settings.gridImageSize, 321);
    });
  });

  group("merging", () {
    const base = {"a": "1", "b": "1", "c": "1", "d": "1"};

    test("keeps changes made on either side, and the account's when both changed a setting", () {
      expect(mergeLayouts(base: base, local: {...base, "a": "local", "c": "local"}, remote: {...base, "b": "remote"}), {
        "a": "local",
        "b": "remote",
        "c": "local",
        "d": "1",
      });
      expect(mergeLayouts(base: base, local: {...base, "a": "local"}, remote: {...base, "a": "remote"}), {
        ...base,
        "a": "remote",
      });
    });

    test("keeps settings only one side knows", () {
      expect(mergeLayouts(base: base, local: {...base, "new": "local"}, remote: {...base, "newer": "remote"}), {
        ...base,
        "new": "local",
        "newer": "remote",
      });
    });
  });

  group("syncing", () {
    test("the first device with a layout saves it with the account", () async {
      final phone = await device("Phone", _customizedSettings());
      await phone.sync();

      final saved = SavedLayout.decode(store.layout)!;
      expect(saved.values, phone.layout);
      expect(saved.savedBy, "Phone");
      expect(phone.asked, isEmpty);
    });

    test("a device that was already set up asks, then takes the account's layout", () async {
      final phone = await device("Phone", _customizedSettings());
      await phone.sync();
      final tv = await device("TV", _newSettings())
        ..answer = LayoutChoice.saved;
      await tv.sync();

      expect(tv.asked.single.savedBy, "Phone");
      expect(tv.layout, phone.layout);
      expect(tv.settings.homeScreenConfiguration.sections.first.customSectionTitle, "Favorites, at random");
      expect(store.saves, 1);

      // It's asked only once
      await tv.sync();
      expect(tv.asked, hasLength(1));
    });

    test("a device can keep its own layout instead", () async {
      final phone = await device("Phone", _customizedSettings());
      await phone.sync();
      final tv = await device("TV", _newSettings())
        ..answer = LayoutChoice.device;
      await tv.sync();

      expect(tv.layout, LayoutCodec.read(_newSettings()));
      expect(SavedLayout.decode(store.layout)!.values, tv.layout);

      await phone.sync();
      expect(phone.layout, tv.layout);
    });

    test("nothing changes when the question is dismissed, or can't be asked", () async {
      final phone = await device("Phone", _customizedSettings());
      await phone.sync();
      final tv = await device("TV", _newSettings());
      await tv.sync(interactive: false);
      expect(tv.asked, isEmpty);
      await tv.sync();

      expect(tv.asked, hasLength(1));
      expect(tv.layout, LayoutCodec.read(_newSettings()));
      expect(SavedLayout.decode(store.layout)!.values, phone.layout);
    });

    test("a new install takes the account's layout without asking", () async {
      final phone = await device("Phone", _customizedSettings());
      await phone.sync();
      final tv = await device("TV", _newSettings(), newInstall: true);
      await tv.sync(interactive: false);

      expect(tv.asked, isEmpty);
      expect(tv.layout, phone.layout);
    });

    test("a new install doesn't save its layout before it's changed", () async {
      final tv = await device("TV", _newSettings(), newInstall: true);
      await tv.sync();
      expect(store.layout, isNull);

      // So the phone's layout is the one that's kept, without asking
      final phone = await device("Phone", _customizedSettings());
      await phone.sync();
      await tv.sync();
      expect(tv.layout, phone.layout);
      expect(tv.asked, isEmpty);
      expect(phone.asked, isEmpty);
    });

    test("changes made on each device are merged", () async {
      final phone = await device("Phone", _customizedSettings());
      await phone.sync();
      final tv = await device("TV", _newSettings(), newInstall: true);
      await tv.sync();

      await phone.use();
      phone.settings
        ..themeMode = ThemeMode.dark
        ..lyricsFontSize = LyricsFontSize.large;
      await phone.sync();
      await tv.use();
      tv.settings
        ..themeMode = ThemeMode.system
        ..gridImageSize = 99;
      await tv.sync();
      await phone.sync();

      for (final device in [phone, tv]) {
        // Both changed the theme, and the phone's was saved first
        expect(device.settings.themeMode, ThemeMode.dark);
        expect(device.settings.lyricsFontSize, LyricsFontSize.large);
        expect(device.settings.gridImageSize, 99);
      }
      expect(phone.layout, tv.layout);
    });

    test("a layout that couldn't be saved is saved with the next sync", () async {
      final phone = await device("Phone", _customizedSettings());
      await phone.sync();
      final tv = await device("TV", _newSettings(), newInstall: true);
      await tv.sync();

      tv.settings.gridImageSize = 99;
      store.failSaves = true;
      await tv.sync();
      store.failSaves = false;
      expect(SavedLayout.decode(store.layout)!.values["gridImageSize"], phone.layout["gridImageSize"]);

      await tv.sync();
      expect(SavedLayout.decode(store.layout)!.values["gridImageSize"], LayoutCodec.encode(99));
    });

    test("layout changes are saved shortly after they're made", () async {
      final phone = await device("Phone", _customizedSettings());
      await phone.sync();
      phone.service.start();
      addTearDown(phone.service.dispose);

      FinampSetters.setLyricsFontSize(LyricsFontSize.small);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await phone.service.sync();

      expect(SavedLayout.decode(store.layout)!.values["lyricsFontSize"], LayoutCodec.encode(LyricsFontSize.small));
      expect(store.saves, 2);

      // Other settings don't save the layout again
      FinampSetters.setCurrentVolume(0.5);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await phone.service.sync();
      expect(store.saves, 2);
    });

    test("doesn't sync while offline or turned off", () async {
      final phone = await device("Phone", _customizedSettings()..isOffline = true);
      await phone.sync();
      phone.settings
        ..isOffline = false
        ..syncLayoutWithAccount = false;
      await phone.sync();
      expect(store.layout, isNull);
    });
  });
}
