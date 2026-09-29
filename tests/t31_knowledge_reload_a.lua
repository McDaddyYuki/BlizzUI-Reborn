-- Knowledge learned with no boss mod survives a reload (part A: learn, log out).
dofile(TESTS_DIR .. "lib.lua")
local HOSTILE = 0xa48
MOCK.inInstance = true
MOCK.spells[93001] = { name = "Rupture" }
H.login()
local TL, K = A.Timeline, A.TimelineKB
check(DBM == nil and BigWigs == nil, "no boss mod installed")
local g = MOCK.creatureGUID(93000, 1)
for p = 1, 5 do
    MOCK.units.boss1 = { guid = g, name = "Standalone Boss", level = -1, class = "worldboss", combat = true }
    H.enterCombat(); H.fire("INSTANCE_ENCOUNTER_ENGAGE_UNIT")
    local t0 = GetTime()
    for _, c in ipairs({ 12, 30, 48, 66, 84 }) do
        H.tick(.1, math.floor((c - (GetTime() - t0)) * 10 + .5))
        H.fire("COMBAT_LOG_EVENT_UNFILTERED", GetTime(), "SPELL_CAST_SUCCESS", g, "Standalone Boss", HOSTILE, "", nil, 0, 93001, "Rupture", 1)
    end
    MOCK.units.boss1 = nil; H.leaveCombat(); H.tick(.1, 40)
end
local rec = K:Rec(K:Context(), 93000, 93001)
check(rec and rec.acc and near(rec.acc.cd, 18, .3) and rec.first and near(rec.first.t, 12, .6), "learned from observed pulls: every 18s, opens at 12s")
H.logout(TMP_DIR .. "sv_knowledge.lua")
