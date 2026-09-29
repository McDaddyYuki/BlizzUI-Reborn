-- Part B: after the reload, on this character and another one.
dofile(TESTS_DIR .. "lib.lua")
MOCK.inInstance = true
MOCK.spells[93001] = { name = "Rupture" }
H.login()
local TL, K = A.Timeline, A.TimelineKB
local g = MOCK.creatureGUID(93000, 1)
local function pull()
    MOCK.units.boss1 = { guid = g, name = "Standalone Boss", level = -1, class = "worldboss", combat = true }
    H.enterCombat(); H.fire("INSTANCE_ENCOUNTER_ENGAGE_UNIT")
    local ev = TL:Encounter().events["l93000:93001"]
    local ok = ev and ev.prov == "learned" and near(ev.expires - GetTime(), 12, .6)
    MOCK.units.boss1 = nil; H.leaveCombat(); H.tick(.1, 40)
    return ok
end
check(BlizzUIRebornDB.timeline.schema == 3 and not BlizzUIRebornDB.timeline.timelineBackup, "a 0.7 account needs no migration backup")
check(pull(), "after reload: the learned opener is predicted")
local main = BlizzUIRebornCharDB
BlizzUIRebornCharDB = {}; A:InitDB(); A:LoadActive()
check(pull(), "another character on the account: same prediction")
BlizzUIRebornCharDB = main; A:InitDB(); A:LoadActive()
check(#MOCK.errors == 0 and #A.errorLog == 0, "no Lua errors")
