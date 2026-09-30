import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../deck/deck.dart';
import '../../deck/scripts.dart';
import '../../deck/theme.dart';
import '../../deck/widgets.dart';
import '../../slides/journey/journey.dart' show arabicForm;
import '../../worlds/factory/factory_kit.dart';

/// The pipeline as the factory's assembly line: seven machines on one belt,
/// each powering on at its build step (0..6). Crates of "Hi كتاب" drop out of
/// the text chute and ride through every powered machine; at the first dark
/// machine they tip into a waiting bin. What each machine did shows on the
/// crate itself, not in labels: itemize paints it in its script's colour,
/// fonts drops the glyph in, shape swaps in the joined Arabic form, and the
/// oven turns it into pixels for the screen at the end of the line.
///
/// Only the machine names are text, big; the newest machine (this step's
/// stage) is lit amber. The tour group watches it from the catwalk;
/// operators sleep at dark machines and wake up when the power comes on.
/// Click a machine → its deep-dive slide.
class FactoryPipeline extends StatefulWidget {
  const FactoryPipeline({super.key});

  @override
  State<FactoryPipeline> createState() => _FactoryPipelineState();
}

const _ids = ['string', 'itemize', 'fallback', 'shaping', 'linebreak', 'bidi', 'raster'];
const _names = ['text', 'itemize', 'fonts', 'shape', 'wrap', 'position', 'raster'];

const _sample = 'Hi كتاب';

// Content-area coordinates (the SlideFrame child is 1472 × 628).
const _floor = 604.0;
const _beltTop = 452.0;
const _cw = 64.0, _ch = 46.0;
const _crateTop = _beltTop - _ch;
const _pitch = 92.0;
const _walkY = 104.0; // catwalk floor
const _endSlot = 14; // the screen's intake

/// Indexing belt: move for [_mv] of every [_per] seconds, then all machines work.
const _per = 1.1;
const _mv = 0.4;

double _sx(double slot) => 84 + _pitch * slot;

/// Machine i works on the crate at slot 2i.
double _mx(int i) => _sx(2.0 * i);

/// Visual centre of machine i (the cutter's blade sits in the gap after its slot).
double _vx(int i) => i == 4 ? _mx(4) + 24 : _mx(i);

/// Between machine [l] and the next one: where the waiting bin parks.
double _binX(int l) => l >= 6 ? -150 : _sx(2.0 * l + 1) + 46;

/// Clickable area of machine i.
Rect _target(int i) => Rect.fromLTRB(_vx(i) - 80, 196, _vx(i) + (i == 6 ? 84 : 80), _beltTop + 12);

class _FactoryPipelineState extends State<FactoryPipeline> {
  final _power = _Power();

  @override
  Widget build(BuildContext context) {
    final step = SlideScope.of(context).step.clamp(0, 6);
    return SlideFrame(
      title: 'The pipeline',
      child: FactoryScene(
        painter: (clock, text, io) => _PipelinePainter(clock, text, io, step, _power),
        onTarget: (context, i) => DeckScope.read(context).goToId(_ids[i]),
      ),
    );
  }
}

/// When each machine powered on (local scene seconds; infinity = dark), and
/// where the tour group and the bin are headed. Updated by the painter on the
/// first frame after the build step changes.
class _Power {
  int step = -1;
  final on = List<double>.filled(7, double.infinity);
  double stepAt = 0;
  double groupFrom = 0, groupTo = 0, groupAt = 0;
  double binFrom = 0, binTo = 0, binAt = 0;

  static double groupX(int s) => _vx(s) - 14;

  double group(double t) {
    final d = (groupTo - groupFrom).abs();
    final dur = (d / 95).clamp(0.6, 4.0);
    return lerp(groupFrom, groupTo, eio(seg(t, groupAt, groupAt + dur)));
  }

  double binDur() => ((binTo - binFrom).abs() / 110).clamp(0.5, 14.0);

  double bin(double t) => lerp(binFrom, binTo, eio(seg(t, binAt, binAt + binDur())));

  void update(int s, double now) {
    if (s == step) return;
    if (step < 0) {
      // Arriving on the slide: power up in a quick cascade after the transition.
      for (var i = 0; i <= s; i++) {
        on[i] = now + 0.35 + 0.3 * i;
      }
      groupFrom = groupX(s) - 160;
      groupTo = groupX(s);
      groupAt = now + 0.2;
      binFrom = binTo = _binX(s);
      binAt = now;
    } else {
      var at = now + 0.05;
      for (var i = 0; i < 7; i++) {
        if (i <= s && on[i] == double.infinity) {
          on[i] = at;
          at += 0.3;
        } else if (i > s) {
          on[i] = double.infinity;
        }
      }
      groupFrom = group(now);
      groupTo = groupX(s);
      groupAt = now + 0.15;
      binFrom = bin(now);
      binTo = _binX(s);
      // Let the crate that is already tipping land before the bin moves on.
      binAt = s > step ? now + _per : now;
    }
    step = s;
    stepAt = now;
  }
}

class _PipelinePainter extends CustomPainter {
  _PipelinePainter(this.clock, this.text, this.io, this.step, this.power) : super(repaint: clock);

  final SceneClock clock;
  final TextCache text;
  final SceneInput io;
  final int step;
  final _Power power;

  @override
  void paint(Canvas canvas, Size size) {
    power.update(step, clock.local);
    io.targets
      ..clear()
      ..addAll([for (var i = 0; i < 7; i++) _target(i)]);
    _Line(canvas, clock.local, text, io, power).draw();
  }

  @override
  bool shouldRepaint(_PipelinePainter old) => old.step != step;
}

/// One unit on the line: a code point of the sample and what each machine
/// learns about it.
class _Unit {
  _Unit(this.index, this.cp, this.form, this.formName);

  final int index; // UTF-16 offset in the sample (all BMP here)
  final int cp;
  final String form; // what the crate shows once shaped (Arabic: joined form)
  final String formName; // init / medi / fina / isol, '' for non-Arabic

  String get char => String.fromCharCode(cp);
  bool get space => cp == 0x20;
  Script get script {
    final s = scriptOf(cp);
    // Common characters (the space) join the run before them.
    return s == Script.common ? Script.latin : s;
  }

  bool get rtl => script.rtl;
}

final _units = () {
  final runes = _sample.runes.toList();
  var off = 0;
  return [
    for (var i = 0; i < runes.length; i++)
      () {
        final (name, display) = arabicForm(runes, i);
        final u = _Unit(off, runes[i], display, name);
        off += runes[i] > 0xFFFF ? 2 : 1;
        return u;
      }(),
  ];
}();

final _boxCache = Expando<List<Rect>>();

class _Line extends FactoryInk {
  _Line(super.c, this.t, this.txt, this.io, this.pw) : cyc = (t / _per).floor() {
    ph = t / _per - cyc;
    e = ph < _mv ? eio(ph / _mv) : 1.0;
  }

  final double t;
  final TextCache txt;
  final SceneInput io;
  final _Power pw;
  final int cyc;
  late final double ph;
  late final double e;

  bool get dwell => ph >= _mv;

  /// Progress through [a, b] of the dwell (fractions of it).
  double dw(double a, double b) => seg(ph, _mv + a * (1 - _mv), _mv + b * (1 - _mv));

  bool powered(int i, double at) => pw.on[i] <= at;

  /// 0..1: how lit machine i is (with a flicker as it powers up).
  double lit(int i) {
    final a = t - pw.on[i];
    if (a < 0) return 0;
    if (a > 0.55) return 1;
    return rnd((a * 22).floor(), i, 3) > 0.45 ? 1 : 0.25;
  }

  int? get hover {
    final m = io.mouse;
    if (m == null) return null;
    for (var i = 0; i < 7; i++) {
      if (_target(i).contains(m)) return i;
    }
    return null;
  }

  double boost(int i, [double dur = 1.2]) => io.boost(i, t, dur);

  _Unit unit(int k) => _units[k % _units.length];

  /// The furthest slot crate [k] gets to: it drops at slot 0 in the dwell of
  /// cycle k and must find machine i powered when it leaves slot 2i-1 (at the
  /// start of cycle k+2i). -1 = never dropped; 2i-1 = tips into the bin
  /// there; [_endSlot] = reaches the screen.
  int reach(int k) {
    if (!powered(0, (k + _mv) * _per)) return -1;
    for (var i = 1; i < 7; i++) {
      if (!powered(i, (k + 2 * i) * _per)) return 2 * i - 1;
    }
    return _endSlot;
  }

  /// Crate k sits at work slot [slot] right now (dwell or arriving).
  bool crateAt(int k, int slot) => k >= 0 && cyc - k == slot && reach(k) >= slot;

  /// Has machine [i] finished with a crate at [pos]?
  bool done(double pos, int i, double a, double b) {
    final s = 2.0 * i;
    if (pos > s + 1e-3) return true;
    if (pos < s - 1e-3) return false;
    return dwell && dw(a, b) >= 1;
  }

  TextPainter mono(String s, double size, [Color col = BP.inkDim, double weight = 400]) =>
      txt.get(s, BT.mono(size, color: col, weight: weight));

  TextPainter sample(String s, double size, [Color col = BP.ink]) => txt.get(s, BT.sample(size, color: col));

  /// The sample laid out as a real paragraph, narrow enough that the greedy
  /// line breaker wraps after the space: "Hi " / "كتاب".
  TextPainter get para {
    final style = BT.sample(32, color: BP.ink);
    final w = math.max(txt.get('Hi ', style).width, txt.get('كتاب', style).width) + 6;
    return txt.get(_sample, style, maxWidth: w);
  }

  /// Each unit's box in [para] (bidi puts the Arabic ones right to left).
  List<Rect> get boxes {
    final p = para;
    return _boxCache[p] ??= [
      for (final u in _units)
        () {
          final b = p.getBoxesForSelection(TextSelection(baseOffset: u.index, extentOffset: u.index + 1));
          if (b.isEmpty) return Rect.zero;
          return b.map((e) => e.toRect()).reduce((a, c) => a.expandToInclude(c));
        }(),
    ];
  }

  /// Which line unit [u] lands on.
  int lineOf(_Unit u) {
    final lines = para.computeLineMetrics();
    if (lines.length < 2) return 1;
    final b = boxes[u.index];
    return b.center.dy > lines.first.height ? 2 : 1;
  }

  void draw() {
    catwalkBack();
    belts();
    machinesBack();
    crates();
    machinesFront();
    screen();
    floorCrew();
    bin();
    catwalk();
    labels();
  }

  /// Draw [body] for machine [i] faded to how lit it is.
  void machine(int i, void Function(double on) body) {
    final on = lit(i);
    dim = lerp(0.32, 1, on);
    body(on);
    dim = 1;
  }

  // ── Belts ─────────────────────────────────────────────────────────────────

  void belts() {
    for (var i = 0; i < 7; i++) {
      final x0 = i == 0 ? 20.0 : _sx(2.0 * i - 1) + 46;
      final x1 = i == 6 ? 1318.0 : _sx(2.0 * i + 1) + 46;
      final moving = powered(i, t);
      machine(i, (_) => conveyor(x0, x1, _beltTop, _floor, moving ? (cyc - 1 + e) * _pitch : 0, legEvery: 170));
    }
  }

  // ── Crates ────────────────────────────────────────────────────────────────

  void crates() {
    for (var k = cyc - _endSlot - 2; k <= cyc; k++) {
      if (k < 0) continue;
      final r = reach(k);
      if (r < 0) continue;
      final u = unit(k);
      if (k == cyc) {
        // Dropping out of the chute.
        if (!dwell) continue;
        final y = lerp(_crateTop - 70, _crateTop, ei(dw(0, 0.35))) - 3 * bump(dw(0.35, 0.5));
        c.save();
        c.clipRect(const Rect.fromLTRB(0, 392, 400, 700));
        unitCrate(Rect.fromLTWH(_sx(0) - _cw / 2, y, _cw, _ch), u, 0);
        c.restore();
        continue;
      }
      final pos = cyc - k - 1 + e;
      if (pos > r) {
        if (pos > r + 1) continue;
        final f = pos - r;
        if (r == _endSlot) continue;
        if (r == _endSlot - 1) {
          // Into the screen's intake.
          c.save();
          c.clipRect(const Rect.fromLTRB(0, 0, 1320, 700));
          unitCrate(Rect.fromLTWH(_sx(r + f) - _cw / 2, _crateTop, _cw, _ch), u, r + f);
          c.restore();
          continue;
        }
        // Off the end of the powered belt, into the bin.
        final x = _sx(r.toDouble()) + 44 * eo(f);
        final y = _crateTop + 78 * f * f;
        c.save();
        c.translate(x, y + _ch / 2);
        c.rotate(0.7 * f);
        unitCrate(Rect.fromLTWH(-_cw / 2, -_ch / 2, _cw, _ch), u, r.toDouble());
        c.restore();
        continue;
      }
      unitCrate(Rect.fromLTWH(_sx(pos) - _cw / 2, _crateTop, _cw, _ch), u, pos);
    }
  }

  /// A crate at belt position [pos]. What the machines it passed did shows
  /// on the crate itself: its script's colour (itemize), the glyph (fonts),
  /// the joined form (shape), a tab for the second line (wrap), pixels (raster).
  void unitCrate(Rect r, _Unit u, double pos) {
    final sorted = done(pos, 1, 0, 0.35);
    final fonted = done(pos, 2, 0, 0.42);
    final shaped = done(pos, 3, 0, 0.2);
    final wrapped = done(pos, 4, 0, 0.3);
    final baked = done(pos, 6, 0, 0.62);
    final sc = u.script.color;
    final col = baked ? BP.line : (sorted ? sc : BP.inkDim);
    c.drawRect(r, fl(BP.panel));
    c.drawRect(r, st(col, sorted ? 1.8 : 1.2));
    final strip = r.top + 7;
    c.drawLine(Offset(r.left, strip), Offset(r.right, strip), st(col.withValues(alpha: 0.5), 0.8));
    if (wrapped && lineOf(u) == 2) {
      c.drawRect(Rect.fromLTRB(r.right - 16, r.top + 2, r.right - 4, strip - 2), fl(BP.violet));
    }
    final body = Rect.fromLTRB(r.left + 3, strip + 1, r.right - 3, r.bottom - 2);
    if (baked) {
      pixels(txt.raster(u.space ? '·' : (shaped ? u.form : u.char), BT.sample(14)), body);
    } else if (fonted) {
      if (u.space) {
        c.drawLine(body.bottomLeft.translate(18, -6), body.bottomRight.translate(-18, -6), st(BP.inkFaint, 1));
      } else {
        paintFit(sample(shaped ? u.form : u.char, 34, shaped ? BP.ink : BP.inkDim), body, fitHeight: true);
      }
    } else {
      final b = body.deflate(5);
      c.drawLine(b.topLeft, b.bottomRight, st(BP.lineFaint, 1));
      c.drawLine(b.bottomLeft, b.topRight, st(BP.lineFaint, 1));
    }
  }

  // ── Machines ──────────────────────────────────────────────────────────────

  void machinesBack() {
    hopper();
    sorter();
    vending();
    pressFrame();
    cutterFrame();
    gantryFrame();
  }

  void machinesFront() {
    sorterArm();
    vendingDrop();
    ram();
    blade();
    trolley();
    oven();
  }

  /// 0 · text: the chute the string goes into; the character whose crate is
  /// dropping lights up in its window.
  void hopper() {
    final x = _mx(0);
    machine(0, (on) {
      final funnel = Path()
        ..moveTo(x - 70, 262)
        ..lineTo(x + 70, 262)
        ..lineTo(x + 34, 330)
        ..lineTo(x - 34, 330)
        ..close();
      c.drawPath(funnel, fl(BP.panel));
      c.drawPath(funnel, st(BP.line, 1.4));
      box(Rect.fromLTRB(x - 36, 330, x + 36, 392));
      c.drawLine(Offset(x - 40, 392), Offset(x + 40, 392), st(BP.line, 2));
      final win = Rect.fromLTRB(x - 48, 268, x + 48, 300);
      c.drawRect(win, st(BP.lineDim, 1));
      final style = BT.sample(22, color: on > 0.5 ? BP.inkDim : BP.inkFaint);
      final str = txt.get(_sample, style);
      final at = Offset(win.center.dx - str.width / 2, win.center.dy - str.height / 2);
      str.paint(c, at);
      // The character going down the chute right now (or the last one).
      final k = dwell ? cyc : cyc - 1;
      if (on >= 1 && k >= 0 && reach(k) >= 0 && !unit(k).space) {
        final hot = txt.get(_sample, BT.sample(22, color: BP.amber));
        final u = unit(k);
        final b = hot.getBoxesForSelection(TextSelection(baseOffset: u.index, extentOffset: u.index + 1));
        if (b.isNotEmpty) {
          c.save();
          c.clipRect(b.map((e) => e.toRect()).reduce((a, c) => a.expandToInclude(c)).shift(at));
          hot.paint(c, at);
          c.restore();
        }
      }
      final dropping = on > 0 && crateAt(cyc, 0) && dwell && dw(0, 0.4) < 1;
      lamp(Offset(x + 22, 346), BP.amber, dropping || boost(0) > 0);
      lamp(Offset(x + 22, 362), BP.green, on >= 1, 3.5);
    });
  }

  /// 1 · itemize: a sorter reads each code point's script and paints the
  /// crate with its run's colour.
  void sorter() {
    final x = _mx(1);
    machine(1, (on) {
      final roof = Path()
        ..moveTo(x - 58, 280)
        ..lineTo(x - 42, 264)
        ..lineTo(x + 42, 264)
        ..lineTo(x + 58, 280)
        ..close();
      c.drawPath(roof, fl(BP.panel));
      c.drawPath(roof, st(BP.line, 1.3));
      box(Rect.fromLTRB(x - 58, 280, x + 58, 376));
      for (final lx in [x - 52, x + 52]) {
        c.drawLine(Offset(lx, 376), Offset(lx, _beltTop), st(BP.line, 1.2));
      }
      final scr = Rect.fromLTRB(x - 46, 292, x + 46, 320);
      c.drawRect(scr, st(BP.lineDim, 1));
      // The crate under the arm (or, while the belt moves, the last one).
      _Unit? u;
      if (on >= 1) {
        final k = dwell ? cyc - 2 : cyc - 3;
        if (k >= 0 && reach(k) >= 2) u = unit(k);
      }
      if (u != null) {
        // The run's direction, in its script's colour.
        final col = u.script.color;
        final d = u.rtl ? -1.0 : 1.0;
        final y = scr.center.dy;
        final tip = Offset(x + d * 30, y);
        c.drawRect(scr.deflate(3), fl(col.withValues(alpha: 0.14)));
        c.drawLine(Offset(x - d * 30, y), tip, st(col, 3));
        c.drawPath(
          Path()
            ..moveTo(tip.dx - d * 10, y - 8)
            ..lineTo(tip.dx, y)
            ..lineTo(tip.dx - d * 10, y + 8),
          st(col, 3),
        );
      }
      // Run lamps: latin, arabic.
      for (var j = 0; j < 2; j++) {
        final s = j == 0 ? Script.latin : Script.arabic;
        lamp(Offset(x - 12 + j * 24.0, 350), s.color, (u != null && u.script == s) || boost(1) > 0, 4.5);
      }
    });
  }

  void sorterArm() {
    final x = _mx(1);
    machine(1, (on) {
      var gy = 384.0;
      if (on >= 1 && crateAt(cyc - 2, 2) && dwell) {
        final down = eio(dw(0, 0.2));
        final up = eio(dw(0.55, 0.85));
        gy = lerp(384, _crateTop - 2, down * (1 - up));
      }
      c.drawLine(Offset(x, 376), Offset(x, gy - 3), st(BP.line, 2.2));
      c.drawLine(Offset(x - 16, gy - 3), Offset(x + 16, gy - 3), st(BP.line, 1.8));
      c.drawLine(Offset(x - 16, gy - 3), Offset(x - 18, gy + 4), st(BP.line, 1.5));
      c.drawLine(Offset(x + 16, gy - 3), Offset(x + 18, gy + 4), st(BP.line, 1.5));
    });
  }

  /// 2 · fonts: a vending machine with two shelves, one per family in the
  /// fallback list. The first family that has the glyph dispenses it.
  static const _shelf = [
    ['H', 'i', 'a', 'b'],
    ['ك', 'ت', 'ا', 'ب'],
  ];

  Rect _cell(int row, int col) => Rect.fromLTWH(_mx(2) - 48 + col * 24.0, 266 + row * 36.0, 24, 34);

  _Unit? _atFonts(double on) {
    if (on < 1 || !dwell || !crateAt(cyc - 4, 4)) return null;
    return unit(cyc - 4);
  }

  void vending() {
    final x = _mx(2);
    machine(2, (on) {
      box(Rect.fromLTRB(x - 56, 256, x + 56, 382));
      for (final lx in [x - 50, x + 50]) {
        c.drawLine(Offset(lx, 382), Offset(lx, _beltTop), st(BP.line, 1.2));
      }
      c.drawRect(Rect.fromLTRB(x - 50, 262, x + 50, 338), st(BP.lineDim, 1));
      final u = _atFonts(on);
      final pick = u == null || dw(0, 0.42) >= 1 ? null : u;
      for (var row = 0; row < 2; row++) {
        for (var col = 0; col < 4; col++) {
          final r = _cell(row, col);
          final g = _shelf[row][col];
          final hot = pick != null && (pick.char == g || (pick.space && row == 0 && col == 0));
          c.drawRect(r.deflate(1.5), st(hot ? BP.amber : BP.lineFaint, hot ? 1.6 : 1));
          paintFit(sample(g, 18, hot ? BP.amber : BP.inkDim), r.deflate(4), fitHeight: true);
        }
      }
      // Which shelf (font) answered: the first one, or the fallback.
      final shown = u ?? (on >= 1 && cyc >= 5 && reach(cyc - 5) >= 4 ? unit(cyc - 5) : null);
      for (var row = 0; row < 2; row++) {
        lamp(Offset(x - 40 + row * 16.0, 349), row == 0 ? BP.line : BP.amber, shown != null && shown.rtl == (row == 1), 4);
      }
      c.drawRect(Rect.fromLTRB(x - 14, 364, x + 14, 382), st(BP.line, 1.2));
      if (boost(2) > 0) {
        for (var col = 0; col < 4; col++) {
          c.drawRect(_cell((t * 6).floor() % 2, col).deflate(1.5), st(BP.amber, 1.4));
        }
      }
    });
  }

  void vendingDrop() {
    final u = _atFonts(lit(2));
    if (u == null || u.space) return;
    final a = dw(0.08, 0.42);
    if (a <= 0 || a >= 1) return;
    final y = lerp(372, _crateTop + 26, ei(a));
    paintFit(sample(u.char, 20, BP.amber), Rect.fromCenter(center: Offset(_mx(2), y), width: 30, height: 24), fitHeight: true);
  }

  /// 3 · shape: a stamping press. Latin crates get their glyph id from the
  /// font's cmap; Arabic ones come out in their joined forms.
  void pressFrame() {
    final x = _mx(3);
    machine(3, (on) {
      box(Rect.fromLTRB(x - 52, 262, x + 52, 294));
      box(Rect.fromLTRB(x - 48, 294, x - 38, _beltTop), w: 1.1);
      box(Rect.fromLTRB(x + 38, 294, x + 48, _beltTop), w: 1.1);
      final fw = Offset(x + 68, 274);
      c.drawCircle(fw, 14, fl(BP.panel));
      c.drawCircle(fw, 14, st(BP.line, 1.3));
      final a = on >= 1 ? (t - pw.on[3]) * (3.2 + 8 * boost(3)) : 0.0;
      final sp = Path();
      for (var i = 0; i < 3; i++) {
        final d = Offset(math.cos(a + i * 2.094), math.sin(a + i * 2.094)) * 12;
        sp
          ..moveTo(fw.dx, fw.dy)
          ..lineTo(fw.dx + d.dx, fw.dy + d.dy);
      }
      c.drawPath(sp, st(BP.line, 1.2));
      c.drawLine(fw, Offset(x + 52, 268), st(BP.lineDim, 1));
      gauge(Offset(x - 30, 278), 9, on >= 1 ? 0.35 + 0.5 * (dwell ? 1 - dw(0.2, 1) : ph / _mv) : 0);
    });
  }

  void ram() {
    final x = _mx(3);
    machine(3, (on) {
      var y = 356.0;
      var impact = -1.0;
      if (on >= 1 && crateAt(cyc - 6, 6) && dwell) {
        final down = ei(dw(0, 0.18));
        final up = eio(dw(0.35, 0.8));
        y = lerp(356, _crateTop, down * (1 - up));
        impact = dw(0.18, 0.7);
      }
      c.drawLine(Offset(x, 294), Offset(x, y - 26), st(BP.line, 4));
      final r = Rect.fromLTRB(x - 26, y - 26, x + 26, y);
      box(r, w: 1.4);
      c.drawLine(Offset(r.left + 4, y - 7), Offset(r.right - 4, y - 7), st(BP.lineDim, 1));
      if (impact > 0 && impact < 1) {
        for (final sg in [-1.0, 1.0]) {
          for (var i = 0; i < 2; i++) {
            puff(Offset(x + sg * (38 + impact * (10 + 8 * i)), _beltTop - 8 - i * 6 - impact * 8), c01(impact + i * 0.1), 2, 6 + 2.5 * i);
          }
        }
      }
      if (boost(3) > 0) sparks(Offset(x, y + 2), seg(t, io.targetAt, io.targetAt + 0.8), 7);
    });
  }

  /// 4 · wrap: a guillotine with a width ruler. Greedy breaking: it only
  /// cuts at a break opportunity (after the space) when the line is full.
  static const _bladeX = 866.0;

  bool _cutting(double on) => on >= 1 && dwell && crateAt(cyc - 8, 8) && unit(cyc - 8).space;

  void cutterFrame() {
    const bx = _bladeX;
    machine(4, (on) {
      box(const Rect.fromLTRB(bx - 60, 270, bx + 60, 298));
      for (final px in [bx - 56, bx + 56]) {
        c.drawLine(Offset(px - 2, 298), Offset(px - 2, _beltTop), st(BP.line, 1.2));
        c.drawLine(Offset(px + 2, 298), Offset(px + 2, _beltTop), st(BP.line, 1.2));
      }
      for (var xx = bx - 52; xx <= bx + 52; xx += 8) {
        c.drawLine(Offset(xx, 298), Offset(xx, (xx - bx + 52) % 32 == 0 ? 305 : 302), st(BP.lineDim, 1));
      }
      final cut = _cutting(on);
      final passing = on >= 1 && dwell && crateAt(cyc - 8, 8) && !cut;
      lamp(const Offset(bx + 30, 284), BP.green, passing || boost(4) > 0, 4);
      lamp(const Offset(bx + 44, 284), BP.amber, cut || boost(4) > 0, 4);
    });
  }

  void blade() {
    const bx = _bladeX;
    machine(4, (on) {
      var bottom = 372.0;
      var cut = -1.0;
      if (_cutting(on)) {
        bottom = lerp(372, _beltTop + 4, ei(dw(0.05, 0.2)) * (1 - eio(dw(0.45, 0.85))));
        cut = dw(0.18, 0.55);
      }
      c.drawLine(const Offset(bx, 298), Offset(bx, bottom - 44), st(BP.line, 3));
      final b = Path()
        ..moveTo(bx - 7, bottom - 44)
        ..lineTo(bx + 7, bottom - 44)
        ..lineTo(bx + 7, bottom)
        ..lineTo(bx - 7, bottom - 8)
        ..close();
      c.drawPath(b, fl(BP.panel));
      c.drawPath(b, st(BP.line, 1.4));
      c.drawLine(Offset(bx - 7, bottom - 8), Offset(bx + 7, bottom), st(BP.ink, 2));
      if (cut > 0 && cut < 1) sparks(const Offset(bx, _beltTop - 6), cut, cyc);
    });
  }

  /// 5 · position: a gantry reads each glyph's box in the laid-out paragraph
  /// (shown on its board) and marks the crate with its x.
  static const _board = Rect.fromLTRB(952, 246, 1056, 312);

  (Rect, double) _boardFit() {
    final p = para;
    final inner = _board.deflate(6);
    final s = math.min(inner.width / p.width, inner.height / p.height);
    final o = Offset(inner.center.dx - p.width * s / 2, inner.center.dy - p.height * s / 2);
    return (o & Size(p.width * s, p.height * s), s);
  }

  _Unit? _atGantry(double on) => on >= 1 && dwell && crateAt(cyc - 10, 10) ? unit(cyc - 10) : null;

  void gantryFrame() {
    final x = _mx(5);
    machine(5, (on) {
      for (final px in [x - 68, x + 68]) {
        c.drawLine(Offset(px, 318), Offset(px, _beltTop), st(BP.line, 1.4));
        c.drawLine(Offset(px - 8, _beltTop), Offset(px + 8, _beltTop), st(BP.line, 1.4));
      }
      box(Rect.fromLTRB(x - 76, 316, x + 76, 330), w: 1.3);
      // The board: the real paragraph, current glyph boxed.
      box(_board, col: BP.lineDim, w: 1);
      final (r, s) = _boardFit();
      c.save();
      c.translate(r.left, r.top);
      c.scale(s);
      para.paint(c, Offset.zero);
      c.restore();
      final u = _atGantry(on);
      if (u != null) {
        final b = boxes[u.index];
        final hb = Rect.fromLTRB(r.left + b.left * s, r.top + b.top * s, r.left + b.right * s, r.top + b.bottom * s);
        c.drawRect(hb.inflate(1), st(BP.amber, 1.2));
        c.drawPath(dashPath(Path()
          ..moveTo(hb.center.dx, _board.bottom)
          ..lineTo(trolleyX(), 316), dash: 3, gap: 3), st(BP.amber.withValues(alpha: 0.7), 1));
      }
      c.drawLine(Offset(_board.left + 10, _board.bottom), Offset(_board.left + 10, 316), st(BP.lineDim, 1));
      c.drawLine(Offset(_board.right - 10, _board.bottom), Offset(_board.right - 10, 316), st(BP.lineDim, 1));
    });
  }

  double _glyphX(_Unit u) {
    final (r, s) = _boardFit();
    return r.left + boxes[u.index].center.dx * s;
  }

  double trolleyX() {
    final x = _mx(5);
    final on = lit(5);
    if (on < 1) return x;
    final k = cyc - 10;
    final now = crateAt(k, 10) ? _glyphX(unit(k)) : x;
    final prev = k - 1 >= 0 && reach(k - 1) >= 10 ? _glyphX(unit(k - 1)) : x;
    if (!dwell) return prev;
    return lerp(prev, now, eio(dw(0, 0.3)));
  }

  void trolley() {
    machine(5, (on) {
      final tx = trolleyX();
      box(Rect.fromLTRB(tx - 12, 330, tx + 12, 342), w: 1.2);
      var hook = 356.0;
      if (_atGantry(on) != null) {
        hook = lerp(356, _crateTop - 2, eio(dw(0.3, 0.45)) * (1 - eio(dw(0.6, 0.85))));
      }
      c.drawLine(Offset(tx, 342), Offset(tx, hook - 6), st(BP.inkDim, 1));
      // Caliper jaws.
      c.drawLine(Offset(tx - 9, hook - 6), Offset(tx + 9, hook - 6), st(BP.amber, 1.8));
      c.drawLine(Offset(tx - 9, hook - 6), Offset(tx - 9, hook + 2), st(BP.amber, 1.4));
      c.drawLine(Offset(tx + 9, hook - 6), Offset(tx + 9, hook + 2), st(BP.amber, 1.4));
      if (_atGantry(on) != null && dw(0.45, 0.55) > 0 && dw(0.45, 0.55) < 1) {
        star(Offset(tx, _crateTop - 4), 6, BP.amber);
      }
    });
  }

  /// 6 · raster: the oven bakes outlines into pixel coverage. Its front is
  /// drawn over the crates, with a window onto the belt.
  void oven() {
    final x = _mx(6);
    machine(6, (on) {
      final body = Rect.fromLTRB(x - 76, 284, x + 76, 474);
      final win = Rect.fromLTRB(x - 60, 398, x + 60, 464);
      final shell = Path()
        ..fillType = PathFillType.evenOdd
        ..addRect(body)
        ..addRect(win);
      c.drawPath(shell, fl(BP.panel));
      c.drawRect(body, st(BP.line, 1.4));
      c.drawRect(win, st(BP.line, 1.2));
      final chimney = Rect.fromLTRB(x + 44, 250, x + 60, 284);
      box(chimney, w: 1.3);
      c.drawLine(Offset(chimney.left - 4, chimney.top), Offset(chimney.right + 4, chimney.top), st(BP.line, 2));
      final baking = on >= 1 && dwell && crateAt(cyc - 12, 12);
      final heat = baking ? bump(dw(0, 1)) : 0.0;
      final flick = 0.5 + 0.5 * math.sin(t * 7.3) * math.sin(t * 2.9 + 1);
      if (on > 0) {
        final coil = Path()..moveTo(win.left + 6, win.top + 6);
        for (var i = 1; i <= 13; i++) {
          coil.lineTo(win.left + 6 + i * 8.3, win.top + (i.isEven ? 6 : 11));
        }
        c.drawPath(coil, st(BP.coral.withValues(alpha: (0.35 + 0.25 * flick + 0.4 * heat) * on), 1.3));
        steam(Offset(x + 52, 244), t, per: 0.5 - 0.2 * boost(6), life: 2.4, rise: 40, r: 9 + 6 * heat + 8 * boost(6), seed: 6, until: double.infinity);
      }
      gauge(Offset(x - 50, 316), 14, on >= 1 ? 0.45 + 0.15 * math.sin(t * 0.8) + 0.3 * heat + 0.2 * boost(6) : 0);
      for (var i = 0; i < 3; i++) {
        lamp(Offset(x + 16.0 + i * 16, 312), [BP.green, BP.amber, BP.red][i], on >= 1 && (rnd((t * 2).floor(), i, 5) > 0.45 || boost(6) > 0));
      }
      for (var y = 346.0; y < 386; y += 7) {
        c.drawLine(Offset(x + 6, y), Offset(x + 66, y), st(BP.lineFaint, 1));
      }
      // Firebox on the floor.
      final fb = Rect.fromLTRB(x + 20, 566, x + 60, _floor);
      box(fb, w: 1.2);
      final last = ((t / 2.4 - 0.87).floor() + 0.87) * 2.4;
      if (on > 0) {
        c.drawRect(fb.deflate(8), fl(BP.amber.withValues(alpha: (0.15 + 0.4 * math.exp(-(t - last) * 1.8)) * on)));
      }
    });
  }

  /// The end of the line: a screen that lights each glyph where layout put it.
  void screen() {
    final on = lit(6);
    dim = lerp(0.32, 1, on);
    const base = Rect.fromLTRB(1322, 386, 1470, 474);
    const scr = Rect.fromLTRB(1330, 252, 1466, 372);
    for (final lx in [1340.0, 1452.0]) {
      c.drawLine(Offset(lx, base.bottom), Offset(lx, _floor), st(BP.line, 1.4));
      c.drawLine(Offset(lx - 8, _floor), Offset(lx + 8, _floor), st(BP.line, 1.4));
    }
    box(base, w: 1.3);
    c.drawRect(const Rect.fromLTRB(1322, 402, 1330, 458), st(BP.line, 1.2));
    for (var y = 420.0; y < 462; y += 7) {
      c.drawLine(Offset(1360, y), Offset(1456, y), st(BP.lineFaint, 1));
    }
    c.drawLine(Offset(scr.center.dx, scr.bottom), Offset(scr.center.dx, base.top), st(BP.line, 2));
    box(scr, w: 1.6);
    final inner = scr.deflate(9);
    c.drawRect(inner, st(BP.lineDim, 1));
    dim = 1;
    // What has arrived: the newest crate through the intake and the ones
    // before it in the same word; the previous word lingers, dim.
    var last = -1;
    for (var k = cyc - _endSlot; k >= cyc - _endSlot - 8 && k >= 0; k--) {
      if (k == cyc - _endSlot && !dwell) continue;
      if (reach(k) == _endSlot) {
        last = k;
        break;
      }
    }
    if (on < 1) {
      for (var y = inner.top + 4; y < inner.bottom; y += 6) {
        c.drawLine(Offset(inner.left + 2, y), Offset(inner.right - 2, y), st(BP.lineFaint.withValues(alpha: 0.6), 1));
      }
      return;
    }
    // The laid-out paragraph waits on the screen, faint; each glyph lights up
    // as its crate arrives (the newest one amber).
    final p = para;
    final style = BT.sample(32, color: BP.inkFaint);
    final w = math.max(txt.get('Hi ', style).width, txt.get('كتاب', style).width) + 6;
    final ghost = txt.get(_sample, style, maxWidth: w);
    final hotStyle = BT.sample(32, color: BP.amber);
    final hot = txt.get(_sample, hotStyle, maxWidth: w);
    final s = math.min((inner.width - 16) / p.width, (inner.height - 12) / p.height);
    final o = Offset(inner.center.dx - p.width * s / 2, inner.center.dy - p.height * s / 2);
    final n = _units.length;
    final rep = last < 0 ? 0 : last ~/ n, idx = last < 0 ? -1 : last % n;
    final age = last < 0 ? 1e9 : t - (last + _endSlot + _mv) * _per;
    c.save();
    c.translate(o.dx, o.dy);
    c.scale(s);
    for (var j = 0; j < n; j++) {
      if (_units[j].space) continue;
      final arrived = j <= idx && reach(rep * n + j) == _endSlot;
      final b = boxes[j].inflate(1);
      c.save();
      c.clipRect(b);
      (arrived ? (j == idx && age < 0.5 ? hot : p) : ghost).paint(c, Offset.zero);
      c.restore();
    }
    c.restore();
    lamp(Offset(scr.right - 12, scr.bottom - 7), BP.green, last >= 0 && (age < 0.3 || (t * 1.5) % 2 < 1.4), 3);
  }

  // ── People ────────────────────────────────────────────────────────────────

  Limbs guy(Offset feet, double h, int dir, Pose f, {Color hat = BP.amber}) {
    final m = io.mouse;
    if (m != null && (m - feet.translate(0, -h * 0.55)).distance < h * 0.7) f.wave(t);
    return worker(feet, h, dir, f, hat: hat);
  }

  double _opX(int i) => i == 6 ? _mx(6) + 96 : _mx(i) + (i == 5 ? 80 : 64);

  void floorCrew() {
    for (var i = 0; i < 7; i++) {
      final x = _opX(i);
      final feet = Offset(x, _floor);
      final a = t - pw.on[i];
      if (a < 0) {
        // Asleep on an upturned crate.
        box(Rect.fromLTRB(x - 9, _floor - 12, x + 9, _floor), col: BP.lineDim, w: 1);
        final f = Pose()
          ..sit(32, 12)
          ..lean = 0.22
          ..head = 0.55
          ..upA = 0.75
          ..foA = 1.5
          ..upB = 0.65
          ..foB = 1.45;
        dim = 0.6;
        final g = guy(feet, 32, -1, f);
        dim = 1;
        zees(g.head, t + i * 0.37, -1);
        continue;
      }
      if (a < 1.1) {
        // Power's on: jump up, stretch.
        final f = Pose()..cheer(t, i);
        final g = guy(feet, 34, -1, f);
        if (a < 0.6) alarm(g.head, t);
        continue;
      }
      _work(i, feet);
    }
  }

  void _work(int i, Offset feet) {
    final f = Pose();
    final x = feet.dx;
    switch (i) {
      case 0: // pulls the chute's gate lever for every drop
        final pull = dwell && crateAt(cyc, 0) ? eo(dw(0, 0.2)) * (1 - eio(dw(0.5, 0.85))) : 0.0;
        f
          ..upA = lerp(2.4, 1.25, pull)
          ..foA = lerp(2.75, 1.6, pull)
          ..lean = 0.12 * pull;
        final g = guy(feet, 34, -1, f);
        box(Rect.fromLTRB(x - 40, _floor - 20, x - 22, _floor), w: 1.1);
        c.drawLine(Offset(x - 31, _floor - 18), g.handA, st(BP.line, 1.6));
        c.drawCircle(g.handA, 2.6, fl(BP.amber));
      case 1: // types each script into the sorter's console
        final busy = dwell && crateAt(cyc - 2, 2);
        f
          ..upA = 1.15
          ..foA = 1.5 + (busy ? 0.25 * math.sin(t * 18) : 0)
          ..upB = 1.05
          ..foB = 1.45 + (busy ? 0.25 * math.sin(t * 18 + 1.6) : 0)
          ..head = 0.25;
        box(Rect.fromLTRB(x - 44, _floor - 26, x - 20, _floor), w: 1.1);
        c.drawLine(Offset(x - 44, _floor - 26), Offset(x - 16, _floor - 30), st(BP.line, 1.2));
        guy(feet, 34, -1, f);
      case 2: // presses the vending machine's button
        final press = dwell && crateAt(cyc - 4, 4) ? bump(dw(0, 0.4)) : 0.0;
        f
          ..point(lerp(0.5, 2.0, press))
          ..head = -0.25 * press;
        guy(feet, 34, -1, f);
      case 3: // the press lever
        final pull = dwell && crateAt(cyc - 6, 6) ? eo(dw(0, 0.2)) * (1 - eio(dw(0.5, 0.85))) : 0.0;
        f
          ..upA = lerp(2.4, 1.25, pull)
          ..foA = lerp(2.75, 1.6, pull)
          ..lean = 0.12 * pull;
        final g = guy(feet, 34, -1, f);
        box(Rect.fromLTRB(x - 40, _floor - 20, x - 22, _floor), w: 1.1);
        c.drawLine(Offset(x - 31, _floor - 18), g.handA, st(BP.line, 1.6));
        c.drawCircle(g.handA, 2.6, fl(BP.amber));
      case 4: // measures the line; calls the cut
        final cut = _cutting(1) ? bump(dw(0, 0.7)) : 0.0;
        f
          ..head = 0.15 + 0.08 * math.sin(t * 2)
          ..upB = 1.0
          ..foB = 1.9;
        if (cut > 0) f.point(lerp(0.4, 2.5, cut));
        final g = guy(feet, 34, -1, f);
        clipboard(g.handB, done: cut > 0.5);
      case 5: // drives the gantry from a pendant
        f
          ..upA = 1.0
          ..foA = 1.75
          ..head = -0.2;
        final g = guy(feet, 34, -1, f);
        final pend = Rect.fromCenter(center: g.handA + const Offset(-3, -3), width: 7, height: 11);
        c.drawLine(Offset(_mx(5) + 74, 330), pend.topCenter, st(BP.inkDim, 1));
        box(pend, w: 1);
        lamp(pend.center, BP.amber, _atGantry(1) != null && (t * 8).floor().isEven, 1.8);
      default: // stokes the oven
        const per = 2.4;
        final p = (t / per) % 1;
        final toss = p >= 0.45;
        if (!toss) {
          final sc = bump(seg(p, 0.05, 0.42));
          f
            ..lean = 0.2 + 0.45 * sc
            ..upA = 0.6
            ..foA = 0.9 + 0.3 * sc
            ..upB = 0.3
            ..foB = 0.95;
        } else {
          final sw = eo(seg(p, 0.45, 0.65)) * (1 - eio(seg(p, 0.75, 1)));
          f
            ..lean = 0.3 - 0.2 * sw
            ..upA = lerp(0.7, 1.5, sw)
            ..foA = lerp(0.9, 1.75, sw)
            ..upB = lerp(0.4, 1.2, sw)
            ..foB = lerp(1.0, 1.8, sw);
        }
        final g = guy(feet, 34, toss ? -1 : 1, f);
        shovel(g.handB, g.handA, 11);
        c.drawPath(
          Path()
            ..moveTo(x + 16, _floor)
            ..quadraticBezierTo(x + 28, _floor - 16, x + 40, _floor),
          st(BP.lineDim, 1.2),
        );
    }
  }

  /// The bin that catches crates at the first dark machine; its minder
  /// pulls it along whenever the next machine comes on.
  void bin() {
    final x = pw.bin(t);
    if (x < -120) return;
    final moving = t > pw.binAt && t < pw.binAt + pw.binDur() && (pw.binTo - pw.binFrom).abs() > 1;
    final dir = pw.binTo >= pw.binFrom ? 1 : -1;
    // Pile inside (crates that tipped in earlier).
    if (pw.step < 6 && t > pw.on[0] + 3 * _per) {
      for (final (dx, dy, g) in [(-34.0, 488.0, 0), (2.0, 492.0, 3)]) {
        final r = Rect.fromLTWH(x + dx, dy, 32, 26);
        c.drawRect(r, fl(BP.panel));
        c.drawRect(r, st(_units[g].script.color.withValues(alpha: 0.7), 1));
      }
    }
    final cage = Rect.fromLTRB(x - 40, 498, x + 40, 584);
    c.drawRect(cage, fl(BP.panel.withValues(alpha: 0.85)));
    final mesh = Path();
    for (var xx = cage.left + 10; xx < cage.right; xx += 10) {
      mesh
        ..moveTo(xx, cage.top)
        ..lineTo(xx, cage.bottom);
    }
    for (var yy = cage.top + 12; yy < cage.bottom; yy += 12) {
      mesh
        ..moveTo(cage.left, yy)
        ..lineTo(cage.right, yy);
    }
    c.drawPath(mesh, st(BP.lineFaint, 1));
    c.drawRect(cage, st(BP.line, 1.3));
    c.drawLine(cage.topLeft.translate(-3, 0), cage.topRight.translate(3, 0), st(BP.line, 2));
    final roll = x / 5;
    for (final wx in [cage.left + 12, cage.right - 12]) {
      final w = Offset(wx, _floor - 8);
      c.drawCircle(w, 8, fl(BP.panel));
      c.drawCircle(w, 8, st(BP.line, 1.2));
      c.drawLine(w, w + Offset(math.cos(roll), math.sin(roll)) * 8, st(BP.line, 1));
    }
    // The minder.
    final f = Pose();
    Offset feet;
    int fd;
    if (moving) {
      feet = Offset(x + dir * 58, _floor);
      fd = dir;
      f
        ..walk(x / 5, amp: 0.38)
        ..lean = 0.18
        ..upB = -0.7
        ..foB = -0.5;
    } else {
      feet = Offset(x + 54, _floor);
      fd = -1;
      final ep = ((t - pw.binAt) / 5).floor();
      if (rnd(ep, 7) < 0.4) {
        f.watch();
      } else {
        f
          ..upA = 0.9
          ..foA = 2.2
          ..head = 0.25;
      }
    }
    final g = guy(feet, 32, fd, f);
    if (moving) c.drawLine(g.handB, Offset(x + dir * 40, cage.top + 6), st(BP.line, 1.3));
  }

  // ── Catwalk & labels ──────────────────────────────────────────────────────

  void catwalkBack() {
    for (final x in [300.0, 900.0, 1400.0]) {
      c.drawLine(Offset(x, 0), Offset(x, _walkY - 26), st(BP.lineFaint, 1));
    }
    for (var i = 0; i < 7; i++) {
      final x = _vx(i);
      machine(i, (on) {
        hangingLamp(Offset(x, _walkY + 2), _walkY + 44, 250, on, spread: 50);
        if (i == pw.step && on > 0) {
          // This step's stage: its lamp throws a spotlight down to the belt.
          final cone = Path()
            ..moveTo(x - 9, _walkY + 52)
            ..lineTo(x + 9, _walkY + 52)
            ..lineTo(x + 96, _beltTop + 10)
            ..lineTo(x - 96, _beltTop + 10)
            ..close();
          c.drawPath(cone, fl(BP.amber.withValues(alpha: 0.07 * on)));
        }
      });
    }
  }

  void catwalk() {
    // The tour group, watching the newest machine from above.
    final gx = pw.group(t);
    final dur = ((pw.groupTo - pw.groupFrom).abs() / 95).clamp(0.6, 4.0);
    final walking = t > pw.groupAt && t < pw.groupAt + dur && (pw.groupTo - pw.groupFrom).abs() > 1;
    final dir = walking && pw.groupTo < pw.groupFrom ? -1 : 1;
    final newest = pw.step >= 0 ? t - pw.on[pw.step] : -1.0;
    final cheer = !walking && newest > 0.3 && newest < 1.8;
    const h = 26.0;
    for (var i = 3; i >= 1; i--) {
      final vx = gx - dir * (i * h * 0.95 + (i == 3 ? 3 : 0));
      final f = Pose();
      if (walking) {
        f.walk(gx / 5 + i * 1.7, amp: 0.36);
      } else if (cheer) {
        f.cheer(t, i * 3);
      } else {
        f.head = 0.3 + 0.05 * math.sin(t + i);
        if (i == 2 && rnd((t / 5).floor(), 11) < 0.5) {
          f
            ..upA = 1.9
            ..foA = 2.9
            ..upB = 1.8
            ..foB = 2.8
            ..head = 0.1;
        }
      }
      final m = io.mouse;
      final feet = Offset(vx, _walkY);
      if (m != null && (m - feet.translate(0, -h * 0.55)).distance < h * 0.7) f.wave(t);
      final g = worker(feet, h * 0.92, dir, f, hat: BP.line, ink: BP.inkDim, back: BP.inkFaint);
      if (i == 2 && !walking && !cheer && rnd((t / 5).floor(), 11) < 0.5) {
        final cam = Rect.fromCenter(center: g.handA + Offset(dir * 2.0, -2), width: 7, height: 5);
        box(cam, col: BP.inkDim, w: 1);
        if ((t * 0.7 + 0.3) % 5 < 0.12) star(cam.center, 6, BP.ink);
      }
    }
    final f = Pose();
    if (walking) f.walk(gx / 5, amp: 0.4);
    f
      ..upB = 2.65
      ..foB = 2.85;
    if (!walking) {
      f
        ..point(0.75 + 0.06 * math.sin(t * 2))
        ..head = 0.35;
    }
    final g = guy(Offset(gx, _walkY), h, dir, f, hat: BP.green);
    flag(g.handB, t, color: BP.green);

    // Deck and railing in front of them.
    floor(-20, 1492, _walkY, col: BP.lineDim);
    c.drawLine(const Offset(-20, _walkY - 26), const Offset(1492, _walkY - 26), st(BP.lineDim, 1.2));
    c.drawLine(const Offset(-20, _walkY - 13), const Offset(1492, _walkY - 13), st(BP.lineFaint, 1));
    final posts = Path();
    for (var x = 12.0; x < 1492; x += 64) {
      posts
        ..moveTo(x, _walkY - 26)
        ..lineTo(x, _walkY);
    }
    c.drawPath(posts, st(BP.lineDim, 1));
  }

  void labels() {
    final hv = hover;
    for (var i = 0; i < 7; i++) {
      final x = _vx(i);
      final on = lit(i);
      final current = i == pw.step && on > 0;
      final hot = hv == i || current;
      final col = hot ? BP.amber : (on > 0.5 ? BP.ink : BP.inkFaint);
      final name = mono(_names[i], 24, col, 600);
      final r = Rect.fromCenter(center: Offset(x, 212), width: name.width + 28, height: 40);
      box(
        r,
        col: hot ? BP.amber : (on > 0.5 ? BP.lineDim : BP.lineFaint),
        w: current ? 2 : 1.2,
        fill: current ? Color.alphaBlend(BP.amber.withValues(alpha: 0.1), BP.panel) : BP.panel,
      );
      name.paint(c, Offset(r.center.dx - name.width / 2, r.center.dy - name.height / 2));
      if (hv == i) {
        c.drawPath(dashPath(Path()..addRect(_target(i).inflate(4)), dash: 5, gap: 4), st(BP.amber.withValues(alpha: 0.6), 1));
      }
    }
  }
}
