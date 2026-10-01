import 'dart:math' as math;
import 'dart:typed_data';

import 'package:characters/characters.dart';
import 'package:flutter/painting.dart' show TextDirection, TextPainter, TextSelection, TextSpan;
import 'package:text_slides/booth/raster.dart';

/// One letter of the name on the wall: a grapheme and the bricks that make
/// it.
class WallLetter {
  WallLetter._(this.text, this.glyph, this._start, this._end, this._boxL, this._boxR);

  /// The grapheme, and its place among the name's non-space graphemes (the
  /// order of the smooth letters).
  final String text;
  final int glyph;

  // Its code units in the name, and its layout box in raster columns.
  final int _start, _end;
  final double _boxL, _boxR;

  /// How many bricks it has, and where: columns [col0, col1] and rows from
  /// the bottom [row0, row1], inclusive.
  int bricks = 0;
  int col0 = 1 << 30, col1 = -1, row0 = 1 << 30, row1 = -1;

  /// Per row from the bottom: its leftmost and rightmost column (−1: none).
  late final Int16List left, right;

  /// How much the text engine kerned it against the letter before (in em;
  /// negative is tighter). 0 for the first letter and for pairs the font
  /// doesn't kern (CJK, mostly).
  double kernEm = 0;

  /// The letter before it on the wall ('' for the first).
  String before = '';

  /// Its outermost column on [side] (−1 left, +1 right) in the rows
  /// [a, b] (from the bottom), or its ink edge when it has none there.
  int edge(int side, int a, int b) {
    var best = -1;
    for (var rr = math.max(a, 0); rr <= math.min(b, left.length - 1); rr++) {
      final c = side < 0 ? left[rr] : right[rr];
      if (c < 0) continue;
      if (best < 0 || (side < 0 ? c < best : c > best)) best = c;
    }
    return best >= 0 ? best : (side < 0 ? col0 : col1);
  }
}

/// The name's letters on the wall: which bricks make each grapheme, and how
/// the text engine kerned each pair. A pure function of the raster (cached).
///
/// Bricks are shared out by ink rather than by layout box, so a letter keeps
/// the bits of ink that reach past its advance (the leg of a K under the
/// next letter's box): solid bricks (coverage ≥ ½) in connected blobs go to
/// the letter whose box holds most of the blob, and the anti-aliased edges
/// join the solid brick they touch.
class NameLetters {
  NameLetters._(this.r, this.letters, this.letterOf);

  static final _cache = Expando<NameLetters>('NameLetters');

  static NameLetters of(NameRaster r) => _cache[r] ??= _split(r);

  final NameRaster r;

  /// Left to right, those with bricks.
  final List<WallLetter> letters;

  /// Each raster brick's letter (an index into [letters]).
  final Int16List letterOf;

  int get length => letters.length;

  static NameLetters _split(NameRaster r) {
    final name = r.name;
    final tp = TextPainter(
      text: TextSpan(text: name, style: NameRaster.nameStyle(r.fontSize)),
      textDirection: TextDirection.ltr,
    )..layout();
    final cands = <WallLetter>[];
    var off = 0, glyph = 0;
    for (final ch in name.characters) {
      final start = off;
      off += ch.length;
      if (ch.trim().isEmpty) continue;
      final g = glyph++;
      final boxes = tp.getBoxesForSelection(TextSelection(baseOffset: start, extentOffset: off));
      if (boxes.isEmpty) continue;
      var l = double.infinity, rt = -double.infinity;
      for (final b in boxes) {
        l = math.min(l, b.left);
        rt = math.max(rt, b.right);
      }
      cands.add(WallLetter._(ch, g, start, off, l - r.inkOffset.dx, rt - r.inkOffset.dx));
    }
    tp.dispose();
    final n = r.bricks.length;
    if (cands.isEmpty) cands.add(WallLetter._(name, 0, 0, name.length, 0, r.cols.toDouble()));

    // The letter whose box holds column centre x (else the nearest box).
    int boxOf(double x) {
      var best = 0;
      var bestD = double.infinity;
      for (var k = 0; k < cands.length; k++) {
        final c = cands[k];
        final d = x < c._boxL ? c._boxL - x : (x > c._boxR ? x - c._boxR : 0.0);
        if (d < bestD) {
          bestD = d;
          best = k;
        }
      }
      return best;
    }

    final cols = r.cols, rows = r.rows;
    final grid = Int32List(cols * rows)..fillRange(0, cols * rows, -1);
    for (var i = 0; i < n; i++) {
      grid[r.bricks[i].row * cols + r.bricks[i].col] = i;
    }
    final owner = Int16List(n)..fillRange(0, n, -1);
    // Solid blobs, each to the letter most of it is in (or split by box
    // when two letters' ink touch).
    final seen = Uint8List(n);
    final blob = <int>[];
    final counts = Int32List(cands.length);
    for (var s = 0; s < n; s++) {
      if (seen[s] != 0 || r.bricks[s].cover < 0.5) continue;
      blob
        ..clear()
        ..add(s);
      seen[s] = 1;
      for (var q = 0; q < blob.length; q++) {
        final b = r.bricks[blob[q]];
        for (var dy = -1; dy <= 1; dy++) {
          for (var dx = -1; dx <= 1; dx++) {
            final x = b.col + dx, y = b.row + dy;
            if (x < 0 || y < 0 || x >= cols || y >= rows) continue;
            final j = grid[y * cols + x];
            if (j >= 0 && seen[j] == 0 && r.bricks[j].cover >= 0.5) {
              seen[j] = 1;
              blob.add(j);
            }
          }
        }
      }
      counts.fillRange(0, counts.length, 0);
      for (final i in blob) {
        counts[boxOf(r.bricks[i].col + 0.5)]++;
      }
      var top = 0;
      for (var k = 1; k < counts.length; k++) {
        if (counts[k] > counts[top]) top = k;
      }
      final whole = counts[top] >= blob.length * 0.75;
      for (final i in blob) {
        owner[i] = whole ? top : boxOf(r.bricks[i].col + 0.5);
      }
    }
    // The soft edges join the solid ink they touch (breadth first).
    final queue = <int>[
      for (var i = 0; i < n; i++)
        if (owner[i] >= 0) i,
    ];
    for (var q = 0; q < queue.length; q++) {
      final b = r.bricks[queue[q]];
      for (var dy = -1; dy <= 1; dy++) {
        for (var dx = -1; dx <= 1; dx++) {
          final x = b.col + dx, y = b.row + dy;
          if (x < 0 || y < 0 || x >= cols || y >= rows) continue;
          final j = grid[y * cols + x];
          if (j >= 0 && owner[j] < 0) {
            owner[j] = owner[queue[q]];
            queue.add(j);
          }
        }
      }
    }
    for (var i = 0; i < n; i++) {
      if (owner[i] < 0) owner[i] = boxOf(r.bricks[i].col + 0.5);
    }

    // Bounds and row edges.
    for (final c in cands) {
      c
        ..left = (Int16List(rows)..fillRange(0, rows, -1))
        ..right = (Int16List(rows)..fillRange(0, rows, -1));
    }
    for (var i = 0; i < n; i++) {
      final b = r.bricks[i], c = cands[owner[i]];
      final rb = rows - 1 - b.row;
      c
        ..bricks += 1
        ..col0 = math.min(c.col0, b.col)
        ..col1 = math.max(c.col1, b.col)
        ..row0 = math.min(c.row0, rb)
        ..row1 = math.max(c.row1, rb);
      if (c.left[rb] < 0 || b.col < c.left[rb]) c.left[rb] = b.col;
      if (b.col > c.right[rb]) c.right[rb] = b.col;
    }
    // Left to right, without the empty ones (a grapheme whose ink went to a
    // ligature with its neighbour).
    final order = [
      for (var k = 0; k < cands.length; k++)
        if (cands[k].bricks > 0) k,
    ]..sort((a, b) => cands[a].col0 != cands[b].col0 ? cands[a].col0 - cands[b].col0 : a - b);
    final index = Int16List(cands.length);
    for (var k = 0; k < order.length; k++) {
      index[order[k]] = k;
    }
    final letters = [for (final k in order) cands[k]];
    final letterOf = Int16List(n);
    for (var i = 0; i < n; i++) {
      letterOf[i] = index[owner[i]];
    }
    final widths = <String, double>{};
    for (var k = 1; k < letters.length; k++) {
      letters[k]
        ..before = letters[k - 1].text
        ..kernEm = _kern(name, letters[k - 1], letters[k], widths);
    }
    return NameLetters._(r, letters, letterOf);
  }

  /// Measured at a large size so rounding doesn't show.
  static const _probe = 400.0;

  /// The kerning between [a] and [b] (in em): the pair laid out together
  /// against each grapheme on its own.
  static double _kern(String name, WallLetter a, WallLetter b, Map<String, double> widths) {
    if (a._end > b._start) return 0; // not in reading order (right to left)
    final pair = name.substring(a._start, b._end);
    var alone = 0.0;
    for (final g in pair.characters) {
      alone += widths[g] ??= _width(g);
    }
    final d = (_width(pair) - alone) / _probe;
    // Bigger than any kern: joining scripts change shape when paired.
    return d.abs() < 0.004 || d.abs() > 0.25 ? 0 : d;
  }

  static double _width(String s) {
    final tp = TextPainter(
      text: TextSpan(text: s, style: NameRaster.nameStyle(_probe)),
      textDirection: TextDirection.ltr,
    )..layout();
    final w = tp.width;
    tp.dispose();
    return w;
  }
}
