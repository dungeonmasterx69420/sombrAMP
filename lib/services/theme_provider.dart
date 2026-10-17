import 'dart:async';
import 'dart:io';

import 'package:dynamic_color/dynamic_color.dart';
import 'package:finamp/color_schemes.g.dart';
import 'package:finamp/services/album_image_provider.dart';
import 'package:finamp/services/current_album_image_provider.dart';
import 'package:finamp/services/finamp_settings_helper.dart';
import 'package:finamp/services/queue_service.dart';
import 'package:flutter/material.dart' hide Image;
import 'package:flutter_blurhash/flutter_blurhash.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:get_it/get_it.dart';
import 'package:logging/logging.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../models/finamp_models.dart';
import '../models/jellyfin_models.dart';
import 'widget_bindings_observer_provider.dart';

part 'theme_provider.g.dart';

final themeProviderLogger = Logger("ThemeProvider");

class PlayerScreenTheme extends StatelessWidget {
  final Widget child;
  final Duration? themeTransitionDuration;
  final ThemeData Function(ThemeData)? themeOverride;

  const PlayerScreenTheme({super.key, required this.child, this.themeTransitionDuration, this.themeOverride});

  @override
  Widget build(BuildContext context) {
    return Consumer(
      builder: (context, ref, child) {
        final image = ref.watch(currentAlbumImageProvider);
        // Directly watching currentAlbumImageProvider in the override seems to have issues with not rebuilding the
        // provider until after the consuming widgets have already started building, so watch in a surrounding consumer
        // to work around this.
        return ProviderScope(overrides: [localImageProvider.overrideWithValue(image)], child: child!);
      },
      child: Consumer(
        builder: (context, ref, child) {
          // precache adjacent themes
          final List<FinampQueueItem> precacheItems = GetIt.instance<QueueService>().peekQueue(
            next: 2,
            previous: 1,
            current: true,
          );
          for (final itemToPrecache in precacheItems) {
            final base = itemToPrecache.baseItem;
            ref.listen(finampThemeProvider(ThemeInfo(base, useLargeImage: true)), (_, _) {});
          }
          // sombra System S: artwork doesn't tint the UI, the app theme carries through.
          var theme = Theme.of(context);
          if (themeOverride != null) {
            theme = themeOverride!(theme);
          }
          return AnimatedTheme(
            duration: getThemeTransitionDuration(context, themeTransitionDuration),
            data: theme,
            child: child!,
          );
        },
        child: child,
      ),
    );
  }
}

class ItemTheme extends StatelessWidget {
  final Widget child;
  final BaseItemDto item;
  final Duration? themeTransitionDuration;
  final ThemeData Function(ThemeData)? themeOverride;

  const ItemTheme({
    super.key,
    required this.item,
    required this.child,
    this.themeTransitionDuration,
    this.themeOverride,
  });

  @override
  Widget build(BuildContext context) {
    return ProviderScope(
      overrides: [localThemeInfoProvider.overrideWithValue(ThemeInfo(item))],
      child: Consumer(
        builder: (context, ref, child) {
          // sombra System S: artwork doesn't tint the UI, the app theme carries through.
          var theme = Theme.of(context);
          if (themeOverride != null) {
            theme = themeOverride!(theme);
          }
          return AnimatedTheme(
            duration: getThemeTransitionDuration(context, themeTransitionDuration),
            data: theme,
            child: child!,
          );
        },
        child: child,
      ),
    );
  }
}

/// The local ThemeInfo request.  Do not read this directly, use [localImageProvider].
final Provider<ThemeInfo?> localThemeInfoProvider = Provider((ref) => null, dependencies: const []);

final Provider<FinampImage> localImageProvider = Provider((ref) {
  var item = ref.watch(localThemeInfoProvider);
  if (item == null) {
    return FinampImage.empty();
  }
  return ref.watch(themeImageProvider(item));
}, dependencies: [localThemeInfoProvider]);

final Provider<ColorScheme> localThemeProvider = Provider(
  (ref) => ref.watch(systemSColorSchemeProvider),
  dependencies: [localImageProvider],
);

/// The System S colour scheme for the current brightness and phosphor.
///
/// sombra System S keeps the phosphor as the only colour, so items no longer get colours from their
/// artwork; every theme request resolves to this.
final Provider<ColorScheme> systemSColorSchemeProvider = Provider((ref) {
  final accent = ref.watch(finampSettingsProvider.useSystemAccentColor)
      ? ref.watch(finampSettingsProvider.systemAccentColor)
      : ref.watch(finampSettingsProvider.accentColor);
  return getColorScheme(accent, ref.watch(brightnessProvider), ref.watch(finampSettingsProvider.amoledTheme));
});

@riverpod
ColorScheme finampTheme(Ref ref, ThemeInfo request) {
  var image = ref.watch(themeImageProvider(request));
  return ref.watch(finampThemeFromImageProvider(image.colorRequest));
}

@riverpod
FinampThemeImage themeImage(Ref ref, ThemeInfo request) {
  var item = request.item;
  String? cacheKey = request.item.blurHash ?? request.item.imageId;
  // If useLargeImage, we are doing theme pre-caching for the player and should always use the full-size image,
  // even if no-one else is currently using it.
  if (request.useLargeImage) {
    final albumImage = ref.watch(albumImageProvider(AlbumImageRequest(item: item)));
    assert(albumImage.fullQuality);
    return albumImage.asTheme(request);
  }
  // Re-use an existing request if possible to hit the image cache
  else if (albumRequestsCache.containsKey(cacheKey)) {
    if (albumRequestsCache[cacheKey] == null) {
      return FinampThemeImage.empty(request);
    }
    final albumImage = ref.watch(albumImageProvider(albumRequestsCache[cacheKey]!));
    return albumImage.asTheme(request);
  } else {
    // Use blurhash if possible, otherwise fetch 100x100
    if (item.blurHash != null) {
      final image = BlurHashImage(item.blurHash!);
      return FinampThemeImage(image, request, fullQuality: false);
    } else if (item.imageId != null) {
      // ignore: avoid_manual_providers_as_generated_provider_dependency
      final albumImage = ref.watch(albumImageProvider(AlbumImageRequest(item: item, maxHeight: 100, maxWidth: 100)));
      return albumImage.asTheme(request);
    } else {
      return FinampThemeImage.empty(request);
    }
  }
}

@riverpod
class FinampThemeFromImage extends _$FinampThemeFromImage {
  @override
  ColorScheme build(ThemeColorRequest theme) => ref.watch(systemSColorSchemeProvider);
}

ColorScheme getGrayTheme(Brightness brightness) => _systemSScheme(brightness);

ColorScheme getDefaultTheme(Brightness brightness) => _systemSScheme(brightness);

ColorScheme _systemSScheme(Brightness brightness) {
  final settings = FinampSettingsHelper.finampSettings;
  final accent = settings.useSystemAccentColor ? settings.systemAccentColor : settings.accentColor;
  return getColorScheme(accent, brightness, settings.amoledTheme);
}

@immutable
class ThemeInfo {
  const ThemeInfo(this.item, {this.useIsolate = true, this.useLargeImage = false});

  final BaseItemDto item;

  final bool useIsolate;

  final bool useLargeImage;

  @override
  bool operator ==(Object other) {
    return other is ThemeInfo && other._imageCode == _imageCode && other.useLargeImage == useLargeImage;
  }

  @override
  int get hashCode => Object.hash(_imageCode, useLargeImage);

  String? get _imageCode => item.blurHash ?? item.imageId;
}

@immutable
class FinampImage {
  const FinampImage.empty() : image = null, fullQuality = false;
  const FinampImage(this.image, {this.fullQuality = false});

  /// The imageProvider associated with [request]
  final ImageProvider? image;

  /// Whether we have the full-size imageProvider usable in any scenario, or a rescaled version.
  final bool fullQuality;

  BaseItemDto? get item => null;

  @override
  bool operator ==(Object other) {
    return other is FinampImage && other.image == image && other.item == item;
  }

  @override
  String toString() => "FinampImage(image: $image item: ${item?.name} fullQuality: $fullQuality)";

  @override
  int get hashCode => Object.hash(image, item);
}

@immutable
class FinampThemeImage extends FinampImage {
  const FinampThemeImage(super.image, this.themeRequest, {required super.fullQuality});
  const FinampThemeImage.empty(this.themeRequest) : super(null, fullQuality: true);

  final ThemeInfo themeRequest;

  ThemeColorRequest get colorRequest => ThemeColorRequest(image, item.blurHash, themeRequest.useIsolate, fullQuality);

  @override
  BaseItemDto get item => themeRequest.item;
}

@immutable
/// A request to calculate a theme color.  This is separate from [FinampThemeImage] as this does not consider
/// BaseItemDto.id when determining duplicates.
class ThemeColorRequest {
  const ThemeColorRequest(this.image, this.blurHash, this.useIsolate, this.fullQuality);

  final ImageProvider? image;

  final String? blurHash;

  final bool useIsolate;

  final bool fullQuality;

  @override
  bool operator ==(Object other) {
    return other is ThemeColorRequest && other.image == image && other.blurHash == blurHash;
  }

  @override
  int get hashCode => Object.hash(image, blurHash);
}

_ThemeTransitionCalculator? _calculator;

Duration getThemeTransitionDuration(BuildContext context, Duration? duration) =>
    (_calculator ??= _ThemeTransitionCalculator()).getThemeTransitionDuration(context, duration);

/// Skip track change transition animations if app or route is in background
class _ThemeTransitionCalculator {
  _ThemeTransitionCalculator() {
    AppLifecycleListener(
      onShow: () {
        // Continue skipping until we get a foreground track change.
        _skipAllTransitions = true;
      },
      onHide: () {
        _skipAllTransitions = true;
      },
      onRestart: () {
        unawaited(fetchSystemPalette());
      },
      onResume: () {
        unawaited(fetchSystemPalette());
      },
    );
    GetIt.instance<QueueService>().getCurrentTrackStream().listen((value) {
      _skipAllTransitions = false;
    });
  }

  bool _skipAllTransitions = false;

  Duration getThemeTransitionDuration(BuildContext context, Duration? duration) {
    if (_skipAllTransitions || MediaQuery.disableAnimationsOf(context)) {
      return Duration.zero;
    }
    return (context.mounted && (ModalRoute.isCurrentOf(context) ?? true))
        ? duration ?? const Duration(milliseconds: 1000)
        : Duration.zero;
  }
}

Future<void> fetchSystemPalette() async {
  final currentColor = FinampSettingsHelper.finampSettings.systemAccentColor;
  Color? newColor;

  if (Platform.isAndroid) {
    final palette = await DynamicColorPlugin.getCorePalette();
    newColor = palette?.toColorScheme().primary;
  } else {
    newColor = await DynamicColorPlugin.getAccentColor();
  }

  // only update when needed (color transitions is laggy, no need to run it when not required)
  if (newColor != currentColor) {
    FinampSetters.setSystemAccentColor(newColor);
  }
}
