import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../deck/scripts.dart';
import '../deck/theme.dart';
import '../deck/widgets.dart';

/// Font fallback: a character falls through a stack of fonts. Each font that
/// lacks it flashes ✕ and lets it through; the first one that has it catches it.
class FallbackSlide extends StatefulWidget {
  const FallbackSlide({super.key});

  @override
  State<FallbackSlide> createState() => _FallbackSlideState();
}

class _Plate {
  const _Plate(this.name, this.sample);

  final String name;
  final String sample;
}

const _plates = [
  _Plate('Space Grotesk', 'Aa Éé 12'),
  _Plate('Noto Kufi Arabic', 'ب ت ع'),
  _Plate('system CJK', '字 あ 한'),
  _Plate('system emoji', '😀 👋'),
  _Plate('system …', 'ก अ א'),
  _Plate('.notdef → □', ''),
];

const _chips = <(String, String)>[
  ('A', 'A'),
  ('ب', 'ب'),
  ('字', '字'),
  ('😀', '😀'),
  ('ก', 'ก'),
  ('अ', 'अ'),
  ('\uE000', 'E000'),
  ('\u0378', '0378'),
];

// Stage geometry (content-area coordinates).
const _stageX = 430.0;
const _plW = 720.0;
const _plH = 74.0;
const _plGap = 14.0;
const _plTop = 96.0;
const _slotX = _plW - 114;
const _startY = 8.0;

double _plateY(int k) => _plTop + k * (_plH + _plGap);
double _slotY(int k) => _plateY(k) + _plH / 2;

bool _isTofu(int cp) =>
    cp < 0x20 ||
    (cp >= 0x7F && cp < 0xA0) ||
    (cp >= 0xE000 && cp <= 0xF8FF) ||
    cp >= 0xF0000 ||
    (cp >= 0xFDD0 && cp <= 0xFDEF) ||
    (cp & 0xFFFE) == 0xFFFE ||
    cp == 0x0378 ||
    cp == 0x0379 ||
    (cp >= 0x0380 && cp <= 0x0383) ||
    cp == 0x038B ||
    cp == 0x038D ||
    cp == 0x03A2;

/// Which plate catches [cp]: decided by script, like a per-character lookup.
int _plateFor(int cp) {
  if (_isTofu(cp)) return 5;
  if (cp < 0x80 || (cp >= 0xA0 && cp <= 0xFF)) return 0;
  switch (scriptOf(cp)) {
    case Script.latin:
      return 0;
    case Script.arabic:
      return 1;
    case Script.han:
    case Script.kana:
    case Script.hangul:
      return 2;
    case Script.emoji:
      return 3;
    default:
      return 4;
  }
}

String _hex(int cp) => cp.toRadixString(16).toUpperCase().padLeft(4, '0');

/// Key frames of one drop, in milliseconds.
class _Timeline {
  _Timeline(this.target) {
    var t = 0.0;
    var y = _startY;
    for (var k = 0; k <= target; k++) {
      final last = k == target;
      final dur = last ? 640.0 : (k == 0 ? 420.0 : 300.0);
      segs.add((t, t + dur, y, _slotY(k), last));
      t += dur;
      arrive.add(t);
      if (!last) t += _pause;
      y = _slotY(k);
    }
    total = t + 500;
  }

  static const _pause = 280.0;

  final int target;
  final segs = <(double, double, double, double, bool)>[];
  final arrive = <double>[];
  late final double total;

  double yAt(double ms) {
    for (final (t0, t1, y0, y1, last) in segs) {
      if (ms < t0) return y0;
      if (ms <= t1) {
        final u = (ms - t0) / (t1 - t0);
        final c = last ? Curves.bounceOut : Curves.easeInCubic;
        return y0 + (y1 - y0) * c.transform(u);
      }
    }
    return segs.last.$4;
  }

  /// Horizontal "no!" shake while a font is being rejected.
  double shakeAt(double ms) {
    for (var k = 0; k < target; k++) {
      final d = ms - arrive[k];
      if (d >= 0 && d <= _pause) {
        final u = d / _pause;
        return math.sin(u * math.pi * 5) * 7 * (1 - u);
      }
    }
    return 0;
  }

  bool falling(double ms) {
    for (final (t0, t1, _, _, _) in segs) {
      if (ms >= t0 && ms <= t1) return true;
    }
    return false;
  }

  bool landed(double ms) => ms >= arrive.last;
}

class _FallbackSlideState extends State<FallbackSlide> with TickerProviderStateMixin {
  late final TextEditingController _ctrl = TextEditingController();
  late final AnimationController _drop = AnimationController(vsync: this);
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  )..repeat();

  String _char = 'ب';
  int _chip = 1;
  bool _auto = true;
  Timer? _next;
  late _Timeline _tl;

  @override
  void initState() {
    super.initState();
    _drop.addStatusListener(_onStatus);
    _start(_char, rebuild: false);
  }

  void _onStatus(AnimationStatus s) {
    if (s != AnimationStatus.completed || !_auto) return;
    _next?.cancel();
    _next = Timer(const Duration(milliseconds: 1600), () {
      if (!mounted || !_auto) return;
      _chip = (_chip + 1) % _chips.length;
      _start(_chips[_chip].$1);
    });
  }

  void _start(String ch, {bool rebuild = true}) {
    if (ch.isEmpty) return;
    final cp = ch.runes.first;
    void apply() {
      _char = ch;
      _tl = _Timeline(_plateFor(cp));
    }

    rebuild ? setState(apply) : apply();
    _drop.duration = Duration(milliseconds: _tl.total.round());
    _drop.forward(from: 0);
  }

  void _pick(int i) {
    _next?.cancel();
    setState(() {
      _auto = false;
      _chip = i;
    });
    _ctrl.text = _chips[i].$1;
    _start(_chips[i].$1);
  }

  void _typed(String s) {
    if (s.isEmpty) return;
    _next?.cancel();
    setState(() => _auto = false);
    _start(s.characters.last);
  }

  void _toggleAuto() {
    setState(() => _auto = !_auto);
    if (_auto && _drop.isCompleted) _onStatus(AnimationStatus.completed);
    if (!_auto) _next?.cancel();
  }

  @override
  void dispose() {
    _next?.cancel();
    _drop.dispose();
    _pulse.dispose();
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SlideFrame(
      title: 'Font fallback',
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Picker
          Positioned(
            left: 0,
            top: _plTop,
            width: 350,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    for (var i = 0; i < _chips.length; i++)
                      _CharChip(
                        label: _chips[i].$2,
                        mono: _chips[i].$1 != _chips[i].$2,
                        selected: _chips[i].$1 == _char,
                        onTap: () => _pick(i),
                      ),
                  ],
                ),
                const SizedBox(height: 34),
                BpTextField(controller: _ctrl, width: 334, style: BT.sample(34), onChanged: _typed, hint: 'type'),
                const SizedBox(height: 26),
                BpButton(label: 'auto', selected: _auto, onTap: _toggleAuto, size: 14),
              ],
            ),
          ),
          // Group brackets
          const Positioned(
            left: _stageX - 44,
            top: _plTop,
            width: 30,
            height: 2 * _plH + _plGap,
            child: _GroupBracket(label: 'app'),
          ),
          Positioned(
            left: _stageX - 44,
            top: _plateY(2),
            width: 30,
            height: 3 * _plH + 2 * _plGap,
            child: const _GroupBracket(label: 'platform'),
          ),
          // Plates + falling glyph
          Positioned(
            left: _stageX,
            top: 0,
            width: _plW + 20,
            height: 628,
            child: AnimatedBuilder(
              animation: Listenable.merge([_drop, _pulse]),
              builder: (context, _) => _stage(),
            ),
          ),
          // Readout
          Positioned(
            left: _stageX + _plW + 50,
            top: _plTop,
            right: 0,
            child: AnimatedBuilder(animation: _drop, builder: (context, _) => _readout()),
          ),
          Positioned(
            left: _stageX + _plW + 50,
            right: 0,
            top: _plateY(4) + 6,
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                BpTag('per character', color: BP.amber),
                SizedBox(height: 12),
                BpTag('web: Noto from fonts.gstatic.com', size: 12, color: BP.inkDim),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _readout() {
    final ms = _drop.value * _tl.total;
    final cp = _char.runes.first;
    final done = _tl.landed(ms);
    final target = _tl.target;
    final col = target == 5 ? BP.red : BP.green;
    final script = _isTofu(cp) ? '—' : scriptOfCluster(_char).label;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('U+${_hex(cp)}', style: BT.mono(30, color: BP.amber, weight: 500)),
        const SizedBox(height: 6),
        Text(script, style: BT.mono(16, color: BP.inkDim)),
        const SizedBox(height: 40),
        AnimatedOpacity(
          opacity: done ? 1 : 0,
          duration: const Duration(milliseconds: 300),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('→', style: BT.mono(22, color: col)),
              const SizedBox(height: 4),
              Text(_plates[target].name, style: BT.display(26, color: col)),
              const SizedBox(height: 10),
              Text('${target + 1} ${target == 0 ? 'lookup' : 'lookups'}', style: BT.mono(14, color: BP.inkDim)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _stage() {
    final ms = _drop.value * _tl.total;
    final target = _tl.target;
    final y = _tl.yAt(ms);
    final x = _slotX + _tl.shakeAt(ms);
    final landed = _tl.landed(ms);
    final cp = _char.runes.first;
    final tofu = target == 5;
    final emoji = scriptOfCluster(_char) == Script.emoji;
    final falling = _tl.falling(ms) && !landed;

    Widget glyph(double alpha, {bool outline = false}) {
      if (tofu) return _Tofu(cp: cp, solid: landed, alpha: alpha);
      final base = BT.sample(58, color: BP.ink, height: 1.0);
      final style = outline && !emoji
          ? base.copyWith(
              color: null,
              foreground: Paint()
                ..style = PaintingStyle.stroke
                ..strokeWidth = 1.6
                ..color = BP.ink.withValues(alpha: alpha),
            )
          : base.copyWith(color: (landed ? BP.ink : BP.inkDim).withValues(alpha: alpha));
      final child = Text(_char, style: style, textAlign: TextAlign.center, softWrap: false);
      return emoji ? Opacity(opacity: landed ? alpha : alpha * 0.55, child: child) : child;
    }

    return Stack(
      clipBehavior: Clip.none,
      children: [
        // The chute.
        Positioned(
          left: _slotX - 1,
          top: 0,
          width: 2,
          height: _plateY(5) + _plH,
          child: const CustomPaint(painter: _ChutePainter()),
        ),
        for (var k = 0; k < _plates.length; k++)
          Positioned(
            left: 0,
            top: _plateY(k),
            width: _plW,
            height: _plH,
            child: _PlateView(
              index: k,
              plate: _plates[k],
              state: k > target || ms < _tl.arrive[k]
                  ? 0
                  : (k == target ? 2 : 1),
              since: k <= target ? ms - _tl.arrive[k] : 0,
              pulse: _pulse.value,
            ),
          ),
        // Trail while falling.
        if (falling)
          for (var g = 1; g <= 3; g++)
            Positioned(
              left: x - 60,
              top: y - 50 - g * 20,
              width: 120,
              height: 100,
              child: Center(child: glyph(0.16 / g, outline: true)),
            ),
        Positioned(
          left: x - 60,
          top: y - 50,
          width: 120,
          height: 100,
          child: Center(child: glyph(1, outline: !landed)),
        ),
        // Code point riding along.
        Positioned(
          left: x + 50,
          top: y - 34,
          child: Opacity(
            opacity: landed ? 0 : 1,
            child: Text('U+${_hex(cp)}', style: BT.mono(13, color: BP.amber)),
          ),
        ),
      ],
    );
  }
}

class _PlateView extends StatelessWidget {
  const _PlateView({
    required this.index,
    required this.plate,
    required this.state,
    required this.since,
    required this.pulse,
  });

  final int index;
  final _Plate plate;

  /// 0 untouched · 1 rejected · 2 caught.
  final int state;
  final double since;
  final double pulse;

  @override
  Widget build(BuildContext context) {
    final flash = state == 1 ? math.exp(-since / 260) : 0.0;
    final pop = state == 2 ? Curves.elasticOut.transform((since / 700).clamp(0.0, 1.0)) : 0.0;
    final border = switch (state) {
      1 => Color.lerp(BP.red.withValues(alpha: 0.45), BP.red, flash)!,
      2 => BP.green,
      _ => BP.lineDim,
    };
    final fill = switch (state) {
      1 => Color.alphaBlend(BP.red.withValues(alpha: 0.22 * flash), BP.panel),
      2 => Color.alphaBlend(
        BP.green.withValues(alpha: 0.08 + 0.06 * math.sin(pulse * math.pi * 2).abs()),
        BP.panel,
      ),
      _ => BP.panel,
    };
    final nameColor = switch (state) {
      1 => BP.inkDim,
      2 => BP.green,
      _ => BP.ink,
    };
    return BpPanel(
      padding: EdgeInsets.zero,
      color: border,
      fill: fill,
      child: Row(
        children: [
          SizedBox(
            width: 52,
            child: Center(
              child: Text('0${index + 1}', style: BT.mono(13, color: BP.inkFaint)),
            ),
          ),
          Expanded(
            child: Text(plate.name, style: BT.display(24, color: nameColor), softWrap: false),
          ),
          SizedBox(
            width: 150,
            child: Text(
              plate.sample,
              style: BT.sample(22, color: BP.inkFaint),
              softWrap: false,
              overflow: TextOverflow.clip,
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 84,
            height: 60,
            child: CustomPaint(
              painter: DashedRectPainter(
                color: state == 2 ? BP.green : (state == 1 ? BP.red.withValues(alpha: 0.5) : BP.lineFaint),
                dash: 4,
                gap: 4,
              ),
            ),
          ),
          const SizedBox(width: 16),
          SizedBox(
            width: 40,
            child: Center(
              child: switch (state) {
                1 => Opacity(
                  opacity: 0.5 + 0.5 * flash,
                  child: Transform.scale(
                    scale: 1 + 0.6 * flash,
                    child: Text('✕', style: BT.mono(24, color: BP.red, weight: 700)),
                  ),
                ),
                2 => Transform.scale(
                  scale: 0.4 + 0.6 * pop,
                  child: Text('✓', style: BT.mono(26, color: BP.green, weight: 700)),
                ),
                _ => const SizedBox.shrink(),
              },
            ),
          ),
          const SizedBox(width: 16),
        ],
      ),
    );
  }
}

/// A last-resort "tofu" box with the code point's hex digits inside.
class _Tofu extends StatelessWidget {
  const _Tofu({required this.cp, required this.solid, required this.alpha});

  final int cp;
  final bool solid;
  final double alpha;

  @override
  Widget build(BuildContext context) {
    final hex = _hex(cp);
    final half = (hex.length / 2).ceil();
    final c = (solid ? BP.ink : BP.inkDim).withValues(alpha: alpha);
    return SizedBox(
      width: 44,
      height: 58,
      child: CustomPaint(
        painter: solid
            ? _BoxPainter(c)
            : DashedRectPainter(color: c, dash: 4, gap: 3, strokeWidth: 1.5),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(hex.substring(0, half), style: BT.mono(12, color: c, height: 1.1)),
              Text(hex.substring(half), style: BT.mono(12, color: c, height: 1.1)),
            ],
          ),
        ),
      ),
    );
  }
}

class _BoxPainter extends CustomPainter {
  _BoxPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      (Offset.zero & size).deflate(1),
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(_BoxPainter old) => old.color != color;
}

class _ChutePainter extends CustomPainter {
  const _ChutePainter();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawPath(
      dashPath(Path()
        ..moveTo(size.width / 2, 0)
        ..lineTo(size.width / 2, size.height), dash: 5, gap: 5),
      Paint()
        ..color = BP.lineDim
        ..style = PaintingStyle.stroke,
    );
  }

  @override
  bool shouldRepaint(_ChutePainter old) => false;
}

class _GroupBracket extends StatelessWidget {
  const _GroupBracket({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      RotatedBox(
        quarterTurns: 3,
        child: Text(label, style: BT.mono(13, color: BP.inkDim)),
      ),
      const SizedBox(width: 6),
      const Expanded(child: CustomPaint(painter: _BracketPainter(), child: SizedBox.expand())),
    ],
  );
}

class _BracketPainter extends CustomPainter {
  const _BracketPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = BP.lineDim
      ..style = PaintingStyle.stroke;
    canvas.drawPath(
      Path()
        ..moveTo(size.width, 1)
        ..lineTo(1, 1)
        ..lineTo(1, size.height - 1)
        ..lineTo(size.width, size.height - 1),
      p,
    );
  }

  @override
  bool shouldRepaint(_BracketPainter old) => false;
}

class _CharChip extends StatelessWidget {
  const _CharChip({required this.label, required this.mono, required this.selected, required this.onTap});

  final String label;
  final bool mono;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => MouseRegion(
    cursor: SystemMouseCursors.click,
    child: GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        width: 76,
        height: 76,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? BP.line.withValues(alpha: 0.16) : Colors.transparent,
          border: Border.all(color: selected ? BP.amber : BP.lineDim, width: selected ? 2 : 1),
        ),
        child: mono
            ? Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('□', style: BT.mono(20, color: selected ? BP.ink : BP.inkDim)),
                  Text(label, style: BT.mono(12, color: selected ? BP.amber : BP.inkDim)),
                ],
              )
            : Text(label, style: BT.sample(32, color: selected ? BP.ink : BP.inkDim)),
      ),
    ),
  );
}
