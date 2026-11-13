-- Forte_Dev/Suites/Frames.lua
-- The frames the addon builds, on the LIVE client: cooldown bar, spell-timer anchor, options window
-- (opened and closed through the real /fx slash handler, out of combat only), class frames, fonts, the
-- timer's corner-form position, and this addon's own beacon geometry.

ForteXorcist = ForteXorcist or {}
local FX = ForteXorcist
local Dev = FX.Dev

local fontProbe

local function num(v)
    local p = Dev.plain(v)
    if type(p) == "number" then return p end
    return nil
end

--- width, height, scale, alpha of a frame as plain numbers (nil when unreadable).
local function facts(f)
    local function call(name)
        local fn = f[name]
        if type(fn) ~= "function" then return nil end
        local ok, v = pcall(fn, f)
        return ok and num(v) or nil
    end
    return call("GetWidth"), call("GetHeight"), call("GetScale"), call("GetAlpha")
end

local function sane(T, f, what)
    T.truthy(f, what .. " frame exists")
    local w, h, scale, alpha = facts(f)
    T.truthy(w and w > 0 and w < 5000, what .. " width " .. Dev.S(w))
    T.truthy(h and h > 0 and h < 5000, what .. " height " .. Dev.S(h))
    T.truthy(scale and scale >= 0.2 and scale <= 5, what .. " scale " .. Dev.S(scale))
    T.truthy(alpha and alpha >= 0 and alpha <= 1, what .. " alpha " .. Dev.S(alpha))
    T.note(string.format("%dx%d scale %.2f alpha %.2f", w, h, scale, alpha))
end

Dev.RegisterSuite("frames", "ooc", function(T)
    T.check("frames: cooldown bar", function()
        sane(T, _G.ForteXorcistCooldownAnchor, "cooldown bar")
    end)

    T.check("frames: spell timer anchor", function()
        sane(T, _G.ForteXorcistTimerAnchor, "timer anchor")
    end)

    T.check("frames: timer position uses the corner form (FX.db.timer.display.corner)", function()
        local d = FX.db and FX.db.timer and FX.db.timer.display
        T.truthy(type(d) == "table", "FX.db.timer.display")
        local corner = Dev.plain(d.corner)
        T.truthy(corner == "BOTTOMLEFT" or corner == "TOPLEFT", "corner=" .. Dev.S(corner))
        T.truthy(num(d.x) ~= nil and num(d.y) ~= nil, "x/y numbers")
        local f = _G.ForteXorcistTimerAnchor
        if f and f.GetPoint then
            local ok, point = pcall(f.GetPoint, f)
            T.eq(ok and Dev.plain(point), corner, "anchor point vs saved corner")
        end
        T.note("corner " .. corner)
    end)

    T.check("frames: options window opens and closes through /fx options", function()
        if Dev.inCombat() then T.skip("in combat") end
        local O = FX.Options
        if not O or type(O.IsOpen) ~= "function" then T.skip("Forte_Options not loaded") end
        local slash = _G.SlashCmdList and _G.SlashCmdList.FORTEXORCIST
        T.truthy(type(slash) == "function", "SlashCmdList.FORTEXORCIST")
        local was = O:IsOpen() and true or false
        local ok1, ok2
        ok1 = pcall(slash, "options")
        local afterFirst = O:IsOpen() and true or false
        ok2 = pcall(slash, "options")
        local afterSecond = O:IsOpen() and true or false
        if afterSecond ~= was then pcall(slash, "options") end   -- restore whatever the owner had
        T.truthy(ok1 and ok2, "the slash handler raised")
        T.eq(afterFirst, not was, "state after the first toggle")
        T.eq(afterSecond, was, "state after the second toggle")
        local win = _G.ForteXorcistOptionsWindow
        if win then
            local w, h = facts(win)
            T.truthy(w and h and w > 0 and h > 0, "window size " .. Dev.S(w) .. "x" .. Dev.S(h))
        end
    end)

    T.check("frames: class frames", function()
        local token = Dev.classToken()
        local title = Dev.classTitle(token)
        if not (token and title) then T.skip("class unknown") end
        local required = token == "HUNTER"
            and { "ForteXorcistHunterSwingAnchor", "ForteXorcistHunterReminderAnchor", "ForteXorcistHunterRangeAnchor" }
            or {}
        local missing, checked = {}, 0
        for _, name in ipairs(required) do
            if not _G[name] then missing[#missing + 1] = name end
        end
        T.eq(#missing, 0, "class frames missing: " .. table.concat(missing, ","))
        -- every other named frame of this class (optional ones such as the melee rail) must be sane too
        local prefix = "ForteXorcist" .. title
        local found = {}
        for k, v in pairs(_G) do
            if type(k) == "string" and k:sub(1, #prefix) == prefix and type(v) == "table" and v.GetObjectType then
                found[#found + 1] = k
            end
        end
        table.sort(found)
        for _, name in ipairs(found) do
            local w, h, scale, alpha = facts(_G[name])
            T.truthy(w and h and scale and alpha, name .. " readable")
            T.truthy(w >= 0 and h >= 0 and scale >= 0.2 and scale <= 5 and alpha >= 0 and alpha <= 1, name .. " sane")
            checked = checked + 1
        end
        if #required == 0 and checked == 0 then T.skip("no named class frames known for " .. token) end
        T.note(checked .. " class frame(s) checked")
    end)

    T.check("frames: the shipped .ttf font object is usable", function()
        local displays = {
            { "cooldown", FX.Cooldown and FX.Cooldown.Display },
            { "timer", FX.Timer and FX.Timer.Display },
            { "hunter swing", FX.Hunter and FX.Hunter.Swing },
        }
        if not fontProbe then
            fontProbe = _G.UIParent:CreateFontString(nil, "OVERLAY")
            fontProbe:Hide()
        end
        local bad, checked = {}, 0
        for _, d in ipairs(displays) do
            local name, disp = d[1], d[2]
            if type(disp) == "table" then
                checked = checked + 1
                local path = disp.fontFile
                if type(path) ~= "string" then
                    bad[#bad + 1] = name .. ": font rejected (template fallback)"
                elseif not path:lower():find("%.ttf$") then
                    bad[#bad + 1] = name .. ": not a .ttf"
                else
                    pcall(fontProbe.SetFont, fontProbe, path, 12, "")
                    local okGet, got = pcall(fontProbe.GetFont, fontProbe)
                    got = okGet and Dev.plain(got)
                    if type(got) ~= "string" or got:lower() ~= path:lower() then
                        bad[#bad + 1] = name .. ": SetFont did not take"
                    end
                end
            end
        end
        if checked == 0 then T.skip("no display with a font yet") end
        T.eq(#bad, 0, table.concat(bad, "; "))
        T.note(checked .. " display font(s) ok")
    end)

    T.check("frames: Forte_Dev beacon is 96x6 at the top-left", function()
        local B = Dev.Beacon
        T.truthy(B and B.frame, "beacon frame built")
        local w, h = facts(B.frame)
        T.eq(w, 96, "beacon width")
        T.eq(h, 6, "beacon height")
        local ok, point = pcall(B.frame.GetPoint, B.frame)
        T.eq(ok and Dev.plain(point), "TOPLEFT", "beacon anchor")
    end)
end)
