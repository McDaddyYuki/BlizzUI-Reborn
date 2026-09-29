-- Crowded timelines in every direction/size, overflow count, provenance
-- labels, right-click controls and the Encounter Details window.
dofile(TESTS_DIR .. "lib.lua")
local HOSTILE = 0xa48
local function advance(sec) H.tick(0.1, math.floor(sec / 0.1 + .5)) end
MOCK.inInstance = true
H.login()
local TL, K, V = A.Timeline, A.TimelineKB, A.TimelineView

-- a practice fight with 12 abilities landing together
local E = TL:StartEncounter(nil, nil, "Crowd", GetTime(), "test")
for i = 1, 12 do
    local ab = { key = "c" .. i, name = "Ability " .. i, spellName = "Ability " .. i, icon = "Interface\\Icons\\Spell_" .. i, practice = true, opened = true }
    TL:AddAbility(ab)
    TL:Schedule(ab, GetTime() + 3 + (i % 3) * .2 + (i > 9 and 50 or 0))
end
A:RefreshTimeline()
local function shownIcons() local n = 0; for _, b in ipairs(V.root.icons) do if b:IsShown() then n = n + 1 end end; return n end
for _, dir in ipairs({ { "vertical", "down" }, { "vertical", "up" }, { "horizontal", "right" }, { "horizontal", "left" } }) do
    for _, size in ipairs({ 50, 200 }) do
        for _, names in ipairs({ false, true }) do
            A:SetSetting("bosstimeline", "orientation", dir[1]); A:SetSetting("bosstimeline", "direction", dir[2])
            A:SetSetting("bosstimeline", "iconSize", size); A:SetSetting("bosstimeline", "showName", names)
            advance(.1)
            local tag = dir[1] .. "/" .. dir[2] .. " " .. size .. "%" .. (names and " names" or "")
            local drawn = shownIcons()
            check(drawn >= 4 and drawn <= 8 and (drawn == 8 or (names and size == 200)), tag .. ": up to 8 icons drawn (" .. drawn .. ")")
            check(V.root.more and V.root.more:IsShown() and V.root.more:GetText() == "+" .. (12 - drawn), tag .. ": '+N' counts the rest")
            -- every icon stays inside the timeline along its track
            local l, b, w, h = A.Rect(V.root)
            local inside = true
            for _, ic in ipairs(V.root.icons) do
                if ic:IsShown() then
                    local x, y = ic:GetCenter()
                    local s = V.root:GetEffectiveScale() / UIParent:GetEffectiveScale()
                    x, y = x * s, y * s
                    if dir[1] == "vertical" and (y < b - 1 or y > b + h + 1) then inside = false end
                    if dir[1] == "horizontal" and (x < l - 1 or x > l + w + 1) then inside = false end
                end
            end
            check(inside, tag .. ": icons stay on the track")
        end
    end
end
A:SetSetting("bosstimeline", "view", "bars")
advance(.1)
local bars = 0
for _, b in ipairs(V.root.bars) do if b:IsShown() then bars = bars + 1 end end
check(bars == 6 and V.root.more:GetText() == "+6", "bars: 6 drawn and '+6'")
A:SetSetting("bosstimeline", "view", "timeline")
TL:EndEncounter("test")

-- ------------------------------------------------------------ provenance and controls on a real fight
T.learned(36612, 69057, "Bone Spike Graveyard", { cd = 18, first = 15, flag = "aoe" })
local g = MOCK.creatureGUID(36612, 3)
MOCK.spells[69057] = { name = "Bone Spike Graveyard", castMs = 3000 }
MOCK.units.boss1 = { guid = g, name = "Lord Marrowgar", level = -1, class = "worldboss", combat = true }
H.enterCombat(); H.fire("INSTANCE_ENCOUNTER_ENGAGE_UNIT")
advance(.2)
local spike
for _, ev in ipairs(TL:DisplayList()) do if ev.name == "Bone Spike Graveyard" then spike = ev end end
check(spike and spike.prov == "learned" and V.TimerText(spike):sub(1, 1) == "~", "learned estimate shows '~'")
check(V.SourceTag(spike) == "learned", "source label: learned")
local icon
for _, b in ipairs(V.root.icons) do if b:IsShown() and b.event == spike then icon = b end end
H.hover(icon)
local lines = table.concat(GameTooltip.__lines or {}, "|")
check(lines:find("Learned on this server") and lines:find("Right%-click"), "tooltip says where the timing comes from")
H.hover(nil)
-- the boss casts it: now there is a record, and the right-click menu works
H.fire("COMBAT_LOG_EVENT_UNFILTERED", GetTime(), "SPELL_CAST_START", g, "Lord Marrowgar", HOSTILE, "", nil, 0, 69057, "Bone Spike Graveyard", 1)
advance(3)
H.fire("COMBAT_LOG_EVENT_UNFILTERED", GetTime(), "SPELL_CAST_SUCCESS", g, "Lord Marrowgar", HOSTILE, "", nil, 0, 69057, "Bone Spike Graveyard", 1)
advance(.2)
for _, ev in ipairs(TL:DisplayList()) do if ev.name == "Bone Spike Graveyard" then spike = ev end end
for _, b in ipairs(V.root.icons) do if b:IsShown() and b.event == spike then icon = b end end
H.click(icon, "RightButton")
check(T.menuRow("Hide This Ability") and T.menuRow("Set Repeat Time"), "right-click menu")
H.click(T.menuRow("Hide This Ability"))
local hidden = true
for _, ev in ipairs(TL:DisplayList()) do if ev.name == "Bone Spike Graveyard" then hidden = false end end
check(hidden, "hidden from the timeline")
local t = A.TimelineTarget(spike)
check(t.rec and t.npc == 36612, "the ability's record is found")
K:Override(t.rec, "cd", 17); TL:Changed()
K:Lock(t.rec, true)
MOCK.units.boss1 = nil; H.leaveCombat(); advance(4)
-- Encounter Details
A:TimelineDetails()
local p = A.timelineDetails
check(p and p:IsShown(), "Encounter Details window")
local found
for _, r in ipairs(p.rows) do if r:IsShown() and r.name:GetText():find("Bone Spike") then found = r end end
check(found and found.name:GetText():find("hidden") and found.info:GetText():find("manual: every 17s") and found.info:GetText():find("locked"), "row shows hidden, manual timing, locked")
H.click(found.gear)
H.click(T.menuRow("Show This Ability"))
A:TimelineDetails()
for _, r in ipairs(p.rows) do if r:IsShown() and r.name:GetText():find("Bone Spike") then found = r end end
check(not found.name:GetText():find("hidden"), "shown again from the details window")
H.click(p.share)
check(A.dialogs.Text:IsShown() and A.dialogs.Text.box.box:GetText():sub(1, 5) == "BRK3:", "share boss data")
H.escape(); p:Hide()
-- next pull uses the manual timing
MOCK.units.boss1 = { guid = g, name = "Lord Marrowgar", level = -1, class = "worldboss", combat = true }
H.enterCombat(); H.fire("INSTANCE_ENCOUNTER_ENGAGE_UNIT")
H.fire("COMBAT_LOG_EVENT_UNFILTERED", GetTime(), "SPELL_CAST_SUCCESS", g, "Lord Marrowgar", HOSTILE, "", nil, 0, 69057, "Bone Spike Graveyard", 1)
for _, ev in ipairs(TL:DisplayList()) do if ev.name == "Bone Spike Graveyard" and ev.source == "predict" then spike = ev end end
check(spike.prov == "manual" and near(spike.remaining, 17, .2), "manual repeat time is used")
-- predictions switch: only casts and boss mod timers
BlizzUIRebornDB.timeline.predictions = false; A:RefreshTimeline()
local anyPredict = false
for _, ev in ipairs(TL:DisplayList()) do if ev.source == "predict" then anyPredict = true end end
check(not anyPredict, "'Show predicted abilities' off hides forecasts")
BlizzUIRebornDB.timeline.predictions = true
MOCK.units.boss1 = nil; H.leaveCombat(); advance(4)
check(#MOCK.errors == 0 and #A.errorLog == 0, "no Lua errors")
