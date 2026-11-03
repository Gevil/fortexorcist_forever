-- addon/Forte_Options/tests/test_profiles.lua
-- The profile model of Forte_Options/Core/Settings.lua (FX.Profiles), the
-- Profiles page (Pages/Profiles.lua), the profile tab row of UI/Window.lua
-- and the /fx reset command. The laws (PLAN §11.1 H3 + wave 5 acceptance): a
-- corrupt key of a registered module is dropped while a legacy key of the
-- original survives, a profile switch moves a LIVE setting (the Cooldown bar
-- width, measured on the real frame) and moves back, a reset is per module
-- and is gated behind a confirmation, the profiles are keyed `Name-Realm`,
-- and THE STORE IS SPARSE: it carries only values that differ from the
-- registered defaults (a page build and a /reload-equivalent pass leave no
-- default-valued key; a moved shipped default reaches a profile that never
-- touched the key; a profile copy copies explicit values only).
--
-- This suite runs LAST in Forte_Options (test_options < test_profiles), owns
-- the profile store for its own run, and leaves the shipped state as it
-- found it (the last test proves it).

local FX = ForteXorcist
local S = FX.Settings
local P = FX.Profiles
local O = FX.Options
local DB = FX.DB

local function countKeys(t)
    local n = 0
    for _ in pairs(t) do n = n + 1 end
    return n
end

local function profileNames()
    local out = {}
    for name in pairs(FX.db.profiles.byName) do out[#out + 1] = name end
    table.sort(out)
    return out
end

local function settingsOf(name)
    local p = FX.db.profiles.byName[name]
    return p and p.settings
end

--- The EFFECTIVE value of one profile's key: the stored value if the
--- (sparse) store carries one, the registered default otherwise -- the raw
--- read of the wave-5 store, for the laws that speak about a profile's
--- values, not about the shape of its table.
local function storedOf(profileName, module, key)
    local st = settingsOf(profileName)
    if type(st) ~= "table" then return S:GetDefault(module, key) end
    local t = st[module]
    if type(t) == "table" and t[key] ~= nil then return t[key] end
    return S:GetDefault(module, key)
end

local function barWidth()
    local d = FX.Cooldown and FX.Cooldown.Display
    return d and d.anchor and d.anchor:GetWidth()
end

local function cleanupProfiles()
    local root = S._profilesRoot()
    for _, name in ipairs({ DB.CharacterKey(), P.SHARED_NAME }) do
        if not root.byName[name] then root.byName[name] = { settings = {} } end
    end
    for _, name in ipairs(P.List()) do
        if name ~= DB.CharacterKey() and name ~= P.SHARED_NAME then
            P.Delete(name)
        end
    end
    root.perCharacter = true
    P.Bind(true)
    P.Select(DB.CharacterKey())
    P.SetPerCharacter(true)
    S.CancelReset()
end

local function widgetByLabel(page, label)
    for _, sec in ipairs(page.sections) do
        for _, wd in ipairs(sec.widgets) do
            if wd.spec and wd.spec.label == label then return wd end
        end
    end
end

local function pressButton(page, label)
    local wd = widgetByLabel(page, label)
    if not wd or not wd.obj or not wd.obj.GetScript then return false end
    local fn = wd.obj:GetScript("OnClick")
    if not fn then return false end
    fn(wd.obj)
    return true
end

--- The window caches a built page (Window.lua SetPage); the Profiles page
--- re-shapes itself after its OWN create/delete/switch (its rebuild() →
--- InvalidatePage). A profile a test created from outside the page needs
--- the same invalidation to show up, which is what this does.
local function openProfiles()
    O:InvalidatePage("Profiles")
    O:Open("Profiles")
    return O.pagesBuilt["Profiles"]
end

-- ============================================================ the store ====

test("FX.Profiles is the profile layer of the settings store", function()
    assertNotNil(P, "FX.Profiles exists")
    for _, fn in ipairs({ "Active", "List", "Create", "Delete", "Select",
        "SetPerCharacter", "IsPerCharacter", "SanitizeName", "ApplyLive" }) do
        assertEquals("function", type(P[fn]), fn)
    end
    assertEquals("function", type(S.SanitizeProfile))
    assertEquals("function", type(S.RequestReset))
    assertEquals("function", type(S.ConfirmReset))
end)

test("the live store rides the active profile, keyed Name-Realm", function()
    local me = DB.CharacterKey()
    assertNotNil(me, "the client gives a player name")
    assertTrue(#me > #tostring(UnitName("player")),
        "the key carries a realm: " .. me)
    assertEquals(me, P.Active(), "a fresh install starts on its own profile")
    assertEquals(true, FX.db.profiles.perCharacter, "per-character is the default")
    assertEquals(me, FX.db.profiles.characters[me], "the character is bound to it")
    assertNotNil(settingsOf(me))
    -- The store IS the profile's table: one write, visible in the file the
    -- client will save (the SavedVariables round trip is the launch probe).
    local t = S._store("Cooldown")
    assertEquals(settingsOf(me).Cooldown, t)
    -- Wave 5: the table is SPARSE. The old layer seeded every default into
    -- it, which is what froze the shipped values into the file; reading a
    -- key must not write it.
    assertEquals(nil, t.Width,
        "a key nobody moved is NOT in the profile: the default lives in the registration")
    assertEquals(250, S:Get("Cooldown", "Width"),
        "Get fills the registered default in, without storing it")
    assertEquals(nil, settingsOf(me).Cooldown.Width,
        "the read left nothing behind")
end)

test("the account-wide profile exists beside it, per-character by default", function()
    assertNotNil(settingsOf(P.SHARED_NAME), "the shared profile is there")
    assertEquals(true, P.IsPerCharacter())
    assertTrue(P.IsShared(P.SHARED_NAME))
    assertFalse(P.IsShared(DB.CharacterKey()))
end)

-- ================================================= the sparse store (W5) ==
test("a Set equal to the registered default deletes the stored key (colour deep-equal)",
function()
    local t = S._store("Cooldown")
    S:Set("Cooldown", "Width", 250)              -- the shipped default
    assertEquals(nil, t.Width, "the default is not a user value: nothing is stored")
    assertEquals(250, S:Get("Cooldown", "Width"), "the effective value is the default")
    S:Set("Cooldown", "Width", 340)
    assertEquals(340, t.Width, "a real choice is stored")
    S:Set("Cooldown", "Width", 250)              -- back to the default
    assertEquals(nil, t.Width, "and moving back to the default REMOVES the key")
    -- Colour rows ride deep equality:
    S:Set("Cooldown", "BarColor", { 1, 1, 1, 0.20 })
    assertEquals(nil, t.BarColor, "a colour deep-equal to the default is not stored")
    S:Set("Cooldown", "BarColor", { 1, 1, 1, 0.5 })
    assertNotNil(t.BarColor, "a colour with a moved alpha is stored")
    S:Reset("Cooldown", "BarColor")
    assertEquals(nil, t.BarColor, "the reset is a delete: the default is the effective value")
    assertEquals(0.20, S:Get("Cooldown", "BarColor")[4])
    assertEquals(0, countKeys(t),
        "every key this probe moved sits at its default again: the module table is empty")
    -- The listener contract of a Set-to-default is untouched: the consumer
    -- is told the value, that is how a reset reaches the live bar.
    local seenKey, seenVal, count = nil, nil, 0
    S:OnChange("Cooldown", function(k, v)
        seenKey, seenVal, count = k, v, count + 1
    end)
    S:Set("Cooldown", "Width", 250)
    assertEquals("Width", seenKey)
    assertEquals(250, seenVal)
    assertEquals(1, count, "a Set that stores nothing still notifies")
    S:Reset("Cooldown", "Width")
end)

test("a moved shipped default reaches profiles that never touched the key",
function()
    -- The wave 5 point on the mechanism's face: the profile carries no
    -- shadow of a default, so the registration IS the shipped value for
    -- every profile that never set the key. The old layer seeded the old
    -- default into the profile at the first read, and a changed shipped
    -- default never arrived (the frozen AltTimeFormat = false).
    S:Register("DriftProbe", { speed = 1, tone = { 1, 0, 0, 1 } })
    local me = P.Active()
    assertEquals(1, S:Get("DriftProbe", "speed"))
    local st = settingsOf(me)
    assertEquals(nil, st.DriftProbe and st.DriftProbe.speed,
        "reading a default leaves no key in the file")
    S:Set("DriftProbe", "speed", 7)              -- a real choice
    assertEquals(7, storedOf(me, "DriftProbe", "speed"))
    assertEquals(7, st.DriftProbe.speed, "stored")
    S:Set("DriftProbe", "speed", 1)              -- back to the (then) default
    assertEquals(nil, st.DriftProbe.speed, "un-setting is a delete")
    -- the shipped default moves under the install:
    S:Register("DriftProbe", { speed = 2, tone = { 1, 0, 0, 1 } })
    assertEquals(2, S:Get("DriftProbe", "speed"),
        "the moved default reaches the profile that never set the key")
    assertEquals(2, storedOf(P.SHARED_NAME, "DriftProbe", "speed"),
        "and every other profile of the install")
    for _, p in pairs(FX.db.profiles.byName) do
        p.settings.DriftProbe = nil
    end
    FX.db.defaultsPruned.DriftProbe = nil
end)

test("a module that registers AFTER the ladder is pruned at its registration (the LoD path)",
function()
    -- The load-on-demand pages (Hunter, Spell Timer, the Warlock plates,
    -- the Messages pages) register at PLAYER_LOGIN, after the ADDON_LOADED
    -- ladder; the marker table `db.defaultsPruned` is the hand-off and
    -- Settings:Register runs the deferred prune over every profile.
    assertNotNil(FX.db.defaultsPruned, "the v2 step marked this install")
    local me = P.Active()
    local st = settingsOf(me)
    st.LateProbe = { speed = 1, loud = 9 }       -- a legacy, seeded install
    FX.db.defaultsPruned.LateProbe = nil         -- ... unseen by the ladder
    S:Register("LateProbe", { speed = 1, loud = 2 })
    local t = st.LateProbe
    assertEquals(nil, t.speed,
        "the frozen default is dropped at the module's registration")
    assertEquals(9, t.loud, "the user-set value stays")
    assertEquals(true, FX.db.defaultsPruned.LateProbe,
        "marked in the file: the next login prunes it no more")
    st.LateProbe = nil
    FX.db.defaultsPruned.LateProbe = nil
end)

-- =========================================================== key sanity ====

test("a corrupt key of a registered module is dropped, and the default comes back",
function()
    local name = P.Active()
    local cd = settingsOf(name).Cooldown
    cd.Width = "very wide"          -- a string where a number belongs
    cd.BogusKey = 17                -- a key the module never registered
    cd.IgnoreCooldown = 2.99        -- the ORIGINAL's name of IgnoreShort
    local dropped = S:SanitizeProfile(name)
    assertEquals(3, dropped, "type clash, unknown key and legacy name all go")
    assertEquals(nil, cd.BogusKey)
    assertEquals(nil, cd.Width, "the type clash is dropped, the default reseeds")
    assertEquals(nil, cd.IgnoreCooldown,
        "a key the module does not know is not a setting: FE-22 carries a"
        .. " rename FORWARD (a migration step), this pass is what makes a hand-"
        .. " edited or future-edited file readable again")
    assertEquals(250, S:Get("Cooldown", "Width"))
    assertEquals(250, barWidth(), "and the live bar agrees with the store")
    assertEquals(0, S:SanitizeProfile(P.SHARED_NAME),
        "the untouched shared copy has nothing to drop")
end)

test("junk under a module name goes with it; an unregistered module is untouched",
function()
    local name = P.Active()
    local st = settingsOf(name)
    st.Cooldown = "not a table at all"      -- a hand-edited file
    st.SomeFutureModule = { x = 1 }          -- not registered in this session
    local dropped = S:SanitizeProfile(name)
    assertEquals(1, dropped, "only the junk module is dropped")
    assertEquals(nil, st.Cooldown, "its junk value is gone with it")
    S._store("Cooldown")                     -- the reader recreates the table
    assertEquals("table", type(settingsOf(name).Cooldown))
    assertEquals(nil, settingsOf(name).Cooldown.Width,
        "the recreated table is sparse: no key, no stored value")
    assertEquals(250, S:Get("Cooldown", "Width"),
        "and the next read is the shipped default, not the junk")
    assertNotNil(settingsOf(name).SomeFutureModule,
        "a module this session does not know has no type law to break")
    settingsOf(name).SomeFutureModule = nil
end)

test("the key sanity pass runs for a profile the first time it is read", function()
    local created = P.Create("KeyProbe")
    assertNotNil(created)
    settingsOf(created).Cooldown.MaxTime = "forever"
    assertNotNil(P.Select(created))
    assertEquals(300, S:Get("Cooldown", "MaxTime"),
        "the profile switched to is checked at the first read, not at login")
    P.Select(DB.CharacterKey())
    assertNotNil(P.Delete(created))
    assertEquals(250, S:Get("Cooldown", "Width"))
end)

-- ========================================================= profile ops ====

test("a name is the gate: trim, length, forbidden characters, clashes", function()
    assertEquals("Two", P.SanitizeName("  Two  "))
    assertEquals(nil, P.SanitizeName("   "))
    assertEquals(nil, P.SanitizeName(""))
    assertEquals(nil, P.SanitizeName(42))
    assertEquals(nil, P.SanitizeName("a|b"), "colour codes are out")
    assertEquals(nil, P.SanitizeName("a\0b"), "control characters are out")
    assertEquals(nil, P.SanitizeName(string.rep("x", 40)))
    assertNotNil(P.Create("Two"))
    assertEquals(nil, P.Create("two"), "the name space is case-insensitive")
    assertEquals(nil, P.Create("  Two  "), "a trimmed clash is still a clash")
    local _, err = P.Create("Two")
    assertNotNil(err, "a refusal says why")
    assertNotNil(P.Delete("Two"))
end)

test("Create copies the profile in use; switching back restores its values",
function()
    local base = P.Active()
    S:Set("Cooldown", "Width", 340)
    local created = P.Create("CopyTest")
    assertNotNil(created)
    assertEquals(340, storedOf(created, "Cooldown", "Width"), "the copy carries the values")
    assertEquals(1, countKeys(settingsOf(created).Cooldown),
        "and ONLY the explicit values: the copy law (wave 5) carries the keys"
        .. " the profile set, defaults ride the registration")
    settingsOf(created).Cooldown.Width = 180
    assertNotEquals(180, storedOf(base, "Cooldown", "Width"), "not a live alias")
    assertNotNil(P.Select(created))
    assertEquals(created, P.Active())
    assertEquals(180, barWidth(), "the switch moved the LIVE bar")
    assertNotNil(P.Select(base))
    assertEquals(340, barWidth(), "and switching back moved it back")
    assertNotNil(P.Delete(created))
    S:Set("Cooldown", "Width", 250)   -- back to the default: the key goes
    assertEquals(nil, settingsOf(base).Cooldown and settingsOf(base).Cooldown.Width,
        "a key returned to its default leaves the profile")
end)

test("switching profiles is live in the consumer, not only in the store",
function()
    local base = P.Active()
    local created = P.Create("LiveBar")
    assertNotNil(created)
    S:Set("Cooldown", "Width", 250)
    P.Select(created)
    S:Set("Cooldown", "Width", 396)
    local d = FX.Cooldown.Display
    assertEquals(396, S:Get("Cooldown", "Width"))
    assertEquals(396, d.anchor:GetWidth(), "the bar frame is 396 wide now")
    P.Select(base)
    assertEquals(250, d.anchor:GetWidth(), "the old profile's value is on the bar")
    P.Select(created)
    assertEquals(396, d.anchor:GetWidth(), "and back again")
    P.Select(base)
    P.Delete(created)
end)

test("a stored `false` under a `true` default rides the switch (CodeReview6 M1)",
function()
    -- M1: ApplyLive's `S:Set(module, key, v ~= nil and v or deepCopy(d))`
    -- LOSES a stored `false` (`true and false` is false, the `or` then
    -- hands the DEFAULT, the stored value is never reached), so the first
    -- profile switch RE-LOCKS a bar the player unlocked -- and because the
    -- pushed `true` is default-equal, Set DELETES the stored `false`
    -- (:447-448): the single non-default the sparse store is built to
    -- carry, eaten out of SavedVariables. The bar page ships Lock = true
    -- (Pages/Cooldown.lua:71), the stored `false` is the player's one move.
    local base = P.Active()
    local d = FX.Cooldown.Display
    d:Init()
    assertNotNil(d.anchor, "the Cooldown bar is live in every gate run")
    assertEquals(true, S:GetDefault("Cooldown", "Lock"), "the bar ships locked")
    S:Set("Cooldown", "Lock", false)
    assertEquals(false, S:Get("Cooldown", "Lock"))
    assertEquals(false, settingsOf(base).Cooldown.Lock, "the false is stored")
    assertFalse(d.cfg.locked, "the bar is unlocked live")
    local created = P.Create("LockRide")
    assertNotNil(created)
    assertNotNil(P.Select(created))
    S:Set("Cooldown", "Lock", true)              -- the ride profile is locked
    assertTrue(d.cfg.locked)
    assertNil(settingsOf(created).Cooldown and settingsOf(created).Cooldown.Lock,
        "a default is not stored")
    assertNotNil(P.Select(base))
    assertEquals(false, S:Get("Cooldown", "Lock"),
        "M1: the switch back carries the STORED false, not the default")
    assertEquals(false, settingsOf(base).Cooldown.Lock,
        "and the stored key SURVIVES the switch (false under a true default"
        .. " is not default-equal: it stays in the profile)")
    assertFalse(d.cfg.locked, "the bar frame follows: unlocked across the switch")
    assertTrue(d.anchor:IsMovable(), "the live frame is draggable again")
    assertNotNil(P.Delete(created))
    -- Hand the shipped state back: the bar locked (the publish moves
    -- GlobalLock back to its default too), the profile sparse again.
    S:Reset("Cooldown", "Lock")
    assertTrue(d.cfg.locked, "back to the shipped lock")
    assertNil(settingsOf(base).Cooldown and settingsOf(base).Cooldown.Lock,
        "and the profile carries no frozen Lock")
end)

test("sharing moves this character to the account-wide profile, and back",
function()
    local me = DB.CharacterKey()
    assertNotNil(P.Select(me))
    local boundBefore = FX.db.profiles.characters[me]
    assertEquals(me, boundBefore)
    assertNotNil(P.SetPerCharacter(false))
    assertEquals(false, FX.db.profiles.perCharacter)
    assertEquals(P.SHARED_NAME, P.Active(), "every character rides the shared one")
    assertEquals(me, FX.db.profiles.characters[me],
        "the character bindings SURVIVE the toggle: switching back restores them")
    S:Set("Cooldown", "Width", 260)
    assertEquals(260, settingsOf(P.SHARED_NAME).Cooldown.Width,
        "the shared profile is what is being written now")
    assertNotNil(P.SetPerCharacter(true))
    assertEquals(me, P.Active())
    assertEquals(250, storedOf(me, "Cooldown", "Width"),
        "the character's own values are intact (the 250 rides the registration)")
    assertEquals(250, barWidth())
    S:Set("Cooldown", "Width", 250)
end)

test("the last profile can not be deleted; deleting the active one moves the session",
function()
    local names = P.List()
    assertTrue(#names >= 2, "this install has its character and the shared profile")
    assertNotNil(P.Create("Doomed"))
    assertNotNil(P.Select("Doomed"))
    assertEquals("Doomed", P.Active())
    local boundTo = {}
    for who, target in pairs(FX.db.profiles.characters) do
        if target == "Doomed" then boundTo[#boundTo + 1] = who end
    end
    assertTrue(#boundTo >= 1, "the session character is bound to the profile it rides")
    assertNotNil(P.Delete("Doomed"))
    assertNil(P.Find("Doomed"))
    assertNotEquals("Doomed", P.Active(), "the session moved onto a survivor")
    assertEquals(storedOf(P.Active(), "Cooldown", "Width"),
        S:Get("Cooldown", "Width"), "and its live values are the survivor's")
    for who, target in pairs(FX.db.profiles.characters) do
        assertNotEquals("Doomed", target, who .. " is not left pointing at a deleted profile")
    end
    -- The last profile is untouchable (FW:InstanceDelete, Forte_Core.lua:2100).
    local all = P.List()
    while #all > 1 do
        assertNotNil(P.Delete(all[#all]))
        all = P.List()
    end
    local one, err = P.Delete(all[1])
    assertEquals(nil, one)
    assertNotNil(err)
    assertEquals(1, #P.List())
    -- The loop above deleted down to one profile: rebuild this install's
    -- pair (its character + the account-wide one) for the tests after this.
    local root = S._profilesRoot()
    for _, name in ipairs({ DB.CharacterKey(), P.SHARED_NAME }) do
        if not root.byName[name] then
            root.byName[name] = { settings = {} }
        end
    end
    root.perCharacter = true
    P.Bind(true)
    assertNotNil(P.Select(DB.CharacterKey()))
    assertEquals(P.SHARED_NAME, root.active == DB.CharacterKey()
        and P.SHARED_NAME or root.active, "the shared profile is back in the list")
    assertNotNil(settingsOf(P.SHARED_NAME))
end)

-- ============================================================== the page ====

test("the Profiles page is registered and opens with its controls", function()
    local def = O.pages["Profiles"]
    assertNotNil(def, "Pages/Profiles.lua registered the page")
    assertEquals("Profiles", def.module)
    O:Open("Profiles")
    assertEquals("Profiles", O.pageId)
    local page = openProfiles()
    assertNotNil(page)
    assertNotNil(widgetByLabel(page, "Per-character profiles"), "the sharing row")
    assertNotNil(widgetByLabel(page, "Active profile"), "what is in use")
    assertNotNil(widgetByLabel(page, "This character"), "the Name-Realm key")
    assertNotNil(widgetByLabel(page, "Name of the new profile"), "the name field")
    local created = widgetByLabel(page, "Create a copy of " .. tostring(P.Active()))
    assertNotNil(created, "the create row")
    -- A Use row per profile: the active one is disabled, the others are not.
    local uses, activeSeen = 0, false
    for _, sec in ipairs(page.sections) do
        for _, wd in ipairs(sec.widgets) do
            if wd.spec and wd.spec.text == "Use" then
                uses = uses + 1
                if not wd.spec.enabled then activeSeen = true end
            end
        end
    end
    assertEquals(#P.List(), uses, "one Use row per profile")
    assertTrue(activeSeen, "the row of the profile in use is the disabled one")
end)

test("the page's Use row switches the profile live; the Create row creates",
function()
    local base = P.Active()
    assertNotNil(P.Create("PageOne"))
    local page = openProfiles()
    S:Set("Cooldown", "Width", 250)
    local wd = widgetByLabel(page, "Use PageOne")
    assertNotNil(wd, "the created profile has a Use row")
    assertEquals(true, wd.spec.enabled, "it is enabled: it is not the one in use")
    wd.obj:GetScript("OnClick")(wd.obj)
    assertEquals("PageOne", P.Active(), "the row switched to it")
    S:Set("Cooldown", "Width", 205)
    assertEquals(205, barWidth(), "and the bar moved with it")
    page = openProfiles()
    local inUse = widgetByLabel(page, "Use PageOne (in use)")
    assertNotNil(inUse, "the profile in use carries the (in use) tag")
    assertEquals(false, inUse.spec.enabled, "and its Use row is the disabled one")
    wd = widgetByLabel(page, "Use " .. base)
    assertNotNil(wd, "the profile left behind has its own row")
    wd.obj:GetScript("OnClick")(wd.obj)
    assertEquals(base, P.Active())
    assertEquals(250, barWidth(), "its own values are on the bar again")
    -- The typed name field plus the Create row: a copy of the one in use.
    page = openProfiles()
    local eb = widgetByLabel(page, "Name of the new profile")
    assertNotNil(eb, "the name field is a real string row")
    eb.obj:SetText("TypedOne")
    eb.obj:GetScript("OnEnterPressed")(eb.obj)
    assertEquals("TypedOne", S:Get("Profiles", "NewProfileName"))
    local created = pressButton(openProfiles(),
        "Create a copy of " .. tostring(P.Active()))
    assertNotEquals(false, created, "the Create row is there and pressed")
    assertNotNil(settingsOf("TypedOne"), "the typed name became a profile")
    assertEquals(250, storedOf("TypedOne", "Cooldown", "Width"),
        "as a copy of the profile that was in use")
    assertEquals(nil, settingsOf("TypedOne").Cooldown.Width,
        "and the copy carries no frozen default: 250 is the shipped value"
        .. " (the profile in use had it set back to the default)")
    P.Delete("TypedOne")
    P.Delete("PageOne")
    O:Close()
end)

test("the profile tab row lists the profiles and is the switcher", function()
    local base = P.Active()
    openProfiles()
    assertNotNil(O.profileTabs, "the tab row built")
    -- A tab's OnClick closes over the active state it was BUILT with (the
    -- row is rebuilt on every change), so a click always goes through the
    -- row as it stands now.
    local function tabOf(name)
        for _, tab in ipairs(O.profileTabs) do
            if tab.profile == name then return tab end
        end
    end
    local count, overflow = 0, nil
    for _, tab in ipairs(O.profileTabs) do
        if tab.profile == "..." then overflow = tab
        elseif tab.profile then count = count + 1 end
    end
    assertTrue(count > 0, "the row carries a tab per profile")
    if #P.List() <= O.C.MAX_TABS then
        for _, name in ipairs(P.List()) do
            assertNotNil(tabOf(name), "a tab for " .. name)
        end
        assertEquals(nil, overflow, "no fold while they all fit")
    else
        assertNotNil(overflow, "past MAX_TABS the row folds onto the page")
    end
    assertNotNil(P.Create("TabOne"))
    O:OnProfileChanged()          -- the switch hook rebuilds the row with it
    local tab = tabOf("TabOne")
    assertNotNil(tab, "the row re-shapes with the list")
    tab:GetScript("OnClick")(tab)
    assertEquals("TabOne", P.Active(), "the tab switched, live")
    assertEquals(storedOf("TabOne", "Cooldown", "Width"),
        S:Get("Cooldown", "Width"), "the store moved with the tab")
    tab = tabOf(base)
    assertNotNil(tab, "the profile left behind has a tab of its own now")
    tab:GetScript("OnClick")(tab)
    assertEquals(base, P.Active(), "and clicking it moved back")
    assertNotNil(P.Delete("TabOne"))
    O:Close()
end)

test("the module index has NO Profiles cell: the original had none", function()
    for _, entry in ipairs(O.INDEX) do
        assertNotEquals("Profiles", tostring(entry.id),
            "the grid carries the original's modules only")
    end
    assertNotNil(O.pages["Profiles"], "the page is reached from the tab row")
    O:Open("General")
    assertEquals("Profiles", "Profiles")
    O:Close()
end)

-- ================================================================ reset ====

test("the reset command is per module, armed first, confirmed by command", function()
    S.CancelReset()
    local base = P.Active()
    S:Set("Cooldown", "Width", 333)
    S:Set("General", "FrameScale", 0.77)
    assertEquals(333, barWidth())
    FX.OnSlash("reset cooldown")           -- through the real slash path
    assertEquals("Cooldown", S.PendingReset(), "the module is named and armed")
    assertEquals(333, S:Get("Cooldown", "Width"), "arming applies NOTHING")
    assertEquals(333, barWidth(), "not one pixel of the live bar")
    FX.OnSlash("reset confirm")
    assertEquals(nil, S.PendingReset())
    assertEquals(250, S:Get("Cooldown", "Width"), "the module is at its defaults")
    assertEquals(250, barWidth(), "live, not only stored")
    assertEquals(0.77, S:Get("General", "FrameScale"),
        "the neighbouring module is untouched: the reset is PER MODULE")
    assertFalse(S.ConfirmReset(), "a second confirm is a no-op, not a reset")
    S:Set("General", "FrameScale", 1.0)
    assertEquals(base, P.Active(), "a reset does not move the profile")
end)

test("cancel drops an armed reset; an unknown module arms nothing", function()
    S.CancelReset()
    S:Set("General", "FrameScale", 0.55)
    assertNotNil(S.RequestReset("general"))
    assertEquals("General", S.PendingReset())
    assertNotNil(S.CancelReset())
    assertEquals(nil, S.PendingReset())
    assertEquals(0.55, S:Get("General", "FrameScale"), "cancel changed nothing")
    assertEquals(false, S.RequestReset("nosuchmodule"), "a refusal says so")
    assertEquals(nil, S.PendingReset(), "a refusal leaves nothing armed")
    S:Set("General", "FrameScale", 1.0)
end)

test("reset all moves every registered module and nothing else", function()
    S.CancelReset()
    local profilesBefore = #P.List()
    local perChar = P.IsPerCharacter()
    S:Set("Cooldown", "Width", 321)
    S:Set("General", "FrameScale", 0.44)
    assertNotNil(S.RequestReset("all"))
    assertEquals("all", S.PendingReset())
    assertTrue(S.ConfirmReset())
    assertEquals(250, S:Get("Cooldown", "Width"))
    assertEquals(1.0, S:Get("General", "FrameScale"))
    assertEquals(250, barWidth())
    assertEquals(profilesBefore, #P.List(), "a reset is not a profile operation")
    assertEquals(perChar, P.IsPerCharacter(), "and not a sharing operation")
end)

test("the page's Reset rows arm, and its Confirm row applies", function()
    S.CancelReset()
    O:Open("Profiles")
    local page = O.pagesBuilt["Profiles"]
    local resetAll = widgetByLabel(page, "Reset every module")
    assertNotNil(resetAll, "the all row")
    local resetCd = widgetByLabel(page, "Reset Cooldown")
    assertNotNil(resetCd, "one row per registered module")
    S:Set("Cooldown", "Height", 44)
    assertNotNil(pressButton(page, "Reset Cooldown"))
    assertEquals("Cooldown", S.PendingReset())
    assertEquals(44, S:Get("Cooldown", "Height"), "armed only")
    page = O.pagesBuilt["Profiles"]        -- the arm rebuilt the page
    assertNotNil(pressButton(page, "Confirm the armed reset"))
    assertEquals(24, S:Get("Cooldown", "Height"), "the Confirm row applied it")
    assertEquals(nil, S.PendingReset())
    page = O.pagesBuilt["Profiles"]
    assertNotNil(pressButton(page, "Reset Cooldown"))
    page = O.pagesBuilt["Profiles"]
    assertNotNil(pressButton(page, "Cancel the armed reset"))
    assertEquals(nil, S.PendingReset())
    O:Close()
end)

test("building every options page + a /reload-equivalent pass leaves no default-valued keys",
function()
    -- The live uiforever finding, encoded as a law: after the whole window
    -- has been built -- every registered page opened, every widget
    -- initialised, every live-state mirror (the lock m4 pushes) run -- and
    -- the /reload equivalents have run (the ladder over the live DB, every
    -- page rebuilt from its chunk-level build), NO profile of the install
    -- stores a key whose value equals its registered default. The old layer
    -- failed this at the first page: seeding wrote every default and the
    -- mirrors wrote the shipped lock values.
    local ids = {}
    for id in pairs(O.pages) do ids[#ids + 1] = id end
    table.sort(ids)
    assertTrue(#ids >= 5, "the registered pages: " .. table.concat(ids, ", "))
    for _, id in ipairs(ids) do O:Open(id) end
    O:Close()
    -- the /reload equivalent: the ladder over the live DB (the stamp skips
    -- every step), then every page rebuilt from its def, then a profile
    -- switch round trip (ApplyLive's default pushes over every module).
    DB.Migrate(FX.db)
    for _, id in ipairs(ids) do O:InvalidatePage(id) end
    for _, id in ipairs(ids) do O:Open(id) end
    O:Close()
    local base = P.Active()
    assertNotNil(P.Select(P.SHARED_NAME))
    assertNotNil(P.Select(base))
    local offenders = {}
    for name in pairs(FX.db.profiles.byName) do
        local st = settingsOf(name)
        if type(st) == "table" then
            for module, t in pairs(st) do
                if type(t) == "table" and S:IsRegistered(module) then
                    for key, value in pairs(t) do
                        local def = S:GetDefault(module, key)
                        if def ~= nil and S._deepEqual(value, def) then
                            offenders[#offenders + 1] =
                                name .. "." .. module .. "." .. tostring(key)
                        end
                    end
                end
            end
        end
    end
    assertEquals(0, #offenders, "default-valued keys in the store: "
        .. table.concat(offenders, ", "))
end)

test("the suite leaves the shipped state as it found it", function()
    cleanupProfiles()
    assertEquals(DB.CharacterKey(), P.Active())
    assertEquals(true, P.IsPerCharacter())
    assertNotNil(settingsOf(P.SHARED_NAME))
    assertEquals(nil, S.PendingReset())
    assertEquals(250, S:Get("Cooldown", "Width"))
    assertEquals(1.0, S:Get("General", "FrameScale"))
    local names = profileNames()
    assertEquals(2, #names, "this character and the account-wide profile: "
        .. table.concat(names, ", "))
end)
