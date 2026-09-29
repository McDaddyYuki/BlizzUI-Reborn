-- Bug 5: Revert Changes must always work
dofile(TESTS_DIR .. "lib.lua")
SHOW_MULTI_ACTIONBAR_1 = 1; MultiActionBar_Update()
H.login()
T.open()
A.db.editor.snap = false
local ids = { "player", "target", "action1", "action2", "micro", "bags", "cast", "buffs", "chat", "statusbars", "minimap", "objectives", "party", "stance" }
local function snapshot()
    local t = {}
    for _, id in ipairs(ids) do local l, b, w, h = T.rect(id); t[id] = { l, b, w, h } end
    return t
end
local function same(a, b, label)
    local bad = {}
    for id, r in pairs(a) do
        local q = b[id]
        if not (near(r[1], q[1]) and near(r[2], q[2]) and near(r[3], q[3]) and near(r[4], q[4])) then bad[#bad + 1] = id end
    end
    check(#bad == 0, label .. (#bad > 0 and (" (differs: " .. table.concat(bad, ", ") .. ")") or ""))
end
local base = snapshot()
for round = 1, 5 do
    -- a different mix of drags + settings each round
    for i, id in ipairs(ids) do
        if (i + round) % 2 == 0 then T.dragElement(id, (round * 7) % 40 - 20, (round * 11) % 30 - 15) end
    end
    A:SetSetting("player", "scale", 50 + round * 10)
    A:SetSetting("action1", "rows", 1 + round % 3)
    A:SetSetting("micro", "orientation", round % 2 == 0 and "vertical" or "horizontal")
    check(A.dirty and A.editor.revert:IsEnabled(), "round " .. round .. ": dirty and Revert enabled")
    H.click(A.editor.revert)
    H.tick(0.02, 2)
    check(not A.dirty and not A.editor.revert:IsEnabled(), "round " .. round .. ": clean after revert")
    same(base, snapshot(), "round " .. round .. ": every element back where it was")
    check(near(PlayerFrame:GetScale(), 1), "round " .. round .. ": scale reverted")
end

-- revert for a single element from its settings dialog
A:SelectElement("target")
local l0, b0 = T.rect("target")
T.dragElement("target", 25, 25)
local page = A.settingsDialog.pages.target
check(page.revert:IsEnabled(), "per-element revert enabled after change")
H.click(page.revert)
local l1, b1 = T.rect("target")
check(near(l1, l0) and near(b1, b0), "per-element revert restores the element")

-- Reset To Default Position on a Modern-based layout returns to the Modern spot
T.dragElement("target", -80, 40)
H.click(page.reset)
local el, eb = T.expectedRect("target", "BOTTOM", 290, 208)
local rl, rb = T.rect("target")
check(near(rl, el) and near(rb, eb), "Reset To Default Position returns to the preset position")

-- revert on a saved custom layout returns to the saved state (not the preset)
A:CreateLayout("Revert Test", false)
T.dragElement("player", 60, 0)
A:Save()
local sl, sb = T.rect("player")
T.dragElement("player", -120, 50)
H.click(A.editor.revert)
local rl2, rb2 = T.rect("player")
check(near(rl2, sl) and near(rb2, sb), "revert on custom layout returns to its saved position")

-- revert of an element that was not in the saved layout (Classic) restores native
A:LoadPreset("Classic")
local nl, nb = T.rect("focus")
T.dragElement("focus", 30, -30)
H.click(A.editor.revert)
local fl, fb = T.rect("focus")
check(near(fl, nl) and near(fb, nb), "revert on Classic returns frames to native positions")
local p, rel, rp, x, y = FocusFrame:GetPoint(1)
check(p == "TOPLEFT" and near(x, 250) and near(y, -240), "native anchor restored exactly")
