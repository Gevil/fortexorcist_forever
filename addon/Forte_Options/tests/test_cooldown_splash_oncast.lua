-- addon/Forte_Options/tests/test_cooldown_splash_oncast.lua
-- Issue #1: the Cooldown page's new row "Splash icons when cast"
-- (`SplashOnCast`, default OFF, sparse). The bar's `Splash ready cooldowns`
-- acts at READY only; this row is the opt-in for the old first-sighting
-- splash, which the original ForteXorcist did not do.

local FX = ForteXorcist
local O = FX.Options
local S = FX.Settings

test("Cooldown page: 'Splash icons when cast' sits in Specifics with a tip that says what it does",
function()
    O:Open("Cooldown")
    local page = O.pagesBuilt["Cooldown"]
    local found, section
    for si, sec in ipairs(page.sections) do
        for _, wd in ipairs(sec.widgets) do
            if wd.spec.key == "SplashOnCast" then found, section = wd, si end
        end
    end
    assertNotNil(found, "the row is on the Cooldown page")
    assertEquals(3, section, "it rides the Specifics section with the other Splash rows")
    assertEquals("Splash icons when cast", found.label:GetText())
    local tip = found.spec.tip
    assertNotNil(tip)
    assertTrue(tip:find("original", 1, true) ~= nil,
        "the tip states the original did not do it")
    assertTrue(tip:find("cast", 1, true) ~= nil, "the tip says what it does")
    assertTrue(tip:find("Off by default", 1, true) ~= nil)
end)

test("Cooldown page: SplashOnCast defaults OFF, is sparse, and rides the section recycle",
function()
    assertEquals(false, S:GetDefault("Cooldown", "SplashOnCast"))
    local t = S._store("Cooldown")
    S:Reset("Cooldown", "SplashOnCast")
    assertEquals(nil, t.SplashOnCast, "the default is not written")
    O:Open("Cooldown")
    local rec = O.pagesBuilt["Cooldown"].sections[3].bar.recycle
    S:Set("Cooldown", "SplashOnCast", true)
    assertEquals(true, t.SplashOnCast)
    rec:GetScript("OnClick")(rec)
    assertEquals(false, S:Get("Cooldown", "SplashOnCast"))
    assertEquals(nil, t.SplashOnCast, "the recycle removes the key again")
end)
