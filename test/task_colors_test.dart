import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todo_app/settings/theme_provider.dart';
import 'package:todo_app/utils/task_colors.dart';
import 'package:todo_app/utils/task_palette.dart';
import 'package:todo_app/widgets/color_picker_row.dart';

/// WCAG contrast ratio between two opaque colours.
double _contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final (hi, lo) = la > lb ? (la, lb) : (lb, la);
  return (hi + 0.05) / (lo + 0.05);
}

/// [foreground] flattened over [background], as it is actually painted.
Color _shown(Color background, Color foreground) =>
    Color.alphaBlend(foreground, background);

void main() {
  group('onTaskColor', () {
    test('titles stay readable on every task swatch', () {
      for (final swatch in ColorPickerRow.colors) {
        final shown = _shown(swatch, onTaskColor(swatch));
        expect(
          _contrast(shown, swatch),
          greaterThanOrEqualTo(4.5),
          reason: 'title on ${swatch.toARGB32().toRadixString(16)}',
        );
      }
    });

    test('secondary content stays readable on every task swatch', () {
      for (final swatch in ColorPickerRow.colors) {
        final shown = _shown(swatch, onTaskColorMuted(swatch));
        expect(
          _contrast(shown, swatch),
          greaterThanOrEqualTo(3.0),
          reason: 'label on ${swatch.toARGB32().toRadixString(16)}',
        );
      }
    });

    test('a deep surface turns the text white, a light one black', () {
      expect(taskSurfaceIsDark(const Color(0xFF1A1A1A)), isTrue);
      expect(taskSurfaceIsDark(const Color(0xFF8B7CF6)), isFalse);
      expect(taskSurfaceIsDark(const Color(0xFFF6E1E9)), isFalse);
    });
  });

  group('the paired palette', () {
    test('the picker offers exactly the palette accents', () {
      expect(
        ColorPickerRow.colors.map((c) => c.toARGB32()),
        taskPalette.map((s) => s.accent.toARGB32()),
      );
    });

    test('every light tone really is a light one', () {
      for (final swatch in taskPalette) {
        expect(
          swatch.light.computeLuminance(),
          greaterThan(0.7),
          reason: 'light tone of ${swatch.accent.toARGB32().toRadixString(16)}',
        );
        expect(
          swatch.light.computeLuminance(),
          greaterThan(swatch.accent.computeLuminance()),
        );
      }
    });

    test('an accent resolves to its own light tone', () {
      for (final swatch in taskPalette) {
        expect(taskLightTone(swatch.accent), swatch.light);
        // A task that already holds a light tone keeps it.
        expect(taskLightTone(swatch.light), swatch.light);
      }
    });

    test('a colour from before the palette still gets a light tone', () {
      // Tasks saved under the previous palette hold colours in no family.
      const legacy = Color(0xFFE998A1);
      final light = taskLightTone(legacy);
      expect(light, isNot(legacy));
      expect(light.computeLuminance(), greaterThan(0.7));
    });

    test('the glyph on a half-empty pill reads on the light tone', () {
      for (final swatch in taskPalette) {
        final glyph = inkOn(swatch.light, swatch.accent, minContrast: 3);
        expect(
          _contrast(glyph, swatch.light),
          greaterThanOrEqualTo(3.0),
          reason: 'accent on ${swatch.light.toARGB32().toRadixString(16)}',
        );
      }
    });

    test('a white glyph on an accent is decoration, not text', () {
      // Deliberate: the marker's icon is white on every family, which is 1.6:1
      // on the yellow one. It reads by its shape, and nothing but icons is ever
      // drawn in it — a *label* on an accent has to go through onTaskColor.
      for (final swatch in taskPalette) {
        expect(_contrast(Colors.white, swatch.accent), lessThan(4.5));
        expect(
          _contrast(onTaskColor(swatch.accent), swatch.accent),
          greaterThanOrEqualTo(4.5),
        );
      }
    });
  });

  group('flattenOn', () {
    test('a white glass button over a deep card still takes dark text', () {
      // The habit card paints its buttons as white at 45% over the task colour.
      final glass = flattenOn(
        const Color(0xFFD33243),
        Colors.white.withValues(alpha: 0.45),
      );
      expect(taskSurfaceIsDark(glass), isFalse);
      expect(
        _contrast(_shown(glass, onTaskColor(glass)), glass),
        greaterThanOrEqualTo(4.5),
      );
    });
  });

  group('appColorPalette', () {
    test('every accent has a readable black-or-white foreground', () {
      for (final accent in appColorPalette) {
        final onAccent = accent.computeLuminance() > 0.179
            ? Colors.black
            : Colors.white;
        expect(
          _contrast(onAccent, accent),
          greaterThanOrEqualTo(4.5),
          reason: 'onPrimary for ${accent.toARGB32().toRadixString(16)}',
        );
      }
    });
  });
}
