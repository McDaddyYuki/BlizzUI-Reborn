-- shared helpers for scenario tests
T = {}
function T.rect(id) local d = A.elements[id]; return A:AnchorRect(d) end
function T.center(id) local l, b, w, h = T.rect(id); return l + w / 2, b + h / 2 end
function T.overlay(id) return A.elements[id].overlay end
-- screen px <-> UIParent units
function T.px(u) return u * UIParent:GetEffectiveScale() end
function T.open() A:OpenEditor(); H.tick(0.02, 2) end
function T.dragElement(id, dxU, dyU)
    local o = T.overlay(id)
    assert(o and o:IsShown(), "overlay for " .. id .. " not shown")
    H.drag(o, T.px(dxU), T.px(dyU), 8)
end
function T.dialog(key) return A.dialogs[key] end
function T.confirmButton(text)
    local d = A.dialogs.Confirm
    if not d or not d:IsShown() then return nil end
    for _, b in ipairs(d.buttons) do if b:IsShown() and b.text:GetText() == text then return b end end
end
function T.menuRow(text)
    local m = BlizzUIRebornMenu
    if not m or not m:IsShown() then return nil end
    for _, r in ipairs(m.rows) do
        local t = r.text:GetText()
        t = t and t:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
        if r:IsShown() and t and (t == text or t:find(text, 1, true) == 1) then return r end
    end
end
function T.chooseLayout(text)
    H.click(A.editor.layout)
    local r = T.menuRow(text)
    assert(r, "layout menu row " .. text .. " not found")
    H.click(r)
    H.tick(0.02, 2)
end
function T.gear(layoutText, action)
    H.click(A.editor.layout)
    local r = T.menuRow(layoutText)
    assert(r, "layout row " .. layoutText)
    H.click(r.gear)
    local a = T.menuRow(action)
    assert(a, "gear action " .. action)
    H.click(a)
    H.tick(0.02, 2)
end
function T.typeDialog(key, text, charSpecific)
    local d = A.dialogs[key]
    assert(d and d:IsShown(), key .. " dialog not shown")
    H.type(d.box.box, text)
    if charSpecific ~= nil and d.check:IsShown() then d.check:SetChecked(charSpecific) end
    H.click(d.ok)
    H.tick(0.02, 2)
end
function T.expectedRect(id, point, x, y)
    local def = A.elements[id]
    local _, _, w, h = A:AnchorRect(def)
    local l, b = A.FromPosition(point, x, y, w, h)
    return l, b
end
function T.nativeAnchor(frame) local p = { frame:GetPoint(1) }; return p end
-- Test fixture: knowledge as if this account had already learned and
-- validated it from observed pulls (the addon ships none).
-- opts: cd (repeat), first (opener), thr (HP %), flag ("aoe"/"deadly"/...)
function T.learned(npc, id, name, opts)
    local K = A.TimelineKB
    local rec = K:Rec(K:Context(), npc, id, true)
    rec.n = name
    if opts.cd then rec.acc = { kind = "repeat", cd = opts.cd, lo = opts.cd - 1, hi = opts.cd + 1, n = 8, pull = 1, accepted = 2 } end
    if opts.first then rec.first = { kind = "first", t = opts.first, lo = opts.first - 1, hi = opts.first + 1 } end
    if opts.thr then rec.thr = { kind = "threshold", hp = opts.thr, lo = opts.thr, n = 3 } end
    local b = K:Boss(npc, true)
    b.auto = true
    if opts.flag then K:Flags(npc, id, name, true)[opts.flag] = true end
    return rec
end
