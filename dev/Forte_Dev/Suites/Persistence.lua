-- Forte_Dev/Suites/Persistence.lua
-- SavedVariables round trip. Every run writes a fresh nonce into ForteDevDB.nonce; the NEXT UI load
-- finds the one the previous load left on disk (Dev.state.prevNonce, captured in Dev.InitDB before
-- anything was written) and this suite verifies it. The first run ever (or after `clear` + wipe) has no
-- nonce from a previous load: that is a skip, "pending first reload".

ForteXorcist = ForteXorcist or {}
local FX = ForteXorcist
local Dev = FX.Dev

local counter = 0

local function makeNonce()
    counter = counter + 1
    local value = string.format("fx%d-%d-%d", Dev.now(), Dev.DB().runId, counter)
    return { value = value, check = value:reverse(), written = Dev.now(), stamp = Dev.stamp() }
end

Dev.RegisterSuite("persistence", "ooc", function(T)
    T.check("persistence: nonce from the previous load survived", function()
        local prev = Dev.state.prevNonce
        -- Write the nonce for the NEXT load first, so a failure below cannot leave none behind.
        Dev.DB().nonce = makeNonce()
        if not prev then T.skip("pending first reload (no nonce from a previous load)") end
        T.eq(type(prev.value), "string", "nonce value")
        T.eq(prev.check, prev.value:reverse(), "nonce check string")
        T.note("nonce " .. Dev.clip(prev.value, 40) .. " written " .. tostring(prev.written) .. " by " .. prev.stamp)
    end)

    T.check("persistence: ForteDevDB is the contract shape", function()
        local db = Dev.DB()
        T.eq(type(db.runs), "table", "runs")
        T.eq(type(db.commands), "table", "commands")
        T.eq(type(db.runId), "number", "runId")
        T.eq(type(db.stamp), "string", "stamp")
        T.eq(type(db.build), "string", "build")
    end)
end)
