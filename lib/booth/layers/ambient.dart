import 'package:flutter/rendering.dart';

import '../../worlds/factory/factory_kit.dart';
import '../layer.dart';
import '../layout.dart';
import '../model.dart';
import 'ambient_city.dart';
import 'ambient_kit.dart';
import 'ambient_sky.dart';
import 'ambient_street.dart';
import 'ambient_street_sim.dart';
import 'ambient_train.dart';

/// The city of text around the factory, behind everything else: a sky with
/// an 8-minute day (sun 日, moon 月, glyph stars), word-clouds, glyph-birds,
/// the talk's blimp, a skyline whose windows are letters of many scripts
/// and whose neon signs say hello in many languages, an elevated letter
/// train, and in front of it all the street: traffic, the bus stop, people
/// walking by (and stopping to watch the name go up).
///
/// Everything is a function of the scene time except the street, which is a
/// small simulation ([StreetSim]) stepped with the model.
class AmbientLayer extends BoothLayer {
  final _text = TextCache();
  final _sprites = AmbientSprites();
  final _batch = SpriteBatch(8000);
  final _sky = SkyArt();
  final _city = CityArt();
  final _train = TrainArt();
  final _street = StreetArt();
  final _sim = StreetSim();

  @override
  BoothSystem? get system => _sim;

  @override
  CustomPainter painter(BoothModel m) => _CityPainter(this, m);

  @override
  CustomPainter? foreground(BoothModel m) => _StreetPainter(this, m);

  AmbientFrame _frame(Canvas c, BoothModel m) {
    _sprites.prepare();
    c.clipRect(Offset.zero & BL.size);
    return AmbientFrame(c, m, _text, _sprites, _batch);
  }

  @override
  void dispose() {
    _text.dispose();
    _sprites.dispose();
    _city.dispose();
    _train.dispose();
    _street.dispose();
  }
}

/// Sky, skyline, train and the road surface (behind the factory and site).
class _CityPainter extends CustomPainter {
  _CityPainter(this.l, this.m) : super(repaint: m);

  final AmbientLayer l;
  final BoothModel m;

  @override
  void paint(Canvas c, Size size) {
    final f = l._frame(c, m);
    l._sky.paintSky(f);
    l._sky.paintClouds(f);
    // Balloons rise from behind the rooftops.
    l._sky.paintBalloons(f);
    l._train.paintPillars(f);
    l._city.paint(f);
    l._train.paintDeck(f);
    // Nearer than the skyline's tower and the train.
    l._sky.paintBlimp(f);
    l._sky.paintBirds(f);
    l._street.paintBack(f);
  }

  @override
  bool shouldRepaint(_CityPainter old) => false;
}

/// The street in front of everything (never above the ground line over the
/// plot, never into the input band).
class _StreetPainter extends CustomPainter {
  _StreetPainter(this.l, this.m) : super(repaint: m);

  final AmbientLayer l;
  final BoothModel m;

  @override
  void paint(Canvas c, Size size) {
    final f = l._frame(c, m);
    l._street.paintFront(f, l._sim);
  }

  @override
  bool shouldRepaint(_StreetPainter old) => false;
}
