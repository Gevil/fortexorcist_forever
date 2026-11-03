-- addon/Forte_Options/tests/test_test_mode_row.lua
-- The demo control's row (Wave I-3c, docs/research/upstream-addons-2026-11-03.md
-- §6 "Test Mode"): the Cooldown page's "Fill the frames with test data" row is
-- the window's face of `/fx test`, and the note's law for the feature is
-- "never writes settings (sparse store law)" -- so the row must be an ACTION
-- row (Forte_Options/Core/Widgets.lua W.BTN: label + push button, no `key`
-- bound, no recycle icon), never a W.CHK, which is a write to
-- `FX.Settings:Set` and would persist a demo switch into a profile. The
-- sparse-store law of Core/Settings.lua: the store holds the values that
-- differ from the shipped defaults, i.e. the player's choices.
--
-- The press is driven through the real script (the row's own OnClick), the law
-- of tests/test_options.lua and tests/test_advanced.lua; the store is measured
-- as a signature around the press, so "no write" is a fact and not a claim.

local FX = ForteXorcist
local O = FX.Options
local S = FX.Settings
local T = FX.TestMode

local function enableAll()
    if not T._eventFrame then T:OnEnable() end
    if not FX.Cooldown.Module._eventFrame then FX.Cooldown.Module:OnEnable() end
    if not FX.Timer.Module.options then FX.Timer.Module:OnEnable() end
end

local function rowByLabel(section, label)
    for _, wd in ipairs(section.widgets) do
        if wd.spec.label == label then return wd end
    end
end

local function storeSignature()
    local lines = {}
    local profiles = (FX.db and FX.db.profiles and FX.db.profiles.byName) or {}
    for name in pairs(profiles) do lines[#lines + 1] = name end
    table.sort(lines)
    local out = {}
    for _, name in ipairs(lines) do
        local settings = profiles[name].settings or {}
        local modules = {}
        for m in pairs(settings) do modules[#modules + 1] = m end
        table.sort(modules)
        for _, m in ipairs(modules) do
            local keys = {}
            for k in pairs(settings[m] or {}) do keys[#keys + 1] = k end
            table.sort(keys)
            for _, k in ipairs(keys) do
                out[#out + 1] = string.format("%s.%s.%s=%s", name, m, k,
                    tostring(settings[m][k]))
            end
        end
    end
    return table.concat(out, "\n")
end

test("the Cooldown page carries the demo control as an action row", function()
    enableAll()
    O:Open("Cooldown")
    local page = O.pagesBuilt["Cooldown"]
    local row = rowByLabel(page.sections[2], "Fill the frames with test data")
    assertNotNil(row, "Basics carries the demo control")
    assertEquals("Fill", row.spec.text, "the button's caption is the action")
    -- The law: no key is bound, so the row has no write path into the store
    -- and no recycle icon to reset a value that is not a value.
    assertEquals(nil, row.spec.key)
    assertEquals(nil, row.resetBtn)
    assertNotNil(row.obj, "a real push button")
    assertNotNil(row.spec.onPress, "and it drives the feature")
    local tip = (row.spec.tip or ""):lower()
    assertTrue(tip:find("test") ~= nil or tip:find("demo") ~= nil,
        "the tip says what the row is")
    assertTrue(tip:find("scrub") ~= nil,
        "the tip says how the synthetic entries leave")
    O:Close()
end)

test("the row is not a checkbox and no module registers a TestMode key",
function()
    O:Open("Cooldown")
    local row = rowByLabel(O.pagesBuilt["Cooldown"].sections[2],
        "Fill the frames with test data")
    assertNotNil(row)
    assertEquals(nil, row.boxFill,
        "a checkbox writes the store; this row must not")
    for _, module in ipairs(S:GetModuleNames()) do
        assertEquals(nil, S:GetDefault(module, "TestMode"),
            module .. " registers no TestMode key")
    end
    O:Close()
end)

test("pressing the row starts and stops the demo and writes no setting",
function()
    enableAll()
    if T.active then T:Stop("test") end
    O:Open("Cooldown")
    local page = O.pagesBuilt["Cooldown"]
    local row = rowByLabel(page.sections[2], "Fill the frames with test data")
    local before = storeSignature()
    -- The real script, on the real button.
    local onClick = row.obj:GetScript("OnClick")
    assertNotNil(onClick)
    onClick(row.obj)
    assertTrue(T.active, "the press starts the demo")
    assertEquals("on", T.reason)
    assertTrue(T:Count() > 0,
        "and both frames carry synthetic rows (" .. T:Count() .. ")")
    onClick(row.obj)
    assertEquals(false, T.active, "the second press stops it")
    assertEquals(0, T:Count(), "and scrubs them")
    assertEquals(before, storeSignature(), "the press wrote no setting")
    O:Close()
end)

test("the row's tip names the in-combat refusal", function()
    O:Open("Cooldown")
    local row = rowByLabel(O.pagesBuilt["Cooldown"].sections[2],
        "Fill the frames with test data")
    local tip = (row.spec.tip or ""):lower()
    assertTrue(tip:find("combat") ~= nil,
        "the tip tells the player the mode will not start in a fight")
    O:Close()
end)

test("the suite leaves the shipped state as it found it", function()
    O:Close()
    assertEquals(false, T.active)
    assertEquals(0, T:Count())
end)
