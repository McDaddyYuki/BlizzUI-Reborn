dofile(TESTS_DIR .. "lib.lua")
H.login()
-- the game menu grows only once even when a server script resets its height
for i = 1, 5 do GameMenuFrame:Show(); GameMenuFrame:Hide() end
GameMenuFrame:Show()
check(near(GameMenuFrame:GetHeight(), 248 + 21 + 2), "game menu height stays correct across openings")
local p, rel = GameMenuButtonContinue:GetPoint(1)
check(rel == A.menuButton, "Continue sits under Edit Mode")
GameMenuFrame:Hide()
SlashCmdList.BLIZZUIREBORN("restore")
check(not A.active and A.char.suspended, "restore suspends management")
local pp, prel, prp, px, py = PlayerFrame:GetPoint(1)
check(pp == "TOPLEFT" and near(px, -19) and near(py, -4), "player frame native")
local ap, arel = ActionButton1:GetPoint(1)
check(arel == MainMenuBarArtFrame, "action bar native")
check(near(MainMenuExpBar:GetScale(), 1), "xp bar native")
check(not A.elements.compartment.frame:IsShown(), "compartment hidden")
SlashCmdList.BLIZZUIREBORN("")
check(not A.editing, "editor refuses while suspended")
SlashCmdList.BLIZZUIREBORN("enable")
check(A.active and not A.char.suspended, "enable resumes")
local l, b = T.rect("player")
local el, eb = T.expectedRect("player", "BOTTOM", -290, 208)
check(near(l, el) and near(b, eb), "layout re-applied")
SlashCmdList.BLIZZUIREBORN("report")
check(A.dialogs.Text:IsShown() and A.dialogs.Text.box.box:GetText():find("BlizzUI Reborn"), "report dialog")
A.dialogs.Text:Hide()
SlashCmdList.BLIZZUIREBORN("help")
-- UI scale change keeps anchored layout
UIParent:SetScale(1.2)
H.fire("UI_SCALE_CHANGED"); H.tick(0.1, 3)
local W = UIParent:GetWidth()
local l2, b2, w2 = T.rect("target")
local el2, eb2 = T.expectedRect("target", "BOTTOM", 290, 208)
check(near(l2, el2) and near(b2, eb2), "positions stay correct after UI scale change")
for _, id in ipairs(A.order) do
    local def = A.elements[id]
    if def.applied then
        local ll, bb, ww, hh = A:AnchorRect(def)
        check(ll >= -1 and bb >= -1 and ll + ww <= W + 1, id .. " stays on screen at the new scale")
    end
end
