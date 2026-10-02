import 'dart:math' as math;

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/painting.dart';
import 'package:text_slides/deck/theme.dart';
import 'package:vector_math/vector_math.dart' as vm;

import 'figure.dart';
import 'kit.dart';
import 'motion.dart';
import 'shot.dart';
import 'vignette.dart';

/// 改行電車 · Line breaking, at the north end of the park: a paragraph's
/// lines are the carriages of a tram (read left to right, the first line
/// leading). The words wait on the platform in order; the tram pulls in
/// and they board the carriage at the platform one by one, left to right,
/// until the next one doesn't fit (it tries, and is sent back): the tram
/// moves up a carriage, and that word starts the next line. A ↵ ends its line however much room is left. Then
/// 行頭に来ません。— and the full stop, with no room left for it, may not
/// start a line (kinsoku, 禁則): it hangs off the end of the last carriage
/// (ぶら下げ). The conductor waves the tram off, and the next is due.
///
/// Who goes where is worked out like a text engine would: greedy, from the
/// words' real widths (shaped and extruded with the real text stack).
class LineTram extends Vignette {
  LineTram(super.kit);

  @override
  String get name => 'tram';
  @override
  String get kick => '改行電車 · LINE BREAKING';
  @override
  String get line => 'Fill the line, then the next';
  @override
  String get note => 'greedy breaking; 。 may not start a line (禁則)';

  @override
  double get loop => _loop;
  @override
  double get visit => _depart + 1.6;

  @override
  final frame = trs(vm.Vector3(0, 0, 66.6));

  // ── The paragraph ─────────────────────────────────────────────────────────

  /// What boards: words (a space between them), a forced break, then
  /// characters (no spaces: a line may break between any two), the full
  /// stop last.
  static const _words = ['Text', 'flows', 'across', 'lines', '↵', '行', '頭', 'に', '来', 'ま', 'せ', 'ん', '。'];
  static const _jaFrom = 5;

  /// The carriages: how many, their length and the room for a line in each
  /// (the line's width), the gap between them.
  static const _cars = 3, _carLen = 3.1, _gap = 0.45, _pitch = _carLen + _gap;
  static double _room = 2.4;

  /// Where the carriage at the platform has its line's start (x).
  static const _zoneX = -1.3;

  /// The platform's edge (z), its top; the floor of a carriage.
  static const _platZ = -1.35, _platY = 0.42, _floorY = 0.62;

  // ── The timeline ──────────────────────────────────────────────────────────

  static const _arrive = 2.6, _board = 0.55, _try = 0.9, _move = 1.25;

  /// Each word's line, its pen (x from its line's start), when it boards;
  /// the words that try and are sent back (index, when); when the tram
  /// moves up; when it leaves.
  final _line = <int>[], _x = <double>[], _at = <double>[];
  final _tries = <(int, double)>[];
  final _moves = <double>[];
  static double _depart = 14, _loop = 18;

  // ── Building ──────────────────────────────────────────────────────────────

  late final List<Glyph3D> _glyphs;
  int _conductor = -1;
  final _p = FigurePose();
  bool _ready = false;

  static TextStyle _style(bool ja) => TextStyle(
    fontFamily: BP.display,
    fontSize: 160,
    fontWeight: FontWeight.w700,
    locale: ja ? const Locale('ja') : null,
    fontVariations: const [FontVariation('wght', 700)],
  );

  @override
  List<(String, TextStyle)> get fontRuns => [('Text flows across lines ↵ 改行電車 LINE BREAK', _style(false)), ('行頭に来ません。改行駅', _style(true))];

  @override
  Future<void> init() async {
    makePool(boxes: 16, glows: 12);
    _build();
    final ink = pbr(Vignette.c(0x1E2A4A), roughness: 0.45, emissive: Vignette.c(0x1E2A4A), emissiveStrength: 0.05);
    _glyphs = await letters([for (final (i, w) in _words.indexed) (w, _style(i >= _jaFrom))], ink, unitsPerPx: 0.36 / 160, depth: 0.09);
    _plan();
    await _signs();
    _conductor = person(
      FigureLook()
        ..top = rgbHex(0x24314F)
        ..legs = rgbHex(0x1C2233)
        ..cap = rgbHex(0x24314F)
        ..shoes = rgbHex(0x111215)
        ..skin = rgbHex(0xE0BB9E)
        ..hairColor = rgbHex(0x1A1714)
        ..gloves = rgbHex(0xF4F2EC),
    );
    _ready = true;
  }

  /// Lays the paragraph out like a text engine (greedy, from the shaped
  /// widths), the room per line chosen so the full stop comes just past
  /// the last line's end; then the timeline.
  void _plan() {
    double w(int i) => _glyphs[i].solid.advance;
    final space = w(0) * 0.28;
    // The room: the Japanese line exactly, a little to spare (not enough
    // for 。).
    var ja = 0.0;
    for (var i = _jaFrom; i < _words.length - 1; i++) {
      ja += w(i);
    }
    _room = ja + w(_words.length - 1) * 0.45;
    _line.clear();
    _x.clear();
    _at.clear();
    _tries.clear();
    _moves.clear();
    var line = 0, pen = 0.0, t = _arrive;
    for (var i = 0; i < _words.length; i++) {
      // (A forced break takes no room: it just ends its line.)
      final brk = _words[i] == '↵';
      final spaced = pen > 0 && i < _jaFrom && !brk ? space : 0.0;
      final last = i == _words.length - 1;
      if (!brk && pen + spaced + w(i) > _room + 1e-6 && !last) {
        // Doesn't fit: tries, is sent back; the tram moves up a carriage.
        _tries.add((i, t));
        t += _try;
        _moves.add(t);
        t += _move;
        line++;
        pen = 0;
        _line.add(line);
        _x.add(0);
      } else {
        // (The full stop hangs past the end if it must: kinsoku.)
        _line.add(line);
        _x.add(pen + spaced);
      }
      _at.add(t);
      t += i >= _jaFrom ? _board * 0.55 : _board;
      pen = _x[i] + w(i);
      if (_words[i] == '↵') {
        _moves.add(t);
        t += _move;
        line++;
        pen = 0;
      }
    }
    _depart = t + 0.9;
    _loop = _depart + 5.5;
    if (const String.fromEnvironment('BOOTH3D_TIMES') != '') {
      debugPrint(
        'TRAM room ${_room.toStringAsFixed(2)} m: ${[for (var i = 0; i < _words.length; i++) '${_words[i]}@${_line[i]}:${_x[i].toStringAsFixed(2)}'].join(' ')}',
      );
    }
  }

  void _build() {
    final b = Batch();
    final m = pbr(rgb(1, 1, 1), roughness: 0.7);
    final steel = pbr(rgb(1, 1, 1), roughness: 0.35, metallic: 0.7);
    // The rails along the park's end, the sleepers, the platform.
    for (final z in [-0.55, 0.55]) {
      box(b, steel, 46, 0.06, 0.08, 0, 0.03, z, Vignette.c(0x9AA3AD));
    }
    for (var k = -30; k <= 30; k++) {
      box(b, m, 0.24, 0.04, 1.5, k * 0.75, 0.02, 0, Vignette.c(0x5A4B3E));
    }
    box(b, m, 14.0, _platY, 1.6, 2.6, _platY / 2, _platZ - 0.8, Vignette.c(0xC9C3B6));
    box(b, m, 14.0, 0.03, 0.12, 2.6, _platY + 0.015, _platZ - 0.06, Vignette.c(0xF2C94C));
    // The station's sign on its posts, behind the tracks.
    for (final x in [-1.4, 3.4]) {
      box(b, m, 0.1, 3.2, 0.1, x, 1.6, 1.75, Vignette.c(0x3A4C6E));
    }
    // The tram's carriages are drawn every frame (they move).
    b.buildInto(detail, 'tram line', castsShadows: false, lightChannelMask: 0x01);
  }

  Future<void> _signs() async {
    await Future.wait([
      sign(4.4, 0.62, vm.Matrix4.translation(vm.Vector3(1.0, 2.95, 1.7)), (c, s) {
        c.drawRect(Offset.zero & s, Paint()..color = const Color(0xFFF4F1EA));
        c.drawRect(Rect.fromLTWH(0, s.height * 0.78, s.width, s.height * 0.22), Paint()..color = const Color(0xFF2E6DA8));
        Vignette.text(c, '改行駅 · LINE BREAK', Rect.fromLTWH(0, 0, s.width, s.height * 0.76), s.height * 0.46, const Color(0xFF1E2A4A), lang: 'ja');
      }),
      // The line's width, marked on the platform's edge.
      sign(
        _room,
        0.16,
        vm.Matrix4.translation(vm.Vector3(_zoneX + _room / 2, _platY + 0.09, _platZ - 0.02)),
        (c, s) {
          c.drawRect(Offset.zero & s, Paint()..color = const Color(0xFF1E2A4A));
          final p = Paint()
            ..color = const Color(0xFFF2C94C)
            ..strokeWidth = s.height * 0.08;
          c
            ..drawLine(Offset(4, s.height / 2), Offset(s.width - 4, s.height / 2), p)
            ..drawLine(Offset(4, s.height * 0.2), Offset(4, s.height * 0.8), p)
            ..drawLine(Offset(s.width - 4, s.height * 0.2), Offset(s.width - 4, s.height * 0.8), p);
          Vignette.text(
            c,
            'maxWidth ${_room.toStringAsFixed(2)} m',
            Rect.fromLTWH(s.width * 0.3, 0, s.width * 0.4, s.height),
            s.height * 0.5,
            const Color(0xFFF4F1EA),
          );
        },
        px: 768,
        thick: 0.01,
      ),
    ]);
  }

  // ── Posing ────────────────────────────────────────────────────────────────

  /// The front carriage's line start (x) at [u]: in from the right,
  /// moving up a carriage at a time, away to the left.
  double _trainX(double u) {
    var x = _zoneX + 24 * (1 - eo(seg(u, 0, _arrive)));
    for (final m in _moves) {
      x -= _pitch * eio(seg(u, m, m + _move));
    }
    final d = seg(u, _depart, _depart + 3.4);
    return x - 26 * d * d;
  }

  /// Where carriage [k]'s line starts with the front one's at [x] (the
  /// others behind it, to the right).
  static double _carX(double x, int k) => x + k * _pitch;

  @override
  void pose(double u, double t, double night) {
    if (!_ready) return;
    pool.begin();
    final x0 = _trainX(u);
    // The carriages: cream and green, a stripe, the line's ends marked
    // (green its start, orange its end), their numbers.
    for (var k = 0; k < _cars; k++) {
      final cx = _carX(x0, k) + _room / 2;
      final green = Vignette.c(0x2F8F6A), cream = Vignette.c(0xF1E9D6);
      // An open car: the deck, a low rail along the front, a back wall,
      // ends, a canopy on posts.
      pbox(cx, 0.36, 0, _carLen, 0.36, 1.5, green);
      pbox(cx, 0.58, 0, _carLen - 0.1, 0.06, 1.42, Vignette.c(0x8A8F98));
      pbox(cx, 0.92, 0.7, _carLen, 0.62, 0.06, cream);
      pbox(cx, 0.7, -0.7, _carLen, 0.05, 0.05, cream);
      for (final dx in [-_carLen / 2 + 0.05, _carLen / 2 - 0.05]) {
        pbox(cx + dx, 0.95, 0, 0.1, 0.7, 1.5, cream);
        pbox(cx + dx, 1.75, -0.68, 0.06, 1.6, 0.06, cream);
        pbox(cx + dx, 1.75, 0.68, 0.06, 1.6, 0.06, cream);
      }
      pbox(cx, 2.58, 0, _carLen + 0.12, 0.08, 1.62, green);
      pglow(_carX(x0, k) - 0.03, 1.3, -0.62, 0.04, 1.1, 0.04, vm.Vector4(0.2, 1.6, 0.6, 1));
      pglow(_carX(x0, k) + _room + 0.03, 1.3, -0.62, 0.04, 1.1, 0.04, vm.Vector4(2.2, 0.9, 0.1, 1));
      // A skirt over the wheels.
      pbox(cx, 0.15, -0.7, _carLen - 0.3, 0.22, 0.05, Vignette.c(0x22252B));
    }
    // The words: waiting on the platform (in order, the next at the
    // door), boarding (a hop in), riding; one that tries and doesn't fit
    // goes up to the end and back.
    var queue = 0.0, all = 0.0;
    double w(int i) => _glyphs[i].solid.advance;
    final refill = u > _depart + 3.0;
    for (var i = 0; i < _words.length; i++) {
      final g = _glyphs[i];
      final at = _at[i];
      // In the queue: the words still to board, from the door leftwards
      // (moving up as the ones ahead board); refilled when the tram's
      // gone, each popping up in its place.
      final qx = _zoneX + _room + 0.75 + (refill ? all : queue);
      final pop = refill ? smooth(_depart + 3.0 + 0.12 * i, _depart + 3.4 + 0.12 * i, u) : 1.0;
      queue += (w(i) + 0.22) * (1 - smooth(at, at + 0.45, u));
      all += w(i) + 0.22;
      var x = qx, y = _platY, z = _platZ - 0.45, s = refill ? pop : 1.0;
      for (final (j, tt) in _tries) {
        if (j == i && u >= tt && u < tt + _try) {
          // Up to the end of the line, and back: no room.
          final f = seg(u, tt, tt + _try), there = math.sin(math.pi * f);
          final cx = _carX(x0, _line[i] - 1);
          x = lerp(qx, cx + _room - w(i) * 0.6, there);
          y = _platY + 0.3 * math.sin(math.pi * seg(f, 0, 0.5));
          z = lerp(_platZ - 0.45, -0.1, there);
          if (f > 0.35 && f < 0.75) pglow(cx + _room + 0.03, 1.3, -0.62, 0.1, 1.2, 0.1, vm.Vector4(3.0, 0.3, 0.2, 1));
        }
      }
      if (!refill && u >= at) {
        final f = eio(seg(u, at, at + (i >= _jaFrom ? _board * 0.55 : _board)));
        final cx = _carX(x0, _line[i]) + _x[i];
        x = lerp(qx, cx, f);
        y = lerp(_platY, _floorY, f) + 0.35 * math.sin(math.pi * f);
        z = lerp(_platZ - 0.45, 0.05, f);
      }
      pen(g, x, y + 0.04, z, s: s);
    }
    // The conductor on the platform: watching the boarding, the flag held
    // out for each move up and for the off.
    final p = _p..rest();
    p.pos.setValues(_zoneX - 1.9, _platY, _platZ - 0.75);
    final m = Manner.of(130);
    p.yaw = -1.85;
    Idle.stand(p, t, m, look: 0.4, at: vm.Vector3(_zoneX + 1.2, 1.2, 0));
    var wave = 0.0;
    for (final mv in [..._moves, _depart]) {
      wave = math.max(wave, smooth(mv - 0.6, mv - 0.3, u) * (1 - smooth(mv + 0.4, mv + 0.8, u)));
    }
    p.handTo(1, 0.4, 0.28 + 0.05 * math.sin(t * 9), -0.18, wave);
    draw(_conductor, p);
    pool.end();
  }

  // ── The camera ────────────────────────────────────────────────────────────

  @override
  Shot shot(double u) {
    // From the lawn, a little above: the carriage at the platform and the
    // words waiting; closer for the kinsoku; back for the off.
    final close = smooth(_at[_jaFrom] - 0.5, _at[_jaFrom] + 0.5, u) * (1 - smooth(_depart - 0.6, _depart + 0.4, u));
    final eye = vm.Vector3(lerp(2.6, 2.4, close), lerp(4.4, 3.4, close), lerp(-7.0, -5.0, close));
    final tg = vm.Vector3(lerp(_zoneX + _room / 2 + 1.1, _zoneX + _room - 0.2, close), lerp(0.5, 0.75, close), lerp(-0.7, -0.2, close));
    return Shot(eye, tg, fov: 44, settle: 1.2, drift: 0.4);
  }
}
