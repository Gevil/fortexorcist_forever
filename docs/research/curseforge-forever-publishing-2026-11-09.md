# Publishing ForteXorcist 1.0.0 to CurseForge (WoW Forever), Wago and GitHub Releases

Researched 2026-11-09 by `RsrchCurseForge`. Read-only: nothing in the repo was changed except this note.
The one experiment (packager dry run) ran on a throwaway clone, `/tmp/fxpkg` (`git clone --no-hardlinks`), with `-d` (no upload).

Evidence tags: **[V]** = read on a fetched page or API response (URL + date given), **[D]** = derived from local code/files,
**[T]** = observed in my own packager test run, **[I]** = inference, **[UNVERIFIED]** = could not confirm.
All web pages below were fetched 2026-11-09.

---

## 0. Short answers

| Question | Answer |
|---|---|
| Is Forever a CurseForge target? | **Yes.** It is a separate *Flavor* ("Forever") with game version **1.60.1**, filterable on the site and selectable as an installation in the CurseForge app. |
| Forever game-version *type* id | **88568** (hard-coded in the BigWigs packager, and used in CurseForge's own site search URLs). |
| Forever game-version *id* for "1.60.1" | **Not obtainable without an author API token** (every `/api/game/...` call returns 401 anonymously). One `curl` + `jq` command in §3.3 returns it. The packager looks it up itself, so you never need to hard-code it. |
| Current API endpoint | Upload: `POST https://wow.curseforge.com/api/projects/{projectId}/upload-file`. Version list: `GET https://wow.curseforge.com/api/game/wow/versions` (what the packager uses today). The older generic `/api/game/versions` still answers (401, not 404) as well. Header `X-Api-Token`. |
| Best automation | **BigWigs packager** (`BigWigsMods/packager@v2`, v2.7.0 of 2026-11-05 already maps `16001` -> `forever` -> CurseForge type 88568, Wago `forever`). I ran it on a clone: it produced a correct 16-folder zip tagged `1.60.1`. Needs a `.pkgmeta` with `move-folders` because our addons live under `addon/`. |
| Owner-only | CurseForge/Wago accounts, creating the two projects, logo/screenshots, API tokens, GitHub secrets, tag push. See §7. |

---

## 1. Forever on CurseForge, Wago, WowUp, other managers

### 1.1 CurseForge
- **[V]** CurseForge's own blog tells players: "Open CurseForge, choose your **Forever live installation**, and check for addon updates", and gives the folder `World of Warcraft\_forever_\Interface\AddOns`; "In case the CurseForge app does not auto-recognize the addons, make sure to manually scan the addons folder." — *How to Migrate WoW Forever Addons from Beta to Live*, https://blog.curseforge.com/wow-forever-migrate-addons-beta-to-live/ (Oct 25 2026, modified Oct 29).
- **[V]** The WoW search page has a **Flavor** filter: Retail, Classic, Classic TBC, **Forever**, MoP Classic, WotLK Classic, Cataclysm Classic, Titan Reforged Classic — https://www.curseforge.com/wow/search?class=addons&page=2&pageSize=50&sortBy=relevancy&categories=achievements.
- **[V]** Forever files are tagged with game version **1.60.1** and flavor **Forever**. Example, Forever Cooldown Manager v0.8.0-forever: "Flavors: Forever", "Supported game versions: 1.60.1", type R (release) — https://www.curseforge.com/wow/addons/forever-cooldown-manager/files/8982464.
- **[V]** Multi-flavor single files are normal. EllesmereUI's file list has game-version filter `12.1.5 … 12.0.0, 1.60.1` and flavor filter `Retail / Forever`; each file shows "12.1.5+6 | Retail+ 1" (the "+1" is Forever) — https://www.curseforge.com/wow/addons/ellesmereui/files/all. Cooldown Master ships one install for Retail, Era, TBC, MoP and Forever (its page says "runs on … WoW Forever from one install") — https://www.curseforge.com/wow/addons/cooldown-master.
- **[V]** Site-wide Forever filter URL used by third-party guides: `https://www.curseforge.com/wow/search?class=addons&gameVersionTypeId=88568` (https://wowforeverinfo.com/guides/addons, "Updated 9 Nov"). Same number as the packager constant (§1.5). **[I]** So `88568` is the "Forever" version *type*; "1.60.1" is one version inside it.
- **[UNVERIFIED]** Auctionator Forever: the page returns HTTP 403 to my fetcher; I did not see its file list. CooldownMaster, EllesmereUI and Forever Cooldown Manager were checked instead.

### 1.2 Where the install goes
- **[V]** `_forever_` (see blog above). The repo's own AGENTS.md says the same (`<WoW install>/_forever_/`) **[D]**.
- **[V]** CurseForge's "This addon might be corrupt (Belongs to…)" warning means "the game flavor the addon's file is compatible with does not match the game flavor it is installed to" — https://support.curseforge.com/en/support/solutions/articles/9000198422-world-of-warcraft-addons-faq-and-troubleshooting (modified 2026-07-07). **[I]** So tag the file *Forever / 1.60.1 only* (we are not a Retail addon) or Retail installs may show the warning.

### 1.3 Wago
- **[V]** `https://addons.wago.io/api/data/game` returns patch lists per game type, including `"forever": ["1.60.1"]` (fetched via curl, 2026-11-09; other keys: `bc, cata, classic, mop, retail, titan, wotlk`).
- **[V]** Several Forever addons are listed on Wago (ForeverAuras, ForeverForge, ForeverDB, EllesmereUI Forever Essentials, …) — search results `addons.wago.io/addons/...`. Note ForeverUI's Wago page now says "Moved: ForeverUI is no longer on Wago" — https://addons.wago.io/addons/foreverui (so Wago is optional, authors do leave).
- **[UNVERIFIED]** That the Wago *app* installs to `_forever_`: only a secondary guide says "Forever is recognized by … the Wago App" (https://forevermeta.me/en/guides/wow-forever-addons-interface, 2026-10-23). Wago's own page for this was a client-rendered SPA and did not load in my fetcher.

### 1.4 WowUp, Ajour
- **[V]** WowUp **2.24.0** (2026-10-10) release note: "WoW Forever support" — GitHub API `releases/tags/v2.24.0`. WowUp 2.25.4 (2026-11-03) is current stable.
- **[V]** WowUp's GitHub provider source (`github-addon-provider.ts`, master): (a) prefers a **`release.json`** asset (BigWigs format) with `flavor: "forever"`; (b) otherwise matches the zip by file name `/[-_](forever|camelot)\.zip$/i`; (c) treats an unsuffixed zip as **Retail**; (d) looks only at the most recent releases (a related issue says 5: https://github.com/rusty-key/spoken-wow/issues/881, 2026-11-04) and treats `prerelease` as Beta channel. **[D→action]** Our existing GitHub release `v0.1.0-dev` has asset `ForteXorcist-0.1.0-dev.zip` (no suffix, no `release.json`) — WowUp would **not** offer it to a Forever install. The 1.0.0 release must carry `-forever.zip` and/or `release.json`; the packager does both (§4).
- **[UNVERIFIED]** Ajour: no Forever evidence found in two searches. Do not promise it.

### 1.5 How existing Forever addons get there
- **[V]** Wheelbarrel00 (Cooldown Master, EQ) publishes the *same zip* to CurseForge and GitHub Releases (the CF page embeds a `shields.io/github/v/release/...` badge) and flags Forever as one more flavor; description is a long structured README (§6).
- **[V]** Forever Cooldown Manager's CF "What's new" is a packager-generated changelog with "Full Changelog / Previous Releases" GitHub links — typical output of `BigWigsMods/packager` with a GitHub remote.
- **[V]** packager `release.sh` on master (v2.7.0, 2026-11-05) maps interface `16???` -> game type `forever`, flavor name `camelot`/`forever`, and CurseForge `forever) game_id=88568` (`release.sh` lines ~212, 2905). It also writes `{"flavor":"forever","interface":16001}` into `release.json` for GitHub releases (line ~3340).

---

## 2. CurseForge project creation (WoW addon)

Source: *Creating and Submitting a Project* (modified 2024-09-24), https://support.curseforge.com/support/solutions/articles/9000197241-creating-and-submitting-a-project; *Project Submission Guide and Tips* (2024-12-23), https://support.curseforge.com/support/solutions/articles/9000199552; *Moderation Policies* (modified 2026-10-22), https://support.curseforge.com/support/solutions/articles/9000197279-project-and-modpack-moderation-policies. All **[V]** unless marked.

| Field | Rule |
|---|---|
| Account | Register/log in to CurseForge; start at `https://authors.curseforge.com/#/projects/create/choose-game`, pick *World of Warcraft*. **No project-creation endpoint is documented in the Upload API article** (it covers game versions, file upload/update, maven, localization only) — creating the project is a web-UI step. |
| Name | Unique (taken = rejected). English. Moderation: "Names should not contain game name, class name versions, file versions…". Avoid version numbers and the word "addon". **[I]** Existing live Forever projects use "Forever" in the name (Forever Cooldown Manager, Tweaks Forever, Shortest Path Forever, ForeverPlusPlus), so it is tolerated, but plain **"ForteXorcist"** is the safest moderation-wise if the slug is free **[UNVERIFIED — `www.curseforge.com/wow/addons/fortexorcist` is 403 to me]**. Related projects already exist: "ForteXorcist TBC Classic" (listed as by `Gevil_Burx`; **[UNVERIFIED]** whether that is the owner) and "ForteXorcist TBC Classic Anniversary" (by `Exotelis`, 0 followers, 450 downloads; https://www.curseforge.com/wow/addons/fortexorcist-tbc-classic-anniversary). They are forks of the 2012 code, ours is a rewrite, so a separate project is correct. |
| Summary | One sentence on what it does (not who made it); avoid copying the description. |
| Description | English first, must be functional (what it adds), not generic. Forks must credit/link original. Donation/personal links only at the bottom, reasonable size. **Third-party download links not allowed** (do not put a "download from GitHub" button; linking the repo for source/issues is normal). Editor choice at creation: WYSIWYG or **Markdown**. |
| License | Dropdown of common licenses or Custom. For ported/forked code: license must allow it and follow suit (GPL). Ours: **GPL-3.0** (LICENSE; original ForteXorcist is GPL-3.0 per `addon/Forte_Core/ATTRIBUTION.md` **[D]**). The exact label of the GPL-3 entry in the dropdown **[UNVERIFIED]**. If moderation sees a conflict between repo and page, the CF page wins. |
| Class / main category | Class = *Addons*. Main category list (from the search filters): Achievements, Action Bars, Artwork, Auction & Economy, Audio & Video, Bags & Inventory, Boss Encounters, **Buffs & Debuffs**, Chat & Communication, Class (Death Knight … Warrior), Combat (Caster, Damage Dealer, Healer, Tank), Companions, Data Export, Development Tools, Garrison, Guild, Housing, Libraries, Mail, Map & Minimap, Minigames, Miscellaneous, Plugins, Professions, PvP, Quests & Leveling, Roleplay, Tooltip, Twitch Integration. **[I] Proposed:** main **Buffs & Debuffs** (the 2012 original sits in WoWInterface's "Buff, Debuff, Spell"), additional (max 4, must be relevant) **Hunter**, **Warlock**, **Combat -> Damage Dealer**. |
| Logo | PNG, ≥400×400, 1:1, not a solid colour, **original graphic** (not the game logo or an existing project avatar); known bug with webp. Needs a file the owner supplies. The original's `ForteXorcist.blp` branding is GPL but is a BLP and is Xus's art — **[I]** make a fresh PNG. |
| Screenshots | Only *required* for texture packs/sims, not addons; strongly recommended (in-game images). The repo already has `docs/demo/*.png|gif` **[D]** (README references them); upload them to the project's *Images* tab or embed. |
| Comments / issues / source | Enable comments (recommended); set Issue tracker = `https://github.com/Gevil/fortexorcist_forever/issues` and Source = the repo (project settings tabs). |
| Moderation | New project goes to "moderators" after the first file is uploaded; file shows "Under Review"; may come back with "changes required" — do not delete and re-upload. Hours: "Project/File moderation is done between 8AM to 3PM CET (11PM-6AM PST), 7 days a week, excluding holidays… First in, First out" — https://support.curseforge.com/en/support/solutions/articles/9000198422 (2026-07-07). **No SLA published**; plan for at least one CET business day **[I]**. |
| App sync | "Projects must have at least one 'Release' file before they sync to the CurseForge App"; beta/alpha files only sync if the user opts in. So 1.0.0 = **Release** type. |
| File rules | `.zip` only (real zip), < 2 GB. Changelog required per file (Fair Play rule: "Files must include a change log describing the changes from the previous version"; no re-uploads without changes). |
| Experimental | A project flagged *Experimental* does not sync with the ecosystem — leave it off. |

### 2.1 Multi-folder addons, "main file", modules
- **[V]** CurseForge multi-TOC article: "Every TOC file needs to start with the addon name used in the parent folder (addon_name.toc in the addon_name folder). If you don't use the same name — the CurseForge validator may fail the upload or the addon will not be recognized by the Blizzard client." — https://support.curseforge.com/support/solutions/articles/9000209856-multi-toc-for-world-of-warcraft-addons (modified 2024-02-28). **[D]** All 16 of our folders have `Forte_X.toc` + `Forte_X_Camelot.toc` — OK.
- **[V]** A CurseForge file object has `modules: [{name, fingerprint}]` — https://docs.curseforge.com/rest-api (File / FileModule schema). **[I]** For WoW these are the top-level folders of the zip; the app tracks them by fingerprint. There is no author-facing "main file + modules" setting in the project form; one zip with several top-level folders is the standard (Details, DBM, ElvUI) and is exactly what the packager builds.
- **[V]** The "Zip formats: must not include root folders" rule on the moderation page is under *Minecraft specific*. For WoW the zip **must** have the addon folders at its root (so `Forte_Core/Forte_Core.toc` …). **[T]** The packager output has exactly that.
- Bundled libraries: **none** (no `Libs/` in the repo **[D]**), so no `externals`, no `embedded-libraries`, no nolib package. Bundled third-party *assets* (textures/sound from the 2012 GPL original; URW Gothic AGPL font) are credited in `Forte_Core/ATTRIBUTION.md` — repeat the credit in the description (moderation: proper credit required for other people's content).
- Optional in-game grouping: **[V]** TOC `## Group: <main addon>` groups addons as indented entries in the AddOn List; auto-detection only pairs addons where one name is a complete *prefix* of the other (https://warcraft.wiki.gg/wiki/TOC_format). `Forte_Core` is not a prefix of `Forte_Hunter`, so auto-grouping probably does not happen **[I]**; add `## Group: Forte_Core` to the other 15 TOCs if you want one folded entry (Forever claims "all Modern changes up to 12.1.5"; Group arrived in 11.1.0, so it should work **[I]**).

### 2.2 Changelog formats
**[V]** Upload API `changelogType`: `text` (default) | `html` | `markdown`. The packager sends the changelog as markdown when `manual-changelog` has `markup-type: markdown` (`.pkgmeta` wiki).

---

## 3. Upload methods

### 3.1 Web uploader
**[V]** Project dashboard -> *Files* tab -> upload `.zip`; fields: Display Name, Release Options (go live on approval or at a time you choose), Release Type (Release/Beta/Alpha), Changelog, Supported Version(s) (multi), Related Projects — Creating and Submitting a Project (above). For us: Supported version = **Forever -> 1.60.1** (and nothing else).

### 3.2 REST upload API
Source: *CurseForge Upload API* (modified 2026-09-27), https://support.curseforge.com/en/support/solutions/articles/9000197321-curseforge-upload-api **[V]**.

- Token: https://authors.curseforge.com/#/settings/api-tokens . Auth header `X-Api-Token: <token>` (or `?token=`).
- "URIs relative to the site the project is on"; for WoW the packager uses `https://wow.curseforge.com` **[V release.sh]**. **[T]** I confirmed: `GET https://wow.curseforge.com/api/game/versions` and `/api/game/wow/versions` -> HTTP 401 "You must provide an API token using the `X-Api-Token` header…", a nonexistent path -> 404, `POST /api/projects/1/upload-file` with no body -> 411. So both paths exist; `www.curseforge.com/api/...` answers the same.
- Upload: `POST /api/projects/{projectId}/upload-file`, `multipart/form-data` with `metadata` (JSON string) and `file`:
  ```json
  {
    "changelog": "markdown text",
    "changelogType": "markdown",
    "displayName": "v1.0.0-forever",
    "gameVersions": [ <id of 1.60.1> ],
    "releaseType": "release",
    "isMarkedForManualRelease": false,
    "relations": { "projects": [] }
  }
  ```
  Documented extras: `gameVersionNames: ["1.60.1"]` (names instead of ids — **new in the 2026 article**), `parentFileID`, `releaseType` = `alpha|beta|release`. Response `{ "id": <fileId> }`. `POST /api/projects/{id}/update-file` edits `fileID` metadata afterwards.
- Project id: shown in the project's overview URL / "About Project" box.
- **Game versions**: `GET {site}/api/game/wow/versions` returns objects `{id, gameVersionTypeID, name, slug}`. The packager picks Forever by `gameVersionTypeID == 88568` and `name == "1.60.1"`:
  ```bash
  curl -sS -H "X-Api-Token: $CF_API_TOKEN" https://wow.curseforge.com/api/game/wow/versions \
    | jq '.[] | select(.gameVersionTypeID==88568)'
  ```
  I could not run this (no token). Result = the Forever game-version id(s). **[I]** `gameVersionNames:["1.60.1"]` is unambiguous because Classic Era names are 1.15.x, but the docs do not say how a name that occurs in several types is resolved; prefer the packager (which uses the type id) or ids.
- Token handling: do not put it in the repo; GitHub secret only.

### 3.3 Minimal manual `curl` (if not using the packager)
```bash
ID=<forever 1.60.1 version id>   # from the jq command above
curl -sS -H "X-Api-Token: $CF_API_TOKEN" \
  -F 'metadata={"changelog":"…","changelogType":"markdown","displayName":"v1.0.0-forever","gameVersions":['$ID'],"releaseType":"release"};type=application/json' \
  -F "file=@ForteXorcist-v1.0.0-forever.zip" \
  https://wow.curseforge.com/api/projects/<projectId>/upload-file
```
**[UNVERIFIED]** whether the API accepts the *first* upload to a project that is not yet approved; the web uploader does (that is how a project gets submitted). Safest: first zip through the web uploader, later ones through CI.

---

## 4. BigWigs packager (tested)

Sources: README https://github.com/BigWigsMods/packager (fetched `raw.githubusercontent.com/.../master/README.md`), wiki pages *Preparing-the-PackageMeta-File* and *GitHub-Actions-workflow*, `release.sh` master; latest release **v2.7.0, 2026-11-05** (GitHub API). **[V]**

### 4.1 What it already knows about Forever
- README's multiple-interface example literally contains `16001` "and Forever Beta"; `release.sh` maps `16???` -> `forever`; `-g forever` or `-g camelot` selects it; `-g 1.60.1` (any `1.6x.y`) = Forever; CF type 88568; Wago type `forever`; GitHub `release.json` flavor `forever`; WoWInterface: **unsupported -> skipped** (warning "No WoWInterface game type match for forever") **[V release.sh ~3030]**.
- TOC suffix recognition list in the packager: `Mainline|Classic|Vanilla|BCC|TBC|Wrath|WOTLKC|Cata|Mists|Camelot`. **`_Forever.toc` is not in that list** (the game accepts `_Forever` as an alias of `_Camelot` — https://warcraft.wiki.gg/wiki/TOC_format). **[D]** We ship `X_Camelot.toc`, so we are inside the packager's list. Keep `_Camelot`; do not rename to `_Forever`.
- Env vars: `CF_API_TOKEN` (`CF_API_KEY` still read, "deprecated"), `WAGO_API_TOKEN`, `WOWI_API_TOKEN`, `GH_API_TOKEN` (`GITHUB_API_TOKEN`, `GITHUB_OAUTH` deprecated) — `release.sh` lines 506-512. The wiki workflow example still shows `CF_API_KEY`/`GITHUB_OAUTH`; both work, use the new names.
- Release type from the tag: tag containing `alpha` -> alpha, `beta` -> beta, otherwise release; no tag at HEAD -> alpha (`release.sh` ~854-863). On GitHub: `prerelease: true` for anything not "release".
- Packager aborts if a newer tag points at HEAD ("Found future tag"), and in Actions skips push-branch duplicates. Tags should be **annotated** (wiki).

### 4.2 Our problem: repo layout
The packager wants the main addon's TOC at repo root, but ours live in `addon/Forte_*/`. Solution that worked **[T]**: `package-as: Forte_Core` + one `move-folders` line per addon folder (key = `Forte_Core/addon/<Folder>`, value = `<Folder>`), plus `ignore` for everything that is not the addon. The `move-folders` value without a `/` registers the folder's TOCs for interface/game-version detection (`toc_root_paths`, release.sh ~1118-1122), so `X-Curse-Project-ID`/`X-Wago-ID` are read from `Forte_Core`'s TOC.

**Test results [T]** (clone of `dd7f83d`, no uploads):
- exit 0, 7 s; "Game version: 1.60.1"; "Build type: non-retail version-forever non-alpha non-debug" on tag `v1.0.0` (alpha when untagged).
- Zip root = exactly the 16 addon folders; no `addon/` leftover, no `tests/`, no `*.otf`, no docs/tools/scripts; 202 zip entries (153 files).
- `-n "ForteXorcist-{project-version}{classic}:{project-version}{classic}"` -> `ForteXorcist-v1.0.0-forever.zip`, label `v1.0.0-forever` (the `-forever` suffix is also what WowUp matches). Without `-n`: `Forte_Core-v1.0.0-forever.zip`. With only one template (no `:`) the label became the file name too — use the colon form.
- `## Version: @project-version@` was expanded to `v1.0.0` inside the zip; `## X-Curse-Project-ID`/`## X-Wago-ID` were parsed (`CurseForge ID: 1234567`, `Wago ID: AbCd1234` with dummy values).
- `manual-changelog` reads a file from the checkout even if that file is in `ignore` (prints "Using manual changelog …"). **Gotcha:** `CHANGELOG.md` is 512 lines; the packager would send *all of it* as the CF/GitHub changelog of every release. Use a small generated per-release file (e.g. `RELEASE_NOTES.md`, §9) instead.
- Rebuilding into an existing `.release` with `-o` produced a mess (nested `Forte_Core/addon/...`, "mv: cannot overwrite"); always build into a fresh `.release` (delete it first; add `/.release/` to `.gitignore`).
- Old `release.py` vs packager: both exclude tests/otf. `release.py` zip (dist/ForteXorcist-0.1.0.zip, 133 files) was older than HEAD so the 20-file difference is just newer commits. Only one of the two should remain (see §10).

### 4.3 GitHub Actions
Wiki workflow **[V]** (permissions `contents: write`; `fetch-depth: 0`; tag trigger; secrets as env). Our version in §9.

---

## 5. Wago Addons (additional channel)

- **[V]** Docs https://docs.wago.io/ : API key from https://addons.wago.io/account/apikeys; header `Authorization: Bearer <key>`; `POST https://addons.wago.io/api/projects/<projectId>/version` multipart with `metadata` + `file`; metadata `{label, stability: stable|beta|alpha, changelog (markdown), supported_<type>_patch(es)}`; project id is "8-digit alphanumeric", on https://addons.wago.io/developers ; TOC line `## X-Wago-ID: …`; packager supported.
- **[V]** The packager sends `supported_forever_patches: ["1.60.1"]` for Forever (`release.sh` ~3170: `"supported_${wago_type}_patches"`, with `wago_type=forever`). The Wago doc only shows the older singular `supported_*_patch` keys for retail/wotlk/bc/classic; Forever appears in the live `api/data/game` list (§1.3). **[UNVERIFIED]** that Wago accepts a *manual* `supported_forever_patches` key outside the packager; use the packager.
- **[UNVERIFIED]** Wago project-creation requirements/approval time (page not readable by my fetcher). Expect: Wago account, "Upload your addon" web form, project id on the developer dashboard. Wago has a *Developer Agreement* link on its home page; owner must accept it.
- Value: reaches Wago-app users and gives a second distribution point if CurseForge moderation is slow. Cost: another approval and a second description page. **[I]** Recommended after CurseForge is live (not a launch blocker).

---

## 6. README / description / release-notes conventions

- **[V]** Cooldown Master's CF page (https://www.curseforge.com/wow/addons/cooldown-master): one-paragraph pitch in bold -> badge row (GitHub release version, supported flavors, licence) -> table of contents -> "New in x.y.z" -> *What it does* -> *How it works and its limits on Forever* -> *Quick start* (slash commands) -> per-feature sections with tables -> *WoW Forever* section stating limitations honestly ("Support for WoW Forever is a work in progress, so expect bugs") -> *Credits* -> *Found a bug?* (CurseForge comments, Discord, GitHub issues). It also names the licence (MIT) at the end.
- **[V]** CurseForge moderation: description must say what the project does, functional information, English first; credit original authors; links to donation/personal sites at the bottom.
- **[V]** Keep a Changelog 1.1.0 categories: *Added, Changed, Deprecated, Removed, Fixed, Security*, newest first, `## [x.y.z] - YYYY-MM-DD`, an `[Unreleased]` section — https://keepachangelog.com/en/1.1.0/ . Our `CHANGELOG.md` is already player-facing and newest-first but uses `## Unreleased — <date> (<title>)` headings per day.
- **[I]** Suggested 1.0.0 release-notes layout (paste into `RELEASE_NOTES.md`; first lines are what players read in the CF "What's new" box and the GitHub release body):
  ```markdown
  ## ForteXorcist v1.0.0 — first release for WoW Forever (client 1.60.1, interface 16001)

  Cooldown timeline, spell timers, alerts and class tools, rebuilt for Forever's modern API.
  Install: unzip the 16 `Forte_*` folders into `World of Warcraft/_forever_/Interface/AddOns/`
  (or use the CurseForge / WowUp app with the *Forever* installation selected).

  ### Added
  - Cooldown Timer, Secondary Splash, Spell Timer, Messages & Sound, Options window …
  - Hunter: swing bar, range light, aspect reminder …
  - Warlock: shard / soulstone / healthstone / summon plates …
  - Cooldown, buff and debuff data for all 9 Forever classes (live build 1.60.1.7xxxx)

  ### Known limits on Forever
  - Buff/debuff and cooldown values are hidden in combat; the addon predicts from your own casts and corrects out of combat.
  - No combat-log features (not available to Forever addons).
  - Built and tested in simulators plus first live sessions (Hunter); other classes less so — please report bugs.

  ### Credits / licence
  GPL-3.0. Textures/sound from ForteXorcist by Xus (GPL-3.0); font URW Gothic (AGPL-3.0 + font exception); swing model adapted from WeaponSwingTimer SixxFix (GPL-3.0).
  Bugs: https://github.com/Gevil/fortexorcist_forever/issues
  ```
  Facts in brackets must be checked against `README.md`/`CHANGELOG.md` before release; the bullets above summarise README's "What it does today" **[D]**.

---

## 7. Owner-only vs automatable

| Step | Owner-only? | Why / note |
|---|---|---|
| CurseForge author account, login | **Owner** | Personal account (the existing "ForteXorcist TBC Classic" listing under `Gevil_Burx` may already be theirs — **[UNVERIFIED]**) |
| Create CF project (name, slug, summary, description, licence, categories, logo) | **Owner** (web UI) | No project-create API documented; logo must be original art |
| Screenshots / images tab | **Owner** (web UI) | Source images can be prepared in the repo (`docs/demo/`) |
| Moderator approval of project and first file | **Owner waits** | Human review, CET business hours, FIFO |
| CF API token (https://authors.curseforge.com/#/settings/api-tokens) | **Owner** | Bound to the owner's account; paste only into GitHub Secrets / local `.env` |
| Find numeric project id | Owner (one click) | Then written into the TOC by us |
| Wago account + developer agreement + project + `X-Wago-ID` + API key (https://addons.wago.io/account/apikeys) | **Owner** | Optional channel |
| GitHub repo secrets `CF_API_TOKEN`, `WAGO_API_TOKEN`; Actions permission "read and write" for `GITHUB_TOKEN` | **Owner** | Wiki warns of "Resource not accessible by integration" otherwise |
| Commit + push + annotated tag `v1.0.0` | **Owner's go** (AGENTS.md: commit/push only when asked) | Tag push triggers the release |
| `.pkgmeta`, TOC fields, workflow file, release-notes extractor, README/CHANGELOG edits, retiring `release.py` | Automatable (fx-worker) | Needs the ids from the owner |
| Local dry-run `release.sh -d` and zip inspection | Automatable | Proved in §4 |
| Building zip, uploading to CF/Wago, creating GitHub release + `release.json` | Automatable (CI or local with `.env`) | After tokens exist |
| Smoke-test in the real client (`_forever_`) | **Owner** | AGENTS.md: "Final: the real client" |
| Pinning/answering CF comments, moderation fixes | Owner | |

---

## 8. Step-by-step publish plan

1. **Owner:** create the CurseForge project (World of Warcraft -> Addons). Name `ForteXorcist` (fallback `ForteXorcist Forever`), Markdown editor, GPL-3.0, main category *Buffs & Debuffs* + *Hunter*, *Warlock*, *Damage Dealer*; logo 400×400 PNG; summary one sentence; paste the description (§6 structure); issue tracker + source = GitHub; comments on. Note the **project id**.
2. **Owner (optional now):** create the Wago project; note the 8-char id; generate Wago API key.
3. **Owner:** generate the CF API token; add GitHub secrets `CF_API_TOKEN` (+ `WAGO_API_TOKEN`); set Actions workflow permissions to read/write.
4. **fx-worker:** apply §9: add `.pkgmeta`, `.github/workflows/release.yml`, `/.release/` + `RELEASE_NOTES.md` to `.gitignore`/ignore, TOC fields (both twins, `Forte_Core` only for ids), `## Version: @project-version@` in every TOC pair, `## Group: Forte_Core` (optional). Run `gate.py` (twin law, `Interface: 16001`, luajit syntax) — main agent verifies. Rework or retire `scripts/release.py` + `VERSION` (it stamps `## Version:` itself, now redundant; leaving both violates "no obsolete code").
5. **fx-worker:** rewrite `CHANGELOG.md` headings to `## [1.0.0] - YYYY-MM-DD` with Added/Changed/Fixed, plus a "Known limits" block; write the README install section to mention CurseForge/Wago/WowUp and the 16 folders. Check README `Install` text (currently only manual copy).
6. **Main/owner:** local dry run in a clean checkout with a **local annotated tag** (e.g. `v1.0.0-rc0`): download `release.sh` from the packager repo and run `bash release.sh -d -u -n "ForteXorcist-{project-version}{classic}:{project-version}{classic}"` (same command as my test [T]). Inspect the zip: 16 root folders, `## Interface: 16001`, no `tests/` or `*.otf`, `## Version:` expanded. Install it into `_forever_` and run `/fx status` once. Delete the throwaway tag afterwards.
7. **Owner:** push `main`, then `git tag -a v1.0.0 -m "ForteXorcist 1.0.0"` and `git push origin v1.0.0`. CI uploads to CurseForge (release, game version 1.60.1), Wago and creates the GitHub release `v1.0.0` (+ `ForteXorcist-v1.0.0-forever.zip` + `release.json`). If the very first API upload to a not-yet-approved CF project is refused **[UNVERIFIED]**, upload that zip once by hand (web uploader, Supported version Forever 1.60.1, Release) and use CI from 1.0.1 on.
8. **Wait for CF moderation** (File status "Under Review" -> approved; fix anything "Changes required" without deleting). Optionally upload with `isMarkedForManualRelease` and publish at the time you choose **[V API doc]**.
9. **Verify (owner):** CurseForge app -> Forever installation -> search ForteXorcist -> install -> folders appear under `_forever_/Interface/AddOns` (16 folders) -> game loads. Check the project page shows Flavor *Forever*, game version 1.60.1. WowUp: *Install from URL* `https://github.com/Gevil/fortexorcist_forever` on a Forever install should now find the `-forever.zip` (check the `release.json` asset is attached).
10. **Afterwards:** link the CurseForge/Wago pages from `README.md`. The old GitHub release `v0.1.0-dev` is already a pre-release **[V GitHub API]**; leave it (WowUp prefers the newest stable release).

---

## 9. Ready-to-paste files

### 9.1 `.pkgmeta` (repo root) — **tested [T]** in `/tmp/fxpkg`
```yaml
# BigWigs packager config. Addon folders live under addon/, so the package is
# built with move-folders. Version/ids come from the Forte_Core TOCs.
package-as: Forte_Core

manual-changelog:
  filename: RELEASE_NOTES.md      # generated per release (see workflow); not the 500-line CHANGELOG.md
  markup-type: markdown

move-folders:
  Forte_Core/addon/Forte_Core: Forte_Core
  Forte_Core/addon/Forte_Cooldown: Forte_Cooldown
  Forte_Core/addon/Forte_Timer: Forte_Timer
  Forte_Core/addon/Forte_Messages: Forte_Messages
  Forte_Core/addon/Forte_Options: Forte_Options
  Forte_Core/addon/Forte_Items: Forte_Items
  Forte_Core/addon/Forte_ItemProcs: Forte_ItemProcs
  Forte_Core/addon/Forte_Druid: Forte_Druid
  Forte_Core/addon/Forte_Hunter: Forte_Hunter
  Forte_Core/addon/Forte_Mage: Forte_Mage
  Forte_Core/addon/Forte_Paladin: Forte_Paladin
  Forte_Core/addon/Forte_Priest: Forte_Priest
  Forte_Core/addon/Forte_Rogue: Forte_Rogue
  Forte_Core/addon/Forte_Shaman: Forte_Shaman
  Forte_Core/addon/Forte_Warlock: Forte_Warlock
  Forte_Core/addon/Forte_Warrior: Forte_Warrior

ignore:
  - docs
  - tools
  - scripts
  - dist
  - scratch
  - PLAN.md
  - AGENTS.md
  - README.md
  - CHANGELOG.md
  - RELEASE_NOTES.md
  - VERSION
  - LICENSE            # each addon already has gpl-3.0.txt (Forte_Core) and the packager copies LICENSE only if it is not ignored
  - addon/*/tests      # tested: tests/ not shipped
  - addon/*/docs       # same pattern form as addon/*/tests (not separately tested)
  - "*.otf"            # tested: otf excluded (release.py did the same)

plain-copy:
  - addon/*/Data       # large generated tables: copy as-is, no keyword processing
```
Notes: (a) `LICENSE` is ignored here because `Forte_Core/gpl-3.0.txt` already ships; remove that `ignore` line if you want the packager to copy `LICENSE` into every folder (`release.sh` ~2784: "Copy the license into destdir if one doesn't already exist"). (b) No `externals`, `enable-nolib-creation`, `required-dependencies`.

### 9.2 TOC fields to add
**`addon/Forte_Core/Forte_Core.toc` and `Forte_Core_Camelot.toc`** (twin law: keep byte-identical; replace the two ids with the real ones):
```
## Interface: 16001
## Title: |cffC41F3BForte|r Core
## Notes: ForteXorcist for WoW Forever -- shared bootstrap, compat layer and constants.
## Author: Gevil
## Version: @project-version@
## X-Curse-Project-ID: <CurseForge project id, digits>
## X-Wago-ID: <Wago project id, 8 chars>      # omit the line until the Wago project exists
## X-Website: https://github.com/Gevil/fortexorcist_forever
## X-License: GPL-3.0
## SavedVariables: ForteXorcistDB
```
**Every other `Forte_*.toc` + `_Camelot.toc`** (15 folders): only change `## Version: 0.1.0-dev` -> `## Version: @project-version@`, and (optional) add `## Group: Forte_Core`. Do **not** add the CF/Wago ids to them (the packager reads ids only from the package's TOCs; **[UNVERIFIED]** whether the CurseForge app wants them in each module TOC — Details/DBM-style multi-addon projects normally carry them only in the main addon).
Keep `## Interface: 16001` single-valued. If a later Forever build changes the interface, switch to a comma list (`## Interface: 16001, 16002` — packager README documents multiple values) **[V]**; the 2026-11-10 "class tuning" is a hotfix and live builds 1.60.1.70790→70862 stay `1.60.1` **[V]** (https://foreverchanges.pro/patch-notes, 2026-11-07).
Side effect to accept: a dev install deployed by `scripts/deploy.sh` will show the literal text `@project-version@` as its version in the AddOn list **[I]** (only packaged builds are expanded).

### 9.3 `.github/workflows/release.yml`
```yaml
name: Package and release
on:
  push:
    tags: ['v*']
permissions:
  contents: write
jobs:
  release:
    runs-on: ubuntu-latest
    env:
      CF_API_TOKEN: ${{ secrets.CF_API_TOKEN }}
      WAGO_API_TOKEN: ${{ secrets.WAGO_API_TOKEN }}     # delete if no Wago project yet
      GH_API_TOKEN: ${{ secrets.GITHUB_TOKEN }}
    steps:
      - name: Clone project
        uses: actions/checkout@v7          # version as written in the packager wiki 2026-11-09; check it exists
        with:
          fetch-depth: 0                    # needed for previous-tag detection
      - name: Extract release notes for this tag   # UNTESTED helper; CHANGELOG.md must use "## [x.y.z] - date"
        run: |
          v="${GITHUB_REF_NAME#v}"
          awk -v v="$v" '$0 ~ "^## \\[" v "\\]" {f=1; next} /^## \[/ {f=0} f' CHANGELOG.md > RELEASE_NOTES.md
          test -s RELEASE_NOTES.md
      - name: Package and release
        uses: BigWigsMods/packager@v2
        with:
          args: -n "ForteXorcist-{project-version}{classic}:{project-version}{classic}"
```
Local equivalent (no CI): the packager loads `KEY=value` lines from a `.env` in the checkout or in `.release/` (README "Building locally"); keep that file out of git. Dry run: `bash release.sh -d -u -n "..."` (`-d` skip upload, `-u` unix line endings). Single target: `-g forever` or `-g 1.60.1`; skip a channel: `-p 0` (CurseForge) / `-a 0` (Wago) / `-w 0` (WoWInterface; Forever is unsupported there anyway).

---

## 10. Implications for our setup

- Use one pipeline. Recommended: packager (it handles CurseForge game-version ids, markdown changelog, Wago, GitHub release, `release.json`). Then `scripts/release.py` and `VERSION` are obsolete; retire them in the same change (AGENTS.md "no shims"). If the owner prefers keeping `release.py`, then a tiny curl script (§3.3) + `gh release create` replaces CI, but you must add the `-forever.zip` file name and a hand-written `release.json` for WowUp.
- `.gitignore` gets `/.release/` and `RELEASE_NOTES.md` (generated).
- Dev experience: `@project-version@` placeholder in TOCs; `gate.py` twin/interface checks still pass **[D]** (it regex-matches `## Interface:` and compares twin bytes only). The packager's TOC filter has no known conflict with the `ForeverSVFix` patch lines that `deploy.sh` tolerates **[UNVERIFIED]** (not exercised).
- Licensing: AGPL font — corresponding source (`URWGothic-Book.otf`) is in the GitHub repo but intentionally not in the zip; mention that in the description/ATTRIBUTION link to satisfy "source available". Textures from the 2012 GPL zip credit Xus — put that in the CF description (moderation: credit original).
- Name collision risk: there are already CF projects named *ForteXorcist TBC Classic* and *…Anniversary*. If the owner controls them, link them; if not, say in the description that this is a separate rewrite.
- Stability: ship 1.0.0 as **Release** only after one real-client session on a non-Hunter class has passed, because CF's Release channel auto-installs to every Forever player; otherwise tag `v1.0.0-beta1` (packager -> beta/prerelease, not auto-synced; WowUp "Beta" channel). **[I]**

## Open questions (for the owner)
1. Is the CF account `Gevil_Burx` yours; is the slug `fortexorcist` free; do you want to name the project "ForteXorcist" or "ForteXorcist Forever"?
2. Release type for 1.0.0: stable "Release" now, or `1.0.0-beta1` first?
3. Is Wago wanted at launch? (needs your Wago account + project id.)
4. Logo: do you have an original 400×400 PNG (not Xus's `ForteXorcist.blp`, not the WoW logo)?
5. Retire `scripts/release.py` and `VERSION` in favour of the packager, or keep a local-only builder?
6. Numeric CurseForge ids: the 1.60.1 game-version id (needs your token; command in §3.2) — not required if you use the packager.
7. Can the API upload the *first* file to a not-yet-approved project? Unverified; plan assumes web upload for the first file if the API refuses.
8. Does the CurseForge app need `X-Curse-Project-ID` in each module TOC (not just `Forte_Core`)? Unverified; check after first approval by installing from the app.

## Proposed patch
No `tools/spell_lists/*.json` changes: this note is about publishing, not spell data. The file-level changes (`.pkgmeta`, TOC fields, workflow) are in §9.

## Sources
- CurseForge Blog, *How to Migrate WoW Forever Addons from Beta to Live*, https://blog.curseforge.com/wow-forever-migrate-addons-beta-to-live/ (2026).
- CurseForge Support: *CurseForge Upload API* (2026-09-27) https://support.curseforge.com/en/support/solutions/articles/9000197321-curseforge-upload-api ; *Creating and Submitting a Project* (2024) https://support.curseforge.com/support/solutions/articles/9000197241-creating-and-submitting-a-project ; *Project Submission Guide and Tips* (2024) https://support.curseforge.com/support/solutions/articles/9000199552 ; *Moderation Policies* (2026-10-22) https://support.curseforge.com/support/solutions/articles/9000197279-project-and-modpack-moderation-policies ; *WoW Addons FAQ* (2026-07-07) https://support.curseforge.com/en/support/solutions/articles/9000198422-world-of-warcraft-addons-faq-and-troubleshooting ; *Multi-TOC for WoW Addons* (2024) https://support.curseforge.com/support/solutions/articles/9000209856-multi-toc-for-world-of-warcraft-addons ; CurseForge for Studios API https://docs.curseforge.com/rest-api (2026).
- CurseForge project pages: Cooldown Master https://www.curseforge.com/wow/addons/cooldown-master ; EllesmereUI files https://www.curseforge.com/wow/addons/ellesmereui/files/all ; Forever Cooldown Manager file 8982464 https://www.curseforge.com/wow/addons/forever-cooldown-manager/files/8982464 ; ForteXorcist TBC Classic Anniversary https://www.curseforge.com/wow/addons/fortexorcist-tbc-classic-anniversary ; WoW search https://www.curseforge.com/wow/search?class=addons&page=2&pageSize=50&sortBy=relevancy&categories=achievements.
- BigWigsMods/packager: README https://github.com/BigWigsMods/packager ; `release.sh` (master, v2.7.0, 2026-11-05) https://raw.githubusercontent.com/BigWigsMods/packager/master/release.sh ; wiki https://github.com/BigWigsMods/packager/wiki/Preparing-the-PackageMeta-File and /GitHub-Actions-workflow ; `action.yml`.
- Wago: https://docs.wago.io/ ; https://addons.wago.io/api/data/game .
- WowUp: https://github.com/WowUp/WowUp/releases (v2.24.0, v2.25.4) ; `github-addon-provider.ts` https://github.com/WowUp/WowUp/blob/master/wowup-electron/src/app/addon-providers/github-addon-provider.ts ; issue https://github.com/rusty-key/spoken-wow/issues/881 (2026-11-04).
- Warcraft Wiki, *TOC format* https://warcraft.wiki.gg/wiki/TOC_format (game-type suffix table, `Group`, `Category`).
- Keep a Changelog 1.1.0 https://keepachangelog.com/en/1.1.0/ .
- Secondary (used only for context, flagged): https://wowforeverinfo.com/guides/addons (2026-11-09), https://forevermeta.me/en/guides/wow-forever-addons-interface (2026-10-23), https://wowforeveraddons.com/install/curseforge-app (2026-11-01), https://foreverchanges.pro/patch-notes (2026-11-07).
- Local: `AGENTS.md`, `README.md`, `CHANGELOG.md`, `addon/*/ *.toc`, `addon/Forte_Core/ATTRIBUTION.md`, `scripts/release.py`, `scripts/gate.py`, GitHub API for `Gevil/fortexorcist_forever` (public, GPL-3.0 detected, release `v0.1.0-dev` prerelease with `ForteXorcist-0.1.0-dev.zip`, no `.github/` dir).
