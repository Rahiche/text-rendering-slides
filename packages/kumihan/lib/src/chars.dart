/// Character classes used by kumihan (JLREQ, https://www.w3.org/TR/jlreq/).
library;

/// U+2060 WORD JOINER: zero width, and forbids a line break on both sides
/// (UAX #14 class WJ). kumihan inserts it wherever a break must not happen.
const String wordJoiner = '⁠';

const int _wj = 0x2060;

/// Removes every U+2060 WORD JOINER from [text] (e.g. before copying).
String stripWordJoiners(String text) => text.contains(wordJoiner) ? text.replaceAll(wordJoiner, '') : text;

/// Whether [cp] is U+2060 WORD JOINER.
bool isWordJoiner(int cp) => cp == _wj;

// ─── Kinsoku (禁則) ──────────────────────────────────────────────────────────

/// Characters that must not start a line under strict kinsoku (JLREQ
/// cl-02 closing brackets, cl-03 hyphens, cl-04 dividing punctuation,
/// cl-05 middle dots, cl-06 full stops, cl-07 commas, cl-09 iteration marks,
/// cl-10 prolonged sound mark, cl-11 small kana; CSS `line-break: strict`).
///
/// Flutter's line breaker already forbids most of these; the ones it allows
/// (like CSS `line-break: normal`) are the small kana, ー and ～.
const String lineStartProhibited =
    // closing brackets (cl-02)
    '）〕］｝〉》」』】〙〗｠〟’”»)]}'
    // hyphens (cl-03)
    '‐〜゠–～'
    // dividing punctuation (cl-04)
    '？！‼⁇⁈⁉?!'
    // middle dots (cl-05)
    '・：；'
    // full stops, commas (cl-06, cl-07)
    '。．、，'
    // iteration marks (cl-09)
    'ヽヾゝゞ々〻'
    // prolonged sound marks (cl-10)
    'ーｰ'
    // small kana (cl-11)
    'ぁぃぅぇぉっゃゅょゎゕゖァィゥェォッャュョヮヵヶㇰㇱㇲㇳㇴㇵㇶㇷㇸㇹㇺㇻㇼㇽㇾㇿｧｨｩｪｫｬｭｮｯ';

/// Characters that must not end a line (JLREQ cl-01 opening brackets).
const String lineEndProhibited = '（〔［｛〈《「『【〘〖｟〝‘“«([{';

final Set<int> _startProhibited = lineStartProhibited.runes.toSet();
final Set<int> _endProhibited = lineEndProhibited.runes.toSet();

/// Whether [cp] must not begin a line (strict kinsoku).
bool isLineStartProhibited(int cp) => _startProhibited.contains(cp);

/// Whether [cp] must not end a line (strict kinsoku).
bool isLineEndProhibited(int cp) => _endProhibited.contains(cp);

/// The small kana and prolonged sound marks: allowed at a line start by
/// Flutter (and CSS `line-break: normal`), forbidden by strict kinsoku.
bool isConditionalStarter(int cp) =>
    (cp >= 0x3041 && cp <= 0x3049 && cp.isOdd) || // ぁぃぅぇぉ
    cp == 0x3063 || cp == 0x3083 || cp == 0x3085 || cp == 0x3087 || cp == 0x308E || // っゃゅょゎ
    cp == 0x3095 || cp == 0x3096 || // ゕゖ
    (cp >= 0x30A1 && cp <= 0x30A9 && cp.isOdd) || // ァィゥェォ
    cp == 0x30C3 || cp == 0x30E3 || cp == 0x30E5 || cp == 0x30E7 || cp == 0x30EE || // ッャュョヮ
    cp == 0x30F5 || cp == 0x30F6 || // ヵヶ
    (cp >= 0x31F0 && cp <= 0x31FF) || // ㇰ–ㇿ
    (cp >= 0xFF67 && cp <= 0xFF70) || // ｧ–ｯ ｰ
    cp == 0x30FC || // ー
    cp == 0xFF5E; // ～

/// Pairs that must stay together when doubled (JLREQ cl-08: ―― …… ‥‥).
bool isInseparable(int cp) => cp == 0x2014 || cp == 0x2015 || cp == 0x2026 || cp == 0x2025;

// ─── Scripts ────────────────────────────────────────────────────────────────

/// Whether [cp] is whitespace (a break opportunity kumihan never removes).
bool isSpace(int cp) =>
    cp == 0x20 ||
    cp == 0x09 ||
    cp == 0x0A ||
    cp == 0x0D ||
    cp == 0x0B ||
    cp == 0x0C ||
    cp == 0x85 ||
    cp == 0xA0 ||
    cp == 0x1680 ||
    (cp >= 0x2000 && cp <= 0x200B) ||
    cp == 0x2028 ||
    cp == 0x2029 ||
    cp == 0x202F ||
    cp == 0x205F ||
    cp == 0x3000;

/// CJK ideographs, kana, hangul, CJK punctuation and full-width forms: text
/// where a line may break between any two characters.
bool isCjk(int cp) =>
    (cp >= 0x1100 && cp <= 0x11FF) ||
    (cp >= 0x2E80 && cp <= 0x9FFF) ||
    (cp >= 0xA000 && cp <= 0xA4CF) ||
    (cp >= 0xAC00 && cp <= 0xD7AF) ||
    (cp >= 0xF900 && cp <= 0xFAFF) ||
    (cp >= 0xFE10 && cp <= 0xFE1F) ||
    (cp >= 0xFE30 && cp <= 0xFE4F) ||
    (cp >= 0xFF00 && cp <= 0xFFEF) ||
    (cp >= 0x1B000 && cp <= 0x1B16F) ||
    (cp >= 0x1F200 && cp <= 0x1F2FF) ||
    (cp >= 0x20000 && cp <= 0x3FFFF);

final RegExp _wordChar = RegExp(r'[\p{L}\p{N}\p{M}]', unicode: true);

/// Letters and digits of space-separated scripts (Latin, Greek, Cyrillic…).
/// No line break can happen between two of them, so kumihan never inserts a
/// word joiner there (which also keeps kerning and ligatures intact).
bool isWordChar(int cp) => !isCjk(cp) && _wordChar.hasMatch(String.fromCharCode(cp));

// ─── Yakumono (約物) ─────────────────────────────────────────────────────────

/// Full-width opening brackets (JLREQ cl-01): the glyph sits in the right
/// half of its em box, the left half is blank.
const String yakumonoOpening = '（〔［｛〈《「『【〘〖｟〝';

/// Full-width closing brackets (cl-02), full stops (cl-06) and commas
/// (cl-07): the glyph sits in the left half, the right half is blank.
const String yakumonoClosing = '）〕］｝〉》」』】〙〗｠〟。．、，';

final Set<int> _yOpen = yakumonoOpening.runes.toSet();
final Set<int> _yClose = yakumonoClosing.runes.toSet();

/// Whether [cp] is a full-width opening bracket.
bool isYakumonoOpening(int cp) => _yOpen.contains(cp);

/// Whether [cp] is a full-width closing bracket, full stop or comma.
bool isYakumonoClosing(int cp) => _yClose.contains(cp);
