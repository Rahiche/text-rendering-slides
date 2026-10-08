import 'dart:math' as math;

import 'package:text_slides/booth/raster.dart';
import 'package:vector_math/vector_math.dart' as vm;

import '../world/glyph_works.dart';
import '../world/site_letters.dart';
import 'journey_cards.dart';
import 'talk_section.dart';

/// 05 · One word's journey: the deck's eleven stops as places in the city.
/// The city from above, the Glyph Works from outside, then the works takes
/// the word's first letter down its line a step a press, the camera
/// following (the rest of the word shaped with it in the stick, and drawn
/// with it onto the board).
///
/// The works runs on the section's own clock: a beat plays its step once
/// the camera's nearly there, then holds (the maker stays at the step,
/// idling, as long as the presenter talks). Back cuts to the beat before,
/// as it was left.
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
    final step = _works[beat].step;
    if (step < 0) return;
    final from = _cut ? 0.0 : _beats[beat].fly * 0.75;
    works.talkCaption(step, ((age - from) / 0.5).clamp(0.0, 1.0));
  }
}

/// A beat's part for the works: its clock at the beat's end (null: as the
/// beat before left it), the step the works' caption gives (−1: none), and
/// when (of the camera's way there) the works starts.
class _Works {
  const _Works(this.until, {this.step = -1, this.lag = 0.7});
  final double? Function(WorksTalk tk) until;
  final int step;
  final double lag;
}

double? _hold(WorksTalk tk) => null;

final _beats = <TalkBeat>[
  // The map: the city from above, the plaza and the works.
  TalkBeat(
    0,
    talkShot(-2, 44, -36, -7, 0, 4, 46, drift: 1.0),
    fly: 3.2,
    shift: 0.24,
    cardAt: 2.8,
    chapter: true,
    pins: [TalkPin(vm.Vector3(-12.55, 3.3, 6.2), 'GLYPH WORKS')],
  ),
  // Text(): the works from outside, its sign; the maker walks in.
  TalkBeat(1, talkShot(-11.2, 2.6, 0.2, -12.4, 1.8, 6.0, 50, drift: 0.5), fly: 3.4),
  // A Dart String: the string's board over the feeder.
  TalkBeat(2, talkShot(-14.2, 1.75, 4.7, -15.0, 1.45, 7.6, 40), fly: 2.4),
  // Into the engine: the bytes out of the feeder.
  TalkBeat(3, GlyphWorks.stepShot(0), fly: 1.8),
  // Unicode analysis: into the decoder, the code point out.
  TalkBeat(4, talkShot(-14.75, 1.6, 4.25, -15.15, 0.95, 6.4, 44), fly: 1.6),
  // Find the glyphs: the font cases.
  TalkBeat(5, GlyphWorks.stepShot(2), fly: 1.8),
  // Shape: onto the stick, the rest of the word after it.
  TalkBeat(6, GlyphWorks.stepShot(3), fly: 1.8),
  // Lay out: the line measured.
  TalkBeat(7, talkShot(-13.0, 1.32, 4.7, -13.12, 0.86, 6.3, 36), fly: 1.6),
  // Record: down the rest of the line, still to come.
  TalkBeat(8, talkShot(-13.9, 2.3, 4.0, -10.6, 0.75, 5.7, 46), fly: 2.0),
  // Rasterize: the outline bent, then scanned into pixels.
  TalkBeat(9, GlyphWorks.stepShot(4), fly: 2.0),
  TalkBeat(9, GlyphWorks.stepShot(5), fly: 1.6),
  // Draw: onto the board, the rest of the word with it; the whole board.
  TalkBeat(10, GlyphWorks.stepShot(6), fly: 2.0),
  TalkBeat(10, talkShot(-9.85, 1.5, 3.25, -9.85, 0.8, 5.12, 38), fly: 2.2),
];

final _works = <_Works>[
  _Works((tk) => 0),
  _Works((tk) => tk.at[0] - 0.9, lag: 0.55),
  const _Works(_hold),
  _Works((tk) => tk.end[0] - 0.05, step: 0),
  _Works((tk) => tk.end[1] - 0.05, step: 1),
  _Works((tk) => tk.end[2] - 0.05, step: 2),
  _Works((tk) => tk.set + 0.25, step: 3),
  _Works((tk) => tk.line.$2 + 0.1),
  _Works((tk) => tk.at[4] - 0.25),
  _Works((tk) => tk.end[4] - 0.05, step: 4),
  _Works((tk) => tk.end[5] - 0.05, step: 5),
  _Works((tk) => tk.home + 0.3, step: 6),
  const _Works(_hold),
];
