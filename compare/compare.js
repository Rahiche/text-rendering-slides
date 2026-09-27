// Builds the comparison page from cases.json (live HTML/CSS rendering) and
// out/flutter/*.png + lines.json (Flutter renders from test/compare_render_test.dart).

// Characters that must not start a line under strict kinsoku (JLREQ).
const NO_START = 'ぁぃぅぇぉっゃゅょゎゕゖァィゥェォッャュョヮヵヶー、。，．」』）】〕〉》・：；？！';

const PARAMS = new URLSearchParams(location.search);
const PART = PARAMS.get('part'); // null = everything
const STATIC = PARAMS.get('static') === '1';

const $ = (tag, cls, text) => {
  const e = document.createElement(tag);
  if (cls) e.className = cls;
  if (text != null) e.textContent = text;
  return e;
};

/** Measured line breaks of a single-text-node element. */
function linesOf(el) {
  const node = el.firstChild;
  const text = node.textContent;
  const range = document.createRange();
  const lines = [];
  let cur = '';
  let top = null;
  for (let i = 0; i < text.length; i++) {
    range.setStart(node, i);
    range.setEnd(node, i + 1);
    const r = range.getClientRects()[0];
    if (r) {
      const t = Math.round(r.top);
      if (top === null) top = t;
      if (t - top > 4) {
        lines.push(cur);
        cur = '';
        top = t;
      }
    }
    cur += text[i];
  }
  if (cur) lines.push(cur);
  return lines.map((l) => l.trimEnd());
}

function widthOf(el) {
  const range = document.createRange();
  range.selectNodeContents(el);
  return Math.max(...[...range.getClientRects()].map((r) => r.width));
}

function kinsokuViolations(lines) {
  return lines.slice(1).filter((l) => l && NO_START.includes(l[0])).map((l) => l[0]);
}

function foot(lines, extra) {
  const f = $('div', 'foot');
  const l = $('div', 'lines');
  lines.forEach((line, i) => {
    if (i) l.append($('span', 'sep', '/'));
    l.append(document.createTextNode(line));
  });
  f.append(l);
  const b = $('div', 'badges');
  b.append($('span', 'badge', `${lines.length} line${lines.length > 1 ? 's' : ''}`));
  const bad = kinsokuViolations(lines);
  b.append(bad.length
    ? $('span', 'badge bad', `kinsoku ✕ ${bad.join(' ')}`)
    : $('span', 'badge ok', 'kinsoku ✓'));
  for (const x of extra) b.append(x);
  f.append(b);
  return f;
}

function same(a, b) {
  return a && b && a.join('|') === b.join('|');
}

async function main() {
  if (PART === 'zoom') {
    document.getElementById('summary').remove();
    return;
  }
  const cases = await (await fetch('cases.json')).json();
  let flutter = null;
  try {
    flutter = await (await fetch('out/flutter/lines.json', { cache: 'no-store' })).json();
  } catch (_) { /* renders not generated yet */ }

  document.getElementById('env').textContent =
    `${navigator.userAgent.match(/Chrome\/[\d.]+/)?.[0] ?? navigator.userAgent} · ` +
    `Flutter renders: ${flutter ? 'test/compare_render_test.dart' : 'missing (run compare/capture.sh)'}`;

  await document.fonts.load('400 20px NotoSansJP', 'あ');

  const main = document.getElementById('cases');
  const summary = [];

  cases.forEach((c, n) => {
    const sec = $('section', 'case');
    sec.append($('h2', null, `${n + 1}. ${c.title}`));
    sec.append($('div', 'meta mono', `${c.fontSize}px · width ${c.width}px · 「${c.text}」`));

    const grid = $('div', 'grid');
    grid.append($('div'), $('div', 'colhead', 'default'), $('div', 'colhead', 'Japanese typesetting'));

    // ── Chrome row: live HTML/CSS
    const chrome = {};
    grid.append($('div', 'rowlabel', 'Chrome'));
    for (const mode of ['default', 'ja']) {
      const cell = $('div', 'cell');
      const box = $('div', 'box');
      const s = $('div', `sample chrome-${mode}${c.balance ? ' balance' : ''}`, c.text);
      s.lang = 'ja';
      s.style.fontSize = `${c.fontSize}px`;
      s.style.width = `${c.width}px`;
      box.append(s);
      cell.append(box);
      grid.append(cell);
      chrome[mode] = { cell, sample: s };
    }

    // ── Flutter row: images rendered by flutter test
    const fl = {};
    grid.append($('div', 'rowlabel', 'Flutter'));
    for (const mode of ['text', 'kumihan']) {
      const cell = $('div', 'cell');
      const data = flutter?.[c.id]?.[mode];
      if (data) {
        const img = $('img', 'shot');
        img.src = `out/flutter/${c.id}_${mode}.png?${Date.now()}`;
        img.style.width = `${c.width + 32}px`;
        cell.append(img);
      } else {
        cell.append($('div', 'missing', 'no Flutter render — run compare/capture.sh'));
      }
      grid.append(cell);
      fl[mode] = { cell, data };
    }
    sec.append(grid);
    main.append(sec);

    // Measure after layout.
    requestAnimationFrame(() => {
      const row = { title: c.title };
      for (const [mode, label] of [['default', 'Chrome default'], ['ja', 'Chrome + Japanese CSS']]) {
        const { cell, sample } = chrome[mode];
        const lines = linesOf(sample);
        chrome[mode].lines = lines;
        const w = widthOf(sample);
        cell.append(foot(lines, [$('span', 'badge', `${(w / c.fontSize).toFixed(2)} em wide`)]));
        row[label] = lines;
      }
      for (const [mode, ref] of [['text', 'default'], ['kumihan', 'ja']]) {
        const { cell, data } = fl[mode];
        if (!data) continue;
        const match = same(data.lines, chrome[ref].lines);
        cell.append(foot(data.lines, [
          $('span', 'badge', `${(data.longestLine / c.fontSize).toFixed(2)} em wide`),
          $('span', `badge ${match ? 'ok' : ''}`, match ? `same breaks as Chrome ${ref === 'ja' ? '+ CSS' : 'default'}` : `differs from Chrome ${ref === 'ja' ? '+ CSS' : 'default'}`),
        ]));
        row[mode] = data.lines;
      }
      summary.push(row);
      if (summary.length === cases.length) renderSummary(cases, summary);
    });
  });
}

function renderSummary(cases, rows) {
  const t = $('table');
  const head = $('tr');
  for (const h of ['case', 'Flutter Text: kinsoku', 'kumihan: kinsoku', 'kumihan = Chrome + Japanese CSS?']) head.append($('th', null, h));
  t.append(head);
  for (const c of cases) {
    const r = rows.find((x) => x.title === c.title);
    const tr = $('tr');
    tr.append($('td', null, c.title));
    for (const k of ['text', 'kumihan']) {
      const v = r[k] ? kinsokuViolations(r[k]) : null;
      tr.append($('td', null, v == null ? '—' : v.length ? `✕ ${v.join(' ')}` : '✓'));
    }
    tr.append($('td', null, r.kumihan ? (same(r.kumihan, r['Chrome + Japanese CSS']) ? '✓ same breaks' : '≠ differs') : '—'));
    t.append(tr);
  }
  document.getElementById('summary').append(t);
  document.body.dataset.ready = '1';
}

// ── Slug zoom & perspective ────────────────────────────────────────
// Chrome text under a CSS transform next to an iframe of the Flutter web
// app in probe mode (lib/probe/slug_probe.dart), which renders Flutter Text
// and SlugText under the same Matrix4.
async function renderZoom() {
  if (PART === 'type') return;
  let cases;
  try {
    cases = (await (await fetch('zoom.json')).json()).filter((c) => !(STATIC && c.anim));
  } catch (_) {
    return;
  }
  // Local capture builds the app into out/app/; on the site, reuse a deck build.
  const local = await fetch('out/app/index.html', { method: 'HEAD' }).then((r) => r.ok).catch(() => false);
  const appBase = local ? 'out/app/' : '../classic/';
  await document.fonts.load('300 24px SGrot', 'Text');
  await document.fonts.load('24px CaseJP', '直');

  const root = document.getElementById('zoom');
  root.append($('h2', 'part', 'Slug · zoom & perspective'));
  root.append($('div', 'meta', 'Same font file, size and transform on every side. ' +
    'Chrome: CSS transform on HTML text. Flutter: the web build (Wasm/Skwasm) running live in the iframe. ' +
    'Note: on the web, Skia draws large or perspective glyphs as paths too, so Text and SlugText mostly match here; ' +
    'Slug\u2019s gains are vs Impeller\u2019s glyph atlas on native (mid-size zoom, perspective, animated scale).'));

  for (const c of cases) {
    const w = c.w ?? 520, h = c.h ?? 280, gap = 18;
    const sec = $('section', 'case');
    sec.append($('h2', null, c.title));
    const t = [];
    if (c.persp) t.push(`perspective(${c.persp}px)`);
    if (c.rx) t.push(`rotateX(${c.rx}deg)`);
    if (c.ry) t.push(`rotateY(${c.ry}deg)`);
    if (c.scale && !c.anim) t.push(`scale(${c.scale})`);
    const transform = t.join(' ') || 'none';
    sec.append($('div', 'meta mono', `「${c.text}」 · ${c.size}px · transform-origin ${c.ox}px ${c.oy}px · ${c.anim ? `scale 1 ↔ ${c.scale} (4 s loop)` : transform}`));

    const row = $('div', 'zoomrow');
    // Chrome
    const chromeCol = $('div', 'zoomcol');
    chromeCol.append($('div', 'colhead', 'Chrome · CSS transform'));
    const view = $('div', 'view');
    view.style.width = `${w}px`;
    view.style.height = `${h}px`;
    const subj = $('div', 'subject');
    subj.lang = 'ja';
    subj.textContent = c.text;
    subj.style.fontFamily = c.font === 'jp' ? 'CaseJP' : 'SGrot';
    subj.style.fontWeight = c.font === 'jp' ? '400' : '300';
    Object.assign(subj.style, {
      left: `${c.x0}px`, top: `${c.y0}px`, fontSize: `${c.size}px`,
      transformOrigin: `${c.ox}px ${c.oy}px`,
    });
    view.append(subj);
    chromeCol.append(view);
    row.append(chromeCol);
    sec.append(row);
    root.append(sec);

    // Flutter (one iframe renders Text and SlugText side by side)
    const flCol = $('div', 'zoomcol');
    const heads = $('div', 'probeheads');
    for (const label of ['Flutter · Text', 'Flutter · SlugText']) {
      const hd = $('div', 'colhead', label);
      hd.style.width = `${w}px`;
      heads.append(hd);
    }
    flCol.append(heads);
    // Chrome snaps ascent, descent and half-leading to whole pixels; Flutter
    // keeps fractions. Hand the probe Chrome's measured baseline so both put
    // the glyphs on the same line (≈1px at 24px, which 40× zoom magnifies).
    const mark = document.createElement('span');
    mark.style.cssText = 'display:inline-block;width:0;height:0;vertical-align:baseline';
    subj.append(mark);
    const base = mark.getBoundingClientRect().top - subj.getBoundingClientRect().top;
    mark.remove();
    subj.style.transform = c.anim ? '' : transform;
    if (c.anim) {
      subj.style.setProperty('--s', c.scale);
      // Wall-clock phase, same as the Flutter probe, so the loops stay in step.
      subj.style.animationDelay = `-${Date.now() % 4000}ms`;
      subj.classList.add('anim');
    }

    const params = new URLSearchParams({
      probe: 'slug', w, h, gap, size: c.size, scale: c.scale ?? 1, rx: c.rx ?? 0, ry: c.ry ?? 0,
      persp: c.persp ?? 0, ox: c.ox, oy: c.oy, x0: c.x0, y0: c.y0, anim: c.anim ? 1 : 0,
      text: c.text, font: c.font, base: base.toFixed(3),
    });
    const frame = $('iframe', 'probe');
    frame.src = `${appBase}?${params}`;
    frame.width = String(2 * w + gap);
    frame.height = String(h);
    frame.title = `Flutter Text vs SlugText: ${c.title}`;
    flCol.append(frame);
    row.append(flCol);
  }
}

main().then(renderZoom);
