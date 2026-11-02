-- Forte_Options/Pages/Profiles.lua
-- The Profiles page: which settings this character rides, and the resets.
--
-- WHERE IT SITS (PLAN §11.1 H3 item 5, checked 2026-11-02): the original had
-- NO Profiles cell in its module grid. Its switcher is the TAB ROW under the
-- title bar of the General category -- `tab_actions` handed to
-- `SetMainCategory(FWL.GENERAL, ...)` at Forte_Core/Options.lua:5535, the
-- tabs drawn at :4849-4901 (one per `Profiles.Data` entry, `root.Active` gold,
-- delete gated on `#root.Data > 1`), create/remove/rename/select at
-- :5454-5469, the delete confirmation popup at :5471-5500. This build follows
-- the same law: the tab row (Window.lua RefreshProfileTabs) is the switcher,
-- this page is the editor, and `O.INDEX` gets no new cell. The strings are
-- the original's (`FWL.PROFILES`, `PROFILES_CURRENT`, `PROFILES_CURRENT_TT`,
-- Forte_Core/Localization.lua:339-341).
--
-- The model (Core/Settings.lua FX.Profiles, the v1 shape in
-- Forte_Core/Core/Database.lua, docs/profiles.md): a profile is one settings
-- set; BY DEFAULT every character rides its own, keyed `Name-Realm` (the
-- original's `FW:FullName()`, Forte_Core.lua:1074-1076, and its
-- `Profiles.Characters[name] = index` binding at :1078-1084 / :2142-2162);
-- the account-wide shared profile is the `PerCharacter` row off. Switching
-- applies LIVE: FX.Profiles.Select pushes the new profile's every key
-- through Settings:Set, which is the same notification a checkbox click
-- produces, so the bar width, the colours, the locks -- all move now, not at
-- the next login.
--
-- THE PERSISTENCE CAVEAT (the honest one, in the Tips below and in
-- docs/profiles.md): everything here rides the SavedVariables global
-- `ForteXorcistDB` (Forte_Core.toc). Nobody has been able to log in before
-- launch, so real round-tripping of that global is a launch-day probe
-- (`/fx probe`, docs/launch-day.md, the probeEpoch Q10 row) -- the profiles
-- are as durable as that probe proves them to be.

ForteXorcist = ForteXorcist or {}
local FX = ForteXorcist
local O = FX.Options
local S = FX.Settings
local P = FX.Profiles

local M = "Profiles"
FX.Settings:Register(M, {
    -- The MIRROR of the live sharing mode (FX.Profiles.IsPerCharacter is the
    -- truth; the mirror is what the checkbox reads, the General/GlobalLock
    -- law of Pages/General.lua).
    PerCharacter = true,
    -- The name field of the "new profile" row: a string option like the
    -- pages' other string rows, not profile data.
    NewProfileName = "",
})

-- ------------------------------------------------------------------ helpers --
local notice
local function say(text)
    notice = text
    FX.Print(text)
end

--- The checkbox mirror: push the live mode into the store right before the
--- row reads it, inequality-guarded so a listener that finds the store in
--- agreement writes nothing (no loop).
local function pushSharing()
    local live = P.IsPerCharacter()
    if S:Get(M, "PerCharacter") ~= live then
        S:Set(M, "PerCharacter", live)
    end
end

local wired = false
local function ensureWiring()
    if wired then return end
    wired = true
    S:OnChange(M, function(key, value)
        if key ~= "PerCharacter" then return end
        -- The m4 law: the store row is the mirror, the mode is the truth. A
        -- profile switch re-reads the mirror through ApplyLive, so the mode
        -- a profile was last used under is what its row shows.
        if P.IsPerCharacter() == (not not value) then return end
        P.SetPerCharacter(value)
        pushSharing()
        if O.RefreshProfileTabs then O:RefreshProfileTabs() end
        if O.RefreshAllPages then O:RefreshAllPages() end
    end)
    pushSharing()
end

--- Create/delete/switch change the LIST of profiles, which no widget
--- refresh can re-shape: rebuild the page (Window.lua InvalidatePage) and
--- the tab row with it.
local function rebuild()
    if O.pagesBuilt and O.pagesBuilt["Profiles"] then
        O:InvalidatePage("Profiles")
        O:SetPage("Profiles")
    end
    if O.RefreshProfileTabs then O:RefreshProfileTabs() end
end

--- The popup gate of the destructive button rows (the original's
--- `FX_CONFIRM_DELETE_PROFILE` popup, Options.lua:5471-5500). Where the
--- popup add-on is not loaded the click runs -- a button is a deliberate
--- click on a row that names the profile it deletes.
local function withConfirm(text, run)
    local show = _G.StaticPopup_ShowGenericConfirmation
    if type(show) == "function" then
        local ok = pcall(show, text, run)
        if ok then return end
    end
    run()
end

local function createProfile(alsoUse)
    local raw = S:Get(M, "NewProfileName")
    local name, err = P.Create(raw)
    if not name then
        say("cannot create a profile: " .. tostring(err))
        return
    end
    S:Set(M, "NewProfileName", "")
    if alsoUse then P.Select(name) end
    say("created the profile " .. name .. " as a copy of "
        .. tostring(P.Active()))
    rebuild()
end

-- -------------------------------------------------------------------- page --
O:RegisterPage({
    id = "Profiles",
    module = M,
    title = "Profiles",
    colour = O.C.SLATE,
    build = function(b)
        ensureWiring()
        b.Tips({
            "A profile is one character's whole set of settings, keyed Name-Realm.",
            "By default every character rides its own; turn sharing on for one account-wide profile.",
            "The tabs under the title bar are the switcher; this page is the editor.",
            "The original had no Profiles cell in its module grid, so this page has none either.",
            "Create copies the profile in use; Delete keeps the last profile and moves its characters.",
            "Reset rows ask first: accept the popup, or /fx reset confirm.",
            "Persistence of the ForteXorcistDB file is a launch-day probe: /fx probe.",
        })

        b.Section("Current Profile", function(s)
            s.CHK({
                module = M, key = "PerCharacter",
                label = "Per-character profiles",
                tip = "On (the default): this character (" .. P.Self()
                    .. ") rides its own profile, the original's binding of FW:FullName() to a profile. Off: every character of this account rides the shared profile "
                    .. P.SHARED_NAME .. ". The characters' bindings survive the toggle.",
            })
            s.INFO({
                label = "Active profile",
                value = function() return tostring(P.Active()) end,
                tip = "The profile this window is editing. Switch it on the tabs above, or with the Use rows below.",
            })
            s.INFO({
                label = "This character",
                value = function() return P.Self() end,
                tip = "The key of this character: Name-Realm (the realm from GetRealmName). The original keyed its characters the same way.",
            })
            s.INFO({
                label = "Profiles in this install",
                value = function() return #P.List() end,
                tip = "Profiles in ForteXorcistDB, including the account-wide one.",
            })
        end, {
            module = M, keys = { "PerCharacter" },
            tip = "Per-character settings: the original's instance model.",
        })

        b.Section("Profiles", function(s)
            for _, name in ipairs(P.List()) do
                local isActive = (name == P.Active())
                local tag = P.IsShared(name) and " (account-wide)"
                    or (isActive and " (in use)" or "")
                s.BTN({
                    label = "Use " .. name .. tag,
                    text = "Use",
                    enabled = not isActive,
                    tip = isActive
                        and "this profile is the one in use"
                        or ("switch to " .. name .. " now: every setting of every module is re-applied from it, live"),
                    onPress = function()
                        local ok, err = P.Select(name)
                        if not ok then
                            say("cannot switch: " .. tostring(err))
                            return
                        end
                        say("now using the profile " .. name)
                        if O.OnProfileChanged then O:OnProfileChanged() end
                        rebuild()
                    end,
                })
                s.BTN({
                    label = "Delete " .. name .. tag,
                    text = "Delete",
                    enabled = function() return #P.List() > 1 end,
                    tip = "delete " .. name .. ": the last profile can not go, and the characters bound to it move to a survivor",
                    onPress = function()
                        withConfirm("ForteXorcist: delete the profile "
                            .. name .. "?", function()
                            local ok, err = P.Delete(name)
                            if not ok then
                                say("cannot delete: " .. tostring(err))
                                return
                            end
                            say("deleted the profile " .. name)
                            rebuild()
                        end)
                    end,
                })
            end
            s.STR({
                module = M, key = "NewProfileName",
                label = "Name of the new profile",
                maxLetters = 32,
                tip = "the name for the rows below: 1..32 characters, no | and no control characters.",
            })
            s.BTN({
                label = "Create a copy of " .. tostring(P.Active()),
                text = "Create",
                tip = "create the typed profile as a copy of the one in use (the original's [create new] copies your current settings), and stay on this profile",
                onPress = function() createProfile(false) end,
            })
            s.BTN({
                label = "Create a copy and switch to it",
                text = "Create+Use",
                tip = "same copy, then switch: every setting of every module moves to the new profile's values, live",
                onPress = function() createProfile(true) end,
            })
        end, { tip = "The list: switch, delete, and new profiles as copies." })

        b.Section("Reset", function(s)
            s.INFO({
                label = "Pending reset",
                value = function()
                    local p = S.PendingReset()
                    return p and (p .. " -- confirm it") or "nothing"
                end,
                tip = "an armed reset: accept the popup, type /fx reset confirm, or press Confirm below. Cancel drops it.",
            })
            s.BTN({
                label = "Confirm the armed reset", text = "Confirm",
                enabled = function() return S.PendingReset() ~= nil end,
                tip = "run the armed reset now",
                onPress = function() S.ConfirmReset(); rebuild() end,
            })
            s.BTN({
                label = "Cancel the armed reset", text = "Cancel",
                enabled = function() return S.PendingReset() ~= nil end,
                tip = "drop the armed reset; nothing is changed",
                onPress = function() S.CancelReset(); rebuild() end,
            })
            for _, name in ipairs(S:GetModuleNames()) do
                s.BTN({
                    label = "Reset " .. name, text = "Reset",
                    tip = "every " .. name .. " setting back to the shipped default (asks first) -- the same command as /fx reset "
                        .. name:lower() .. ", the original's per-module reset",
                    onPress = function() S.RequestReset(name); rebuild() end,
                })
            end
            s.BTN({
                label = "Reset every module", text = "Reset all",
                tip = "every setting of every module of THIS profile back to the shipped defaults (asks first) -- /fx reset all, the original's resetall",
                onPress = function() S.RequestReset("all"); rebuild() end,
            })
            s.INFO({
                label = "Last action",
                value = function() return notice or "none" end,
                tip = "what the last button on this page did (the same line is printed to chat).",
            })
        end, { tip = "Per-module and all-module resets, each behind a confirmation." })
    end,
})
