part of 'factory_draw.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Static parts, recorded once into two pictures (behind and in front of
// everything that moves).
// ─────────────────────────────────────────────────────────────────────────────

class _Static extends FactoryInk {
  _Static(super.c, this.sc);

  final FactoryScene sc;

  FactoryTexts get tx => sc.texts;

  void back() {
    hall();
    elevatorFrame();
    lineFrame();
    sorter();
    fonts();
    pressFrame();
    exitBeltFrame();
    plates();
  }

  void front() {
    hopper();
    kiln();
    walls();
    roof();
    bin();
    floorProps();
  }

  void hall() {
    const hall = Rect.fromLTRB(FG.left, FG.roofBot, FG.right, FG.floor);
    c.drawRect(hall, fl(_hallFill));
    // Back wall: panel seams and a dado rail.
    final seams = Path();
    for (var x = FG.left + 46.0; x < FG.right - 12; x += 46) {
      seams
        ..moveTo(x, FG.trussY + 2)
        ..lineTo(x, FG.floor);
    }
    c.drawPath(seams, st(BP.gridMinor, 1));
    c.drawLine(const Offset(FG.left + 7, 652), const Offset(FG.right - 7, 652), st(BP.gridMajor, 1));
    // High windows either side of the screen.
    for (final r in const [Rect.fromLTRB(62, 434, 96, 476), Rect.fromLTRB(500, 434, 544, 476)]) {
      c.drawRect(r, fl(BP.paper));
      c.drawRect(r, st(BP.lineDim, 1));
      c.drawLine(Offset(r.center.dx, r.top), Offset(r.center.dx, r.bottom), st(BP.lineFaint, 1));
      c.drawLine(Offset(r.left, r.center.dy), Offset(r.right, r.center.dy), st(BP.lineFaint, 1));
    }
    // Roof truss.
    final diag = Path();
    var up = true;
    for (var x = FG.left + 7.0; x < FG.right - 8; x += 14) {
      diag
        ..moveTo(x, up ? FG.roofBot : FG.trussY)
        ..lineTo(x + 14, up ? FG.trussY : FG.roofBot);
      up = !up;
    }
    c.drawPath(diag, st(BP.lineFaint, 1));
    c.drawLine(const Offset(FG.left + 7, FG.trussY), const Offset(FG.right - 7, FG.trussY), st(BP.lineDim, 1.2));
    // Screen hangers.
    for (final x in [FG.screen.left + 26, FG.screen.right - 26]) {
      c.drawLine(Offset(x, FG.trussY), Offset(x, FG.screen.top), st(BP.lineDim, 1.2));
    }
    // The right bay: a wall clock and the green-cross safety banner.
    c.drawCircle(_clock, 10, fl(BP.panel));
    c.drawCircle(_clock, 10, st(BP.line, 1.2));
    for (var i = 0; i < 12; i++) {
      final a = i * math.pi / 6;
      final u = Offset(math.cos(a), math.sin(a));
      c.drawLine(_clock + u * (i % 3 == 0 ? 7 : 8.2), _clock + u * 9.2, st(BP.lineDim, 1));
    }
    const banner = Rect.fromLTRB(529, 500, 547, 584);
    box(banner, col: BP.green.withValues(alpha: 0.8), w: 1.1);
    final cross = banner.topCenter + const Offset(0, 9);
    c.drawRect(Rect.fromCenter(center: cross, width: 10, height: 3.4), fl(BP.green));
    c.drawRect(Rect.fromCenter(center: cross, width: 3.4, height: 10), fl(BP.green));
    for (var i = 0; i < 4; i++) {
      final p = tx.get('安全第一'[i], FS.name(12, BP.ink), key: 'safe');
      p.paint(c, Offset(banner.center.dx - p.width / 2, banner.top + 18 + i * 15.5));
    }
    // Floor.
    c.drawLine(const Offset(FG.left, FG.floor - 0.5), const Offset(FG.right, FG.floor - 0.5), st(BP.line, 1.4));
  }

  void elevatorFrame() {
    const x = FG.elevX, top = FG.elevTop - 12, bot = 696.0;
    for (final dx in [-11.0, 11.0]) {
      c.drawLine(Offset(x + dx, top), Offset(x + dx, bot), st(BP.lineDim, 1.2));
    }
    final brace = Path()..moveTo(x - 11, top + 20);
    var l = true;
    for (var y = top + 20; y < bot - 24; y += 24) {
      brace.lineTo(l ? x + 11 : x - 11, y + 24);
      l = !l;
    }
    c.drawPath(brace, st(BP.lineFaint, 1));
    // Discharge chute from the head into the hopper.
    final chute = Path()
      ..moveTo(x + 6, FG.elevTop - 6)
      ..lineTo(x + 26, FG.elevTop + 6)
      ..lineTo(x + 24, FG.elevTop + 11)
      ..lineTo(x + 6, FG.elevTop + 2)
      ..close();
    c.drawPath(chute, fl(BP.panel));
    c.drawPath(chute, st(BP.line, 1.1));
  }

  void lineFrame() {
    const r = Rect.fromLTRB(FG.lineL, FG.lineY, FG.lineR, FG.lineY + 8);
    c.drawRect(r, fl(BP.panel));
    c.drawLine(r.topLeft, r.topRight, st(BP.line, 1.3));
    c.drawLine(r.bottomLeft, r.bottomRight, st(BP.line, 1.3));
    c.drawCircle(Offset(r.left, r.center.dy), 4, fl(BP.panel));
    c.drawCircle(Offset(r.left, r.center.dy), 4, st(BP.line, 1.1));
    final legs = Path();
    for (final x in [118.0, 300.0]) {
      legs
        ..moveTo(x - 3, r.bottom)
        ..lineTo(x - 3, FG.floor)
        ..moveTo(x + 3, r.bottom)
        ..lineTo(x + 3, FG.floor)
        ..moveTo(x - 8, FG.floor - 1)
        ..lineTo(x + 8, FG.floor - 1);
    }
    c.drawPath(legs, st(BP.lineDim, 1.2));
  }

  void sorter() {
    final roof = Path()
      ..moveTo(154, 528)
      ..lineTo(210, 528)
      ..lineTo(218, 536)
      ..lineTo(146, 536)
      ..close();
    c.drawPath(roof, fl(BP.panel));
    c.drawPath(roof, st(BP.line, 1.3));
    box(const Rect.fromLTRB(148, 536, 216, 590));
    c.drawRect(_sortScreen, fl(_glass));
    c.drawRect(_sortScreen, st(BP.lineDim, 1));
    for (var i = 0; i < 4; i++) {
      c.drawCircle(Offset(161 + 14.0 * i, 577), 3.6, st(BP.lineDim, 1));
    }
    for (final x in [152.0, 212.0]) {
      c.drawLine(Offset(x, 590), Offset(x, FG.lineY), st(BP.line, 1.2));
    }
    box(const Rect.fromLTRB(175, 586, 189, 592), w: 1.1);
  }

  void fonts() {
    box(const Rect.fromLTRB(228, 528, 296, 590));
    c.drawRect(_fontGlass, fl(_glass));
    c.drawRect(_fontGlass, st(BP.lineDim, 1));
    for (var i = 0; i < 4; i++) {
      final r = _fontCellRect(i);
      c.drawRect(r.deflate(1.5), st(BP.lineFaint, 1));
      final style = i == 0 ? BT.sample(15, color: BP.inkDim) : FS.name(15, BP.inkDim);
      paintFit(tx.get(_fontCellGlyphs[i], style, key: 'cell$i'), r.deflate(3), fitHeight: true);
    }
    // The name strip: which font is being handed out.
    c.drawRect(_fontStrip, fl(_glass));
    c.drawRect(_fontStrip, st(BP.lineDim, 1));
    for (var i = 0; i < 2; i++) {
      c.drawCircle(Offset(237 + 10.0 * i, 584), 2.6, st(BP.lineDim, 1));
    }
    final chute = Path()
      ..moveTo(256, 580)
      ..lineTo(272, 580)
      ..lineTo(269, 590)
      ..lineTo(259, 590)
      ..close();
    c.drawPath(chute, st(BP.line, 1.2));
    for (final x in [232.0, 292.0]) {
      c.drawLine(Offset(x, 590), Offset(x, FG.lineY), st(BP.line, 1.2));
    }
  }

  void pressFrame() {
    box(const Rect.fromLTRB(310, 532, 374, 552));
    c.drawCircle(_pressGauge, 7, fl(BP.panel));
    c.drawCircle(_pressGauge, 7, st(BP.lineDim, 1));
    box(const Rect.fromLTRB(314, 552, 322, FG.lineY + 8), w: 1.1);
    box(const Rect.fromLTRB(362, 552, 370, FG.lineY + 8), w: 1.1);
    c.drawLine(const Offset(374, 538), _flywheel + const Offset(-2, -3), st(BP.lineDim, 1));
    c.drawCircle(_flywheel, 9, fl(BP.panel));
    c.drawCircle(_flywheel, 9, st(BP.line, 1.2));
    // Anvil plate under the belt.
    c.drawLine(const Offset(318, FG.lineY + 10), const Offset(366, FG.lineY + 10), st(BP.lineDim, 2));
  }

  void exitBeltFrame() {
    const r = Rect.fromLTRB(BL.beltStart, BL.beltY, BL.beltEnd, BL.beltY + 8);
    c.drawRect(r, fl(BP.panel));
    c.drawLine(r.topLeft, r.topRight, st(BP.line, 1.3));
    c.drawLine(r.bottomLeft, r.bottomRight, st(BP.line, 1.2));
    final legs = Path();
    for (final x in [500.0, 596.0]) {
      legs
        ..moveTo(x, r.bottom)
        ..lineTo(x, FG.floor)
        ..moveTo(x - 6, FG.floor - 1)
        ..lineTo(x + 6, FG.floor - 1);
    }
    c.drawPath(legs, st(BP.lineDim, 1.2));
    // End stop: the pallet waits here for the crane.
    box(const Rect.fromLTRB(626, 668, 631, BL.beltY), w: 1.1);
    c.drawCircle(Offset(r.right, r.center.dy), 4, fl(BP.panel));
    c.drawCircle(Offset(r.right, r.center.dy), 4, st(BP.line, 1.1));
  }

  void plates() {
    final rs = _plates(tx);
    for (var k = 0; k < 5; k++) {
      final r = rs[k];
      for (final dx in [-r.width / 2 + 8, r.width / 2 - 8]) {
        c.drawLine(Offset(r.center.dx + dx, r.bottom), Offset(r.center.dx + dx, r.bottom + 4), st(BP.lineDim, 1));
      }
      box(r, col: BP.lineDim, w: 1);
      final p = tx.get(FG.machineNames[k], FS.plate, key: 'plate');
      p.paint(c, Offset(r.center.dx - p.width / 2, r.center.dy - p.height / 2));
    }
  }

  // ── In front of the moving parts ─────────────────────────────────────────

  void hopper() {
    final shell = Path()
      ..fillType = PathFillType.evenOdd
      ..addPath(_funnel, Offset.zero)
      ..addRect(FG.hopperPile)
      ..addRect(FG.hopperBody)
      ..addRect(FG.hopperReader);
    c.drawPath(shell, fl(BP.panel));
    c.drawPath(_funnel, st(BP.line, 1.4));
    c.drawRect(FG.hopperBody, st(BP.line, 1.3));
    c.drawRect(FG.hopperPile, st(BP.lineDim, 1));
    c.drawRect(FG.hopperReader, st(BP.lineDim, 1.1));
    c.drawLine(const Offset(70, 598), const Offset(134, 598), st(BP.line, 2));
    c.drawLine(const Offset(58, FG.funnelTop), const Offset(146, FG.funnelTop), st(BP.line, 2));
    // The tube into the hopper.
    final tube = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 11
      ..color = BP.line;
    c.drawPath(_tube, tube);
    c.drawPath(_tube, tube
      ..strokeWidth = 8
      ..color = BP.panel);
    final nozzle = Path()
      ..moveTo(_tubeX - 7, 522)
      ..lineTo(_tubeX + 7, 522)
      ..lineTo(_tubeX + 10, 529)
      ..lineTo(_tubeX - 10, 529)
      ..close();
    c.drawPath(nozzle, fl(BP.panel));
    c.drawPath(nozzle, st(BP.line, 1.2));
    // Clamps along the tube.
    for (final y in [440.0, 480.0]) {
      c.drawLine(Offset(_tubeX - 6, y), Offset(_tubeX + 6, y), st(BP.lineDim, 1.4));
    }
  }

  void kiln() {
    const k = FG.kiln;
    final shell = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(k)
      ..addRect(FG.kilnWin);
    c.drawPath(shell, fl(BP.panel));
    c.drawRect(k, st(BP.line, 1.4));
    c.drawRect(FG.kilnWin, st(BP.line, 1.3));
    c.drawRect(FG.kilnWin.inflate(4), st(BP.lineDim, 1));
    box(Rect.fromLTRB(k.left - 4, k.top - 5, k.right + 4, k.top + 1), w: 1.2);
    // Brick courses on the lower body.
    final courses = Path();
    for (var y = 616.0; y < 648; y += 8) {
      courses
        ..moveTo(k.left + 6, y)
        ..lineTo(k.right - 6, y);
      for (var x = k.left + 6 + ((y ~/ 8).isEven ? 0 : 7); x < k.right - 6; x += 14) {
        courses
          ..moveTo(x, y)
          ..lineTo(x, y + 8);
      }
    }
    c.drawPath(courses, st(BP.lineFaint, 1));
    // Dials.
    c.drawCircle(_kilnGauge, 8, fl(BP.panel));
    c.drawCircle(_kilnGauge, 8, st(BP.lineDim, 1));
    for (var i = 0; i < 3; i++) {
      c.drawCircle(Offset(428 + 12.0 * i, 603), 3.6, st(BP.lineDim, 1));
    }
    // Mouths: the line goes in on the left, pallets come out on the right.
    c.drawRect(const Rect.fromLTRB(390, 598, 394, FG.lineY + 8), fl(BP.paper));
    c.drawRect(const Rect.fromLTRB(390, 598, 394, FG.lineY + 8), st(BP.lineDim, 1));
    c.drawRect(const Rect.fromLTRB(466, 660, 470, BL.beltY), fl(BP.paper));
    c.drawRect(const Rect.fromLTRB(466, 660, 470, BL.beltY), st(BP.lineDim, 1));
    // Firebox.
    box(_firebox, w: 1.2);
    c.drawRect(_firebox.deflate(7), st(BP.line, 1));
    // Flue: out of the kiln's shoulder, up through the roof.
    box(const Rect.fromLTRB(470, 538, 478, 548), w: 1.1);
    box(const Rect.fromLTRB(FG.flueX - 5, 392, FG.flueX + 5, 548), w: 1.2);
    for (final y in [430.0, 480.0, 520.0]) {
      c.drawLine(Offset(FG.flueX - 7, y), Offset(FG.flueX + 7, y), st(BP.lineDim, 1.4));
    }
    c.drawLine(const Offset(FG.flueX - 8, 392), const Offset(FG.flueX + 8, 392), st(BP.line, 2));
  }

  void walls() {
    box(const Rect.fromLTRB(FG.left, FG.roofBot, FG.left + FG.wall, FG.floor), w: 1.2);
    box(const Rect.fromLTRB(FG.right - FG.wall, FG.roofBot, FG.right, FG.doorTop), w: 1.2);
    box(const Rect.fromLTRB(FG.right - 11, FG.doorTop - 4, FG.right, FG.doorTop + 3), w: 1.2);
  }

  void roof() {
    box(const Rect.fromLTRB(FG.left, FG.roofTop, FG.right, FG.roofBot), w: 1.3);
    c.drawLine(const Offset(FG.left, FG.roofTop), const Offset(FG.right, FG.roofTop), st(BP.line, 2));
    // The sign on the roof.
    final p = tx.get('グリフ工場 · Glyph Works', FS.sign, key: 'sign');
    final r = Rect.fromCenter(center: const Offset(306, 392), width: p.width + 28, height: 21);
    for (final x in [r.left + 18, r.right - 18]) {
      c.drawLine(Offset(x, r.bottom), Offset(x, FG.roofTop), st(BP.lineDim, 1.4));
    }
    box(r, col: BP.amber, w: 1.4, fill: const Color(0xFF14243A));
    p.paint(c, Offset(r.center.dx - p.width / 2, r.center.dy - p.height / 2));
    // The tube along the roof (drawn here so it sits on top of it).
    final tube = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 11
      ..color = BP.line;
    final upper = Path()
      ..moveTo(FG.left, 392)
      ..lineTo(_tubeX - 14, 392)
      ..quadraticBezierTo(_tubeX, 392, _tubeX, 406)
      ..lineTo(_tubeX, 414);
    c.drawPath(upper, tube);
    c.drawPath(upper, tube
      ..strokeWidth = 8
      ..color = BP.panel);
  }

  void bin() {
    final p = Path()..addPolygon(_bin, true);
    c.drawPath(p, fl(BP.panel));
    c.drawPath(p, st(BP.line, 1.3));
    c.drawLine(const Offset(30, FG.binTop), const Offset(144, FG.binTop), st(BP.line, 2));
    // Grate.
    final g = Path();
    for (var x = 40.0; x < 140; x += 8) {
      g
        ..moveTo(x, FG.binTop - 3)
        ..lineTo(x, FG.binTop);
    }
    c.drawPath(g, st(BP.lineDim, 1));
    final label = tx.get('リサイクル', FS.small, key: 'bin');
    label.paint(c, Offset(68, 684 - label.height / 2));
    recycleMark(this, const Offset(58, 684), 6.5, BP.green.withValues(alpha: 0.75));
  }

  void floorProps() {
    // The hopper operator's gate lever box and the press lever box.
    box(const Rect.fromLTRB(132, 686, 144, FG.floor), w: 1.1);
    box(const Rect.fromLTRB(354, 686, 366, FG.floor), w: 1.1);
    // Crates of fonts: picked up by the hopper, delivered by the press.
    for (final (x, y, g) in [(171.0, 688.0, 'Aa'), (172.0, 676.0, 'あ'), (332.0, 688.0, '字')]) {
      final r = Rect.fromLTWH(x, y, 18, 12);
      crate(r, BP.lineDim, w: 1);
      paintFit(
        tx.get(g, g == 'Aa' ? BT.sample(9, color: BP.inkDim) : FS.name(9, BP.inkDim), key: 'fc'),
        r.deflate(2),
        fitHeight: true,
      );
    }
  }
}
