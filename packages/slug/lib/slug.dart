/// Resolution-independent GPU text (Slug algorithm).
///
/// Glyph outlines are split into bands of quadratic curves, packed into a
/// data texture, and a fragment shader computes exact per-pixel coverage
/// from horizontal and vertical rays (Eric Lengyel, JCGT 2017; reference
/// shaders MIT, github.com/EricLengyel/Slug; patent dedicated to the public
/// domain in 2026).
library;

export 'src/encoder.dart';
export 'src/font.dart';
export 'src/painter.dart';
export 'src/reference.dart';
export 'src/text.dart';
