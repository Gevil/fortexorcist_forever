# Publishing ForteXorcist Forever 1.0.0 to CurseForge: owner checklist

Channels: **CurseForge + GitHub release.** Wago is not used. Evidence and sources for every claim
below: `docs/research/curseforge-forever-publishing-2026-11-09.md` (tags there: V = read on a page,
UNVERIFIED = could not be confirmed). Things that are *not* verified are marked **(unverified)**.

What is already in the repo: `.pkgmeta` (16 folders, ignores tests/docs), `.github/workflows/release.yml`
(runs on a `v*` tag), `scripts/release_notes.py` (writes `RELEASE_NOTES.md` from `CHANGELOG.md`),
`scripts/release.py` (local build of the same payload). What only you can do: the CurseForge account,
project, logo, API token, GitHub secret, the tag.

> **Status 2026-11-11:** the owner created the project (**ID 1796794**) and the 1.0.0 file was uploaded
> through the API (file ID 9554784, Release, Forever 1.60.1); it is **Under Review**. `X-Curse-Project-ID`
> is in both `Forte_Core` tocs for the packager. What remains: regenerate the API token (the first one was
> pasted in a chat), store the new one as the repo secret `CF_API_KEY`, and answer moderator feedback.
> Sections B and C below stay as the reference for later releases (the first-upload fallback in step 11 was
> not needed).

## A. CurseForge account and project

1. **Account.** Sign in (or register) at <https://www.curseforge.com/> and open the authors area:
   <https://authors.curseforge.com/>. Create/complete the author profile.
   (A listing "ForteXorcist TBC Classic" exists under the name `Gevil_Burx`; **(unverified)** whether
   that is you. If it is yours, you can link it as a related project; if not, say in the description
   that this is a separate rewrite.)
2. **Create the project.** <https://authors.curseforge.com/#/projects/create/choose-game> → game
   **World of Warcraft** → class **Addons**. There is no project-creation API; this is a web form.
3. **Fields.**
   - **Name:** `ForteXorcist Forever`. The slug is generated from the name; check it reads
     `fortexorcist-forever` and edit it if the form allows. Names must be unique (a taken name is
     rejected); if it is taken, use `ForteXorcist for Forever`.
   - **Summary** (one sentence, about 135 characters; paste as is):
     `Cooldown bar, spell timers, crowd-control warnings and Hunter/Warlock tools for WoW Forever, a rebuild of the classic ForteXorcist.`
   - **Description:** choose the **Markdown** editor, paste the text in section E. (A parallel draft,
     `docs/release/curseforge-description.md`, also exists. Use one of the two, not both. Section E
     was checked against the code and states that the Warlock group comms are on by default; the
     other draft says only that a fresh install sends nothing to party or raid chat.)
   - **License:** GPL-3.0 (pick the GPL v3 entry in the dropdown; its exact label is **(unverified)**).
     The textures and sound come from the GPL-3.0 original, so the page must say GPL-3.0.
   - **Categories:** main **Buffs & Debuffs**; additional (up to 4, must be relevant): **Hunter**,
     **Warlock**, **Combat → Damage Dealer**. Category names come from the site's search filters on
     2026-11-09; pick the closest available names if the form differs.
   - **Logo:** a **PNG, at least 400×400, square, original artwork**. Not the WoW/Forever logo, not
     an existing project's avatar, not Xus's `ForteXorcist.blp` (his art). Not webp (known upload
     bug). The repo has no logo; you supply it.
   - **Images:** upload the screenshots from `docs/demo/` (`cooldown-bar-and-timer.png`,
     `warlock-plates.png`, `options-window.png`, and the `.gif` files). Optional but recommended.
   - **Links:** Issue tracker `https://github.com/Gevil/fortexorcist_forever/issues`; Source
     `https://github.com/Gevil/fortexorcist_forever`. Enable comments. Leave **Experimental** off
     (an experimental project does not sync to the app).
   - **Do not** put a "download from GitHub" button or link in the description (third-party download
     links are not allowed); linking the repository for source and issues is fine.
4. **Project ID.** After the project exists, open its overview page; the numeric **Project ID** is
   shown in the "About Project" box (also in the project URL in the authors area). Keep it for step 7.

## B. API token and GitHub secret

5. **API token.** <https://authors.curseforge.com/#/settings/api-tokens> → generate a token. Copy it
   once; never commit it, never paste it into an issue or chat.
6. **GitHub secret.** Repository `Gevil/fortexorcist_forever` → *Settings* → *Secrets and variables* →
   *Actions* → *New repository secret*: name **`CF_API_KEY`**, value = the token. (The workflow reads
   `CF_API_KEY`; the packager still accepts that name, though it lists it as deprecated in favour of
   `CF_API_TOKEN`. If the packager ever stops reading it, rename the secret and the one `env:` line
   in `release.yml`.) Also *Settings* → *Actions* → *General* → *Workflow permissions* → **Read and
   write permissions**, or the GitHub release step fails with "Resource not accessible by
   integration". `GITHUB_TOKEN` needs no secret.
   Without `CF_API_KEY` the workflow still runs: it warns and skips CurseForge, and publishes the
   GitHub release.

## C. The project id in the toc, the release, the first upload

7. **The toc edit (the only edit the id needs).** In **both** `addon/Forte_Core/Forte_Core.toc` and
   `addon/Forte_Core/Forte_Core_Camelot.toc` (they must stay byte-identical; `gate.py` checks), add
   this line directly after `## Author: Gevil` (line 5):
   ```
   ## X-Curse-Project-ID: <the numeric id from step 4>
   ```
   Optional in the same place: `## X-Website: https://github.com/Gevil/fortexorcist_forever` and
   `## X-License: GPL-3.0`. Do not add the id to the other 15 folders: the packager reads it from the
   package's main toc, and whether the CurseForge app wants it in each module toc is
   **(unverified)**; check after the first approval by installing from the app. (`X-Wago-ID` is not
   used.) Commit that edit before tagging.
8. **Changelog heading.** The workflow builds the release notes from `CHANGELOG.md`, so the top
   section for the release must have a heading that contains the version, for example
   `## [1.0.0] - 2026-11-10`. If there is none, the job stops at "Release notes for this tag"
   (by design: it must not publish another release's notes). Preview locally:
   `python3 scripts/release_notes.py` (writes `RELEASE_NOTES.md`, ignored by git).
9. **Dry run (recommended, no upload).** Local build of the payload:
   `python3 scripts/release.py --dry-run`, then without `--dry-run` for
   `dist/ForteXorcist-1.0.0-forever.zip` + `.sha256`. It builds from the committed tree (`git archive HEAD`),
   so commit first. Unzip it and check: 16 `Forte_*` folders at the zip root, `## Interface: 16001`,
   no `tests/` and no `*.otf`.
10. **Tag.** `VERSION`, the tocs and `Constants.lua` all say `1.0.0`; the tag must match `VERSION`
    (the workflow checks). Use an annotated tag:
    ```
    git tag -a v1.0.0 -m "ForteXorcist 1.0.0"
    git push origin main
    git push origin v1.0.0
    ```
    The workflow packages with the BigWigs packager, tags the file **Forever / 1.60.1**, uploads it to
    CurseForge as a **Release** (a tag containing `alpha` or `beta` becomes alpha/beta and a GitHub
    pre-release) and creates the GitHub release with the zip (`ForteXorcist-v1.0.0-forever.zip`) and
    `release.json` (the `-forever` suffix and `release.json` are what WowUp needs to offer it to a
    Forever install).
    The research recommends shipping Release only after one real-client session on a non-Hunter class;
    otherwise tag `v1.0.0-beta1` first (not auto-synced to the CurseForge app). Your call.
11. **If the API refuses the first upload.** Whether the API accepts the *first* file of a project that
    has not been approved yet is **(unverified)**. If the Actions log shows a CurseForge error:
    1. Get the zip: the GitHub release asset `ForteXorcist-v1.0.0-forever.zip` (or build it with step 9).
    2. Project dashboard → **Files** → upload the `.zip` (a real zip, under 2 GB).
    3. **Display name:** `ForteXorcist 1.0.0`. **Release type:** **Release**. **Supported versions:**
       **Forever → 1.60.1** and nothing else (tagging it for Retail would make Retail installs show
       a "might be corrupt" warning). **Changelog:** paste `RELEASE_NOTES.md`, set the type to
       Markdown. Leave "Related projects" empty.
    4. Submit. Use CI for every later version (1.0.1 and on). Do not re-run the failed 1.0.0 workflow
       with `CF_API_KEY` set after uploading by hand: it would try to upload a second 1.0.0.

## D. What to expect from moderation

- The new project, and its first file, go to human moderators. The file shows **Under Review**.
  Hours are 8:00 to 15:00 CET, 7 days a week, first in first out; no published SLA. Plan at least one
  CET business day.
- Moderation may come back with **changes required** (name, description, credits, licence). Fix it
  in place; do not delete and re-upload the project or file.
- A project must have at least one **Release** file before it syncs to the CurseForge app. Beta/alpha
  files only sync for users who opt in.
- Every file needs a changelog; re-uploading an unchanged file is not allowed.
- Verification after approval: CurseForge app → your **Forever live installation** → search
  *ForteXorcist Forever* → install; 16 `Forte_*` folders appear in `_forever_/Interface/AddOns`; log in;
  `/fx status`. The project page should show Flavor **Forever**, game version **1.60.1**. If the app does
  not see the folders, scan the AddOns folder manually (CurseForge's own advice).
- After it is live, add the project link to `README.md` ("Install", option 1) and tell the manager.

## E. Paste-ready description (Markdown)

```markdown
**Cooldown bar, spell timers, crowd-control warnings and class tools for WoW Forever.**
ForteXorcist Forever is a rebuild of the classic ForteXorcist addon (2012, by Xus) for the Forever
client's modern API and its combat restrictions. It keeps the original's look. It is not a port of the
2012 code.

## What it does
- **Cooldown Timer**: one bar on a power-scale time axis; icons slide as cooldowns burn; ready pulse,
  charge counts, a flash when you cast a spell that is on cooldown; trinkets, potions, weapon
  enchants and racials are tracked too.
- **Secondary Splash** (off by default): a big pop of an ability's icon the moment it is ready.
- **Spell Timer**: rows per spell and target, grouped by target, coloured by kind. Own and pet casts are
  predicted and corrected from real auras when you are out of combat.
- **Messages & Sound**: crowd-control fade and break warnings (Banish, Fear, Subjugate Demon,
  Seduction, Polymorph, Sap) with sounds; optional self messages. Announcements to other players are
  all off until you switch them on.
- **Options window** (`/fx options`): the original's layout, profiles per character or shared, every
  setting applies live.
- **Hunter**: Auto Shot swing bar (reload / stand-still aim window / safe-to-move), clip band for Aimed
  Shot and Multi-Shot, optional melee-weave line and melee rail, optional range light, aspect reminder.
- **Warlock**: shard, soulstone, healthstone and summon plates; optional group comms so other
  ForteXorcist users in your group fill in your stone and shard spies.
- **Shaman**: totem rows by element.
- **Druid, Mage, Paladin, Priest, Rogue, Warrior**: cooldown bar and Spell Timer from generated class
  data (about 630 spell rows for the nine classes).

## How it works, and its limits on Forever
Addons cannot read the combat log on Forever, and many buff and cooldown values are hidden during
combat. ForteXorcist predicts from your own casts and corrects itself when the real values can be read,
so timers can be slightly off in combat. It does not use the combat log, and it sends no chat to other
players unless you turn that on (the only default traffic is the Warlock group comms, an addon-channel
message that other ForteXorcist users read, never sent solo; it can be switched off).

Played live on Hunter; the other classes are tested in simulators and against the game data. Please
report problems.

## Install and commands
Install through the CurseForge app with the **Forever live installation** selected. `/fx options`
opens the settings, `/fx status` prints the module status, `/fx unlock` and `/fx lock` move the bars.

## Credits and license
GPL-3.0. Original ForteXorcist by Xus (Xussie of Kazzak EU), GPL-3.0: its textures and one sound are
used unmodified. Font: URW Gothic Book (AGPL-3.0 with font exception; the `.otf` source is in the
GitHub repository). The Hunter swing model is adapted from WeaponSwingTimer SixxFix by WatchYourSixx
(original by LeftHandedGlove, GPL-3.0). Cooldown engine design reference: CooldownMaster (MIT). Spell and
item data: mythicsim-forever-engine and wowsims/forever (MIT).

Bugs and source: https://github.com/Gevil/fortexorcist_forever
```
