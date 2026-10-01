import 'dart:collection';
import 'dart:math' as math;
import 'dart:typed_data';

/// Vectorization of one rendered character, so the workshop's crafts can
/// follow the real glyph whatever the font or script:
///
/// * [Contour]s — the outline, traced with marching squares on the
///   anti-aliased coverage (outer outlines and holes);
/// * [Stroke]s — centre lines from thinning the shape, with the stroke's
///   half-width at every point (distance transform), in an approximate
///   writing order (書き順: top to bottom, left to right, horizontal before a
///   vertical that crosses it);
/// * [Span]s — the inside of every raster row.
///
/// Pure Dart (no dart:ui), so it can run on a background isolate.
/// Coordinates are raster pixels; pixel (x, y) covers [x, x+1) × [y, y+1).
class GlyphGeometry {
  GlyphGeometry({
    required this.w,
    required this.h,
    required this.contours,
    required this.strokes,
    required this.spans,
    required this.inkLeft,
    required this.inkTop,
    required this.inkRight,
    required this.inkBottom,
  });

  final int w;
  final int h;
  final List<Contour> contours;
  final List<Stroke> strokes;
  final List<Span> spans;
  final double inkLeft;
  final double inkTop;
  final double inkRight;
  final double inkBottom;

  double get inkWidth => inkRight - inkLeft;
  double get inkHeight => inkBottom - inkTop;
  bool get isEmpty => contours.isEmpty;

  double get outlineLength => contours.fold(0, (a, c) => a + c.perimeter);
  double get strokeLength => strokes.fold(0, (a, s) => a + s.pathLength);
}

/// A closed outline: x0, y0, x1, y1, … (the last point joins the first).
class Contour {
  Contour(this.pts, {required this.hole, required this.area});

  final Float64List pts;
  final bool hole;

  /// Absolute area in px².
  final double area;

  int get count => pts.length ~/ 2;

  double get perimeter {
    var s = 0.0;
    final n = count;
    for (var i = 0; i < n; i++) {
      final j = (i + 1) % n;
      s += _dist(pts[2 * i], pts[2 * i + 1], pts[2 * j], pts[2 * j + 1]);
    }
    return s;
  }
}

/// One centre-line stroke with the half-width of the stroke at each point.
class Stroke {
  Stroke(this.pts, this.radius);

  final Float64List pts;
  final Float64List radius;

  int get count => pts.length ~/ 2;

  double get pathLength {
    var s = 0.0;
    for (var i = 1; i < count; i++) {
      s += _dist(pts[2 * i - 2], pts[2 * i - 1], pts[2 * i], pts[2 * i + 1]);
    }
    return s;
  }

  double get maxRadius => radius.fold(0.0, math.max);
}

/// Inside run of raster row [y]: pixels x0 ≤ x < x1.
class Span {
  const Span(this.y, this.x0, this.x1);
  final int y;
  final int x0;
  final int x1;
}

/// Input for [vectorize]: a w×h coverage raster (0..255, row-major). The
/// raster should have at least 2 empty pixels of padding on every side.
class VectorizeInput {
  const VectorizeInput(this.w, this.h, this.alpha);
  final int w;
  final int h;
  final Uint8List alpha;
}

GlyphGeometry vectorize(VectorizeInput input) {
  final w = input.w, h = input.h, a = input.alpha;
  final mask = Uint8List(w * h);
  var l = w, t = h, r = -1, b = -1;
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      if (a[y * w + x] >= 128) {
        mask[y * w + x] = 1;
        if (x < l) l = x;
        if (x > r) r = x;
        if (y < t) t = y;
        if (y > b) b = y;
      }
    }
  }
  if (r < 0) {
    return GlyphGeometry(
      w: w,
      h: h,
      contours: const [],
      strokes: const [],
      spans: const [],
      inkLeft: 0,
      inkTop: 0,
      inkRight: 0,
      inkBottom: 0,
    );
  }
  final contours = traceContours(w, h, a);
  final dist = distanceTransform(w, h, mask);
  final skel = thin(w, h, mask);
  final strokes = skeletonStrokes(w, h, skel, dist, inkHeight: (b - t + 1).toDouble());
  final spans = <Span>[];
  for (var y = 0; y < h; y++) {
    var x = 0;
    while (x < w) {
      while (x < w && mask[y * w + x] == 0) {
        x++;
      }
      if (x >= w) break;
      final x0 = x;
      while (x < w && mask[y * w + x] == 1) {
        x++;
      }
      spans.add(Span(y, x0, x));
    }
  }
  return GlyphGeometry(
    w: w,
    h: h,
    contours: contours,
    strokes: strokes,
    spans: spans,
    inkLeft: l.toDouble(),
    inkTop: t.toDouble(),
    inkRight: r + 1.0,
    inkBottom: b + 1.0,
  );
}

// ── Outline: marching squares ─────────────────────────────────────────────

/// Closed outlines of coverage ≥ ½, interpolated between pixel centres.
/// Outer outlines first (largest first), then holes.
List<Contour> traceContours(int w, int h, Uint8List alpha) {
  // Corners are pixel centres of a raster padded by one empty pixel.
  final cw = w + 2, ch = h + 2;
  final v = Float64List(cw * ch);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      v[(y + 1) * cw + x + 1] = alpha[y * w + x] / 255;
    }
  }
  final edges = cw * ch * 2;
  final ex = Float64List(edges), ey = Float64List(edges);
  final next = Int32List(edges)..fillRange(0, edges, -1);
  int hId(int i, int j) => (j * cw + i) * 2; // corner (i,j) → (i+1,j)
  int vId(int i, int j) => (j * cw + i) * 2 + 1; // corner (i,j) → (i,j+1)
  // Corner (i, j) is the centre of raster pixel (i-1, j-1), i.e. raster
  // coordinates (i-0.5, j-0.5): the padding is already accounted for.
  void ptH(int i, int j) {
    final id = hId(i, j);
    final fa = v[j * cw + i], fb = v[j * cw + i + 1];
    ex[id] = i - 0.5 + (0.5 - fa) / (fb - fa);
    ey[id] = j - 0.5;
  }

  void ptV(int i, int j) {
    final id = vId(i, j);
    final fa = v[j * cw + i], fd = v[(j + 1) * cw + i];
    ex[id] = i - 0.5;
    ey[id] = j - 0.5 + (0.5 - fa) / (fd - fa);
  }

  const top = 0, right = 1, bottom = 2, left = 3;
  for (var j = 0; j < ch - 1; j++) {
    for (var i = 0; i < cw - 1; i++) {
      final fa = v[j * cw + i], fb = v[j * cw + i + 1];
      final fc = v[(j + 1) * cw + i + 1], fd = v[(j + 1) * cw + i];
      final idx =
          (fa >= 0.5 ? 8 : 0) | (fb >= 0.5 ? 4 : 0) | (fc >= 0.5 ? 2 : 0) | (fd >= 0.5 ? 1 : 0);
      if (idx == 0 || idx == 15) continue;
      final centre = (fa + fb + fc + fd) / 4 >= 0.5;
      final List<(int, int)> pairs = switch (idx) {
        1 => [(left, bottom)],
        2 => [(bottom, right)],
        3 => [(left, right)],
        4 => [(top, right)],
        5 => centre ? [(top, left), (right, bottom)] : [(top, right), (bottom, left)],
        6 => [(top, bottom)],
        7 => [(top, left)],
        8 => [(top, left)],
        9 => [(top, bottom)],
        10 => centre ? [(top, right), (bottom, left)] : [(top, left), (right, bottom)],
        11 => [(top, right)],
        12 => [(right, left)],
        13 => [(right, bottom)],
        _ => [(bottom, left)], // 14
      };
      int edgeId(int e) {
        switch (e) {
          case top:
            ptH(i, j);
            return hId(i, j);
          case right:
            ptV(i + 1, j);
            return vId(i + 1, j);
          case bottom:
            ptH(i, j + 1);
            return hId(i, j + 1);
          default:
            ptV(i, j);
            return vId(i, j);
        }
      }

      for (final (e1, e2) in pairs) {
        var p = edgeId(e1), q = edgeId(e2);
        // Orient every segment the same way relative to the inside: the
        // field's gradient (pointing inside) must be on the same side.
        final mx = (ex[p] + ex[q]) / 2 - (i - 0.5), my = (ey[p] + ey[q]) / 2 - (j - 0.5);
        final gu = -fa * (1 - my) + fb * (1 - my) + fc * my - fd * my;
        final gv = -fa * (1 - mx) - fb * mx + fc * mx + fd * (1 - mx);
        final cross = (ex[q] - ex[p]) * gv - (ey[q] - ey[p]) * gu;
        if (cross > 0) {
          final s = p;
          p = q;
          q = s;
        }
        next[p] = q;
      }
    }
  }
  // Link segments into loops.
  final seen = Uint8List(edges);
  final loops = <(Float64List, double)>[];
  for (var e = 0; e < edges; e++) {
    if (next[e] < 0 || seen[e] == 1) continue;
    final pts = <double>[];
    var cur = e;
    while (cur >= 0 && seen[cur] == 0) {
      seen[cur] = 1;
      pts
        ..add(ex[cur])
        ..add(ey[cur]);
      cur = next[cur];
    }
    if (pts.length < 6) continue;
    final p = Float64List.fromList(pts);
    loops.add((p, _signedArea(p)));
  }
  if (loops.isEmpty) return [];
  var outerSign = 0.0, best = -1.0;
  for (final (_, area) in loops) {
    if (area.abs() > best) {
      best = area.abs();
      outerSign = area.sign;
    }
  }
  final out = [
    for (final (p, area) in loops)
      if (area.abs() >= 1.0)
        Contour(simplifyClosed(p, 0.3), hole: area.sign != outerSign, area: area.abs()),
  ];
  out.sort((a, b) {
    if (a.hole != b.hole) return a.hole ? 1 : -1;
    return b.area.compareTo(a.area);
  });
  return out;
}

double _signedArea(Float64List p) {
  var s = 0.0;
  final n = p.length ~/ 2;
  for (var i = 0; i < n; i++) {
    final j = (i + 1) % n;
    s += p[2 * i] * p[2 * j + 1] - p[2 * j] * p[2 * i + 1];
  }
  return s / 2;
}

double _dist(double ax, double ay, double bx, double by) {
  final dx = bx - ax, dy = by - ay;
  return math.sqrt(dx * dx + dy * dy);
}

/// Douglas–Peucker on an open polyline.
Float64List simplifyOpen(Float64List p, double eps) {
  final n = p.length ~/ 2;
  if (n <= 2) return p;
  final keep = Uint8List(n)
    ..[0] = 1
    ..[n - 1] = 1;
  final stack = <(int, int)>[(0, n - 1)];
  while (stack.isNotEmpty) {
    final (s, e) = stack.removeLast();
    var far = -1;
    var dmax = eps;
    final ax = p[2 * s], ay = p[2 * s + 1], bx = p[2 * e], by = p[2 * e + 1];
    final dx = bx - ax, dy = by - ay;
    final len = math.sqrt(dx * dx + dy * dy);
    for (var i = s + 1; i < e; i++) {
      final px = p[2 * i], py = p[2 * i + 1];
      final d = len < 1e-9 ? _dist(ax, ay, px, py) : ((px - ax) * dy - (py - ay) * dx).abs() / len;
      if (d > dmax) {
        dmax = d;
        far = i;
      }
    }
    if (far >= 0) {
      keep[far] = 1;
      stack
        ..add((s, far))
        ..add((far, e));
    }
  }
  final out = <double>[];
  for (var i = 0; i < n; i++) {
    if (keep[i] == 1) out.addAll([p[2 * i], p[2 * i + 1]]);
  }
  return Float64List.fromList(out);
}

/// Douglas–Peucker on a closed polygon (no repeated last point).
Float64List simplifyClosed(Float64List p, double eps) {
  final n = p.length ~/ 2;
  if (n <= 4) return p;
  var far = 0;
  var dmax = -1.0;
  for (var i = 1; i < n; i++) {
    final d = _dist(p[0], p[1], p[2 * i], p[2 * i + 1]);
    if (d > dmax) {
      dmax = d;
      far = i;
    }
  }
  final a = simplifyOpen(Float64List.sublistView(p, 0, 2 * far + 2), eps);
  final b = simplifyOpen(Float64List.fromList([...p.sublist(2 * far), p[0], p[1]]), eps);
  // a ends at `far`, b starts at `far` and ends at 0: drop duplicates.
  return Float64List.fromList([...a, ...b.sublist(2, b.length - 2)]);
}

// ── Distance transform ────────────────────────────────────────────────────

/// Euclidean distance (px) from each inside pixel to the nearest outside
/// pixel (Felzenszwalb–Huttenlocher), 0 outside.
Float64List distanceTransform(int w, int h, Uint8List mask) {
  const inf = 1e20;
  final f = Float64List(w * h);
  for (var i = 0; i < w * h; i++) {
    f[i] = mask[i] == 1 ? inf : 0;
  }
  final n = math.max(w, h);
  final line = Float64List(n), d = Float64List(n), z = Float64List(n + 1);
  final vv = Int32List(n);
  for (var x = 0; x < w; x++) {
    for (var y = 0; y < h; y++) {
      line[y] = f[y * w + x];
    }
    _dt1d(line, h, d, vv, z);
    for (var y = 0; y < h; y++) {
      f[y * w + x] = d[y];
    }
  }
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      line[x] = f[y * w + x];
    }
    _dt1d(line, w, d, vv, z);
    for (var x = 0; x < w; x++) {
      f[y * w + x] = math.sqrt(d[x]);
    }
  }
  return f;
}

void _dt1d(Float64List f, int n, Float64List d, Int32List v, Float64List z) {
  const inf = 1e30;
  var k = 0;
  v[0] = 0;
  z[0] = -inf;
  z[1] = inf;
  for (var q = 1; q < n; q++) {
    var s = ((f[q] + q * q) - (f[v[k]] + v[k] * v[k])) / (2 * q - 2 * v[k]);
    while (s <= z[k]) {
      k--;
      s = ((f[q] + q * q) - (f[v[k]] + v[k] * v[k])) / (2 * q - 2 * v[k]);
    }
    k++;
    v[k] = q;
    z[k] = s;
    z[k + 1] = inf;
  }
  k = 0;
  for (var q = 0; q < n; q++) {
    while (z[k + 1] < q) {
      k++;
    }
    d[q] = (q - v[k]) * (q - v[k]) + f[v[k]];
  }
}

// ── Skeleton ──────────────────────────────────────────────────────────────

/// Zhang–Suen thinning to a one-pixel, 8-connected skeleton.
Uint8List thin(int w, int h, Uint8List mask) {
  final s = Uint8List.fromList(mask);
  // Keep a one-pixel empty frame.
  for (var x = 0; x < w; x++) {
    s[x] = 0;
    s[(h - 1) * w + x] = 0;
  }
  for (var y = 0; y < h; y++) {
    s[y * w] = 0;
    s[y * w + w - 1] = 0;
  }
  final del = <int>[];
  var changed = true;
  while (changed) {
    changed = false;
    for (var step = 0; step < 2; step++) {
      del.clear();
      for (var y = 1; y < h - 1; y++) {
        for (var x = 1; x < w - 1; x++) {
          final i = y * w + x;
          if (s[i] == 0) continue;
          final p2 = s[i - w], p3 = s[i - w + 1], p4 = s[i + 1], p5 = s[i + w + 1];
          final p6 = s[i + w], p7 = s[i + w - 1], p8 = s[i - 1], p9 = s[i - w - 1];
          final bsum = p2 + p3 + p4 + p5 + p6 + p7 + p8 + p9;
          if (bsum < 2 || bsum > 6) continue;
          var trans = 0;
          if (p2 == 0 && p3 == 1) trans++;
          if (p3 == 0 && p4 == 1) trans++;
          if (p4 == 0 && p5 == 1) trans++;
          if (p5 == 0 && p6 == 1) trans++;
          if (p6 == 0 && p7 == 1) trans++;
          if (p7 == 0 && p8 == 1) trans++;
          if (p8 == 0 && p9 == 1) trans++;
          if (p9 == 0 && p2 == 1) trans++;
          if (trans != 1) continue;
          if (step == 0) {
            if (p2 * p4 * p6 != 0 || p4 * p6 * p8 != 0) continue;
          } else {
            if (p2 * p4 * p8 != 0 || p2 * p6 * p8 != 0) continue;
          }
          del.add(i);
        }
      }
      for (final i in del) {
        s[i] = 0;
      }
      if (del.isNotEmpty) changed = true;
    }
  }
  // Staircases → clean diagonals (drop the corner pixel of each step).
  for (var y = 1; y < h - 1; y++) {
    for (var x = 1; x < w - 1; x++) {
      final i = y * w + x;
      if (s[i] == 0) continue;
      final n = s[i - w] == 1, e = s[i + 1] == 1, so = s[i + w] == 1, we = s[i - 1] == 1;
      final ne = s[i - w + 1] == 1,
          se = s[i + w + 1] == 1,
          sw = s[i + w - 1] == 1,
          nw = s[i - w - 1] == 1;
      if ((n && e && !so && !we && !sw) ||
          (e && so && !n && !we && !nw) ||
          (so && we && !n && !e && !ne) ||
          (we && n && !e && !so && !se)) {
        s[i] = 0;
      }
    }
  }
  return s;
}

/// Turns a skeleton into strokes: traces branches between end points and
/// junctions, prunes spurs, joins branches that continue straight through a
/// junction, splits at sharp corners, and orders them like handwriting.
List<Stroke> skeletonStrokes(
  int w,
  int h,
  Uint8List s,
  Float64List dist, {
  required double inkHeight,
}) {
  final nb = <int>[-w - 1, -w, -w + 1, -1, 1, w - 1, w, w + 1];
  final deg = Uint8List(w * h);
  for (var y = 1; y < h - 1; y++) {
    for (var x = 1; x < w - 1; x++) {
      final i = y * w + x;
      if (s[i] == 0) continue;
      var c = 0;
      for (final o in nb) {
        c += s[i + o];
      }
      deg[i] = c;
    }
  }
  bool isNode(int i) => deg[i] != 2;
  List<int> neighbours(int i) => [
    for (final o in nb)
      if (s[i + o] == 1) i + o,
  ];

  // Trace chains between nodes.
  final seen = HashSet<int>();
  int key(int a, int b) => a < b ? a * w * h + b : b * w * h + a;
  final chains = <List<int>>[];
  final onChain = Uint8List(w * h);
  for (var i = 0; i < w * h; i++) {
    if (s[i] == 0 || !isNode(i)) continue;
    if (deg[i] == 0) {
      chains.add([i]);
      onChain[i] = 1;
      continue;
    }
    for (final q in neighbours(i)) {
      if (!seen.add(key(i, q))) continue;
      final chain = [i, q];
      var prev = i, cur = q;
      while (!isNode(cur)) {
        int? step;
        for (final n in neighbours(cur)) {
          if (n != prev && !seen.contains(key(cur, n))) {
            step = n;
            break;
          }
        }
        if (step == null) break;
        seen.add(key(cur, step));
        chain.add(step);
        prev = cur;
        cur = step;
      }
      for (final p in chain) {
        onChain[p] = 1;
      }
      chains.add(chain);
    }
  }
  // Loops with no node at all (an 'O' drawn as one ring).
  for (var i = 0; i < w * h; i++) {
    if (s[i] == 0 || onChain[i] == 1) continue;
    final chain = [i];
    onChain[i] = 1;
    var prev = -1, cur = i;
    while (true) {
      int? step;
      for (final n in neighbours(cur)) {
        if (n != prev && onChain[n] == 0) {
          step = n;
          break;
        }
      }
      if (step == null) break;
      chain.add(step);
      onChain[step] = 1;
      prev = cur;
      cur = step;
    }
    chain.add(i); // closed
    chains.add(chain);
  }

  // Junction clusters: adjacent node pixels are one junction.
  final parent = <int, int>{};
  int find(int a) {
    var r = a;
    while (parent[r] != r) {
      r = parent[r]!;
    }
    var c = a;
    while (parent[c] != r) {
      final n = parent[c]!;
      parent[c] = r;
      c = n;
    }
    return r;
  }

  for (var i = 0; i < w * h; i++) {
    if (s[i] == 1 && deg[i] >= 3) parent[i] = i;
  }
  for (final i in parent.keys.toList()) {
    for (final o in nb) {
      final j = i + o;
      if (parent.containsKey(j)) {
        final a = find(i), b = find(j);
        if (a != b) parent[a] = b;
      }
    }
  }
  int? cluster(int p) => parent.containsKey(p) ? find(p) : null;

  final branches = <_Branch>[];
  for (final c in chains) {
    final a = cluster(c.first), b = cluster(c.last);
    // Bits of a junction cluster connecting to itself.
    if (a != null && a == b && c.length <= 4) continue;
    final pts = <double>[];
    final rad = <double>[];
    for (final p in c) {
      pts
        ..add(p % w + 0.5)
        ..add(p ~/ w + 0.5);
      rad.add(math.max(0.8, dist[p]));
    }
    branches.add(_Branch(pts, rad, a, b, closed: c.length > 2 && c.first == c.last && a == null));
  }

  // Prune short spurs off junctions (artefacts of thinning).
  for (var pass = 0; pass < 3; pass++) {
    final degree = <int, int>{};
    for (final br in branches) {
      if (br.a != null) degree[br.a!] = (degree[br.a!] ?? 0) + 1;
      if (br.b != null) degree[br.b!] = (degree[br.b!] ?? 0) + 1;
    }
    var removed = false;
    branches.removeWhere((br) {
      final freeA = br.a == null, freeB = br.b == null;
      if (freeA == freeB || br.closed) return false; // both ends free or both at junctions
      final j = freeA ? br.b! : br.a!;
      if ((degree[j] ?? 0) < 3) return false;
      final r = freeA ? br.rad.last : br.rad.first;
      if (br.length < math.max(3.0, 1.6 * r + 1)) {
        removed = true;
        return true;
      }
      return false;
    });
    if (!removed) break;
  }

  // Pair branches through each junction when they continue straight on.
  final ends = <int, List<(int, bool)>>{}; // junction → (branch, at start?)
  for (var k = 0; k < branches.length; k++) {
    final br = branches[k];
    if (br.a != null) ends.putIfAbsent(br.a!, () => []).add((k, true));
    if (br.b != null) ends.putIfAbsent(br.b!, () => []).add((k, false));
  }
  final link = <(int, bool), (int, bool)>{};
  for (final list in ends.values) {
    if (list.length == 2) {
      link[list[0]] = list[1];
      link[list[1]] = list[0];
      continue;
    }
    final dirs = [for (final (k, atStart) in list) branches[k].direction(atStart)];
    final used = <int>{};
    while (true) {
      var best = -0.72;
      (int, int)? pair;
      for (var x = 0; x < list.length; x++) {
        if (used.contains(x)) continue;
        for (var y = x + 1; y < list.length; y++) {
          if (used.contains(y)) continue;
          final dot = dirs[x].$1 * dirs[y].$1 + dirs[x].$2 * dirs[y].$2;
          if (dot < best) {
            best = dot;
            pair = (x, y);
          }
        }
      }
      if (pair == null) break;
      used
        ..add(pair.$1)
        ..add(pair.$2);
      link[list[pair.$1]] = list[pair.$2];
      link[list[pair.$2]] = list[pair.$1];
    }
  }

  // Walk linked branches into strokes.
  final done = Uint8List(branches.length);
  final strokes = <_Branch>[];
  void walk(int k, bool fromStart) {
    final pts = <double>[];
    final rad = <double>[];
    var cur = k;
    var forward = fromStart;
    var closed = false;
    while (true) {
      done[cur] = 1;
      final br = branches[cur];
      final n = br.rad.length;
      for (var m = 0; m < n; m++) {
        final idx = forward ? m : n - 1 - m;
        if (pts.isNotEmpty && m == 0) continue; // shared junction point
        pts
          ..add(br.pts[2 * idx])
          ..add(br.pts[2 * idx + 1]);
        rad.add(br.rad[idx]);
      }
      final exitEnd = (cur, !forward); // leaving through the far end
      final to = link[exitEnd];
      if (to == null) break;
      if (done[to.$1] == 1) {
        closed = to.$1 == k;
        break;
      }
      cur = to.$1;
      forward = to.$2; // entering at its start → walk forward
    }
    strokes.add(_Branch(pts, rad, null, null, closed: closed || branches[k].closed));
  }

  for (var k = 0; k < branches.length; k++) {
    if (done[k] == 1) continue;
    final startFree = !link.containsKey((k, true));
    final endFree = !link.containsKey((k, false));
    if (startFree) {
      walk(k, true);
    } else if (endFree) {
      walk(k, false);
    }
  }
  for (var k = 0; k < branches.length; k++) {
    if (done[k] == 0) walk(k, true); // cycles of links
  }

  // Smooth, simplify, split at sharp corners, orient, order.
  final out = <Stroke>[];
  for (final st in strokes) {
    for (final piece in _splitSharp(_smooth(st))) {
      out.add(_orient(piece));
    }
  }
  return _order(out, inkHeight);
}

class _Branch {
  _Branch(this.pts, this.rad, this.a, this.b, {this.closed = false});

  final List<double> pts;
  final List<double> rad;
  final int? a;
  final int? b;
  final bool closed;

  int get n => rad.length;

  double get length {
    var s = 0.0;
    for (var i = 1; i < n; i++) {
      s += _dist(pts[2 * i - 2], pts[2 * i - 1], pts[2 * i], pts[2 * i + 1]);
    }
    return s;
  }

  /// Unit direction leaving the junction at this end.
  (double, double) direction(bool atStart) {
    final k = math.min(n - 1, 7);
    final (x0, y0) = atStart ? (pts[0], pts[1]) : (pts[2 * n - 2], pts[2 * n - 1]);
    final idx = atStart ? k : n - 1 - k;
    final dx = pts[2 * idx] - x0, dy = pts[2 * idx + 1] - y0;
    final l = math.sqrt(dx * dx + dy * dy);
    return l < 1e-6 ? (0, 0) : (dx / l, dy / l);
  }
}

_Branch _smooth(_Branch b) {
  final n = b.n;
  if (n < 5) return b;
  final pts = List<double>.from(b.pts);
  for (var pass = 0; pass < 2; pass++) {
    final src = List<double>.from(pts);
    for (var i = 1; i < n - 1; i++) {
      final a = math.max(0, i - 2), z = math.min(n - 1, i + 2);
      var sx = 0.0, sy = 0.0;
      for (var k = a; k <= z; k++) {
        sx += src[2 * k];
        sy += src[2 * k + 1];
      }
      pts[2 * i] = sx / (z - a + 1);
      pts[2 * i + 1] = sy / (z - a + 1);
    }
  }
  // Simplify, keeping the radius of the points that survive.
  final keep = simplifyOpen(Float64List.fromList(pts), 0.6);
  final rad = <double>[];
  var j = 0;
  for (var k = 0; k < keep.length ~/ 2; k++) {
    while (j < n - 1 && (pts[2 * j] != keep[2 * k] || pts[2 * j + 1] != keep[2 * k + 1])) {
      j++;
    }
    rad.add(b.rad[j]);
  }
  return _Branch(keep.toList(), rad, null, null, closed: b.closed);
}

/// Splits a stroke where it turns sharply (more than ~60° measured over a
/// few pixels of arc, so smoothing doesn't hide the corner), like a pen lift.
/// Closed loops are opened at a corner first (口 → four sides).
List<_Branch> _splitSharp(_Branch b) {
  var n = b.n;
  if (n < 3) return [b];
  var pts = b.pts, rad = b.rad;
  if (b.closed && n > 3 && pts[0] == pts[2 * n - 2] && pts[1] == pts[2 * n - 1]) {
    // Drop the repeated closing point; we'll re-add it after rotating.
    pts = pts.sublist(0, 2 * n - 2);
    rad = rad.sublist(0, n - 1);
    n -= 1;
  }
  final arc = Float64List(n);
  for (var i = 1; i < n; i++) {
    arc[i] = arc[i - 1] + _dist(pts[2 * i - 2], pts[2 * i - 1], pts[2 * i], pts[2 * i + 1]);
  }
  final total = arc[n - 1] + (b.closed ? _dist(pts[2 * n - 2], pts[2 * n - 1], pts[0], pts[1]) : 0);
  final medianR = ([...rad]..sort())[rad.length ~/ 2];
  final reach = math.max(5.0, 1.4 * medianR);
  (double, double) at(double s) {
    if (b.closed) {
      s = (s % total + total) % total;
    } else {
      s = s.clamp(0, arc[n - 1]);
    }
    var i = 0;
    while (i < n - 1 && arc[i + 1] < s) {
      i++;
    }
    if (i >= n - 1) {
      if (!b.closed) return (pts[2 * n - 2], pts[2 * n - 1]);
      final f = (s - arc[n - 1]) / math.max(1e-9, total - arc[n - 1]);
      return (
        pts[2 * n - 2] + (pts[0] - pts[2 * n - 2]) * f,
        pts[2 * n - 1] + (pts[1] - pts[2 * n - 1]) * f,
      );
    }
    final f = (s - arc[i]) / math.max(1e-9, arc[i + 1] - arc[i]);
    return (
      pts[2 * i] + (pts[2 * i + 2] - pts[2 * i]) * f,
      pts[2 * i + 1] + (pts[2 * i + 3] - pts[2 * i + 1]) * f,
    );
  }

  final turn = Float64List(n); // 1 - cos(angle)
  for (var i = 0; i < n; i++) {
    if (!b.closed && (arc[i] < reach * 0.8 || arc[n - 1] - arc[i] < reach * 0.8)) continue;
    final (bx, by) = at(arc[i] - reach);
    final (fx, fy) = at(arc[i] + reach);
    final ux = pts[2 * i] - bx,
        uy = pts[2 * i + 1] - by,
        vx = fx - pts[2 * i],
        vy = fy - pts[2 * i + 1];
    final lu = math.sqrt(ux * ux + uy * uy), lv = math.sqrt(vx * vx + vy * vy);
    if (lu < 1e-6 || lv < 1e-6) continue;
    turn[i] = 1 - (ux * vx + uy * vy) / (lu * lv);
  }
  // Corners: local maxima of the turn above ~60°, at least `reach` apart.
  final cuts = <int>[];
  for (var i = 0; i < n; i++) {
    if (turn[i] < 0.5) continue;
    var peak = true;
    for (var j = 0; j < n && peak; j++) {
      if (j == i) continue;
      var d = (arc[j] - arc[i]).abs();
      if (b.closed) d = math.min(d, total - d);
      if (d < reach && (turn[j] > turn[i] || (turn[j] == turn[i] && j < i))) peak = false;
    }
    if (peak) cuts.add(i);
  }
  if (cuts.isEmpty) {
    if (!b.closed) return [b];
    return [
      _Branch([...pts, pts[0], pts[1]], [...rad, rad[0]], null, null, closed: true),
    ];
  }
  if (b.closed) {
    // Rotate to start at the first corner and close the loop there.
    final c0 = cuts.first;
    final rp = <double>[...pts.sublist(2 * c0), ...pts.sublist(0, 2 * c0 + 2)];
    final rr = <double>[...rad.sublist(c0), ...rad.sublist(0, c0 + 1)];
    final shifted = [for (final c in cuts.skip(1)) c - c0, rr.length - 1];
    final out = <_Branch>[];
    var s0 = 0;
    for (final c in shifted) {
      if (c - s0 >= 1) {
        out.add(_Branch(rp.sublist(2 * s0, 2 * c + 2), rr.sublist(s0, c + 1), null, null));
      }
      s0 = c;
    }
    return out;
  }
  final out = <_Branch>[];
  var s0 = 0;
  for (final c in [...cuts, n - 1]) {
    if (c - s0 >= 1) {
      out.add(_Branch(pts.sublist(2 * s0, 2 * c + 2), rad.sublist(s0, c + 1), null, null));
    }
    s0 = c;
  }
  return out;
}

/// Horizontal-ish strokes run left → right, the rest top → bottom.
Stroke _orient(_Branch b) {
  final n = b.n;
  var pts = b.pts, rad = b.rad;
  if (n >= 2) {
    final dx = pts[2 * n - 2] - pts[0], dy = pts[2 * n - 1] - pts[1];
    final reverse = dx.abs() > dy.abs() * 1.15 ? dx < 0 : dy < 0;
    if (reverse) {
      pts = [
        for (var i = n - 1; i >= 0; i--) ...[pts[2 * i], pts[2 * i + 1]],
      ];
      rad = rad.reversed.toList();
    }
  }
  return Stroke(Float64List.fromList(pts), Float64List.fromList(rad));
}

bool _horizontal(Stroke s) {
  final n = s.count;
  if (n < 2) return false;
  return (s.pts[2 * n - 2] - s.pts[0]).abs() > (s.pts[2 * n - 1] - s.pts[1]).abs() * 1.15;
}

/// Writing order: by start (top band, then left), then a horizontal stroke
/// goes before a vertical one that crosses it (十: 一 then 丨).
List<Stroke> _order(List<Stroke> strokes, double inkHeight) {
  final band = math.max(4.0, inkHeight * 0.12);
  strokes.sort((a, b) {
    final ba = (a.pts[1] / band).floor(), bb = (b.pts[1] / band).floor();
    if (ba != bb) return ba.compareTo(bb);
    final c = a.pts[0].compareTo(b.pts[0]);
    if (c != 0) return c;
    // Same start: the vertical first (口: 丨 before the top).
    return (_horizontal(a) ? 1 : 0).compareTo(_horizontal(b) ? 1 : 0);
  });
  for (var pass = 0; pass < 3; pass++) {
    var moved = false;
    for (var i = 0; i < strokes.length; i++) {
      for (var j = i + 1; j < strokes.length; j++) {
        if (!_horizontal(strokes[i]) && _horizontal(strokes[j]) && _cross(strokes[i], strokes[j])) {
          strokes.insert(i, strokes.removeAt(j));
          moved = true;
        }
      }
    }
    if (!moved) break;
  }
  return strokes;
}

bool _cross(Stroke a, Stroke b) {
  for (var i = 1; i < a.count; i++) {
    for (var j = 1; j < b.count; j++) {
      if (_segX(
        a.pts[2 * i - 2],
        a.pts[2 * i - 1],
        a.pts[2 * i],
        a.pts[2 * i + 1],
        b.pts[2 * j - 2],
        b.pts[2 * j - 1],
        b.pts[2 * j],
        b.pts[2 * j + 1],
      )) {
        return true;
      }
    }
  }
  return false;
}

bool _segX(double ax, double ay, double bx, double by, double cx, double cy, double dx, double dy) {
  double o(double px, double py, double qx, double qy, double rx, double ry) =>
      (qx - px) * (ry - py) - (qy - py) * (rx - px);
  final d1 = o(ax, ay, bx, by, cx, cy), d2 = o(ax, ay, bx, by, dx, dy);
  final d3 = o(cx, cy, dx, dy, ax, ay), d4 = o(cx, cy, dx, dy, bx, by);
  return d1 * d2 < 0 && d3 * d4 < 0;
}
