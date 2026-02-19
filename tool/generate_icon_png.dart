// Dart script to render the Leggio logo as a 1024x1024 PNG.
// Uses the `image` package (transitive dep of flutter_launcher_icons).
//
// Run: dart run tool/generate_icon_png.dart

import 'dart:io';
import 'dart:math';
import 'package:image/image.dart' as img;

void main() {
  const size = 1024;
  final image = img.Image(width: size, height: size);

  // Blue gradient colors
  const c1r = 0x15, c1g = 0x65, c1b = 0xC0; // #1565C0
  const c2r = 0x0D, c2g = 0x47, c2b = 0xA1; // #0D47A1

  img.Color blueAt(double x, double y) {
    final t = ((x + y) / (2 * size)).clamp(0.0, 1.0);
    final r = (c1r + (c2r - c1r) * t).round();
    final g = (c1g + (c2g - c1g) * t).round();
    final b = (c1b + (c2b - c1b) * t).round();
    return img.ColorRgba8(r, g, b, 255);
  }

  final blue = img.ColorRgba8(0x15, 0x65, 0xC0, 255);
  final darkBlue = img.ColorRgba8(0x0D, 0x47, 0xA1, 255);

  // Scale factor from 100x100 SVG viewBox to 1024x1024
  const s = size / 100.0;

  // Helper to draw a thick line
  void drawThickLine(
      double x1, double y1, double x2, double y2, double thickness, img.Color color) {
    final dx = x2 - x1;
    final dy = y2 - y1;
    final len = sqrt(dx * dx + dy * dy);
    if (len == 0) return;
    final nx = -dy / len * thickness / 2;
    final ny = dx / len * thickness / 2;

    // Draw filled polygon (simple rasterization)
    final steps = (len * 2).ceil();
    for (int i = 0; i <= steps; i++) {
      final t = i / steps;
      final cx = x1 + dx * t;
      final cy = y1 + dy * t;
      for (double w = -thickness / 2; w <= thickness / 2; w += 0.5) {
        final px = (cx + (-dy / len) * w).round();
        final py = (cy + (dx / len) * w).round();
        if (px >= 0 && px < size && py >= 0 && py < size) {
          image.setPixel(px, py, color);
        }
      }
    }
  }

  // Draw filled circle
  void fillCircle(double cx, double cy, double r, img.Color color) {
    final x0 = (cx - r).floor();
    final x1 = (cx + r).ceil();
    final y0 = (cy - r).floor();
    final y1 = (cy + r).ceil();
    for (int y = y0; y <= y1; y++) {
      for (int x = x0; x <= x1; x++) {
        if (x >= 0 && x < size && y >= 0 && y < size) {
          final dx = x - cx;
          final dy = y - cy;
          if (dx * dx + dy * dy <= r * r) {
            image.setPixel(x, y, color);
          }
        }
      }
    }
  }

  // Quadratic bezier helper
  List<List<double>> quadBezier(
      double x0, double y0, double cx, double cy, double x1, double y1, int steps) {
    final pts = <List<double>>[];
    for (int i = 0; i <= steps; i++) {
      final t = i / steps;
      final mt = 1 - t;
      final px = mt * mt * x0 + 2 * mt * t * cx + t * t * x1;
      final py = mt * mt * y0 + 2 * mt * t * cy + t * t * y1;
      pts.add([px, py]);
    }
    return pts;
  }

  // Cubic bezier helper
  List<List<double>> cubicBezier(double x0, double y0, double cx1, double cy1,
      double cx2, double cy2, double x1, double y1, int steps) {
    final pts = <List<double>>[];
    for (int i = 0; i <= steps; i++) {
      final t = i / steps;
      final mt = 1 - t;
      final px = mt * mt * mt * x0 +
          3 * mt * mt * t * cx1 +
          3 * mt * t * t * cx2 +
          t * t * t * x1;
      final py = mt * mt * mt * y0 +
          3 * mt * mt * t * cy1 +
          3 * mt * t * t * cy2 +
          t * t * t * y1;
      pts.add([px, py]);
    }
    return pts;
  }

  // Draw bezier curve with thickness
  void drawBezierPath(List<List<double>> pts, double thickness, img.Color color) {
    for (int i = 0; i < pts.length - 1; i++) {
      drawThickLine(pts[i][0], pts[i][1], pts[i + 1][0], pts[i + 1][1],
          thickness, color);
    }
  }

  // --- Draw the book outline ---
  // M42 28 C35 28, 20 25, 16 27 (left top)
  var pts = cubicBezier(42 * s, 28 * s, 35 * s, 28 * s, 20 * s, 25 * s, 16 * s, 27 * s, 80);
  drawBezierPath(pts, 3.5 * s, blue);

  // L16 72 (left side)
  drawThickLine(16 * s, 27 * s, 16 * s, 72 * s, 3.5 * s, blue);

  // C20 70, 35 72, 42 76 (bottom left curve)
  pts = cubicBezier(16 * s, 72 * s, 20 * s, 70 * s, 35 * s, 72 * s, 42 * s, 76 * s, 80);
  drawBezierPath(pts, 3.5 * s, blue);

  // C49 72, 62 70, 68 72 (bottom right curve)
  pts = cubicBezier(42 * s, 76 * s, 49 * s, 72 * s, 62 * s, 70 * s, 68 * s, 72 * s, 80);
  drawBezierPath(pts, 3.5 * s, blue);

  // L68 27 (right side)
  drawThickLine(68 * s, 72 * s, 68 * s, 27 * s, 3.5 * s, blue);

  // C62 25, 49 28, 42 28 (right top)
  pts = cubicBezier(68 * s, 27 * s, 62 * s, 25 * s, 49 * s, 28 * s, 42 * s, 28 * s, 80);
  drawBezierPath(pts, 3.5 * s, blue);

  // Book spine
  drawThickLine(42 * s, 28 * s, 42 * s, 76 * s, 2 * s, blue);

  // --- Treble clef ---
  // C segments approximated
  pts = cubicBezier(29 * s, 34 * s, 32 * s, 34 * s, 34 * s, 37 * s, 34 * s, 41 * s, 60);
  drawBezierPath(pts, 2.5 * s, blue);
  pts = cubicBezier(34 * s, 41 * s, 34 * s, 45 * s, 31 * s, 47 * s, 29 * s, 50 * s, 60);
  drawBezierPath(pts, 2.5 * s, blue);
  pts = cubicBezier(29 * s, 50 * s, 29 * s, 52 * s, 30 * s, 54 * s, 32 * s, 53 * s, 60);
  drawBezierPath(pts, 2.5 * s, blue);
  pts = cubicBezier(32 * s, 53 * s, 34 * s, 52 * s, 33 * s, 49 * s, 30 * s, 48 * s, 60);
  drawBezierPath(pts, 2.5 * s, blue);
  pts = cubicBezier(30 * s, 48 * s, 27 * s, 47 * s, 25 * s, 49 * s, 26 * s, 53 * s, 60);
  drawBezierPath(pts, 2.5 * s, blue);
  pts = cubicBezier(26 * s, 53 * s, 27 * s, 58 * s, 30 * s, 61 * s, 29 * s, 65 * s, 60);
  drawBezierPath(pts, 2.5 * s, blue);

  // Dot at bottom of clef
  fillCircle(29 * s, 65 * s, 2 * s, blue);

  // --- Staff lines ---
  drawThickLine(46 * s, 42 * s, 64 * s, 40 * s, 1.5 * s, blue);
  drawThickLine(46 * s, 50 * s, 64 * s, 48 * s, 1.5 * s, blue);
  drawThickLine(46 * s, 58 * s, 64 * s, 56 * s, 1.5 * s, blue);

  // --- Quill (filled) ---
  // Build outline from Q beziers and fill
  final quillLeft = <List<double>>[];
  quillLeft.add([78 * s, 15 * s]);
  quillLeft.addAll(quadBezier(78 * s, 15 * s, 81 * s, 22 * s, 83 * s, 32 * s, 40));
  quillLeft.addAll(quadBezier(83 * s, 32 * s, 85 * s, 42 * s, 81 * s, 52 * s, 40));
  quillLeft.add([79 * s, 62 * s]);

  final quillRight = <List<double>>[];
  quillRight.add([79 * s, 62 * s]);
  quillRight.add([77 * s, 52 * s]);
  quillRight.addAll(quadBezier(77 * s, 52 * s, 75 * s, 42 * s, 76 * s, 32 * s, 40));
  quillRight.addAll(quadBezier(76 * s, 32 * s, 77 * s, 22 * s, 78 * s, 15 * s, 40));

  // Fill quill using scanline
  final allQuillPts = [...quillLeft, ...quillRight];
  final minY = allQuillPts.map((p) => p[1]).reduce(min).floor();
  final maxY = allQuillPts.map((p) => p[1]).reduce(max).ceil();

  // Build left and right edges
  for (int y = minY; y <= maxY; y++) {
    double? leftX, rightX;

    for (final edgePts in [quillLeft, quillRight]) {
      for (int i = 0; i < edgePts.length - 1; i++) {
        final y0 = edgePts[i][1];
        final y1 = edgePts[i + 1][1];
        if ((y0 <= y && y1 >= y) || (y1 <= y && y0 >= y)) {
          if ((y1 - y0).abs() < 0.001) continue;
          final t = (y - y0) / (y1 - y0);
          final x = edgePts[i][0] + t * (edgePts[i + 1][0] - edgePts[i][0]);
          if (leftX == null || x < leftX) leftX = x;
          if (rightX == null || x > rightX) rightX = x;
        }
      }
    }

    if (leftX != null && rightX != null) {
      for (int x = leftX.floor(); x <= rightX.ceil(); x++) {
        if (x >= 0 && x < size && y >= 0 && y < size) {
          image.setPixel(x, y, blueAt(x.toDouble(), y.toDouble()));
        }
      }
    }
  }

  // Quill stem
  drawThickLine(79 * s, 62 * s, 79 * s, 78 * s, 2 * s, darkBlue);

  // Save
  final outDir = Directory('assets/icon');
  if (!outDir.existsSync()) outDir.createSync(recursive: true);
  final png = img.encodePng(image);
  File('assets/icon/leggio-logo-blue.png').writeAsBytesSync(png);
  print('Generated assets/icon/leggio-logo-blue.png (${size}x$size)');
}
