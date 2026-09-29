dofile(TESTS_DIR .. "lib.lua")
H.login()
T.open()
A.db.editor.snap = false
A:CreateLayout("Share Me", false)
T.dragElement("player", 33, -21)
A:SetSetting("action3", "orientation", "vertical")
A:SetSetting("cast", "time", true)
A:Save()
local l0, b0 = T.rect("player")
H.click(A.editor.layout); H.click(T.menuRow("Share Current Layout"))
local d = A.dialogs.Text
check(d:IsShown(), "share dialog shown")
local text = d.box.box:GetText()
check(text:sub(1, 3) == "BR2" and not text:find("|", 1, true), "export is BR2 without | characters")
H.click(d.ok)
-- import it back under another name
A:LoadPreset("Classic")
H.click(A.editor.layout); H.click(T.menuRow("Import Layout"))
T.typeDialog("Text", "garbage")
check(A.dialogs.Text:IsShown() and A.dialogs.Text.err:GetText():find("not a BlizzUI"), "invalid text rejected with a message")
T.typeDialog("Text", text)
H.tick(0.02, 2)
check(A.dialogs.Name:IsShown(), "name prompt after a valid import")
check(A.dialogs.Name.box.box:GetText() == "Share Me 2", "suggested unique name")
T.typeDialog("Name", "Imported")
check(A.char.active.name == "Imported", "imported layout active")
local l1, b1 = T.rect("player")
check(near(l1, l0) and near(b1, b0), "imported positions match")
check(A.draft.frames.action3.orientation == "vertical" and A.draft.frames.cast.time == true, "imported settings match")
-- legacy BR1 strings from the old version still import
local legacy = "BR1\nN|Old\nO||1||1\nF||player||scale||110\nF||player||x||0.3\nF||player||y||0.4"
local data, name = A:Decode(legacy)
check(data and name == "Old" and data.frames.player.point and data.frames.player.scale == 110, "legacy BR1 import converts positions")
local bad = { "BR2\nF:player:point:NOWHERE\nF:player:x:1\nF:player:y:1", "BR2\nF:player:x:1\nF:player:y:1",
    "BR2\nF:player:point:TOP\nF:player:x:1\nF:player:y:1\nF:player:scale:999", "BR2\nF:nosuch:point:TOP", "BR2\nF:player:point:TOP\nF:player:x:1\nF:player:y:1\nF:player:evil:1" }
for i, s in ipairs(bad) do check(A:Decode(s) == nil, "malformed string " .. i .. " rejected") end
-- names with odd characters survive the round trip
local exported = A:Export(A.draft, "Raid: 25% / Heroic")
local _, n2 = A:Decode(exported)
check(n2 == "Raid: 25% / Heroic", "names are escaped safely")
