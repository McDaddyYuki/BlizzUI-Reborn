-- Boss Timeline shows mechanics only: big hits, AoE, adds, DBM-announced
-- spells and timed abilities; not filler casts like Shadow Bolt.
dofile(TESTS_DIR .. "lib.lua")
local HOSTILE = 0xa48
local TL
local function advance(sec) H.tick(0.1, math.floor(sec / 0.1 + .5)) end
local function cast(guid, who, id, name, event) H.fire("COMBAT_LOG_EVENT_UNFILTERED", GetTime(), event or "SPELL_CAST_SUCCESS", guid, who, HOSTILE, "", nil, 0, id, name, 1) end
local function hit(guid, who, id, name, dest, amount, overkill)
    H.fire("COMBAT_LOG_EVENT_UNFILTERED", GetTime(), "SPELL_DAMAGE", guid, who, HOSTILE, dest, "x", 0x511, id, name, 1, amount, overkill or 0)
end
local function shown(name) for _, ev in ipairs(TL:DisplayList()) do if ev.name == name then return ev end end end
local P1, P2, P3 = "0x0000000000000001", "0x0000000000000002", "0x0000000000000003"
GetNumPartyMembers = function() return 2 end
MOCK.units.party1 = { guid = P2, name = "Healer", player = true, friendly = true, combat = true }
MOCK.units.party2 = { guid = P3, name = "Mage", player = true, friendly = true, combat = true }
UnitHealthMax = function() return 20000 end
MOCK.inInstance = true
for id, n in pairs({ [90101] = "Shadow Bolt", [90102] = "Crushing Blow", [90103] = "Shadow Nova", [90104] = "Raise Dead",
    [43650] = "Enfeeble", [52611] = "Summon Skeletons", [48583] = "Stone Strike" }) do MOCK.spells[id] = { name = n } end
MOCK.spells[90101].castMs = 2000
H.login()
TL = A.Timeline

-- ------------------------------------------------------------ an unknown boss
local g = MOCK.creatureGUID(91000, 1)
MOCK.units.target = { guid = g, name = "Custom Boss", level = 83, class = "worldboss", combat = true }
H.enterCombat()
advance(.2)
check(TL:Active(), "fight tracked")
local t0 = GetTime()
local warnings = {}
hooksecurefunc(A, "TimelineWarn", function(_, sev, name) warnings[#warnings + 1] = sev .. ":" .. name end)
for i = 0, 8 do
    local at = i * 10
    advance(at - (GetTime() - t0))
    -- filler: Shadow Bolt at the tank every 5 seconds, 2s cast, ~12% damage
    for j = 0, 1 do
        if j == 1 then advance(5) end
        cast(g, "Custom Boss", 90101, "Shadow Bolt", "SPELL_CAST_START")
        advance(2)
        cast(g, "Custom Boss", 90101, "Shadow Bolt")
        hit(g, "Custom Boss", 90101, "Shadow Bolt", P1, 2500)
    end
    if i % 2 == 0 then -- every 20s: a hit on the tank for 60%
        cast(g, "Custom Boss", 90102, "Crushing Blow")
        hit(g, "Custom Boss", 90102, "Crushing Blow", P1, 12000)
    end
    if i % 2 == 1 then -- every 20s: hits the whole group for 20%
        cast(g, "Custom Boss", 90103, "Shadow Nova")
        for _, p in ipairs({ P1, P2, P3 }) do hit(g, "Custom Boss", 90103, "Shadow Nova", p, 4000) end
    end
    if i % 2 == 0 then cast(g, "Custom Boss", 90104, "Raise Dead", "SPELL_SUMMON") end
end
local sb, cb, nova = shown("Shadow Bolt"), shown("Crushing Blow"), shown("Shadow Nova")
check(not sb, "filler (Shadow Bolt) is not on the timeline")
check(cb and cb.danger, "a hit for 60% of health is a dangerous mechanic")
check(nova and not nova.danger, "a spell hitting the whole group is a mechanic")
check(shown("Raise Dead"), "summoning adds is a mechanic")
local fl = BlizzUIRebornDB.timeline.bosses[91000].spells
check(not fl[90101] and fl[90102].deadly and fl[90103].aoe, "flags: filler none, big hit dangerous, group hit AoE")
-- Shadow Bolt casts in progress: no timeline entry, no warning
cast(g, "Custom Boss", 90101, "Shadow Bolt", "SPELL_CAST_START")
local castShown = false
for _, ev in ipairs(TL:DisplayList()) do if ev.state == "cast" then castShown = true end end
check(not castShown, "filler casts in progress are not shown")
local fillerWarned = false
for _, w in ipairs(warnings) do if w:find("Shadow Bolt") then fillerWarned = true end end
check(not fillerWarned, "no warnings for filler")
local cbWarned = false
for _, w in ipairs(warnings) do if w:find("Crushing Blow") then cbWarned = true end end
check(cbWarned, "warnings for the dangerous one")
-- the red ring for dangerous abilities
advance(.2)
local red = false
for _, b in ipairs(A.TimelineView.root.icons) do
    if b:IsShown() and b.event and b.event.name == "Crushing Blow" then local r, gg = b.ring:GetVertexColor(); red = r > .9 and gg < .5 end
end
check(red, "dangerous abilities get a red ring")
-- option: show everything
BlizzUIRebornDB.timeline.allAbilities = true
TL:Changed()
local anyCast = false
for _, ev in ipairs(TL:DisplayList()) do if ev.state == "cast" and ev.name == "Shadow Bolt" then anyCast = true end end
check(anyCast, "'Show every boss ability' shows filler casts too")
BlizzUIRebornDB.timeline.allAbilities = nil
MOCK.units.target = nil
MOCK.units.party1.combat, MOCK.units.party2.combat = false, false -- the whole group leaves combat
H.leaveCombat()
advance(4)

-- ------------------------------------------------------------ Skarvald & Dalronn (Utgarde Keep, heroic)
-- No boss flag and no boss list: the player is asked once, and the answer
-- is remembered for this server and instance.
local sk, da = MOCK.creatureGUID(24200, 1), MOCK.creatureGUID(24201, 1)
MOCK.units.target = { guid = sk, name = "Skarvald the Constructor", level = 82, class = "elite", combat = true }
H.enterCombat()
H.fire("PLAYER_TARGET_CHANGED")
advance(.2)
check(not TL:Active(), "an elite without a boss flag is not assumed to be a boss")
local prompt = A.bossPrompt
check(prompt and prompt:IsShown() and prompt.text:GetText():find("Skarvald"), "one small question: is it a boss?")
H.click(prompt.yes)
check(TL:Active() and TL:Encounter().npcs[24200] and not prompt:IsShown(), "answered yes: tracked at once")
check(A.TimelineKB:BossDecision(24200) == true, "remembered for this server and instance")
MOCK.units.focus = { guid = da, name = "Dalronn the Controller", level = 82, class = "elite", combat = true }
t0 = GetTime()
for i = 0, 5 do
    advance(i * 12 - (GetTime() - t0))
    cast(da, "Dalronn the Controller", 90101, "Shadow Bolt")
    hit(da, "Dalronn the Controller", 90101, "Shadow Bolt", P3, 1500)
    cast(da, "Dalronn the Controller", 43650, "Enfeeble")
    cast(sk, "Skarvald the Constructor", 48583, "Stone Strike")
    hit(sk, "Skarvald the Constructor", 48583, "Stone Strike", P1, 11000)
end
check(shown("Stone Strike") and shown("Stone Strike").danger, "Skarvald's one-shot hit is on the timeline, marked dangerous")
check(not TL:Encounter().npcs[24201] and not shown("Enfeeble"), "the unconfirmed second creature adds nothing")
A:SetBossDecision(24201, "Dalronn the Controller", true)
check(TL:Encounter().npcs[24201] and TL:Encounter().trusted[24201], "confirming the second boss adds it to the same fight")
cast(da, "Dalronn the Controller", 43650, "Enfeeble")
check(TL:Encounter().obs["24201:43650"], "its casts are recorded from then on")
check(not shown("Shadow Bolt"), "Dalronn's Shadow Bolts are not shown")
MOCK.units.target, MOCK.units.focus = nil, nil
H.leaveCombat()
advance(4)
-- next time: no question, tracked from the start
MOCK.units.target = { guid = sk, name = "Skarvald the Constructor", level = 82, class = "elite", combat = true }
H.enterCombat(); H.fire("PLAYER_TARGET_CHANGED"); advance(.2)
check(TL:Active(), "a confirmed boss is recognised on the next pull")
MOCK.units.target = nil; H.leaveCombat(); advance(4)
-- correcting a mistake: "Not a Boss"
A:SetBossDecision(24201, "Dalronn the Controller", false)
check(A.TimelineKB:BossDecision(24201) == false, "a mistaken confirmation can be undone")
MOCK.units.target = { guid = da, name = "Dalronn the Controller", level = -1, class = "worldboss", combat = true }
H.enterCombat(); H.fire("PLAYER_TARGET_CHANGED"); advance(.2)
check(not TL:Active(), "'Not a Boss' wins even over the game's boss flag")
MOCK.units.target = nil; H.leaveCombat(); advance(4)
check(#MOCK.blocked == 0, "no blocked actions")
