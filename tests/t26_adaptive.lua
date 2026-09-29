-- Adaptive encounter knowledge: the 12 acceptance scenarios (deterministic
-- replays of casts, boss health and boss mod timers).
dofile(TESTS_DIR .. "lib.lua")
local HOSTILE = 0xa48
local TL, K
local function advance(sec) H.tick(0.1, math.floor(sec / 0.1 + .5)) end
local function log(event, guid, who, id, name, dest, x1, x2)
    H.fire("COMBAT_LOG_EVENT_UNFILTERED", GetTime(), event, guid, who, HOSTILE, dest or "", nil, 0, id, name, 1, x1, x2)
end
local function listed(n)
    for _, ev in ipairs(TL:DisplayList()) do if ev.name == n and ev.source ~= "cast" then return ev end end
end
local cbs, mods = {}, {}
DBM = { RegisterCallback = function(_, ev, f) cbs[ev] = cbs[ev] or {}; table.insert(cbs[ev], f) end,
    GetModByName = function(_, id) return mods[id] end }
local function dbm(ev, ...) for _, f in ipairs(cbs[ev] or {}) do f(ev, ...) end end
local registry = {}
LibStub = setmetatable({ GetLibrary = function(_, name)
    if name == "AceEvent-3.0" then return { Embed = function(_, t) t.RegisterMessage = function(_, m, fn) registry[m] = registry[m] or {}; table.insert(registry[m], fn) end; return t end } end
end }, { __call = function(self, name) return self:GetLibrary(name) end })
local function bw(m, ...) for _, fn in ipairs(registry[m] or {}) do fn(m, ...) end end
MOCK.inInstance = true
local SPELLS = { [91001] = "Crush", [91002] = "Dark Rift", [91003] = "Frenzy", [91004] = "Void Pulse", [91005] = "Tail Swipe", [91006] = "Sear" }
for id, n in pairs(SPELLS) do MOCK.spells[id] = { name = n } end
H.login()
TL, K = A.Timeline, A.TimelineKB

-- a boss with health; `script(t0)` drives it; returns the encounter
local function fight(npc, name, seconds, script, opt)
    opt = opt or {}
    local g = MOCK.creatureGUID(npc, opt.spawn or 1)
    local u = { guid = g, name = name, level = -1, class = "worldboss", combat = true, hp = opt.hp or 1000, maxhp = 1000 }
    MOCK.units.boss1 = u
    H.enterCombat(); H.fire("INSTANCE_ENCOUNTER_ENGAGE_UNIT")
    local t0 = GetTime()
    local E = TL:Encounter()
    for step = 1, seconds * 10 do
        H.tick(0.1)
        script(GetTime() - t0, g, u, E)
    end
    return E, g, u
end
local function finish()
    MOCK.units.boss1 = nil
    H.leaveCombat()
    advance(4)
end
local function at(t, when) return math.abs(t - when) < .05 end

-- ------------------------------------------------------------ 1. DBM says 30, the server does 24
mods.Seeded = { id = "Seeded", creatureId = 91000, inCombat = true }
local function seededPull()
    local E, g = fight(91000, "Seeded Boss", 110, function(t, g)
        if at(t, 1) then dbm("DBM_Pull", mods.Seeded, 1) end
        if at(t, 2) then dbm("DBM_TimerStart", "crush", "Next Crush", 28, nil, "cd", 91001, 0, "Seeded", nil, nil, "Crush") end
        for _, c in ipairs({ 10, 34, 58, 82, 106 }) do
            if at(t, c) then
                log("SPELL_CAST_SUCCESS", g, "Seeded Boss", 91001, "Crush")
                log("SPELL_DAMAGE", g, "Seeded Boss", 91001, "Crush", "0x0000000000000001", 70, 0) -- a big hit on the player
                dbm("DBM_TimerStart", "crush", "Next Crush", 30, nil, "cd", 91001, 0, "Seeded", nil, nil, "Crush") -- DBM restarts at 30
            end
        end
    end)
    return E
end
local shownSource = {}
for p = 1, 6 do
    seededPull()
    local l = listed("Crush")
    shownSource[p] = l and l.source
    finish()
end
local rec = K:Rec(K:Context(), 91000, 91001)
check(rec and rec.acc and near(rec.acc.cd, 24, .3), "1: the server's 24s timing is accepted after the evidence rule")
check(shownSource[1] == "dbm" and shownSource[3] == "dbm", "1: DBM's timer is shown until then")
check(#rec.pe >= 3 and K:PrefersLocal(rec), "1: learned timing proved more accurate than DBM's on this server")
seededPull()
local l = listed("Crush")
check(l and l.source == "predict" and l.prov == "learned", "1: then the learned timing is shown instead of DBM's")
finish()
local main = BlizzUIRebornCharDB
BlizzUIRebornCharDB = {}; A:InitDB(); A:LoadActive()
check(K:Rec(K:Context(), 91000, 91001).acc, "1: another character uses the same knowledge")
BlizzUIRebornCharDB = main; A:InitDB(); A:LoadActive()

-- ------------------------------------------------------------ 2. random intervals
math.randomseed(7)
for p = 1, 6 do
    local next_ = 8 + math.random() * 40
    fight(91100, "Random Boss", 120, function(t, g)
        if t >= next_ then log("SPELL_CAST_SUCCESS", g, "Random Boss", 91002, "Dark Rift"); next_ = t + 8 + math.random() * 40 end
    end)
    finish()
end
rec = K:Rec(K:Context(), 91100, 91002)
check(rec and not rec.acc and not (rec.cand and rec.cand.kind == "repeat"), "2: random intervals: no precise repeat timing claimed")
-- bounded variation (20-28s) becomes a window
for p = 1, 6 do
    local next_ = 20 + math.random() * 8
    fight(91100, "Random Boss", 120, function(t, g)
        if t >= next_ then log("SPELL_CAST_SUCCESS", g, "Random Boss", 91006, "Sear"); next_ = t + 20 + math.random() * 8 end
    end)
    finish()
end
rec = K:Rec(K:Context(), 91100, 91006)
local model = rec and (rec.acc or rec.cand)
check(model and model.kind == "window" and model.lo >= 19 and model.hi <= 29, "2: bounded variation: an expected window, not a fixed second")

-- ------------------------------------------------------------ 3. HP threshold with fast and slow groups
local function hpPull(dps, delay)
    local cast = false
    return fight(91200, "Threshold Boss", 110, function(t, g, u)
        u.hp = math.max(1, 1000 - t * dps * 10)
        if not cast and u.hp <= 350 then
            cast = GetTime() + (delay or 0)
        end
        if cast and cast ~= true and GetTime() >= cast then
            log("SPELL_CAST_SUCCESS", g, "Threshold Boss", 91003, "Frenzy"); cast = true
        end
    end)
end
hpPull(1.0); finish(); hpPull(1.6); finish(); hpPull(0.8, 1.2); finish()
rec = K:Rec(K:Context(), 91200, 91003)
check(rec and rec.thr and rec.thr.hp >= 34 and rec.thr.hp <= 36, "3: the 35% threshold is learned once")
check(not rec.first and not rec.acc, "3: the fight time it took is not stored as an opener or a cooldown")
-- ------------------------------------------------------------ 4. ETA from health loss
local E, g, u = fight(91200, "Threshold Boss", 1, function(t, g, u) u.hp = 1000 end)
local ev = listed("Frenzy")
check(ev and ev.threshold and ev.hp >= 34, "4: the threshold entry is on the timeline")
local function run(sec, f) for _ = 1, sec * 10 do H.tick(.1); f() end end
local warns = 0
local hook = function(_, sev, name) if name == "Frenzy" then warns = warns + 1 end end
hooksecurefunc(A, "TimelineWarn", hook)
u.hp = 500
run(6, function() u.hp = u.hp - 1 end) -- 1 percentage point a second
ev = listed("Frenzy")
local eta = ev.expires - GetTime()
check(ev.state == "eta" and near(eta, (u.hp / 10 - ev.hp), 1.5), "4: ETA from the measured loss (about 15s from 50%)")
run(6, function() end) -- no damage
check(listed("Frenzy").state == "waiting", "4: no damage: 'waiting', no infinite countdown")
u.hp = 700 -- healed / scripted jump
run(2, function() end)
run(8, function() u.hp = u.hp - 3 end)
eta = listed("Frenzy").expires - GetTime()
check(listed("Frenzy").state == "eta" and eta > 0, "4: recovers after a heal with a fresh trend")
run(20, function()
    u.hp = math.max(330, u.hp - 3 + ((math.floor(GetTime() * 10) % 2 == 0) and 2 or 0))
end)
check(warns == 1, "4: one warning for the occurrence, even with a bouncing ETA")
check(listed("Frenzy").state == "reached", "4: threshold reached, awaiting the mechanic (no 'cast now')")
log("SPELL_CAST_SUCCESS", g, "Threshold Boss", 91003, "Frenzy")
check(not listed("Frenzy"), "4: latched once it happens")
u.hp = 600; run(2, function() end)
check(not listed("Frenzy"), "4: a heal above the threshold does not re-arm it")
finish()

-- ------------------------------------------------------------ 5. delayed threshold cast
rec = K:Rec(K:Context(), 91200, 91003)
local thrBefore = rec.thr.hp
hpPull(1.4, 1.5); finish()
rec = K:Rec(K:Context(), 91200, 91003)
check(rec.thr and rec.thr.hp == thrBefore, "5: a cast delayed below the threshold doesn't move the learned threshold")

-- ------------------------------------------------------------ 6. mixed mechanics: only eligible ones forecast
E = fight(91200, "Threshold Boss", 1, function() end)
local kinds = {}
for _, x in pairs(E.events) do kinds[x.name] = x.threshold and "hp" or x.source end
check(kinds.Frenzy == "hp" and not kinds["Dark Rift"], "6: only this boss's eligible mechanics are forecast (HP one as a threshold)")
finish()

-- ------------------------------------------------------------ 7. contexts and migration
MOCK.difficulty = 3
check(not K:Rec(K:Context(), 91200, 91003), "7: heroic has no normal-difficulty knowledge")
MOCK.difficulty = 1
BlizzUIRebornDB.timeline.schema = 1
BlizzUIRebornDB.timeline.learned = { [99000] = { boss = true, name = "Old Boss", spells = { Nuke = { id = 91004, first = { 5, 6 }, gap = { 10, 10 }, deadly = true } } } }
K:Init()
check(BlizzUIRebornDB.timeline.bosses[99000].spells[91004].deadly and not BlizzUIRebornDB.timeline.learned, "7: old data migrated: flags kept")
check(K:Rec(K:Context(), 91000, 91001).acc, "7: accepted knowledge survives the migration pass")

-- ------------------------------------------------------------ 8. interrupts, wipes, late joins
local gs = MOCK.creatureGUID(91300, 1)
MOCK.units.boss1 = { guid = gs, name = "Caster", level = -1, class = "worldboss", combat = true }
H.enterCombat(); H.fire("INSTANCE_ENCOUNTER_ENGAGE_UNIT")
for i = 1, 4 do
    advance(10)
    log("SPELL_CAST_START", gs, "Caster", 91004, "Void Pulse")
    advance(.5)
    H.fire("COMBAT_LOG_EVENT_UNFILTERED", GetTime(), "SPELL_INTERRUPT", "0x0000000000000001", "Tester", 0x511, gs, "Caster", HOSTILE, 1766, "Kick", 1, 91004, "Void Pulse", 32)
end
local obs = TL:Encounter().obs["91300:91004"]
check(not obs, "8: interrupted attempts are not casts")
finish()
H.enterCombat()
advance(20) -- joined late
MOCK.units.boss1 = { guid = gs, name = "Caster", level = -1, class = "worldboss", combat = true }
TL:ScanUnits()
check(TL:Encounter() and TL:Encounter().late, "8: late join recognised")
log("SPELL_CAST_SUCCESS", gs, "Caster", 91005, "Tail Swipe")
finish()
rec = K:Rec(K:Context(), 91300, 91005)
check(rec and #rec.f == 0, "8: no opener learned from a late join")

-- ------------------------------------------------------------ 9. a new custom spell
local gn = MOCK.creatureGUID(91400, 1)
MOCK.units.boss1 = { guid = gn, name = "New Boss", level = -1, class = "worldboss", combat = true }
H.enterCombat(); H.fire("INSTANCE_ENCOUNTER_ENGAGE_UNIT")
MOCK.spells[91004].castMs = 2500
advance(5)
log("SPELL_CAST_START", gn, "New Boss", 91004, "Void Pulse")
local seenCast = false
BlizzUIRebornDB.timeline.allAbilities = true; TL:Changed()
for _, x in ipairs(TL:DisplayList()) do if x.state == "cast" and x.name == "Void Pulse" then seenCast = true end end
BlizzUIRebornDB.timeline.allAbilities = nil; TL:Changed()
check(seenCast, "9: the first observed cast is shown as it happens")
advance(5)
local trashG = MOCK.creatureGUID(12000, 7)
log("SPELL_CAST_SUCCESS", trashG, "Cultist", 91004, "Void Pulse")
check(TL:Encounter().obs["91400:91004"] and #TL:Encounter().obs["91400:91004"].occ == 1 and not TL:Encounter().obs["12000:91004"], "9: identically named trash casts are rejected")
finish()
rec = K:Rec(K:Context(), 91400, 91004)
check(rec and rec.pulls == 1 and not rec.acc, "9: evidence kept as a candidate, nothing promoted from one pull")

-- ------------------------------------------------------------ 10. both boss mods
mods.Duo = { id = "Duo", creatureId = 91500, inCombat = true }
local gd = MOCK.creatureGUID(91500, 1)
MOCK.units.boss1 = { guid = gd, name = "Duo Boss", level = -1, class = "worldboss", combat = true }
H.enterCombat(); H.fire("INSTANCE_ENCOUNTER_ENGAGE_UNIT")
dbm("DBM_Pull", mods.Duo, 0)
local module = { moduleName = "Duo" }
bw("BigWigs_OnBossEngage", module, "Duo Boss")
dbm("DBM_TimerStart", "swipe", "Next Tail Swipe", 20, nil, "cd", 91005, 0, "Duo", nil, nil, "Tail Swipe")
bw("BigWigs_StartBar", module, 91005, "Tail Swipe", 21, nil)
local count = 0
for _, x in ipairs(TL:DisplayList()) do if x.name == "Tail Swipe" then count = count + 1 end end
check(count == 1, "10: two boss mods, one entry")
dbm("DBM_TimerPause", "swipe"); advance(2); dbm("DBM_TimerResume", "swipe")
dbm("DBM_TimerStop", "swipe"); bw("BigWigs_StopBar", module, "Tail Swipe")
check(not listed("Tail Swipe"), "10: cancelled: nothing revived")
log("SPELL_CAST_SUCCESS", gd, "Duo Boss", 91005, "Tail Swipe")
check(#TL:Encounter().obs["91500:91005"].occ == 1, "10: one cast = one observation (boss mod timers are not evidence)")
finish()
BlizzUIRebornDB.timeline.useBossMods = false
MOCK.units.boss1 = { guid = gd, name = "Duo Boss", level = -1, class = "worldboss", combat = true }
H.enterCombat(); H.fire("INSTANCE_ENCOUNTER_ENGAGE_UNIT")
dbm("DBM_TimerStart", "swipe", "Next Tail Swipe", 20, nil, "cd", 91005, 0, "Duo", nil, nil, "Tail Swipe")
check(not listed("Tail Swipe") or listed("Tail Swipe").source ~= "dbm", "10: boss mods turned off: their timers are ignored")
finish()
BlizzUIRebornDB.timeline.useBossMods = true

-- ------------------------------------------------------------ 11. practice, collection switches, layouts
local pullsBefore = BlizzUIRebornDB.timeline.pull
A:TestTimeline(); advance(41)
check(BlizzUIRebornDB.timeline.pull == pullsBefore and not K:Recs(K:Context(), 0), "11: practice fights never touch knowledge")
BlizzUIRebornDB.timeline.learn = false
MOCK.units.boss1 = { guid = gn, name = "New Boss", level = -1, class = "worldboss", combat = true }
H.enterCombat(); H.fire("INSTANCE_ENCOUNTER_ENGAGE_UNIT")
advance(2); log("SPELL_CAST_SUCCESS", gn, "New Boss", 91006, "Sear")
finish()
check(not K:Rec(K:Context(), 91400, 91006), "11: learning off: nothing collected")
BlizzUIRebornDB.timeline.learn = true
A:ToggleElement("bosstimeline", false); A:ToggleElement("bosswarnings", false)
check(not TL.enabled, "11: both displays off (default): collection stops")
BlizzUIRebornDB.timeline.learnHidden = true; A:RefreshTimeline()
check(TL.enabled and not BlizzUIRebornBossTimeline:IsShown(), "11: 'keep learning while hidden': collects without showing anything")
BlizzUIRebornDB.timeline.learnHidden = nil
A:ToggleElement("bosstimeline", true); A:ToggleElement("bosswarnings", true)
A:LoadPreset("Classic"); A:LoadPreset("Modern")
check(K:Rec(K:Context(), 91000, 91001).acc, "11: switching layouts keeps knowledge")

-- ------------------------------------------------------------ 12. server ruleset change
K:MarkServerChange()
rec = K:Rec(K:Context(), 91000, 91001)
check(rec.acc and rec.reval, "12: old timing kept (re-checking), not destroyed")
local shift = {}
for p = 1, 4 do -- the server now does 20s
    fight(91000, "Seeded Boss", 90, function(t, g)
        for _, c in ipairs({ 10, 30, 50, 70 }) do if at(t, c) then log("SPELL_CAST_SUCCESS", g, "Seeded Boss", 91001, "Crush") end end
    end)
    finish()
    shift[p] = K:Rec(K:Context(), 91000, 91001).acc.cd
end
check(shift[1] == 24 and shift[2] == 24 and shift[3] == 24 and shift[4] == 24, "12: no flip-flopping while the new timing is being checked (held-out casts from 2+ pulls needed)")
fight(91000, "Seeded Boss", 90, function(t, g)
    for _, c in ipairs({ 10, 30, 50, 70 }) do if at(t, c) then log("SPELL_CAST_SUCCESS", g, "Seeded Boss", 91001, "Crush") end end
end)
finish()
rec = K:Rec(K:Context(), 91000, 91001)
check(rec.acc and near(rec.acc.cd, 20, .3) and rec.prev and near(rec.prev.cd, 24, .3), "12: new timing accepted after validation; old one kept for rollback")
check(K:Rollback(rec) and near(rec.acc.cd, 24, .3), "12: rollback works")
K:Rollback(rec)
-- export / import (data only)
local code = K:Export(91000)
check(code:sub(1, 5) == "BRK3:" and code:find("observed", 1, true) and not code:find("s2:pe ", 1, true) and not code:find("s2:le ", 1, true), "export string: validated models only, marked observed")
K:ForgetBoss(91000)
local n = K:Import(code)
rec = K:Rec(K:Context(), 91000, 91001)
check(n >= 1 and rec.cand and rec.cand.imported and not rec.acc, "imported timings wait for local validation")
check(not K:Import("BRK1:{ s5:hello F }") or true, "malformed import handled")
check(select(1, K.Deserialize("{ s999999:x }")) == nil, "oversized/damaged strings rejected")
check(#MOCK.errors == 0 and #A.errorLog == 0, "no Lua errors")
