-- addon/Forte_Warlock/Pages/Warlock.lua
-- The warlock Tools pages: one page PER MODULE INDEX CELL of the original's
-- window (`docs/refs/options-panel.png`), so the four cells of the grid light
-- up exactly as the original's do. Forte_Options' index maps one page id per
-- cell (Forte_Options/UI/Window.lua's `O.INDEX` + `RefreshIndexCells`: a cell
-- is enabled exactly while a page of ITS id is registered), and the ids this
-- build targets are the index's own `ShardManager`, `Soulstone`,
-- `Healthstone` and `Summon` rows. The fifth warlock cell, `ShardSpy`, stays
-- dim on purpose: the raid-wide spy half is Phase 6 comms
-- (docs/warlock-tools.md, spec SS-08/HS-02).
--
-- All four pages share ONE settings module, "Warlock" (the Hunter page's
-- one-module-per-class-toolbox convention): the shared
-- Enable/Lock/ShowTime/BgColor/BarColor keys plus each tool's own keys, so a
-- value typed on one page is the same value the other pages show. The
-- consequence is stated plainly: the header's recycle icon on any of the four
-- pages restores the WHOLE Warlock module (the per-section recycle icons are
-- the granular ones).
--
-- Wiring contract: every key has a public setter seam on
-- FX.Warlock.Shards / .Soulstone / .Healthstone / .Summon (the shared
-- UI/Frame.lua law); the OnChange listener below routes each change through
-- their ApplySettings, and each frame ALSO self-wires from its own Init
-- (Forte_Warlock works with Forte_Options not installed; the listener here is
-- the page-side mirror, idempotent with it). Saved values are applied at
-- login by the frames' ApplyStoredSettings. Lock follows the Forte_Cooldown
-- m4 rule: the frames publish the LIVE lock state of their frames into
-- Warlock.Lock (never the other way), so the checkboxes, the header lock
-- icons and /fx lock|unlock agree.
--
-- Load-order law (the Forte_Hunter/Pages/Hunter.lua one, verbatim): this
-- chunk is FORTE_WARLOCK's and the loader is free to run it before
-- Forte_Options' files, so NOTHING on FX.Settings / FX.Options may be touched
-- at file load. The whole registration is one idempotent function, run at load
-- when FX.Settings + FX.Options exist and, when they do not, from
-- FX.Warlock.UI:OnEnable at PLAYER_LOGIN. FX.Settings:Register is safe at
-- that late point: the store seeds lazily on the first Get/Set and defaults
-- never overwrite a saved value.

ForteXorcist = ForteXorcist or {}
local FX = ForteXorcist

FX.Warlock = FX.Warlock or {}
FX.Warlock.Pages = FX.Warlock.Pages or {}
local P = FX.Warlock.Pages

local M = "Warlock"

--- A colour/size default read off the frame's own skin table (ONE truth: the
--- store default and the frame skin can not drift apart, the Hunter page's
--- rule). The skin tables are FX.Warlock.<Frame>Skin.
local function skin(skinName, key, fallback)
    local s = FX.Warlock[skinName]
    local v = s and s[key]
    if v == nil then return fallback end
    if type(v) == "table" then
        local out = {}
        for i = 1, 4 do out[i] = v[i] end
        return out
    end
    return v
end

-- The plate geometry is the original's: the frame is Width(100)+2*BORDER(3)
-- = 106 wide x 20 high (Forte_Soulstone.lua:65 + Forte_Core.lua:479;
-- Forte_Soulstone.xml:124), the `<Name>Height` keys are the second-line bar
-- heights (the original's SoulstoneHeight/SummonHeight/HealthstoneHeight,
-- Forte_Soulstone.lua:671, Forte_Summon.lua:587, Forte_Healthstone.lua:339).
local DEFAULTS = {
    -- Shared Basics (the four frames' master switch, the shared lock, the
    -- shared time/label text switch).
    Enable = true,
    Lock = true,
    ShowTime = true,
    -- Shard Manager
    ShardEnable = true,
    ShardSize = 106,
    ShardColor = skin("ShardsSkin", "TextColor", { 1, 1, 1, 1 }),
    -- Soulstone Tracker
    SoulstoneEnable = true,
    SoulstoneWidth = 106,
    SoulstoneHeight = 12,
    SoulstoneColor = skin("SoulstoneSkin", "BarColor",
        { 0.64, 0.21, 0.93, 1 }),                 -- Forte_Soulstone.xml:119
    -- Healthstone Spy
    HealthstoneEnable = true,
    HealthstoneSize = 106,
    HealthstoneColor = skin("HealthstoneSkin", "TextColor", { 1, 1, 1, 1 }),
    -- Summon Assistant
    SummonEnable = true,
    SummonWidth = 106,
    SummonHeight = 12,
    SummonColor = skin("SummonSkin", "BarColor",
        { 0.64, 0.21, 0.93, 1 }),                -- Forte_Summon.lua:597
    -- Shared appearance (the Classic purple-plate law of ref4.png, the
    -- original's SoulstoneBgColor, Forte_Soulstone.lua:659): the plate wash
    -- and the backdrop are ONE pair for the four frames.
    BarColor = skin("ShardsSkin", "BgColor", { 0.31, 0.00, 0.62, 0.75 }),
    TextColor = skin("ShardsSkin", "TextColor", { 1, 1, 1, 1 }),
    BgColor = skin("ShardsSkin", "BgColor", { 0.31, 0.00, 0.62, 0.75 }),
}

local VIEWS = { "Shards", "Soulstone", "Healthstone", "Summon" }

local wired = false
local function ensureWiring()
    if wired then return end
    wired = true
    FX.Settings:OnChange(M, function(key, value)
        for i = 1, #VIEWS do
            local v = FX.Warlock[VIEWS[i]]
            if v and v.ApplySettings then
                v:ApplySettings({ [key] = value })
            end
        end
    end)
    -- m4: mirror the LIVE lock state of the frames into the store right
    -- before a checkbox/header icon reads it.
    for i = 1, #VIEWS do
        local v = FX.Warlock[VIEWS[i]]
        if v and v.cfg and v.cfg.locked ~= nil then
            local live = v.cfg.locked and true or false
            if FX.Settings:Get(M, "Lock") ~= live then
                FX.Settings:Set(M, "Lock", live)
            end
            break
        end
    end
end

--- The shared "Basics" section every page opens with: the tool's own switch
--- plus the module's master switch, lock and text switch.
local function basics(s, enableKey, tip)
    s.CHK({ module = M, key = enableKey, label = "Enable",
        tip = tip })
    s.CHK({ module = M, key = "Enable", label = "Enable warlock tools",
        tip = "Master switch of all four warlock frames. Off hides every one of them live." })
    s.CHK({ module = M, key = "Lock", label = "Lock",
        tip = "Lock the frames against dragging (moves with /fx lock|unlock and Global Frame Lock)." })
    s.CHK({ module = M, key = "ShowTime", label = "Show time and label text",
        tip = "The timer/label text on the bars, the shard source label and the stone cooldown text. Applied live." })
end

--- The shared colour section (the per-tool tint plus the shared pair).
local function colours(s, colourKey, colourLabel, colourTip)
    s.COL({ module = M, key = colourKey, label = colourLabel,
        tip = colourTip })
    s.COL({ module = M, key = "BarColor", label = "Plate colour",
        tip = "The dark-purple plate wash (default the original's SoulstoneBgColor .31/0/.62/.75). Applied live." })
    s.COL({ module = M, key = "BgColor", label = "Background colour",
        tip = "Plate backdrop (default the original's SoulstoneBgColor .31/0/.62/.75). Applied live." })
end

-- ------------------------------------------------------------------ pages --
local PAGES = {
    {
        id = "ShardManager", title = "Shard Manager",
        colourKey = "PURPLE", enableKey = "ShardEnable",
        tips = {
            "The soul shard count, read from the bags (the power bar is the second source).",
            "The plate is the count (x<n>); the label right of it prints <n> total and the second line names which source answered.",
            "Count only: ForteXorcist never spends or gates on shards.",
            "The original's Shard Spy half was a removed module; the raid-wide half is not built.",
        },
        build = function(b)
            b.Tips({
                "The shard count plate; hover it (unlocked) for the source label.",
                "Drag the plate with Lock off; the position is saved per character.",
                "/fx lock and /fx unlock move this plate with the Cooldown bar.",
                "The recycle icon on a section restores that section's defaults.",
            })
            b.Section("Basics", function(s)
                basics(s, "ShardEnable",
                    "Show the shard count plate. Off hides it live.")
            end, {
                module = M,
                keys = { "ShardEnable", "Enable", "Lock", "ShowTime" },
                tip = "Master switches of the Shard Manager.",
            })
            b.Section("Frame Sizing", function(s)
                s.NUM({ module = M, key = "ShardSize", label = "Plate width",
                    min = 60, max = 400, step = 1,
                    tip = "Shard plate width in px (default 106 = 100 + 2*3, the original's frame width). Resizes live." })
            end, {
                module = M, keys = { "ShardSize" },
                tip = "Width of the shard plate.",
            })
            b.Section("Coloring", function(s)
                colours(s, "ShardColor", "Count colour",
                    "The shard count text (default white). Applied live.")
            end, {
                module = M, keys = { "ShardColor", "BarColor", "BgColor" },
                tip = "Count, plate and backdrop colours.",
            })
        end,
    },
    {
        id = "Soulstone", title = "Soulstone Tracker",
        colourKey = "PURPLE", enableKey = "SoulstoneEnable",
        build = function(b)
            b.Tips({
                "The plate prints x<n> and `no ss up` while no stone we cast is up; the second line then carries <bearer> and the m:ss.",
                "The window is PREDICTED from our own cast: Forever hides auras in combat, so no raid-wide panel is built (SS-05).",
                "Drag the plate with Lock off; the position is saved per character.",
                "The recycle icon on a section restores that section's defaults.",
            })
            b.Section("Basics", function(s)
                basics(s, "SoulstoneEnable",
                    "Show the soulstone timer bar. Off hides it live.")
            end, {
                module = M,
                keys = { "SoulstoneEnable", "Enable", "Lock", "ShowTime" },
                tip = "Master switches of the Soulstone Tracker.",
            })
            b.Section("Frame Sizing", function(s)
                s.NUM({ module = M, key = "SoulstoneWidth", label = "Plate width",
                    min = 60, max = 1024, step = 1,
                    tip = "Plate width in px (default 106 = 100 + 2*3, the original's frame width). Resizes live." })
                s.NUM({ module = M, key = "SoulstoneHeight", label = "Bar height",
                    min = 4, max = 64, step = 1,
                    tip = "Second-line bar height in px (default 12, the original's SoulstoneHeight). Resizes live." })
            end, {
                module = M, keys = { "SoulstoneWidth", "SoulstoneHeight" },
                tip = "Geometry of the soulstone plate and its bar.",
            })
            b.Section("Coloring", function(s)
                colours(s, "SoulstoneColor", "Bar colour",
                    "The bar fill (default the Soulstone category colour .64/.21/.93). Applied live.")
            end, {
                module = M,
                keys = { "SoulstoneColor", "BarColor", "BgColor" },
                tip = "Fill and backdrop colours.",
            })
        end,
    },
    {
        id = "Healthstone", title = "Healthstone Spy",
        colourKey = "GREEN", enableKey = "HealthstoneEnable",
        build = function(b)
            b.Tips({
                "The plate carries the healthstone count in OUR bags and the stone's item cooldown.",
                "The plate dims and prints the time left while the stone is on its cooldown.",
                "The raid-wide spy half was raid comms in the original; Phase 6, not built.",
                "The recycle icon on a section restores that section's defaults.",
            })
            b.Section("Basics", function(s)
                basics(s, "HealthstoneEnable",
                    "Show the healthstone plate. Off hides it live.")
            end, {
                module = M,
                keys = { "HealthstoneEnable", "Enable", "Lock", "ShowTime" },
                tip = "Master switches of the Healthstone Spy.",
            })
            b.Section("Frame Sizing", function(s)
                s.NUM({ module = M, key = "HealthstoneSize",
                    label = "Plate width", min = 60, max = 400, step = 1,
                    tip = "Healthstone plate width in px (default 106 = 100 + 2*3, the original's frame width). Resizes live." })
            end, {
                module = M, keys = { "HealthstoneSize" },
                tip = "Width of the healthstone plate.",
            })
            b.Section("Coloring", function(s)
                colours(s, "HealthstoneColor", "Count colour",
                    "The healthstone count text (default white). Applied live.")
            end, {
                module = M, keys = { "HealthstoneColor", "BarColor", "BgColor" },
                tip = "Count, plate and backdrop colours.",
            })
        end,
    },
    {
        id = "Summon", title = "Summon Assistant",
        colourKey = "PURPLE", enableKey = "SummonEnable",
        build = function(b)
            b.Tips({
                "The bar is the Ritual of Summoning channel: it fills as the channel runs, with the seconds left.",
                "The channel is PREDICTED from our own cast events and self-expires at the data's cast time.",
                "The roster/distance list of the original sampled the world map: not feasible on Forever (SU-02), so it is not built.",
                "The recycle icon on a section restores that section's defaults.",
            })
            b.Section("Basics", function(s)
                basics(s, "SummonEnable",
                    "Show the ritual channel indicator. Off hides it live.")
            end, {
                module = M,
                keys = { "SummonEnable", "Enable", "Lock", "ShowTime" },
                tip = "Master switches of the Summon Assistant.",
            })
            b.Section("Frame Sizing", function(s)
                s.NUM({ module = M, key = "SummonWidth", label = "Plate width",
                    min = 60, max = 1024, step = 1,
                    tip = "Plate width in px (default 106 = 100 + 2*3, the original's frame width). Resizes live." })
                s.NUM({ module = M, key = "SummonHeight", label = "Bar height",
                    min = 4, max = 64, step = 1,
                    tip = "Second-line bar height in px (default 12, the original's SummonHeight). Resizes live." })
            end, {
                module = M, keys = { "SummonWidth", "SummonHeight" },
                tip = "Geometry of the summon plate and its bar.",
            })
            b.Section("Coloring", function(s)
                colours(s, "SummonColor", "Bar colour",
                    "The channel fill (default the original's SummoningColor .64/.21/.93). Applied live.")
            end, {
                module = M,
                keys = { "SummonColor", "BarColor", "BgColor" },
                tip = "Fill and backdrop colours.",
            })
        end,
    },
}

--- Register the settings defaults + the four pages. Idempotent; needs
--- FX.Settings + FX.Options. Returns true when the pages are registered.
function P.RegisterWarlockPages()
    local O = FX.Options
    if not O or not O.pages or not FX.Settings then return false end
    local registered = 0
    for _, def in ipairs(PAGES) do
        if not O.pages[def.id] then
            FX.Settings:Register(M, DEFAULTS)
            O:RegisterPage({
                id = def.id,
                module = M,
                title = def.title,
                colour = O.C[def.colourKey],
                lockKey = "Lock",
                build = function(b)
                    ensureWiring()
                    def.build(b)
                end,
            })
        end
        if O.pages[def.id] then registered = registered + 1 end
    end
    return registered == #PAGES
end

-- Load-time fast path: Forte_Options ran first (the loader honoured the
-- OptionalDeps), so register right now. Otherwise FX.Warlock.UI:OnEnable
-- (PLAYER_LOGIN) calls the same function once every chunk has run.
P.RegisterWarlockPages()
