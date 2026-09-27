// Slug glyph coverage for Flutter's FragmentProgram.
//
// Port of the reference pixel shader for the Slug algorithm:
//   Eric Lengyel, "GPU-Centered Font Rendering Directly from Glyph Outlines",
//   Journal of Computer Graphics Techniques (JCGT) 6(2), 2017.
//   Reference shaders: https://github.com/EricLengyel/Slug
//   Slug shader code Copyright 2017 by Eric Lengyel, MIT License
//   (see packages/slug/LICENSE). The Slug patent (US 10,373,352) was
//   dedicated to the public domain on 17 March 2026.
//
// What differs from the reference, because of Flutter runtime effects:
// * No uint / bitwise ops: the 0x2E74 root-eligibility lookup becomes sign
//   tests, and texels are read with texture() at texel centres and decoded
//   from bytes (RGBA8 data texture, see lib/src/encoder.dart).
// * No vertex stage: each glyph quad is a Canvas.drawRect in local
//   coordinates (FlutterFragCoord() is local). Pixels-per-em comes from a
//   local->device homography passed as uniforms, differentiated analytically:
//   exact under perspective, and no fwidth() (unavailable on the web).
// * Dilation of the quad is done on the CPU from the same homography.
// * Curves are duplicated per band (no curve-location indirection) and root
//   solving uses the cancellation-free form of the quadratic formula.

#version 460 core
precision highp float;

#include <flutter/runtime_effect.glsl>

#define MAX_CURVES 64

uniform vec4 uTex;   // data width, data height, glyph base texel, mode
uniform vec4 uH0;    // local -> device homography, row x (h00, h01, h02, -)
uniform vec4 uH1;    // row y
uniform vec4 uH2;    // row w
uniform vec4 uMap;   // local -> glyph grid: gx = x*a + b, gy = -y*a + c
uniform vec4 uBand;  // horizontal bands, vertical bands, h scale, v scale
uniform vec4 uColor; // premultiplied colour

uniform sampler2D uData;

out vec4 fragColor;

vec3 texelAt(float i) {
  float row = floor((i + 0.5) / uTex.x);
  float col = i - row * uTex.x;
  vec2 uv = (vec2(col, row) + 0.5) / uTex.xy;
  return floor(texture(uData, uv).rgb * 255.0 + 0.5);
}

// 12-bit x, 12-bit y packed in r, g, b.
vec2 pointAt(float i) {
  vec3 c = texelAt(i);
  float gh = floor(c.g / 16.0);
  return vec2(c.r * 16.0 + gh, (c.g - gh * 16.0) * 256.0 + c.b);
}

// Roots t of a t^2 - 2b t + c = 0 (the curve's coordinate relative to the
// sample), mapped through the other coordinate: returns (o(t1), o(t2)) where
// o(t) = (oa t - 2 ob) t + oc. Imaginary roots become a double root at the
// extremum t = b / a (as in the reference), so they cancel out.
vec2 solve(float a, float b, float c, float oa, float ob, float oc) {
  float t1;
  float t2;
  float disc = b * b - a * c;
  if (abs(a) < 0.25) {
    // Grid coordinates are integers, so a == 0 exactly: linear in t.
    t1 = c * 0.5 / b;
    t2 = t1;
  } else if (disc <= 0.0) {
    t1 = b / a;
    t2 = t1;
  } else {
    float d = sqrt(disc);
    if (b >= 0.0) {
      t1 = c / (b + d);
      t2 = (b + d) / a;
    } else {
      t1 = (b - d) / a;
      t2 = c / (b - d);
    }
  }
  return vec2((oa * t1 - ob * 2.0) * t1 + oc, (oa * t2 - ob * 2.0) * t2 + oc);
}

// Root eligibility from the signs of the three control points (replaces the
// reference's 0x2E74 lookup; identical truth table).
bool eligible1(bool n1, bool n2, bool n3) {
  return (!n1 && (n2 || n3)) || (n1 && !n2 && n3);
}

bool eligible2(bool n1, bool n2, bool n3) {
  return (n1 && !(n2 && n3)) || (!n1 && n2 && !n3);
}

vec3 heat(float t) {
  vec3 cold = vec3(0.18, 0.43, 0.66);
  vec3 warm = vec3(1.0, 0.78, 0.43);
  vec3 hot = vec3(1.0, 0.44, 0.49);
  return t < 0.5 ? mix(cold, warm, t * 2.0) : mix(warm, hot, t * 2.0 - 1.0);
}

void main() {
  vec2 p = FlutterFragCoord().xy;
  vec2 rc = vec2(p.x * uMap.x + uMap.y, -p.y * uMap.x + uMap.z);

  // d(device)/d(local) of the homography at p, then its inverse, gives the
  // glyph-grid units per device pixel (what fwidth(rc) would return).
  vec3 hp = vec3(p, 1.0);
  float w = dot(uH2.xyz, hp);
  float u = dot(uH0.xyz, hp) / w;
  float v = dot(uH1.xyz, hp) / w;
  float j00 = (uH0.x - u * uH2.x) / w;
  float j01 = (uH0.y - u * uH2.y) / w;
  float j10 = (uH1.x - v * uH2.x) / w;
  float j11 = (uH1.y - v * uH2.y) / w;
  float det = abs(j00 * j11 - j01 * j10);
  vec2 gridPerPixel = abs(uMap.x) * vec2(abs(j11) + abs(j01), abs(j10) + abs(j00)) / max(det, 1e-20);
  vec2 ppu = 1.0 / max(gridPerPixel, vec2(1e-6));

  float base = uTex.z;
  float by = clamp(floor(rc.y * uBand.z), 0.0, uBand.x - 1.0);
  float bx = clamp(floor(rc.x * uBand.w), 0.0, uBand.y - 1.0);
  vec3 hh = texelAt(base + by);
  vec3 vh = texelAt(base + uBand.x + bx);
  float hStart = base + hh.g * 256.0 + hh.b;
  float vStart = base + vh.g * 256.0 + vh.b;
  float tested = 0.0;

  // Horizontal ray (+x): curves sorted by max x, descending.
  float xcov = 0.0;
  float xwgt = 0.0;
  for (int i = 0; i < MAX_CURVES; i++) {
    if (float(i) >= hh.r) break;
    float t = hStart + 3.0 * float(i);
    vec2 q1 = pointAt(t);
    vec2 q2 = pointAt(t + 1.0);
    vec2 q3 = pointAt(t + 2.0);
    vec2 p1 = q1 - rc;
    if (max(max(p1.x, q2.x - rc.x), q3.x - rc.x) * ppu.x < -0.5) break;
    tested += 1.0;
    bool n1 = p1.y < 0.0;
    bool n2 = q2.y - rc.y < 0.0;
    bool n3 = q3.y - rc.y < 0.0;
    bool e1 = eligible1(n1, n2, n3);
    bool e2 = eligible2(n1, n2, n3);
    if (e1 || e2) {
      vec2 a = q1 - q2 * 2.0 + q3;
      vec2 b = q1 - q2;
      vec2 r = solve(a.y, b.y, p1.y, a.x, b.x, p1.x) * ppu.x;
      if (e1) {
        xcov += clamp(r.x + 0.5, 0.0, 1.0);
        xwgt = max(xwgt, clamp(1.0 - abs(r.x) * 2.0, 0.0, 1.0));
      }
      if (e2) {
        xcov -= clamp(r.y + 0.5, 0.0, 1.0);
        xwgt = max(xwgt, clamp(1.0 - abs(r.y) * 2.0, 0.0, 1.0));
      }
    }
  }

  // Vertical ray (+y): curves sorted by max y, descending.
  float ycov = 0.0;
  float ywgt = 0.0;
  for (int i = 0; i < MAX_CURVES; i++) {
    if (float(i) >= vh.r) break;
    float t = vStart + 3.0 * float(i);
    vec2 q1 = pointAt(t);
    vec2 q2 = pointAt(t + 1.0);
    vec2 q3 = pointAt(t + 2.0);
    vec2 p1 = q1 - rc;
    if (max(max(p1.y, q2.y - rc.y), q3.y - rc.y) * ppu.y < -0.5) break;
    tested += 1.0;
    bool n1 = p1.x < 0.0;
    bool n2 = q2.x - rc.x < 0.0;
    bool n3 = q3.x - rc.x < 0.0;
    bool e1 = eligible1(n1, n2, n3);
    bool e2 = eligible2(n1, n2, n3);
    if (e1 || e2) {
      vec2 a = q1 - q2 * 2.0 + q3;
      vec2 b = q1 - q2;
      vec2 r = solve(a.x, b.x, p1.x, a.y, b.y, p1.y) * ppu.y;
      if (e1) {
        ycov -= clamp(r.x + 0.5, 0.0, 1.0);
        ywgt = max(ywgt, clamp(1.0 - abs(r.x) * 2.0, 0.0, 1.0));
      }
      if (e2) {
        ycov += clamp(r.y + 0.5, 0.0, 1.0);
        ywgt = max(ywgt, clamp(1.0 - abs(r.y) * 2.0, 0.0, 1.0));
      }
    }
  }

  // Combine both rays, weighted by how close their nearest root is to the
  // pixel centre (reference CalcCoverage, nonzero fill rule).
  float coverage = max(
    abs(xcov * xwgt + ycov * ywgt) / max(xwgt + ywgt, 1.0 / 65536.0),
    min(abs(xcov), abs(ycov))
  );
  coverage = clamp(coverage, 0.0, 1.0);

  if (uTex.w > 0.5) {
    // Debug: heat map of curves tested for this pixel.
    float k = clamp(tested / 32.0, 0.0, 1.0);
    fragColor = vec4(heat(k), 1.0) * (0.28 + 0.72 * coverage);
  } else {
    fragColor = uColor * coverage;
  }
}
