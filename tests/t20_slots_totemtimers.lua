-- 0.4.1: empty action slots, Totem Timers element
dofile(TESTS_DIR .. "lib.lua")
-- slots 3 and 5 of the main bar and 62 (bottom-left bar, button 2) are empty
MOCK.actions[3], MOCK.actions[5], MOCK.actions[62] = nil, nil, nil
SHOW_MULTI_ACTIONBAR_1 = 1
H.login()
check(A:Settings(A.elements.action1).always == false, "Always Show Buttons is off")
check(ActionButton3:GetAlpha() == 0 and ActionButton5:GetAlpha() == 0, "empty slots are blank")
check(ActionButton4:GetAlpha() == 1 and ActionButton1:GetAlpha() == 1, "filled slots stay")
check(MultiBarBottomLeftButton2:GetAlpha() == 0 and MultiBarBottomLeftButton3:GetAlpha() == 1, "same on the other bars")
-- dragging a spell shows every slot so it can be dropped anywhere
H.fire("ACTIONBAR_SHOWGRID")
check(ActionButton3:GetAlpha() == 1, "empty slot visible while a spell is on the cursor")
MOCK.actions[3] = true
ActionButton_Update(ActionButton3)
H.fire("ACTIONBAR_HIDEGRID")
check(ActionButton3:GetAlpha() == 1, "slot that got a spell stays")
check(ActionButton5:GetAlpha() == 0, "other empty slot blank again after the drop")
-- a slot emptied in combat (page/stance change) is blanked without blocked calls
H.clearErrors()
H.enterCombat()
MOCK.actions[4] = nil
ActionButton_Update(ActionButton4)
check(ActionButton4:GetAlpha() == 0, "emptied in combat -> blank")
check(#MOCK.blocked == 0, "no blocked actions")
H.leaveCombat()
MOCK.actions[4] = true
-- Always Show Buttons on shows them again
T.open()
A:SetSetting("action1", "always", true)
check(ActionButton5:GetAlpha() == 1, "Always Show Buttons on: empty slot shown")
A:SetSetting("action1", "always", false)
check(ActionButton5:GetAlpha() == 0, "off again: blank")

-- Totem Timers
MOCK.totems = 4
TotemFrame_Update()
check(A.elements.totemtimers and A.elements.totemtimers.frame == TotemFrame, "Totem Timers element bound to TotemFrame")
A.db.editor.snap = false
check(T.overlay("totemtimers") and T.overlay("totemtimers"):IsShown(), "Totem Timers selectable in Edit Mode")
local l0, b0 = T.rect("totemtimers")
T.dragElement("totemtimers", 60, -30)
local l1, b1 = T.rect("totemtimers")
check(near(l1 - l0, 60, 1) and near(b1 - b0, -30, 1), "totem timers can be dragged")
A:SetSetting("totemtimers", "scale", 150)
check(near(TotemFrame:GetScale(), 1.5, .01), "totem timers can be resized")
local l2, b2 = T.rect("totemtimers")
-- death knights: Blizzard re-anchors it to the player frame; the drift check puts it back
MOCK.playerClass = "DEATHKNIGHT"
TotemFrame_Update()
H.tick(0.1, 3)
local l3, b3 = T.rect("totemtimers")
check(near(l3, l2, 1) and near(b3, b2, 1), "stays where it was put after Blizzard re-anchors it")
check(#MOCK.errors == 0, "no Lua errors")
