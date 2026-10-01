import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../model.dart';
import '../names.dart';
import '../store.dart';
import 'board.dart';
import 'fx.dart';
import 'ink.dart';
import 'input.dart';
import 'operator.dart';
import 'tally.dart';

/// Feedback above the input after Enter: a printed receipt (place in line
/// and wait, with the ticket as its stub) or a kind "not quite".
class Toast {
  const Toast({
    required this.ok,
    required this.en,
    required this.ja,
    required this.at,
    this.name,
    this.serial,
  });
  final bool ok;
  final String en;
  final String ja;

  /// Scene time it appeared.
  final double at;

  /// The accepted name and its job: the receipt's ticket stub.
  final String? name;
  final int? serial;

  /// Seconds on screen.
  double get life => ok ? 6.5 : 5.5;
}

/// A ticket printed for the job [serial] at scene time [at]: it rises with
/// its receipt out of the input, tears off, and flies to its place on the
/// rail.
class Flight {
  const Flight(this.serial, this.name, this.at);
  final int serial;
  final String name;
  final double at;

  static const leaves = 1.25;
  static const lands = 2.45;

  bool landed(double t) => t - at >= lands;
}

/// Operator feedback (real time, so fast-forward doesn't hurry it).
class Flash {
  Flash(this.en, this.ja, {this.warn = false}) : at = DateTime.now();
  final String en;
  final String ja;
  final bool warn;
  final DateTime at;

  double get age => DateTime.now().difference(at).inMilliseconds / 1000;
}

/// The UI's own state beside the model: the history of built names, the
/// toast and tickets after Enter, idle tracking, and the operator's help.
///
/// One per [BoothModel], shared by the overlay and the operator keys in the
/// scene through [BoothUi.of]. UI animations run on scene time ([model.t]),
/// so capture mode renders them like everything else.
class BoothUi extends ChangeNotifier {
  BoothUi._(this.model, BoothStore store) : history = BoothHistory(store) {
    history.addListener(_historyChanged);
    history.load().then((saved) => model.built.insertAll(0, saved.map((b) => b.name)));
    model.onBuilt = (m) => history.add(m.built.last);
    model.addListener(_tick);
  }

  static final _all = Expando<BoothUi>('BoothUi');

  /// The UI state for [m] (created on first use, with the default store).
  static BoothUi of(BoothModel m) => _all[m] ??= BoothUi._(m, createStore());

  /// Creates the UI state for [m] with [store] (tests).
  @visibleForTesting
  static BoothUi attach(BoothModel m, BoothStore store) => _all[m] = BoothUi._(m, store);

  final BoothModel model;
  final BoothHistory history;

  /// The board's title, when an app wants its own (the 3D booth: 名前の街 ·
  /// Name City). Null: by build mode (名前工場 / 名前工房).
  ({String ja, String en})? title;
  final text = UiText();

  /// No typing for this long: the input invites the next visitor.
  static const idleAfter = 20.0;

  /// Text typed and left this long is cleared for the next visitor.
  static const clearAfter = 90.0;

  /// More names than this waiting: "come back in a few minutes".
  static const maxQueue = 20;

  double get t => model.t;

  // ── Typing ────────────────────────────────────────────────────────────────

  /// Scene time of the last keystroke (or Enter).
  double lastInput = 0;

  /// Scene time of the last Enter (the ↵ key on screen goes down).
  double pressedAt = -100;

  /// Scene time of the last rejection (the input shakes its head).
  double shakeAt = -100;

  Toast? toast;
  final flights = <Flight>[];

  double idleFor(double t) => t - lastInput;

  /// The input changed (typing, IME composition).
  void typed() {
    lastInput = t;
    // Fixing a rejected name: the "not quite" can go.
    if (toast case final s? when !s.ok && t - s.at > 1.2) {
      toast = null;
      notifyListeners();
    }
  }

  /// Horizontal offset of the input while it shakes.
  double shakeDx(double t) {
    final a = t - shakeAt;
    if (a < 0 || a > 0.5) return 0;
    return math.sin(a * math.pi * 2 * 6) * 10 * (1 - a / 0.5);
  }

  Flight? flightFor(int serial) {
    for (final f in flights) {
      if (f.serial == serial) return f;
    }
    return null;
  }

  /// Enter with [raw] in the input: queues the name (toast + ticket) or
  /// explains kindly why not.
  NameCheck submit(String raw) {
    pressedAt = t;
    lastInput = t;
    var check = checkName(raw);
    if (check case NameOk(:final name)) check = _lineCheck(name) ?? check;
    if (check case NameRejected(:final en, :final ja)) {
      toast = Toast(ok: false, en: en, ja: ja, at: t);
      shakeAt = t;
      notifyListeners();
      return check;
    }
    // Before it joins the line this is the wait until it starts.
    final wait = model.estimatedWait;
    final r = model.submit(raw);
    if (r is NameOk) {
      final job = model.queue.last;
      toast = _accepted(job, model.queue.length, wait);
      flights.add(Flight(job.serial, job.name, t));
    }
    notifyListeners();
    return r;
  }

  NameRejected? _lineCheck(String name) {
    final k = name.toLowerCase();
    final j = model.job;
    final building =
        j != null && !j.sample && j.cutAt == null && j.phase.index <= Phase.reveal.index;
    if ((building && j.name.toLowerCase() == k) ||
        model.queue.any((q) => q.name.toLowerCase() == k)) {
      return NameRejected('$name is already in line!', '$nameさんはもう並んでいます');
    }
    if (model.queue.length >= maxQueue) {
      return const NameRejected(
        'The line is full: please try again in a few minutes',
        'ただいま満員です。少し後でもう一度どうぞ',
      );
    }
    return null;
  }

  /// The receipt for [job], [pos] in line, starting in about [wait] seconds.
  /// (The name is on its ticket stub, right beside the message.)
  Toast _accepted(Job job, int pos, double wait) {
    final mins = math.max(1, (wait / 60).round());
    final soon = wait < 45;
    final String en, ja;
    if (pos <= 1 && soon) {
      en = 'Got it! You’re next · starting now';
      ja = '受付完了！まもなく建設開始です';
    } else if (pos <= 1) {
      en = 'Got it! You’re next · in about $mins min';
      ja = '受付完了！次の番です・約$mins分後';
    } else {
      en = 'Got it! #$pos in line · starts in about $mins min';
      ja = '受付完了！$pos番目・約$mins分後に開始';
    }
    return Toast(ok: true, en: en, ja: ja, at: t, name: job.name, serial: job.serial);
  }

  void _tick() {
    final t = model.t;
    if (flights.isNotEmpty) flights.removeWhere((f) => t - f.at > Flight.lands + 0.6);
    if (toast case final s? when t - s.at > s.life + 0.6) toast = null;
  }

  // ── Built today ───────────────────────────────────────────────────────────

  List<BuiltName>? _today;
  int _todayKey = 0;

  /// The counter rolls from [countFrom] since scene time [countAt].
  int countFrom = 0;
  double countAt = -100;

  /// Names built today (local date), oldest first.
  List<BuiltName> get today {
    final now = DateTime.now();
    final key = now.year * 10000 + now.month * 100 + now.day;
    if (_today == null || key != _todayKey) {
      _today = history.on(now);
      _todayKey = key;
    }
    return _today!;
  }

  void _historyChanged() {
    final before = _today?.length ?? 0;
    _today = null;
    if (today.length != before) {
      countFrom = before;
      countAt = t;
    }
    notifyListeners();
  }

  // ── Operator (Ctrl+Shift+…, see BoothScene) ──────────────────────────────

  bool help = false;
  double speed = 1;
  Flash? flash;
  DateTime? _armed;

  /// Ctrl+Shift+R was pressed once: a second press resets today.
  bool get armed =>
      _armed != null && DateTime.now().difference(_armed!) < const Duration(seconds: 6);

  void _flash(String en, String ja, {bool warn = false}) {
    flash = Flash(en, ja, warn: warn);
    notifyListeners();
  }

  void toggleHelp() {
    help = !help;
    _armed = null;
    notifyListeners();
  }

  void operatorSkip() {
    final j = model.job;
    if (j == null || j.phase == Phase.demolish || j.phase == Phase.cleanup) {
      _flash('Nothing to skip right now', 'スキップするものはありません');
      return;
    }
    model.skip();
    _flash('Skipped “${j.name}”', '「${j.name}」をスキップ');
  }

  void operatorDropLast() {
    if (model.queue.isEmpty) {
      _flash('Nobody is waiting', '待っている人はいません');
      return;
    }
    final name = model.queue.last.name;
    model.dropLast();
    _flash('Removed “$name” from the line', '「$name」を列から削除');
  }

  /// Ctrl+Shift+M: Name Factory (bricks) ↔ Name Workshop (crafts), from
  /// the next name on.
  void operatorMode() {
    final craft = model.mode == BuildMode.bricks;
    model.mode = craft ? BuildMode.craft : BuildMode.bricks;
    _flash(
      craft
          ? 'Next name: Name Workshop (one character at a time)'
          : 'Next name: Name Factory (bricks)',
      craft ? '次の名前から：名前工房' : '次の名前から：名前工場',
    );
  }

  void operatorSpeed(double s) {
    speed = s;
    final x = s.round();
    _flash(s > 1 ? 'Fast-forward ×$x' : 'Normal speed', s > 1 ? '早送り ×$x' : '通常の速さ');
  }

  /// Ctrl+Shift+R: the first press opens the help and asks; a second press
  /// within a few seconds forgets today's names.
  void operatorReset() {
    if (!armed) {
      _armed = DateTime.now();
      help = true;
      _flash('Press Ctrl+Shift+R again to reset today', 'もう一度押すと今日の記録をリセット', warn: true);
      return;
    }
    _armed = null;
    history.clearDay().then((gone) {
      // The model's list mirrors the history; today's are its newest.
      for (final b in gone.reversed) {
        final i = model.built.lastIndexOf(b.name);
        if (i >= 0) model.built.removeAt(i);
      }
      _flash('Today’s history reset (${gone.length} names)', '今日の記録をリセットしました（${gone.length}名）');
    });
  }
}

/// Everything the booth shows on top of the scene layers: the board (top
/// left), the input and the built-today tally (bottom band), the toast and
/// flying tickets after Enter, and the operator's help.
class BoothOverlay extends StatefulWidget {
  const BoothOverlay({super.key, required this.model});

  final BoothModel model;

  @override
  State<BoothOverlay> createState() => _BoothOverlayState();
}

class _BoothOverlayState extends State<BoothOverlay> {
  late final BoothUi _ui = BoothUi.of(widget.model);

  @override
  Widget build(BuildContext context) {
    final m = widget.model;
    return RepaintBoundary(
      child: Stack(
        fit: StackFit.expand,
        children: [
          IgnorePointer(child: CustomPaint(painter: _BackPainter(m, _ui))),
          NameInput(model: m),
          IgnorePointer(child: CustomPaint(painter: _FrontPainter(m, _ui))),
        ],
      ),
    );
  }
}

class _BackPainter extends CustomPainter {
  _BackPainter(this.m, this.ui) : super(repaint: Listenable.merge([m, ui]));

  final BoothModel m;
  final BoothUi ui;

  @override
  void paint(Canvas canvas, Size size) {
    ui.text.frame(m.t);
    final k = UiInk(canvas, ui.text);
    paintBoard(k, m, ui);
    paintTally(k, m, ui);
  }

  @override
  bool shouldRepaint(_BackPainter old) => old.m != m || old.ui != ui;
}

class _FrontPainter extends CustomPainter {
  _FrontPainter(this.m, this.ui) : super(repaint: Listenable.merge([m, ui]));

  final BoothModel m;
  final BoothUi ui;

  @override
  void paint(Canvas canvas, Size size) {
    ui.text.frame(m.t);
    final k = UiInk(canvas, ui.text);
    paintFx(k, m, ui);
    paintOperator(k, m, ui);
  }

  @override
  bool shouldRepaint(_FrontPainter old) => old.m != m || old.ui != ui;
}
