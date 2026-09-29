-- Bug 4: every element can be selected, dragged and configured
dofile(TESTS_DIR .. "lib.lua")
H.login()
T.open()
A.db.editor.snap = false
check(not TargetFrame:IsShown(), "target frame hidden (no target)")
local o = T.overlay("target")
check(o and o:IsShown(), "hidden target frame still has an edit-mode selection")

local moved, total = 0, 0
for _, id in ipairs(A.order) do
    local def = A.elements[id]
    if A:IsEditable(def) and A:ElementEnabled(def) and def.kind ~= "status" then
        total = total + 1
        local l0, b0 = T.rect(id)
        local W, Hh = UIParent:GetWidth(), UIParent:GetHeight()
        local dx = (l0 > W / 2) and -37 or 37
        local dy = (b0 > Hh / 2) and -23 or 23
        if def.kind == "compartment" then dx, dy = -37, -23 end
        T.dragElement(id, dx, dy)
        local l1, b1 = T.rect(id)
        if near(l1 - l0, dx, 1) and near(b1 - b0, dy, 1) then moved = moved + 1
        else print(string.format("    %s moved by %.1f,%.1f expected %d,%d", id, l1 - l0, b1 - b0, dx, dy)) end
        -- the selection box follows the element
        local ol, ob = T.overlay(id):GetLeft(), T.overlay(id):GetBottom()
        local el, eb = A:ElementRect(def)
        check(near(ol, el, 1) and near(ob, eb, 1), id .. " overlay follows the element")
    end
end
check(moved == total and total > 20, string.format("all %d movable elements moved exactly (%d ok)", total, moved))
check(A.selected ~= nil and A.settingsDialog:IsShown(), "dragging selects and opens settings")

-- target frame actually moved (real frame position, not just the overlay)
local e = A.draft.frames.target
local p, rel, rp, x, y = TargetFrame:GetPoint(1)
check(p == e.point and rel == UIParent, "TargetFrame anchored to the stored point")

-- clicking a selection opens its settings panel with the right title
H.click(T.overlay("player")); A:SelectElement("player")
check(A.settingsDialog.title:GetText() == "Player Frame", "settings title")
local page = A.settingsDialog.pages.player
local size = page.controls[1].ctl
size:Commit(120)
check(near(PlayerFrame:GetScale(), 1.2, .001), "Frame Size slider scales the player frame")
size:Step(1)
check(near(PlayerFrame:GetScale(), 1.25, .001), "slider arrow steps by 5%")

-- action bar settings
A:SelectElement("action2")
local s = A.settingsDialog.pages.action2.controls
local function ctl(key) for _, c in ipairs(s) do if c.opt.key == key then return c.ctl end end end
ctl("rows"):Commit(2)
local b1l, b1t = MultiBarBottomLeftButton1:GetLeft(), MultiBarBottomLeftButton1:GetTop()
local b7l, b7t = MultiBarBottomLeftButton7:GetLeft(), MultiBarBottomLeftButton7:GetTop()
check(near(b1l, b7l) and b7t < b1t, "2 rows: button 7 starts the second row")
ctl("icons"):Commit(8)
check(MultiBarBottomLeftButton9:GetAlpha() == 0 and not MultiBarBottomLeftButton9:IsMouseEnabled(), "# of icons hides extra buttons")
check(MultiBarBottomLeftButton8:GetAlpha() == 1, "visible buttons stay")
H.click(ctl("orientation")); H.click(T.menuRow("Vertical"))
check(A.draft.frames.action2.orientation == "vertical", "orientation dropdown")
check(A.settingsDialog.pages.action2.controls[2].ctl.label:GetText() == "# of Columns", "rows label becomes columns when vertical")
ctl("padding"):Commit(8)
local g = MultiBarBottomLeftButton2:GetTop() - MultiBarBottomLeftButton1:GetTop()
check(near(math.abs(MultiBarBottomLeftButton1:GetBottom() - MultiBarBottomLeftButton2:GetTop()), 8, .1), "padding applied")

-- bar 1: hide art
A:SelectElement("action1")
local a1 = A.settingsDialog.pages.action1.controls
for _, c in ipairs(a1) do if c.opt.key == "hideArt" then H.click(c.ctl) end end
check(MainMenuBarLeftEndCap:GetAlpha() == 1, "art shown after unchecking Hide Bar Art")
for _, c in ipairs(a1) do if c.opt.key == "hideArt" then H.click(c.ctl) end end
check(MainMenuBarLeftEndCap:GetAlpha() == 0, "art hidden again")

-- bar enable checkbox (bars 2-5)
A:ToggleElement("action4", true)
check(MultiBarRight:IsShown(), "enabling Action Bar 4 shows it")
A:ToggleElement("action4", false)
check(not MultiBarRight:IsShown(), "disabling Action Bar 4 hides it")

-- cast bar lock
A:SelectElement("cast")
local cc = A.settingsDialog.pages.cast.controls
for _, c in ipairs(cc) do if c.opt.key == "lock" then H.click(c.ctl) end end
local p2, rel2 = CastingBarFrame:GetPoint(1)
check(rel2 == PlayerFrame, "Lock to Player Frame anchors the cast bar to the player frame")
local l0 = T.rect("cast")
T.dragElement("cast", 40, 0)
check(near(T.rect("cast"), l0), "locked cast bar does not move by dragging")
for _, c in ipairs(cc) do if c.opt.key == "lock" then H.click(c.ctl) end end

-- status bars width
A:SetSetting("statusbars", "scale", 70)
check(near(MainMenuExpBar:GetScale(), .7), "XP/rep bar size applies")

-- arrow-key nudging
A:SelectElement("player")
local nl, nb = T.rect("player")
H.pressKey("RIGHT"); H.pressKey("UP"); H.pressKey("SHIFT-UP")
local ml, mb = T.rect("player")
check(near(ml - nl, 1) and near(mb - nb, 11), "arrow keys nudge the selected element")
A:Deselect()
check(not H.pressKey("RIGHT"), "nudge bindings cleared on deselect")

-- snapping to screen centre
A.db.editor.snap = true
A.db.editor.grid = false
for _, id in ipairs(A.order) do if id ~= "focus" then A.db.editor.previews[id] = false end end
A:UpdateOverlays()
local cl, cb, cw = T.rect("focus")
local W = UIParent:GetWidth()
T.dragElement("focus", (W / 2 - cw / 2) - cl + 5, 0)
local sl = T.rect("focus")
check(near(sl + cw / 2, W / 2, .2), "element centre snaps to the screen centre line")
