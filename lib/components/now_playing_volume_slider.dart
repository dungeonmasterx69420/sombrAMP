import 'package:finamp/l10n/app_localizations.dart';
import 'package:finamp/services/finamp_settings_helper.dart';
import 'package:finamp/services/music_player_background_task.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';
import 'package:get_it/get_it.dart';

/// A compact volume control for the now playing bar on desktops, which have no volume buttons of their own.  The
/// speaker mutes and unmutes.
class NowPlayingVolumeSlider extends ConsumerStatefulWidget {
  const NowPlayingVolumeSlider({super.key, required this.color});

  final Color color;

  @override
  ConsumerState<NowPlayingVolumeSlider> createState() => _NowPlayingVolumeSliderState();
}

class _NowPlayingVolumeSliderState extends ConsumerState<NowPlayingVolumeSlider> {
  /// The volume to go back to when unmuting.
  double _volumeBeforeMute = 1.0;

  void _setVolume(double volume) => GetIt.instance<MusicPlayerBackgroundTask>().setVolume(volume);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final volume = ref.watch(finampSettingsProvider.currentVolume).clamp(0.0, 1.0);
    final muted = volume == 0;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: muted ? l10n.volumeUnmute : l10n.volumeMute,
          visualDensity: const VisualDensity(horizontal: -4),
          color: widget.color,
          icon: Icon(
            muted
                ? TablerIcons.volume_3
                : volume < 0.5
                ? TablerIcons.volume_2
                : TablerIcons.volume,
            size: 22,
          ),
          onPressed: () {
            if (muted) {
              _setVolume(_volumeBeforeMute == 0 ? 1.0 : _volumeBeforeMute);
            } else {
              _volumeBeforeMute = volume;
              _setVolume(0);
            }
          },
        ),
        SizedBox(
          width: 120,
          child: Slider(
            value: volume,
            label: l10n.outputMenuVolumeSectionTitle,
            semanticFormatterCallback: (value) => "${(value * 100).round()}%",
            onChanged: _setVolume,
          ),
        ),
      ],
    );
  }
}
