-- addon/Forte_Messages/Pages/RaidMsg.lua
-- The Party/Raid Messages page: it lights the `RaidMsg` index cell
-- (O.INDEX: { "RaidMsg", "Party/Raid", GREEN } -- Forte_Options/UI/
-- Window.lua:59). The routing is the original's: bit1 of a message row
-- sends FW:ToGroup (RAID in a raid, PARTY in a party), bit2 sends
-- FW:ToChannel (SAY/YELL/a channel) -- the two master switches `OutputRaid`
-- and `Output` are the original's own rows (Forte_Core.lua:2046-2070,
-- defaults :2518-2519), and each row carries its own group/channel switches
-- exactly like the row's `{[0]=bits}` bits (Forte_Core.lua:2525-2527).
--
-- LEGALITY (the page says it; docs/messages-sounds.md carries the evidence):
-- every send goes through C_ChatInfo.SendChatMessage and is gated on the
-- chat-messaging-lockdown checks first (Core/Announce.lua) -- inside an
-- instance a locked-down send is silently swallowed by the client
-- (EUI_Chat_EditBox.lua:64-68), so we do not pretend it went: the gate
-- skips it, counts it, and `/fx messages` reports the count.
--
-- THE SHIPPED-DEFAULT LAW (the manager ruling of 2026-11-02 on review 4 E2):
-- EVERY group/channel announce on this page ships OFF -- the three announce
-- rows, all twelve fade/break checkboxes, and all 40 cast-announce
-- checkboxes (the 20 rows x group/channel, wave 2b T2). A default install
-- therefore never speaks to a party or a raid without one click per row.
-- The verbatim
-- half is the TEXTS (and the texts' fade thresholds); the source's own
-- `{[0]=bits}` values ride each row's `bits` field and are named in that
-- row's section tip -- the source ships Banish/Enslave/Seduction party-ON
-- (Forte_Class/Warlock/Warlock.lua:372-373, :382-391), and ticking the box
-- restores that. The two master switches stay the original's (OutputRaid
-- true, Output on): with every row off, they gate nothing on their own.

ForteXorcist = ForteXorcist or {}
local FX = ForteXorcist

FX.Messages = FX.Messages or {}
FX.Messages.Pages = FX.Messages.Pages or {}
local P = FX.Messages.Pages

local M = "RaidMsg"

-- The CC fade/break rows -- the original's registrations (ST:RegisterOnTimerFade
-- of Fear/Banish/Enslave Demon/Seduction/Mesmerize, Warlock.lua:246-250,
-- Polymorph Mage.lua:92, Sap Rogue.lua:80) and its message rows
-- (Warlock.lua:373,:387-391, Mage.lua:122, Rogue.lua:102). WHAT IS VERBATIM is
-- the TEXT (and the text's first number, which IS the fade threshold --
-- ST_GetFadeTime, Forte_Timer.lua:1590-1603) and the row's `{[0]=bits}` slot,
-- carried here as the row's `bits` field (0 silent, 1 group). WHAT IS NOT
-- VERBATIM is the SEND: every fade/break checkbox ships OFF, because a
-- default install must not speak to a party/raid the owner never opted into
-- (the manager ruling of 2026-11-02 on review 4 E2; the source's own party-ON
-- bits are recorded in the row's section tip).
--
-- The KEYS are the FOREVER names (the registry gate, review 4 E4): a fade
-- entry only bites when Forte_Timer has a row of that exact name, and rows
-- come from `FX.Timer.Registry:Build(FX._playerClass)` over the GENERATED
-- data (`addon/Forte_<Class>/Data/<Class>.lua`, the durationMs > 0 gate).
-- Forever names `Enslave Demon` **Subjugate Demon** (mythicsim
-- spells.jsonl: 1098/11725/11726, ClassFlags.Family 5 = Warlock; the generated
-- Warlock data carries `Subjugate Demon` 11726), so the Enslave row keys on
-- that name -- the TEXTS stay the original's (">> Enslave on %s …").
-- `Seduction`/`Mesmerize` are the Succubus pet's casts (the original's
-- `AddSpell(6358, 30, "Pet")` / `AddSpell(115268, 30, "Pet") -- Mesmerize`,
-- Warlock.lua:73-74). CORRECTION (Iteration H wave 1, 2026-11-02, PLAN §11.1):
-- the Iteration G verdict that the pair is not in the Forever data was
-- measured on the **70425** data set and on the simulator client only. The
-- live 70707 client's own spell store carries the kit --
-- `wowsims/forever` (`164d1cf6`) `sim/core/spelldata/spells_auto_gen.go`:
-- `6358 Seduction`, `6359 Seduction` (ranks), `24594 Mesmerize`, alongside
-- `Devour Magic`, `Spell Lock`, `Soothing Kiss`, `Lash of Pain`, `Suffering`.
-- The pair is LIVE data, and the pair is LIVE behaviour as of wave 2b's
-- "PetRows v2": Forte_Timer registers the cast spine for the **pet** unit
-- too (its `Core/Casts.lua` + `Module.lua` pet registration), so a pet
-- Seduction inserts a row and the shared FADING/BROKEN sites light this
-- pair and the Mesmerize alias that shares it (Mesmerize has no durationMs
-- in the data, so no own row; the fade/break keys alias onto Seduction per
-- `P.FADE_SPELL_KEYS`). `Seduction` 6358 is a generated Warlock row and
-- `Mesmerize` 24594 lands as its name row (wave 2a D3). The rows and their
-- texts ship so the owner sees the pair (the census, review 4 E2) and the
-- tip names the live feed. Mesmerize shares the Seduction rows
-- (ST:RegisterOnTimerFade(mesmerize,"SeduceFade"), Warlock.lua:250).
P.FADE_ROWS = {
    { prefix = "Fear", spell = "Fear", bits = 0,
        fade = ">> Fear on %s Fading in 3 seconds! <<",
        brk = ">> Fear on %s Broke Early! <<",
        note = "The source ships these rows OFF (bits 0, Mage/Warlock :387)." },
    { prefix = "Banish", spell = "Banish", bits = 1,
        fade = ">> Banish on %s Fading in 3 seconds! <<",
        brk = ">> Banish on %s Broke Early! <<",
        note = "The source ships this ON (party bits 1, Warlock.lua:372-391) "
            .. "- tick to restore." },
    { prefix = "Enslave", spell = "Subjugate Demon", bits = 1,
        fade = ">> Enslave on %s Fading in 3 seconds! <<",
        brk = ">> Enslave on %s Broke Early! <<",
        note = "The source ships this ON (party bits 1, Warlock.lua:372-391) "
            .. "- tick to restore. Forever names the spell Subjugate Demon; "
            .. "the texts stay the original's." },
    { prefix = "Seduction", spell = "Seduction", bits = 1,
        fade = ">> Seduction on %s Fading in 3 seconds! <<",
        brk = ">> Seduction on %s Broke Early! <<",
        note = "The source ships this ON (party bits 1, Warlock.lua:372-391) "
            .. "- tick to restore. LIVE: this pair fires from the Succubus "
            .. "PET's own casts - Forte_Timer's pet cast feed (its Casts/"
            .. "Module pet registration, wave 2b 'PetRows v2') inserts the "
            .. "row of a pet Seduction and its FADING/BROKEN rides the "
            .. "shared sites, so the fade/break announces light with the "
            .. "boxes ticked. The spells are live 70707 data (the client's "
            .. "own spell store: Seduction 6358/6359, Mesmerize 24594 - the "
            .. "Iteration G 'no such spell' verdict measured the 70425 data "
            .. "set and the simulator only); the Mesmerize alias shares "
            .. "this pair (no durationMs of its own, so no own row). "
            .. "See docs/messages-sounds.md.",
    },
    { prefix = "Polymorph", spell = "Polymorph", bits = 0,
        fade = ">> Polymorph on %s Fading in 3 seconds! <<",
        brk = ">> Polymorph on %s Broke Early! <<",
        note = "The source ships these rows OFF (bits 0, Mage.lua:122)." },
    { prefix = "Sap", spell = "Sap", bits = 0,
        fade = ">> Sap on %s Fading in 3 seconds! <<",
        brk = ">> Sap on %s Broke Early! <<",
        note = "The source ships these rows OFF (bits 0, Rogue.lua:102)." },
}
P.FADE_SPELL_KEYS = {
    Fear = "Fear", Banish = "Banish", ["Subjugate Demon"] = "Enslave",
    Seduction = "Seduction", Mesmerize = "Seduction",
    Polymorph = "Polymorph", Sap = "Sap",
}

-- THE CAST ANNOUNCE ROWS (wave 2b T2, `docs/class-port.md` S17: the 20
-- `CA:RegisterOnSelfCastSuccess` + `CA:CastShow` raid warnings of
-- Druid.lua:190-227, Paladin.lua:125-168 and Warrior.lua:79-104). The
-- `P.FADE_ROWS` shape, one row per announced self-cast: the row's TEXTS and
-- its `{[0]=bits}` value are the verbatim half (the texts are the
-- originals', quoted below with their file:line), the SEND is the opt-in
-- half: `prefix .. "Party"` / `prefix .. "Channel"` every one of them ships
-- OFF (the shipped-default law, review 4 E2 - the manager ruling of
-- 2026-11-02), so a fresh install never talks to a party about a cooldown
-- the owner never asked it to talk about. `bits` records the source's own
-- value (0 silent, 1 party; the source's own Vigilance row is the one row
-- that ships silent, Warrior.lua:104) and the section tip names it.
--
-- The KEYS are the FOREVER names (the fade registry gate, review 4 E4, in
-- the announce form): the hook matches the NAME the player's own cast event
-- resolves to, so a key the client's spell set does not carry is an inert
-- row - the row's note names exactly that, and the pair of them on this
-- build are Ardent Defender (`31850`, no row in the 70425 pull nor in the
-- 70707 store's Names table) and Salvation (`1038`, in the 70425 base data,
-- REMOVED on 70707 - the generated Paladin data's own header records the
-- drop). Renames are keyed on the FOREVER name and keep the source's text,
-- the Subjugate Demon precedent: Hand of Freedom -> `Blessing of Freedom`,
-- Hand of Protection -> `Blessing of Protection`, Hand of Sacrifice ->
-- `Hand of Sacrifice` (462853, with the 2012 id 6940's Forever name
-- `Blessing of Sacrifice` aliasing to the same row, the Mesmerize-shares-
-- Seduction shape), Guardian of Ancient Kings -> `Avenging Wrath`
-- (407788/409934 - the Paladin's own DR of the same family).
--
-- The `spec` field is the source's specialization gate, re-expressed on the
-- PINNED pair (the 2012 globals `GetSpecialization`/`GetActiveSpecGroup` are
-- absent from the catalog; `C_SpecializationInfo.GetSpecialization` +
-- `C_SpecializationInfo.GetActiveSpecGroup` are in it,
-- @SpecializationInfoDocumentation.lua:236/:40). Exactly one of the 20 rows
-- carries a gate: Guardian of Ancient Kings was gated in the source
-- (Paladin.lua:139), and its Forever name row is the same ret paladin DR.
--
-- Q5 (the owner ruling of 2026-11-02): the Druid rows carry PLAIN spell
-- names. The source's `FWL._FERAL/_BEAR/_CAT` form suffixes
-- (Druid/Localization.lua:73-88) label the form-paired BAR rows (the S16
-- `SetCustomName` seam) - they are not announce labels, and none of the six
-- Druid announce rows is form-paired.
P.CAST_ROWS = {
    { prefix = "Barkskin", spell = "Barkskin", bits = 1, key = "BSStart",
        src = "Druid.lua:213", group = "Self Damage Reduction",
        text = "+++ Barkskin (10 sec) +++",
        note = "The source ships this ON (party bits 1) - tick to restore." },
    { prefix = "SurvivalInstincts", spell = "Survival Instincts", bits = 1,
        key = "SIStart", src = "Druid.lua:216",
        group = "Self Damage Reduction",
        text = "+++ Survival Instincts (12 sec) +++",
        note = "The source ships this ON (party bits 1) - tick to restore." },
    { prefix = "FrenziedRegeneration", spell = "Frenzied Regeneration",
        bits = 1, key = "FRStart", src = "Druid.lua:219",
        group = "Self Damage Reduction",
        text = "+++ Frenzied Regeneration (20 sec) +++",
        note = "The source ships this ON (party bits 1) - tick to restore." },
    { prefix = "Rebirth", spell = "Rebirth", bits = 1, key = "RebirthStart",
        src = "Druid.lua:223", group = "Other", target = true,
        text = ">>> Rebirth on %s <<<",
        note = "The source hands the target to this row (CastShow(t), "
            .. "Druid.lua:200). The source ships it ON (party bits 1)." },
    { prefix = "Innervate", spell = "Innervate", bits = 1,
        key = "InnervateStart", src = "Druid.lua:226", group = "Other",
        target = true, text = ">>> Innervate on %s <<<",
        note = "The source hands the target (Druid.lua:202). The source "
            .. "ships this ON (party bits 1)." },
    { prefix = "Tranquility", spell = "Tranquility", bits = 1,
        key = "TranquilityStart", src = "Druid.lua:229", group = "Other",
        text = ">>> Tranquility up <<<",
        note = "No target in the source's text (Druid.lua:204). The source "
            .. "ships this ON (party bits 1)." },
    { prefix = "AuraMastery", spell = "Aura Mastery", bits = 1,
        key = "AMStart", src = "Paladin.lua:151",
        group = "Raid Damage Reduction", text = "+++ Aura Mastery (6sec) +++",
        note = "The source's 2012 id 31821 has no Forever row; the name "
            .. "does (the 70707 store's Names table carries Aura Mastery "
            .. "409932), and the announce keys on the NAME. The source "
            .. "ships this ON (party bits 1)." },
    { prefix = "Salvation", spell = "Salvation", bits = 1, key = "SalvStart",
        src = "Paladin.lua:154", group = "Hands", target = true,
        text = "+++ Salvation on %s (10sec) +++",
        note = "INERT ON THIS BUILD, for one named reason: the spell is "
            .. "gone. 1038 is a row of the 70425 base data and the 70707 "
            .. "store dropped it - the generated Paladin data's header "
            .. "records 'Salvation: id(s) 1038 removed on 70707 - the name "
            .. "is gone from the build's Names table'. No cast of the name "
            .. "can reach the hook, so the row cannot fire. The source "
            .. "ships this ON (party bits 1)." },
    { prefix = "Sacrifice", spell = "Hand of Sacrifice", bits = 1,
        key = "SacStart", src = "Paladin.lua:156", group = "Hands",
        target = true, text = "+++ Sacrifice on %s (12sec) +++",
        note = "Forever's 462853 Hand of Sacrifice is the key; the source's "
            .. "2012 id 6940 lives on as the Forever name Blessing of "
            .. "Sacrifice (20729), which aliases to this row the way "
            .. "Mesmerize shares the Seduction rows. The source ships "
            .. "this ON (party bits 1)." },
    { prefix = "Freedom", spell = "Blessing of Freedom", bits = 1,
        key = "FreeStart", src = "Paladin.lua:158", group = "Hands",
        target = true, text = "+++ Freedom on %s (6sec) +++",
        note = "The 2012 Hand of Freedom is Forever's Blessing of Freedom "
            .. "(1044) - the key is the Forever name, the text the "
            .. "source's. The source ships this ON (party bits 1)." },
    { prefix = "HandOfProtection", spell = "Blessing of Protection", bits = 1,
        key = "BOPStart", src = "Paladin.lua:160", group = "Hands",
        target = true, text = "+++ Hand of Protection on %s (12sec) +++",
        note = "The 2012 Hand of Protection is Forever's Blessing of "
            .. "Protection (10278). The source ships this ON (party bits 1)." },
    { prefix = "DivineProtection", spell = "Divine Protection", bits = 1,
        key = "DPStart", src = "Paladin.lua:162",
        group = "Self Damage Reduction",
        text = "+++ Divine Protection (10sec) +++",
        note = "The source ships this ON (party bits 1)." },
    { prefix = "GuardianOfAncientKings", spell = "Avenging Wrath", bits = 1,
        key = "GOTAKStart", src = "Paladin.lua:164", spec = 2,
        group = "Self Damage Reduction",
        text = "+++ Guardian of Ancient Kings (12sec) +++",
        spec = 2,
        note = "The 2012 Guardian of Ancient Kings (86659/86669) has no "
            .. "row on either build; Forever's Paladin DR of that family "
            .. "is Avenging Wrath (407788/409934), which is the key, the "
            .. "text the source's (the Subjugate Demon shape). The source "
            .. "gates this row on the specialization (Paladin.lua:139, "
            .. "GetSpecialization(...) == 2); the row's OWN key spell is "
            .. "spec-specific on this build, so no gate is enforced (the "
            .. "'spec' field records the source's gate - the pinned "
            .. "C_SpecializationInfo pair, the row's `spec` field) as an "
            .. "OPEN item for a build where a shared name meets the row. "
            .. "The source ships this ON (party bits 1)." },
    { prefix = "ArdentDefender", spell = "Ardent Defender", bits = 1,
        key = "ADStart", src = "Paladin.lua:166",
        group = "Self Damage Reduction",
        text = "+++ Ardent Defender (10sec) +++",
        note = "INERT ON THIS BUILD, for one named reason: the 2012 spell "
            .. "(31850) has no row in the 70425 pull and no name in the "
            .. "70707 store's Names table, so no cast of it can reach the "
            .. "hook. The source ships this ON (party bits 1)." },
    { prefix = "ShieldWall", spell = "Shield Wall", bits = 1, key = "SWStart",
        src = "Warrior.lua:100", group = "Self Damage Reduction",
        text = "+++ Shield Wall (12 sec) +++",
        note = "The source ships this ON (party bits 1)." },
    { prefix = "LastStand", spell = "Last Stand", bits = 1, key = "LSStart",
        src = "Warrior.lua:101", group = "Self Damage Reduction",
        text = "+++ Last Stand (20 sec) +++",
        note = "The source ships this ON (party bits 1)." },
    { prefix = "RallyingCry", spell = "Rallying Cry", bits = 1, key = "RCStart",
        src = "Warrior.lua:98", group = "Raid Damage Reduction",
        text = "+++ Rallying Cry (10 sec) +++",
        note = "The source ships this ON (party bits 1)." },
    { prefix = "EnragedRegeneration", spell = "Enraged Regeneration",
        bits = 1, key = "ERStart", src = "Warrior.lua:102",
        group = "Self Damage Reduction",
        text = "+++ Enraged Regeneration (10 sec) +++",
        note = "The 2012 id 55694's Forever row is 402913 of the same name. "
            .. "The source ships this ON (party bits 1)." },
    { prefix = "Intervene", spell = "Intervene", bits = 1,
        key = "InterveneStart", src = "Warrior.lua:99",
        group = "Raid Damage Reduction", target = true,
        text = "+++ Intervene on %s (10 sec) +++",
        note = "The source hands the target (Warrior.lua:95). The source "
            .. "ships this ON (party bits 1)." },
    { prefix = "Vigilance", spell = "Vigilance", bits = 0,
        key = "VigilanceStart", src = "Warrior.lua:104", group = "Other",
        target = true, text = ">>> Vigilance on %s (12 sec) <<<",
        note = "The ONE row the source itself ships SILENT (bits 0, "
            .. "Warrior.lua:104) - here the shipped default and the "
            .. "source's bits agree. The source hands the target "
            .. "(Warrior.lua:96)." },
}

-- The announce key table: the FOREVER spell name (plus the alias names) ->
-- the row's prefix, the `P.FADE_SPELL_KEYS` shape. The hook canonicalizes
-- the client's localized cast name onto the English data name first
-- (`FX.Locale.CanonicalName`, H1b) and then asks this table, so a German
-- `Schildwall` meets the Shield Wall row.
P.CAST_SPELL_KEYS = {}
do
    for _ = 1, #P.CAST_ROWS do
        local row = P.CAST_ROWS[_]
        P.CAST_SPELL_KEYS[row.spell] = row.prefix
    end
    -- The aliases: the 2012 id 6940's Forever name shares the Sacrifice row.
    P.CAST_SPELL_KEYS["Blessing of Sacrifice"] = "Sacrifice"
end

-- The class each row's source spell belongs to - the survey's split (docs/
-- class-port.md S17: 6 Druid, 8 Paladin, 6 Warrior), the census' count. The
-- announce itself is name-keyed and class-blind (a Warrior who somehow
-- hears a `Blessing of Freedom` cast gets the Paladin row, the Soulstone
-- family pattern's law): this table is the SHAPE record, so a row dropped
-- or a class left short fails the census.
P.CAST_ROW_CLASS = {
    Barkskin = "Druid", SurvivalInstincts = "Druid",
    FrenziedRegeneration = "Druid", Rebirth = "Druid", Innervate = "Druid",
    Tranquility = "Druid",
    AuraMastery = "Paladin", Salvation = "Paladin", Sacrifice = "Paladin",
    Freedom = "Paladin", HandOfProtection = "Paladin",
    DivineProtection = "Paladin", GuardianOfAncientKings = "Paladin",
    ArdentDefender = "Paladin",
    ShieldWall = "Warrior", LastStand = "Warrior", RallyingCry = "Warrior",
    EnragedRegeneration = "Warrior", Intervene = "Warrior",
    Vigilance = "Warrior",
}

P.DEFAULTS = P.DEFAULTS or {}
P.DEFAULTS[M] = {
    -- The master switches (the original's OutputRaid :2518 default true,
    -- Output :2519 default on with the channel slot defaulting to SAY --
    -- the original's "MyProChannel" was a sample value, not a default).
    OutputRaid = true,
    OutputEnable = true,
    OutputChannel = "SAY",
    -- "<spell> ready" -- the CooldownLeft row (Forte_Core.lua:2527). The
    -- announce half is OPT-IN (off), the chat text is the original's.
    ReadyAnnounce = false,
    ReadyChannel = false,
    ReadyAnnounceText = ">> %s is ready <<",
    -- The timer-expiry announce -- the TimeLeft / TimeLeftNoTarg rows
    -- (Forte_Core.lua:2525-2526). Opt-in.
    ExpireAnnounce = false,
    ExpireChannel = false,
    ExpireAnnounceText = ">> %s on %s is fading <<",
    ExpireAnnounceNoTargetText = ">> %s is fading <<",
    -- "Soulstone used on X" -- the Warlock family's SoulstoneSuccess row,
    -- verbatim ("Soulstoned >> %s << Use it well!",
    -- Forte_Class/Warlock/Warlock.lua:365), shipped-default-off kept.
    SoulstoneAnnounce = false,
    SoulstoneChannel = false,
    SoulstoneAnnounceText = "Soulstoned >> %s << Use it well!",
}
do
    for _ = 1, #P.FADE_ROWS do
        local row = P.FADE_ROWS[_]
        P.DEFAULTS[M][row.prefix .. "FadeText"] = row.fade
        P.DEFAULTS[M][row.prefix .. "BreakText"] = row.brk
        -- E2 (review 4, manager ruling 2026-11-02): EVERY group/channel
        -- announce ships OFF. The source's `{[0]=bits}` value is the row's
        -- `bits` field (1 for Banish/Enslave/Seduction, Warlock.lua:372-373,
        -- :382-391) and is recorded in that row's section tip -- it is not a
        -- shipped default, because a fresh install must not talk to a
        -- party/raid the owner never asked it to talk to. The texts are the
        -- verbatim half; the SEND is the opt-in half.
        P.DEFAULTS[M][row.prefix .. "FadeParty"] = false
        P.DEFAULTS[M][row.prefix .. "BreakParty"] = false
        P.DEFAULTS[M][row.prefix .. "FadeChannel"] = false
        P.DEFAULTS[M][row.prefix .. "BreakChannel"] = false
    end
    -- E2, the same law for the 20 cast rows: the TEXTS are verbatim, the
    -- SENDS ship OFF. A fresh install announces nothing to anybody.
    for _ = 1, #P.CAST_ROWS do
        local row = P.CAST_ROWS[_]
        P.DEFAULTS[M][row.prefix .. "CastText"] = row.text
        P.DEFAULTS[M][row.prefix .. "CastParty"] = false
        P.DEFAULTS[M][row.prefix .. "CastChannel"] = false
    end
end

P.WIDGET_TIPS = P.WIDGET_TIPS or {}
local TIPS = {}
P.WIDGET_TIPS[M] = TIPS
TIPS.OutputRaid = "The group master switch (the original's OutputRaid, "
    .. "Forte_Core.lua:2518): RAID in a raid, PARTY in a party, a local "
    .. "echo with no group. Applied live."
TIPS.OutputEnable = "The channel master switch (the original's Output, "
    .. "Forte_Core.lua:2519). Applied live."
TIPS.OutputChannel = "Where the channel half goes: SAY, YELL or CHANNEL1"
    .. "-CHANNEL10 (the ToChannel law, Forte_Core.lua:2058-2070). Anything "
    .. "else is refused. Applied live."
TIPS.ReadyAnnounce = "Announce to your party/raid when a tracked cooldown "
    .. "pops (the CooldownLeft text below; the original's own default is "
    .. "OFF). Applied live."
TIPS.ReadyChannel = "The SAY/YELL/channel twin of the switch above. "
    .. "Applied live."
TIPS.ReadyAnnounceText = "Template; %%s is the spell (the original's "
    .. "CooldownLeft, Forte_Core.lua:2527). Applied live."
TIPS.ExpireAnnounce = "Announce to your party/raid when a Spell Timer "
    .. "expires (the TimeLeft text below; opt-in). Applied live."
TIPS.ExpireChannel = "The SAY/YELL/channel twin. Applied live."
TIPS.ExpireAnnounceText = "Template; %%s1 the spell, %%s2 the target (the "
    .. "original's TimeLeft, Forte_Core.lua:2525). Applied live."
TIPS.ExpireAnnounceNoTargetText = "The no-target twin (TimeLeftNoTarg, "
    .. "Forte_Core.lua:2526). Applied live."
TIPS.SoulstoneAnnounce = "Announce to your party/raid when YOU create a "
    .. "soulstone for someone (the original's SoulstoneSuccess, Warlock.lua:"
    .. "365 -- the shipped default is OFF and stays OFF; opt-in). Applied "
    .. "live."
TIPS.SoulstoneChannel = "The SAY/YELL/channel twin. Applied live."
TIPS.SoulstoneAnnounceText = "The original's text, verbatim: Soulstoned >> "
    .. "%%s << Use it well! (Warlock.lua:365). Applied live."

-- The cast rows' tips, generated from the table (the fade rows' tips are
-- generated the same way, in the section meta).
do
    for _ = 1, #P.CAST_ROWS do
        local row = P.CAST_ROWS[_]
        local src = "The source's " .. row.key .. " row (" .. row.src
            .. "), the text verbatim. " .. (row.note or "")
        TIPS[row.prefix .. "CastParty"] = "Announce to your party/raid when "
            .. "YOU cast " .. row.spell .. " (opt-in). " .. src
            .. " Applied live."
        TIPS[row.prefix .. "CastChannel"] = "The SAY/YELL/channel twin of "
            .. "the switch above. Applied live."
        TIPS[row.prefix .. "CastText"] = "Template; %%s is your cast's "
            .. "target. " .. src .. " Applied live."
    end
end

function P.RegisterRaidMsgPage()
    local O = FX.Options
    if not O or not O.pages or not FX.Settings then return false end
    if not O.pages[M] then
        FX.Settings:Register(M, P.DEFAULTS[M])
        O:RegisterPage({
            id = M,
            module = M,
            title = "Party/Raid",
            colour = O.C.GREEN,
            build = function(b)
                b.Tips({
                    "Announcements go to your RAID in a raid and to your PARTY in a party (the ToGroup law), to SAY/YELL/a channel on the channel half (the ToChannel law).",
                    "Inside instances the client locks addon chat (chat-messaging-lockdown): the gate then skips the send, counts it, and /fx messages shows the count -- nothing pretends a swallowed line went.",
                    "Every announce row is opt-in: EVERY group and channel checkbox on this page ships OFF (the three announce rows, the twelve fade/break boxes, the 40 cast-announce boxes), so a default install sends nothing to anyone. The original's own bits ride each row's tip (Banish/Enslave/Seduction ship party-ON, Warlock.lua:372-391; the 20 Druid/Paladin/Warrior cast rows ship party-ON too, and Warrior Vigilance is the one row the source ships silent) - tick to restore.",
                    "No raid-target data is read anywhere in this module (the target is your own cast's, the names your own events carry).",
                })
                b.Section("Master switches", function(s)
                    s.CHK({ module = M, key = "OutputRaid",
                        label = "Allow party/raid announcements",
                        tip = TIPS.OutputRaid })
                    s.CHK({ module = M, key = "OutputEnable",
                        label = "Allow say/yell/channel announcements",
                        tip = TIPS.OutputEnable })
                    s.STR({ module = M, key = "OutputChannel",
                        label = "Channel", tip = TIPS.OutputChannel })
                end, {
                    module = M,
                    keys = { "OutputRaid", "OutputEnable", "OutputChannel" },
                    tip = "The two master switches (OutputRaid / Output).",
                })
                b.Section("Cooldown Ready", function(s)
                    s.CHK({ module = M, key = "ReadyAnnounce",
                        label = "Announce to group (opt-in)",
                        tip = TIPS.ReadyAnnounce })
                    s.CHK({ module = M, key = "ReadyChannel",
                        label = "Announce to channel (opt-in)",
                        tip = TIPS.ReadyChannel })
                    s.STR({ module = M, key = "ReadyAnnounceText",
                        label = "Text", tip = TIPS.ReadyAnnounceText })
                end, {
                    module = M,
                    keys = { "ReadyAnnounce", "ReadyChannel",
                        "ReadyAnnounceText" },
                    tip = "The CooldownLeft announce half.",
                })
                b.Section("Timer Expiry", function(s)
                    s.CHK({ module = M, key = "ExpireAnnounce",
                        label = "Announce to group (opt-in)",
                        tip = TIPS.ExpireAnnounce })
                    s.CHK({ module = M, key = "ExpireChannel",
                        label = "Announce to channel (opt-in)",
                        tip = TIPS.ExpireChannel })
                    s.STR({ module = M, key = "ExpireAnnounceText",
                        label = "Text", tip = TIPS.ExpireAnnounceText })
                    s.STR({ module = M, key = "ExpireAnnounceNoTargetText",
                        label = "Text (no target)",
                        tip = TIPS.ExpireAnnounceNoTargetText })
                end, {
                    module = M,
                    keys = { "ExpireAnnounce", "ExpireChannel",
                        "ExpireAnnounceText", "ExpireAnnounceNoTargetText" },
                    tip = "The TimeLeft announce half.",
                })
                for _ = 1, #P.FADE_ROWS do
                    local row = P.FADE_ROWS[_]
                    b.Section(row.spell .. " (CC fade/break)", function(s)
                        s.STR({ module = M,
                            key = row.prefix .. "FadeText",
                            label = "Fade text (its first number is the "
                                .. "warning lead)" })
                        s.CHK({ module = M,
                            key = row.prefix .. "FadeParty",
                            label = "Announce the fade to group" })
                        s.CHK({ module = M,
                            key = row.prefix .. "FadeChannel",
                            label = "Announce the fade to channel" })
                        s.STR({ module = M,
                            key = row.prefix .. "BreakText",
                            label = "Break text" })
                        s.CHK({ module = M,
                            key = row.prefix .. "BreakParty",
                            label = "Announce the break to group" })
                        s.CHK({ module = M,
                            key = row.prefix .. "BreakChannel",
                            label = "Announce the break to channel" })
                    end, {
                        module = M,
                        keys = { row.prefix .. "FadeText",
                            row.prefix .. "FadeParty",
                            row.prefix .. "FadeChannel",
                            row.prefix .. "BreakText",
                            row.prefix .. "BreakParty",
                            row.prefix .. "BreakChannel" },
                        tip = "The original's " .. row.spell
                            .. " fade/break rows (the texts verbatim; the "
                            .. "fade text's first number IS the warning "
                            .. "lead, ST_GetFadeTime, Forte_Timer.lua:"
                            .. "1590-1603). " .. (row.note or ""),
                    })
                end
                -- The 20 cast announce rows, wave 2b T2. One section per
                -- row, the rows grouped in the source's own groups. Three
                -- controls each: the text, the group send, the channel
                -- send. The sends ship OFF (E2), the texts verbatim.
                for _ = 1, #P.CAST_ROWS do
                    local row = P.CAST_ROWS[_]
                    b.Section(row.spell .. " (cast)", function(s)
                        s.STR({ module = M, key = row.prefix .. "CastText",
                            label = "Text",
                            tip = TIPS[row.prefix .. "CastText"] })
                        s.CHK({ module = M, key = row.prefix .. "CastParty",
                            label = "Announce to group (opt-in)",
                            tip = TIPS[row.prefix .. "CastParty"] })
                        s.CHK({ module = M, key = row.prefix .. "CastChannel",
                            label = "Announce to channel (opt-in)",
                            tip = TIPS[row.prefix .. "CastChannel"] })
                    end, {
                        tip = "Announces when YOU cast " .. row.spell
                            .. " (the " .. row.key .. " row, " .. row.src
                            .. "), the " .. row.group .. " group of the "
                            .. "source's layout. Every send ships OFF "
                            .. "(the shipped-default law); the source's "
                            .. "own bits for this row are " .. row.bits
                            .. " (0 silent, 1 party).",
                    })
                end
                b.Section("Soulstone", function(s)
                    s.CHK({ module = M, key = "SoulstoneAnnounce",
                        label = "Announce to group (opt-in)",
                        tip = TIPS.SoulstoneAnnounce })
                    s.CHK({ module = M, key = "SoulstoneChannel",
                        label = "Announce to channel (opt-in)",
                        tip = TIPS.SoulstoneChannel })
                    s.STR({ module = M, key = "SoulstoneAnnounceText",
                        label = "Text", tip = TIPS.SoulstoneAnnounceText })
                end, {
                    module = M,
                    keys = { "SoulstoneAnnounce", "SoulstoneChannel",
                        "SoulstoneAnnounceText" },
                    tip = "The SoulstoneSuccess announce half.",
                })
            end,
        })
    end
    return FX.Options.pages[M] ~= nil
end
