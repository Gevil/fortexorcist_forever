-- Forte_Options/Pages/Advanced.lua
-- The Advanced Options page (the original's `FWL.ADVANCED` category, index
-- cell 99 of its grid -- `Forte_Core/Options.lua:5574` -- and the module
-- files' own `SetMainCategory(FWL.ADVANCED, ...)` rows). The page registers
-- the settings module `Advanced`; the module pages' rows ride it, and every
-- row on it has a live consumer: a row whose consumer does not exist is not
-- on this page (the list of the dropped rows is at the bottom of this
-- header, and docs/research/options-fidelity.md "Advanced cell" is the
-- survey it came from).
--
-- THE ROWS, with the original's own strings
-- (labels/defaults from `Forte_Core/Localization.lua` / `Forte_Core.lua`):
--   * "Show startup text" :497, `ShowStartupText` (`Options.lua:5577`,
--     default true `Forte_Core.lua:2529`). The consumer is the login print
--     itself: Forte_Core/Core/Init.lua's `FX.PrintStartupLine`.
--   * "Expand all" :500 / "Load expanded" :502, `ExpandSubcats` /
--     `LoadExpandSubcats` (`Options.lua:5589-5590`, defaults
--     `Forte_Core.lua:2530-2531`). The consumers are the window's section
--     builder and its fold memory (UI/Window.lua `StartCollapsed` /
--     `RememberCollapse`). DEFAULT DRIFT: the source ships
--     `ExpandSubcats = false`, which opens every page with its sections
--     folded; ours ships true -- the fold-the-rest law is live (switch it
--     off and a fresh page opens folded), the shipped LOOK is the panel
--     screenshot's. The same ship-locked ruling as `GlobalLock`
--     (docs/research/options-fidelity.md "Defaults audit").
--   * "Animate auto-scrolling" :347, `AnimateScroll` (`Options.lua:5591`,
--     default false `Forte_Core.lua:2477`). The consumer is the wheel:
--     UI/Window.lua's `Scroll` eases to its target through the window
--     frame's own OnUpdate (`StepScrollAnim`) instead of jumping.
--   * "Frame level (strata)" :440 -- one row per module frame, the source's
--     own per-module Advanced rows and their key names
--     (`CooldownStrata` Forte_Cooldown.lua:1790, `SplashStrata` :1793,
--     `TimerStrata` Forte_Timer.lua:3277, `SoulstoneStrata`
--     Forte_Soulstone.lua:645, `HealthstoneStrata` Forte_Healthstone.lua:316,
--     `SummonStrata` Forte_Summon.lua:573; `HunterStrata`/`ShardStrata` are
--     ours -- the source's Hunter class file registers no options and its
--     shard modules are not in the snapshot). Every one lands on its
--     frame's `SetFrameStrata` through the module's own `SetStrata` seam
--     (Forte_Cooldown/UI/Timeline.lua, Forte_Cooldown/UI/Splash.lua,
--     Forte_Timer/Module.lua + UI/Rows.lua, Forte_Hunter/UI/Swing.lua,
--     Forte_Warlock/UI/Frame.lua for the four plates), which every one of
--     them self-wires to this module and applies at login. The eight legal
--     names are the catalog's FrameStrata (`SetFrameStrata`,
--     SimpleFrameAPIDocumentation.lua:1293), and the value is validated at
--     the consumer: a name outside the eight is stored as typed and
--     ignored, so the frame never falls off the screen.
--
-- DROPPED, no consumer to give them (not rows, not keys, not tips):
--   * `FrameSnap` + `FrameSnapDistance` + `FrameDistance`
--     (`Options.lua:5581-5583`, defaults `Forte_Core.lua:2481-2483`). Every
--     Forte frame drags through the engine's native `StartMoving`, and no
--     snap grid exists to snap to -- the key that IS registered
--     (`General.FrameSnap`) stays stored-only and says so
--     (Pages/General.lua, pinned inert by Forte_Cooldown/tests/
--     test_timeline.lua). The two distance rows are not added at all.
--   * The Core block: `LoadDelay`, `UpdateInterval`, `AnimationInterval`,
--     `Chill` (`Options.lua:5624-5629`, defaults `Forte_Core.lua:2472-2475`).
--     Our engines run on fixed per-module cadences (Forte_Cooldown/
--     Module.lua:14, Forte_Timer/Module.lua's DRAW_SECONDS, Forte_Warlock/
--     UI/Module.lua:51, the Hunter bar's TICK_SECONDS) -- none reads a
--     setting, and the source's own tip says they need a reload anyway.
--   * `OptionsColums`, `OptionsHeight` (`Options.lua:5587-5588`): the
--     builder is a fixed two-column grid (UI/Window.lua's column cursor)
--     and the window a fixed 780x650 (its geometry tests), so both would be
--     writes into a void.
--   * `GlobalFrameNames` (`Options.lua:5578`): the frame names are compiled
--     into the `CreateFrame` calls; the source's own tip needs a reload.
--   * `TimerSpellsTooltip` (`Options.lua:5592`) and the whole Options
--     Linking + options-appearance blocks (`Options.lua:5594-5622`): no
--     spell-group tooltips, no clones/profile-linking, no themable window.
--   * `REMOVE_BACKUP` (`Options.lua:5627`): there is no backup cache here.

ForteXorcist = ForteXorcist or {}
local FX = ForteXorcist
local O = FX.Options

local M = "Advanced"
local DEFAULT_STRATA = "MEDIUM"   -- Forte_Core.lua:2531

FX.Settings:Register(M, {
    -- The module's own behaviour rows.
    ShowStartupText = true,        -- Forte_Core.lua:2529
    AnimateScroll = false,         -- :2477
    ExpandSubcats = true,          -- :2530 -- ship-expanded, see the header
    LoadExpandSubcats = true,      -- :2531
    -- The per-frame draw level, one key per frame, named as the source
    -- names it. The frame reads it through its own module's shared-key
    -- wiring (see the header), never through a page.
    CooldownStrata = DEFAULT_STRATA,
    SplashStrata = DEFAULT_STRATA,
    TimerStrata = DEFAULT_STRATA,
    HunterStrata = DEFAULT_STRATA,
    ShardStrata = DEFAULT_STRATA,
    SoulstoneStrata = DEFAULT_STRATA,
    HealthstoneStrata = DEFAULT_STRATA,
    SummonStrata = DEFAULT_STRATA,
})

--- The tip the source's own strata row carries (Localization.lua:441),
--- rendered from the eight names of the catalog.
local STRATA_TIP = "Frame level of this module. Valid are, from lowest to"
    .. " highest level: BACKGROUND, LOW, MEDIUM, HIGH, DIALOG, FULLSCREEN,"
    .. " FULLSCREEN_DIALOG, TOOLTIP. Applied live; a name outside the eight"
    .. " is kept as typed and ignored."

--- One strata row (the source's `STR` row type: a text field, the value the
--- player types). `tip` names the frame the row drives, because a row that
--- moves nothing on this class must not read as a live control.
local function strataRow(s, key, label)
    s.STR({
        module = M, key = key,
        label = label,
        strWidth = 140, maxLetters = 20,
        tip = STRATA_TIP,
    })
end

O:RegisterPage({
    id = "Advanced",
    module = M,
    title = "Advanced Options",
    colour = O.C.SLATE,
    build = function(b)
        b.Tips({
            "You will usually not have to change anything here."
                .. " It's only for problem solving.",
            "Every row on this page has a live consumer; the ones of the"
                .. " original that have none here (frame snapping,"
                .. " update intervals, option columns) are not on it.",
            "The frame levels are the draw order of the module frames:"
                .. " a module you can not click through, or that hides"
                .. " behind a Blizzard dialog, is usually one name off.",
            "The recycle icon left of every row restores just that option.",
        })
        b.Section("General Module Options", function(s)
            s.CHK({
                module = M, key = "ShowStartupText",
                label = "Show startup text",
                tip = "Show the ForteXorcist startup lines in your chat"
                    .. " window. Off = a silent login; the line returns at"
                    .. " the next login.",
            })
        end, {
            module = M, keys = { "ShowStartupText" },
            tip = "What the addon says when you log in.",
        })
        b.Section("Options Behavior", function(s)
            s.CHK({
                module = M, key = "ExpandSubcats",
                label = "Expand all",
                tip = "Expand all sections. Off opens a page with its"
                    .. " sections folded, except 'Some Tips' and 'Basics'."
                    .. " Applied to a section that has no state of its own"
                    .. " yet -- close and reopen the page (or switch"
                    .. " profiles) to see the change.",
            })
            s.CHK({
                module = M, key = "LoadExpandSubcats",
                label = "Load expanded",
                tip = "Remember which sections you folded yourself, per page"
                    .. " and profile. Off keeps a fold for the page that is"
                    .. " open now only.",
            })
            s.CHK({
                module = M, key = "AnimateScroll",
                label = "Animate auto-scrolling",
                tip = "Animates the scrolling of the options. This gives you"
                    .. " a better feeling of 'where you are' in the options"
                    .. " menu. Applied live to the mouse wheel.",
            })
        end, {
            module = M,
            keys = { "ExpandSubcats", "LoadExpandSubcats", "AnimateScroll" },
            tip = "How this window itself behaves.",
        })
        -- The per-frame block: the source's own per-module sub-categories
        -- of its Advanced category, one section per frame family.
        b.Section("Cooldown Timer", function(s)
            strataRow(s, "CooldownStrata", "Frame level (strata)")
        end, {
            module = M, keys = { "CooldownStrata" },
            tip = "The Forte Cooldowns bar.",
        })
        b.Section("Secondary Splash", function(s)
            strataRow(s, "SplashStrata", "Frame level (strata)")
        end, {
            module = M, keys = { "SplashStrata" },
            tip = "The Secondary Splash window.",
        })
        b.Section("Spell Timer", function(s)
            strataRow(s, "TimerStrata", "Frame level (strata)")
        end, {
            module = M, keys = { "TimerStrata" },
            tip = "The Forte Spell Timers panel.",
        })
        b.Section("Hunter Tools", function(s)
            strataRow(s, "HunterStrata", "Frame level (strata)")
        end, {
            module = M, keys = { "HunterStrata" },
            tip = "The Hunter swing bar (a Hunter's frame; the row is live"
                .. " on a Hunter, stored on every other class).",
        })
        b.Section("Warlock Tools", function(s)
            strataRow(s, "ShardStrata", "Frame level - Shard Spy")
            strataRow(s, "SoulstoneStrata", "Frame level - Soulstone Tracker")
            strataRow(s, "HealthstoneStrata", "Frame level - Healthstone Spy")
            strataRow(s, "SummonStrata", "Frame level - Summon Assistant")
        end, {
            module = M,
            keys = { "ShardStrata", "SoulstoneStrata", "HealthstoneStrata",
                "SummonStrata" },
            tip = "The four Warlock plates (a warlock's frames; the rows are"
                .. " live on a warlock, stored on every other class).",
        })
    end,
})
