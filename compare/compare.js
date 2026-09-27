// Builds the comparison page from cases.json (live HTML/CSS rendering) and
// out/flutter/*.png + lines.json (Flutter renders from test/compare_render_test.dart).

// Characters that must not start a line under strict kinsoku (JLREQ).
const NO_START = 'ぁぃぅぇぉっゃゅょゎゕゖァィゥェォッャュョヮヵヶー、。，．」』）】〕〉》・：；？！';

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

main();
