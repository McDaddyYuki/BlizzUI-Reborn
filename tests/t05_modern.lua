-- Bug 6: Modern preset must convert the whole UI to the Retail layout/style
dofile(TESTS_DIR .. "lib.lua")
H.login()
A:LoadPreset("Classic")
A:LoadPreset("Modern")
local ok, bad = 0, {}
for id, pos in pairs(A.ModernPositions) do
    local def = A.elements[id]
    if A:BindElement(def) then
        local l, b = T.rect(id)
        local el, eb = T.expectedRect(id, pos[1], pos[2], pos[3])
        if near(l, el, 1) and near(b, eb, 1) then ok = ok + 1 else bad[#bad + 1] = id end
    end
end
check(#bad == 0, "every Modern element at its preset position (" .. ok .. " ok; wrong: " .. table.concat(bad, ",") .. ")")
check(MainMenuBarLeftEndCap:GetAlpha() == 0 and MainMenuBarTexture0:GetAlpha() == 0, "gryphons and bar art hidden")
check(ActionBarUpButton:GetAlpha() == 0, "page arrows hidden")
check(not MainMenuBar:IsMouseEnabled(), "empty classic bar strip no longer blocks clicks")
-- the game's own art is left alone (no reskin)
check(PlayerFrameTexture:GetTexture() == nil or not PlayerFrameTexture:GetTexture():find("BlizzUIReborn"), "player frame keeps stock art")
check(ActionButton1:GetNormalTexture():GetAlpha() == 1, "action buttons keep stock art")
check(MinimapBorder:GetAlpha() == 1 and MinimapZoomIn:IsShown(), "minimap keeps stock look")
check(near(CastingBarFrame:GetWidth(), 195), "cast bar keeps stock size")
check(MainMenuXPBarDiv1:GetAlpha() == 1 and near(MainMenuExpBar:GetWidth(), 1024), "XP bar keeps stock art")
check(near(MainMenuExpBar:GetEffectiveScale() / UIParent:GetEffectiveScale(), .5, .01), "XP bar scaled to 50% in Modern")
local p, rel = MainMenuExpBar:GetPoint(1)
check(rel == A.elements.statusbars.frame, "xp bar anchored to the bar holder")
for _, o in ipairs(MOCK.frames) do
    if o.__tex and o.__tex:find("BlizzUIReborn") then check(false, "custom texture used: " .. o.__tex) end
end
-- bonus (stance) bar follows action bar 1
local b1 = { ActionButton1:GetLeft(), ActionButton1:GetBottom() }
local bb = { BonusActionButton1:GetLeft(), BonusActionButton1:GetBottom() }
check(near(b1[1], bb[1]) and near(b1[2], bb[2]), "stance/form buttons share Action Bar 1's position")
-- Classic brings the native layout back
A:LoadPreset("Classic")
local p2, rel2, rp2, x2, y2 = PlayerFrame:GetPoint(1)
check(p2 == "TOPLEFT" and near(x2, -19), "Classic: player frame native")
check(MainMenuBarLeftEndCap:GetAlpha() == 1, "Classic: bar art back")
check(near(MainMenuExpBar:GetScale(), 1), "Classic: native XP bar")
local ap, arel = ActionButton1:GetPoint(1)
check(arel == MainMenuBarArtFrame, "Classic: action button 1 back on the main bar")
