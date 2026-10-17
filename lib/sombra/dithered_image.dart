import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

/// System S's 1-bit artwork: the picture reduced to [cells] x [cells] and dithered the way the old Macs did
/// it (Atkinson), drawn in [ink] on a transparent ground.
///
/// As on sombra.wtf, the dark theme draws the lit pixels and the light theme the unlit ones ([inkIsLit]),
/// so the picture reads the right way round on either pane.
@immutable
class DitheredImage extends ImageProvider<DitheredImage> {
  const DitheredImage(this.source, {required this.cells, required this.ink, required this.inkIsLit});

  final ImageProvider source;
  final int cells;
  final Color ink;
  final bool inkIsLit;

  /// System S draws a cell about every 2 logical pixels (96 cells for a cover, 22 for a 44px thumbnail).
  static int cellsFor(double logicalSize) => (logicalSize / 2).round().clamp(16, 256);

  @override
  Future<DitheredImage> obtainKey(ImageConfiguration configuration) => SynchronousFuture(this);

  @override
  ImageStreamCompleter loadImage(DitheredImage key, ImageDecoderCallback decode) => OneFrameImageStreamCompleter(
    _load(),
    informationCollector: () => [DiagnosticsProperty<ImageProvider>('Dithered image', this)],
  );

  Future<ImageInfo> _load() async {
    final original = await _resolve(source);
    try {
      final rgba = await _shrink(original.image, cells);
      final pixels = atkinson(rgba, cells, ink: ink, inkIsLit: inkIsLit);
      final completer = Completer<ui.Image>();
      ui.decodeImageFromPixels(pixels, cells, cells, ui.PixelFormat.rgba8888, completer.complete);
      return ImageInfo(image: await completer.future);
    } finally {
      original.dispose();
    }
  }

  static Future<ImageInfo> _resolve(ImageProvider provider) {
    final completer = Completer<ImageInfo>();
    final stream = provider.resolve(ImageConfiguration.empty);
    late final ImageStreamListener listener;
    listener = ImageStreamListener(
      (info, _) {
        stream.removeListener(listener);
        if (!completer.isCompleted) completer.complete(info);
      },
      onError: (error, stack) {
        stream.removeListener(listener);
        if (!completer.isCompleted) completer.completeError(error, stack);
      },
    );
    stream.addListener(listener);
    return completer.future;
  }

  /// The picture centre-cropped to a square and averaged down to [cells] x [cells] RGBA bytes.
  static Future<Uint8List> _shrink(ui.Image image, int cells) async {
    final recorder = ui.PictureRecorder();
    final side = image.width < image.height ? image.width : image.height;
    final source = Rect.fromLTWH((image.width - side) / 2, (image.height - side) / 2, side * 1.0, side * 1.0);
    Canvas(recorder).drawImageRect(
      image,
      source,
      Rect.fromLTWH(0, 0, cells * 1.0, cells * 1.0),
      Paint()..filterQuality = FilterQuality.medium,
    );
    final small = await recorder.endRecording().toImage(cells, cells);
    try {
      final data = await small.toByteData(format: ui.ImageByteFormat.rawRgba);
      return data!.buffer.asUint8List();
    } finally {
      small.dispose();
    }
  }

  /// Dithers [rgba] ([cells] x [cells]) to ink-or-nothing pixels, using System S's Atkinson diffusion.
  @visibleForTesting
  static Uint8List atkinson(Uint8List rgba, int cells, {required Color ink, required bool inkIsLit}) {
    final n = cells;
    final field = Float32List(n * n);
    for (var k = 0; k < n * n; k++) {
      field[k] = (0.2126 * rgba[k * 4] + 0.7152 * rgba[k * 4 + 1] + 0.0722 * rgba[k * 4 + 2]) / 255;
    }
    _stretch(field);

    final out = Uint8List(n * n * 4);
    final r = (ink.r * 255).round();
    final g = (ink.g * 255).round();
    final b = (ink.b * 255).round();
    final lit = inkIsLit ? 1 : 0;
    for (var j = 0; j < n; j++) {
      for (var i = 0; i < n; i++) {
        final k = j * n + i;
        final value = field[k] >= 0.5 ? 1 : 0;
        final error = (field[k] - value) / 8;
        if (i + 1 < n) field[k + 1] += error;
        if (i + 2 < n) field[k + 2] += error;
        if (j + 1 < n) {
          if (i > 0) field[k + n - 1] += error;
          field[k + n] += error;
          if (i + 1 < n) field[k + n + 1] += error;
        }
        if (j + 2 < n) field[k + 2 * n] += error;
        if (value != lit) continue;
        out[k * 4] = r;
        out[k * 4 + 1] = g;
        out[k * 4 + 2] = b;
        out[k * 4 + 3] = 255;
      }
    }
    return out;
  }

  /// Spreads the brightness over the full range (ignoring the extreme 2% at each end), so dull or dark
  /// artwork still dithers into a readable picture.
  static void _stretch(Float32List field) {
    final sorted = Float32List.fromList(field)..sort();
    final low = sorted[(sorted.length * 0.02).floor()];
    final high = sorted[(sorted.length * 0.98).floor().clamp(0, sorted.length - 1)];
    if (high - low < 0.1) return;
    for (var k = 0; k < field.length; k++) {
      field[k] = ((field[k] - low) / (high - low)).clamp(0.0, 1.0);
    }
  }

  @override
  bool operator ==(Object other) =>
      other is DitheredImage &&
      other.source == source &&
      other.cells == cells &&
      other.ink == ink &&
      other.inkIsLit == inkIsLit;

  @override
  int get hashCode => Object.hash(source, cells, ink, inkIsLit);

  @override
  String toString() => 'DitheredImage($source, cells: $cells)';
}
