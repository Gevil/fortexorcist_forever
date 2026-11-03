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
-- UI/Frame.lua law) and each frame self-wires the store to that seam from its
-- own Init/OnEnable (`Frame:_HookSettings`, the one live settings path —
-- Forte_Warlock works with Forte_Options not installed; the page ships NO
-- second mirror, review 3 m4 deleted the dead one). Saved values are applied
-- at login by the frames' ApplyStoredSettings. Lock follows the Forte_Cooldown
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
    -- FWL.EXPAND_UP ("Expand up", Forte_Core.lua:243): the bar list grows up
    -- from the plate instead of hanging below it. The original's
    -- SoulstoneExpand, Forte_Soulstone.lua:604, def false :674.
    SoulstoneExpand = false,
    -- The READY-look gate (the original's ShowReady, Forte_Soulstone.lua:608,
    -- def false :667) and its colour (the "Resurrect" row's ReadyColor, def
    -- {1,1,0} :651): with the gate on, a warlock with no stone up and no
    -- stone on cooldown prints `ready to res` where the plate otherwise
    -- prints `no ss up` (Forte_Soulstone.lua:309).
    SoulstoneShowReady = false,
    SoulstoneReadyColour = skin("SoulstoneSkin", "ReadyColour",
        { 1.00, 1.00, 0.00, 1 }),
    -- Healthstone Spy
    HealthstoneEnable = true,
    HealthstoneSize = 106,
    HealthstoneColor = skin("HealthstoneSkin", "TextColor", { 1, 1, 1, 1 }),
    -- H6 group comms (Core/Comms.lua): ON by default, and the send gate is
    -- "in a group" -- solo the comms never transmit (the law, not the key).
    CommsEnable = true,
    -- The "No info" spy bar (the original's HealthstoneUnknown, default
    -- true, Forte_Healthstone.lua:333).
    HealthstoneUnknown = true,
    -- FWL.EXPAND_UP / AUTO_HIDE / SHOW_BARS / AUTO_MINIMIZE / BAR_SPACING
    -- (the original's HealthstoneExpand :609, HealthstoneAuto :606,
    -- HealthstoneDetails :608, HealthstoneDetailsAuto :607, HealthstoneSpace
    -- :611 -- the defaults at Forte_Healthstone.lua:340-345).
    HealthstoneExpand = false,
    HealthstoneAuto = false,
    HealthstoneDetails = true,
    HealthstoneDetailsAuto = false,
    HealthstoneSpace = 1,
    -- FWL.HEALTHSTONE_DRAW_INTERVAL ("Healthstone draw interval",
    -- Forte_Core.lua:283; the original's HealthstoneInterval,
    -- Forte_Healthstone.lua:318 with SetRange(0.5,5), def 2 at :321). The
    -- 2012 body of the key is the roster RESAMPLE cadence
    -- (`FW:Delay(FW.Default.HealthstoneInterval, FWHS_Update)`,
    -- Forte_Healthstone.lua:113-116): the spy re-asked its members that
    -- often. The resampler lives in the add-on's Core/Comms.lua (the one
    -- file that ticks the roster), so that is the key's consumer here; the
    -- plate draws on the data's arrival, not on a timer.
    HealthstoneInterval = 2,
    -- FWL.LITTLE_HS / MANY_HS / LITTLE_UNKNOWN / MANY_UNKNOWN
    -- (Forte_Healthstone.lua:303-306; the defaults :328-331 verbatim). The
    -- spy bars' colour ramp: `ColorVal` = MIN mixed toward MAX by the bar's
    -- value (Forte_Healthstone.lua:104-111, FW:MixColors
    -- Forte_Core.lua:2080-2084).
    HealthstoneMinColor = { 0.93, 1.00, 0.00, 1 },
    HealthstoneMaxColor = { 0.53, 1.00, 0.00, 1 },
    HealthstoneUnknownMinColor = { 0.53, 1.00, 0.00, 1 },
    HealthstoneUnknownMaxColor = { 1.00, 0.00, 0.00, 1 },
    -- Summon Assistant
    SummonEnable = true,
    SummonWidth = 106,
    SummonHeight = 12,
    SummonColor = skin("SummonSkin", "BarColor",
        { 0.64, 0.21, 0.93, 1 }),                -- Forte_Summon.lua:597
    -- FWL.SHOW_BARS / EXPAND_UP (the original's SummonDetails,
    -- Forte_Summon.lua:562, def true :595; SummonExpand :564, def false
    -- :598): the summon plate's queue bars and their direction.
    SummonDetails = true,
    SummonExpand = false,
    -- Shared appearance (the Classic purple-plate law of ref4.png, the
    -- original's SoulstoneBgColor, Forte_Soulstone.lua:659): the plate wash
    -- and the backdrop are ONE pair for the four frames.
    BarColor = skin("ShardsSkin", "BgColor", { 0.31, 0.00, 0.62, 0.75 }),
    TextColor = skin("ShardsSkin", "TextColor", { 1, 1, 1, 1 }),
    BgColor = skin("ShardsSkin", "BgColor", { 0.31, 0.00, 0.62, 0.75 }),
}

local VIEWS = { "Shards", "Soulstone", "Healthstone", "Summon" }

local lockPublished = false
local function publishLiveLock()
    if lockPublished then return end
    lockPublished = true
    -- Review 3 m4: the page-side `FX.Settings:OnChange` mirror that used to
    -- live here is GONE. It routed every key to `v:ApplySettings`, a method
    -- no Warlock frame has (the grep of Forte_Warlock: zero definitions), so
    -- the guard never fired -- dead code. The frames' self-wiring
    -- (`Frame:_HookSettings`, run from Init and OnEnable, with its own m1
    -- `_wired` guard) is the one live settings path; the `_HookSettings`
    -- keymap is the Warlock idiom, so no `ApplySettings` seam is added.
    -- The Forte_Cooldown m4 lock law: mirror the LIVE lock state of the
    -- frames into the store right before a checkbox/header icon reads it.
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
        view = "Shards",           -- C4: the page's live lock frame
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
        view = "Soulstone",        -- C4: the page's live lock frame
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
                -- FWL.EXPAND_UP ("Expand up", Forte_Core.lua:243; the
                -- original's SoulstoneExpand, Forte_Soulstone.lua:604).
                s.CHK({ module = M, key = "SoulstoneExpand",
                    label = "Expand up",
                    tip = "The bar run grows UPWARD from the plate instead of hanging below it (the original's Expand up). Relayouts live." })
            end, {
                module = M,
                keys = { "SoulstoneWidth", "SoulstoneHeight",
                         "SoulstoneExpand" },
                tip = "Geometry of the soulstone plate and its bar.",
            })
            b.Section("Coloring", function(s)
                colours(s, "SoulstoneColor", "Bar colour",
                    "The bar fill (default the Soulstone category colour .64/.21/.93). Applied live.")
                -- FWL.RESURRECT ("Resurrect", Forte_Core.lua:229): the
                -- colour of the `ready to res` readout -- the original's
                -- ReadyColor (Forte_Soulstone.lua:609, default {1,1,0}
                -- :651), applied to the header label whose show gate is the
                -- box above it.
                s.CHK({ module = M, key = "SoulstoneShowReady",
                    label = "Show the ready readout",
                    tip = "With a window that has run out and no new stone on its way, the plate prints `ready to res` in the colour below where it otherwise prints `no ss up` (the original's ShowReady gate, Forte_Soulstone.lua:608, default off). Applied live." })
                s.COL({ module = M, key = "SoulstoneReadyColour",
                    label = "Resurrect",
                    tip = "The colour of the `ready to res` readout (the original's ReadyColor, default 1/1/0). Applied live." })
            end, {
                module = M,
                keys = { "SoulstoneColor", "BarColor", "BgColor",
                         "SoulstoneShowReady", "SoulstoneReadyColour" },
                tip = "Fill, backdrop and the ready-readout colours.",
            })
        end,
    },
    {
        id = "Healthstone", title = "Healthstone Spy",
        colourKey = "GREEN", enableKey = "HealthstoneEnable",
        view = "Healthstone",      -- C4: the page's live lock frame
        build = function(b)
            b.Tips({
                "The plate carries the healthstone count in OUR bags and the stone's item cooldown.",
                "The plate dims and prints the time left while the stone is on its cooldown.",
                "In a group the spy half rides the addon comms: the Total bar is the warlocks-with-stones over the members reporting, the No-info bar the members without ForteXorcist, the right label x<missing>.",
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
            b.Section("Raid Spy", function(s)
                s.CHK({ module = M, key = "CommsEnable",
                    label = "Group comms",
                    tip = "Talk to other ForteXorcists in the group (party/raid addon channel): report stone and shard counts, hear who is summoning. Solo it never sends; a chat-messaging lockdown skips the sends. " })
                s.CHK({ module = M, key = "HealthstoneUnknown",
                    label = "Show players with no info",
                    tip = "The second bar counts the members whose addon has not answered (the original's HealthstoneUnknown, default on)." })
                -- FWL.AUTO_HIDE ("Auto-hide outside party/raid", the
                -- original's HealthstoneAuto, Forte_Healthstone.lua:289):
                -- the plate's own show gate.
                s.CHK({ module = M, key = "HealthstoneAuto",
                    label = "Auto-hide outside party/raid",
                    tip = "Hide the plate outside a group (the original's Auto-hide). Applied live." })
                -- FWL.SHOW_BARS / AUTO_MINIMIZE (HealthstoneDetails +
                -- HealthstoneDetailsAuto, Forte_Healthstone.lua:287-288):
                -- the bars' show gate, `Details and (not DetailsAuto or
                -- GROUPED)` (Forte_Healthstone.lua:143).
                s.CHK({ module = M, key = "HealthstoneDetails",
                    label = "Show bars",
                    tip = "The two spy bars (Total, No-info). Off leaves only the plate's header line (the original's Show bars)." })
                s.CHK({ module = M, key = "HealthstoneDetailsAuto",
                    label = "Auto-minimize outside party/raid",
                    tip = "Hide the bars outside a group (the original's Auto-minimize)." })
            end, {
                module = M,
                keys = { "CommsEnable", "HealthstoneUnknown",
                         "HealthstoneAuto", "HealthstoneDetails",
                         "HealthstoneDetailsAuto" },
                tip = "The raid-wide spy half.",
            })
            b.Section("Frame Sizing", function(s)
                s.NUM({ module = M, key = "HealthstoneSize",
                    label = "Plate width", min = 60, max = 400, step = 1,
                    tip = "Healthstone plate width in px (default 106 = 100 + 2*3, the original's frame width). Resizes live." })
                -- FWL.BAR_SPACING (the original's HealthstoneSpace,
                -- Forte_Healthstone.lua:300): the gap of the bar run.
                s.NUM({ module = M, key = "HealthstoneSpace",
                    label = "Bar spacing", min = 0, max = 20, step = 1,
                    tip = "Gap between the spy bars in px (the original's Bar spacing, default 1). Relayouts live." })
                -- FWL.EXPAND_UP (the original's HealthstoneExpand,
                -- Forte_Healthstone.lua:292).
                s.CHK({ module = M, key = "HealthstoneExpand",
                    label = "Expand up",
                    tip = "The bar run grows UPWARD from the plate instead of hanging below it (the original's Expand up). Relayouts live." })
                -- FWL.HEALTHSTONE_DRAW_INTERVAL ("Healthstone draw
                -- interval", Forte_Core.lua:283; the original's
                -- HealthstoneInterval with SetRange(0.5,5),
                -- Forte_Healthstone.lua:318, def 2 :321).
                s.NUM({ module = M, key = "HealthstoneInterval",
                    label = "Healthstone draw interval",
                    min = 0.5, max = 5, step = 0.1,
                    tip = "Seconds between the spy's roster resamples (the original's Healthstone draw interval, default 2, range 0.5-5). The plate draws when the data arrives; this paces the asking. " })
            end, {
                module = M,
                keys = { "HealthstoneSize", "HealthstoneSpace",
                         "HealthstoneExpand", "HealthstoneInterval" },
                tip = "Width, spacing, direction and resample interval.",
            })
            b.Section("Coloring", function(s)
                colours(s, "HealthstoneColor", "Count colour",
                    "The healthstone count text (default white). Applied live.")
                -- FWL.LITTLE_HS / MANY_HS / LITTLE_UNKNOWN / MANY_UNKNOWN
                -- (the original's HealthstoneMinColor/MaxColor/
                -- UnknownMinColor/UnknownMaxColor, Forte_Healthstone.lua:
                -- 303-306): the spy bars' colour ramp -- a nearly-full bar
                -- reads the "many" colour, an empty one the "little".
                s.COL({ module = M, key = "HealthstoneMinColor",
                    label = "Little Healthstones",
                    tip = "Low end of the Total bar's colour ramp (the original's default .93/1/0). Applied live." })
                s.COL({ module = M, key = "HealthstoneMaxColor",
                    label = "Many Healthstones",
                    tip = "High end of the Total bar's colour ramp (the original's default .53/1/0). Applied live." })
                s.COL({ module = M, key = "HealthstoneUnknownMinColor",
                    label = "Little unknown",
                    tip = "Low end of the No-info bar's colour ramp (the original's default .53/1/0). Applied live." })
                s.COL({ module = M, key = "HealthstoneUnknownMaxColor",
                    label = "Many unknown",
                    tip = "High end of the No-info bar's colour ramp (the original's default 1/0/0). Applied live." })
            end, {
                module = M,
                keys = { "HealthstoneColor", "BarColor", "BgColor",
                         "HealthstoneMinColor", "HealthstoneMaxColor",
                         "HealthstoneUnknownMinColor",
                         "HealthstoneUnknownMaxColor" },
                tip = "Count, plate, backdrop and the spy bars' ramps.",
            })
        end,
    },
    {
        id = "Summon", title = "Summon Assistant",
        colourKey = "PURPLE", enableKey = "SummonEnable",
        view = "Summon",           -- C4: the page's live lock frame
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
                -- FWL.SHOW_BARS (the original's SummonDetails,
                -- Forte_Summon.lua:562): the ritual rows -- the plate's
                -- header line (the count, the clock) stays either way.
                s.CHK({ module = M, key = "SummonDetails",
                    label = "Show bars",
                    tip = "The ritual rows: my channel's bar and one row per ritual of the raid. Off leaves the plate's count and clock (the original's Show bars)." })
                -- FWL.EXPAND_UP (the original's SummonExpand,
                -- Forte_Summon.lua:564).
                s.CHK({ module = M, key = "SummonExpand",
                    label = "Expand up",
                    tip = "The bar run grows UPWARD from the plate instead of hanging below it (the original's Expand up). Relayouts live." })
            end, {
                module = M,
                keys = { "SummonWidth", "SummonHeight", "SummonDetails",
                         "SummonExpand" },
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
                -- C4: the header glyph reads THIS page's plate. The four
                -- plates share the one Warlock.Lock key (the shared lock
                -- law of UI/Frame.lua), so they move as one lock unit; a
                -- divergence between a plate and the Cooldown bar is the
                -- n4/C4 case the header must follow, not swallow.
                lockFrame = function() return FX.Warlock[def.view] end,
                build = function(b)
                    publishLiveLock()
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
