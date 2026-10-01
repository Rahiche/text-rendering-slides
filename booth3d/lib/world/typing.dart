import 'dart:math' as math;

import 'package:characters/characters.dart';
import 'package:flutter_scene/scene.dart';
import 'package:text_slides/booth/craft/extrude.dart';
import 'package:text_slides/booth/craft/plan.dart' show vectorizeText;
import 'package:text_slides/booth/model.dart';
import 'package:text_slides/booth/ui/booth_ui.dart';
import 'package:vector_math/vector_math.dart' as vm;

import 'kit.dart';
import 'site_fx.dart';
import 'site_geo.dart';

/// The visitor's typing, in the plaza. Every character committed in the
/// input drops from the sky as a small extruded letter, bounces and settles
/// in a row at the front of the plaza (just above the input on screen).
/// Enter sends the letters hopping off to join the line; Backspace, or the
/// input being cleared, pops them.
class Typing3D {
  Typing3D(this.scene);

  final Scene scene;

  /// The waiting area: where the row starts (left end), on the ground.
  static final origin = vm.Vector3(-7.2, 0.04, -7.4);
  static const maxWidth = 11.0, letterH = 0.95, gap = 0.12, space = 0.42;

  final _root = Node(name: 'typed letters');
  final _letters = <_Typed>[];
  final _cache = <String, _Glyph>{}; // insertion order = LRU order
  final _loading = <String>{};
  final _mats = <PhysicallyBasedMaterial>[];
  final _events = <String>[];
  BoothUi? _ui;
  String _draft = '';
  double _changedAt = -100;
  int _serial = 0;

  /// How much there is to see (for the camera): 1 while someone types.
  double weight = 0;

  void init() {
    scene.add(_root);
    for (final c in fxPalette.take(6)) {
      _mats.add(pbr(c, roughness: 0.32, metallic: 0.05, emissive: c, emissiveStrength: 0.35));
    }
  }

  /// Follows [ui]'s draft (committed text).
  void attach(BoothUi ui) {
    if (identical(ui, _ui)) return;
    _ui = ui;
    _draft = ui.draft.value;
    ui.draft.addListener(() => _events.add(ui.draft.value));
    for (final g in _draft.characters) {
      _spawn(g, 0, delay: 0);
    }
  }

  void update(BoothModel m, double dt, Fx3D fx) {
    final t = m.t;
    for (final next in _events) {
      _apply(next, t);
    }
    _events.clear();

    // Layout: the waiting row, squeezed to fit.
    var total = 0.0;
    for (final l in _letters) {
      if (l.leaving) continue;
      total += l.width + gap;
    }
    final squeeze = total > maxWidth ? maxWidth / total : 1.0;
    var x = origin.x;
    for (final l in _letters) {
      if (l.leaving) continue;
      final w = l.width * squeeze;
      l.targetX = x + w / 2;
      l.scale = squeeze;
      x += w + gap * squeeze;
    }

    var n = 0;
    for (var i = _letters.length - 1; i >= 0; i--) {
      final l = _letters[i];
      final glyph = _cache[l.ch];
      if (l.node == null && glyph != null && glyph.geometry != null) {
        l.node = Node(name: 'typed ${l.ch}', mesh: Mesh(glyph.geometry!, _mats[l.hue]));
        _root.add(l.node!);
        l.born = math.max(l.born, t);
      }
      if (l.node == null && l.leaving) {
        _letters.removeAt(i);
        continue;
      }
      if (!l.placed) {
        l.x = l.targetX;
        l.placed = true;
      }
      // Glide along the row as letters come and go.
      l.x = approach(l.x, l.targetX, dt, 0.12);
      if (_draw(l, t, fx)) {
        if (l.node != null) _root.remove(l.node!);
        _letters.removeAt(i);
        continue;
      }
      if (!l.leaving) n++;
    }
    // The camera cares while someone is busy typing (or just sent it off).
    final busy = (n > 0 || _letters.isNotEmpty) && t - _changedAt < 10;
    weight = approach(weight, busy ? 1 : 0, dt, busy ? 0.5 : 2.0);
  }

  /// The draft changed from [_draft] to [next]: new characters drop in,
  /// removed ones pop, or (Enter) they all hop away into the line.
  void _apply(String next, double t) {
    _changedAt = t;
    final before = _draft.characters.toList();
    final after = next.characters.toList();
    _draft = next;
    var p = 0;
    while (p < before.length && p < after.length && before[p] == after[p]) {
      p++;
    }
    final live = [
      for (final l in _letters)
        if (!l.leaving) l,
    ];
    final ui = _ui;
    final submitted = after.isEmpty && before.isNotEmpty && ui != null && ui.flights.isNotEmpty && (t - ui.flights.last.at).abs() < 0.6;
    for (var k = live.length - 1; k >= p; k--) {
      final l = live[k];
      l.leaving = true;
      l.leftAt = t;
      if (submitted) {
        l.hop = true;
        l.order = k;
      }
    }
    for (var k = p; k < after.length; k++) {
      _spawn(after[k], t, delay: (k - p) * 0.07);
    }
  }

  void _spawn(String ch, double t, {required double delay}) {
    final hue = (_serial++) % 6;
    final blank = ch.trim().isEmpty;
    final l = _Typed(ch, hue, t + delay, blank ? space : _cache[ch]?.width ?? letterH * 0.7);
    _letters.add(l);
    if (blank) return;
    final cached = _cache.remove(ch);
    if (cached != null) {
      _cache[ch] = cached; // most recently used
      l.width = cached.width;
      return;
    }
    if (_loading.contains(ch)) return;
    _loading.add(ch);
    vectorizeText(ch).then((gs) {
      _loading.remove(ch);
      if (gs.isEmpty || gs.first.$2.isEmpty) {
        _cache[ch] = _Glyph(null, letterH * 0.5);
      } else {
        final g = gs.first.$2;
        final mesh = extrudeGlyph(g, unitsPerPx: letterH / 105, depth: 0.32);
        _cache[ch] = _Glyph(glyphGeometry(mesh), mesh.width);
      }
      for (final l in _letters) {
        if (l.ch == ch) l.width = _cache[ch]!.width;
      }
      // Bounded: forget the least recently used characters.
      while (_cache.length > 160) {
        final old = _cache.keys.firstWhere((k) => !_letters.any((l) => l.ch == k), orElse: () => '');
        if (old.isEmpty) break;
        _cache.remove(old);
      }
    });
  }

  /// Poses letter [l]; true when it's gone.
  bool _draw(_Typed l, double t, Fx3D fx) {
    final node = l.node;
    final tau = t - l.born;
    if (node == null) return false;
    if (tau < 0) {
      node.visible = false;
      return false;
    }
    node.visible = true;
    var y = origin.y, s = l.scale, roll = 0.0, yaw = 0.0;
    var x = l.x, z = origin.z;
    // Dropping in from the sky with a few bounces.
    final (h, impact) = _bounce(tau);
    y += h;
    if (impact >= 0 && impact < 0.16) s *= 1 + 0.18 * (1 - impact / 0.16);
    if (impact >= 0 && impact < 0.35) {
      // A little splash of sparks along the ground where it lands.
      final f = impact / 0.35;
      for (var k = 0; k < 6; k++) {
        final a = k / 6 * math.pi * 2 + l.hue;
        final r = 0.25 + 0.55 * eo(f);
        fx.spark(x + math.cos(a) * r, origin.y + 0.06 + 0.25 * math.sin(f * math.pi), z + math.sin(a) * r * 0.6, 0.05 * (1 - f), fxPalette[l.hue], 5);
      }
    }
    roll = 0.25 * math.sin(tau * 9 + l.hue) * math.exp(-tau * 2.2);
    // Alive: a little bob, out of step with the neighbours.
    y += 0.025 * math.max(0, math.sin(t * 2.4 + l.hue * 1.3)) * c01(tau - 1.5);
    if (l.leaving) {
      final u = t - l.leftAt;
      if (l.hop) {
        // Two little hops, then a big leap up and away to join the line.
        final start = l.order * 0.06;
        final v = u - start;
        if (v > 0) {
          final hops = math.min(v, 0.6);
          y += 0.35 * math.sin(hops / 0.3 * math.pi).abs();
          if (v > 0.6) {
            final f = c01((v - 0.6) / 1.1);
            x += -3.5 * f - 1.5 * f * f;
            y += 7.5 * math.sin(f * math.pi * 0.5) + 2 * f;
            z += 9 * f;
            yaw = f * 4;
            s *= 1 - 0.75 * f;
            if (f > 0.05 && f < 0.98) {
              fx.spark(x, y + 0.4, z, 0.07 * (1 - f), fxPalette[l.hue], 6);
            }
            if (f >= 1) {
              node.visible = false;
              return true;
            }
          }
        }
      } else {
        // Pop: a quick swell, then gone in a burst of sparks.
        final f = u / 0.24;
        if (f >= 1) {
          node.visible = false;
          return true;
        }
        s *= f < 0.4 ? 1 + 0.5 * f / 0.4 : 1.2 * (1 - (f - 0.4) / 0.6);
        for (var k = 0; k < 10; k++) {
          final a = k / 10 * math.pi * 2;
          final r = 0.2 + 0.8 * f;
          fx.spark(x + math.cos(a) * r, y + 0.45 + math.sin(a) * r, z - 0.2, 0.06 * (1 - f) + 0.01, fxPalette[(l.hue + k) % 7], 7);
        }
      }
    }
    node.place((m) => setTrs(m, x, y, z, yaw: yaw, roll: roll, s: s));
    return false;
  }

  /// Height above the ground [tau] seconds after being dropped, and seconds
  /// since the latest impact (or -1 while still falling the first time).
  static (double, double) _bounce(double tau) {
    const g = 22.0, y0 = 6.5, e = 0.42;
    final t1 = math.sqrt(2 * y0 / g);
    if (tau < t1) return (y0 - 0.5 * g * tau * tau, -1);
    var v = g * t1 * e;
    var at = t1;
    for (var k = 0; k < 4; k++) {
      final d = 2 * v / g;
      if (tau < at + d) {
        final s = tau - at;
        return (v * s - 0.5 * g * s * s, s);
      }
      at += d;
      v *= e;
    }
    return (0, tau - at);
  }
}

class _Glyph {
  _Glyph(this.geometry, this.width);
  final MeshGeometry? geometry;
  final double width;
}

class _Typed {
  _Typed(this.ch, this.hue, this.born, this.width);
  final String ch;
  final int hue;
  double born;
  double width;
  Node? node;
  double x = 0, targetX = 0, scale = 1;
  bool placed = false;
  bool leaving = false, hop = false;
  double leftAt = 0;
  int order = 0;
}
