/*
 * scripts/uif_battery.js — the uiforever.com launch battery, ONE async
 * function the MANAGER runs in his browser kernel (PLAN §11.1 slice H2).
 * Never run it from this repo: it drives the site's live UI.
 *
 * Kernel globals it uses (all provided by the manager's kernel):
 *   uifTab                 the open uiforever tab  (.evaluate/.uploadFile)
 *   clickText(text)        clicks the visible control whose text is <text>
 *   lua(cmd, waitMs)       types <cmd> into the site's Lua CONSOLE, waits,
 *                          returns the console text that came back. The
 *                          console takes PLAIN Lua (never a `/run ` prefix:
 *                          the console echoed that verbatim and ran nothing,
 *                          live finding 2026-11-02). The returned text mixes
 *                          the `› `-prefixed echo of the typed command with
 *                          the printed lines — parse printed lines only.
 *
 * Run it as:
 *   await uifBattery({ zip: '/tmp/fx_uif.zip', fresh: true, persist: true })
 * options:
 *   zip            the release zip to import (default /tmp/fx_uif.zip)
 *   fresh          true = first clear the Forte_ rows of a previous import
 *                  (per-row ✕, 350 ms apart, until none remain). The row
 *                  FAILS when the ADDON LIST PANEL — the container of the
 *                  per-addon rows, each a checkbox + a ✕ — shows Forte rows
 *                  while 0 were removed: a dead \u2715 selector must not
 *                  read as "nothing to clean". The count is scoped to that
 *                  panel (defect 4, 2026-11-02: the page-wide count let the
 *                  Lua console's `ForteXorcist...` lines pose as rows); the
 *                  panel's `visible` is -1 when it cannot be located, which
 *                  fails the row. Mock-tested by
 *                  scripts/uif_battery_mock_test.js.
 *   expectMarker   Lua expression string (e.g. `ForteXorcist.Hunter and
 *                  ForteXorcist.Hunter.Tools and
 *                  ForteXorcist.Hunter.Tools.Swing.CycleState ~= nil`),
 *                  evaluated after /reload; the CODE row passes only when
 *                  it prints true — it proves the site runs THIS zip's
 *                  bytes, not the previous import's. Default: compare
 *                  ForteXorcist.CONST.VERSION (the build constant in
 *                  addon/Forte_Core/Core/Constants.lua) to the shipped value
 *   reloadWaitMs   settle time after /reload (default 20000)
 *   importOnly     true = import + reload, skip the checks
 *   checksOnly     true = skip the import (site already loaded), run checks
 *   persist        true = also run the PERSIST row (writes one setting,
 *                  /reloads, reads it back, restores the old value)
 *
 * What it proves, in order:
 *   1. IMPORT   the manager's live recipe (2026-11-02): clear the old Forte_
 *               rows (the row FAILS if Forte rows are visible in the list
 *               while 0 were removed) -> tag the LAST .zip file input ->
 *               upload -> poll up to 15 s for the `Import addons?` DIALOG
 *               (its text plus a button whose text is exactly `Import`
 *               inside it) and click THAT button -> poll the dialog GONE
 *               -> Later -> Let's go -> /reload -> the header reads
 *               `ADDONS · N/N active` with N >= 15. The dialog lands
 *               seconds after the upload on a larger zip: the
 *               2026-11-02 blind clickText('Import') hit nothing, the import
 *               never ran, and every later check passed against the
 *               PREVIOUSLY loaded code (false PASS). No dialog = FAIL.
 *   2. CODE     the expectMarker Lua expression prints true (default: the
 *               ForteXorcist.CONST.VERSION build constant) — the bytes
 *               running are the bytes just imported.
 *   3. CLASSSET exactly the player's own Forte_<Class> add-on is resident,
 *               over the nine class add-ons; the site's own Mage log-in
 *               artefact is tolerated (PLAN §9 2026-11-02 LoD row).
 *   4. MODULES  ForteXorcist._moduleOrder prints (a live-verified array,
 *               `Locale,Probe,Splash,Cooldown,Timer,Messages`), and the
 *               always-loaded set Cooldown,Locale,Log,Messages,Probe,Splash,
 *               Timer is in it (Log: code-review-10 M3/M4, gate.py's
 *               ALWAYS_MODULES is the law).
 *   5. CORE     the Splash and Messages modules are present.
 *   6. DB       ForteXorcist.db.version == 1 and db.profiles.active is set
 *               (the H3 profiles schema).
 *   7. RAIDMSG  a COOLDOWN_READY pop sends 0 party/raid chat lines with the
 *               shipped defaults (every announce gate is opt-in, review 4 E2).
 *   8. PERSIST  (opt-in `persist`) Settings:Set Cooldown Width 333 ->
 *               /reload -> reads back 333 -> restores the old value.
 *   9. ERRORS   the Errors tab (its text matches /^Errors\s*\d*$/) says
 *               "No Lua errors" and no body line mentions Forte_.
 *
 * It returns { pass, rows } -- rows = [{ name, pass, expect, got }] -- and
 * console.logs the same as a table. Nothing here raises on a failed check:
 * a fail is a row, not an exception.
 */
// The default CODE marker. `FX.CONST.VERSION` is the build constant of
// addon/Forte_Core/Core/Constants.lua (present at the 2026-11-02 read);
// release.py stamps only the tocs' `## Version:`, so this constant ships
// verbatim in the zip. If the constant is ever dropped from the repo, set
// this to null and the CODE row skips with a note.
const DEFAULT_CODE_MARKER =
  '(ForteXorcist.CONST and ForteXorcist.CONST.VERSION) == "0.1.0-dev"';

// ------------------------------------------------------- fx-clear-forte ----
// The fresh-clear sweep, at module scope on purpose: the mock harness
// scripts/uif_battery_mock_test.js drives THESE EXACT BYTES against a fake
// DOM. Both known false-PASS classes of this sweep are COUNTING bugs, so a
// transcribed copy of the body in a test would prove nothing.
//
// It is handed to `uifTab.evaluate`, which serialises it into the page, so it
// may touch only its own locals plus the document it is passed (the battery
// passes the page's own `document` from inside the page expression; the mock
// harness passes its fake one).
async function forteClearSweep(docArg) {
  // fx-clear-forte
  const doc = docArg || (typeof document === 'undefined' ? null : document);
  const nap = (ms) => new Promise((r) => setTimeout(r, ms));
  const xText = (b) => (b.textContent || '').trim() === '\u2715';
  const xButtonsIn = (n) => Array.from(n.querySelectorAll('button')).filter(xText);
  const allX = () => xButtonsIn(doc.body || doc.documentElement || doc);
  const rowOf = (b) => {
    // Widest ancestor that still contains exactly this one \u2715: the row.
    let n = b.parentElement; let last = null;
    while (n) {
      const xs = Array.from(n.querySelectorAll('button')).filter(xText);
      if (xs.length !== 1) break;
      last = n; n = n.parentElement;
    }
    return last || b.parentElement;
  };
  const targets = () => allX().filter((b) => {
    const row = rowOf(b);
    // The site lists imported addons by title ("Forte Cooldown"), not folder
    // ("Forte_Cooldown"): match either spelling (manager, live run 2026-11-03).
    return /\bForte[_ ]/.test((row && row.textContent) || '');
  });
  // Defect 3 (2026-11-02): this sweep once removed 0 of 15 rows and PASSED,
  // because "0 targets" and "nothing to clean" are the same number to a
  // count-only check. Count the Forte rows visible in the add-on list
  // independently of the \u2715 selector, so the caller can fail a 0-removal
  // sweep that ran while rows stood on screen.
  // Defect 4 (2026-11-02, slice F-C): that count asked the WHOLE page for the
  // smallest `Forte`-bearing elements, so the Lua CONSOLE printing
  // `ForteXorcist...` lines fed it — 70 console lines read as 70 visible rows
  // over an empty list (and, inverted, a console that happened to be quiet
  // masked a dead \u2715 selector). The count belongs to the ADDONS LIST
  // PANEL: the left panel's `ADDONS` header plus the per-addon rows under it
  // (each row = a checkbox + a \u2715), which makes the Lua console a SIBLING
  // of what is counted. A panel that cannot be located at all reports
  // -1, which the caller's 0-removed gate fails LOUDLY instead of passing.
  const deepestCommonAncestor = (nodes) => {
    let n = nodes[0] ? nodes[0].parentElement : null;
    while (n && !nodes.every((x) => n.contains(x))) n = n.parentElement;
    return n;
  };
  const addonsHeader = () => {
    const norm = (s) => (s || '').replace(/\s+/g, ' ').trim();
    const hits = Array.from(doc.querySelectorAll('body *'))
      .filter((n) => /^ADDONS\b/i.test(norm(n.textContent)));
    return hits[hits.length - 1] || null;   // document order: last = innermost
  };
  const panelOf = () => {
    const xs = allX();
    const hdr = addonsHeader();
    // THE HEADER ANCHORS THE PANEL. Climb from the `ADDONS` header to the
    // SMALLEST element that also contains a \u2715: that element is the left
    // add-on panel (header + its rows), and the console / right panes are its
    // SIBLINGS, out of the count by construction. Anchoring on the \u2715 set
    // alone would let one \u2715 outside the list (a dialog's close control)
    // widen the anchor to the whole document and put the console back in the
    // count.
    if (hdr) {
      for (let n = hdr; n; n = n.parentElement) {
        const inPanel = xButtonsIn(n).length;
        if (inPanel > 0) {
          return { panel: n,
            kind: `${inPanel} of ${xs.length} \u2715 in the header's panel` };
        }
      }
      // The header with no \u2715 under it anywhere: an empty list. Count
      // inside the header's own container.
      const p = hdr.parentElement || hdr;
      return { panel: p, kind: 'empty list, ADDONS header anchor' };
    }
    // No header on the page: fall back to the SMALLEST element holding every
    // \u2715 (the list container), and name the weaker anchor in the row.
    const p = deepestCommonAncestor(xs);
    return { panel: p, kind: p
      ? `no ADDONS header: ${xs.length} \u2715 common ancestor`
      : 'no \u2715, no ADDONS header' };
  };
  const forteRowsVisible = (panel) => {
    if (!panel) return -1;
    const has = (n) => /Forte/.test(n.textContent || '');
    const leaves = Array.from(panel.querySelectorAll('*'))
      .filter((n) => has(n) && !Array.from(n.children).some(has));
    // The panel with no separate leaf under it (a site that puts the add-on
    // name right on the row element): the panel's own text is the row.
    if (!leaves.length && has(panel)) leaves.push(panel);
    return leaves.length;
  };
  const where = panelOf();
  const visible = forteRowsVisible(where.panel);
  const matched = targets().length;
  let removed = 0;
  for (let guard = 0; guard < 80; guard++) {
    const t = targets()[0];
    if (!t) break;
    t.click();
    removed += 1;
    await nap(350);
  }
  return { visible, matched, removed, left: targets().length, panel: where.kind };
}

// The IMPORT-cleared row's verdict: `left === 0` (nothing left to clean) and
// a 0-removal sweep is honest ONLY when the panel showed no Forte row to
// remove (`visible === 0`); an unlocatable panel reports -1 and fails.
const forteClearVerdict = (cleared) => cleared.left === 0
  && (cleared.removed > 0 || cleared.visible === 0);

async function uifBattery(options) {
  const opt = options || {};
  const zip = opt.zip || '/tmp/fx_uif.zip';
  const reloadWaitMs = opt.reloadWaitMs || 20000;
  // The "Import addons?" dialog of a larger zip lands seconds after the
  // upload (live finding 2026-11-02, the false-PASS race): poll this long
  // for it, and this long for it to close after Import.
  const IMPORT_DIALOG_MS = 15000;
  const DIALOG_GONE_MS = 15000;
  const rows = [];
  const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
  const add = (name, pass, expect, got) => {
    rows.push({ name, pass: !!pass, expect, got: String(got == null ? '' : got).slice(0, 900) });
    return rows[rows.length - 1];
  };
  const safeClick = async (text) => {
    try {
      await clickText(text);
      await sleep(500);
      return true;
    } catch (e) {
      return false;
    }
  };
  const bodyText = async () =>
    String(await uifTab.evaluate(() => document.body.innerText));
  // Poll the in-page `view` (evaluated as-is) until ok(value) accepts it;
  // null on timeout.
  const pollFor = async (view, budgetMs, ok) => {
    const deadline = Date.now() + budgetMs;
    for (;;) {
      const v = await uifTab.evaluate(view).catch(() => null);
      if (v && ok(v)) return v;
      if (Date.now() >= deadline) return null;
      await sleep(250);
    }
  };
  const sawOutBody = async (needle, budgetMs) => {
    const deadline = Date.now() + budgetMs;
    for (;;) {
      if (!(await bodyText()).includes(needle)) return true;
      if (Date.now() >= deadline) return false;
      await sleep(250);
    }
  };
  // The import dialog as it must be gated on (defect 1, 2026-11-02): the
  // body shows `Import addons?` AND a button whose text is exactly
  // `Import` lives INSIDE that dialog. The old gate only asked the body
  // for `Forte_` — true while the PREVIOUS import's rows were listed —
  // so Import was clicked against an absent dialog and the run passed on
  // stale bytes.
  const importDialogView = () => {
    // fx-import-dialog
    const norm = (s) => (s || '').replace(/\s+/g, ' ').trim();
    const ask = 'Import addons?';
    const impBtn = (n) => Array.from(n.querySelectorAll('button')).find(
      (b) => (b.textContent || '').trim() === 'Import'
        && b.getBoundingClientRect().width > 0) || null;
    const askers = Array.from(document.querySelectorAll('body *')).filter(
      (n) => norm(n.textContent).includes(ask));
    // The dialog = the INNERMOST element carrying both the prompt and the
    // exact-text Import button. The heading alone is not a dialog, and an
    // Import control that lives OUTSIDE every prompt-carrying subtree is
    // not the dialog's button (defect 1's blind global clickText hit the
    // site's import control of its own while the dialog stood absent).
    const withBtn = askers.filter((n) => impBtn(n));
    const dialog = withBtn[withBtn.length - 1] || null;
    return { asked: askers.length > 0, present: !!dialog };
  };
  // The console answer is `<printed lines>` interleaved with `› ` echoes of
  // the typed command (live finding 2026-11-02: the echo carries the marker
  // inside print(...) and fooled the old parser). Drop echo lines, then match
  // the marker at the START of a line, e.g. /^FXBAT-CLASSES=(.*)$/m.
  const luaMarked = async (cmd, marker, waitMs) => {
    const out = await lua(cmd, waitMs == null ? 1500 : waitMs);
    const text = String(out == null ? '' : out);
    const printed = text.split('\n')
      .filter((l) => !l.trimStart().startsWith('\u203A')).join('\n');
    const m = printed.match(new RegExp('^' + marker + '(.*)$', 'm'));
    return { line: m ? m[0] : '', printed, text };
  };
  const titleCase = (token) => String(token).charAt(0)
    + String(token).slice(1).toLowerCase();

  // ------------------------------------------------------------- 1. import
  if (!opt.checksOnly) {
    if (opt.fresh) {
      // Replace a previous import: the per-row ✕ on each FORTE row only,
      // 350 ms apart, rescanning until no Forte_ row carries one (the manager's
      // live recipe 2026-11-02; the old one-shot sweep never emptied the list,
      // so the re-import never landed: the site showed `ADDONS · 0/0 active`).
      // The sweep's bytes live at module scope (forteClearSweep) so the mock
      // harness scripts/uif_battery_mock_test.js can drive the SAME code
      // against a fake DOM; `evaluate` serialises the function itself, and
      // inside the page it runs on the page's own document (docArg unset).
      const cleared = await uifTab.evaluate(forteClearSweep)
        .catch(() => ({ visible: -1, matched: 0, removed: 0, left: -1,
          panel: 'sweep evaluate failed' }));
      // 0 removed is honest only when no Forte row was visible to remove.
      const clearOk = forteClearVerdict(cleared);
      add('IMPORT cleared previous Forte_ imports', clearOk,
        'every Forte_ row removed (per-row \u2715, none left); 0 removed '
        + 'only allowed with no Forte row visible IN THE ADDON LIST PANEL',
        'selector: button text \'\u2715\' inside a row matching /Forte[_ ]/ | '
        + `panel: ${cleared.panel} | `
        + `Forte rows visible in the panel before: ${cleared.visible} | `
        + `${cleared.removed} of ${cleared.matched} matched removed, `
        + `${cleared.left} left`);
      await sleep(1500);
    }
    // Tag the LAST accept=".zip" input, after scrubbing stale tags (the
    // 2026-11-02 recipe: the site re-renders its drop zone, the first input is
    // not reliably the live one).
    const tag = await uifTab.evaluate(() => {
      // fx-tag-zip
      const inputs = Array.from(document.querySelectorAll('input[type=file]'));
      for (const i of inputs) i.removeAttribute('data-fxzip');
      const zips = inputs.filter((i) => (i.accept || '').includes('.zip'));
      const target = zips[zips.length - 1];
      if (!target) return 'no-zip-input';
      target.setAttribute('data-fxzip', '1');
      return `tagged last of ${zips.length}`;
    });
    add('IMPORT tag the zip input', String(tag).startsWith('tagged'),
      'the LAST accept=".zip" file input tagged', tag);
    await uifTab.uploadFile('input[data-fxzip="1"]', zip);
    // Defect 1 (2026-11-02): on a larger zip the `Import addons?` dialog
    // appears SEVERAL SECONDS after the upload; the old blind
    // clickText('Import') hit nothing, the import never ran, and every
    // later check read the PREVIOUSLY loaded code — a false PASS. Poll for
    // the dialog itself (its text + its own exact-text `Import` button),
    // then click THAT button in-page. No dialog within the budget = the
    // import did not run: the IMPORT rows FAIL, loudly.
    const dlg = await pollFor(importDialogView, IMPORT_DIALOG_MS, (v) => v.present);
    add('IMPORT the import dialog appears after the upload', !!dlg,
      `the "Import addons?" dialog with its exact-text Import button `
      + `within ${IMPORT_DIALOG_MS} ms of the upload`,
      dlg ? 'present'
        : 'never appeared: the upload opened no import — the import did NOT run');
    const imported = !dlg ? 'skipped: no dialog to press'
      : await uifTab.evaluate(() => {
        // fx-import-click
        const norm = (s) => (s || '').replace(/\s+/g, ' ').trim();
        const ask = 'Import addons?';
        const impBtn = (n) => Array.from(n.querySelectorAll('button')).find(
          (b) => (b.textContent || '').trim() === 'Import'
            && b.getBoundingClientRect().width > 0) || null;
        const askers = Array.from(document.querySelectorAll('body *')).filter(
          (n) => norm(n.textContent).includes(ask));
        const withBtn = askers.filter((n) => impBtn(n));
        const dialog = withBtn[withBtn.length - 1];
        const btn = dialog ? impBtn(dialog) : null;
        if (!btn) return 'no-import-button';
        btn.click();
        return 'clicked the dialog Import button';
      }).catch(() => 'evaluate-failed');
    add('IMPORT pressed the dialog Import button',
      String(imported).startsWith('clicked'),
      'a click on the Import button INSIDE the dialog', imported);
    // The import finishes when the dialog closes; Later / Let's go /
    // /reload must not be pressed while it still stands (they would be
    // the blind clicks defect 1 was made of).
    const gone = await sawOutBody('Import addons?', DIALOG_GONE_MS);
    add('IMPORT the import dialog closes after Import', gone,
      `the "Import addons?" text gone within ${DIALOG_GONE_MS} ms of the press`,
      gone ? 'gone' : 'still open: the import did not complete');
    await sleep(3000);
    await safeClick('Later');                 // the rename prompt
    await safeClick("Let's go");              // the tips dialog
    const reloaded = await safeClick('/reload');
    add('RELOAD pressed /reload', reloaded, "the header's /reload button", 'clickText(/reload)');
    await sleep(reloadWaitMs);                // the 3D scene + all add-ons
    const hdr = (await bodyText()).match(/ADDONS\D{1,3}?(\d+)\s*\/\s*(\d+)/i);
    add('IMPORT the addon header reports the set active',
      !!hdr && Number(hdr[1]) === Number(hdr[2]) && Number(hdr[1]) >= 15,
      'ADDONS · N/N active with N >= 15',
      hdr ? `${hdr[1]}/${hdr[2]} active` : 'no ADDONS · N/N header found');
    if (opt.importOnly) return report(zip, rows);
  }

  // ------------------------------------------------------ 2. CODE live bytes
  // Defect 2 (2026-11-02): every check below reads BEHAVIOUR, and the site
  // keeps serving the previously loaded add-ons when an import did not land
  // — so a green run proved nothing about the bytes just uploaded. Evaluate
  // a marker expression (option `expectMarker`, a Lua expression) against
  // the LIVE engine after /reload; the row passes only when it prints true.
  // Default marker: ForteXorcist.CONST.VERSION, the build constant of
  // addon/Forte_Core/Core/Constants.lua — the shipped bytes carry it (the
  // release stamps only the tocs). DEFAULT_CODE_MARKER === null is the
  // documented state "the repo has no version constant": the row then skips.
  const marker = opt.expectMarker == null
    ? DEFAULT_CODE_MARKER : String(opt.expectMarker);
  const codeRow = 'CODE the live code prints the expected marker true';
  if (!marker) {
    add(codeRow, true, 'skipped: no expectMarker given and the repo carries '
      + 'no version constant to compare', 'skipped');
  } else {
    const code = await luaMarked(
      'local ok,v = pcall(function() return (' + marker + ') end) '
      + 'local out if not ok then out = "error:" .. tostring(v) '
      + 'elseif v then out = "true" else out = "false" end '
      + 'print("FXBAT-CODE=" .. out)',
      'FXBAT-CODE=');
    const mCode = code.printed.match(/^FXBAT-CODE=(\S*)$/m);
    add(codeRow, !!mCode && mCode[1] === 'true',
      `FXBAT-CODE=true for (${marker})`,
      mCode ? mCode[1] : (code.line || '(no printed line)'));
  }

  // ---------------------------------------------------- 3. class add-on set
  // Load-on-demand law (docs/launch-day.md F12): over the nine class add-ons,
  // exactly the player's own is resident. Plain Lua — the console IS Lua.
  const cls = await luaMarked(
    'local L={} local P=(select(2,UnitClass("player")) or ""):upper() '
    + 'for _,c in ipairs({"Druid","Hunter","Mage","Paladin","Priest",'
    + '"Rogue","Shaman","Warlock","Warrior"}) do '
    + 'if C_AddOns.IsAddOnLoaded("Forte_"..c) then L[#L+1]=c end end '
    + 'table.sort(L) print("FXBAT-CLASSES="..table.concat(L,",")'
    + '.." PLAYER="..P)',
    'FXBAT-CLASSES=');
  const mCls = cls.printed.match(/^FXBAT-CLASSES=([A-Za-z,]*)\s+PLAYER=([A-Za-z]+)$/m);
  if (mCls) {
    const loaded = mCls[1] ? mCls[1].split(',').filter(Boolean) : [];
    const player = titleCase(mCls[2]);
    // The site logs a session in as Mage once (PLAN §9 2026-11-02), so a
    // resident Forte_Mage beside the real class is the site's artefact.
    const foreign = loaded.filter((c) => c !== player && c !== 'Mage');
    add('CLASSSET only the player class is resident',
      loaded.includes(player) && foreign.length === 0,
      `${player} only (a resident Mage is tolerated: the site's log-in artefact)`,
      `resident=[${loaded.join(',')}] player=${player}`);
  } else {
    add('CLASSSET only the player class is resident', false,
      'FXBAT-CLASSES= print', cls.line || '(no printed line)');
  }

  // -------------------------------------------------------- 4. module list
  // _moduleOrder is the registration array (Init.lua); `modules` is keyed by
  // it and iterating a key map proved flakier live (2026-11-02).
  const mods = await luaMarked(
    'local L={} for i,n in ipairs(ForteXorcist._moduleOrder or {}) do '
    + 'L[#L+1]=tostring(n) end table.sort(L) '
    + 'print("FXBAT-MODULES="..table.concat(L,","))',
    'FXBAT-MODULES=');
  const mMod = mods.printed.match(/^FXBAT-MODULES=(.*)$/m);
  const modList = mMod ? mMod[1].trim().split(',').filter(Boolean) : [];
  const core = ['Cooldown', 'Locale', 'Log', 'Messages', 'Probe', 'Splash', 'Timer'];
  const missingCore = core.filter((c) => !modList.includes(c));
  add('MODULES the module list prints', !!mMod, 'FXBAT-MODULES= print',
    mods.line || '(no printed line)');
  add('MODULES the always-loaded set is enabled',
    modList.length > 0 && missingCore.length === 0, core.join(','),
    modList.join(','));

  // ------------------------------------------------------ 5. Splash + Messages
  add('CORE Splash and Messages are present',
    modList.includes('Splash') && modList.includes('Messages'),
    'Splash + Messages in the module list', modList.join(','));

  // -------------------------------------------------------------- 6. DB
  // The expected schema is the addon's own DB.SCHEMA_VERSION (v2 since wave 5:
  // the sparse store), so the row never pins a stale number.
  const db = await luaMarked(
    'local d=ForteXorcist.db local v=d and d.version '
    + 'local want=ForteXorcist.DB and ForteXorcist.DB.SCHEMA_VERSION '
    + 'local a=d and d.profiles and d.profiles.active '
    + 'print("FXBAT-DB version="..tostring(v).." want="..tostring(want).." active="..tostring(a) '
    + '.." activen="..(type(a)=="string" and #a>0 and "1" or "0"))',
    'FXBAT-DB');
  const mDb = db.printed.match(/^FXBAT-DB version=(\S+) want=(\S+) active=(\S*) activen=([01])$/m);
  add('DB the schema is the build\'s SCHEMA_VERSION and the active profile is set',
    !!mDb && mDb[1] === mDb[2] && mDb[1] !== 'nil' && mDb[4] === '1',
    'version == DB.SCHEMA_VERSION, activen=1',
    mDb ? `version=${mDb[1]} want=${mDb[2]} active=${mDb[3]}` : (db.line || '(no printed line)'));

  // ----------------------------------- 7. party/raid chat defaults OFF
  // The announce gate counts accepted sends; a ready pop with the shipped
  // defaults must not send anything (review 4 E2: every announce is opt-in).
  const raid = await luaMarked(
    'local A=ForteXorcist.Messages and ForteXorcist.Messages.Announce '
    + 'if not A then print("FXBAT-RAIDMSG absent") else '
    + 'local a=A.counts.sent '
    + 'if ForteXorcist.Fire and ForteXorcist.EVENTS then ForteXorcist.Fire('
    + 'ForteXorcist.EVENTS.COOLDOWN_READY,"Rapid Fire",1.0,nil,nil) end '
    + 'print("FXBAT-RAIDMSG delta="..tostring(A.counts.sent-a)'
    + '.." sent="..tostring(A.counts.sent)) end',
    'FXBAT-RAIDMSG');
  const mRaid = raid.printed.match(/^FXBAT-RAIDMSG delta=(-?\d+) sent=(-?\d+)/m);
  add('RAIDMSG a ready pop sends 0 party/raid lines by default',
    !!mRaid && mRaid[1] === '0' && mRaid[2] === '0',
    'delta=0 sent=0',
    mRaid ? `delta=${mRaid[1]} sent=${mRaid[2]}` : (raid.line || '(no printed line)'));

  // ------------------------------------------------------------- 8. PERSIST
  // One settings write must survive a /reload (SavedVariables round-trip).
  if (opt.persist) {
    const pre = await luaMarked(
      'print("FXBAT-PERSISTPRE value="'
      + '..tostring(ForteXorcist.Settings:Get("Cooldown","Width")))',
      'FXBAT-PERSISTPRE');
    const mPre = pre.printed.match(/^FXBAT-PERSISTPRE value=([-+.\d]+)$/m);
    const prev = mPre ? Number(mPre[1]) : null;
    await luaMarked(
      'ForteXorcist.Settings:Set("Cooldown","Width",333) '
      + 'print("FXBAT-PERSISTSET ok")', 'FXBAT-PERSISTSET');
    await safeClick('/reload');
    await sleep(reloadWaitMs);
    const read = await luaMarked(
      'print("FXBAT-PERSISTREAD value="'
      + '..tostring(ForteXorcist.Settings:Get("Cooldown","Width")))',
      'FXBAT-PERSISTREAD');
    const mRead = read.printed.match(/^FXBAT-PERSISTREAD value=([-+.\d]+|nil)$/m);
    add('PERSIST a settings write survives /reload',
      !!mRead && mRead[1] !== 'nil' && Number(mRead[1]) === 333,
      'Width reads 333 after /reload',
      mRead ? `value=${mRead[1]}` : (read.line || '(no printed line)'));
    // Leave the install exactly as found: write the read value back, or the
    // registered default when the pre-read was not a number.
    const restore = Number.isFinite(prev)
      ? `ForteXorcist.Settings:Set("Cooldown","Width",${prev}) `
        + 'print("FXBAT-PERSISTRESTORED ok")'
      : 'local d=ForteXorcist.Settings:GetDefault("Cooldown","Width") '
        + 'ForteXorcist.Settings:Set("Cooldown","Width",d) '
        + 'print("FXBAT-PERSISTRESTORED default="..tostring(d))';
    await luaMarked(restore, 'FXBAT-PERSISTRESTORED');
  }

  // ---------------------------------------------------------- 9. Lua errors
  // The tab's text is `Errors` or `Errors <count>`: match it in-page
  // (clickText wants an exact label and misses the counted variant).
  const opened = await uifTab.evaluate(() => {
    // fx-errors-tab
    const re = /^Errors\s*\d*$/;
    const els = Array.from(document.querySelectorAll(
      'button,[role="tab"],[role="button"],a,li'));
    for (const el of els) {
      const t = (el.textContent || '').trim().replace(/\s+/g, ' ');
      if (re.test(t) && el.getBoundingClientRect().width > 0) {
        el.click();
        return 'clicked ' + t;
      }
    }
    return 'no-errors-tab';
  }).catch(() => 'evaluate-failed');
  await sleep(800);
  const body = await bodyText();
  const clean = /No Lua errors/i.test(body);
  const forteHits = body.split('\n').filter((l) => l.includes('Forte_')).slice(0, 6);
  add('ERRORS the Errors tab reports no Lua errors',
    String(opened).startsWith('clicked') && clean && forteHits.length === 0,
    'No Lua errors and no Forte_ mention',
    forteHits.length ? forteHits.join(' | ')
      : String(opened) + (clean ? ' + No Lua errors' : ' + tab did not say "No Lua errors"'));

  // ------------------------------------------------------------------ report
  return report(zip, rows);
}

function report(zip, rows) {
  const result = { pass: rows.every((r) => r.pass), zip, rows };
  console.log(`uif_battery: ${result.pass ? 'PASS' : 'FAIL'} (${rows.length} checks)\n`
    + rows.map((r) => `  ${r.pass ? 'PASS' : 'FAIL'}  ${r.name}\n`
      + `          expect: ${r.expect}\n          got:      ${r.got}`).join('\n'));
  return result;
}

// Kernel-friendly publication: the file evaluates to the function, and the
// name is reachable as a global for kernels that eval-then-call. The clear
// sweep and its verdict ride along as properties so the mock harness
// (scripts/uif_battery_mock_test.js) drives the shipped bytes.
if (typeof globalThis !== 'undefined') globalThis.uifBattery = uifBattery;
if (typeof module !== 'undefined' && module.exports) {
  module.exports = uifBattery;
  module.exports.forteClearSweep = forteClearSweep;
  module.exports.forteClearVerdict = forteClearVerdict;
}
uifBattery;
