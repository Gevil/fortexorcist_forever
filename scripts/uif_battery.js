/*
 * scripts/uif_battery.js — the uiforever.com launch battery, ONE async
 * function the MANAGER runs in his browser kernel (PLAN §11.1 slice H2).
 * Never run it from this repo: it drives the site's live UI.
 *
 * Kernel globals it uses (all provided by the manager's kernel):
 *   uifTab                 the open uiforever tab  (.evaluate/.uploadFile)
 *   clickText(text)        clicks the visible control whose text is <text>
 *   lua(cmd, waitMs)       types <cmd> into the site's Lua console, waits,
 *                          returns the console text that came back
 *
 * Run it as:
 *   await uifBattery({ zip: '/tmp/fx_uif.zip' })
 * options:
 *   zip            the release zip to import (default /tmp/fx_uif.zip)
 *   fresh          true = clear previously imported addons (per-row ✕) first
 *   reloadWaitMs   settle time after /reload (default 20000)
 *   importOnly     true = import + reload, skip the checks
 *   checksOnly     true = skip the import (site already loaded), run checks
 *
 * What it proves, in order:
 *   1. IMPORT   the zip is uploaded and Imported, the rename/tips dialogs are
 *               closed, /reload is pressed and the site settles.
 *   2. CLASSSET exactly the player's own Forte_<Class> add-on is resident --
 *               the site's own log-in-as-Mage artifact is tolerated (PLAN §9
 *               2026-11-02 LoD row: the site logs in as Mage once at session
 *               start, so Forte_Mage can be resident beside the real class).
 *   3. MODULES  the module registry prints, and the always-loaded set is in
 *               it (the list is reported verbatim in the result).
 *   4. CORE     the Splash and Messages modules are present.
 *   5. RAIDMSG  a COOLDOWN_READY pop sends 0 party/raid chat lines with the
 *               shipped defaults (every announce gate is opt-in, review 4 E2).
 *   6. ERRORS   the site's Errors tab says "No Lua errors." and names no
 *               Forte_* file.
 *
 * It returns { pass, rows } -- rows = [{ name, pass, expect, got }] -- and
 * console.logs the same as a table. Nothing here raises on a failed check:
 * a fail is a row, not an exception.
 */
async function uifBattery(options) {
  const opt = options || {};
  const zip = opt.zip || '/tmp/fx_uif.zip';
  const reloadWaitMs = opt.reloadWaitMs || 20000;
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
  // The site's console answers a `/run ... print(x)` with a block of text;
  // pull the line that carries our marker, so prompt echo cannot confuse us.
  const luaMarked = async (cmd, marker, waitMs) => {
    const out = await lua(cmd, waitMs || 1500);
    const text = String(out == null ? '' : out);
    const line = text.split('\n').map((l) => l.trim())
      .filter((l) => l.includes(marker)).pop();
    return { line: line || '', text };
  };

  // ------------------------------------------------------------- 1. import
  if (!opt.checksOnly) {
    const tag = await uifTab.evaluate(() => {
      const inputs = Array.from(
        document.querySelectorAll('input[type=file]'));
      const zipInput = inputs.find((i) => (i.accept || '').includes('.zip'));
      if (!zipInput) return 'no-zip-input';
      zipInput.setAttribute('data-fxzip', '1');
      return 'tagged ' + inputs.length + ' file input(s)';
    });
    add('IMPORT tag the zip input', tag === 'tagged 5 file input(s)'
      || String(tag).startsWith('tagged'), 'the accept=".zip" file input tagged', tag);
    if (opt.fresh) {
      // Replace a previous import: the per-row ✕ on each imported addon.
      const removed = await uifTab.evaluate(async () => {
        const btns = Array.from(document.querySelectorAll('button'))
          .filter((b) => (b.textContent || '').trim() === '\u2715');
        for (const b of btns) { b.click(); await new Promise((r) => setTimeout(r, 300)); }
        return btns.length;
      }).catch(() => 0);
      add('IMPORT cleared previous imports', true, 'per-row \u2715 clicked', removed + ' row(s)');
    }
    await uifTab.uploadFile('input[data-fxzip="1"]', zip);
    await sleep(2500);                       // the import dialog lists addons
    const imported = await safeClick('Import');
    add('IMPORT pressed Import', imported, 'the Import button', 'clickText(Import)');
    await sleep(1500);
    await safeClick('Later');                // the rename prompt
    await safeClick("Let's go");             // the tips dialog
    const reloaded = await safeClick('/reload');
    add('RELOAD pressed /reload', reloaded, "the header's /reload button", 'clickText(/reload)');
    await sleep(reloadWaitMs);               // the 3D scene + all add-ons
  }

  // ---------------------------------------------------- 2. class add-on set
  // The F12 probe (docs/launch-day.md): load-on-demand means exactly the
  // player's class add-on may be resident.
  const cls = await luaMarked(
    '/run local L={} for c,n in pairs(ForteXorcist.CLASS_ADDONS or {}) do '
    + 'if C_AddOns.IsAddOnLoaded(n) then L[#L+1]=c end end '
    + 'table.sort(L) print("FXBAT-CLASSES="..table.concat(L,",")'
    + '.." PLAYER="..tostring(ForteXorcist._playerClass))',
    'FXBAT-CLASSES=');
  const mCls = cls.line.match(/FXBAT-CLASSES=([A-Z,]*)\s*PLAYER=(\w+)/);
  if (mCls) {
    const loaded = mCls[1] ? mCls[1].split(',') : [];
    const player = mCls[2];
    // Load-on-demand law: only the player's own class add-on may be resident.
    // The site logs a session in as Mage once (PLAN §9 2026-11-02), so a
    // resident Forte_Mage beside the real class is the site's artefact.
    const foreign = loaded.filter((c) => c !== player && c !== 'MAGE');
    add('CLASSSET only the player class is resident',
      loaded.includes(player) && foreign.length === 0,
      `${player} only (a resident MAGE is tolerated: the site's log-in artefact)`,
      `resident=[${loaded.join(',')}] player=${player}`);
  } else {
    add('CLASSSET only the player class is resident', false,
      'FXBAT-CLASSES= print', cls.line || '(no console line)');
  }

  // -------------------------------------------------------- 3. module list
  const mods = await luaMarked(
    '/run local L={} for n in pairs(ForteXorcist.modules or {}) do L[#L+1]=n end '
    + 'table.sort(L) print("FXBAT-MODULES="..table.concat(L,","))',
    'FXBAT-MODULES=');
  const mMod = mods.line.match(/FXBAT-MODULES=(.*)$/);
  const modList = mMod ? mMod[1].trim().split(',').filter(Boolean) : [];
  const core = ['Cooldown', 'Messages', 'Probe', 'Splash', 'Timer'];
  const missingCore = core.filter((c) => !modList.includes(c));
  add('MODULES the module list prints', !!mMod, 'FXBAT-MODULES= print',
    mods.line || '(no console line)');
  add('MODULES the always-loaded set is enabled',
    modList.length > 0 && missingCore.length === 0, core.join(','),
    modList.join(','));

  // ----------------------------------------------------- 4. Splash + Messages
  add('CORE Splash and Messages are present',
    modList.includes('Splash') && modList.includes('Messages'),
    'Splash + Messages in the module list', modList.join(','));

  // ------------------------------------------ 5. party/raid chat defaults OFF
  // The announce gate counts accepted sends; a ready pop with the shipped
  // defaults must not send anything (review 4 E2: every announce is opt-in).
  const raid = await luaMarked(
    '/run local A=ForteXorcist.Messages and ForteXorcist.Messages.Announce '
    + 'if not A then print("FXBAT-RAIDMSG absent") else '
    + 'local a=A.counts.sent '
    + 'if ForteXorcist.Fire and ForteXorcist.EVENTS then ForteXorcist.Fire('
    + 'ForteXorcist.EVENTS.COOLDOWN_READY,"Rapid Fire",1.0,nil,nil) end '
    + 'print("FXBAT-RAIDMSG delta="..tostring(A.counts.sent-a)'
    + '.." sent="..tostring(A.counts.sent)) end',
    'FXBAT-RAIDMSG');
  const mRaid = raid.line.match(/delta=(-?\d+).*sent=(-?\d+)/);
  add('RAIDMSG a ready pop sends 0 party/raid lines by default',
    !!mRaid && mRaid[1] === '0' && mRaid[2] === '0',
    'delta=0 sent=0',
    mRaid ? `delta=${mRaid[1]} sent=${mRaid[2]}` : (raid.line || '(no console line)'));

  // ---------------------------------------------------------- 6. Lua errors
  const errorsOpened = await safeClick('Errors');
  const body = String(await uifTab.evaluate(() => document.body.innerText));
  const clean = /No Lua errors\./i.test(body);
  const forteHits = body.split('\n')
    .filter((l) => /Forte_[A-Za-z]+\b.*(\.lua|\.toc)/.test(l)).slice(0, 6);
  add('ERRORS the Errors tab reports no Lua errors',
    errorsOpened && clean && forteHits.length === 0,
    'No Lua errors. and no Forte_* mention',
    forteHits.length ? forteHits.join(' | ')
      : (clean ? 'No Lua errors.' : 'the tab did not say "No Lua errors."'));

  // ------------------------------------------------------------------ report
  const result = {
    pass: rows.every((r) => r.pass),
    zip,
    rows,
  };
  console.log(`uif_battery: ${result.pass ? 'PASS' : 'FAIL'} (${rows.length} checks)\n`
    + rows.map((r) => `  ${r.pass ? 'PASS' : 'FAIL'}  ${r.name}\n`
      + `          expect: ${r.expect}\n          got:      ${r.got}`).join('\n'));
  return result;
}

// Kernel-friendly publication: the file evaluates to the function, and the
// name is reachable as a global for kernels that eval-then-call.
if (typeof globalThis !== 'undefined') globalThis.uifBattery = uifBattery;
if (typeof module !== 'undefined' && module.exports) module.exports = uifBattery;
uifBattery;
