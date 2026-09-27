import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:slug/slug.dart';

SlugFont testFont(String file) {
  final dir = Directory.current.path.endsWith('test') ? 'fonts' : 'test/fonts';
  return SlugFont.fromBytes(File('$dir/$file').readAsBytesSync(), debugName: file);
}

SlugFont spaceGrotesk() => testFont('SpaceGrotesk.ttf');
SlugFont notoJp() => testFont('NotoSansJP-case.ttf');

/// The glyph outline as a Flutter path, built straight from the TrueType
/// points (independently of the encoder): pen at [pen], [scale] px per unit.
ui.Path glyphFillPath(SlugFont font, int gid, ui.Offset pen, double scale) {
  ui.Offset map(SlugPoint p) => ui.Offset(pen.dx + p.x * scale, pen.dy - p.y * scale);
  final path = ui.Path();
  for (final c in font.contours(gid)) {
    if (c.isEmpty) continue;
    final pts = [for (final p in c) (map(p), p.onCurve)];
    final first = pts.indexWhere((p) => p.$2);
    ui.Offset start;
    List<(ui.Offset, bool)> seq;
    if (first < 0) {
      start = (pts.last.$1 + pts.first.$1) / 2;
      seq = pts;
    } else {
      start = pts[first].$1;
      seq = [...pts.sublist(first + 1), ...pts.sublist(0, first)];
    }
    path.moveTo(start.dx, start.dy);
    ui.Offset? ctrl;
    for (final (p, on) in seq) {
      if (on) {
        if (ctrl != null) {
          path.quadraticBezierTo(ctrl.dx, ctrl.dy, p.dx, p.dy);
          ctrl = null;
        } else {
          path.lineTo(p.dx, p.dy);
        }
      } else {
        if (ctrl != null) {
          final mid = (ctrl + p) / 2;
          path.quadraticBezierTo(ctrl.dx, ctrl.dy, mid.dx, mid.dy);
        }
        ctrl = p;
      }
    }
    if (ctrl != null) path.quadraticBezierTo(ctrl.dx, ctrl.dy, start.dx, start.dy);
    path.close();
  }
  return path;
}

Future<Float64List> alphaOf(ui.Image image) async {
  final bytes = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
  final out = Float64List(image.width * image.height);
  for (var i = 0; i < out.length; i++) {
    out[i] = bytes.getUint8(4 * i + 3) / 255;
  }
  return out;
}

/// Renders [draw] into a w×h image and returns its alpha channel.
Future<Float64List> renderAlpha(int w, int h, void Function(ui.Canvas) draw) async {
  final rec = ui.PictureRecorder();
  final canvas = ui.Canvas(rec);
  draw(canvas);
  final pic = rec.endRecording();
  final img = await pic.toImage(w, h);
  pic.dispose();
  final a = await alphaOf(img);
  img.dispose();
  return a;
}

class Diff {
  Diff(this.mean, this.max, this.bad, this.speckles, this.pixels, this.ink);

  final double mean;
  final double max;

  /// Fraction of glyph-area pixels differing by more than 0.25.
  final double bad;

  /// Pixels that are solidly inside/outside in the reference (all 8
  /// neighbours agree) but wrong by more than 0.2 in the candidate.
  final int speckles;
  final int pixels;

  /// Relative difference of total coverage (ink), |Σgot − Σref| / Σref.
  final double ink;

  /// Thresholds for "small error": corners are where Slug's two 1-D box
  /// filters differ most from exact area coverage, and small glyphs are
  /// mostly corners.
  bool isCloseAt(double px) =>
      speckles == 0 &&
      mean < (px <= 12 ? 0.11 : 0.07) &&
      bad < 0.05 &&
      ink < (px <= 12 ? 0.15 : (px <= 24 ? 0.06 : 0.04));

  @override
  String toString() =>
      'mean ${mean.toStringAsFixed(4)} max ${max.toStringAsFixed(3)} '
      'bad ${(bad * 100).toStringAsFixed(2)}% ink ${(ink * 100).toStringAsFixed(2)}% '
      'speckles $speckles / $pixels px';
}

Diff compare(Float64List ref, Float64List got, int w, int h) {
  var sum = 0.0, mx = 0.0, bad = 0, speck = 0, area = 0, inkRef = 0.0, inkGot = 0.0;
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final i = y * w + x;
      final d = (ref[i] - got[i]).abs();
      inkRef += ref[i];
      inkGot += got[i];
      if (ref[i] > 0 || got[i] > 0) {
        area++;
        sum += d;
        if (d > 0.25) bad++;
      }
      mx = math.max(mx, d);
      if (x > 0 && y > 0 && x < w - 1 && y < h - 1) {
        final v = ref[i];
        if (v == 0 || v == 1) {
          var solid = true;
          for (var dy = -1; dy <= 1 && solid; dy++) {
            for (var dx = -1; dx <= 1; dx++) {
              if (ref[(y + dy) * w + x + dx] != v) {
                solid = false;
                break;
              }
            }
          }
          if (solid && d > 0.2) speck++;
        }
      }
    }
  }
  return Diff(
    area == 0 ? 0 : sum / area,
    mx,
    area == 0 ? 0 : bad / area,
    speck,
    area,
    inkRef == 0 ? 0 : (inkGot - inkRef).abs() / inkRef,
  );
}

class MaskStats {
  MaskStats(this.iou, this.centroidShift);

  /// Intersection over union of the two masks (coverage > 0.5).
  final double iou;

  /// Distance between the two coverage centroids, in pixels.
  final double centroidShift;

  @override
  String toString() =>
      'IoU ${iou.toStringAsFixed(3)} centroid shift ${centroidShift.toStringAsFixed(3)} px';
}

MaskStats maskStats(Float64List a, Float64List b, int w, int h) {
  var inter = 0, union = 0;
  var ax = 0.0, ay = 0.0, as = 0.0, bx = 0.0, by = 0.0, bs = 0.0;
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final i = y * w + x;
      final ma = a[i] > 0.5, mb = b[i] > 0.5;
      if (ma && mb) inter++;
      if (ma || mb) union++;
      ax += a[i] * x;
      ay += a[i] * y;
      as += a[i];
      bx += b[i] * x;
      by += b[i] * y;
      bs += b[i];
    }
  }
  final dx = ax / as - bx / bs, dy = ay / as - by / bs;
  return MaskStats(union == 0 ? 1 : inter / union, math.sqrt(dx * dx + dy * dy));
}
