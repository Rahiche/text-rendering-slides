# kumihan (組版)

Japanese typesetting for Flutter `Text`, for problems Flutter doesn't solve yet:

| problem in Flutter today | kumihan |
| --- | --- |
| Headings break mid-word (`今日は天気｜です`, `カンファ｜レンス`) | Breaks only between phrases (文節), using a Dart port of [BudouX](https://github.com/google/budoux) v0.9.2 — the model behind Chrome's `word-break: auto-phrase` |
| A phrase wider than the line gets split anywhere, even putting `。` at a line start | Width-aware: over-wide phrases are left to the normal line breaker, so kinsoku still holds |
| Small kana and `ー` may start a line (like CSS `line-break: normal`) | Strict kinsoku (禁則処理) |
| Headings end with a lonely word on the last line | `balance: true` — the narrowest width with the same line count (like CSS `text-wrap: balance`) |
| No `chws` in Noto Sans JP / Hiragino, so `」「` `。」` keep full-width gaps | `yakumono: true` — `halt` applied per character by adjacency (JLREQ punctuation spacing) |

```dart
KumihanText(
  'Flutterで日本語の改行をきれいにする方法',
  style: TextStyle(fontSize: 48),
  balance: true,
  yakumono: true,
)

// Or on plain strings:
Kumihan.phrases('今日は天気です。');           // [今日は, 天気です。]
Kumihan.prepare(text, maxWidth: w, style: s);  // text with U+2060 WORD JOINERs
```

It works by inserting U+2060 WORD JOINER between the characters inside each
phrase (zero width, same layout otherwise), so it works with the normal
`Text`/`RichText` pipeline. Copied text would contain the joiners: wrap
selectable content in `KumihanSelectionArea`, which strips them on copy, or
call `Kumihan.strip`. Meant for display text, not for `TextField`s.

Also includes the Simplified and Traditional Chinese BudouX models
(`KumihanLang.zhHans`, `KumihanLang.zhHant`).

Credits: BudouX models and parser © Google LLC, Apache-2.0 (see
`third_party/budoux`). Kinsoku and yakumono rules follow the W3C
[Requirements for Japanese Text Layout (JLREQ)](https://www.w3.org/TR/jlreq/).
