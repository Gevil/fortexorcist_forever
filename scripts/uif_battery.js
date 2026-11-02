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
 *                  (per-row ✕, 350 ms apart, until none remain)
 *   reloadWaitMs   settle time after /reload (default 20000)
 *   importOnly     true = import + reload, skip the checks
 *   checksOnly     true = skip the import (site already loaded), run checks
 *   persist        true = also run the PERSIST row (writes one setting,
 *                  /reloads, reads it back, restores the old value)
 *
 * What it proves, in order:
 *   1. IMPORT   the manager's live recipe (2026-11-02): clear the old Forte_
 *               rows -> tag the LAST .zip file input -> upload -> the dialog
 *               lists the zip's addons (body text grows a Forte_ mention,
 *               polled up to 8 s) -> Import -> Later -> Let's go -> /reload
 *               -> the header reads `ADDONS · N/N active` with N >= 15.
 *   2. CLASSSET exactly the player's own Forte_<Class> add-on is resident,
 *               over the nine class add-ons; the site's own log-in-as-Mage
 *               artifact is tolerated (PLAN §9 2026-11-02 LoD row).
 *   3. MODULES  ForteXorcist._moduleOrder prints (a live-verified array,
 *               `Locale,Probe,Splash,Cooldown,Timer,Messages`), and the
 *               always-loaded set Cooldown,Locale,Messages,Probe,Splash,
 *               Timer is in it.
 *   4. CORE     the Splash and Messages modules are present.
 *   5. DB       ForteXorcist.db.version == 1 and db.profiles.active is set
 *               (the H3 profiles schema).
 *   6. RAIDMSG  a COOLDOWN_READY pop sends 0 party/raid chat lines with the
 *               shipped defaults (every announce gate is opt-in, review 4 E2).
 *   7. PERSIST  (opt-in `persist`) Settings:Set Cooldown Width 333 ->
 *               /reload -> reads back 333 -> restores the old value.
 *   8. ERRORS   the Errors tab (its text matches /^Errors\s*\d*$/) says
 *               "No Lua errors" and no body line mentions Forte_.
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
  const bodyText = async () =>
    String(await uifTab.evaluate(() => document.body.innerText));
  const sawInBody = async (needle, budgetMs) => {
    const deadline = Date.now() + budgetMs;
    for (;;) {
      if ((await bodyText()).includes(needle)) return true;
      if (Date.now() >= deadline) return false;
      await sleep(250);
    }
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
      const cleared = await uifTab.evaluate(async () => {
        // fx-clear-forte
        const nap = (ms) => new Promise((r) => setTimeout(r, ms));
        const xText = (b) => (b.textContent || '').trim() === '\u2715';
        const rowOf = (b) => {
          // Widest ancestor that still contains exactly this one ✕: the row.
          let n = b.parentElement; let last = null;
          while (n) {
            const xs = Array.from(n.querySelectorAll('button')).filter(xText);
            if (xs.length !== 1) break;
            last = n; n = n.parentElement;
          }
          return last || b.parentElement;
        };
        const targets = () => Array.from(document.querySelectorAll('button'))
          .filter(xText).filter((b) => {
            const row = rowOf(b);
            return /\bForte_/.test((row && row.textContent) || '');
          });
        let removed = 0;
        for (let guard = 0; guard < 80; guard++) {
          const t = targets()[0];
          if (!t) break;
          t.click();
          removed += 1;
          await nap(350);
        }
        return { removed, left: targets().length };
      }).catch(() => ({ removed: 0, left: -1 }));
      add('IMPORT cleared previous Forte_ imports', cleared.left === 0,
        'every Forte_ row removed (per-row \u2715, none left)',
        `${cleared.removed} removed, ${cleared.left} left`);
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
    // The import dialog lists the zip's addons: the body text grows a
    // Forte_ mention. Poll up to 8 s (a 2500 ms fixed sleep raced it on the
    // 2026-11-02 run and Import was pressed against an empty dialog).
    const listed = await sawInBody('Forte_', 8000);
    add('IMPORT the import dialog lists the addons', listed,
      'body text mentions Forte_ within 8000 ms of the upload',
      listed ? 'seen' : 'never seen');
    const imported = await safeClick('Import');
    add('IMPORT pressed Import', imported, 'the Import button', 'clickText(Import)');
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

  // ---------------------------------------------------- 2. class add-on set
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

  // -------------------------------------------------------- 3. module list
  // _moduleOrder is the registration array (Init.lua); `modules` is keyed by
  // it and iterating a key map proved flakier live (2026-11-02).
  const mods = await luaMarked(
    'local L={} for i,n in ipairs(ForteXorcist._moduleOrder or {}) do '
    + 'L[#L+1]=tostring(n) end table.sort(L) '
    + 'print("FXBAT-MODULES="..table.concat(L,","))',
    'FXBAT-MODULES=');
  const mMod = mods.printed.match(/^FXBAT-MODULES=(.*)$/m);
  const modList = mMod ? mMod[1].trim().split(',').filter(Boolean) : [];
  const core = ['Cooldown', 'Locale', 'Messages', 'Probe', 'Splash', 'Timer'];
  const missingCore = core.filter((c) => !modList.includes(c));
  add('MODULES the module list prints', !!mMod, 'FXBAT-MODULES= print',
    mods.line || '(no printed line)');
  add('MODULES the always-loaded set is enabled',
    modList.length > 0 && missingCore.length === 0, core.join(','),
    modList.join(','));

  // ----------------------------------------------------- 4. Splash + Messages
  add('CORE Splash and Messages are present',
    modList.includes('Splash') && modList.includes('Messages'),
    'Splash + Messages in the module list', modList.join(','));

  // ------------------------------------------------------------- 5. DB
  const db = await luaMarked(
    'local d=ForteXorcist.db local v=d and d.version '
    + 'local a=d and d.profiles and d.profiles.active '
    + 'print("FXBAT-DB version="..tostring(v).." active="..tostring(a) '
    + '.." activen="..(type(a)=="string" and #a>0 and "1" or "0"))',
    'FXBAT-DB');
  const mDb = db.printed.match(/^FXBAT-DB version=(\S+) active=(\S*) activen=([01])$/m);
  add('DB the schema is v1 and the active profile is set',
    !!mDb && mDb[1] === '1' && mDb[3] === '1',
    'version=1 activen=1',
    mDb ? `version=${mDb[1]} active=${mDb[2]}` : (db.line || '(no printed line)'));

  // ------------------------------------------ 6. party/raid chat defaults OFF
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

  // ------------------------------------------------------------ 7. PERSIST
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

  // ---------------------------------------------------------- 8. Lua errors
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
// name is reachable as a global for kernels that eval-then-call.
if (typeof globalThis !== 'undefined') globalThis.uifBattery = uifBattery;
if (typeof module !== 'undefined' && module.exports) module.exports = uifBattery;
uifBattery;
