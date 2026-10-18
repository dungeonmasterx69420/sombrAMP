import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:audio_service/audio_service.dart';
import 'package:finamp/components/AddToPlaylistScreen/add_to_playlist_button.dart';
import 'package:finamp/components/audio_fade_progress_visualizer_container.dart';
import 'package:finamp/components/global_snackbar.dart';
import 'package:finamp/components/now_playing_volume_slider.dart';
import 'package:finamp/components/one_line_marquee_helper.dart';
import 'package:finamp/components/print_duration.dart';
import 'package:finamp/utils/platform_helper.dart';
import 'package:finamp/l10n/app_localizations.dart';
import 'package:finamp/models/finamp_models.dart';
import 'package:finamp/services/current_track_metadata_provider.dart';
import 'package:finamp/services/feedback_helper.dart';
import 'package:finamp/services/queue_service.dart';
import 'package:finamp/services/theme_provider.dart';
import 'package:finamp/sombra/system_s.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';
import 'package:get_it/get_it.dart';
import 'package:simple_gesture_detector/simple_gesture_detector.dart';

import '../models/jellyfin_models.dart' as jellyfin_models;
import '../screens/player_screen.dart';
import '../services/current_album_image_provider.dart';
import '../services/finamp_settings_helper.dart';
import '../services/media_state_stream.dart';
import '../services/music_player_background_task.dart';
import '../services/process_artist.dart';
import 'PlayerScreen/player_split_screen_scaffold.dart';
import 'album_image.dart';

class NowPlayingBar extends ConsumerWidget {
  const NowPlayingBar({super.key, this.focusNode});

  /// The focus node of the track's title and artist, which open the player screen.
  final FocusNode? focusNode;

  static const horizontalPadding = 8.0;
  static const albumImageSize = 64.0;
  static const showPlayButtonAtEnd = false;

  // System S: the bar is a small window, a pane with an ink edge and a hard shadow like a toast's.
  BoxDecoration? getShadow(BuildContext context) => const BoxDecoration();

  Decoration getWindowEdge(BuildContext context) => ShapeDecoration(
    shape: SystemSWindowBorder(
      side: BorderSide(color: ColorScheme.of(context).outline),
      shadow: ColorScheme.of(context).outline,
      depth: 3,
      stepped: false,
    ),
  );

  /// Playback is live, so progress glows in the phosphor.
  Color getProgressForegroundColor(WidgetRef ref) {
    return SystemSTheme.of(ref.context).phosphor;
  }

  Color getProgressBackgroundColor(WidgetRef ref) {
    return ColorScheme.of(ref.context).surfaceContainer;
  }

  Widget buildLoadingQueueBar(WidgetRef ref, void Function()? retryCallback) {
    final progressBackgroundColor = getProgressBackgroundColor(ref).withValues(alpha: 0.5);
    var context = ref.context;

    return SimpleGestureDetector(
      onVerticalSwipe: (direction) {
        if (direction == SwipeDirection.up && retryCallback != null) {
          retryCallback();
        }
      },
      onTap: retryCallback,
      child: Padding(
        padding: const EdgeInsets.only(left: 12.0, bottom: 12.0, right: 12.0),
        child: Container(
          decoration: getShadow(ref.context),
          foregroundDecoration: getWindowEdge(ref.context),
          child: Material(
            clipBehavior: Clip.antiAlias,
            color: ColorScheme.of(context).surfaceContainer,
            elevation: 0,
            child: Container(
              width: MediaQuery.widthOf(context),
              height: albumImageSize,
              padding: EdgeInsets.zero,
              child: Container(
                clipBehavior: Clip.antiAlias,
                decoration: ShapeDecoration(color: progressBackgroundColor, shape: const Border()),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.start,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Container(
                      width: albumImageSize,
                      height: albumImageSize,
                      decoration: const ShapeDecoration(shape: Border(), color: Color.fromRGBO(0, 0, 0, 0.3)),
                      child: (retryCallback != null)
                          ? const Icon(Icons.refresh, size: albumImageSize)
                          : const Center(child: CircularProgressIndicator.adaptive()),
                    ),
                    Expanded(
                      child: Container(
                        height: albumImageSize,
                        padding: const EdgeInsets.only(left: 12, right: 4),
                        alignment: Alignment.centerLeft,
                        child: Text(
                          (retryCallback != null)
                              ? AppLocalizations.of(context)!.queueRetryMessage
                              : AppLocalizations.of(context)!.queueLoadingMessage,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  static Future<void> openPlayerScreen() async {
    minimizeSplitScreen.value = false;
    await GlobalSnackbar.navigatorState?.push(
      PageRouteBuilder<void>(
        pageBuilder: (context, animation, secondaryAnimation) => const PlayerScreen(),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          if (MediaQuery.disableAnimationsOf(context)) {
            return child;
          }
          const begin = Offset(0.0, 1.0);
          const end = Offset.zero;

          var tween = Tween(begin: begin, end: end).chain(CurveTween(curve: Curves.easeInOutQuad));
          var offsetAnimation = animation.drive(tween);

          if (animation.status == AnimationStatus.reverse) {
            // dismiss animation
            return FadeTransition(opacity: animation, child: child);
          } else {
            return SlideTransition(position: offsetAnimation, child: child);
          }
        },
        settings: const RouteSettings(name: PlayerScreen.routeName),
      ),
    );
  }

  Widget buildNowPlayingBar(WidgetRef ref, FinampQueueItem currentTrack) {
    final audioHandler = GetIt.instance<MusicPlayerBackgroundTask>();
    final queueService = GetIt.instance<QueueService>();

    Duration? playbackPosition;

    final currentTrackBaseItem = currentTrack.item.extras?["itemJson"] != null
        ? jellyfin_models.BaseItemDto.fromJson(currentTrack.item.extras!["itemJson"] as Map<String, dynamic>)
        : null;
    var context = ref.context;

    final elapsedPartBackgroundColor = getProgressForegroundColor(ref);
    final remainingPartBackgroundColor = getProgressBackgroundColor(ref);
    Color primaryTextColor = ColorScheme.of(context).onSurface;

    final showPauseButton = ref.watch(
      mediaStateProvider.select((x) => x.playbackState.playing && x.fadeDirection != FadeDirection.fadeOut),
    );

    return Padding(
      padding: const EdgeInsets.only(left: 12.0, bottom: 12.0, right: 12.0),
      child: Semantics.fromProperties(
        properties: SemanticsProperties(label: AppLocalizations.of(context)!.nowPlayingBarTooltip, button: true),
        child: SimpleGestureDetector(
          onTap: () async => await openPlayerScreen(),
          child: Dismissible(
            key: const Key("NowPlayingBarDismiss"),
            direction: ref.watch(finampSettingsProvider.disableGesture)
                ? DismissDirection.none
                : DismissDirection.vertical,
            confirmDismiss: (direction) async {
              if (direction == DismissDirection.down) {
                FeedbackHelper.feedback(FeedbackType.success);
                await queueService.stopAndClearQueue();
              } else {
                await openPlayerScreen();
              }
              return false;
            },
            dismissThresholds: const {DismissDirection.up: 0.15, DismissDirection.down: 0.7},
            child: Container(
              clipBehavior: Clip.antiAlias,
              decoration: getShadow(context),
              foregroundDecoration: getWindowEdge(context),
              //TODO use a PageView instead of a Dismissible, and only wrap dynamic items (not the buttons)
              child: Dismissible(
                key: const Key("NowPlayingBar"),
                direction: ref.watch(finampSettingsProvider.disableGesture)
                    ? DismissDirection.none
                    : DismissDirection.horizontal,
                confirmDismiss: (direction) async {
                  if (direction == DismissDirection.endToStart) {
                    FeedbackHelper.feedback(FeedbackType.light);
                    await audioHandler.skipToNext();
                  } else {
                    FeedbackHelper.feedback(FeedbackType.light);
                    await audioHandler.skipToPrevious(forceSkip: true);
                  }
                  return false;
                },
                child: Material(
                  clipBehavior: Clip.antiAlias,
                  color: ColorScheme.of(context).surfaceContainer,
                  elevation: 0,
                  // If we have a media item and the player hasn't finished, show
                  // the now playing bar.
                  child: //TODO move into separate component and share with queue list
                  Container(
                    width: MediaQuery.widthOf(context),
                    height: albumImageSize,
                    padding: EdgeInsets.zero,
                    clipBehavior: Clip.antiAlias,
                    decoration: ShapeDecoration(color: remainingPartBackgroundColor, shape: const Border()),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.start,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Stack(
                          alignment: Alignment.center,
                          children: [
                            if (ref.watch(finampSettingsProvider.showProgressOnNowPlayingBar))
                              Positioned.fill(child: ColoredBox(color: remainingPartBackgroundColor)),
                            AlbumImage(
                              placeholderBuilder: (_) => const SizedBox.shrink(),
                              imageListenable: currentAlbumImageProvider,
                              borderRadius: BorderRadius.zero,
                            ),
                            if (!showPlayButtonAtEnd)
                              AudioFadeProgressVisualizerContainer(
                                key: const Key("AlbumArtAudioFadeProgressVisualizer"),
                                width: albumImageSize,
                                height: albumImageSize,
                                borderRadius: BorderRadius.zero,
                                child: IconButton(
                                  tooltip: AppLocalizations.of(context)!.togglePlaybackButtonTooltip,
                                  onPressed: () {
                                    FeedbackHelper.feedback(FeedbackType.light);
                                    unawaited(audioHandler.togglePlayback());
                                  },
                                  color: Colors.white,
                                  icon: Icon(
                                    showPauseButton ? TablerIcons.player_pause : TablerIcons.player_play,
                                    shadows: <Shadow>[Shadow(color: Colors.black, blurRadius: 10.0)],
                                    size: 32,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        Expanded(
                          child: Stack(
                            children: [
                              if (ref.watch(finampSettingsProvider.showProgressOnNowPlayingBar))
                                Positioned.fill(
                                  child: StreamBuilder<Duration>(
                                    stream: AudioService.position,
                                    initialData: audioHandler.playbackState.value.position,
                                    builder: (context, snapshot) {
                                      if (snapshot.hasData) {
                                        playbackPosition = snapshot.data;
                                        var itemLength = currentTrack.item.duration;
                                        return FractionallySizedBox(
                                          alignment: AlignmentDirectional.centerStart,
                                          widthFactor: itemLength == null
                                              ? 0
                                              : max(0, playbackPosition!.inMilliseconds / itemLength.inMilliseconds),
                                          // A phosphor strip along the bottom edge, so the text stays ink on pane.
                                          child: Align(
                                            alignment: Alignment.bottomCenter,
                                            child: SizedBox(
                                              height: 4,
                                              width: double.infinity,
                                              child: ColoredBox(color: elapsedPartBackgroundColor),
                                            ),
                                          ),
                                        );
                                      } else {
                                        return SizedBox.shrink();
                                      }
                                    },
                                  ),
                                ),
                              Row(
                                mainAxisSize: MainAxisSize.max,
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    // An ink well too, so a keyboard or remote can open the player screen. It gets
                                    // its own material, since the bar's colour would cover the focus.
                                    child: Material(
                                      type: MaterialType.transparency,
                                      child: InkWell(
                                        focusNode: focusNode,
                                        onTap: () async => await openPlayerScreen(),
                                        child: Container(
                                          height: albumImageSize,
                                          padding: const EdgeInsets.only(left: 12, right: 4),
                                          child: Column(
                                            mainAxisSize: MainAxisSize.min,
                                            mainAxisAlignment: MainAxisAlignment.center,
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              OneLineMarqueeHelper(
                                                key: ValueKey(currentTrack.item.id),
                                                text: currentTrack.item.title,
                                                style: TextStyle(
                                                  fontSize: 14.5,
                                                  height: 26 / 20,
                                                  color: primaryTextColor,
                                                  fontWeight: Theme.brightnessOf(context) == Brightness.light
                                                      ? FontWeight.w500
                                                      : FontWeight.w600,
                                                ),
                                              ),
                                              const SizedBox(height: 4),
                                              Row(
                                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                                children: [
                                                  Expanded(
                                                    child: Text(
                                                      processArtist(currentTrack.item.artist, context),
                                                      style: TextStyle(
                                                        color: primaryTextColor,
                                                        fontSize: 13,
                                                        fontWeight: FontWeight.w400,
                                                        overflow: TextOverflow.ellipsis,
                                                      ),
                                                    ),
                                                  ),
                                                  StreamBuilder<Duration>(
                                                    stream: AudioService.position,
                                                    initialData: audioHandler.playbackState.value.position,
                                                    builder: (context, snapshot) {
                                                      if (snapshot.hasData) {
                                                        playbackPosition = snapshot.data;
                                                        final showRemaining = Platform.isIOS || Platform.isMacOS;
                                                        final positionFullMinutes =
                                                            (playbackPosition?.inMinutes ?? 0) % 60;
                                                        final positionFullHours = (playbackPosition?.inHours ?? 0);
                                                        final positionSeconds = (playbackPosition?.inSeconds ?? 0) % 60;
                                                        final durationFullHours =
                                                            (currentTrack.item.duration?.inHours ?? 0);
                                                        final durationFullMinutes =
                                                            (currentTrack.item.duration?.inMinutes ?? 0) % 60;
                                                        final durationSeconds =
                                                            (currentTrack.item.duration?.inSeconds ?? 0) % 60;
                                                        return Semantics.fromProperties(
                                                          properties: SemanticsProperties(
                                                            label:
                                                                "${positionFullHours > 0 ? "$positionFullHours hours " : ""}${positionFullMinutes > 0 ? "$positionFullMinutes minutes " : ""}$positionSeconds seconds of ${durationFullHours > 0 ? "$durationFullHours hours " : ""}${durationFullMinutes > 0 ? "$durationFullMinutes minutes " : ""}$durationSeconds seconds",
                                                          ),
                                                          excludeSemantics: true,
                                                          container: true,
                                                          child: Row(
                                                            children: [
                                                              Text(
                                                                printDuration(
                                                                  showRemaining
                                                                      ? ((currentTrack.item.duration ?? Duration.zero) -
                                                                            (playbackPosition ?? Duration.zero))
                                                                      : playbackPosition,
                                                                  leadingZeroes: false,
                                                                  isRemaining: showRemaining,
                                                                ),
                                                                style: TextStyle(
                                                                  fontSize: 14,
                                                                  fontWeight: FontWeight.w400,
                                                                  color: primaryTextColor.withValues(alpha: 0.8),
                                                                  fontFeatures: const [
                                                                    // fixed-width digits
                                                                    FontFeature.tabularFigures(),
                                                                  ],
                                                                ),
                                                              ),
                                                              if (!showRemaining) ...[
                                                                const SizedBox(width: 2),
                                                                Text(
                                                                  '/',
                                                                  style: TextStyle(
                                                                    color: primaryTextColor.withValues(alpha: 0.8),
                                                                    fontSize: 14,
                                                                    fontWeight: FontWeight.w400,
                                                                    fontFeatures: const [
                                                                      // fixed-width digits
                                                                      FontFeature.tabularFigures(),
                                                                    ],
                                                                  ),
                                                                ),
                                                                const SizedBox(width: 2),
                                                                Text(
                                                                  // '3:44',
                                                                  (currentTrack.item.duration?.inHours ?? 0.0) >= 1.0
                                                                      ? "${currentTrack.item.duration?.inHours.toString()}:${((currentTrack.item.duration?.inMinutes ?? 0) % 60).toString().padLeft(2, '0')}:${((currentTrack.item.duration?.inSeconds ?? 0) % 60).toString().padLeft(2, '0')}"
                                                                      : "${currentTrack.item.duration?.inMinutes.toString()}:${((currentTrack.item.duration?.inSeconds ?? 0) % 60).toString().padLeft(2, '0')}",
                                                                  style: TextStyle(
                                                                    color: primaryTextColor.withValues(alpha: 0.8),
                                                                    fontSize: 14,
                                                                    fontWeight: FontWeight.w400,
                                                                    fontFeatures: const [
                                                                      // fixed-width digits
                                                                      FontFeature.tabularFigures(),
                                                                    ],
                                                                  ),
                                                                ),
                                                              ],
                                                            ],
                                                          ),
                                                        );
                                                      } else {
                                                        return const SizedBox.shrink();
                                                      }
                                                    },
                                                  ),
                                                ],
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.only(right: 5.0),
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.end,
                                      children: [
                                        // Desktops have no volume buttons, so the bar gets a slider when there's room
                                        if (isDesktop && MediaQuery.widthOf(context) >= 600)
                                          NowPlayingVolumeSlider(color: primaryTextColor),
                                        AddToPlaylistButton(
                                          item: currentTrackBaseItem,
                                          queueItem: currentTrack,
                                          color: primaryTextColor,
                                          size: 28,
                                          visualDensity: const VisualDensity(horizontal: -4),
                                        ),

                                        if (showPlayButtonAtEnd)
                                          Stack(
                                            alignment: Alignment.center,
                                            children: [
                                              AudioFadeProgressVisualizerContainer(
                                                key: const Key("AlbumArtAudioFadeProgressVisualizer"),
                                                color: primaryTextColor.withValues(alpha: 0.5),
                                                width: albumImageSize,
                                                height: albumImageSize,
                                                borderRadius: BorderRadius.circular(12.0),
                                                child: SizedBox.shrink(),
                                              ),
                                              IconButton(
                                                tooltip: AppLocalizations.of(context)!.togglePlaybackButtonTooltip,
                                                onPressed: () {
                                                  FeedbackHelper.feedback(FeedbackType.light);
                                                  unawaited(audioHandler.togglePlayback());
                                                },
                                                color: primaryTextColor,
                                                visualDensity: VisualDensity.compact,
                                                icon: Icon(
                                                  showPauseButton ? TablerIcons.player_pause : TablerIcons.player_play,
                                                  size: 28,
                                                ),
                                              ),
                                            ],
                                          ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final queueService = GetIt.instance<QueueService>();

    return Hero(
      tag: "nowplaying",
      createRectTween: (from, to) => RectTween(begin: from, end: from),
      child: PlayerScreenTheme(
        // The now playing bar must be enclosed in a SafeArea at all times so that the enclosing scaffold properly adds
        // bottom padding, even if the now playing bar itself is empty.
        child: SafeArea(
          // use consumer to obtain ref of correct (player screen theme) ProviderContainer
          child: Consumer(
            builder: (context, ref, child) {
              ref.listen(currentTrackMetadataProvider, (metadataOrNull, metadata) {}); // keep provider alive
              return StreamBuilder<FinampQueueInfo?>(
                stream: queueService.getQueueStream(),
                initialData: queueService.getQueue(),
                builder: (context, snapshot) {
                  if (snapshot.hasData &&
                      snapshot.data!.saveState == SavedQueueState.loading &&
                      !usingPlayerSplitScreen) {
                    return buildLoadingQueueBar(ref, null);
                  } else if (snapshot.hasData &&
                      snapshot.data!.saveState == SavedQueueState.failed &&
                      !usingPlayerSplitScreen) {
                    return buildLoadingQueueBar(ref, queueService.retryQueueLoad);
                  } else if (snapshot.hasData && snapshot.data!.currentTrack != null && !usingPlayerSplitScreen) {
                    final bar = buildNowPlayingBar(ref, snapshot.data!.currentTrack!);
                    return isTelevision ? _RemoteFocusScope(child: bar) : bar;
                  } else {
                    return const SizedBox.shrink();
                  }
                },
              );
            },
          ),
        ),
      ),
    );
  }
}

/// Keeps a remote's left and right among the bar's buttons; up leaves it. The list above reaches down behind the bar,
/// past what's visible, so moving sideways could otherwise take the focus to items that can't be seen.
class _RemoteFocusScope extends StatefulWidget {
  const _RemoteFocusScope({required this.child});

  final Widget child;

  @override
  State<_RemoteFocusScope> createState() => _RemoteFocusScopeState();
}

class _RemoteFocusScopeState extends State<_RemoteFocusScope> {
  final _node = FocusScopeNode(
    debugLabel: "NowPlayingBar",
    // The focus goes to the buttons, not the bar as a whole
    skipTraversal: true,
    traversalEdgeBehavior: TraversalEdgeBehavior.parentScope,
    directionalTraversalEdgeBehavior: TraversalEdgeBehavior.parentScope,
  );

  @override
  void dispose() {
    _node.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FocusScope(node: _node, child: widget.child);
}
