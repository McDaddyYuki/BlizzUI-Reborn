-- Shaman totem bar: switching Call of the Elements / Ancestors / Spirits
dofile(TESTS_DIR .. "lib.lua")
MultiCastActionBarFrame_Update(MultiCastActionBarFrame)
H.tick(0.05, 10)
H.login()
local function at()
    local l, b = T.rect("totems")
    local e = A:Settings(A.elements.totems)
    local el, eb = T.expectedRect("totems", e.point, e.x, e.y)
    return near(l, el, 1) and near(b, eb, 1)
end
check(at(), "totem bar at its Modern position")
for round = 1, 3 do
    for page = 1, 3 do
        MultiCastFlyoutButton_OnClick(page)
        local stable, moved = true, false
        for i = 1, 20 do
            H.tick(0.03)
            if not at() then stable = false end
        end
        check(_G["MultiCastActionPage" .. page]:IsShown(), "round " .. round .. ": page " .. page .. " shown after switching")
        for other = 1, 3 do
            if other ~= page then check(not _G["MultiCastActionPage" .. other]:IsShown(), "round " .. round .. ": page " .. other .. " hidden") end
        end
        check(MultiCastSummonSpellButton:GetAttribute("spell") == MOCK.totemSpells[page], "summon button follows the page")
        check(stable, "round " .. round .. ": bar never jumps back to the default spot while switching page " .. page)
    end
end
-- in combat too (pages switch through secure code)
H.enterCombat()
MultiCastFlyoutButton_OnClick(2); H.tick(0.03, 20)
check(MultiCastActionPage2:IsShown() and at(), "switching in combat works and the bar stays put")
H.leaveCombat()
-- Edit Mode can still move and resize it
T.open()
A.db.editor.snap = false
local l0, b0 = T.rect("totems")
T.dragElement("totems", 40, 20)
local l1, b1 = T.rect("totems")
check(near(l1 - l0, 40, 1) and near(b1 - b0, 20, 1), "totem bar can be dragged")
A:SetSetting("totems", "scale", 120)
check(near(MultiCastActionButton1:GetEffectiveScale() / UIParent:GetEffectiveScale(), 1.2, .01), "totem bar can be resized")
MultiCastFlyoutButton_OnClick(3); H.tick(0.03, 20)
check(MultiCastActionPage3:IsShown() and at(), "paging still works after moving")
A:RequestExit(); if T.confirmButton("Exit") then H.click(T.confirmButton("Exit")) end
-- Classic gives the bar back to Blizzard (animation included)
A:LoadPreset("Classic")
local p, rel = MultiCastActionBarFrame:GetPoint(1)
check(MultiCastActionBarFrame:GetParent() == UIParent and rel == MainMenuBar, "Classic restores the native bar")
check(MultiCastActionBarFrame:GetScript("OnUpdate") ~= nil, "Classic restores the slide animation")
MOCK.totemSlideFrames = 0
MultiCastFlyoutButton_OnClick(1); H.tick(0.03, 20)
check(MOCK.totemSlideFrames > 0 and MultiCastActionPage1:IsShown(), "native paging + animation work after restore")
