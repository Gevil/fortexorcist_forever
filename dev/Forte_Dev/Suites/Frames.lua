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

-- ------------------------------------------------------------- font probe --
-- `FontString:SetFont(path, size, flags)` on the live client (measured 2026-11-13, client 70938): the
-- font file is loaded lazily on first RENDER. Before that SetFont returns false, GetFont() returns nil and
-- GetStringWidth() is 0, yet the text then draws in that font; once it has rendered, SetFont returns true
-- and GetFont() returns the path. So the boolean is NOT evidence of rejection: only a RAISE ("invalid font
-- asset (<path>): file not found") means the file is unusable. The probe therefore reads pcall-only and
-- reports the boolean as information (true = already rendered, false = pending first render).

local FP = {}
Dev.FontProbe = FP
FP.CONTROL_PATH = "Fonts\\FRIZQT__.TTF"   -- Blizzard's own font: SetFont must not raise on it
FP.SIZE = 12

--- The probe FontString (created once, hidden). Tests replace this seam with a stub.
function FP.Probe()
    if not fontProbe then
        fontProbe = _G.UIParent:CreateFontString(nil, "OVERLAY")
        fontProbe:Hide()
    end
    return fontProbe
end

--- SetFont(path, 12, "") on `fs` under pcall. Returns (usable, word): usable = SetFont did not raise.
--- word: "true" (already rendered), "false" (pending first render), "nil", "secret", "?<type>",
--- "raised:notfound" or "raised:<clipped message>". Never raises.
function FP.Try(fs, path)
    local ok, r = pcall(fs.SetFont, fs, path, FP.SIZE, "")
    if not ok then
        local msg = Dev.S(r, 200)
        if msg:find("file not found", 1, true) then return false, "raised:notfound" end
        return false, "raised:" .. Dev.clip(msg, 40)
    end
    if Dev.isSecret(r) then return true, "secret" end
    if r == true then return true, "true" end
    if r == false then return true, "false" end
    if r == nil then return true, "nil" end
    return true, "?" .. type(r)
end

--- "Interface\AddOns\Forte_Core\Fonts\X.ttf" -> "Forte_Core\Fonts\X.ttf" (display only).
function FP.ShortPath(path)
    local p = tostring(path):gsub("/", "\\"):gsub("\\\\+", "\\")
    local rest = p:match("^[Ii][Nn][Tt][Ee][Rr][Ff][Aa][Cc][Ee]\\[Aa][Dd][Dd][Oo][Nn][Ss]\\(.*)$")
    return rest or p
end

--- One-line diagnostic, <= Dev.DETAIL_MAX chars: "ctl=<control word>; cd,tm=<word> @<path>; sw=<word> @<path>".
--- `entries` = { { name = "cd", path = <string|nil>, word = "..." } ... }; entries with the same path
--- and word are merged so the (long) path is printed once.
function FP.Detail(controlWord, entries)
    local out, order, groups = { "ctl=" .. tostring(controlWord) }, {}, {}
    for _, e in ipairs(entries) do
        local path = type(e.path) == "string" and FP.ShortPath(e.path) or "-"
        local key = path .. "\0" .. e.word
        local g = groups[key]
        if not g then
            g = { names = {}, path = path, word = e.word }
            groups[key] = g
            order[#order + 1] = g
        end
        g.names[#g.names + 1] = e.name
    end
    for _, g in ipairs(order) do
        out[#out + 1] = table.concat(g.names, ",") .. "=" .. g.word .. " @" .. g.path
    end
    return Dev.clip(table.concat(out, "; "), Dev.DETAIL_MAX)
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

    T.check("frames: font probe control (Blizzard FRIZQT__.TTF SetFont does not raise)", function()
        local usable, word = FP.Try(FP.Probe(), FP.CONTROL_PATH)
        if not usable then T.fail("control " .. FP.CONTROL_PATH .. " SetFont -> " .. word .. " (the probe itself is broken)") end
        T.note("SetFont -> " .. word)
    end)

    local function fontDisplays()
        return {
            { "cooldown", FX.Cooldown and FX.Cooldown.Display, "cd" },
            { "timer", FX.Timer and FX.Timer.Display, "tm" },
            { "hunter swing", FX.Hunter and FX.Hunter.Swing, "sw" },
        }
    end

    T.check("frames: the shipped .ttf font object is usable", function()
        local _, controlWord = FP.Try(FP.Probe(), FP.CONTROL_PATH)
        local entries, bad, checked = {}, 0, 0
        for _, d in ipairs(fontDisplays()) do
            local disp = d[2]
            if type(disp) == "table" then
                checked = checked + 1
                local path = disp.fontFile
                local usable, word
                if type(path) ~= "string" then
                    usable, word = false, "nopath"        -- the display fell back to its template font
                elseif not path:lower():find("%.ttf$") then
                    usable, word = false, "notttf"
                else
                    usable, word = FP.Try(FP.Probe(), path)
                end
                if not usable then bad = bad + 1 end
                entries[#entries + 1] = { name = d[3], path = path, word = word }
            end
        end
        if checked == 0 then T.skip("no display with a font yet") end
        local detail = FP.Detail(controlWord, entries)
        if bad > 0 then T.fail(detail) end
        T.note(Dev.clip(detail .. " (true=rendered, false=pending first render)", Dev.DETAIL_MAX))
    end)

    T.check("frames: the shipped font has rendered", function()
        local path
        for _, d in ipairs(fontDisplays()) do
            if type(d[2]) == "table" and type(d[2].fontFile) == "string" then path = d[2].fontFile break end
        end
        if not path then T.skip("no display font path") end
        local fs = FP.Probe()
        local usable, word = FP.Try(fs, path)
        if not usable then T.skip("SetFont raised: " .. word) end
        local okGet, got = pcall(fs.GetFont, fs)
        got = okGet and Dev.plain(got)
        if type(got) ~= "string" or got:lower() ~= path:lower() then T.skip("pending first render") end
        T.note("GetFont -> " .. FP.ShortPath(got))
    end)

    T.check("frames: Forte_Dev beacon is 96x6 at the top-left", function()
        local B = Dev.Beacon
        T.truthy(B and B.frame, "beacon frame built")
        local w, h = facts(B.frame)
        T.near(w, 96, "beacon width")
        T.near(h, 6, "beacon height")
        local ok, point, _, _, x, y = pcall(B.frame.GetPoint, B.frame)
        T.eq(ok and Dev.plain(point), "TOPLEFT", "beacon anchor")
        T.near(num(x), 0, "beacon x offset")
        T.near(num(y), 0, "beacon y offset")
    end)
end)
