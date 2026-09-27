import 'dart:typed_data';
import 'dart:ui' show Rect;

import 'package:flutter/services.dart' show AssetBundle, rootBundle;

/// A point of a TrueType contour, in font units (y up).
class SlugPoint {
  const SlugPoint(this.x, this.y, this.onCurve);

  final double x;
  final double y;
  final bool onCurve;
}

/// A tiny TrueType (`glyf`) reader: cmap, advances and quadratic outlines.
///
/// Adapted from the deck's `FontData` so the package is self-contained.
/// Outlines are the font's default instance (variable fonts: default axis
/// values). CFF (`.otf`) fonts are not supported.
class SlugFont {
  SlugFont.fromByteData(this._d, {this.debugName = 'font'}) : id = _nextId++ {
    final n = _d.getUint16(4);
    for (var i = 0; i < n; i++) {
      final r = 12 + 16 * i;
      final tag = String.fromCharCodes(_d.buffer.asUint8List(_d.offsetInBytes + r, 4));
      _tables[tag] = (_d.getUint32(r + 8), _d.getUint32(r + 12));
    }
    if (!_tables.containsKey('glyf') || !_tables.containsKey('loca')) {
      throw ArgumentError('$debugName: only TrueType (glyf) outlines are supported');
    }
    final head = _tables['head']!.$1;
    unitsPerEm = _d.getUint16(head + 18);
    _longLoca = _d.getInt16(head + 50) == 1;
    final hhea = _tables['hhea']!.$1;
    ascender = _d.getInt16(hhea + 4);
    descender = _d.getInt16(hhea + 6);
    _numHMetrics = _d.getUint16(hhea + 34);
    numGlyphs = _d.getUint16(_tables['maxp']!.$1 + 4);
    _parseCmap();
    _parseFvar();
  }

  /// Parses a font from raw bytes.
  factory SlugFont.fromBytes(Uint8List bytes, {String debugName = 'font'}) =>
      SlugFont.fromByteData(ByteData.sublistView(bytes), debugName: debugName);

  static int _nextId = 0;
  static final Map<String, Future<SlugFont>> _cache = {};

  /// Loads (and caches) a `.ttf` asset.
  static Future<SlugFont> load(String asset, {AssetBundle? bundle}) =>
      _cache.putIfAbsent(asset, () async {
        final data = await (bundle ?? rootBundle).load(asset);
        return SlugFont.fromByteData(data, debugName: asset);
      });

  /// Unique per instance; used in atlas cache keys.
  final int id;
  final String debugName;
  final ByteData _d;
  final Map<String, (int, int)> _tables = {};
  final Map<int, int> _cmap = {};
  late final int unitsPerEm;
  late final int ascender;
  late final int descender;
  late final int numGlyphs;
  late final int _numHMetrics;
  late final bool _longLoca;

  /// Variation axes (tag → default value). Outlines are always the default
  /// instance, so text laid out for them must use these values.
  final Map<String, double> defaultAxes = {};

  bool has(int codePoint) => (_cmap[codePoint] ?? 0) != 0;

  int glyphId(int codePoint) => _cmap[codePoint] ?? 0;

  /// Horizontal advance in font units.
  int advance(int gid) {
    final hmtx = _tables['hmtx']!.$1;
    final i = gid < _numHMetrics ? gid : _numHMetrics - 1;
    return _d.getUint16(hmtx + 4 * i);
  }

  void _parseCmap() {
    final cmap = _tables['cmap']!.$1;
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
    if (off12 != null) {
      final groups = _d.getUint32(off12 + 12);
      for (var i = 0; i < groups; i++) {
        final r = off12 + 16 + 12 * i;
        final start = _d.getUint32(r);
        final end = _d.getUint32(r + 4);
        final g0 = _d.getUint32(r + 8);
        for (var c = start; c <= end; c++) {
          _cmap[c] = g0 + (c - start);
        }
      }
      return;
    }
    if (off4 == null) return;
    final o = off4;
    final segX2 = _d.getUint16(o + 6);
    final ends = o + 14;
    final starts = ends + segX2 + 2;
    final deltas = starts + segX2;
    final ranges = deltas + segX2;
    for (var s = 0; s < segX2 ~/ 2; s++) {
      final end = _d.getUint16(ends + 2 * s);
      final start = _d.getUint16(starts + 2 * s);
      final delta = _d.getInt16(deltas + 2 * s);
      final rangeOff = _d.getUint16(ranges + 2 * s);
      if (start == 0xFFFF) continue;
      for (var c = start; c <= end; c++) {
        int g;
        if (rangeOff == 0) {
          g = (c + delta) & 0xFFFF;
        } else {
          g = _d.getUint16(ranges + 2 * s + rangeOff + 2 * (c - start));
          if (g != 0) g = (g + delta) & 0xFFFF;
        }
        if (g != 0) _cmap[c] = g;
      }
    }
  }

  void _parseFvar() {
    final t = _tables['fvar'];
    if (t == null) return;
    final o = t.$1;
    final axOff = _d.getUint16(o + 4);
    final count = _d.getUint16(o + 8);
    final size = _d.getUint16(o + 10);
    for (var a = 0; a < count; a++) {
      final p = o + axOff + a * size;
      final tag = String.fromCharCodes(_d.buffer.asUint8List(_d.offsetInBytes + p, 4));
      defaultAxes[tag] = _d.getInt32(p + 8) / 65536;
    }
  }

  (int, int) _glyphRange(int gid) {
    final loca = _tables['loca']!.$1;
    final glyf = _tables['glyf']!.$1;
    if (_longLoca) {
      return (glyf + _d.getUint32(loca + 4 * gid), glyf + _d.getUint32(loca + 4 * gid + 4));
    }
    return (glyf + 2 * _d.getUint16(loca + 2 * gid), glyf + 2 * _d.getUint16(loca + 2 * gid + 2));
  }

  final Map<int, List<List<SlugPoint>>> _outlines = {};

  /// Contours of a glyph in font units (y up). Composite glyphs are flattened.
  List<List<SlugPoint>> contours(int gid) =>
      _outlines.putIfAbsent(gid, () => _contours(gid, 0));

  /// Bounds of the glyph's points in font units (y up), or null if empty.
  Rect? bounds(int gid) {
    final cs = contours(gid);
    double? l, t, r, b;
    for (final c in cs) {
      for (final p in c) {
        l = l == null || p.x < l ? p.x : l;
        r = r == null || p.x > r ? p.x : r;
        b = b == null || p.y < b ? p.y : b;
        t = t == null || p.y > t ? p.y : t;
      }
    }
    return l == null ? null : Rect.fromLTRB(l, b!, r!, t!);
  }

  List<List<SlugPoint>> _contours(int gid, int depth) {
    if (gid < 0 || gid >= numGlyphs) return const [];
    final (start, end) = _glyphRange(gid);
    if (end <= start || depth > 4) return const [];
    final nContours = _d.getInt16(start);
    if (nContours >= 0) return _simple(start, nContours);
    return _composite(start + 10, depth);
  }

  List<List<SlugPoint>> _simple(int start, int nContours) {
    var p = start + 10;
    final ends = <int>[];
    for (var i = 0; i < nContours; i++) {
      ends.add(_d.getUint16(p));
      p += 2;
    }
    if (ends.isEmpty) return const [];
    final nPts = ends.last + 1;
    p += 2 + _d.getUint16(p); // skip instructions
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
    final out = <List<SlugPoint>>[];
    var s = 0;
    for (final e in ends) {
      out.add([
        for (var i = s; i <= e; i++) SlugPoint(xs[i].toDouble(), ys[i].toDouble(), flags[i] & 1 != 0),
      ]);
      s = e + 1;
    }
    return out;
  }

  List<List<SlugPoint>> _composite(int p, int depth) {
    final out = <List<SlugPoint>>[];
    while (true) {
      final flags = _d.getUint16(p);
      final gid = _d.getUint16(p + 2);
      p += 4;
      double dx, dy;
      if (flags & 1 != 0) {
        dx = _d.getInt16(p).toDouble();
        dy = _d.getInt16(p + 2).toDouble();
        p += 4;
      } else {
        dx = _d.getInt8(p).toDouble();
        dy = _d.getInt8(p + 1).toDouble();
        p += 2;
      }
      if (flags & 2 == 0) dx = dy = 0; // point matching: unsupported
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
      for (final contour in _contours(gid, depth + 1)) {
        out.add([
          for (final pt in contour)
            SlugPoint(pt.x * a + pt.y * c + dx, pt.x * b + pt.y * d + dy, pt.onCurve),
        ]);
      }
      if (flags & 0x20 == 0) break;
    }
    return out;
  }
}
