-- Boss Timeline: detection, first pull (learning), predictions from learned
-- knowledge, casts, warnings,
-- Edit Mode element (move/resize/settings/enable/disable), layouts.
dofile(TESTS_DIR .. "lib.lua")
local TL, V = nil, nil
local HOSTILE = 0xa48
local function cleu(event, guid, name, spellId, spellName, dest)
    H.fire("COMBAT_LOG_EVENT_UNFILTERED", GetTime(), event, guid, name, HOSTILE, dest or "", dest and "Tank" or nil, 0x511, spellId, spellName, 1)
end
local function advance(sec) H.tick(0.1, math.floor(sec / 0.1 + .5)) end
local function event(pred)
    local E = TL:Encounter()
    if not E then return nil end
    for _, ev in pairs(E.events) do if pred(ev) then return ev end end
end
local function named(n) return event(function(ev) return ev.name == n and ev.source ~= "cast" end) end
local function shownIcons()
    local n = 0
    for _, b in ipairs(V.root.icons) do if b:IsShown() then n = n + 1 end end
    return n
end

MOCK.spells[69057] = { name = "Bone Spike Graveyard", icon = "Interface\\Icons\\Ability_Warrior_BloodFrenzy", castMs = 3000 }
MOCK.spells[69076] = { name = "Bone Storm", icon = "Interface\\Icons\\Ability_Whirlwind", castMs = 3000 }
MOCK.spells[26662] = { name = "Berserk", icon = "Interface\\Icons\\Spell_Shadow_UnholyFrenzy" }
MOCK.inInstance = true
H.login()
TL, V = A.Timeline, A.TimelineView

-- ------------------------------------------------------------ idle
check(A.elements.bosstimeline and A.elements.bosswarnings, "Boss Timeline and Boss Warnings elements registered")
check(A:TimelineShown() and A:WarningsShown(), "both on by default")
check(not BlizzUIRebornBossTimeline:IsShown(), "timeline hidden outside boss fights (In Encounter)")
check(not TL.frame:IsShown(), "engine idle: no OnUpdate running")
check(not TL.frame:IsEventRegistered("COMBAT_LOG_EVENT_UNFILTERED"), "combat log not listened to out of combat")
check(TL.frame:IsEventRegistered("PLAYER_REGEN_DISABLED"), "engine waits for combat")
local p, x, y = A:Settings(A.elements.bosstimeline).point, A:Settings(A.elements.bosstimeline).x, A:Settings(A.elements.bosstimeline).y
check(p == "BOTTOM" and near(x, -485, 1) and near(y, 336, 1), "Modern: Retail spot left of the action bars")

-- ------------------------------------------------------------ normal mob: nothing
MOCK.units.target = { guid = MOCK.creatureGUID(1234, 1), name = "Scourge Ghoul", level = 80, class = "elite", combat = true }
H.enterCombat()
advance(1.2)
check(not TL:Active(), "an elite trash mob is not a boss")
check(TL.frame:IsEventRegistered("COMBAT_LOG_EVENT_UNFILTERED"), "combat log listened to in combat")
cleu("SPELL_CAST_START", MOCK.creatureGUID(1234, 1), "Scourge Ghoul", 69057, "Bone Spike Graveyard")
check(not TL:Active(), "trash casts don't start a fight")
MOCK.units.target = nil
H.leaveCombat()
advance(1)
check(not TL.frame:IsEventRegistered("COMBAT_LOG_EVENT_UNFILTERED"), "stops listening after combat")

-- ------------------------------------------------------------ Lord Marrowgar, first pull: nothing known
check(A.TimelineData == nil, "no encounter list ships with the addon")
local boss = MOCK.creatureGUID(36612, 7)
MOCK.units.boss1 = { guid = boss, name = "Lord Marrowgar", level = -1, class = "worldboss", combat = true }
H.enterCombat()
H.fire("INSTANCE_ENCOUNTER_ENGAGE_UNIT")
check(TL:Active(), "boss fight detected (boss1 unit)")
local E = TL:Encounter()
check(E.npcs[36612] and E.guids[boss] and E.trusted[36612], "encounter knows the boss")
local nothing = true
for _, ev in pairs(E.events) do nothing = false end
check(nothing, "unfamiliar boss, no boss mod: no invented first ability or time")
advance(.3)
check(BlizzUIRebornBossTimeline:IsShown() and V.root.hint:IsShown() and V.root.hint:GetText():find("Learning"), "the timeline says it is learning")
advance(5)
cleu("SPELL_CAST_START", boss, "Lord Marrowgar", 69057, "Bone Spike Graveyard")
local firstCast = event(function(ev) return ev.state == "cast" end)
check(firstCast and firstCast.name == "Bone Spike Graveyard" and TL:Visible(firstCast), "the boss's cast is shown as it happens")
check(not BlizzUIRebornBossWarnings.lines.critical:IsShown(), "shown but not alarmed: nothing says it matters yet")
advance(3)
cleu("SPELL_CAST_SUCCESS", boss, "Lord Marrowgar", 69057, "Bone Spike Graveyard")
check(not named("Bone Spike Graveyard"), "one cast is no basis for a forecast")
MOCK.units.boss1 = nil
H.leaveCombat()
advance(4)
check(not TL:Active(), "first pull over")

-- ------------------------------------------------------------ with knowledge learned on earlier pulls
T.learned(36612, 69057, "Bone Spike Graveyard", { cd = 15, first = 15, flag = "aoe" })
T.learned(36612, 69076, "Bone Storm", { cd = 90, first = 45, flag = "aoe" })
MOCK.units.boss1 = { guid = boss, name = "Lord Marrowgar", level = -1, class = "worldboss", combat = true }
H.enterCombat()
H.fire("INSTANCE_ENCOUNTER_ENGAGE_UNIT")
E = TL:Encounter()
local spike, storm = named("Bone Spike Graveyard"), named("Bone Storm")
check(spike and spike.prov == "learned" and near(spike.expires - GetTime(), 15, .2), "Bone Spike Graveyard predicted 15s after the pull (learned opener)")
check(storm and near(storm.expires - GetTime(), 45, .2), "Bone Storm predicted 45s after the pull")
advance(.3)
check(not V.root.hint:IsShown(), "no 'Learning' note while there is something to show")
check(BlizzUIRebornBossTimeline:IsShown(), "timeline appears for the fight")
check(shownIcons() >= 2, "ability icons on the timeline")
-- icons sit in time order along the track (vertical, travelling down: now at the bottom)
local function iconFor(ev) for _, b in ipairs(V.root.icons) do if b:IsShown() and b.event == ev then return b end end end
local bs, bb = iconFor(spike), iconFor(storm)
local _, sy = bs:GetCenter()
local _, by = bb:GetCenter()
check(sy < by, "sooner ability is closer to the now end")
local _, y0 = bs:GetCenter()
advance(2)
local _, y1 = bs:GetCenter()
check(y1 < y0, "icons travel toward the now end")
check(bs.timer:GetText() == "~13", "countdown on the icon (~ = estimate)")
check(iconFor(storm) and iconFor(storm):IsShown(), "far abilities wait in the queue at the end")
-- imminent: highlight + medium warning at 5 seconds
advance(8.2)
check(bs.glow:IsShown(), "highlight inside 5 seconds")
check(BlizzUIRebornBossWarnings:IsShown(), "boss warning shown")
local medium = BlizzUIRebornBossWarnings.lines.medium
check(medium:IsShown() and medium.text:GetText():find("Bone Spike Graveyard in"), "medium warning: ability coming")
-- the boss casts it: cast in progress + critical warning + next prediction
advance(4.8)
cleu("SPELL_CAST_START", boss, "Lord Marrowgar", 69057, "Bone Spike Graveyard")
local cast = event(function(ev) return ev.state == "cast" end)
check(cast and near(cast.expires - GetTime(), 3, .05), "cast in progress shown with its cast time")
local critical = BlizzUIRebornBossWarnings.lines.critical
check(critical:IsShown() and critical.text:GetText() == "Lord Marrowgar: Bone Spike Graveyard", "critical warning: boss is casting")
local shownNames = {}
for _, x in ipairs(TL:DisplayList()) do shownNames[#shownNames + 1] = x.name .. ":" .. x.source end
check(table.concat(shownNames, ","):find("Bone Spike Graveyard:cast") and not table.concat(shownNames, ","):find("Bone Spike Graveyard:predict"), "while it is being cast, only the cast shows (not its countdown too)")
advance(3)
cleu("SPELL_CAST_SUCCESS", boss, "Lord Marrowgar", 69057, "Bone Spike Graveyard")
check(not event(function(ev) return ev.state == "cast" end), "cast bar entry ends with the cast")
spike = named("Bone Spike Graveyard")
check(spike and spike.state == "timer" and near(spike.expires - GetTime(), 12, .2), "completed: next one predicted 15s after the cast began")
-- boss cast bar (exact time) when targeted
MOCK.units.boss1.cast = { name = "Bone Storm", icon = "Interface\\Icons\\Ability_Whirlwind", startMs = GetTime() * 1000, endMs = (GetTime() + 2.5) * 1000 }
H.fire("UNIT_SPELLCAST_START", "boss1", "Bone Storm")
cast = event(function(ev) return ev.state == "cast" end)
check(cast and near(cast.expires - GetTime(), 2.5, .05) and cast.name == "Bone Storm", "boss unit cast bar timing")
MOCK.units.boss1.cast = nil
H.fire("UNIT_SPELLCAST_STOP", "boss1", "Bone Storm")
check(not event(function(ev) return ev.state == "cast" end), "stops with the cast bar")
-- a prediction that doesn't happen waits at the now line, then leaves
local before = named("Bone Spike Graveyard")
advance(15.2)
check(before.state == "soon", "overdue: waits as 'soon'")
advance(8)
check(not named("Bone Spike Graveyard"), "dropped after its grace period")
-- kill: boss dies
check(#MOCK.blocked == 0, "no blocked actions during the fight")
H.fire("COMBAT_LOG_EVENT_UNFILTERED", GetTime(), "UNIT_DIED", "", nil, 0, boss, "Lord Marrowgar", HOSTILE)
MOCK.units.boss1.dead = true
check(TL:Active(), "waits a moment in case another boss joins")
advance(4.2)
check(not TL:Active(), "fight ends when the boss dies")
advance(.2)
check(not BlizzUIRebornBossTimeline:IsShown(), "timeline hides after the fight")
check(TL.lastEnd.reason == "kill", "kill recorded")
MOCK.units.boss1 = nil
H.leaveCombat()

-- ------------------------------------------------------------ wipe: combat ends
MOCK.units.boss1 = { guid = boss, name = "Lord Marrowgar", level = -1, class = "worldboss", combat = true }
H.enterCombat()
H.fire("INSTANCE_ENCOUNTER_ENGAGE_UNIT")
check(TL:Active(), "second pull")
MOCK.units.boss1 = nil
H.leaveCombat()
advance(1.1)
check(TL:Active(), "a short drop out of combat (phase change) doesn't end the fight")
advance(3)
check(not TL:Active() and TL.lastEnd.reason == "combat", "wipe: fight ends once the group is out of combat")
check(not TL.frame:IsEventRegistered("COMBAT_LOG_EVENT_UNFILTERED"), "combat log released after a wipe")

-- ------------------------------------------------------------ Edit Mode
T.open()
advance(.1)
check(BlizzUIRebornBossTimeline:IsShown() and shownIcons() >= 3, "Edit Mode shows a preview timeline")
check(BlizzUIRebornBossWarnings:IsShown() and BlizzUIRebornBossWarnings.lines.critical:IsShown(), "Edit Mode shows sample warnings")
check(T.overlay("bosstimeline"):IsShown() and T.overlay("bosswarnings"):IsShown(), "both selectable")
A.db.editor.snap = false
local l0, b0 = T.rect("bosstimeline")
T.dragElement("bosstimeline", 80, 40)
local l1, b1 = T.rect("bosstimeline")
check(near(l1 - l0, 80, 1) and near(b1 - b0, 40, 1), "timeline can be dragged")
local wl0, wb0 = T.rect("bosswarnings")
T.dragElement("bosswarnings", -30, -60)
local wl1, wb1 = T.rect("bosswarnings")
check(near(wl1 - wl0, -30, 1) and near(wb1 - wb0, -60, 1), "warnings can be dragged")
-- settings dialog: Retail options, only those that apply
A:SelectElement("bosstimeline")
local page = A.settingsDialog.pages.bosstimeline
local function ctl(key) for _, c in ipairs(page.controls) do if c.opt.key == key then return c.ctl end end end
check(ctl("orientation"):IsShown() and not ctl("barWidth"):IsShown() and not ctl("padding"):IsShown(), "timeline view: bar settings hidden")
check(ctl("showName"):IsShown(), "vertical: Show Spell Name available")
A:SetSetting("bosstimeline", "orientation", "horizontal")
A:RefreshSettings()
local w, h = BlizzUIRebornBossTimeline:GetWidth(), BlizzUIRebornBossTimeline:GetHeight()
check(w > h, "horizontal timeline")
check(not ctl("showName"):IsShown(), "horizontal: Show Spell Name hidden (Retail)")
check(ctl("direction"):GetText() == "Right" or (ctl("direction").text and ctl("direction").text:GetText() == "Right"), "direction follows orientation (Right)")
A:SetSetting("bosstimeline", "direction", "left")
advance(.1)
local sorted = {}
for _, b in ipairs(V.root.icons) do if b:IsShown() then sorted[#sorted + 1] = { b.event.remaining, (b:GetCenter()) } end end
table.sort(sorted, function(a, b) return a[1] < b[1] end)
check(#sorted >= 2 and sorted[1][2] < sorted[#sorted][2], "icons travel left: now at the left end")
A:SetSetting("bosstimeline", "view", "bars")
A:RefreshSettings()
advance(.1)
local bars = 0
for _, b in ipairs(V.root.bars) do if b:IsShown() then bars = bars + 1 end end
check(bars >= 3 and shownIcons() == 0, "Bars view")
check(ctl("barWidth"):IsShown() and ctl("padding"):IsShown() and not ctl("orientation"):IsShown(), "bars view: bar settings shown")
local bw0 = BlizzUIRebornBossTimeline:GetWidth()
A:SetSetting("bosstimeline", "barWidth", 150)
check(BlizzUIRebornBossTimeline:GetWidth() > bw0, "bar width")
A:SetSetting("bosstimeline", "scale", 150)
check(near(BlizzUIRebornBossTimeline:GetScale(), 1.5, .01), "overall size")
A:SetSetting("bosstimeline", "alpha", 60)
check(near(BlizzUIRebornBossTimeline:GetAlpha(), .6, .01), "transparency")
A:SetSetting("bosstimeline", "background", 40)
check(near(BlizzUIRebornBossTimeline.bg:GetAlpha(), .4, .01), "background")
check(A.settingsDialog:GetHeight() > 200, "dialog sized to its settings")
-- disable / enable from the Edit Mode list
A:ToggleElement("bosstimeline", false)
check(not BlizzUIRebornBossTimeline:IsShown() and not T.overlay("bosstimeline"):IsShown(), "unticking hides the timeline")
check(TL.enabled, "engine keeps running for Boss Warnings")
A:ToggleElement("bosswarnings", false)
check(not TL.enabled and not TL.frame:IsEventRegistered("PLAYER_REGEN_DISABLED"), "both off: engine fully off")
A:ToggleElement("bosstimeline", true); A:ToggleElement("bosswarnings", true)
check(TL.enabled and BlizzUIRebornBossTimeline:IsShown(), "ticked again: back")
-- save, reload values, revert
local saveName = "Raid"
A:CreateLayout(saveName, false)
check(A.saved.frames.bosstimeline and A.saved.frames.bosstimeline.view == "bars", "saved with the layout")
A:SetSetting("bosstimeline", "view", "timeline")
A:Revert()
check(A:Settings(A.elements.bosstimeline).view == "bars" and #V.root.bars > 0, "revert restores the saved settings")
-- export / import round trip
local code = A:Export(A.saved, "Raid")
local data = A:Decode(code)
check(data and data.frames.bosstimeline and data.frames.bosstimeline.view == "bars" and data.frames.bosstimeline.barWidth == 150, "share/import carries the timeline settings")
-- Classic preset: default spot and settings
A:RequestLayout("preset", "Classic")
H.tick(.1, 2)
check(A:Settings(A.elements.bosstimeline).view == "timeline", "Classic: default settings")
local cl, cb, cw = A.Rect(BlizzUIRebornBossTimeline)
local W = UIParent:GetWidth()
check(near(cl + cw, W / 2 - 457, 1) and near(cb, 336, 1), "Classic: Retail default position")
A:RequestExit()
if T.confirmButton("Exit") then H.click(T.confirmButton("Exit")) end
advance(.1)
check(not BlizzUIRebornBossTimeline:IsShown() and not BlizzUIRebornBossWarnings:IsShown(), "preview gone after Edit Mode")

-- ------------------------------------------------------------ practice fight
A:TestTimeline()
advance(.2)
check(TL:Active() and BlizzUIRebornBossTimeline:IsShown(), "practice fight shows the timeline")
advance(8.2)
check(event(function(ev) return ev.state == "cast" end) or named("Shadow Bolt Volley"), "practice boss casts")
advance(33)
check(not TL:Active() and not BlizzUIRebornBossTimeline:IsShown(), "practice fight ends by itself")

-- ------------------------------------------------------------ options
MOCK.units.boss1 = { guid = boss, name = "Lord Marrowgar", level = -1, class = "worldboss", combat = true }
H.enterCombat()
H.fire("INSTANCE_ENCOUNTER_ENGAGE_UNIT")
advance(.2)
local all = #TL:DisplayList()
A:TimelineDB().hideLong = true; A:RefreshTimeline()
advance(.2)
check(shownIcons() == 0, "Hide Long Countdowns: nothing within 12 seconds yet")
advance(4)
check(shownIcons() == 1, "Hide Long Countdowns: shows the ability once it is 12 seconds away")
A:TimelineDB().hideLong = nil; A:TimelineDB().hideQueued = true; A:RefreshTimeline()
advance(.2)
local near40 = 0
for _, ev in ipairs(TL:DisplayList()) do if ev.remaining <= TL.LONG then near40 = near40 + 1 end end
check(near40 < all and shownIcons() == near40, "Hide Queued Countdowns: abilities beyond 40 seconds are not listed")
A:TimelineDB().hideQueued = nil; A:RefreshTimeline()
MOCK.units.boss1 = nil
H.leaveCombat()
advance(4)
check(#MOCK.errors == 0 and #A.errorLog == 0, "no Lua errors")
check(#MOCK.blocked == 0, "no blocked actions")
