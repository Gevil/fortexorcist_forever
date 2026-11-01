# power auras / weakauras item procs detection from addons in wow forevver ?

*Created: 11/1/2026, 6:03:40 PM*

---

**You**

power auras / weakauras item procs detection from addons in wow forevver ?

---

**Assistant**

**Original WeakAuras does not work in WoW Forever**, and item-proc detection in particular is limited by a "secret values" system in the modern engine: the moment you enter combat, aura and cooldown data become unreadable to addons, so a plain port of WeakAuras goes blind exactly when procs fire. [^1] [^2]

Here's what actually works for proc detection on the server:

| Addon | Proc support | Notes |
|---|---|---|
| **Power Auras** | Class-specific procs (Overpower, Mongoose, etc.) with glowing arc overlays | Detects your class and shows its own procs; no Cooldown Manager needed [^3] |
| **ClassicProcAuras** | Blizzard-style animated spell-activation overlays | Uses WoW's native aura-container functionality, so it bypasses the addon data lock [^4] |
| **EverAuras** (WeakAuras fork) | Buff/debuff/cooldown triggers that keep working in combat | Hands combat-locked displays to the game itself, so it doesn't go blind in combat [^1] |
| **ForeverAuras** (WeakAuras fork) | Full WeakAuras-style triggers | Still under development / beta; open issues on GitHub [^5] |

**The practical limitation for item procs:** the "secret values" lock means any trigger that reads `Aura` or `Cooldown` data via the standard WoW API will stop updating once you're in combat. Addons that work around this either:

- push the display logic into the game's native UI (ClassicProcAuras, EverAuras), or
- rely on events that *are* still visible to addons (cast/spell events, combat log) rather than polling aura state.

So if your item proc shows up as a buff on you, you can catch it with a `buff` trigger in EverAuras or ForeverAuras (once stable), or with a Power Auras/ClassicProcAuras preset if one exists for that specific proc. If it's purely a combat-log event (e.g., "item X procs on hit"), a `cast` or `spell` trigger reading the combat log is your best bet, since that data isn't subject to the same lock. [^1]

For the most current preset lists and which specific item procs are already covered, check the CurseForge pages for [Power Auras](https://www.curseforge.com/wow/addons/power-aura) and [ClassicProcAuras](https://www.curseforge.com/wow/addons/classicprocauras) — both list supported procs per class. [^3] [^4]

**References**

[^1]: [A WeakAuras Fork - World of Warcraft Addons - CurseForge](https://www.curseforge.com/wow/addons/everauras) (22%)
[^2]: [No Weakauras in WoW Forever? Here’s What to Use Instead](https://www.icy-veins.com/wow-forever/news/no-weakauras-in-wow-forever-heres-what-to-use-instead/) (11%)
[^3]: [Power Auras - World of Warcraft Addons - CurseForge](https://www.curseforge.com/wow/addons/power-auras) (22%)
[^4]: [ClassicProcAuras - World of Warcraft Addons - CurseForge](https://www.curseforge.com/wow/addons/classicprocauras) (22%)
[^5]: [ForeverAuras - Wago Addons](https://addons.wago.io/addons/foreverauras) (22%)

---

**You**

are ther any addons that solved this already ?

---

**Assistant**

Yes — three forks now exist that work around it, and one of them (EverAuras) explicitly handles proc alerts in combat. But "solved" comes with a hard ceiling: **you can display a proc, you still can't do logic on it.**

| Addon | Approach | Proc support status |
|---|---|---|
| **[EverAuras](https://www.curseforge.com/wow/addons/everauras)** | Hands displays to the game engine; WeakAuras 2 + M33kAuras base | Most complete. Proc textures/stop-motion/models on proc buffs, **sounds that fire on show/hide in combat**, conditions on remaining time, stack-count conditions, Dynamic Groups sorted by time left. Imports WA and ForeverAuras strings [^1] |
| **[Musca Auras](https://www.curseforge.com/wow/addons/musca-auras)** | Same engine-draw mechanism, plus "Game Categories" aura filtering | Has a dedicated **proc alert** recipe: Texture/Icon on player buff (proc spell ID) + Glow + On Show sound. Game Categories can surface auras the game otherwise hides completely in combat [^2] |
| **[ForeverAuras](https://github.com/Tulkas22/ForeverAuras)** | Direct WA2 fork, renamed globals | Works, but README states **early development, "expect errors, especially in combat."** Keeps out-of-combat triggers, removes what can't function [^3] |

**How they actually do it:** the game itself draws the aura icon, timer, stack text and bar from the secret value without the addon ever reading it. That's why icons and countdowns keep running in combat even though `UnitAura` data is unreadable [^2] [^1].

**What still isn't solved — relevant to item procs:**

- **No conditionals on the proc.** Logic on secret data (stacks, remaining time, health) freezes at its last pre-combat state and only updates when combat ends [^2]. So "glow only if proc is up AND you have 5 combo points" won't work.
- **Aura name is blank in combat** for game-hidden auras found via Game Categories [^2].
- **The combat log is closed on Forever** — combat-log/`CLEU` triggers never fire. Use `UNIT_SPELLCAST_SUCCEEDED:player` instead [^2]. (This corrects what I said last message: combat-log triggers are not a viable fallback on this server.)
- Community reports of auras **disappearing intermittently in combat** in ForeverAuras [^4], and old Classic imports only partially working [^4].

**Practical recommendation for item procs:** use **EverAuras** — it's the only one advertising in-combat *sounds* on aura gain/loss, which is what you actually want from a proc alert. Set up a Texture/Icon on Player buff with the item's proc spell ID, add a Proc glow, and put the sound in Actions → On Show. Keep a **Musca Auras** install in reserve for the Game Categories trick if the proc buff is one the game hides entirely; the two convert each other's imports cleanly, and Musca's guide says never to run both at once [^2].

**References**

[^1]: [EverAuras - A WeakAuras Fork - World of Warcraft Addons - CurseForge](https://www.curseforge.com/wow/addons/everauras) (25%)
[^2]: [Musca-Auras/GUIDE.md at main · dldvlpr-addons-wow/Musca-Auras · GitHub](https://github.com/dldvlpr-addons-wow/Musca-Auras/blob/main/GUIDE.md) (25%)
[^3]: [GitHub - Tulkas22/ForeverAuras: World of Warcraft addon that provides a powerful framework to display customizable graphics on your screen. · GitHub](https://github.com/Tulkas22/ForeverAuras) (25%)
[^4]: [WeakAuras now working in Forever perfectly](https://www.reddit.com/r/wow/comments/1wp0sz0/weakauras_now_working_in_forever_perfectly/) (25%)

---

