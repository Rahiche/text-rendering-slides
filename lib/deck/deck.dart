import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../worlds/world.dart';
import 'theme.dart';

/// One slide in the deck.
///
/// [steps] is how many times "next" stays on this slide before moving on.
/// Slides read the current step with `SlideScope.of(context).step`.
class SlideDef {
  const SlideDef({
    required this.id,
    required this.section,
    required this.title,
    required this.builder,
    this.steps = 1,
  });

  final String id;
  final String section;
  final String title;
  final int steps;
  final WidgetBuilder builder;
}

class DeckController extends ChangeNotifier {
  DeckController(this.slides);

  final List<SlideDef> slides;
  int index = 0;
  int step = 0;
  int direction = 1;
  int nonce = 0;
  bool overview = false;

  SlideDef get current => slides[index];

  void next() {
    if (overview) return;
    if (step < current.steps - 1) {
      step++;
      notifyListeners();
    } else if (index < slides.length - 1) {
      _go(index + 1, 0);
    }
  }

  void prev() {
    if (overview) return;
    if (step > 0) {
      step--;
      notifyListeners();
    } else if (index > 0) {
      _go(index - 1, slides[index - 1].steps - 1);
    }
  }

  void goTo(int i, {int step = 0}) {
    overview = false;
    if (i == index) {
      this.step = step;
      notifyListeners();
      return;
    }
    _go(i.clamp(0, slides.length - 1), step);
  }

  void goToId(String id) {
    final i = slides.indexWhere((s) => s.id == id);
    if (i >= 0) goTo(i);
  }

  void replay() {
    nonce++;
    step = 0;
    notifyListeners();
  }

  void toggleOverview() {
    overview = !overview;
    notifyListeners();
  }

  void _go(int i, int s) {
    direction = i >= index ? 1 : -1;
    index = i;
    step = s;
    notifyListeners();
  }
}

class DeckScope extends InheritedNotifier<DeckController> {
  const DeckScope({super.key, required DeckController controller, required super.child})
    : super(notifier: controller);

  static DeckController of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<DeckScope>()!.notifier!;

  /// Access without subscribing to changes (for callbacks).
  static DeckController read(BuildContext context) =>
      context.getInheritedWidgetOfExactType<DeckScope>()!.notifier!;
}

/// Per-slide info. The outgoing slide keeps its old values during the wipe.
class SlideScope extends InheritedWidget {
  const SlideScope({
    super.key,
    required this.index,
    required this.step,
    required this.total,
    required this.section,
    required super.child,
  });

  final int index;
  final int step;
  final int total;
  final String section;

  static SlideScope of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SlideScope>()!;

  @override
  bool updateShouldNotify(SlideScope old) => old.step != step || old.index != index;
}

class Deck extends StatefulWidget {
  const Deck({super.key, required this.worlds, required this.initial, required this.slidesFor});

  /// All versions of the deck; `w` cycles through them while presenting.
  final List<World> worlds;
  final World initial;
  final List<SlideDef> Function(World world) slidesFor;

  @override
  State<Deck> createState() => _DeckState();
}

class _DeckState extends State<Deck> {
  late World _world = widget.initial;
  late DeckController _c = DeckController(widget.slidesFor(_world));

  /// Switch to another world, staying on the same slide id when it exists.
  void _setWorld(World w) {
    final id = _c.current.id;
    final next = DeckController(widget.slidesFor(w));
    final i = next.slides.indexWhere((s) => s.id == id);
    next.index = i >= 0 ? i : _c.index.clamp(0, next.slides.length - 1);
    final old = _c;
    setState(() {
      _world = w;
      _c = next;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
  }

  /// When the platform's font set changes (on the web: a Noto fallback font
  /// finished downloading), rebuild and repaint everything — keeping state —
  /// so painters that measured text with tofu pick up the real glyphs.
  Timer? _fontTimer;

  void _onFontsChanged() {
    _fontTimer?.cancel();
    _fontTimer = Timer(const Duration(milliseconds: 250), () {
      if (!mounted) return;
      void visit(Element e) {
        e.markNeedsBuild();
        e.renderObject?.markNeedsPaint();
        e.visitChildren(visit);
      }

      (context as Element).visitChildren(visit);
    });
  }

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onKey);
    PaintingBinding.instance.systemFonts.addListener(_onFontsChanged);
    // Deep link on the web: ?slide=<id>
    final id = Uri.base.queryParameters['slide'];
    if (id != null) {
      final i = _c.slides.indexWhere((s) => s.id == id);
      if (i >= 0) _c.index = i;
    }
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    PaintingBinding.instance.systemFonts.removeListener(_onFontsChanged);
    _fontTimer?.cancel();
    _c.dispose();
    super.dispose();
  }

  bool _editingText() {
    final ctx = FocusManager.instance.primaryFocus?.context;
    if (ctx == null) return false;
    return ctx.widget is EditableText || ctx.findAncestorWidgetOfExactType<EditableText>() != null;
  }

  bool _onKey(KeyEvent e) {
    if (e is KeyUpEvent) return false;
    final k = e.logicalKey;
    if (k == LogicalKeyboardKey.escape) {
      if (_editingText()) {
        FocusManager.instance.primaryFocus?.unfocus();
      } else if (_c.overview) {
        _c.toggleOverview();
      }
      return false;
    }
    if (_editingText()) return false;
    if (k == LogicalKeyboardKey.arrowRight ||
        k == LogicalKeyboardKey.space ||
        k == LogicalKeyboardKey.pageDown) {
      _c.next();
    } else if (k == LogicalKeyboardKey.arrowLeft || k == LogicalKeyboardKey.pageUp) {
      _c.prev();
    } else if (e is KeyDownEvent) {
      if (k == LogicalKeyboardKey.keyO) {
        _c.toggleOverview();
      } else if (k == LogicalKeyboardKey.keyR) {
        _c.replay();
      } else if (k == LogicalKeyboardKey.home) {
        _c.goTo(0);
      } else if (k == LogicalKeyboardKey.end) {
        _c.goTo(_c.slides.length - 1);
      } else if (k == LogicalKeyboardKey.keyW && widget.worlds.length > 1) {
        final i = widget.worlds.indexWhere((w) => w.id == _world.id);
        _setWorld(widget.worlds[(i + 1) % widget.worlds.length]);
      }
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return WorldScope(
      world: _world,
      child: DeckScope(
        controller: _c,
        child: ListenableBuilder(
          listenable: _c,
          builder: (context, _) => LayoutBuilder(
            builder: (context, box) {
              final worldRuler = _worldRuler();
              final scale = math.min(
                box.maxWidth / BP.canvas.width,
                box.maxHeight / BP.canvas.height,
              );
              final origin = Offset(
                (box.maxWidth - BP.canvas.width * scale) / 2,
                (box.maxHeight - BP.canvas.height * scale) / 2,
              );
              return ColoredBox(
                color: BP.paper,
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: CustomPaint(
                        painter: GridPaperPainter(scale: scale, origin: origin),
                      ),
                    ),
                    const Positioned(left: 0, top: 0, child: _FontWarmup()),
                    Positioned.fill(
                      child: FittedBox(
                        child: SizedBox.fromSize(
                          size: BP.canvas,
                          child: Stack(
                            clipBehavior: Clip.none,
                            children: [
                              Positioned.fill(child: _slides()),
                              const Positioned.fill(
                                child: IgnorePointer(
                                  child: CustomPaint(painter: CropMarksPainter()),
                                ),
                              ),
                              ?worldRuler,
                              if (worldRuler == null)
                                Positioned(
                                  left: BP.margin,
                                  right: BP.margin,
                                  bottom: 22,
                                  height: 48,
                                  child: _Ruler(controller: _c),
                                ),
                              if (_c.overview) Positioned.fill(child: _Overview(controller: _c)),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget? _worldRuler() {
    final r = _world.ruler(_c);
    if (r == null) return null;
    return Positioned(left: 0, right: 0, bottom: 0, height: 110, child: r);
  }


  Widget _slides() {
    final def = _c.current;
    final key = ValueKey('${_world.id}:${_c.index}:${_c.nonce}');
    final worldTransition = _world.transition;
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 800),
      layoutBuilder: (current, previous) =>
          Stack(fit: StackFit.expand, children: [...previous, ?current]),
      transitionBuilder: (child, anim) => worldTransition != null
          ? worldTransition(
              context,
              child,
              anim,
              incoming: child.key == key,
              forward: _c.direction > 0,
            )
          : _Wipe(
              animation: anim,
              incoming: child.key == key,
              forward: _c.direction > 0,
              child: child,
            ),
      child: SlideScope(
        key: key,
        index: _c.index,
        step: _c.step,
        total: _c.slides.length,
        section: def.section,
        child: Builder(builder: def.builder),
      ),
    );
  }
}

/// Blueprint wipe: a scan line sweeps across, revealing the next sheet.
class _Wipe extends StatelessWidget {
  const _Wipe({
    required this.animation,
    required this.incoming,
    required this.forward,
    required this.child,
  });

  final Animation<double> animation;
  final bool incoming;
  final bool forward;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      child: child,
      builder: (context, child) {
        // Incoming runs 0→1, outgoing runs 1→0; both map to the same edge.
        final u = incoming ? animation.value : 1 - animation.value;
        final e = Curves.easeInOutCubic.transform(u.clamp(0.0, 1.0));
        final edge = forward ? e : 1 - e;
        final showNew = incoming;
        // forward: new sheet is left of the edge; backward: right of it.
        final keepLeft = forward ? showNew : !showNew;
        final done = incoming && u >= 1;
        // Keep the same widget structure throughout so slide state survives.
        return Stack(
          fit: StackFit.expand,
          children: [
            ClipRect(
              clipper: _EdgeClipper(edge: edge, keepLeft: keepLeft, open: done),
              child: IgnorePointer(ignoring: !incoming, child: child),
            ),
            if (incoming && !done)
              IgnorePointer(
                child: CustomPaint(
                  painter: _ScanLinePainter(edge: edge, t: u, forward: forward),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _EdgeClipper extends CustomClipper<Rect> {
  _EdgeClipper({required this.edge, required this.keepLeft, this.open = false});

  final double edge;
  final bool keepLeft;
  final bool open;

  @override
  Rect getClip(Size size) {
    if (open) return Rect.fromLTRB(-400, -400, size.width + 400, size.height + 400);
    final x = size.width * edge;
    return keepLeft
        ? Rect.fromLTRB(-400, -400, x, size.height + 400)
        : Rect.fromLTRB(x, -400, size.width + 400, size.height + 400);
  }

  @override
  bool shouldReclip(_EdgeClipper old) =>
      old.edge != edge || old.keepLeft != keepLeft || old.open != open;
}

class _ScanLinePainter extends CustomPainter {
  _ScanLinePainter({required this.edge, required this.t, required this.forward});

  final double edge;
  final double t;
  final bool forward;

  @override
  void paint(Canvas canvas, Size size) {
    final x = size.width * edge;
    final fade = math.sin(t * math.pi).clamp(0.0, 1.0);
    final trail = 120.0 * (forward ? -1 : 1);
    canvas.drawRect(
      Rect.fromLTRB(math.min(x, x + trail), 0, math.max(x, x + trail), size.height),
      Paint()
        ..shader =
            LinearGradient(
              begin: forward ? Alignment.centerRight : Alignment.centerLeft,
              end: forward ? Alignment.centerLeft : Alignment.centerRight,
              colors: [
                BP.line.withValues(alpha: 0.18 * fade),
                BP.line.withValues(alpha: 0),
              ],
            ).createShader(
              Rect.fromLTRB(math.min(x, x + trail), 0, math.max(x, x + trail), size.height),
            ),
    );
    canvas.drawLine(
      Offset(x, -40),
      Offset(x, size.height + 40),
      Paint()
        ..color = BP.line.withValues(alpha: 0.9 * fade)
        ..strokeWidth = 2,
    );
    // Tick marks riding the scan line.
    final tick = Paint()
      ..color = BP.line.withValues(alpha: 0.6 * fade)
      ..strokeWidth = 1;
    for (var y = 0.0; y < size.height; y += 24) {
      final l = (y % 120 == 0) ? 14.0 : 6.0;
      canvas.drawLine(Offset(x - l, y), Offset(x + l, y), tick);
    }
  }

  @override
  bool shouldRepaint(_ScanLinePainter old) => old.edge != edge || old.t != t;
}

/// The blueprint grid, drawn across the whole window and aligned to the canvas.
class GridPaperPainter extends CustomPainter {
  GridPaperPainter({required this.scale, required this.origin});

  final double scale;
  final Offset origin;

  @override
  void paint(Canvas canvas, Size size) {
    final minor = Paint()
      ..color = BP.gridMinor
      ..strokeWidth = 1;
    final major = Paint()
      ..color = BP.gridMajor
      ..strokeWidth = 1;
    final step = 24 * scale;
    if (step < 2) return;
    var i = -((origin.dx / step).ceil());
    for (var x = origin.dx + i * step; x < size.width; x += step, i++) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), i % 5 == 0 ? major : minor);
    }
    var j = -((origin.dy / step).ceil());
    for (var y = origin.dy + j * step; y < size.height; y += step, j++) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), j % 5 == 0 ? major : minor);
    }
  }

  @override
  bool shouldRepaint(GridPaperPainter old) => old.scale != scale || old.origin != origin;
}

class CropMarksPainter extends CustomPainter {
  const CropMarksPainter({this.inset = 18, this.length = 22, this.color = BP.line});

  final double inset;
  final double length;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..strokeWidth = 1.5;
    final r = Rect.fromLTRB(inset, inset, size.width - inset, size.height - inset);
    for (final c in [r.topLeft, r.topRight, r.bottomLeft, r.bottomRight]) {
      final dx = c.dx < size.width / 2 ? length : -length;
      final dy = c.dy < size.height / 2 ? length : -length;
      canvas.drawLine(c, c + Offset(dx, 0), p);
      canvas.drawLine(c, c + Offset(0, dy), p);
    }
  }

  @override
  bool shouldRepaint(CropMarksPainter old) => false;
}

/// Bottom progress ruler: one tick per slide, a marker for the current one.
class _Ruler extends StatelessWidget {
  const _Ruler({required this.controller});

  final DeckController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final n = c.slides.length;
    return LayoutBuilder(
      builder: (context, box) {
        final w = box.maxWidth - 260;
        double xOf(int i) => 170 + (n == 1 ? 0 : i * w / (n - 1));
        return Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              left: 0,
              top: 16,
              child: Text(c.current.section, style: BT.mono(14, color: BP.inkDim)),
            ),
            Positioned(
              right: 0,
              top: 16,
              child: GestureDetector(
                onTap: c.toggleOverview,
                child: MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: Text(
                    '${(c.index + 1).toString().padLeft(2, '0')} / ${n.toString().padLeft(2, '0')}',
                    style: BT.mono(14, color: BP.line),
                  ),
                ),
              ),
            ),
            for (var i = 0; i < n; i++)
              Positioned(
                left: xOf(i) - 8,
                top: 8,
                width: 16,
                height: 30,
                child: _Tick(
                  title: c.slides[i].title,
                  major: i == 0 || c.slides[i].section != c.slides[i - 1].section,
                  done: i <= c.index,
                  onTap: () => c.goTo(i),
                ),
              ),
            AnimatedPositioned(
              duration: const Duration(milliseconds: 500),
              curve: Curves.easeOutCubic,
              left: xOf(c.index) - 6,
              top: 0,
              child: Transform.rotate(
                angle: math.pi / 4,
                child: Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: BP.amber,
                    border: Border.all(color: BP.paper, width: 2),
                  ),
                ),
              ),
            ),
            if (c.current.steps > 1)
              Positioned(
                left: xOf(c.index) - (c.current.steps * 8) / 2 + 1,
                top: 40,
                child: Row(
                  children: [
                    for (var s = 0; s < c.current.steps; s++)
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 250),
                        width: 5,
                        height: 5,
                        margin: const EdgeInsets.only(right: 3),
                        color: s <= c.step ? BP.amber : BP.lineFaint,
                      ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}

class _Tick extends StatefulWidget {
  const _Tick({required this.title, required this.major, required this.done, required this.onTap});

  final String title;
  final bool major;
  final bool done;
  final VoidCallback onTap;

  @override
  State<_Tick> createState() => _TickState();
}

class _TickState extends State<_Tick> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.topCenter,
          children: [
            Positioned(
              top: 12,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: _hover ? 3 : 1.5,
                height: widget.major ? 18 : 9,
                color: _hover ? BP.amber : (widget.done ? BP.line : BP.lineDim),
              ),
            ),
            if (_hover)
              Positioned(
                bottom: 34,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: BP.panel,
                    border: Border.all(color: BP.line),
                  ),
                  child: Text(widget.title, softWrap: false, style: BT.mono(13, color: BP.ink)),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Overview extends StatelessWidget {
  const _Overview({required this.controller});

  final DeckController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 300),
      builder: (context, t, child) => Opacity(opacity: t, child: child),
      child: Container(
        color: BP.paper.withValues(alpha: 0.96),
        padding: const EdgeInsets.fromLTRB(64, 56, 64, 90),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('index', style: BT.mono(16)),
            const SizedBox(height: 16),
            Expanded(
              child: GridView.count(
                crossAxisCount: 6,
                mainAxisSpacing: 14,
                crossAxisSpacing: 14,
                childAspectRatio: 16 / 9,
                children: [
                  for (var i = 0; i < c.slides.length; i++)
                    _OverviewCard(
                      index: i,
                      def: c.slides[i],
                      current: i == c.index,
                      onTap: () => c.goTo(i),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OverviewCard extends StatefulWidget {
  const _OverviewCard({
    required this.index,
    required this.def,
    required this.current,
    required this.onTap,
  });

  final int index;
  final SlideDef def;
  final bool current;
  final VoidCallback onTap;

  @override
  State<_OverviewCard> createState() => _OverviewCardState();
}

class _OverviewCardState extends State<_OverviewCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final hot = _hover || widget.current;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: hot ? BP.panel : BP.paper,
            border: Border.all(
              color: widget.current ? BP.amber : (hot ? BP.line : BP.lineFaint),
              width: widget.current ? 2 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${(widget.index + 1).toString().padLeft(2, '0')} / ${widget.def.section}',
                style: BT.mono(12, color: BP.inkDim),
              ),
              const Spacer(),
              Text(widget.def.title, style: BT.display(20, color: BP.ink)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Lays out (never paints) one paragraph with every script the deck uses, so on
/// the web CanvasKit downloads the Noto fallback fonts early — but only after
/// the title slide has had a moment to animate.
class _FontWarmup extends StatefulWidget {
  const _FontWarmup();

  @override
  State<_FontWarmup> createState() => _FontWarmupState();
}

class _FontWarmupState extends State<_FontWarmup> {
  static const _sample =
      'Aa ب ש अक्षि ক ก่ข 文字字 かなカナ 한글 Жж Ωω ა Ա ሀ ཀ Ꭰ ᐃ ᠮ 縦書き 👋🏽👨‍👩‍👧‍👦🇩🇿😀👩‍💻 ✕✓◆□';

  bool _go = false;
  Timer? _t;

  @override
  void initState() {
    super.initState();
    _t = Timer(const Duration(milliseconds: 1500), () {
      if (mounted) setState(() => _go = true);
    });
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _go
      ? const Offstage(
          child: Text(_sample, style: TextStyle(fontFamily: BP.display, fontSize: 12)),
        )
      : const SizedBox();
}
