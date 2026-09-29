-- 0.7.0: independent learning rules, migration from 0.6.x, data-only sharing.
dofile(TESTS_DIR .. "lib.lua")
local HOSTILE = 0xa48
local TL, K
local function advance(sec) H.tick(0.1, math.floor(sec / 0.1 + .5)) end
local function log(event, guid, who, id, name, dest, x1, x2)
    H.fire("COMBAT_LOG_EVENT_UNFILTERED", GetTime(), event, guid, who, HOSTILE, dest or "", nil, 0, id, name, 1, x1, x2)
end
local function listed(n) for _, ev in ipairs(TL:DisplayList()) do if ev.name == n and ev.source ~= "cast" then return ev end end end
local cbs, mods = {}, {}
DBM = { RegisterCallback = function(_, ev, f) cbs[ev] = cbs[ev] or {}; table.insert(cbs[ev], f) end,
    GetModByName = function(_, id) return mods[id] end }
local function dbm(ev, ...) for _, f in ipairs(cbs[ev] or {}) do f(ev, ...) end end
MOCK.inInstance = true
for id, n in pairs({ [92001] = "Rend", [92002] = "Hex", [92003] = "Quake", [92004] = "Madness" }) do MOCK.spells[id] = { name = n } end
MOCK.spells[92002].castMs = 2000
-- a 0.6.1 account: learned records scored against the old built-in timings
BlizzUIRebornDB = { version = 3, timeline = { schema = 2, pull = 40, kb = { ["Frostmourne|raid|1"] = { [92900] = {
    [92901] = { n = "Old Nova", g = { { 20, 1, 1 }, { 20, 2, 1 } }, f = {}, h = {}, pe = { 3, 4 }, le = {}, useBaseline = true,
        acc = { kind = "repeat", cd = 20, lo = 19, hi = 21, n = 6, pull = 3, accepted = 5 }, cv = { { 1, 6, -1 }, { .5, 5, -1 } }, ae = { .4 },
        ph = { ["2"] = { cand = { kind = "repeat", cd = 12, lo = 11, hi = 13, n = 5, pull = 30 }, cv = { { .2, 4, -1 } }, ae = {} } } },
} } }, bosses = { [92900] = { confirmed = true, name = "Old Boss", spells = { [92901] = { n = "Old Nova", deadly = true } } } } },
    layouts = { Mine = { frames = { player = { point = "TOPLEFT", x = 10, y = -10 } } } } }
H.login()
TL, K = A.Timeline, A.TimelineKB
local db = BlizzUIRebornDB.timeline

-- ------------------------------------------------------------ migration
local rec = db.kb["Frostmourne|raid|1"][92900][92901]
check(db.schema == 3, "migrated to schema 3")
check(db.timelineBackup and db.timelineBackup.schema == 2 and db.timelineBackup.kb["Frostmourne|raid|1"][92900][92901].useBaseline, "old records backed up once before changing")
check(#rec.g == 2 and #rec.pe == 2 and rec.acc and rec.acc.cd == 20, "observed samples and the accepted model are kept")
check(#rec.cv == 0 and #rec.ph["2"].cv == 0, "validation scored against the removed baseline is cleared")
check(rec.audit and select(2, K:Repeat(rec)), "carried-over model is labelled as re-checking")
check(rec.useProvider and rec.useBaseline == nil, "'use built-in/boss mod timing' becomes 'always use boss mod timing'")
check(db.bosses[92900].confirmed and db.bosses[92900].legacy and db.bosses[92900].spells[92901].deadly, "boss confirmation and flags kept (marked legacy)")
check(BlizzUIRebornDB.layouts.Mine and BlizzUIRebornDB.layouts.Mine.frames.player.x == 10, "layouts untouched")
local backupRef = db.timelineBackup
K:Init(); K:Init()
check(db.schema == 3 and db.timelineBackup == backupRef and rec.acc and rec.acc.cd == 20 and #rec.g == 2, "migration is idempotent")

-- ------------------------------------------------------------ fights
local function fight(npc, name, seconds, script)
    local g = MOCK.creatureGUID(npc, 1)
    local u = { guid = g, name = name, level = -1, class = "worldboss", combat = true, hp = 1000, maxhp = 1000 }
    MOCK.units.boss1 = u
    H.enterCombat(); H.fire("INSTANCE_ENCOUNTER_ENGAGE_UNIT")
    local t0 = GetTime()
    for _ = 1, seconds * 10 do H.tick(.1); script(GetTime() - t0, g, u) end
    return TL:Encounter(), g, u
end
local function finish() MOCK.units.boss1 = nil; H.leaveCombat(); advance(4) end
local function at(t, w) return math.abs(t - w) < .05 end

-- provider timings are never samples: DBM says 30, the boss does 25
mods.P = { id = "P", creatureId = 92000, inCombat = true }
for p = 1, 3 do
    fight(92000, "Provider Boss", 90, function(t, g)
        if at(t, .5) then dbm("DBM_Pull", mods.P, .5) end
        for _, c in ipairs({ 10, 35, 60, 85 }) do
            if at(t, c) then log("SPELL_CAST_SUCCESS", g, "Provider Boss", 92001, "Rend"); dbm("DBM_TimerStart", "rend", "Rend", 30, nil, "cd", 92001, 0, "P", nil, nil, "Rend") end
        end
    end)
    finish()
end
rec = K:Rec(K:Context(), 92000, 92001)
local only25 = #rec.g > 0
for _, s in ipairs(rec.g) do if not near(s[1], 25, .3) then only25 = false end end
check(only25, "only observed intervals are stored (boss mod's 30s never is)")
check(#rec.pe >= 3 and near(rec.pe[1], 5, .3), "boss mod accuracy kept separately (compared, not learned)")

-- an interrupt: the recast gap is not a cooldown sample
local E = fight(92000, "Provider Boss", 60, function(t, g)
    if at(t, 5) or at(t, 20) or at(t, 35) then log("SPELL_CAST_START", g, "Provider Boss", 92002, "Hex") end
    if at(t, 7) or at(t, 37) then log("SPELL_CAST_SUCCESS", g, "Provider Boss", 92002, "Hex") end
    if at(t, 21) then H.fire("COMBAT_LOG_EVENT_UNFILTERED", GetTime(), "SPELL_INTERRUPT", "0x0000000000000001", "Tester", 0x511, g, "Provider Boss", HOSTILE, 1766, "Kick", 1, 92002, "Hex", 32) end
    if at(t, 23) then log("SPELL_CAST_START", g, "Provider Boss", 92002, "Hex") end
    if at(t, 25) then log("SPELL_CAST_SUCCESS", g, "Provider Boss", 92002, "Hex") end
end)
local o = E.obs["92000:92002"]
check(o and #o.occ == 3 and o.occ[2][6] and #K:PullGaps(o) == 1, "interrupted attempt: no occurrence, and the recast gap after it is not a sample")
finish()

-- a skipped cast (boss out of range / immune) hides as a double gap: not a sample
E = fight(92000, "Provider Boss", 100, function(t, g)
    for _, c in ipairs({ 10, 25, 40, 70, 85 }) do if at(t, c) then log("SPELL_CAST_SUCCESS", g, "Provider Boss", 92003, "Quake") end end
end)
local gaps = K:PullGaps(E.obs["92000:92003"], nil, true)
local has30 = false
for _, gp in ipairs(gaps) do if gp[1] > 25 then has30 = true end end
check(#gaps == 3 and not has30, "a 30s gap between 15s casts (one missed) is left out")
finish()

-- validation needs held-out casts from 2+ later pulls and 75%+ within tolerance
local vb = 92100
for p = 1, 3 do
    fight(vb, "Validate Boss", 70, function(t, g) for _, c in ipairs({ 10, 25, 40, 55, 70 }) do if at(t, c) then log("SPELL_CAST_SUCCESS", g, "Validate Boss", 92004, "Madness") end end end)
    finish()
end
rec = K:Rec(K:Context(), vb, 92004)
check(rec.cand and not rec.acc, "3 pulls: a candidate, not accepted")
fight(vb, "Validate Boss", 70, function(t, g) for _, c in ipairs({ 10, 25, 40, 55, 70 }) do if at(t, c) then log("SPELL_CAST_SUCCESS", g, "Validate Boss", 92004, "Madness") end end end)
finish()
check(rec.cand and not rec.acc and #rec.cv >= 3, "held-out casts from one pull are not enough")
fight(vb, "Validate Boss", 70, function(t, g) for _, c in ipairs({ 10, 25, 40, 55, 70 }) do if at(t, c) then log("SPELL_CAST_SUCCESS", g, "Validate Boss", 92004, "Madness") end end end)
finish()
check(rec.acc and near(rec.acc.cd, 15, .3), "accepted after held-out casts from a second pull (no boss mod involved)")
-- works with no provider installed at all, and predicts next time
E = fight(vb, "Validate Boss", 12, function(t, g) if at(t, 10) then log("SPELL_CAST_SUCCESS", g, "Validate Boss", 92004, "Madness") end end)
TL:Changed()
local nx = E.events["l" .. vb .. ":92004"]
check(nx and nx.prov == "learned" and near(nx.expires - GetTime(), 13, .5), "validated model predicts the next cast")
finish()

-- filler is remembered from observed casts
local fb = MOCK.creatureGUID(92200, 1)
fight(92200, "Filler Boss", 30, function(t, g) if t > 1 and math.floor(t * 10 + .5) % 50 == 0 then log("SPELL_CAST_SUCCESS", g, "Filler Boss", 92001, "Rend") end end)
finish()
check(K:Flags(92200, 92001) and K:Flags(92200, 92001).filler, "a spell cast every few seconds is remembered as filler")

-- ------------------------------------------------------------ health ETA edge cases
T.learned(92300, 92003, "Quake", { thr = 30 })
local u
E, _, u = fight(92300, "Slow Boss", 1, function() end)
local function run(sec, f) for _ = 1, sec * 10 do H.tick(.1); f() end end
u.hp = 900
run(8, function() u.hp = u.hp - .02 end) -- 0.02%/s: ~3000s away
local q = listed("Quake")
check(q and q.threshold and q.state == "waiting" and q.remaining >= 0, "a projection far out is 'waiting', never a huge countdown")
u.maxhp = 2000; u.hp = 1200
run(3, function() end)
check(listed("Quake").state ~= "eta" or listed("Quake").remaining >= 0, "max health change: fresh history, no negative time")
run(6, function() u.hp = u.hp - 2 end) -- 1%/s from 60%
q = listed("Quake")
check(q.state == "eta" and near(q.remaining, 24, 6) and q.lo - GetTime() <= 24.5, "ETA from this boss's own health loss")
u.hp = u.hp + 200 -- healed
run(4, function() end)
check(listed("Quake").state == "waiting", "healing / no loss: waiting")
finish()

-- ------------------------------------------------------------ sharing
local code = K:Export(vb)
check(code:sub(1, 5) == "BRK3:" and code:find("Madness", 1, true), "export: validated models")
check(not code:find("s2:pe ", 1, true) and not code:find("s2:cv ", 1, true) and not code:find("s1:g ", 1, true), "export: no raw samples or boss mod data")
for _, bad in ipairs({ "", "hello", "BRK3:", "BRK3:{", "BRK3:{ s7:bosses { -5 { s3:ctx { } } } }", "BRK3:" .. string.rep("{ ", 20),
    "BRK3:{ s7:bosses { 5 { s3:ctx { s3:a|b { 1 { s3:acc { s4:kind s6:repeat s2:cd 99999 } } } } } } }",
    "BRK3:{ s7:bosses { 5 { s3:ctx { s3:a|b { 1 { s3:acc { s4:kind s8:function } } } } } } }", "return os.exit()" }) do
    local before = 0
    for _ in pairs(db.kb) do before = before + 1 end
    local n = K:Import(bad)
    local after = 0
    for _ in pairs(db.kb) do after = after + 1 end
    check((not n or n == 0) and after == before, "malformed import rejected: " .. bad:sub(1, 24))
end
K:ForgetBoss(vb)
check(K:Import(code) == 1 and K:Rec(K:Context(), vb, 92004).cand.imported and not K:Rec(K:Context(), vb, 92004).acc, "imported: a candidate that must validate here")
-- 0.6 strings still import
local v2 = code:gsub("^BRK3:", "BRK2:")
check(K:Import(v2) ~= nil, "0.6 share strings still import")
-- ------------------------------------------------------------ review regressions
-- "Not a boss" wins over DBM's module creatures, mid-fight too
mods.Council = { id = "Council", creatureId = { 94100, 94101 }, inCombat = true }
MOCK.spells[94001] = { name = "Zap" }
K:SetBossDecision(94101, false, "Not Boss")
H.enterCombat()
dbm("DBM_Pull", mods.Council, 0)
local E2 = TL:Encounter()
check(E2 and E2.npcs[94100] and not E2.npcs[94101], "a DBM module's creature the player rejected is not added")
log("SPELL_CAST_SUCCESS", MOCK.creatureGUID(94101, 1), "Not Boss", 94001, "Zap")
check(not E2.npcs[94101] and not E2.obs["94101:94001"], "...nor when it casts")
log("SPELL_CAST_START", MOCK.creatureGUID(94100, 1), "Boss", 94001, "Zap")
A:SetBossDecision(94100, "Boss", false)
check(not TL:Active(), "rejecting the last boss ends the fight, even one a boss mod owns")
advance(5)
check(not TL:Active() and #A.errorLog == 0, "a pending cast of the rejected creature does not revive anything")
H.leaveCombat(); advance(4)
check(not K:Rec(K:Context(), 94100, 94001), "nothing learned from a rejected creature")
-- Forget Learned Timings keeps boss decisions, hides and pins
BlizzUIRebornDB.timeline.bosses[92000].hide = { Rend = true }
A:ForgetLearnedTimings()
check(K:BossDecision(94101) == false and K:BossDecision(94100) == false and BlizzUIRebornDB.timeline.bosses[92000].hide.Rend, "forgetting timings keeps boss decisions and hidden abilities")
check(not next(BlizzUIRebornDB.timeline.kb), "...and forgets the timings")
-- the question is not asked about adds during a fight
local asked
local orig = A.TimelineBossPrompt
A.TimelineBossPrompt = function(_, npc) asked = npc end
MOCK.units.boss1 = { guid = MOCK.creatureGUID(94200, 1), name = "Real Boss", level = -1, class = "worldboss", combat = true }
MOCK.units.target = { guid = MOCK.creatureGUID(94201, 1), name = "Elite Add", level = 82, class = "elite", combat = true }
H.enterCombat(); H.fire("INSTANCE_ENCOUNTER_ENGAGE_UNIT"); H.fire("PLAYER_TARGET_CHANGED")
check(TL:Active() and not asked, "no boss question about an add during a boss fight")
MOCK.units.boss1, MOCK.units.target = nil, nil; H.leaveCombat(); advance(4)
A.TimelineBossPrompt = orig
-- migrated audit models: not exported, and re-checked on fresh casts only
local mig = { acc = { kind = "repeat", cd = 20, lo = 19, hi = 21, n = 6 }, audit = true, cv = {}, ae = { 0, 0, 0, 0 }, g = {}, f = {}, h = {}, n = "Carried" }
BlizzUIRebornDB.timeline.kb["Frostmourne|raid|1"] = { [94300] = { [94301] = mig } }
local ex = K:Export(94300)
check(not ex:find("Carried", 1, true), "a carried-over model being re-checked is not exported")
local oldDb = { schema = 2, kb = { x = { [1] = { [2] = { acc = { kind = "repeat", cd = 9, lo = 8, hi = 10 }, ae = { 0, 0, 0, 0 }, cv = { { 1, 1, -1 } }, g = {}, f = {}, h = {} } } } }, bosses = {} }
K:MigrateV3(oldDb)
check(#oldDb.kb.x[1][2].ae == 0 and oldDb.kb.x[1][2].audit, "migration clears old accuracy history so fresh casts decide")
-- BigWigs bars about a player are not boss timers
check(TL:NamesGroupMember("Infection: " .. (UnitName("player") or "")), "a bar naming a group member is recognised")
check(#MOCK.errors == 0 and #A.errorLog == 0, "no Lua errors")
