import 'dart:typed_data';

import 'package:finamp/sombra/dithered_image.dart';
import 'package:finamp/sombra/system_s.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List grey(int cells, double Function(int i, int j) level) {
  final rgba = Uint8List(cells * cells * 4);
  for (var j = 0; j < cells; j++) {
    for (var i = 0; i < cells; i++) {
      final v = (level(i, j) * 255).round();
      final k = (j * cells + i) * 4;
      rgba
        ..[k] = v
        ..[k + 1] = v
        ..[k + 2] = v
        ..[k + 3] = 255;
    }
  }
  return rgba;
}

int inked(Uint8List pixels) {
  var count = 0;
  for (var k = 3; k < pixels.length; k += 4) {
    if (pixels[k] == 255) count++;
  }
  return count;
}

void main() {
  const ink = Color(0xFFEDEDED);

  group('DitheredImage.atkinson', () {
    test('draws only ink or nothing', () {
      final pixels = DitheredImage.atkinson(grey(32, (i, j) => i / 31), 32, ink: ink, inkIsLit: true);
      for (var k = 0; k < pixels.length; k += 4) {
        final isInk = pixels[k + 3] == 255 && pixels[k] == 0xED && pixels[k + 1] == 0xED && pixels[k + 2] == 0xED;
        final isClear = pixels[k + 3] == 0;
        expect(isInk || isClear, isTrue);
      }
    });

    test('white is all ink on the dark theme and none on the light one', () {
      final white = grey(16, (_, _) => 1);
      expect(inked(DitheredImage.atkinson(white, 16, ink: ink, inkIsLit: true)), 16 * 16);
      expect(inked(DitheredImage.atkinson(white, 16, ink: ink, inkIsLit: false)), 0);
    });

    test('a left-to-right ramp gets denser towards the light end', () {
      const n = 64;
      final pixels = DitheredImage.atkinson(grey(n, (i, _) => i / (n - 1)), n, ink: ink, inkIsLit: true);
      int column(int from, int to) {
        var count = 0;
        for (var j = 0; j < n; j++) {
          for (var i = from; i < to; i++) {
            if (pixels[(j * n + i) * 4 + 3] == 255) count++;
          }
        }
        return count;
      }

      expect(column(0, 16), lessThan(column(24, 40)));
      expect(column(24, 40), lessThan(column(48, 64)));
    });
  });

  group('System S theme', () {
    test('dark is ink on black with amber for what is live', () {
      final theme = systemSThemeData(Brightness.dark);
      final s = theme.extension<SystemSTheme>()!;
      expect(theme.colorScheme.surface, const Color(0xFF0A0A0A));
      expect(theme.colorScheme.onSurface, const Color(0xFFEDEDED));
      expect(theme.colorScheme.primary, const Color(0xFFEDEDED));
      expect(s.phosphor, SystemSPhosphor.amber.glow);
      expect(theme.progressIndicatorTheme.color, SystemSPhosphor.amber.glow);
    });

    test('light uses the paper palette and the darker phosphor ink', () {
      final theme = systemSThemeData(Brightness.light, accent: SystemSPhosphor.cyan.glow);
      final s = theme.extension<SystemSTheme>()!;
      expect(theme.colorScheme.surface, const Color(0xFFCFCFCF));
      expect(s.palette.pane, const Color(0xFFFFFFFF));
      expect(s.phosphor, SystemSPhosphor.cyan.glow);
      expect(s.phosphorInk, SystemSPhosphor.cyan.inkOnLight);
    });

    test('AMOLED only blackens the dark theme', () {
      expect(SystemSTheme.resolve(Brightness.dark, amoled: true).palette.pane, const Color(0xFF000000));
      expect(SystemSTheme.resolve(Brightness.light, amoled: true).palette.pane, const Color(0xFFFFFFFF));
    });
  });
}
