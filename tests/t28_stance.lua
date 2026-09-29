-- Stance bar (paladin auras, warrior stances, DK presences) moves like the
-- totem bar: Blizzard's updates (in or out of combat) never pull it apart.
dofile(TESTS_DIR .. "lib.lua")
local auras = { "Devotion Aura", "Retribution Aura", "Concentration Aura", "Shadow Resistance Aura", "Frost Resistance Aura", "Fire Resistance Aura", "Crusader Aura" }
MOCK.forms = {}
for i, n in ipairs(auras) do MOCK.forms[i] = { "Interface\\Icons\\Aura" .. i, n, i == 1, true } end
ShapeshiftBar_Update()
H.login()
local def = A.elements.stance
check(def.kind == "stancebar", "stance bar uses the whole-bar mover")

-- every shown button is inside the holder, in a row/column, with the layout's padding
local function laidOut(tag)
    local e = A:Settings(def)
    local l, b, w, h = T.rect("stance")
    local ok, why = true, ""
    local n = GetNumShapeshiftForms()
    local x0, y0
    for i = 1, n do
        local bl, bb, bw, bh = A.Rect(_G["ShapeshiftButton" .. i])
        if i == 1 then x0, y0 = bl, bb + bh end
        if e.orientation == "vertical" then
            if not near(bl, l, 1.5) or not near(bb + bh, (b + h) - (i - 1) * (bh + e.padding * (bh / 30)), 1.5) then ok, why = false, "button " .. i end
        else
            if not near(bb, b, 1.5) or not near(bl, l + (i - 1) * (bw + e.padding * (bw / 30)), 1.5) then ok, why = false, "button " .. i end
        end
    end
    local el, eb = T.expectedRect("stance", e.point, e.x, e.y)
    if not (near(l, el, 1) and near(b, eb, 1)) then ok, why = false, "holder off its position" end
    check(ok, tag .. (ok and "" or (" (" .. why .. ")")))
end
laidOut("paladin auras laid out at the layout position")
check(ShapeshiftBarFrame:GetParent() == def.frame and not UIPARENT_MANAGED_FRAME_POSITIONS.ShapeshiftBarFrame, "the bar is held by the layout, not the frame manager")

-- Blizzard updates out of combat, in combat, and the frame manager
UIParent_ManageFramePositions(); H.tick(0.05, 2)
laidOut("frame manager does not move it")
ShapeshiftBar_Update(); H.tick(0.05, 2)
laidOut("ShapeshiftBar_Update out of combat")
H.enterCombat()
MOCK.forms[1][3], MOCK.forms[2][3] = false, true
H.fire("UPDATE_SHAPESHIFT_FORMS"); H.tick(0.05, 2)
laidOut("aura switched in combat: bar stays together")
check(#MOCK.blocked == 0, "no blocked actions in combat")
H.leaveCombat(); H.tick(0.05, 2)

-- Edit Mode: drag, resize, vertical, padding
T.open()
A.db.editor.snap = false
check(T.overlay("stance") and T.overlay("stance"):IsShown(), "stance bar is selectable in Edit Mode")
local l0, b0 = T.rect("stance")
T.dragElement("stance", 60, 40)
local l1, b1 = T.rect("stance")
check(near(l1 - l0, 60, 1) and near(b1 - b0, 40, 1), "stance bar can be dragged")
laidOut("buttons follow the drag")
A:SetSetting("stance", "scale", 130)
check(near(ShapeshiftButton3:GetEffectiveScale() / UIParent:GetEffectiveScale(), 1.3 * MainMenuBar:GetEffectiveScale() / UIParent:GetEffectiveScale(), .01), "stance bar can be resized")
laidOut("resized")
A:SetSetting("stance", "orientation", "vertical"); A:SetSetting("stance", "padding", 8)
laidOut("vertical with padding 8")
check(ShapeshiftBarLeft:GetAlpha() == 0, "horizontal strip art hidden when vertical")
H.enterCombat(); ShapeshiftBar_Update(); H.tick(0.05, 2)
laidOut("vertical survives an in-combat update")
H.leaveCombat()
A:SetSetting("stance", "orientation", "horizontal")
check(ShapeshiftBarLeft:GetAlpha() == 1, "strip art back when horizontal")
-- fewer forms (a warrior-sized bar): the holder shrinks
for i = 4, 7 do MOCK.forms[i] = nil end
ShapeshiftBar_Update(); H.tick(0.05, 3)
local _, _, w3 = T.rect("stance")
check(near(w3, (3 * 30 + 2 * 8) * 1.3 * MainMenuBar:GetEffectiveScale() / UIParent:GetEffectiveScale(), 1.5), "holder fits 3 stances")
laidOut("3 stances")
A:RequestExit(); if T.confirmButton("Save") then H.click(T.confirmButton("Save")) end
if T.confirmButton("Exit") then H.click(T.confirmButton("Exit")) end
-- Classic gives the bar back to Blizzard
A:LoadPreset("Classic")
local p, rel = ShapeshiftBarFrame:GetPoint(1)
check(ShapeshiftBarFrame:GetParent() == MainMenuBar and rel == MainMenuBar and UIPARENT_MANAGED_FRAME_POSITIONS.ShapeshiftBarFrame, "Classic restores the native bar")
local p2, rel2 = ShapeshiftButton2:GetPoint(1)
check(rel2 == ShapeshiftButton1 and p2 == "LEFT", "native button chain restored")
check(#MOCK.errors == 0 and #A.errorLog == 0, "no Lua errors")
