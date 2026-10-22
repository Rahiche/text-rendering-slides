import 'dart:math' as math;

import 'package:text_slides/booth/raster.dart';

import '../world/ease.dart' show eio, lerp, seg;
import '../world/glyph_works.dart';
import '../world/shot.dart';
import '../world/site_letters.dart';
import 'journey_cards.dart';
import 'talk_section.dart';

/// 05 · One word's journey: seven stops, a press each. The city from
/// above, the Glyph Works' hall from across the street, then in through
/// its door and down its line with the word's first letter, the camera
/// following it from step to step within a stop (the rest of the word
/// shaped with it in the stick, and drawn with it onto the board).
///
/// The works runs on the section's own clock: a beat plays its steps once
/// the camera's nearly there, then holds (the line waits at the step as
/// long as the presenter talks). Back cuts to the beat before, as it was
/// left.
class JourneySection extends TalkSection {
  JourneySection(this.works);

  final GlyphWorks works;

  /// The word on its way (the deck's journey word).
  static const word = 'Flutter';

  @override
  String get number => '05';
  @override
  String get title => "One word's journey";
  @override
  List<String> get stops => journeyStops;
  @override
  List<String> get glyphs => const ['F', '→', '#9', '→', '▦'];
  @override
  List<TalkBeat> get beats => _beats;
  @override
  TalkCard card(int stop) => journeyCards(word, works.talkName, works.latin)[stop];

  /// The clock the works runs on; whether the beat on was cut to.
  double _clock = 0;
  bool _cut = false;

  bool _on = false;
  Future<void>? _pending;
  @override
  Future<void>? get pending => _pending;

  late final List<TalkBeat> _beats = [
    // The map: the city from above, the works' hall across the street
    // from the plaza.
    TalkBeat(
      0,
      talkShot(-8, 42, -38, -30, 0, -2, 46, drift: 1.0),
      fly: 3.2,
      shift: 0.24,
      cardAt: 2.8,
      chapter: true,
      pins: [TalkPin(GlyphWorks.pin, 'GLYPH WORKS')],
    ),
    // Text(): the hall from the plaza's side of the street, its sign, the
    // line through its windows.
    TalkBeat(1, GlyphWorks.outside, fly: 3.4, shift: 0.45),
    // Into the engine: in through the door, down the hall to the feeder as
    // the bytes come out of it; then low and close on the decoder as they
    // go in (under the string's board), the code point out.
    _along(2, GlyphWorks.inside, [((tk) => tk.at[0] - 0.85, GlyphWorks.stepShot(0), 3.0), ((tk) => tk.at[1] - 0.4, GlyphWorks.decoderClose, _move)], fly: 2.6),
    // Find the glyphs: the font cases, the arm holding the tile up to each.
    TalkBeat(3, GlyphWorks.stepShot(2), fly: 1.8),
    // Shape, then lay out: onto the stick, the rest of the word after it;
    // in close as the line's measured.
    _along(4, GlyphWorks.stepShot(3), [((tk) => tk.line.$1 - 0.3, GlyphWorks.stickClose, _move)], fly: 1.8),
    // Record, then rasterize: the outline bent, then over to the print head.
    _along(5, GlyphWorks.stepShot(4), [((tk) => tk.at[5] - 0.4, GlyphWorks.stepShot(5), _move)], fly: 2.0),
    // Draw: onto the board, the rest of the word with it; then the whole
    // board, square on.
    _along(6, GlyphWorks.stepShot(6), [((tk) => tk.landed + 0.4, GlyphWorks.boardSquare, _move)], fly: 2.0),
  ];

  /// A beat at [stop] whose camera goes along with the letter: [first],
  /// then each of [then] in turn, eased to over its seconds of the works'
  /// clock from the moment it gives on.
  TalkBeat _along(int stop, Shot first, List<(double Function(WorksTalk tk), Shot, double)> then, {required double fly}) => TalkBeat(
    stop,
    first,
    fly: fly,
    live: () {
      final tk = works.talk;
      var s = first;
      if (tk == null) return s;
      for (final (at, next, move) in then) {
        final u = eio(seg(_clock, at(tk), at(tk) + move));
        if (u <= 0) break;
        s = _mix(s, next, u);
      }
      return s;
    },
  );

  static const _move = 1.4;

  static Shot _mix(Shot a, Shot b, double u) => Shot(
    a.eye + (b.eye - a.eye) * u,
    a.target + (b.target - a.target) * u,
    fov: lerp(a.fov, b.fov, u),
    settle: lerp(a.settle, b.settle, u),
    drift: lerp(a.drift, b.drift, u),
  );

  @override
  void enter() {
    _on = true;
    _clock = 0;
    _pending = NameRaster.of(word).then((r) async {
      if (!_on) return;
      works.planTalk(word, NameLetters.of(r));
      // (The cards' values: the word's fonts looked up, its pixels.)
      await works.pending;
      _pending = null;
    });
  }

  @override
  void leave() {
    _on = false;
    _pending = null;
    works.endTalk();
  }

  @override
  void arrive(int beat, {required bool cut}) {
    // As it was left: the works at the beat's end.
    _cut = cut;
    if (cut && works.talk != null) _clock = _until(beat, works.talk!);
  }

  /// The works' clock at the end of beat [b] (as the last that sets it
  /// left it).
  static double _until(int b, WorksTalk tk) {
    for (var i = b; i >= 0; i--) {
      if (_works[i].until(tk) case final u?) return u;
    }
    return 0;
  }

  @override
  void update(int beat, double age, double t, double dt) {
    final tk = works.talk;
    if (tk != null) {
      // Catch up with the beat before, quickly, if it was cut short; then,
      // once the camera's nearly there, play this beat's part.
      final before = beat == 0 ? 0.0 : _until(beat - 1, tk), until = _until(beat, tk);
      if (_clock < before - 1e-6) {
        _clock = math.min(before, _clock + 3 * dt);
      } else if (age >= _beats[beat].fly * _works[beat].lag) {
        _clock = math.min(until, _clock + dt);
      }
    }
    works.talkTime = _clock;
  }

  @override
  void caption(int beat, double age) {
    final steps = _works[beat].steps, tk = works.talk;
    if (steps.isEmpty || tk == null) return;
    // The step the letter's at: the beat's first until the next begins,
    // the caption dipping as it changes.
    var i = 0;
    while (i + 1 < steps.length && _clock >= tk.at[steps[i + 1]]) {
      i++;
    }
    final from = _cut ? 0.0 : _beats[beat].fly * 0.75;
    var show = ((age - from) / 0.5).clamp(0.0, 1.0);
    for (final s in steps.skip(1)) {
      show = math.min(show, ((_clock - tk.at[s]).abs() / 0.25).clamp(0.0, 1.0));
    }
    works.talkCaption(steps[i], show);
  }
}

/// A beat's part for the works: its clock at the beat's end (null: as the
/// beat before left it), the steps the works' caption gives on the way,
/// and when (of the camera's way there) the works starts.
class _Works {
  const _Works(this.until, {this.steps = const [], this.lag = 0.7});
  final double? Function(WorksTalk tk) until;
  final List<int> steps;
  final double lag;
}

final _works = <_Works>[
  // The map; the hall, from outside.
  _Works((tk) => 0),
  _Works((tk) => tk.at[0] - 0.9, lag: 0.55),
  // The bytes, decoded; the fonts.
  _Works((tk) => tk.end[1] - 0.05, steps: [0, 1]),
  _Works((tk) => tk.end[2] - 0.05, steps: [2]),
  // Shaped, the rest of the word after it; the line measured.
  _Works((tk) => tk.line.$2 + 0.1, steps: [3]),
  // A moment (the recording); the outline; the pixels.
  _Works((tk) => tk.end[5] - 0.05, steps: [4, 5]),
  // Onto the board; the arm back at rest.
  _Works((tk) => tk.home + 0.3, steps: [6]),
];
