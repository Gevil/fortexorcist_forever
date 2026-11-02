/*
 * scripts/uif_battery_mock_test.js — the fx-clear-forte mock (slice F-C,
 * PLAN §11.1 wave 3): run the battery's fresh-clear sweep against FAKE PAGES
 * and assert its counting, without touching the live site.
 *
 *   node scripts/uif_battery_mock_test.js       # exits 0 when every case passes
 *
 * What is under test is `forteClearSweep` + `forteClearVerdict` in
 * scripts/uif_battery.js — imported, NOT re-implemented, so a change to the
 * sweep that breaks a case breaks this file. The two live defects it exists
 * for:
 *   3. a sweep that removed 0 of 15 rows PASSED ("no targets" and "nothing
 *      to clean" are the same number to a count-only check);
 *   4. the "Forte rows visible" count matched text ANYWHERE on the page, so
 *      a Lua console printing `ForteXorcist...` lines posed as add-on rows —
 *      70 console lines over an empty list read as 70 visible rows.
 * The fix is panel scoping: the count only sees the ADDONS LIST PANEL, the
 * container of the per-addon rows (each row = a checkbox + a ✕).
 */
'use strict';

const path = require('node:path');
// The shipped file by default; $FX_BATTERY points the harness at a copy (the
// "prove the case fails on the old code" run).
const battery = require(process.env.FX_BATTERY
  || path.join(__dirname, 'uif_battery.js'));
const forteClearSweep = battery.forteClearSweep;
const forteClearVerdict = battery.forteClearVerdict;

const CROSS = '\u2715';                    // the per-row remove control

// ----------------------------------------------------------- a tiny DOM ----
// Everything the sweep touches: textContent, children, parentElement,
// querySelectorAll over 'button' / 'body *' / '*', contains, click. A click
// on a row's ✕ deletes the row from its list, as the site re-renders.
class El {
  constructor(tag, opts) {
    const o = opts || {};
    this.tagName = String(tag).toUpperCase();
    this.childNodes = [];
    this.parentElement = null;
    this._text = o.text || '';
    this._type = o.type || '';
    this._onDelete = o.onDelete || null;
    this.removed = false;
  }
  append() {
    for (const n of Array.from(arguments)) { n.parentElement = this; this.childNodes.push(n); }
    return this;
  }
  detach() {
    const p = this.parentElement;
    if (!p) return;
    const i = p.childNodes.indexOf(this);
    if (i >= 0) p.childNodes.splice(i, 1);
    this.removed = true;
  }
  get children() { return this.childNodes.slice(); }
  get textContent() {
    // A space joins the pieces, as the site's own whitespace text nodes do:
    // glued text ("activeForte_A") would kill the sweep's /\bForte_/ word
    // boundary and make a real row read as "no Forte row".
    return [this._text].concat(this.childNodes.map((n) => n.textContent)).join(' ');
  }
  getBoundingClientRect() { return { width: 120, height: 24 }; }
  _matches(sel) {
    if (sel === '*' || sel === 'body *') return true;
    return this.tagName === String(sel).toUpperCase();
  }
  querySelectorAll(sel) {
    const out = [];
    const walk = (n) => {
      for (const c of n.childNodes) { out.push(c); walk(c); }
    };
    walk(this);
    return out.filter((n) => n._matches(sel));
  }
  contains(n) {
    for (let p = n; p; p = p.parentElement) if (p === this) return true;
    return false;
  }
  click() { if (this._onDelete) this._onDelete(this); }
}

const el = (tag, opts) => new El(tag, opts);

// The page as the site lays it out: a LEFT panel carrying the
// `ADDONS · N/N active` header plus the list of per-addon rows, and a RIGHT
// console pane whose printed lines mention ForteXorcist (add-on chatter,
// print()s, stack traces) — the text the count must NEVER see.
function makePage(opts) {
  const o = opts || {};
  const names = o.rows || [];
  const consoleLines = o.consoleLines || [];
  const body = el('body');
  const left = el('div');
  if (o.header !== false) {
    left.append(el('div', { text: `ADDONS \u00B7 ${names.length}/${names.length} active` }));
  }
  const list = el('ul');
  for (const name of names) {
    const row = el('li');
    row.append(
      el('input', { type: 'checkbox' }),
      el('span', { text: name }),
      el('button', { text: CROSS, onDelete: () => row.detach() }));
    list.append(row);
  }
  left.append(list);
  const pane = el('div');
  for (const line of consoleLines) pane.append(el('div', { text: line }));
  if (o.strayCross) {
    // A ✕ OUTSIDE the add-on list (a dialog's close control): it must not
    // widen the panel anchor out to the whole document.
    pane.append(el('button', { text: CROSS }));
  }
  body.append(left, pane);
  return { body, list, document: { querySelectorAll: (sel) => body.querySelectorAll(sel) } };
}

// The pre-F-C count, over the WHOLE page: the witness that a case is a real
// regression (the old count on the same bytes).
function pageWideForteCount(doc) {
  const has = (n) => /Forte/.test(n.textContent || '');
  return doc.querySelectorAll('body *')
    .filter((n) => has(n) && !n.children.some(has)).length;
}

const FORTE_NAMES = Array.from({ length: 16 }, (_, i) => `Forte_AddOn${i}`);
const CHATTER = Array.from({ length: 70 }, (_, i) =>
  `ForteXorcist: probe line ${i} (the add-on printing into the console)`);

const cases = [];
// A case hands over a PAGE BUILDER: the page is built twice, once for the
// sweep (which mutates it) and once for the pre-F-C count witness, so the
// two numbers describe the same page.
const run = async (name, build, want) => {
  const witness = build();
  const oldCount = pageWideForteCount(witness.document);
  const page = build();
  const got = await forteClearSweep(page.document);
  const pass = forteClearVerdict(got);
  const bad = [];
  if (pass !== want.pass) bad.push(`verdict ${pass}, wanted ${want.pass}`);
  for (const k of ['visible', 'matched', 'removed', 'left']) {
    if (want[k] !== undefined && got[k] !== want[k]) bad.push(`${k}=${got[k]}, wanted ${want[k]}`);
  }
  if (want.rowsLeft !== undefined && page.list.children.length !== want.rowsLeft) {
    bad.push(`rows on screen ${page.list.children.length}, wanted ${want.rowsLeft}`);
  }
  if (want.oldCount !== undefined && oldCount !== want.oldCount) {
    bad.push(`page-wide count ${oldCount}, wanted ${want.oldCount}`);
  }
  cases.push({ name, ok: bad.length === 0, why: bad.join('; '),
    got: `visible=${got.visible} matched=${got.matched} removed=${got.removed}`
      + ` left=${got.left} panel=${got.panel} rowsLeft=${page.list.children.length}`
      + ` pageWideCount=${oldCount} verdict=${pass}` });
  return cases[cases.length - 1];
};

async function main() {
  // 1. THE F-C DEFECT. The console mentions Forte 70 times, the ADDONS panel
  //    holds no row at all: the sweep has nothing to remove, and the row
  //    MUST PASS (the page-wide count saw 70 "rows" and failed it).
  await run('console mentions Forte 70x over an EMPTY panel -> PASS',
    () => makePage({ rows: [], consoleLines: CHATTER }),
    { pass: true, visible: 0, matched: 0, removed: 0, left: 0, rowsLeft: 0,
      oldCount: 70 });

  // 2. The same console noise with 16 real rows in the panel: the count reads
  //    16 (not the 86 the page-wide count sees), and all 16 are removed.
  await run('console mentions Forte 70x over 16 panel rows -> removes 16',
    () => makePage({ rows: FORTE_NAMES, consoleLines: CHATTER }),
    { pass: true, visible: 16, matched: 16, removed: 16, left: 0, rowsLeft: 0,
      oldCount: 86 });

  // 3. A single row: the panel anchor degenerates onto the row itself; the
  //    count still reads 1 and the sweep removes it.
  await run('one panel row, quiet console -> removes 1',
    () => makePage({ rows: ['Forte_Cooldown'] }),
    { pass: true, visible: 1, matched: 1, removed: 1, left: 0, rowsLeft: 0 });

  // 4. DEFECT 3 STAYS CLOSED: the rows are on screen and the \u2715 removes
  //    nothing (a dead selector). The sweep must report rows LEFT and the
  //    verdict must FAIL.
  const deadRows = ['Forte_Cooldown', 'Forte_Timer', 'Forte_Core'];
  const deadBuilder = () => {
    const p = makePage({ rows: deadRows });
    for (const li of p.list.children) {
      for (const c of li.children) if (c.tagName === 'BUTTON') c._onDelete = null;
    }
    return p;
  };
  await run('three rows whose \u2715 removes nothing -> FAIL', deadBuilder,
    { pass: false, visible: 3, left: 3 });

  // 5b. A \u2715 outside the panel (a dialog close control) beside the 16
  //     rows: the anchor stays the left panel, the count stays 16.
  await run('16 rows plus a stray \u2715 outside the panel -> count stays 16',
    () => makePage({ rows: FORTE_NAMES, consoleLines: CHATTER,
      strayCross: true }),
    { pass: true, visible: 16, matched: 16, removed: 16, left: 0,
      rowsLeft: 0, oldCount: 86 });

  // 5. No \u2715 anywhere AND no ADDONS header: the panel cannot be located,
  //    the count reports -1 and the verdict fails loudly rather than passing
  //    on an unseen page.
  await run('no rows and no ADDONS header (panel unlocatable) -> FAIL',
    () => makePage({ rows: [], header: false }),
    { pass: false, visible: -1, removed: 0, left: 0 });

  const failed = cases.filter((c) => !c.ok);
  for (const c of cases) {
    console.log(`${c.ok ? 'PASS' : 'FAIL'}  ${c.name}\n        ${c.got}`
      + (c.ok ? '' : `\n        ${c.why}`));
  }
  console.log(`uif_battery_mock_test: ${failed.length ? 'FAIL' : 'PASS'}`
    + ` (${cases.length - failed.length}/${cases.length})`);
  process.exitCode = failed.length ? 1 : 0;
}

main().catch((e) => { console.log(`uif_battery_mock_test: ERROR ${e.stack || e}`); process.exitCode = 2; });
