import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/services.dart' show rootBundle;

/// A tiny TrueType reader, so slides can show REAL font data: the table
/// directory, cmap lookups, glyph ids, advances and quadratic outlines.
///
/// Values are for the font's default instance (variable fonts: default axis
/// values, e.g. Space Grotesk wght 300).
class FontData {
  FontData._(this.name, this.asset, this._d) {
    final n = _d.getUint16(4);
    for (var i = 0; i < n; i++) {
      final r = 12 + 16 * i;
      final tag = String.fromCharCodes(_d.buffer.asUint8List(_d.offsetInBytes + r, 4));
      tables[tag] = (_d.getUint32(r + 8), _d.getUint32(r + 12));
    }
    final head = tables['head']!.$1;
    unitsPerEm = _d.getUint16(head + 18);
    _longLoca = _d.getInt16(head + 50) == 1;
    final hhea = tables['hhea']!.$1;
    ascender = _d.getInt16(hhea + 4);
    descender = _d.getInt16(hhea + 6);
    lineGap = _d.getInt16(hhea + 8);
    _numHMetrics = _d.getUint16(hhea + 34);
    numGlyphs = _d.getUint16(tables['maxp']!.$1 + 4);
    _parseCmap();
    _parseFvar();
  }

  final String name;
  final String asset;
  final ByteData _d;

  /// tag → (offset, length)
  final Map<String, (int, int)> tables = {};
  late final int unitsPerEm;
  late final int ascender;
  late final int descender;
  late final int lineGap;
  late final int numGlyphs;
  late final int _numHMetrics;
  late final bool _longLoca;

  /// cmap: code point → glyph id.
  final Map<int, int> _cmap = {};

  /// cmap segments (format 4) or groups (format 12): start, end, first glyph.
  final List<CmapSegment> segments = [];
  int cmapFormat = 0;

  /// Variation axes: tag → (min, default, max).
  final Map<String, (double, double, double)> axes = {};

  static final Map<String, Future<FontData>> _cache = {};

  static Future<FontData> load(String asset, String name) =>
      _cache.putIfAbsent(asset, () async {
        final data = await rootBundle.load(asset);
        return FontData._(name, asset, data);
      });

  static Future<FontData> spaceGrotesk() =>
      load('assets/fonts/SpaceGrotesk.ttf', 'Space Grotesk');
  static Future<FontData> notoKufiArabic() =>
      load('assets/fonts/NotoKufiArabic.ttf', 'Noto Kufi Arabic');

  int get fileSize => _d.lengthInBytes;

  bool has(int codePoint) => (_cmap[codePoint] ?? 0) != 0;

  int glyphId(int codePoint) => _cmap[codePoint] ?? 0;

  /// The segment a code point falls in (for visualising the lookup).
  int segmentIndexOf(int codePoint) =>
      segments.indexWhere((s) => codePoint >= s.start && codePoint <= s.end);

  int advance(int gid) {
    final hmtx = tables['hmtx']!.$1;
    final i = gid < _numHMetrics ? gid : _numHMetrics - 1;
    return _d.getUint16(hmtx + 4 * i);
  }

  int leftSideBearing(int gid) {
    final hmtx = tables['hmtx']!.$1;
    if (gid < _numHMetrics) return _d.getInt16(hmtx + 4 * gid + 2);
    return _d.getInt16(hmtx + 4 * _numHMetrics + 2 * (gid - _numHMetrics));
  }

  void _parseCmap() {
    final cmap = tables['cmap']!.$1;
    final n = _d.getUint16(cmap + 2);
    int? off4;
    int? off12;
    for (var i = 0; i < n; i++) {
      final r = cmap + 4 + 8 * i;
      final pid = _d.getUint16(r);
      final eid = _d.getUint16(r + 2);
      final off = cmap + _d.getUint32(r + 4);
      final fmt = _d.getUint16(off);
      if (fmt == 12 && (pid == 3 && eid == 10 || pid == 0)) off12 ??= off;
      if (fmt == 4 && (pid == 3 && eid == 1 || pid == 0)) off4 ??= off;
    }
    if (off4 != null) {
      cmapFormat = 4;
      final o = off4;
      final segX2 = _d.getUint16(o + 6);
      final segs = segX2 ~/ 2;
      final ends = o + 14;
      final starts = ends + segX2 + 2;
      final deltas = starts + segX2;
      final ranges = deltas + segX2;
      for (var s = 0; s < segs; s++) {
        final end = _d.getUint16(ends + 2 * s);
        final start = _d.getUint16(starts + 2 * s);
        final delta = _d.getInt16(deltas + 2 * s);
        final rangeOff = _d.getUint16(ranges + 2 * s);
        if (start == 0xFFFF) continue;
        segments.add(CmapSegment(start, end, delta: delta, usesRange: rangeOff != 0));
        for (var c = start; c <= end; c++) {
          int g;
          if (rangeOff == 0) {
            g = (c + delta) & 0xFFFF;
          } else {
            final addr = ranges + 2 * s + rangeOff + 2 * (c - start);
            g = _d.getUint16(addr);
            if (g != 0) g = (g + delta) & 0xFFFF;
          }
          if (g != 0) _cmap[c] = g;
        }
      }
    }
    if (off12 != null) {
      cmapFormat = 12;
      segments.clear();
      final o = off12;
      final groups = _d.getUint32(o + 12);
      for (var i = 0; i < groups; i++) {
        final r = o + 16 + 12 * i;
        final start = _d.getUint32(r);
        final end = _d.getUint32(r + 4);
        final g0 = _d.getUint32(r + 8);
        segments.add(CmapSegment(start, end, firstGlyph: g0));
        for (var c = start; c <= end; c++) {
          _cmap[c] = g0 + (c - start);
        }
      }
    }
  }

  void _parseFvar() {
    final t = tables['fvar'];
    if (t == null) return;
    final o = t.$1;
    final axOff = _d.getUint16(o + 4);
    final count = _d.getUint16(o + 8);
    final size = _d.getUint16(o + 10);
    for (var a = 0; a < count; a++) {
      final p = o + axOff + a * size;
      final tag = String.fromCharCodes(_d.buffer.asUint8List(_d.offsetInBytes + p, 4));
      double f(int k) => _d.getInt32(p + 4 + 4 * k) / 65536;
      axes[tag] = (f(0), f(1), f(2));
    }
  }

  /// The ligatures a shaper makes by default (GSUB liga, clig, rlig: their
  /// plain ligature lookups), by first glyph: the other components and the
  /// ligature glyph, in the font's order (longest first). Space Grotesk:
  /// f f i, f i, f l … and t t → t_t.liga.
  late final Map<int, List<(List<int>, int)>> ligatures = _parseLigatures();

  /// The ligature [glyphs] start with at [at] (its glyph id and how many
  /// glyphs it takes), or null.
  (int, int)? ligatureAt(List<int> glyphs, [int at = 0]) {
    for (final (rest, lig) in ligatures[glyphs[at]] ?? const <(List<int>, int)>[]) {
      if (at + rest.length >= glyphs.length) continue;
      var ok = true;
      for (var k = 0; k < rest.length && ok; k++) {
        ok = glyphs[at + 1 + k] == rest[k];
      }
      if (ok) return (lig, rest.length + 1);
    }
    return null;
  }

  Map<int, List<(List<int>, int)>> _parseLigatures() {
    final out = <int, List<(List<int>, int)>>{};
    final t = tables['GSUB'];
    if (t == null) return out;
    final g = t.$1;
    final features = g + _d.getUint16(g + 6), lookups = g + _d.getUint16(g + 8);
    final wanted = <int>{};
    for (var i = 0; i < _d.getUint16(features); i++) {
      final r = features + 2 + 6 * i;
      final tag = String.fromCharCodes(_d.buffer.asUint8List(_d.offsetInBytes + r, 4));
      if (tag != 'liga' && tag != 'clig' && tag != 'rlig') continue;
      final f = features + _d.getUint16(r + 4);
      for (var k = 0; k < _d.getUint16(f + 2); k++) {
        wanted.add(_d.getUint16(f + 4 + 2 * k));
      }
    }
    for (final i in wanted.toList()..sort()) {
      final lookup = lookups + _d.getUint16(lookups + 2 + 2 * i);
      final type = _d.getUint16(lookup);
      for (var s = 0; s < _d.getUint16(lookup + 4); s++) {
        var sub = lookup + _d.getUint16(lookup + 6 + 2 * s), subType = type;
        if (type == 7) {
          // (An extension: the real subtable further on.)
          subType = _d.getUint16(sub + 2);
          sub += _d.getUint32(sub + 4);
        }
        if (subType != 4 || _d.getUint16(sub) != 1) continue;
        final firsts = _coverage(sub + _d.getUint16(sub + 2));
        for (var k = 0; k < _d.getUint16(sub + 4) && k < firsts.length; k++) {
          final set = sub + _d.getUint16(sub + 6 + 2 * k);
          for (var j = 0; j < _d.getUint16(set); j++) {
            final lig = set + _d.getUint16(set + 2 + 2 * j);
            final n = _d.getUint16(lig + 2);
            (out[firsts[k]] ??= []).add(([for (var q = 0; q < n - 1; q++) _d.getUint16(lig + 4 + 2 * q)], _d.getUint16(lig)));
          }
        }
      }
    }
    return out;
  }

  /// An OpenType coverage table's glyphs, in coverage index order.
  List<int> _coverage(int o) {
    if (_d.getUint16(o) == 1) return [for (var k = 0; k < _d.getUint16(o + 2); k++) _d.getUint16(o + 4 + 2 * k)];
    return [
      for (var k = 0; k < _d.getUint16(o + 2); k++)
        for (var gid = _d.getUint16(o + 4 + 6 * k); gid <= _d.getUint16(o + 6 + 6 * k); gid++) gid,
    ];
  }

  (int, int) _glyphRange(int gid) {
    final loca = tables['loca']!.$1;
    final glyf = tables['glyf']!.$1;
    if (_longLoca) {
      return (glyf + _d.getUint32(loca + 4 * gid), glyf + _d.getUint32(loca + 4 * gid + 4));
    }
    return (glyf + 2 * _d.getUint16(loca + 2 * gid), glyf + 2 * _d.getUint16(loca + 2 * gid + 2));
  }

  /// Quadratic outline of a glyph in font units (y up).
  GlyphOutline outline(int gid, [int depth = 0]) {
    final (start, end) = _glyphRange(gid);
    if (end <= start || depth > 4) return const GlyphOutline([], Rect.zero);
    final nContours = _d.getInt16(start);
    final bounds = Rect.fromLTRB(
      _d.getInt16(start + 2).toDouble(),
      _d.getInt16(start + 4).toDouble(),
      _d.getInt16(start + 6).toDouble(),
      _d.getInt16(start + 8).toDouble(),
    );
    if (nContours >= 0) return GlyphOutline(_simple(start, nContours), bounds);
    return GlyphOutline(_composite(start + 10, depth), bounds);
  }

  List<List<OutlinePoint>> _simple(int start, int nContours) {
    var p = start + 10;
    final ends = <int>[];
    for (var i = 0; i < nContours; i++) {
      ends.add(_d.getUint16(p));
      p += 2;
    }
    if (ends.isEmpty) return [];
    final nPts = ends.last + 1;
    final instrLen = _d.getUint16(p);
    p += 2 + instrLen;
    final flags = <int>[];
    while (flags.length < nPts) {
      final f = _d.getUint8(p++);
      flags.add(f);
      if (f & 8 != 0) {
        final rep = _d.getUint8(p++);
        for (var r = 0; r < rep; r++) {
          flags.add(f);
        }
      }
    }
    final xs = List<int>.filled(nPts, 0);
    final ys = List<int>.filled(nPts, 0);
    var v = 0;
    for (var i = 0; i < nPts; i++) {
      final f = flags[i];
      if (f & 2 != 0) {
        final d = _d.getUint8(p++);
        v += (f & 16 != 0) ? d : -d;
      } else if (f & 16 == 0) {
        v += _d.getInt16(p);
        p += 2;
      }
      xs[i] = v;
    }
    v = 0;
    for (var i = 0; i < nPts; i++) {
      final f = flags[i];
      if (f & 4 != 0) {
        final d = _d.getUint8(p++);
        v += (f & 32 != 0) ? d : -d;
      } else if (f & 32 == 0) {
        v += _d.getInt16(p);
        p += 2;
      }
      ys[i] = v;
    }
    final contours = <List<OutlinePoint>>[];
    var s = 0;
    for (final e in ends) {
      contours.add([
        for (var i = s; i <= e; i++)
          OutlinePoint(xs[i].toDouble(), ys[i].toDouble(), flags[i] & 1 != 0),
      ]);
      s = e + 1;
    }
    return contours;
  }

  List<List<OutlinePoint>> _composite(int p, int depth) {
    final out = <List<OutlinePoint>>[];
    while (true) {
      final flags = _d.getUint16(p);
      final gid = _d.getUint16(p + 2);
      p += 4;
      double dx;
      double dy;
      if (flags & 1 != 0) {
        dx = _d.getInt16(p).toDouble();
        dy = _d.getInt16(p + 2).toDouble();
        p += 4;
      } else {
        dx = _d.getInt8(p).toDouble();
        dy = _d.getInt8(p + 1).toDouble();
        p += 2;
      }
      if (flags & 2 == 0) {
        dx = 0;
        dy = 0; // point matching: not supported, place at origin
      }
      var a = 1.0, b = 0.0, c = 0.0, d = 1.0;
      double f2(int o) => _d.getInt16(o) / 16384;
      if (flags & 8 != 0) {
        a = d = f2(p);
        p += 2;
      } else if (flags & 0x40 != 0) {
        a = f2(p);
        d = f2(p + 2);
        p += 4;
      } else if (flags & 0x80 != 0) {
        a = f2(p);
        b = f2(p + 2);
        c = f2(p + 4);
        d = f2(p + 6);
        p += 8;
      }
      for (final contour in outline(gid, depth + 1).contours) {
        out.add([
          for (final pt in contour)
            OutlinePoint(pt.x * a + pt.y * c + dx, pt.x * b + pt.y * d + dy, pt.onCurve),
        ]);
      }
      if (flags & 0x20 == 0) break;
    }
    return out;
  }
}

class CmapSegment {
  const CmapSegment(this.start, this.end, {this.delta = 0, this.usesRange = false, this.firstGlyph});

  final int start;
  final int end;
  final int delta;
  final bool usesRange;
  final int? firstGlyph;
}

class OutlinePoint {
  const OutlinePoint(this.x, this.y, this.onCurve);

  final double x;
  final double y;
  final bool onCurve;
}

class GlyphOutline {
  const GlyphOutline(this.contours, this.bounds);

  /// Contours of points in font units, y up.
  final List<List<OutlinePoint>> contours;
  final Rect bounds;

  int get pointCount => contours.fold(0, (a, c) => a + c.length);

  /// A Flutter path: [scale] px per font unit, [origin] = pen position on the
  /// baseline (y flipped to screen space).
  Path toPath({required double scale, Offset origin = Offset.zero}) {
    Offset map(double x, double y) => Offset(origin.dx + x * scale, origin.dy - y * scale);
    final path = Path();
    for (final c in contours) {
      if (c.isEmpty) continue;
      final pts = [for (final p in c) (map(p.x, p.y), p.onCurve)];
      // Start on an on-curve point, or on the implied midpoint of two offs.
      var first = pts.indexWhere((p) => p.$2);
      Offset start;
      List<(Offset, bool)> seq;
      if (first < 0) {
        start = (pts.last.$1 + pts.first.$1) / 2;
        seq = pts;
      } else {
        start = pts[first].$1;
        seq = [...pts.sublist(first + 1), ...pts.sublist(0, first)];
      }
      path.moveTo(start.dx, start.dy);
      Offset? ctrl;
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
      if (ctrl != null) {
        path.quadraticBezierTo(ctrl.dx, ctrl.dy, start.dx, start.dy);
      }
      path.close();
    }
    return path;
  }
}
