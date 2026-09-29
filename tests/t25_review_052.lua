-- Replays of the six 0.5.2 review findings.
dofile(TESTS_DIR .. "lib.lua")
local HOSTILE = 0xa48
local TL, K
local function advance(sec) H.tick(0.1, math.floor(sec / 0.1 + .5)) end
local function log(event, guid, who, id, name, dest, x1, x2)
    H.fire("COMBAT_LOG_EVENT_UNFILTERED", GetTime(), event, guid, who, HOSTILE, dest or "", nil, 0, id, name, 1, x1, x2)
end
local function named(n, src)
    local E = TL:Encounter()
    if not E then return nil end
    for _, ev in pairs(E.events) do if ev.name == n and (not src or ev.source == src) then return ev end end
end
local function listed(n)
    for _, ev in ipairs(TL:DisplayList()) do if ev.name == n and ev.source ~= "cast" then return ev end end
end
local function engage(npc, spawn, name)
    local g = MOCK.creatureGUID(npc, spawn or 1)
    MOCK.units.boss1 = { guid = g, name = name, level = -1, class = "worldboss", combat = true }
    H.enterCombat()
    H.fire("INSTANCE_ENCOUNTER_ENGAGE_UNIT")
    return g
end
local function done()
    MOCK.units.boss1 = nil
    H.leaveCombat()
    advance(4)
end
-- fake DBM with modules
local cbs, mods = {}, {}
DBM = { RegisterCallback = function(_, ev, f) cbs[ev] = cbs[ev] or {}; table.insert(cbs[ev], f) end,
    GetModByName = function(_, id) return mods[id] end }
local function dbm(ev, ...) for _, f in ipairs(cbs[ev] or {}) do f(ev, ...) end end
MOCK.inInstance = true
for id, n in pairs({ [34098] = "ClearAllDebuffs", [69057] = "Bone Spike Graveyard", [69076] = "Bone Storm", [26662] = "Berserk",
    [63631] = "Shock Blast", [90201] = "Doom Bolt" }) do MOCK.spells[id] = { name = n } end
MOCK.spells[69057].castMs, MOCK.spells[69076].castMs, MOCK.spells[90201].castMs = 3000, 3000, 4000
H.login()
TL, K = A.Timeline, A.TimelineKB

-- knowledge this account learned earlier (fixtures; nothing ships built in)
T.learned(33432, 63631, "Shock Blast", { cd = 35, first = 30, flag = "deadly" })
T.learned(36612, 69057, "Bone Spike Graveyard", { cd = 18, first = 15, flag = "aoe" })
T.learned(36612, 69076, "Bone Storm", { cd = 90, first = 45, flag = "aoe" })

-- ------------------------------------------------------------ 1. no conditional data, phase changes
check(A.TimelineData == nil, "no bundled encounter data")
local g = engage(33432, 1, "Mimiron")
log("SPELL_CAST_SUCCESS", g, "Mimiron", 34098, "ClearAllDebuffs")
local n = 0
for _, ev in pairs(TL:Encounter().events) do if ev.name:find("Phase") then n = n + 1 end end
check(n == 0, "Mimiron: no invented phase predictions")
-- a phase change (from DBM) cancels obsolete predictions
mods.Mimiron = { id = "Mimiron", creatureId = 33432, inCombat = true }
dbm("DBM_TimerStart", "t1", "x", 30, nil, "cd", 63631, 0, "Mimiron", nil, nil, "Shock Blast")
log("SPELL_CAST_START", g, "Mimiron", 63631, "Shock Blast") -- makes a local estimate too
local before = 0
for _, ev in pairs(TL:Encounter().events) do if ev.source == "predict" and not ev.enrage then before = before + 1 end end
dbm("DBM_SetStage", mods.Mimiron, "Mimiron", 2)
local after = 0
for _, ev in pairs(TL:Encounter().events) do if ev.source == "predict" and not ev.enrage then after = after + 1 end end
check(before > 0 and after == 0 and TL:Encounter().phase == 2, "phase change cancels this addon's obsolete predictions")
done()

-- ------------------------------------------------------------ 2. DBM cancel does not revive
mods.LordMarrowgar = { id = "LordMarrowgar", creatureId = 36612, inCombat = true }
local warned = {}
hooksecurefunc(A, "TimelineWarn", function(_, sev, name) warned[#warned + 1] = name end)
g = engage(36612, 2, "Lord Marrowgar")
dbm("DBM_Pull", mods.LordMarrowgar, 0)
check(listed("Bone Spike Graveyard") and listed("Bone Spike Graveyard").source == "predict", "learned prediction before DBM speaks")
dbm("DBM_TimerStart", "spike", "Next Bone Spike", 15, nil, "cd", 69057, 0, "LordMarrowgar", nil, nil, "Bone Spike Graveyard")
check(listed("Bone Spike Graveyard").source == "dbm", "DBM supersedes it")
dbm("DBM_TimerStop", "spike") -- phase transition cancels it
check(not listed("Bone Spike Graveyard"), "cancelled DBM timer: the old learned countdown does not return")
advance(14)
local w = false
for _, x in ipairs(warned) do if x == "Bone Spike Graveyard" then w = true end end
check(not w, "nor its warning")

-- ------------------------------------------------------------ 3. ownership: trash casts and trash modules
local stormBefore = named("Bone Storm", "predict")
local expBefore = stormBefore and stormBefore.expires
local trash = MOCK.creatureGUID(37007, 5)
log("SPELL_CAST_START", trash, "Deathbound Ward", 69076, "Bone Storm")
log("SPELL_CAST_SUCCESS", trash, "Deathbound Ward", 69076, "Bone Storm")
local stormAfter = named("Bone Storm", "predict")
check(stormAfter and stormAfter.expires == expBefore, "a trash mob casting the same spell does not move the boss prediction")
check(not TL:Encounter().npcs[37007], "trash never joins the encounter")
mods.IcecrownTrash = { id = "IcecrownTrash", isTrashMod = true, inCombat = true }
dbm("DBM_TimerStart", "trashtimer", "Trash thing", 20, nil, "cd", 12345, 0, "IcecrownTrash", nil, nil, "Trash Thing")
check(not listed("Trash Thing"), "a trash module's timer is not shown during a boss fight")
mods.Other = { id = "Other", creatureId = 36855, inCombat = true }
dbm("DBM_TimerStart", "other", "Other boss", 20, nil, "cd", 12346, 0, "Other", nil, nil, "Other Thing")
check(not listed("Other Thing"), "another boss module's timer is not shown")
dbm("DBM_TimerStart", "pull", "Pull in", 10, nil, "cd", nil, 0, "PullTimer", nil, nil, "Pull")
check(not listed("Pull in") and not listed("Pull"), "a custom pull timer is not a boss ability")
dbm("DBM_Kill", mods.Other)
check(TL:Active(), "an unrelated module's kill does not end our fight")
dbm("DBM_Kill", mods.LordMarrowgar)
check(not TL:Active(), "our module's kill does")
done()

-- ------------------------------------------------------------ 4. interrupt removes an off-target cast
local cg = engage(90200, 1, "Custom Caster")
MOCK.units.boss1 = nil -- not exposed through any unit token
log("SPELL_CAST_START", cg, "Custom Caster", 90201, "Doom Bolt")
local cast
for _, ev in pairs(TL:Encounter().events) do if ev.source == "cast" then cast = ev end end
check(cast and cast.estimate, "combat-log cast shown, marked as an estimate")
advance(1)
H.fire("COMBAT_LOG_EVENT_UNFILTERED", GetTime(), "SPELL_INTERRUPT", "0x0000000000000001", "Tester", 0x511, cg, "Custom Caster", HOSTILE, 1766, "Kick", 1, 90201, "Doom Bolt", 32)
cast = nil
for _, ev in pairs(TL:Encounter().events) do if ev.source == "cast" then cast = ev end end
check(not cast, "interrupt removes it at once")
advance(5)
check(not TL:Encounter().obs["90200:90201"], "an interrupted attempt is not learned as a cast")
done()

-- ------------------------------------------------------------ 5. learning is per difficulty
local bg = MOCK.creatureGUID(90300, 1)
local function learnPulls(diff, gap, pulls)
    MOCK.difficulty = diff
    for _ = 1, pulls do
        MOCK.units.boss1 = { guid = bg, name = "Custom Boss", level = -1, class = "worldboss", combat = true }
        H.enterCombat(); H.fire("INSTANCE_ENCOUNTER_ENGAGE_UNIT")
        for i = 1, 5 do advance(gap); log("SPELL_CAST_SUCCESS", bg, "Custom Boss", 90201, "Doom Bolt") end
        done()
    end
end
learnPulls(1, 10, 5)
local r1 = K:Rec(K:Context(), 90300, 90201)
check(r1 and r1.acc and near(r1.acc.cd, 10, .3), "difficulty 1 learns 10 seconds")
MOCK.difficulty = 4
check(not K:Rec(K:Context(), 90300, 90201), "difficulty 4 has no knowledge of it")
learnPulls(4, 30, 1)
local r4 = K:Rec(K:Context(), 90300, 90201)
check(r4 and not r4.acc and near(K:Rec("Frostmourne|raid|1", 90300, 90201).acc.cd, 10, .3), "difficulty 4 samples stay separate")
MOCK.difficulty = 1

-- ------------------------------------------------------------ 6. followers follow the current default
A:CreateLayout("One", false)
local main = BlizzUIRebornCharDB
BlizzUIRebornCharDB = {}
A:InitDB()
check(A.char.active.name == "One" and A.char.layoutMode == "follow", "untouched alt inherits One")
local alt = BlizzUIRebornCharDB
BlizzUIRebornCharDB = main; A:InitDB()
A:CreateLayout("Two", false)
A:SetDefaultLayout("Two")
BlizzUIRebornCharDB = alt; A:InitDB()
check(A.char.active.name == "Two", "…and follows the change to Two")
local chooser = { active = { scope = "account", name = "One" }, layoutMode = "chosen" }
BlizzUIRebornCharDB = chooser; A:InitDB()
check(A.char.active.name == "One", "an alt that chose One stays on One")
local old = { active = { scope = "account", name = "One" } } -- pre-0.5.2 manual pick
BlizzUIRebornCharDB = old; A:InitDB()
check(A.char.active.name == "One" and A.char.layoutMode == "chosen", "pre-upgrade manual account pick is preserved")
BlizzUIRebornCharDB = main; A:InitDB()
check(#MOCK.errors == 0, "no Lua errors")
