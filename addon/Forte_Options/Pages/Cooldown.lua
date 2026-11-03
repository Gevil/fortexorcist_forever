-- Forte_Options/Pages/Cooldown.lua
-- The Cooldown Timer page (sections Some Tips / Basics / Specifics /
-- Coloring / Frame Appearance). Defaults mirror the design law, PLAN §3.5
-- (Forte_Cooldown.lua :1801-1866): one 250x24 power-scale bar, Max 300,
-- Loga 0.33, tags "0 1 10 30 60 120 300 600", IgnoreCooldown 2.99, verbatim
-- category colours.
--
-- Wiring: every key on this page drives FX.Cooldown.Display live (see the
-- contract at the seam below); IgnoreShort drives Engine.MIN_COOLDOWN.
-- No key of this page is stored-only any more.
--
-- CD-35/CD-31 (2026-11-02): the three geometry rows of the original's Basics
-- block (Vertical :1705, Flip :1706, "Auto-hide when no cooldowns" :1707) and
-- its Specifics Warn row (:1714) joined the page, at the shipped defaults
-- (:1808/:1809/:1815/:1821) and with the original's own labels
-- (Localization.lua :108-111, :158-159, :510-511). All four are live through
-- Display:ApplySettings -> SetVertical / SetFlip / SetHideZero / SetWarn.
--
-- F-C (2026-11-03): the SPECIFICS block also carries
-- "Item proc timers (experimental)" = `Cooldown.Procs`, the one public face
-- of Forte_Cooldown/Core/Procs.lua. It is the ONLY key of this page the
-- Display does not consume: Forte_Cooldown's own `Procs:_WireSettings`
-- listener is the consumer (the module must work with Forte_Options
-- uninstalled), which is why the key is absent from the Display's KEYMAP by
-- design. Default OFF; the first enable loads the load-on-demand
--   Forte_ItemProcs data add-on.
--
-- OptionsCD (2026-11-03, wave 4 items 2+4): the page now carries the rows of
-- the source's SPECIFICS icon block (`Alpha` :1716 / `AlphaMax` :1717 ->
-- `BarAlpha`/`BarAlphaMax`; `IconTime` :1718; `IconTextColor` :1719 with its
-- [0] gate on `IconTextColorOn`), its SPLASH block (`Splash` :1723,
-- `SplashFactor` :1724) and its TIME RANGE filters (`MinRange`/`MaxRange`/
-- `MinRemaining`/`MaxRemaining` :1729-1732, the NU2 gate on a `<Key>On` key;
-- values 0/3600/0/3600, every gate OFF -- :1826-1829). The labels are the
-- source's strings verbatim (Forte_Cooldown/Localization.lua :118, :122,
-- :124, :140, :161, :163, :175, :177, :180, :182, :185; FWL.TIMER_HIDE in
-- Forte_Core/Localization.lua:526; FWL.SHOW_GLOW :145), and the relabels that
-- came with them: "Hide when not in combat" -> "Hide when out of combat",
-- "Max time" -> "Time scale max (sec)", "Power scale (Loga)" -> "Use power
-- of", "Spark" -> "Show icon Glow". The survey's section ruling stands (the
-- section names and the 5-section layout are ours, docs/research/
-- options-fidelity.md), so the new rows ride Specifics. Every key has a live
-- consumer in Forte_Cooldown/UI/Timeline.lua (SetBarAlpha/SetBarAlphaMax,
-- SetIconTime, SetIconTextColor(On), SetSplashOn/SetSplashFactor, the eight
-- Set<Filter>/Set<Filter>On pair, the filter law of CD_TimeFilterDuration /
-- CD_TimeFilterRemaining :488-495 in D:Update).
--
-- Cosmetics (2026-11-03, wave 6 fix-list item 9): the FRAME SIZING block's
-- IconSize pair (:1760, the shipped default gate-OFF 36 :1805) and the
-- APPEARANCE "Bar text" colour (:1765, default {1,1,1,0.20} :1838) joined
-- the page, at the source's own spots (Sizing rows follow Height, the
-- colour rows ride Frame Appearance). Consumers: Forte_Cooldown/UI/
-- Timeline.lua's SetIconSize/SetIconSizeOn (`_ResizeIconPools` runs the
-- source's `ih = IconSize[0] and IconSize[1] or Height` law :1151/:1364
-- over the slots, the splashes and the pulses; the axis curve, the tags
-- and the segments keep riding Height, :502/:1236 -- the icons grow in
-- place, they do not move) and SetTextColor (the time-tag strings, the
-- source's SetTimeTags :1270/:1289).

ForteXorcist = ForteXorcist or {}
local FX = ForteXorcist
local O = FX.Options

local M = "Cooldown"

FX.Settings:Register(M, {
    -- Basics (the original's BASICS rows, Forte_Cooldown.lua :1704-1708:
    -- Enable, "Flip to vertical", "Flip bar direction", "Auto-hide when no
    -- cooldowns", "Hide when not in combat"; defaults :1808/:1809/:1815/:1816)
    Enable = true,
    Lock = true,
    Vertical = false,
    Flip = false,
    HideZero = false,
    HideCombat = false,
    -- Specifics (PLAN §3.5 + the SPECIFICS row :1714 "Spell on cooldown
    -- Warning", default Warn = true :1821)
    Warn = true,
    Width = 250,
    Height = 24,
    -- The FRAME SIZING block's third row (:1760, the source's NU2 type =
    -- a value plus its `[0]` gate). The shipped gate is OFF
    -- (`IconSize = {[0]=false,36}` :1805): icons ride the bar height
    -- (`ih = s.IconSize[0] and s.IconSize[1] or s.Height` :1151, :1364).
    -- On, icons, glows, splashes and pulses ride IconSize; the axis, the
    -- tags and the segments keep riding Height (:502, :1236).
    IconSizeOn = false,
    IconSize = 36,
    -- The bar alpha RANGE (the SPECIFICS rows :1716 "Minimum bar alpha" and
    -- :1717 "Maximum bar alpha" = the source's `Alpha` :1818 / `AlphaMax`
    -- :1819). Our keys carry the Bar prefix: this module's `Alpha` key is
    -- the header frame's alpha (OP-06), a different law.
    BarAlpha = 0.2,
    BarAlphaMax = 1.0,
    -- The icon text block (SPECIFICS :1718 "Show Icon text" -> `IconTime`
    -- true :1835; :1719 "Icon text color" -> `IconTextColor`
    -- {[0]=false, 1,1,1,1} :1837, the [0] gate on its own key).
    IconTime = true,
    IconTextColorOn = false,
    IconTextColor = { 1.00, 1.00, 1.00, 1.00 },
    -- The SPLASH block (:1723 "Splash ready cooldowns" -> `Splash` true
    -- :1811; :1724 "Splash icon active scale" -> `SplashFactor` 4 :1812, the
    -- row's SetRange(1) floor).
    Splash = true,
    SplashFactor = 4,
    MaxTime = 300,
    PowerScale = 0.33,                 -- Loga
    -- The TIME RANGE filters (:1729-1732, the NU2 rows = a value plus its
    -- `[0]` gate): the values are 0 / 3600 / 0 / 3600 (:1826-1829) and every
    -- gate ships OFF, so a fresh bar shows every cooldown.
    MinRangeOn = false,      MinRange = 0,
    MaxRangeOn = false,      MaxRange = 3600,
    MinRemainingOn = false,  MinRemaining = 0,
    MaxRemainingOn = false,  MaxRemaining = 3600,
    TimeTags = "0 1 10 30 60 120 300 600",
    IgnoreShort = 2.99,                -- Engine.MIN_COOLDOWN
    -- The item/weapon proc ICD windows (Core/Procs.lua). The key is
    -- registered so the store owns the default -- OFF -- per
    -- docs/design-combat-procs.md P-B, so the SPECIFICS row "Item proc timers
    -- (experimental)" (added 2026-11-03, slice F-C) writes it through
    -- FX.Settings:Set like every other key of this page, and so the
    -- Cooldown module's `/fx status` line ("Procs: on/off, N watched")
    -- reports the very state the box drives. The switch is live through
    -- Procs:_WireSettings' listener, and ApplyStoredSettings applies it at
    -- login. Flipping it on loads the load-on-demand Forte_ItemProcs data
    -- add-on (docs/perf.md §4 fix 1), which is the whole reason it is not on
    -- by default.
    Procs = false,
    -- Coloring (Forte_Cooldown.lua :1842-1855, verbatim)
    ColorSpell     = { 1.00, 0.50, 0.00, 1 },
    ColorPowerup   = { 0.00, 0.75, 1.00, 1 },
    ColorItem      = { 1.00, 1.00, 0.00, 1 },
    ColorPotion    = { 0.00, 1.00, 0.00, 1 },
    ColorPet       = { 1.00, 0.00, 0.95, 1 },
    ColorInternal  = { 0.00, 0.60, 0.85, 1 },
    ColorBuff      = { 1.00, 1.00, 1.00, 1 },
    ColorDebuff    = { 1.00, 0.00, 0.00, 1 },
    -- Frame Appearance (BarColor / BgColor / Spark, :1820 + §3.5)
    BarColor = { 1, 1, 1, 0.20 },
    BgColor = { 0, 0, 0, 0.50 },
    -- The APPEARANCE row "Bar text" (:1765, FWL.BAR_TEXT,
    -- Localization.lua:1019), default {1,1,1,0.20} (:1838): the TIME-TAG
    -- text colour (the source's only consumer: SetTimeTags :1270, :1289).
    TextColor = { 1, 1, 1, 0.20 },
    Spark = true,
    -- Header-bar frame fields (OP-06: scale 0.2..5.0, alpha 0.1..1.0)
    Scale = 1.0,
    Alpha = 1.0,
})

-- Wiring contract (T9, 2026-11-02): every key of this module has a public
-- setter seam on FX.Cooldown.Display -- the listener below routes each
-- change through Display:ApplySettings, which maps the key onto its
-- setter (size/Max/Loga/tags -> geometry rebuild of exactly what moved,
-- colours -> TimelineSkin colors + live slot re-tint, BarColor/BgColor/
-- Spark/Scale/Alpha/Enable/HideCombat/AltTimeFormat/BarFont/BarTexture ->
-- their own seams, IgnoreShort -> Engine.MIN_COOLDOWN + a tracked rebuild).
-- Saved values are applied at login by Display:Init (ApplyStoredSettings)
-- and the OnChange listeners make every edit live. Lock is the exception
-- (m4): the LIVE lock state on the bar is the truth -- SetLocked publishes
-- it into Lock/GlobalLock, and the first page build mirrors the live state
-- INTO the store (never the other way), so the checkboxes, the header icon
-- and /fx lock|unlock can never disagree.
--
-- Display:Init also self-wires these two modules (Forte_Cooldown must work
-- without Forte_Options installed); this listener is the page-side mirror
-- and is idempotent with it.

local function display()
    return FX.Cooldown and FX.Cooldown.Display
end

local function pushLiveLock()
    local d = display()
    if not d or not d.cfg or d.cfg.locked == nil then return end
    local live = d.cfg.locked and true or false
    if FX.Settings:Get(M, "Lock") ~= live then
        FX.Settings:Set(M, "Lock", live)
    end
end

local wired = false
local function ensureWiring()
    if wired then return end
    wired = true
    FX.Settings:OnChange(M, function(key, value)
        local d = display()
        if d and d.ApplySettings then
            d:ApplySettings({ [key] = value })
        end
    end)
    pushLiveLock()
end

O:RegisterPage({
    id = "Cooldown",
    module = M,
    title = "Cooldown Timer",
    colour = O.C.GREEN,
    scaleKey = "Scale",
    alphaKey = "Alpha",
    lockKey = "Lock",
    -- C4: this page drives the timeline bar; its header glyph reads the
    -- bar's LIVE cfg.locked (the m4 publish law), never the store copy.
    lockFrame = display,
    build = function(b)
        ensureWiring()
        -- m4: the checkbox (and the header icon BuildHeader builds after
        -- this) read the STORE, so mirror the live lock state into it on
        -- every page build: /fx unlock then Open("Cooldown") must show an
        -- unchecked Lock box.
        pushLiveLock()
        b.Tips({
            "One power-scale timeline: fresh cooldowns ride in from the right.",
            "Drag the bar (with Lock off) to place it; the position is saved.",
            "Colour squares open the colour picker; values print as r g b a.",
            "The recycle icon on a section restores that section's defaults.",
        })
        b.Section("Basics", function(s)
            s.CHK({ module = M, key = "Enable", label = "Enable",
                tip = "Show the Cooldown Timer. Off hides the bar live." })
            s.CHK({ module = M, key = "Lock", label = "Lock",
                tip = "Lock the bar against dragging (shared with Global Frame Lock)." })
            -- CD-35 geometry modes, the original's BASICS rows in its order
            -- (labels verbatim: Localization.lua :108-111, :510-511).
            s.CHK({ module = M, key = "Vertical", label = "Flip to vertical",
                tip = "Change the bar orientation from horizontal to vertical: the icons stack bottom -> top along the bar's height (Forte_Cooldown.lua :1446-1448, :1476-1479). Live." })
            s.CHK({ module = M, key = "Flip", label = "Flip bar direction",
                tip = "Flip the timer bar direction: the icons run right -> left (top -> bottom when vertical) with the time tags and the fills mirrored (Forte_Cooldown.lua :1440-1443). Live." })
            s.CHK({ module = M, key = "HideZero", label = "Auto-hide when no cooldowns",
                tip = "Hide the cooldown timer scale and background when you have no visible cooldowns; the bar returns with the first one (Forte_Cooldown.lua :1348). Live." })
            s.CHK({ module = M, key = "HideCombat", label = "Hide when out of combat",
                tip = "Hide the frame when you get out of combat (FWL.TIMER_HIDE, Forte_Core/Localization.lua:526; the source's BASICS row :1708). Auto-hides the bar out of combat, live with the combat state." })
            -- Wave I-3c (docs/research/upstream-addons-2026-11-03.md §6 "Test
            -- Mode", ranked row 3): the demo control. An ACTION row -- W.BTN
            -- carries no `key` -- deliberately NOT a checkbox: a W.CHK writes
            -- FX.Settings, and a demo mode is not a player preference. The
            -- sparse-store law of Core/Settings.lua says the store holds the
            -- values that differ from the shipped defaults, i.e. the player's
            -- choices; persisting a demo switch would put a fiction in a
            -- profile. One press fills the cooldown bar, the Secondary Splash
            -- and the Spell Timer with synthetic rows of the player's own
            -- class (Forte_Core/Core/TestMode.lua, the `/fx test` command);
            -- pressing again, a combat start or a logout scrubs every one of
            -- them. The state is session-only, so a `/reload` is always off.
            s.BTN({
                label = "Fill the frames with test data",
                text = "Fill",
                tip = "Demo mode (/fx test): put synthetic entries of your OWN spells on the cooldown bar, the splash and the Spell Timer so you can place and judge the frames without a fight. Nothing is sent, nothing is saved, real data resumes -- and a combat start, a logout or a second press scrubs every test entry. It refuses to start while you are in combat.",
                enabled = true,
                onPress = function()
                    if FX.TestMode then FX.TestMode:Toggle() end
                end,
            })
        end, {
            module = M,
            keys = { "Enable", "Lock", "Vertical", "Flip", "HideZero",
                "HideCombat" },
            tip = "Master switch, position lock, bar geometry and visibility.",
        })
        b.Section("Specifics", function(s)
            -- CD-31, the SPECIFICS row :1714 (label verbatim,
            -- Localization.lua :158-159).
            s.CHK({ module = M, key = "Warn", label = "Spell on cooldown Warning",
                tip = "When you try to use an ability that is on cooldown, the timer will focus on this ability: the icon flashes and takes the group's focus (Forte_Cooldown.lua :933-946, :860-877). Live." })
            s.NUM({ module = M, key = "Width", label = "Width",
                min = 60, max = 1024, step = 1,
                tip = "Bar width in px (default 250). Resizes the bar live." })
            s.NUM({ module = M, key = "Height", label = "Height",
                min = 12, max = 128, step = 1,
                tip = "Bar height in px (default 24). Icon size rides it; resizes live." })
            -- The FRAME SIZING block's third row (:1760), the NU2 type =
            -- one value editbox plus its `[0]` gate (the gate rides its
            -- own labelled box, the TIME RANGE pair convention). Labels
            -- verbatim: FWL.ICON_SIZE "Icon size", FWL.ICON_SIZE_TT
            -- "Set the icon sizes independently from the bar height"
            -- (Forte_Cooldown/Localization.lua:173-174).
            s.CHK({ module = M, key = "IconSizeOn",
                label = "Enable custom icon size",
                tip = "The checkbox of the source's \"Icon size\" row (the NU2 at Forte_Cooldown.lua:1760: a value plus its [0] gate, gate default OFF :1805). Off, the icons ride the bar height -- the shipped law (:1151, :1364). Live." })
            s.NUM({ module = M, key = "IconSize", label = "Icon size",
                min = 1, max = 256, step = 1,
                tip = "Set the icon sizes independently from the bar height (Forte_Cooldown.lua:1760, default 36 :1805, behind its Enable box). Resizes the icons, their glows, the splashes and the ready pulses; the axis curve, the time tags and the segments keep riding the bar height (:502, :1236), so the icons grow in place. Live." })
            -- The SPECIFICS icon block of the source, in its row order
            -- (:1716-1719), its labels verbatim (Forte_Cooldown/
            -- Localization.lua :118, :161, :140, :185). `Alpha`/`AlphaMax`
            -- ride the `BarAlpha`/`BarAlphaMax` keys: this module's `Alpha`
            -- key is the header frame's alpha (OP-06), a different law.
            s.NUM({ module = M, key = "BarAlpha", label = "Minimum bar alpha",
                min = 0, max = 1, step = 0.05,
                tip = "This is the visibility (alpha) for a bar at its maximum cooldown duration. In other words, the minimum visibility a bar can get (Forte_Cooldown.lua:1716, default 0.2 :1818). The segment fill runs AlphaMax-(AlphaMax-Alpha)*t7 (:1404) and a fresh icon fades in from here (:1402). Live." })
            s.NUM({ module = M, key = "BarAlphaMax", label = "Maximum bar alpha",
                min = 0, max = 1, step = 0.05,
                tip = "This is the visibility (alpha) for a bar at its minimum cooldown duration. In other words, the maximum visibility a bar can get (Forte_Cooldown.lua:1717, default 1.0 :1819). A settled icon rides exactly this. Live." })
            s.CHK({ module = M, key = "IconTime", label = "Show Icon text",
                tip = "Enable to show the time text on the cooldown icons themselves (Forte_Cooldown.lua:1718, default on :1835). Shown/hidden live on every icon." })
            s.CHK({ module = M, key = "IconTextColorOn",
                label = "Use custom icon text color",
                tip = "The checkbox of the source's \"Icon text color\" row (:1719, the CO2 type: a colour plus its [0] gate, default OFF :1837). On, the icon text takes the colour below; off, it takes the colour of its icon (Forte_Cooldown.lua:1419-1425). Live." })
            s.COL({ module = M, key = "IconTextColor", label = "Icon text color",
                tip = "Use a custom icon text color. If unchecked, the text will take the color of the icon (Forte_Cooldown.lua:1719, default white :1837). Retints every icon on the bar live." })
            -- The SPLASH block (:1723-1724), labels verbatim (:122, :124).
            s.CHK({ module = M, key = "Splash", label = "Splash ready cooldowns",
                tip = "This will show an icon 'splash' at the origin of the cooldown timer each time a cooldown is ready (Forte_Cooldown.lua:1723, default on :1811; the draw gate is s.Splash at :1380). Live: off also clears the splash on screen." })
            s.NUM({ module = M, key = "SplashFactor", label = "Splash icon active scale",
                min = 1, max = 20, step = 0.5,
                tip = "Set what scale factor to use for the icon splash at the middle of the splash animation (Forte_Cooldown.lua:1724, default 4 :1812, the row's floor is 1). The splash grows to this many times the icon. Live." })
            s.NUM({ module = M, key = "MaxTime", label = "Time scale max (sec)",
                min = 5, max = 3600, step = 10,
                tip = "Set the scale of the cooldown bar, by giving the biggest cooldown time in seconds(!) that the bar should display. Cooldowns outside your scale will still show at the end of the bar (Forte_Cooldown.lua:1727, default 300). Curve updates live." })
            s.NUM({ module = M, key = "PowerScale", label = "Use power of",
                min = 0.1, max = 1.0, step = 0.01,
                tip = "Setting this to a lower value means the Cooldown icons will speed up toward the end faster. Setting this to 1.0 means the Cooldown icons will have a constant speed (Forte_Cooldown.lua:1728, default 0.33, the row's range is 0.1-1). Curve updates live." })
            -- The TIME RANGE filters (:1729-1732). The source renders each
            -- one as an NU2 = one value editbox plus its [0] gate checkbox;
            -- the page has one row per key, so the gate gets its own
            -- labelled box and the value row keeps the source's label.
            s.CHK({ module = M, key = "MinRangeOn",
                label = "Enable minimum duration filter",
                tip = "The checkbox of the source's \"Minimum duration\" row (the NU2 type at Forte_Cooldown.lua:1729: a value plus its [0] gate, gate default OFF :1826). Off, the filter is inert. Live." })
            s.NUM({ module = M, key = "MinRange", label = "Minimum duration",
                min = 0, max = 3600, step = 1,
                tip = "Minimum total duration cooldowns must have to be displayed in this cooldown timer instance (Forte_Cooldown.lua:1729, default 0 :1826). Behind its Enable box; the filter runs the pass, live." })
            s.CHK({ module = M, key = "MaxRangeOn",
                label = "Enable maximum duration filter",
                tip = "The checkbox of the source's \"Maximum duration\" row (NU2, Forte_Cooldown.lua:1730, gate default OFF :1827). Live." })
            s.NUM({ module = M, key = "MaxRange", label = "Maximum duration",
                min = 0, max = 3600, step = 1,
                tip = "Maximum total duration cooldowns must have to be displayed in this cooldown timer instance (Forte_Cooldown.lua:1730, default 3600 :1827). Behind its Enable box; live." })
            s.CHK({ module = M, key = "MinRemainingOn",
                label = "Enable minimum remaining filter",
                tip = "The checkbox of the source's \"Minimum remaining\" row (NU2, Forte_Cooldown.lua:1731, gate default OFF :1828). Live." })
            s.NUM({ module = M, key = "MinRemaining", label = "Minimum remaining",
                min = 0, max = 3600, step = 1,
                tip = "Minimum remaining time cooldowns must have to be displayed in this cooldown timer instance (Forte_Cooldown.lua:1731, default 0 :1828). Behind its Enable box; live." })
            s.CHK({ module = M, key = "MaxRemainingOn",
                label = "Enable maximum remaining filter",
                tip = "The checkbox of the source's \"Maximum remaining\" row (NU2, Forte_Cooldown.lua:1732, gate default OFF :1829). Live." })
            s.NUM({ module = M, key = "MaxRemaining", label = "Maximum remaining",
                min = 0, max = 3600, step = 1,
                tip = "Maximum remaining time cooldowns must have to be displayed in this cooldown timer instance (Forte_Cooldown.lua:1732, default 3600 :1829). Behind its Enable box; live." })
            s.STR({ module = M, key = "TimeTags", label = "Custom time tags",
                maxLetters = 64,
                tip = "Space-separated tag seconds (default 0 1 10 30 60 120 300 600). Tags rebuild live." })
            s.NUM({ module = M, key = "IgnoreShort", label = "Ignore shorter than",
                min = 0, max = 60, step = 0.01,
                tip = "Cooldowns shorter than this are ignored (default 2.99 s). Engine.MIN_COOLDOWN, tracked set rebuilt live." })
            -- EXPERIMENTAL (slice F-C, 2026-11-03; the H7 flag gains its row):
            -- `Cooldown.Procs` is the one switch of
            -- Forte_Cooldown/Core/Procs.lua, and this box writes it through
            -- FX.Settings:Set -- the SAME store the Cooldown module's
            -- `/fx status` line reports ("Procs: on/off, N watched").
            -- Forte_Cooldown's own Procs:_WireSettings listener is what makes
            -- the write live (this page has no hand in it: Forte_Cooldown must
            -- work with Forte_Options uninstalled), and the first enable asks
            -- FX.LoadAddOnOnDemand for the load-on-demand Forte_ItemProcs
            -- data (docs/perf.md §4 fix 1), which is the whole reason the
            -- default is OFF.
            s.CHK({ module = M, key = "Procs",
                label = "Item proc timers (experimental)",
                tip = "EXPERIMENTAL, off by default. Puts an item or weapon proc's internal cooldown on the bar: when one of the proc's auras is SEEN on you, a window runs the data's ICD (docs/design-combat-procs.md P-A/P-B). The proc data add-on loads with this box, which is why it is off. Out of combat the read net sees the aura directly; IN-COMBAT proc detection is a LAUNCH-DAY PROBE - the client seals aura reads in combat, so the two seen-routes (the out-of-combat sweep, the UNIT_AURA events) are only proven on the live client (PLAN §11.1 Q3 ruling, docs/launch-day.md). Live: the change is applied the moment you tick it." })
        end, {
            module = M,
            keys = { "Warn", "Width", "Height", "IconSizeOn", "IconSize",
                "BarAlpha", "BarAlphaMax",
                "IconTime", "IconTextColorOn", "IconTextColor",
                "Splash", "SplashFactor", "MaxTime", "PowerScale",
                "MinRangeOn", "MinRange", "MaxRangeOn", "MaxRange",
                "MinRemainingOn", "MinRemaining", "MaxRemainingOn",
                "MaxRemaining",
                "TimeTags", "IgnoreShort", "Procs" },
            tip = "The spell-on-cooldown warning, the power-scale timeline geometry (PLAN §3.5), the icon alpha range, the icon text, the splash icons, the time range filters and the experimental item proc timers.",
        })
        b.Section("Coloring", function(s)
            local rows = {
                { key = "ColorSpell", label = "Spell" },
                { key = "ColorPowerup", label = "Powerup" },
                { key = "ColorItem", label = "Item" },
                { key = "ColorPotion", label = "Potion" },
                { key = "ColorPet", label = "Pet" },
                { key = "ColorInternal", label = "Internal" },
                { key = "ColorBuff", label = "Buff" },
                { key = "ColorDebuff", label = "Debuff" },
            }
            for _, row in ipairs(rows) do
                s.COL({ module = M, key = row.key, label = row.label,
                    tip = row.label .. " category colour (Forte_Cooldown.lua :1842-1855). Icons, segments and text retint live." })
            end
        end, {
            module = M,
            keys = { "ColorSpell", "ColorPowerup", "ColorItem", "ColorPotion",
                "ColorPet", "ColorInternal", "ColorBuff", "ColorDebuff" },
            tip = "Per-category icon/segment colours.",
        })
        b.Section("Frame Appearance", function(s)
            s.COL({ module = M, key = "BarColor", label = "Bar colour",
                tip = "Aluminium bar fill (default white a 0.20). Applied live." })
            s.COL({ module = M, key = "BgColor", label = "Background colour",
                tip = "Bar backdrop (default black a 0.50). Applied live." })
            -- The APPEARANCE block's third row (:1765), label verbatim
            -- FWL.BAR_TEXT "Bar text" (Forte_Core/Localization.lua:1019).
            s.COL({ module = M, key = "TextColor", label = "Bar text",
                tip = "The time-tag text colour (\"Bar text\", Forte_Cooldown.lua:1765, default 1,1,1 a 0.20 :1838; the source's tag path SetTimeTags :1270). Re-tints the scale's tags live." })
            s.CHK({ module = M, key = "Spark", label = "Show icon Glow",
                tip = "Show a glow around the icons that matches the bar color (Forte_Cooldown.lua:1713, the NU2 row: the [0] gate drives the glow and Spark[1] = 1 is its alpha, :1820). The gate also picks the splash's centre crop versus the full texture (:1385). Shown/hidden live on the icons, the splashes and the ready pulses." })
        end, {
            module = M, keys = { "BarColor", "BgColor", "TextColor",
                "Spark" },
            tip = "Bar fill, backdrop and spark.",
        })
    end,
})
