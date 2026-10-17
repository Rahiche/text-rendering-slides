import 'dart:convert' show json, utf8;
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm;

import 'figure_rig.dart';

// The rigged people's skeleton and how it's posed: from the city's own
// figure rig ([FigureRig], whatever a scene has someone doing) and from
// motion-capture clips. rigged.dart dresses and draws them.
//
// Spaces: "model" is the skeleton's own (glTF's: y up, the person facing
// +z, their left at +x); the city's is that mirrored in z (its importer
// roots every glTF model under that flip). A person stands at the city's
// FigureRig root, turned by its yaw, scaled to its size, the flip kept: a
// frame of the figure rig (city) becomes the model frame whose x and y axes
// are the same lines ([RigPose._toModel]).

/// The bones, each after its parent.
abstract final class RigBones {
  static const _fingers = ['thumb', 'index', 'middle', 'ring', 'pinky'];
  static final List<String> names = [
    'pelvis', 'spine_01', 'spine_02', 'spine_03', 'neck_01', 'head', //
    for (final s in const ['l', 'r']) ...['clavicle_$s', 'upperarm_$s', 'lowerarm_$s', 'hand_$s'],
    for (final s in const ['l', 'r']) ...['thigh_$s', 'calf_$s', 'foot_$s', 'ball_$s'],
    for (final s in const ['l', 'r'])
      for (final f in _fingers)
        for (var i = 1; i <= 3; i++) '${f}_0${i}_$s',
  ];
  static final Map<String, int> index = {for (var i = 0; i < names.length; i++) names[i]: i};
  static const count = 52;
  static const pelvis = 0, spine1 = 1, spine2 = 2, spine3 = 3, neck = 4, head = 5;

  // Per side: 0 the skeleton's left ('_l', at +x: the city figure's side 1),
  // 1 its right.
  static int clavicle(int s) => 6 + 4 * s;
  static int upperarm(int s) => 7 + 4 * s;
  static int lowerarm(int s) => 8 + 4 * s;
  static int hand(int s) => 9 + 4 * s;
  static int thigh(int s) => 14 + 4 * s;
  static int calf(int s) => 15 + 4 * s;
  static int foot(int s) => 16 + 4 * s;
  static int ball(int s) => 17 + 4 * s;

  /// The first of a hand's fifteen finger bones (thumb, index, middle,
  /// ring, pinky; three each).
  static int fingers(int s) => 22 + 15 * s;
  static int middle1(int s) => fingers(s) + 6;

  /// The city figure's side for skeleton side [s] (its side 1 is at +x).
  static int figureSide(int s) => 1 - s;
}

// ── Quaternions and vectors in flat lists ──────────────────────────────────

/// Quaternions (x, y, z, w) four to a slot and vectors three to a slot, in
/// flat lists, worked on in place: posing a crowd allocates nothing a
/// frame.
abstract final class Q {
  static void set(Float64List q, int o, double x, double y, double z, double w) {
    q[o] = x;
    q[o + 1] = y;
    q[o + 2] = z;
    q[o + 3] = w;
  }

  static void copy(Float64List a, int ao, Float64List out, int oo) {
    out[oo] = a[ao];
    out[oo + 1] = a[ao + 1];
    out[oo + 2] = a[ao + 2];
    out[oo + 3] = a[ao + 3];
  }

  /// out = a · b.
  static void mul(Float64List a, int ao, Float64List b, int bo, Float64List out, int oo) {
    final ax = a[ao], ay = a[ao + 1], az = a[ao + 2], aw = a[ao + 3];
    final bx = b[bo], by = b[bo + 1], bz = b[bo + 2], bw = b[bo + 3];
    out[oo] = aw * bx + ax * bw + ay * bz - az * by;
    out[oo + 1] = aw * by - ax * bz + ay * bw + az * bx;
    out[oo + 2] = aw * bz + ax * by - ay * bx + az * bw;
    out[oo + 3] = aw * bw - ax * bx - ay * by - az * bz;
  }

  /// out = a⁻¹ · b (a a unit quaternion).
  static void mulInv(Float64List a, int ao, Float64List b, int bo, Float64List out, int oo) {
    final ax = a[ao], ay = a[ao + 1], az = a[ao + 2], aw = a[ao + 3];
    final bx = b[bo], by = b[bo + 1], bz = b[bo + 2], bw = b[bo + 3];
    out[oo] = aw * bx - ax * bw - ay * bz + az * by;
    out[oo + 1] = aw * by + ax * bz - ay * bw - az * bx;
    out[oo + 2] = aw * bz - ax * by + ay * bx - az * bw;
    out[oo + 3] = aw * bw + ax * bx + ay * by + az * bz;
  }

  /// Vector v (at vo) turned by q, into out (at oo; may be v).
  static void rotate(Float64List q, int qo, Float64List v, int vo, Float64List out, int oo) {
    final qx = q[qo], qy = q[qo + 1], qz = q[qo + 2], qw = q[qo + 3];
    final vx = v[vo], vy = v[vo + 1], vz = v[vo + 2];
    final tx = 2 * (qy * vz - qz * vy), ty = 2 * (qz * vx - qx * vz), tz = 2 * (qx * vy - qy * vx);
    out[oo] = vx + qw * tx + qy * tz - qz * ty;
    out[oo + 1] = vy + qw * ty + qz * tx - qx * tz;
    out[oo + 2] = vz + qw * tz + qx * ty - qy * tx;
  }

  /// out = a, [t] (0..1) of the way to b (the short way), unit.
  static void nlerp(Float64List a, int ao, Float64List b, int bo, double t, Float64List out, int oo) {
    if (t <= 0) return copy(a, ao, out, oo);
    if (t >= 1) return copy(b, bo, out, oo);
    final d = a[ao] * b[bo] + a[ao + 1] * b[bo + 1] + a[ao + 2] * b[bo + 2] + a[ao + 3] * b[bo + 3];
    final u = 1 - t, v = d < 0 ? -t : t;
    final x = a[ao] * u + b[bo] * v, y = a[ao + 1] * u + b[bo + 1] * v, z = a[ao + 2] * u + b[bo + 2] * v, w = a[ao + 3] * u + b[bo + 3] * v;
    final n = 1 / math.sqrt(x * x + y * y + z * z + w * w);
    set(out, oo, x * n, y * n, z * n, w * n);
  }

  static void normalize(Float64List q, int o) {
    final n = math.sqrt(q[o] * q[o] + q[o + 1] * q[o + 1] + q[o + 2] * q[o + 2] + q[o + 3] * q[o + 3]);
    if (n < 1e-12) return set(q, o, 0, 0, 0, 1);
    final k = 1 / n;
    q[o] *= k;
    q[o + 1] *= k;
    q[o + 2] *= k;
    q[o + 3] *= k;
  }

  /// The rotation whose matrix has columns x, y, z (orthonormal).
  static void fromBasis(double xx, double xy, double xz, double yx, double yy, double yz, double zx, double zy, double zz, Float64List out, int o) {
    // (Rows r, columns c: m_rc; column x is (m00, m10, m20).)
    final m00 = xx, m10 = xy, m20 = xz, m01 = yx, m11 = yy, m21 = yz, m02 = zx, m12 = zy, m22 = zz;
    final tr = m00 + m11 + m22;
    if (tr > 0) {
      final s = 0.5 / math.sqrt(tr + 1);
      set(out, o, (m21 - m12) * s, (m02 - m20) * s, (m10 - m01) * s, 0.25 / s);
    } else if (m00 > m11 && m00 > m22) {
      final s = 2 * math.sqrt(1 + m00 - m11 - m22);
      set(out, o, 0.25 * s, (m01 + m10) / s, (m02 + m20) / s, (m21 - m12) / s);
    } else if (m11 > m22) {
      final s = 2 * math.sqrt(1 + m11 - m00 - m22);
      set(out, o, (m01 + m10) / s, 0.25 * s, (m12 + m21) / s, (m02 - m20) / s);
    } else {
      final s = 2 * math.sqrt(1 + m22 - m00 - m11);
      set(out, o, (m02 + m20) / s, (m12 + m21) / s, 0.25 * s, (m10 - m01) / s);
    }
    normalize(out, o);
  }

  /// The rotation of matrix [m] (no scale).
  static void fromMatrix(vm.Matrix4 m, Float64List out, int o) {
    final s = m.storage;
    fromBasis(s[0], s[1], s[2], s[4], s[5], s[6], s[8], s[9], s[10], out, o);
  }

  /// out = the shortest turn taking direction (ax, ay, az) to (bx, by, bz)
  /// (any lengths), times q (at qo): q swung to point the other way.
  static void swing(double ax, double ay, double az, double bx, double by, double bz, Float64List q, int qo, Float64List out, int oo) {
    final la = math.sqrt(ax * ax + ay * ay + az * az), lb = math.sqrt(bx * bx + by * by + bz * bz);
    if (la < 1e-9 || lb < 1e-9) return copy(q, qo, out, oo);
    ax /= la;
    ay /= la;
    az /= la;
    bx /= lb;
    by /= lb;
    bz /= lb;
    final d = ax * bx + ay * by + az * bz;
    double x, y, z, w;
    if (d < -0.999999) {
      // Opposite: half a turn about anything square to a.
      x = ay.abs() < 0.9 ? 0.0 : 1.0;
      y = ay.abs() < 0.9 ? 1.0 : 0.0;
      z = 0;
      // (a × that, normalised)
      final cx = ay * z - az * y, cy = az * x - ax * z, cz = ax * y - ay * x, cl = math.sqrt(cx * cx + cy * cy + cz * cz);
      x = cx / cl;
      y = cy / cl;
      z = cz / cl;
      w = 0;
    } else {
      x = ay * bz - az * by;
      y = az * bx - ax * bz;
      z = ax * by - ay * bx;
      w = 1 + d;
      final n = 1 / math.sqrt(x * x + y * y + z * z + w * w);
      x *= n;
      y *= n;
      z *= n;
      w *= n;
    }
    final qx = q[qo], qy = q[qo + 1], qz = q[qo + 2], qw = q[qo + 3];
    out[oo] = w * qx + x * qw + y * qz - z * qy;
    out[oo + 1] = w * qy - x * qz + y * qw + z * qx;
    out[oo + 2] = w * qz + x * qy - y * qx + z * qw;
    out[oo + 3] = w * qw - x * qx - y * qy - z * qz;
  }
}

// ── Motion clips ────────────────────────────────────────────────────────────

/// A motion-capture clip on the skeleton (tool/blender/motions.py: each
/// bone's turn a frame, and the pelvis's place), sampled at even frames,
/// looping.
class RigClip {
  RigClip._(this.name, this.frames, this.fps, this.rot, this.pelvis);

  final String name;
  final int frames;
  final double fps;

  /// Each frame's bones' local turns (frames × 52 × 4) and the pelvis's
  /// place (in its parent's frame; frames × 3), on the body the clips were
  /// made on.
  final Float32List rot, pelvis;

  /// How long a loop is (the last frame is the first again).
  double get period => (frames - 1) / fps;

  /// The pelvis's place moved by this (in its parent's frame, x and y: the
  /// ground plane) puts the clip's ankles, on average, under the person.
  double centreX = 0, centreY = 0;

  /// The clips' body's hips' height (in the root bone's frame).
  static double hips = 0.9111;

  /// When (seconds into the loop) the skeleton's right leg (the city
  /// figure's side 0) is furthest forward: a walk's heel strike.
  double strike = 0;

  /// The local turns at [t] (looped) into [lr], and the pelvis's place
  /// into [pelvisT], for a body whose hips are [hips] high (its pelvis's
  /// travel scaled to them).
  void sample(double t, Float64List lr, Float64List pelvisT, double hips) {
    hips /= RigClip.hips;
    final u = (t / period) % 1.0 * (frames - 1);
    final f0 = u.floor().clamp(0, frames - 2), f = u - f0;
    final a = f0 * RigBones.count * 4, b = a + RigBones.count * 4;
    for (var i = 0; i < RigBones.count; i++) {
      final o = i * 4;
      var x0 = rot[a + o], y0 = rot[a + o + 1], z0 = rot[a + o + 2], w0 = rot[a + o + 3];
      var x1 = rot[b + o], y1 = rot[b + o + 1], z1 = rot[b + o + 2], w1 = rot[b + o + 3];
      if (x0 * x1 + y0 * y1 + z0 * z1 + w0 * w1 < 0) {
        x1 = -x1;
        y1 = -y1;
        z1 = -z1;
        w1 = -w1;
      }
      final x = x0 + (x1 - x0) * f, y = y0 + (y1 - y0) * f, z = z0 + (z1 - z0) * f, w = w0 + (w1 - w0) * f;
      final n = 1 / math.sqrt(x * x + y * y + z * z + w * w);
      Q.set(lr, o, x * n, y * n, z * n, w * n);
    }
    final pa = f0 * 3, pb = pa + 3;
    pelvisT[0] = (pelvis[pa] + (pelvis[pb] - pelvis[pa]) * f - centreX) * hips;
    pelvisT[1] = (pelvis[pa + 1] + (pelvis[pb + 1] - pelvis[pa + 1]) * f - centreY) * hips;
    pelvisT[2] = (pelvis[pa + 2] + (pelvis[pb + 2] - pelvis[pa + 2]) * f) * hips;
  }

  /// Every clip in motions.glb (one animation each; all keys on one even
  /// grid at [fps], a constant channel two keys).
  static Map<String, RigClip> parse(Uint8List glb, double fps) {
    final data = ByteData.sublistView(glb);
    final jlen = data.getUint32(12, Endian.little);
    final g = json.decode(utf8.decode(glb.sublist(20, 20 + jlen))) as Map<String, dynamic>;
    final binAt = 20 + jlen + 8;
    final nodes = (g['nodes'] as List).cast<Map<String, dynamic>>();
    final accessors = (g['accessors'] as List).cast<Map<String, dynamic>>();
    final views = (g['bufferViews'] as List).cast<Map<String, dynamic>>();
    Float32List floats(int i) {
      final a = accessors[i], v = views[a['bufferView'] as int];
      final n = a['count'] as int, comps = const {'SCALAR': 1, 'VEC3': 3, 'VEC4': 4}[a['type']]!;
      final start = binAt + (v['byteOffset'] as int? ?? 0) + (a['byteOffset'] as int? ?? 0);
      return Float32List.fromList(Float32List.sublistView(glb, start, start + 4 * n * comps));
    }

    final out = <String, RigClip>{};
    for (final a in (g['animations'] as List).cast<Map<String, dynamic>>()) {
      final samplers = (a['samplers'] as List).cast<Map<String, dynamic>>();
      final channels = (a['channels'] as List).cast<Map<String, dynamic>>();
      var frames = 2;
      for (final c in channels) {
        frames = math.max(frames, accessors[samplers[c['sampler'] as int]['input'] as int]['count'] as int);
      }
      final rot = Float32List(frames * RigBones.count * 4), pelvis = Float32List(frames * 3);
      // (Bones no channel moves: still.)
      for (var f = 0; f < frames; f++) {
        for (var i = 0; i < RigBones.count; i++) {
          rot[(f * RigBones.count + i) * 4 + 3] = 1;
        }
      }
      for (final c in channels) {
        final target = c['target'] as Map<String, dynamic>;
        final bone = RigBones.index[nodes[target['node'] as int]['name']];
        if (bone == null) continue;
        final s = samplers[c['sampler'] as int];
        final values = floats(s['output'] as int);
        final keys = accessors[s['input'] as int]['count'] as int;
        final rotation = target['path'] == 'rotation';
        if (!rotation && (target['path'] != 'translation' || bone != RigBones.pelvis)) continue;
        final w = rotation ? 4 : 3;
        for (var f = 0; f < frames; f++) {
          final k = keys == frames ? f : 0;
          for (var j = 0; j < w; j++) {
            if (rotation) {
              rot[(f * RigBones.count + bone) * 4 + j] = values[k * 4 + j];
            } else {
              pelvis[f * 3 + j] = values[k * 3 + j];
            }
          }
        }
      }
      out[a['name'] as String] = RigClip._(a['name'] as String, frames, fps, rot, pelvis);
    }
    return out;
  }
}

// ── A body ──────────────────────────────────────────────────────────────────

/// One body's skeleton at rest (from its glTF), measured, and how each bone
/// sits against the city figure's parts ([cal]).
class RigBody {
  RigBody(this.name, this.template) {
    final n = RigBones.count;
    nodes = [
      for (final b in RigBones.names) template.getChildByName(b) ?? (throw StateError('$name: no bone $b')),
    ];
    parent = [for (final b in nodes) nodes.indexOf(b.parent!)];
    final t = vm.Vector3.zero(), s = vm.Vector3.zero(), r = vm.Quaternion.identity();
    for (var i = 0; i < n; i++) {
      nodes[i].localTransform.decompose(t, r, s);
      restLT[i * 3] = t.x;
      restLT[i * 3 + 1] = t.y;
      restLT[i * 3 + 2] = t.z;
      Q.set(restLR, i * 4, r.x, r.y, r.z, r.w);
      Q.normalize(restLR, i * 4);
    }
    // The pelvis's parent (the rig's root bone), in model space: everything
    // between it and the import's root.
    final root = _model(nodes[RigBones.pelvis].parent!);
    root.decompose(t, r, s);
    rootT.setAll(0, [t.x, t.y, t.z]);
    Q.set(rootR, 0, r.x, r.y, r.z, r.w);
    Q.normalize(rootR, 0);
    // The rest pose in model space.
    for (var i = 0; i < n; i++) {
      final p = parent[i];
      final pr = p < 0 ? rootR : restMR, po = p < 0 ? 0 : p * 4;
      final pp = p < 0 ? rootT : restMP, ppo = p < 0 ? 0 : p * 3;
      Q.mul(pr, po, restLR, i * 4, restMR, i * 4);
      Q.rotate(pr, po, restLT, i * 3, restMP, i * 3);
      for (var k = 0; k < 3; k++) {
        restMP[i * 3 + k] += pp[ppo + k];
      }
    }
    _measure();
    _calibrate();
  }

  final String name;
  final Node template;
  late final List<Node> nodes;
  late final List<int> parent;

  /// Rest: each bone's local place and turn, and its place and turn in
  /// model space; the root bone's (the pelvis's parent's).
  final restLT = Float64List(RigBones.count * 3), restLR = Float64List(RigBones.count * 4);
  final restMP = Float64List(RigBones.count * 3), restMR = Float64List(RigBones.count * 4);
  final rootT = Float64List(3), rootR = Float64List(4);

  /// The bone's turn against its city part's: bone = part · cal (model
  /// space). The trunk's parts stand upright facing the way the person
  /// does; a leg's hangs as the figure rig hangs one (rolled, then
  /// pitched), the arm's along it with x the elbow's hinge.
  final cal = Float64List(RigBones.count * 4);

  /// Its size as the city's figures have it (1: hips 0.91 m up, 1.72 m
  /// tall), the head's (by the neck's height), how far the ankle is above
  /// the soles, and where the middle of the palm is in the hand's frame.
  late final double size, headSize, ankleOverSole;
  final palm = Float64List(6);

  /// The pelvis's place against the hip joints' midpoint, in the pelvis's
  /// frame.
  final pelvisOff = Float64List(3);

  /// The hips' height in the root bone's frame (to scale the clips' by).
  double get hips => restLT[RigBones.pelvis * 3 + 2];

  /// Every bone's model turn [mr] and place [mp] from local turns [lr] and
  /// the pelvis's local place [pelvisT].
  void fk(Float64List lr, Float64List pelvisT, Float64List mr, Float64List mp) {
    Q.mul(rootR, 0, lr, 0, mr, 0);
    Q.rotate(rootR, 0, pelvisT, 0, mp, 0);
    for (var c = 0; c < 3; c++) {
      mp[c] += rootT[c];
    }
    for (var i = 1; i < RigBones.count; i++) {
      final p = parent[i];
      Q.mul(mr, p * 4, lr, i * 4, mr, i * 4);
      Q.rotate(mr, p * 4, restLT, i * 3, mp, i * 3);
      for (var c = 0; c < 3; c++) {
        mp[i * 3 + c] += mp[p * 3 + c];
      }
    }
  }

  /// Fits [clip] to the people: its ankles centred under the person on
  /// average, and when its right leg strikes (this the clips' body).
  void fit(RigClip clip, {bool centre = true}) {
    final lr = Float64List(RigBones.count * 4), t = Float64List(3), mr = Float64List(RigBones.count * 4), mp = Float64List(RigBones.count * 3);
    var ax = 0.0, az = 0.0, best = -double.infinity;
    final n = clip.frames - 1;
    for (var f = 0; f < n; f++) {
      final at = f / clip.fps;
      clip.sample(at, lr, t, RigClip.hips);
      fk(lr, t, mr, mp);
      final l = RigBones.foot(0) * 3, r = RigBones.foot(1) * 3;
      ax += 0.5 * (mp[l] + mp[r]);
      az += 0.5 * (mp[l + 2] + mp[r + 2]);
      final ahead = mp[RigBones.calf(1) * 3 + 2] - mp[RigBones.thigh(1) * 3 + 2];
      if (ahead > best) {
        best = ahead;
        clip.strike = at;
      }
    }
    if (!centre) return;
    // (Model x, z into the root bone's frame: turned back by its turn.)
    final d = Float64List.fromList([ax / n, 0, az / n]), out = Float64List(3);
    Q.rotate(Float64List.fromList([-rootR[0], -rootR[1], -rootR[2], rootR[3]]), 0, d, 0, out, 0);
    clip
      ..centreX = out[0]
      ..centreY = out[1];
  }

  vm.Matrix4 _model(Node n) {
    final chain = <Node>[];
    for (Node? k = n; k != null && k != template; k = k.parent) {
      chain.add(k);
    }
    final m = vm.Matrix4.identity();
    for (final k in chain.reversed) {
      m.multiply(k.localTransform);
    }
    return m;
  }

  double _y(int bone) => restMP[bone * 3 + 1];

  void _measure() {
    size = _y(RigBones.thigh(0)) / FigureRig.hip;
    headSize = _y(RigBones.neck) / 1.465;
    var sole = double.infinity;
    for (final m in template.meshNodes) {
      if (!m.name.contains('shoe') && !m.name.contains('boot')) continue;
      final at = _model(m), p = m.extractMeshData().positions;
      final v = vm.Vector3.zero();
      for (var i = 0; i < p.length; i += 3) {
        v.setValues(p[i], p[i + 1], p[i + 2]);
        at.transform3(v);
        if (v.y < sole) sole = v.y;
      }
    }
    if (!sole.isFinite) sole = 0;
    ankleOverSole = _y(RigBones.foot(0)) - sole;
    for (var s = 0; s < 2; s++) {
      final m = RigBones.middle1(s);
      for (var k = 0; k < 3; k++) {
        palm[s * 3 + k] = 0.55 * restLT[m * 3 + k];
      }
    }
    // The pelvis against the hip joints.
    final l = RigBones.thigh(0) * 3, r = RigBones.thigh(1) * 3, p = RigBones.pelvis * 3;
    final d = Float64List.fromList([
      for (var k = 0; k < 3; k++) restMP[p + k] - 0.5 * (restMP[l + k] + restMP[r + k]),
    ]);
    // (Into the pelvis's frame: turned back by its rest turn.)
    final inv = Float64List.fromList([-restMR[0], -restMR[1], -restMR[2], restMR[3]]);
    Q.rotate(inv, 0, d, 0, pelvisOff, 0);
  }

  void _calibrate() {
    // Default: the part is the trunk's, upright (identity).
    Q.copy(restMR, 0, cal, 0);
    for (var i = 0; i < RigBones.count; i++) {
      Q.copy(restMR, i * 4, cal, i * 4);
    }
    final g = Float64List(4), inv = Float64List(4);
    void against(int bone) {
      // cal = g⁻¹ · rest
      Q.set(inv, 0, -g[0], -g[1], -g[2], g[3]);
      Q.mul(inv, 0, restMR, bone * 4, cal, bone * 4);
    }

    double dx(int a, int b, int k) => restMP[b * 3 + k] - restMP[a * 3 + k];
    for (var s = 0; s < 2; s++) {
      // Legs: the figure's leg frame (roll, then pitch) pointing where the
      // bone does. (City directions: z mirrored.)
      for (final (a, b) in [(RigBones.thigh(s), RigBones.calf(s)), (RigBones.calf(s), RigBones.foot(s))]) {
        var x = dx(a, b, 0), y = dx(a, b, 1), z = -dx(a, b, 2);
        final l = math.sqrt(x * x + y * y + z * z);
        x /= l;
        y /= l;
        z /= l;
        // −y of rotZ(roll)·rotX(pitch) is (ca·sr, −ca·cr, −sa).
        final sa = -z, ca = math.sqrt(math.max(1e-9, 1 - sa * sa)), sr = x / ca, cr = -y / ca;
        _cityFrame(cr, sr, 0, -ca * sr, ca * cr, sa, sa * sr, -sa * cr, ca, g);
        against(a);
      }
      // Arms: along the bone, x the elbow's hinge (the figure rig bends an
      // elbow by turning about its x: forearm = turn(x, bend) · upper arm).
      final u = RigBones.upperarm(s), f = RigBones.lowerarm(s), h = RigBones.hand(s);
      double ux = dx(u, f, 0), uy = dx(u, f, 1), uz = -dx(u, f, 2);
      double fx = dx(f, h, 0), fy = dx(f, h, 1), fz = -dx(f, h, 2);
      var hx = uy * fz - uz * fy, hy = uz * fx - ux * fz, hz = ux * fy - uy * fx;
      final hl = math.sqrt(hx * hx + hy * hy + hz * hz);
      hx /= hl;
      hy /= hl;
      hz /= hl;
      for (final (bone, ax, ay, az) in [(u, ux, uy, uz), (f, fx, fy, fz), (h, fx, fy, fz)]) {
        final l = math.sqrt(ax * ax + ay * ay + az * az);
        // y back up the limb; x the hinge, made square to it; z = x × y.
        final yx = -ax / l, yy = -ay / l, yz = -az / l;
        final d = hx * yx + hy * yy + hz * yz;
        var xx = hx - d * yx, xy = hy - d * yy, xz = hz - d * yz;
        final xl = math.sqrt(xx * xx + xy * xy + xz * xz);
        xx /= xl;
        xy /= xl;
        xz /= xl;
        _cityFrame(xx, xy, xz, yx, yy, yz, xy * yz - xz * yy, xz * yx - xx * yz, xx * yy - xy * yx, g);
        against(bone);
      }
    }
  }

  /// The model-space turn [out] of a frame of the city's with columns x, y,
  /// z (the same x and y lines; the flip conjugates it).
  static void _cityFrame(double xx, double xy, double xz, double yx, double yy, double yz, double zx, double zy, double zz, Float64List out) {
    Q.fromBasis(xx, xy, xz, yx, yy, yz, zx, zy, zz, out, 0);
    out[0] = -out[0];
    out[1] = -out[1];
  }
}

// ── Posing one ──────────────────────────────────────────────────────────────

/// One person's skeleton posed: as the city's figure rig has them (each
/// bone turned as its part is, the hands and feet put where the rig's are,
/// whatever this body's lengths), with a motion-capture clip layered in
/// where the scene leaves them to it (a walk's swing, a stand).
class RigPose {
  RigPose(this.body) {
    for (var i = 0; i < RigBones.count; i++) {
      Q.copy(body.restLR, i * 4, lr, i * 4);
    }
  }

  final RigBody body;

  /// Each bone's local turn, and its turn and place in model space; the
  /// pelvis's local place.
  final lr = Float64List(RigBones.count * 4), mr = Float64List(RigBones.count * 4), mp = Float64List(RigBones.count * 3);
  final pelvisT = Float64List(3);

  /// Where the person stands (the city's), facing, and how much bigger
  /// than the body they are.
  final root = Float64List(3);
  double yaw = 0, k = 1;

  /// The clip layered in at [time], faded in from [from] at [fromTime]
  /// ([fade] 0..1 of the way); how much of the legs (and the hips), the
  /// spine, and each arm (and its hand) take it.
  RigClip? clip, from;
  double time = 0, fromTime = 0, fade = 1;
  double legs = 0, spine = 0;
  final arms = Float64List(2);

  /// Each hand's fingers, when the arm is the rig's: from easy (0) to
  /// gripping (1); [relaxed] and [gripping] give them.
  final grip = Float64List(2);
  static Float64List? relaxed, gripping;

  // Scratch.
  final _g = Float64List(4 * 3), _q = Float64List(4), _v = Float64List(3), _w = Float64List(3), _t = Float64List(3);
  final _clip = Float64List(RigBones.count * 4), _clipT = Float64List(3), _from = Float64List(RigBones.count * 4), _fromT = Float64List(3);
  final _arm = Float64List(2 * 3 * 4), _targets = Float64List(2 * 6);
  final _yawInv = Float64List(4);

  /// Poses it for [r] (just solved for a figure [size] tall).
  void solve(FigureRig r, double size) {
    final b = body;
    final rs = r.root.storage;
    root[0] = rs[12];
    root[1] = rs[13];
    root[2] = rs[14];
    yaw = r.joints[FigureRig.jYaw];
    k = size / b.size;
    Q.set(_yawInv, 0, 0, math.sin(-yaw / 2), 0, math.cos(-yaw / 2));

    // The trunk: the pelvis's and the chest's turns, the spine's between;
    // the neck between the chest's and the head's.
    _part(r.pelvis, _g, 0);
    _part(r.chest, _g, 4);
    _part(r.head, _g, 8);
    _cal(_g, 0, RigBones.pelvis);
    Q.nlerp(_g, 0, _g, 4, 0.3, _q, 0);
    _cal(_q, 0, RigBones.spine1);
    Q.nlerp(_g, 0, _g, 4, 0.65, _q, 0);
    _cal(_q, 0, RigBones.spine2);
    _cal(_g, 4, RigBones.spine3);
    Q.nlerp(_g, 4, _g, 8, 0.5, _q, 0);
    _cal(_q, 0, RigBones.neck);
    _cal(_g, 8, RigBones.head);
    // The pelvis where the rig's hip joints are.
    final ps = r.pelvis.storage;
    _toModel(ps[12], ps[13], ps[14], mp, RigBones.pelvis * 3);
    Q.rotate(mr, RigBones.pelvis * 4, b.pelvisOff, 0, _v, 0);
    for (var c = 0; c < 3; c++) {
      mp[RigBones.pelvis * 3 + c] += _v[c];
    }
    for (final i in const [RigBones.spine1, RigBones.spine2, RigBones.spine3, RigBones.neck, RigBones.head]) {
      _place(i);
    }
    for (var s = 0; s < 2; s++) {
      final fs = RigBones.figureSide(s);
      // The clavicle as it rests on the chest.
      final c = RigBones.clavicle(s);
      Q.mul(mr, RigBones.spine3 * 4, b.restLR, c * 4, mr, c * 4);
      _place(c);
      // The arm's bones as the rig's (reached later, from where the
      // shoulder ends up), and where its hand and elbow are.
      _part(r.upper[fs], _q, 0);
      Q.mul(_q, 0, b.cal, RigBones.upperarm(s) * 4, _arm, s * 12);
      _part(r.lower[fs], _q, 0);
      Q.mul(_q, 0, b.cal, RigBones.lowerarm(s) * 4, _arm, s * 12 + 4);
      _part(r.hand[fs], _q, 0);
      Q.mul(_q, 0, b.cal, RigBones.hand(s) * 4, _arm, s * 12 + 8);
      final palm = r.palms[fs], elbow = r.lower[fs].storage;
      _toModel(palm.x, palm.y, palm.z, _targets, s * 6);
      _toModel(elbow[12], elbow[13], elbow[14], _targets, s * 6 + 3);

      // The leg: turned as the rig's, then reaching its ankle (the soles
      // on the ground, this body's being thicker or thinner than the
      // rig's), the knee towards the rig's.
      final th = RigBones.thigh(s), ca = RigBones.calf(s), fo = RigBones.foot(s), ba = RigBones.ball(s);
      _part(r.thighs[fs], _q, 0);
      _cal(_q, 0, th);
      _part(r.shins[fs], _q, 0);
      _cal(_q, 0, ca);
      _part(r.feet[fs], _q, 0);
      _cal(_q, 0, fo);
      Q.mul(mr, fo * 4, b.restLR, ba * 4, mr, ba * 4);
      _place(th);
      final ankle = r.feet[fs].storage, knee = r.shins[fs].storage;
      _toModel(ankle[12], ankle[13], ankle[14], _t, 0);
      // (The foot's up, in model space: the rig's foot's y.)
      _v[0] = 0;
      _v[1] = 1;
      _v[2] = 0;
      Q.rotate(_q, 0, _v, 0, _v, 0);
      final lift = b.ankleOverSole - 0.08 * b.size;
      _toModel(knee[12], knee[13], knee[14], _w, 0);
      _reach(th, ca, fo, _t[0] + _v[0] * lift, _t[1] + _v[1] * lift, _t[2] + _v[2] * lift, _w[0], _w[1], _w[2]);
      _place(ba);
    }

    // Into local turns; the clip layered in.
    _toLocal(RigBones.pelvis);
    for (var i = 1; i < RigBones.fingers(0); i++) {
      if (i < RigBones.clavicle(0) || i >= RigBones.thigh(0)) _toLocal(i);
    }
    final c = clip;
    if (c != null && (legs > 0 || spine > 0 || arms[0] > 0 || arms[1] > 0)) {
      final hips = b.hips;
      c.sample(time, _clip, _clipT, hips);
      final f = from;
      if (f != null && fade < 1) {
        f.sample(fromTime, _from, _fromT, hips);
        for (var i = 0; i < RigBones.count; i++) {
          Q.nlerp(_from, i * 4, _clip, i * 4, fade, _clip, i * 4);
        }
        for (var j = 0; j < 3; j++) {
          _clipT[j] = _fromT[j] + (_clipT[j] - _fromT[j]) * fade;
        }
      }
      if (legs > 0) {
        for (var j = 0; j < 3; j++) {
          pelvisT[j] += (_clipT[j] - pelvisT[j]) * legs;
        }
        Q.nlerp(lr, 0, _clip, 0, legs, lr, 0);
        for (var i = RigBones.thigh(0); i < RigBones.fingers(0); i++) {
          Q.nlerp(lr, i * 4, _clip, i * 4, legs, lr, i * 4);
        }
      }
      if (spine > 0) {
        for (final i in const [RigBones.spine1, RigBones.spine2, RigBones.spine3]) {
          Q.nlerp(lr, i * 4, _clip, i * 4, spine, lr, i * 4);
        }
      }
    }
    // The trunk and the legs from the local turns (the clavicles as they
    // rest, until an arm takes the clip's).
    Q.copy(b.restLR, RigBones.clavicle(0) * 4, lr, RigBones.clavicle(0) * 4);
    Q.copy(b.restLR, RigBones.clavicle(1) * 4, lr, RigBones.clavicle(1) * 4);
    _fromLocal(RigBones.pelvis);
    for (var i = 1; i < RigBones.fingers(0); i++) {
      if (i < RigBones.upperarm(0) || (i >= RigBones.thigh(0)) || i == RigBones.clavicle(1)) _fromLocal(i);
    }

    // The arms: the rig's, reaching its hands from where the shoulders now
    // are, and the clip's, mixed.
    for (var s = 0; s < 2; s++) {
      final cl = RigBones.clavicle(s), u = RigBones.upperarm(s), l = RigBones.lowerarm(s), h = RigBones.hand(s);
      final w = c == null ? 0.0 : arms[s];
      if (w > 0) {
        Q.nlerp(b.restLR, cl * 4, _clip, cl * 4, w, lr, cl * 4);
        _fromLocal(cl);
      }
      _place(u);
      if (w < 1) {
        Q.copy(_arm, s * 12, mr, u * 4);
        Q.copy(_arm, s * 12 + 4, mr, l * 4);
        Q.copy(_arm, s * 12 + 8, mr, h * 4);
        // The wrist where the palm's middle will be on the rig's palm.
        Q.rotate(mr, h * 4, b.palm, s * 3, _v, 0);
        final o = s * 6;
        _reach(u, l, h, _targets[o] - _v[0], _targets[o + 1] - _v[1], _targets[o + 2] - _v[2], _targets[o + 3], _targets[o + 4], _targets[o + 5]);
        _toLocal(u);
        _toLocal(l);
        _toLocal(h);
      }
      if (w > 0) {
        for (final i in [u, l, h]) {
          if (w >= 1) {
            Q.copy(_clip, i * 4, lr, i * 4);
          } else {
            Q.nlerp(lr, i * 4, _clip, i * 4, w, lr, i * 4);
          }
        }
      }
      _fromLocal(u);
      _fromLocal(l);
      _fromLocal(h);
      // The fingers: easy or gripping, or the clip's.
      final f0 = RigBones.fingers(s), easy = relaxed, hold = gripping;
      for (var i = f0; i < f0 + 15; i++) {
        if (easy != null && hold != null) {
          Q.nlerp(easy, i * 4, hold, i * 4, grip[s], lr, i * 4);
        } else {
          Q.copy(b.restLR, i * 4, lr, i * 4);
        }
        if (w > 0) Q.nlerp(lr, i * 4, _clip, i * 4, w, lr, i * 4);
        _fromLocal(i);
      }
    }
  }

  /// Writes the local turns and places into [mats] (one per bone, each a
  /// node's local transform), and the person's place into [rootMat].
  void write(List<vm.Matrix4> mats, vm.Matrix4 rootMat) {
    final b = body;
    for (var i = 0; i < RigBones.count; i++) {
      final t = i == RigBones.pelvis ? pelvisT : b.restLT, o = i == RigBones.pelvis ? 0 : i * 3;
      _setTR(mats[i].storage, lr, i * 4, t[o], t[o + 1], t[o + 2]);
    }
    // At the root, turned, scaled, z flipped (the import's own flip).
    final c = math.cos(yaw), s = math.sin(yaw), m = rootMat.storage;
    m[0] = c * k;
    m[1] = 0;
    m[2] = -s * k;
    m[3] = 0;
    m[4] = 0;
    m[5] = k;
    m[6] = 0;
    m[7] = 0;
    m[8] = -s * k;
    m[9] = 0;
    m[10] = -c * k;
    m[11] = 0;
    m[12] = root[0];
    m[13] = root[1];
    m[14] = root[2];
    m[15] = 1;
  }

  /// A model-space point at the city's [out] (scaled, turned, flipped back).
  void toCity(Float64List p, int o, vm.Vector3 out) {
    final x = p[o] * k, y = p[o + 1] * k, z = -p[o + 2] * k;
    final c = math.cos(yaw), s = math.sin(yaw);
    out.setValues(root[0] + c * x + s * z, root[1] + y, root[2] - s * x + c * z);
  }

  // ── Steps ─────────────────────────────────────────────────────────────

  /// A figure-rig part's turn [m] (the city's) as a model-space turn.
  void _part(vm.Matrix4 m, Float64List out, int o) {
    Q.fromMatrix(m, _w4, 0);
    Q.mul(_yawInv, 0, _w4, 0, out, o);
    out[o] = -out[o];
    out[o + 1] = -out[o + 1];
  }

  final _w4 = Float64List(4);

  /// Bone [i]'s model turn: part [g] (at [o]) · its calibration.
  void _cal(Float64List g, int o, int i) => Q.mul(g, o, body.cal, i * 4, mr, i * 4);

  /// The city's point (x, y, z) in model space, into out (at o).
  void _toModel(double x, double y, double z, Float64List out, int o) {
    final dx = x - root[0], dy = y - root[1], dz = z - root[2];
    final c = math.cos(yaw), s = math.sin(yaw);
    // Turned back by the yaw, z flipped, unscaled.
    out[o] = (c * dx - s * dz) / k;
    out[o + 1] = dy / k;
    out[o + 2] = -(s * dx + c * dz) / k;
  }

  /// Bone [i]'s model place from its parent's turn and place.
  void _place(int i) {
    final p = body.parent[i];
    Q.rotate(mr, p * 4, body.restLT, i * 3, mp, i * 3);
    for (var c = 0; c < 3; c++) {
      mp[i * 3 + c] += mp[p * 3 + c];
    }
  }

  /// Bone [i]'s local turn from its and its parent's model turns (the
  /// pelvis: its place too).
  void _toLocal(int i) {
    final b = body;
    if (i == RigBones.pelvis) {
      Q.mulInv(b.rootR, 0, mr, 0, lr, 0);
      for (var c = 0; c < 3; c++) {
        _v[c] = mp[c] - b.rootT[c];
      }
      Q.set(_q, 0, -b.rootR[0], -b.rootR[1], -b.rootR[2], b.rootR[3]);
      Q.rotate(_q, 0, _v, 0, pelvisT, 0);
      return;
    }
    Q.mulInv(mr, b.parent[i] * 4, mr, i * 4, lr, i * 4);
  }

  /// Bone [i]'s model turn and place from its local turn.
  void _fromLocal(int i) {
    final b = body;
    if (i == RigBones.pelvis) {
      Q.mul(b.rootR, 0, lr, 0, mr, 0);
      Q.rotate(b.rootR, 0, pelvisT, 0, mp, 0);
      for (var c = 0; c < 3; c++) {
        mp[c] += b.rootT[c];
      }
      return;
    }
    Q.mul(mr, b.parent[i] * 4, lr, i * 4, mr, i * 4);
    _place(i);
  }

  /// Bones [a] and [b] (a limb, a placed and both turned) swung so that
  /// [c]'s head is at (tx, ty, tz), or as near as the limb reaches, the
  /// middle joint towards (px, py, pz).
  void _reach(int a, int b, int c, double tx, double ty, double tz, double px, double py, double pz) {
    final lt = body.restLT;
    final l1 = math.sqrt(lt[b * 3] * lt[b * 3] + lt[b * 3 + 1] * lt[b * 3 + 1] + lt[b * 3 + 2] * lt[b * 3 + 2]);
    final l2 = math.sqrt(lt[c * 3] * lt[c * 3] + lt[c * 3 + 1] * lt[c * 3 + 1] + lt[c * 3 + 2] * lt[c * 3 + 2]);
    final sx = mp[a * 3], sy = mp[a * 3 + 1], sz = mp[a * 3 + 2];
    var dx = tx - sx, dy = ty - sy, dz = tz - sz;
    var d = math.sqrt(dx * dx + dy * dy + dz * dz);
    if (d < 1e-6) return;
    dx /= d;
    dy /= d;
    dz /= d;
    d = d.clamp((l1 - l2).abs() + 1e-4, l1 + l2 - 1e-4);
    final along = (l1 * l1 - l2 * l2 + d * d) / (2 * d), off = math.sqrt(math.max(0.0, l1 * l1 - along * along));
    // The pole, square to the reach.
    var nx = px - sx, ny = py - sy, nz = pz - sz;
    final pd = nx * dx + ny * dy + nz * dz;
    nx -= pd * dx;
    ny -= pd * dy;
    nz -= pd * dz;
    var nl = math.sqrt(nx * nx + ny * ny + nz * nz);
    if (nl < 1e-5) {
      // (The pole on the line: where the middle joint is now.)
      Q.rotate(mr, a * 4, lt, b * 3, _w, 0);
      nx = _w[0];
      ny = _w[1];
      nz = _w[2];
      final wd = nx * dx + ny * dy + nz * dz;
      nx -= wd * dx;
      ny -= wd * dy;
      nz -= wd * dz;
      nl = math.max(1e-6, math.sqrt(nx * nx + ny * ny + nz * nz));
    }
    nx /= nl;
    ny /= nl;
    nz /= nl;
    final ex = dx * along + nx * off, ey = dy * along + ny * off, ez = dz * along + nz * off;
    Q.rotate(mr, a * 4, lt, b * 3, _w, 0);
    Q.swing(_w[0], _w[1], _w[2], ex, ey, ez, mr, a * 4, mr, a * 4);
    mp[b * 3] = sx + ex;
    mp[b * 3 + 1] = sy + ey;
    mp[b * 3 + 2] = sz + ez;
    Q.rotate(mr, b * 4, lt, c * 3, _w, 0);
    Q.swing(_w[0], _w[1], _w[2], dx * d - ex, dy * d - ey, dz * d - ez, mr, b * 4, mr, b * 4);
    mp[c * 3] = sx + dx * d;
    mp[c * 3 + 1] = sy + dy * d;
    mp[c * 3 + 2] = sz + dz * d;
  }

  /// m = translate(t) · rotate(q at qo).
  static void _setTR(Float32List m, Float64List q, int qo, double tx, double ty, double tz) {
    final x = q[qo], y = q[qo + 1], z = q[qo + 2], w = q[qo + 3];
    final x2 = x + x, y2 = y + y, z2 = z + z;
    final xx = x * x2, xy = x * y2, xz = x * z2, yy = y * y2, yz = y * z2, zz = z * z2, wx = w * x2, wy = w * y2, wz = w * z2;
    m[0] = 1 - (yy + zz);
    m[1] = xy + wz;
    m[2] = xz - wy;
    m[3] = 0;
    m[4] = xy - wz;
    m[5] = 1 - (xx + zz);
    m[6] = yz + wx;
    m[7] = 0;
    m[8] = xz + wy;
    m[9] = yz - wx;
    m[10] = 1 - (xx + yy);
    m[11] = 0;
    m[12] = tx;
    m[13] = ty;
    m[14] = tz;
    m[15] = 1;
  }
}
