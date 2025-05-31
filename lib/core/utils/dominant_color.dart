import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;

/// Extracts the N most dominant colors from an image URL.
/// Returns a list of [Color]s.
Future<List<Color>> getDominantColorsFromUrl(String url,
    {int colorCount = 6}) async {
  try {
    final response = await http.get(Uri.parse(url));
    if (response.statusCode != 200) return [];

    final bytes = response.bodyBytes;
    final image = img.decodeImage(bytes);
    if (image == null) return [];

    // Downscale for performance but keep enough detail
    final thumb = img.copyResize(image, width: 150, height: 150);

    // Use a map to count color frequencies with better quantization
    final Map<int, int> colorCounts = {};

    for (var y = 0; y < thumb.height; y++) {
      for (var x = 0; x < thumb.width; x++) {
        final pixel = thumb.getPixel(x, y);

        // Extract RGB values
        final r = pixel.r.toInt();
        final g = pixel.g.toInt();
        final b = pixel.b.toInt();

        // Skip very dark or very light pixels early
        final brightness = (r + g + b) / 3;
        if (brightness < 20 || brightness > 235) continue;

        // Less aggressive quantization - group similar colors
        final quantR = (r ~/ 15) * 15;
        final quantG = (g ~/ 15) * 15;
        final quantB = (b ~/ 15) * 15;

        final colorKey = (quantR << 16) | (quantG << 8) | quantB;
        colorCounts[colorKey] = (colorCounts[colorKey] ?? 0) + 1;
      }
    }

    if (colorCounts.isEmpty) return [];

    // Sort by frequency and get the most common colors
    final sortedColors = colorCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final List<Color> palette = [];

    for (final entry in sortedColors) {
      if (palette.length >= colorCount) break;

      final r = (entry.key >> 16) & 0xFF;
      final g = (entry.key >> 8) & 0xFF;
      final b = entry.key & 0xFF;

      final color = Color.fromARGB(255, r, g, b);

      // Check if this color is too similar to existing colors
      bool tooSimilar = false;
      for (final existing in palette) {
        if (_colorsAreSimilar(color, existing)) {
          tooSimilar = true;
          break;
        }
      }

      if (!tooSimilar) {
        palette.add(color);
      }
    }

    // If we don't have enough colors, add some backup colors
    if (palette.length < 3 && sortedColors.isNotEmpty) {
      // Add the most frequent color even if it was filtered
      final topColor = sortedColors.first;
      final r = (topColor.key >> 16) & 0xFF;
      final g = (topColor.key >> 8) & 0xFF;
      final b = topColor.key & 0xFF;
      final fallback = Color.fromARGB(255, r, g, b);

      if (palette.isEmpty ||
          !palette.any((c) => _colorsAreSimilar(c, fallback))) {
        palette.insert(0, fallback);
      }
    }

    return palette;
  } catch (_) {
    return [];
  }
}

/// Check if two colors are too similar
bool _colorsAreSimilar(Color c1, Color c2) {
  const threshold = 40; // Minimum difference
  return (c1.r * 255.round() - c2.r * 255.round()).abs() < threshold &&
      (c1.g * 255.round() - c2.g * 255.round()).abs() < threshold &&
      (c1.b * 255.round() - c2.b * 255.round()).abs() < threshold;
}
