-- Boss Timeline: learning unknown bosses, DBM and BigWigs timers, mid-fight
-- joins, performance.
dofile(TESTS_DIR .. "lib.lua")
local HOSTILE, FRIENDLY_PLAYER = 0xa48, 0x511
local function cleu(event, guid, name, spellId, spellName, flags)
    H.fire("COMBAT_LOG_EVENT_UNFILTERED", GetTime(), event, guid, name, flags or HOSTILE, "", nil, 0, spellId, spellName, 1)
end
local function advance(sec) H.tick(0.1, math.floor(sec / 0.1 + .5)) end
local TL
local function named(n)
    local E = TL:Encounter()
    if not E then return nil end
    for _, ev in pairs(E.events) do if ev.name == n and ev.source ~= "cast" then return ev end end
end
local function listed(n) for _, ev in ipairs(TL:DisplayList()) do if ev.name == n and ev.source ~= "cast" then return ev end end end

-- fake DBM (retail-style callbacks, as DBM-Warmane has) and BigWigs (AceEvent messages)
local dbmCallbacks = {}
local mods = { LordMarrowgar = { id = "LordMarrowgar", creatureId = 36612, inCombat = false } }
DBM = { RegisterCallback = function(self, ev, f) dbmCallbacks[ev] = dbmCallbacks[ev] or {}; table.insert(dbmCallbacks[ev], f) end,
    GetModByName = function(self, id) return mods[id] end }
local function dbm(ev, ...) for _, f in ipairs(dbmCallbacks[ev] or {}) do f(ev, ...) end end
local registry = {}
local AceEvent = { Embed = function(self, t)
    t.RegisterMessage = function(_, msg, fn) registry[msg] = registry[msg] or {}; table.insert(registry[msg], fn) end
    return t
end }
local function bw(msg, ...) for _, fn in ipairs(registry[msg] or {}) do fn(msg, ...) end end
LibStub = setmetatable({ GetLibrary = function(self, name) if name == "AceEvent-3.0" then return AceEvent end end },
    { __call = function(self, name) return self:GetLibrary(name) end })
BigWigs = { GetEnableMobs = function() return { [36612] = "Lord Marrowgar", [37007] = { "Deathbound Ward", "Trash" }, [37813] = "Deathbringer Saurfang" } end }
MOCK.inInstance = true
MOCK.spells[90010] = { name = "Shadow Nova", icon = "Interface\\Icons\\Spell_Shadow_ShadowFury" }
MOCK.spells[90011] = { name = "Strike", icon = "Interface\\Icons\\Ability_MeleeDamage" }
MOCK.spells[69057] = { name = "Bone Spike Graveyard", castMs = 3000 }
MOCK.spells[69076] = { name = "Bone Storm", castMs = 3000 }
MOCK.spells[26662] = { name = "Berserk" }
H.login()
TL = A.Timeline
check(TL.dbmHooked and TL.bwHooked, "DBM and BigWigs timers hooked")

-- ------------------------------------------------------------ learning an unknown boss
local ub = MOCK.creatureGUID(90001, 3)
local function pull(casts, strikes)
    MOCK.units.target = { guid = ub, name = "Custom Boss", level = 83, class = "worldboss", combat = true }
    H.enterCombat()
    advance(.2)
    local t0 = GetTime()
    for _, at in ipairs(casts) do
        advance(at - (GetTime() - t0))
        cleu("SPELL_CAST_SUCCESS", ub, "Custom Boss", 90010, "Shadow Nova")
        -- a melee special every 2 seconds in between
        if strikes then for _ = 1, 4 do advance(2); cleu("SPELL_CAST_SUCCESS", ub, "Custom Boss", 90011, "Strike") end end
    end
    return t0
end
local function wipe()
    MOCK.units.target = nil
    H.leaveCombat()
    advance(4)
end
pull({}, false)
check(TL:Active() and TL:Encounter().npcs[90001], "world boss with no data: fight tracked")
advance(.2)
check(BlizzUIRebornBossTimeline.hint:IsShown(), "shows it is learning the fight")
wipe()
local t0 = pull({ 10, 30, 50, 70 }, true)
local nova = named("Shadow Nova")
check(nova and nova.prov == "provisional" and near(nova.expires - (t0 + 70), 20, .3), "three clean intervals in a pull: a provisional (learning) estimate")
check(not named("Strike"), "spammy abilities are not shown")
wipe()
local rec = A.TimelineKB:Rec(A.TimelineKB:Context(), 90001, 90010)
check(rec and #rec.g == 3 and #rec.f == 1 and not rec.acc, "samples saved per realm/difficulty, nothing accepted yet")
check(BlizzUIRebornDB.timeline.bosses[90001] and BlizzUIRebornDB.timeline.bosses[90001].auto, "world boss remembered as a boss")
pull({ 11, 31, 51, 71 }, false); wipe()
pull({ 10, 30, 50, 70 }, false); wipe()
pull({}, false)
nova = named("Shadow Nova")
check(nova and nova.prov == "learned" and near(nova.expires - TL:Encounter().start, 10, .6), "fourth pull: opener learned from three pulls")
wipe()
-- learned bosses are recognised from the combat log too (no target needed)
H.enterCombat()
cleu("SPELL_CAST_SUCCESS", ub, "Custom Boss", 90010, "Shadow Nova")
check(TL:Active(), "learned boss recognised from its casts")
H.leaveCombat()
advance(4)

-- knowledge learned on earlier pulls (fixtures: nothing ships with the addon)
T.learned(36612, 69057, "Bone Spike Graveyard", { cd = 15, first = 15, flag = "aoe" })
T.learned(36612, 69076, "Bone Storm", { cd = 90, first = 45, flag = "aoe" })

-- ------------------------------------------------------------ joining a fight late
H.enterCombat()
advance(8)
local boss = MOCK.creatureGUID(36612, 9)
cleu("SPELL_CAST_START", boss, "Lord Marrowgar", 69057, "Bone Spike Graveyard")
check(TL:Active() and TL:Encounter().late, "known boss seen in the log mid-fight: tracked (late join)")
check(not named("Bone Storm"), "late join: pull-relative first casts are not guessed")
advance(3)
cleu("SPELL_CAST_SUCCESS", boss, "Lord Marrowgar", 69057, "Bone Spike Graveyard")
local spike = named("Bone Spike Graveyard")
check(spike and spike.state == "timer" and near(spike.expires - GetTime(), 12, .2), "late join: predictions start from the casts seen")
H.leaveCombat()
advance(4)

-- ------------------------------------------------------------ Deadly Boss Mods
H.enterCombat()
mods.LordMarrowgar.inCombat = true
dbm("DBM_Pull", mods.LordMarrowgar, 0)
check(TL:Active() and TL:Encounter().npcs[36612], "DBM pull starts the fight")
check(listed("Bone Spike Graveyard") and listed("Bone Spike Graveyard").source == "predict", "learned prediction until DBM sends timers")
dbm("DBM_TimerStart", "Timer69057cd", "Bone Spike Graveyard CD", 18, "Interface\\Icons\\Ability_Warrior_BloodFrenzy", "cd", 69057, 3, "LordMarrowgar", nil, nil, "Bone Spike Graveyard")
local ev = listed("Bone Spike Graveyard")
check(ev and ev.source == "dbm" and near(ev.remaining, 18, .1), "DBM timer shown instead of the learned one (no proof yet it is better here)")
local count = 0
for _, x in ipairs(TL:DisplayList()) do if x.name == "Bone Spike Graveyard" then count = count + 1 end end
check(count == 1, "no duplicate for the same ability")
dbm("DBM_TimerStart", "Timer69065target", "Impale: Tank", 8, nil, "target", 69065, 3, "LordMarrowgar", nil, nil, "Impale")
check(not listed("Impale"), "debuff/target timers are not boss abilities")
dbm("DBM_TimerUpdate", "Timer69057cd", 10, 20)
check(near(listed("Bone Spike Graveyard").remaining, 10, .1), "DBM timer updates follow")
dbm("DBM_TimerPause", "Timer69057cd")
advance(2)
check(near(listed("Bone Spike Graveyard").remaining, 10, .15), "paused timers stay put")
dbm("DBM_TimerResume", "Timer69057cd")
advance(1)
check(near(listed("Bone Spike Graveyard").remaining, 9, .15), "resumed")
-- a DBM timer that ran out: our own prediction for that ability shows again
dbm("DBM_TimerStart", "Timer69076cd", "Bone Storm CD", 1, nil, "cd", 69076, 2, "LordMarrowgar", nil, nil, "Bone Storm")
check(listed("Bone Storm") and listed("Bone Storm").source == "dbm", "DBM Bone Storm timer")
advance(2.5)
check(not listed("Bone Storm"), "after DBM's timer ends, no old local estimate comes back")
-- the boss casts it and DBM doesn't restart its timer: our fresh estimate takes over
cleu("SPELL_CAST_START", MOCK.creatureGUID(36612, 1), "Lord Marrowgar", 69076, "Bone Storm")
check(not listed("Bone Storm") or listed("Bone Storm").source ~= "predict", "not while DBM may still restart it")
advance(2.2)
check(not listed("Bone Storm"), "not during the cast (DBM may restart it when the cast completes)")
advance(2.5)
check(listed("Bone Storm") and listed("Bone Storm").source == "predict" and near(listed("Bone Storm").remaining, 85.3, .5), "fresh cast, no DBM timer: our estimate from that cast")
dbm("DBM_TimerStart", "berserk", "Berserk", 600, nil, "berserk", nil, 0, "LordMarrowgar")
check(listed("Berserk") or listed("Enrage"), "enrage from DBM")
dbm("DBM_TimerStop", "Timer69057cd")
check(not (listed("Bone Spike Graveyard") and listed("Bone Spike Graveyard").source == "dbm"), "DBM stop removes the timer")
dbm("DBM_Kill", mods.LordMarrowgar)
check(not TL:Active(), "DBM kill ends the fight")
mods.LordMarrowgar.inCombat = false
BlizzUIRebornDB.timeline.useBossMods = false
dbm("DBM_Pull", mods.LordMarrowgar, 0)
check(not TL:Active(), "boss mod timers can be turned off in the options")
BlizzUIRebornDB.timeline.useBossMods = true
H.leaveCombat()
advance(4)

-- ------------------------------------------------------------ BigWigs
H.enterCombat()
local module = { moduleName = "Lord Marrowgar" }
bw("BigWigs_OnBossEngage", module, "Lord Marrowgar")
check(TL:Active(), "BigWigs engage starts the fight")
bw("BigWigs_StartBar", module, 69076, "Bone Storm", 45, "Interface\\Icons\\Ability_Whirlwind")
ev = listed("Bone Storm")
check(ev and ev.source == "bigwigs" and near(ev.remaining, 45, .1), "BigWigs bar shown")
bw("BigWigs_StopBar", module, "Bone Storm")
check(not listed("Bone Storm"), "BigWigs stop removes it")
bw("BigWigs_StartBar", module, 69076, "Bone Storm", 45, "Interface\\Icons\\Ability_Whirlwind")
bw("BigWigs_StopBar", module, 69076)
check(not listed("Bone Storm"), "BigWigs stop by key (the prototype's StopBar) removes it too")
bw("BigWigs_SetStage", module, 2)
check(TL:Encounter().phase == 2, "BigWigs stage message: phase 2")
MOCK.spells[71224] = { name = "Mutated Infection" }
bw("BigWigs_StartBar", module, 71224, "Infection: " .. UnitName("player"), 14, nil)
check(not listed("Infection: " .. UnitName("player")) and not TL:Encounter().owner["id:71224"], "a BigWigs bar about a player is not a boss ability timer")
bw("BigWigs_StartBar", module, 69076, "~Bone Storm", 30, nil)
check(TL:Encounter().owner["id:69076"] and TL:Encounter().owner["id:69076"].bigwigs, "a bar whose text names the spell times that spell")
bw("BigWigs_StartBar", { moduleName = "Deathbringer Saurfang" }, 72385, "Boiling Blood", 20, nil)
check(not listed("Boiling Blood"), "another BigWigs module's bar is ignored")
bw("BigWigs_OnBossWin", { moduleName = "Deathbringer Saurfang" })
check(TL:Active(), "another module's win doesn't end the fight")
bw("BigWigs_OnBossWin", module)
check(not TL:Active(), "BigWigs win ends the fight")
H.leaveCombat()
advance(4)

-- BigWigs trash modules "engage" too: no boss fight from them
H.enterCombat()
bw("BigWigs_OnBossEngage", { moduleName = "Trash" }, "Trash")
check(not TL:Active(), "a BigWigs trash module's engage doesn't start a boss fight")
bw("BigWigs_OnBossEngage", { moduleName = "Unknown" }, "Unknown")
check(not TL:Active(), "nor does a module whose creatures aren't known bosses")
H.leaveCombat(); advance(4)
-- a fight we detected ourselves adopts the BigWigs module of its boss
local mg = MOCK.creatureGUID(36612, 4)
MOCK.units.boss1 = { guid = mg, name = "Lord Marrowgar", level = -1, class = "worldboss", combat = true }
H.enterCombat(); H.fire("INSTANCE_ENCOUNTER_ENGAGE_UNIT")
bw("BigWigs_StartBar", module, 69057, "Bone Spike Graveyard", 15, nil)
check(listed("Bone Spike Graveyard") and listed("Bone Spike Graveyard").source == "bigwigs", "the boss's own BigWigs module is recognised by its creatures")
MOCK.units.boss1 = nil; H.leaveCombat(); advance(4)

-- ------------------------------------------------------------ performance & safety
MOCK.units.boss1 = { guid = boss, name = "Lord Marrowgar", level = -1, class = "worldboss", combat = true }
H.enterCombat()
H.fire("INSTANCE_ENCOUNTER_ENGAGE_UNIT")
local clock = os.clock()
for i = 1, 20000 do
    if i % 4 == 0 then cleu("SPELL_AURA_APPLIED", "0x0000000000000042", "Healer", 48068, "Renew", FRIENDLY_PLAYER)
    elseif i % 4 == 1 then cleu("SPELL_DAMAGE", boss, "Lord Marrowgar", 69146, "Coldflame")
    elseif i % 4 == 2 then cleu("SPELL_AURA_APPLIED", MOCK.creatureGUID(38711, i), "Bone Spike", 69065, "Impaled")
    else cleu("SPELL_CAST_SUCCESS", "0x0000000000000043", "Mage", 42842, "Frostbolt", FRIENDLY_PLAYER) end
end
local spent = os.clock() - clock
print(string.format("    20000 combat log events: %.3fs CPU in the mock", spent))
check(spent < 1.5, "combat log handling is cheap")
clock = os.clock()
advance(10)
print(string.format("    10s of a tracked fight: %.3fs CPU in the mock", os.clock() - clock))
MOCK.units.boss1 = nil
H.leaveCombat()
advance(4)
check(not TL.frame:IsShown() and not BlizzUIRebornBossTimeline:IsShown(), "all quiet after the fight")
check(#MOCK.blocked == 0, "no blocked actions")

-- ------------------------------------------------------------ generic bars and identities
mods.LordMarrowgar.inCombat = true
H.enterCombat()
dbm("DBM_Pull", mods.LordMarrowgar, 0)
local module2 = { moduleName = "Lord Marrowgar" }
bw("BigWigs_OnBossEngage", module2, "Lord Marrowgar")
dbm("DBM_TimerStart", "phase", "Next Phase", 30, nil, "stage", nil, 0, "LordMarrowgar", nil, nil, "Next Phase")
bw("BigWigs_StartBar", module2, "phase", "Next Phase", 31, nil)
local phases = 0
for _, x in ipairs(TL:DisplayList()) do if x.name == "Next Phase" then phases = phases + 1 end end
check(phases == 1, "a phase bar from both boss mods: one entry")
check(listed("Bone Spike Graveyard") and listed("Bone Spike Graveyard").source == "predict", "a generic bar never hides an ability")
-- same localized name, different spell (different icon): not merged
MOCK.spells[99901] = { name = "Bone Spike Graveyard", icon = "Interface\\Icons\\Something_Else" }
dbm("DBM_TimerStart", "other", "Bone Spike Graveyard", 25, nil, "cd", 99901, 0, "LordMarrowgar", nil, nil, "Bone Spike Graveyard")
check(TL:Encounter().aliases["id:69057"] == nil, "a different spell sharing the name is not merged with it")
-- difficulty variant: same name and icon, another ID: joined
MOCK.spells[70826] = { name = "Bone Spike Graveyard", icon = MOCK.spells[69057].icon or "Interface\\Icons\\Spell_Nature_Heal" }
dbm("DBM_TimerStart", "variant", "Bone Spike Graveyard", 20, nil, "cd", 70826, 0, "LordMarrowgar", nil, nil, "Bone Spike Graveyard")
check(TL:Encounter().aliases["id:69057"] == "id:70826", "a variant ID with the same name and icon is the same ability")
local n = 0
for _, x in ipairs(TL:DisplayList()) do if x.name == "Bone Spike Graveyard" and x.spellId ~= 99901 then n = n + 1 end end
check(n == 1, "one entry for the variant (the boss mod's)")
-- DBM variable timers carry their window (DBM-Warmane: hasVariance, max time)
dbm("DBM_TimerStart", "var", "Coldflame", 10, nil, "var", 69146, 0, "LordMarrowgar", nil, nil, "Coldflame", nil, nil, nil, nil, true, 14)
local cf = TL:Encounter().events["dbm:var"]
check(cf and near(cf.expires - GetTime(), 10, .1) and near(cf.hi - GetTime(), 14, .1), "DBM variable timer: shown as a 10-14s window")
-- BigWigs stage messages change the phase when no DBM module owns the fight
check(TL:Encounter().phase == 1, "phase 1")
bw("BigWigs_SetStage", module2, 2)
check(TL:Encounter().phase == 1, "DBM owns this fight's phases: BigWigs' stage message is not used twice")
dbm("DBM_Wipe", mods.LordMarrowgar)
check(not TL:Active(), "DBM wipe ends the fight")
mods.LordMarrowgar.inCombat = false
H.leaveCombat(); advance(4)

-- ------------------------------------------------------------ suspend / resume
SlashCmdList.BLIZZUIREBORN("restore")
check(not TL.enabled and not TL.frame:IsEventRegistered("PLAYER_REGEN_DISABLED"), "/br restore turns the Boss Timeline off")
SlashCmdList.BLIZZUIREBORN("enable")
check(TL.enabled, "/br enable turns it back on")
