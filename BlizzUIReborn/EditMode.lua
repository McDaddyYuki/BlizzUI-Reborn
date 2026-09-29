-- Retail-style HUD Edit Mode: manager window, per-system settings dialog,
-- selection overlays with snapping, keyboard nudging and layout management.
local A = BlizzUIReborn
local M, C = A.Media, A.Colors
local CATEGORIES = { "Frames", "Action Bars", "Combat", "Misc" }

-- ============================================================ helpers
function A:IsEditable(def)
    if def.editable and not def.editable() then return false end
    if def.kind == "compartment" then return self.draft.compartment and true or false end
    if def.kind == "status" then return self.draft.status and self:CarboniteActive() end
    return self:BindElement(def) ~= nil
end
function A:ElementEnabled(def)
    if def.kind == "bar" and def.barIndex > 1 then
        local e = self.draft.frames[def.id]
        local on
        if e and e.enabled ~= nil then on = e.enabled else on = A.BarVisibleSetting(def.barIndex) end
        -- bar 5 only exists while bar 4 is on (3.3.5)
        if def.barIndex == 5 and on then on = self:ElementEnabled(self.elements.action4) end
        return on
    end
    if def.toggle then
        local e = self.draft.frames[def.id]
        return not (e and e.enabled == false)
    end
    return self.db.editor.previews[def.id] ~= false
end

-- ============================================================ grid
function A:BuildGrid()
    if not self.grid then
        self.grid = CreateFrame("Frame", "BlizzUIRebornGrid", UIParent)
        self.grid:SetAllPoints(UIParent); self.grid:SetFrameStrata("BACKGROUND"); self.grid.lines = {}
    end
    local g = self.grid
    for _, l in ipairs(g.lines) do l:Hide() end
    if not self.editing or not self.db.editor.grid then g:Hide(); return end
    local W, H = UIParent:GetWidth(), UIParent:GetHeight()
    local sp, n = self.db.editor.spacing, 0
    local function line(x, y, w, h, center)
        n = n + 1
        local t = g.lines[n]
        if not t then t = g:CreateTexture(nil, "BACKGROUND"); g.lines[n] = t end
        t:ClearAllPoints(); t:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", x, y); A.Size(t, w, h)
        if center then t:SetTexture(.9, .45, .9, .5) else t:SetTexture(1, 1, 1, .12) end
        t:Show()
    end
    local cx, cy = W / 2, H / 2
    line(cx, 0, 1, H, true); line(0, cy, W, 1, true)
    local i = 1
    while cx - i * sp > 0 or cx + i * sp < W do
        if cx - i * sp > 0 then line(cx - i * sp, 0, 1, H) end
        if cx + i * sp < W then line(cx + i * sp, 0, 1, H) end
        i = i + 1
    end
    i = 1
    while cy - i * sp > 0 or cy + i * sp < H do
        if cy - i * sp > 0 then line(0, cy - i * sp, W, 1) end
        if cy + i * sp < H then line(0, cy + i * sp, W, 1) end
        i = i + 1
    end
    g:Show()
end

-- ============================================================ snapping
-- Returns the adjusted bottom-left for a rect being dragged (UIParent units).
function A:Snap(id, l, b, w, h)
    local W, H = UIParent:GetWidth(), UIParent:GetHeight()
    l, b = A.Clamp(l, 0, math.max(0, W - w)), A.Clamp(b, 0, math.max(0, H - h))
    if not self.db.editor.snap or IsShiftKeyDown() then return l, b end
    local range = 8
    local xs, ys = { 0, W / 2, W }, { 0, H / 2, H }
    if self.db.editor.grid then
        local sp = self.db.editor.spacing
        for k = -math.ceil(W / sp), math.ceil(W / sp) do local x = W / 2 + k * sp; if x >= 0 and x <= W then xs[#xs + 1] = x end end
        for k = -math.ceil(H / sp), math.ceil(H / sp) do local y = H / 2 + k * sp; if y >= 0 and y <= H then ys[#ys + 1] = y end end
    end
    for _, oid in ipairs(self.order) do
        local o = self.elements[oid]
        if oid ~= id and o.overlay and o.overlay:IsShown() and o.overlayRect then
            local r = o.overlayRect
            xs[#xs + 1] = r[1]; xs[#xs + 1] = r[1] + r[3]; xs[#xs + 1] = r[1] + r[3] / 2
            ys[#ys + 1] = r[2]; ys[#ys + 1] = r[2] + r[4]; ys[#ys + 1] = r[2] + r[4] / 2
        end
    end
    local bestX, dx = l, range
    for _, x in ipairs(xs) do
        for _, off in ipairs({ 0, w / 2, w }) do
            local d = math.abs(l + off - x)
            if d < dx then dx, bestX = d, x - off end
        end
    end
    local bestY, dy = b, range
    for _, y in ipairs(ys) do
        for _, off in ipairs({ 0, h / 2, h }) do
            local d = math.abs(b + off - y)
            if d < dy then dy, bestY = d, y - off end
        end
    end
    return A.Clamp(bestX, 0, math.max(0, W - w)), A.Clamp(bestY, 0, math.max(0, H - h))
end

-- ============================================================ overlays
local function overlayColors(o, def)
    local sel, hover = A.selected == def.id, o.hover
    local r, g, b = .2, .9, 1
    if sel then r, g, b = 1, .9, .1 end
    for _, e in ipairs(o.edges) do e:SetVertexColor(r, g, b, 1) end
    o.fill:SetVertexColor(sel and 1 or .1, sel and .9 or .85, sel and .05 or 1, hover and .32 or .22)
    o.label:SetTextColor(1, 1, 1, 1)
end
function A:MakeOverlay(def)
    local o = CreateFrame("Button", nil, UIParent)
    o:SetFrameStrata("DIALOG"); o:SetFrameLevel(20)
    o:EnableMouse(true)
    o:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    o.fill = o:CreateTexture(nil, "BACKGROUND"); o.fill:SetTexture(M.White); o.fill:SetAllPoints(o)
    -- 1px outline, as in the original build
    o.edges = {}
    for _, side in ipairs({ { "TOPLEFT", "TOPRIGHT", nil, 1 }, { "BOTTOMLEFT", "BOTTOMRIGHT", nil, 1 }, { "TOPLEFT", "BOTTOMLEFT", 1, nil }, { "TOPRIGHT", "BOTTOMRIGHT", 1, nil } }) do
        local e = o:CreateTexture(nil, "BORDER"); e:SetTexture(M.White)
        e:SetPoint(side[1], o, side[1]); e:SetPoint(side[2], o, side[2])
        if side[3] then e:SetWidth(side[3]) else e:SetHeight(side[4]) end
        o.edges[#o.edges + 1] = e
    end
    o.label = A.Text(o, 11, C.text, "OVERLAY"); o.label:SetPoint("CENTER", o, "CENTER", 0, 0); o.label:SetText(def.label)
    o:SetScript("OnEnter", function(self) self.hover = true; overlayColors(self, def) end)
    o:SetScript("OnLeave", function(self) self.hover = nil; overlayColors(self, def) end)
    o:SetScript("OnMouseDown", function(self, button)
        if button ~= "LeftButton" or A.Combat() or A:HasModal() then return end
        A:SelectElement(def.id)
        local cx, cy = A.Cursor()
        local l, b, w, h = A:ElementRect(def)
        local al, ab, aw, ah = A:AnchorRect(def)
        if not l or not al then return end
        A.drag = { id = def.id, cx = cx, cy = cy, rect = { l, b, w, h }, anchor = { al, ab, aw, ah }, settings = A.Copy(A:Settings(def)) }
        self:SetScript("OnUpdate", function() A:Run("Drag", A.UpdateDrag, A) end)
    end)
    o:SetScript("OnMouseUp", function(self) A:EndDrag() end)
    o:SetScript("OnHide", function(self) if A.drag and A.drag.id == def.id then A:EndDrag() end end)
    def.overlay = o
    overlayColors(o, def)
    return o
end
function A:UpdateDrag()
    local d = self.drag
    if not d then return end
    local def = self.elements[d.id]
    local cx, cy = A.Cursor()
    local mx, my = cx - d.cx, cy - d.cy
    if not d.moving then
        if math.abs(mx) < 3 and math.abs(my) < 3 then return end
        if def.kind == "cast" and d.settings.lock then
            d.blocked = true
            if not d.warned then d.warned = true; self:Print("Uncheck \"Lock to Player Frame\" to move the cast bar.") end
            return
        end
        d.moving = true
    end
    if def.kind == "status" then
        -- free movement around the map: the side follows the nearest edge
        if not d.first then d.first = A.Copy(self.statusFirst or { cx, cy }) end
        if mx == d.lastX and my == d.lastY then return end
        d.lastX, d.lastY = mx, my
        self:StatusDragTo(d.first[1] + mx, d.first[2] + my)
        self:UpdateOverlay(def)
        return
    end
    local r = d.rect
    local l, b = self:Snap(d.id, r[1] + mx, r[2] + my, r[3], r[4])
    mx, my = l - r[1], b - r[2]
    if mx == d.lastX and my == d.lastY then return end
    d.lastX, d.lastY = mx, my
    do
        local a = d.anchor
        local point, x, y = A.ToPosition(a[1] + mx, a[2] + my, a[3], a[4])
        self:SetPosition(d.id, point, x, y, true)
    end
    self:UpdateOverlay(def)
end
function A:EndDrag()
    local d = self.drag
    if not d then return end
    self.drag = nil
    local def = self.elements[d.id]
    if def.overlay then def.overlay:SetScript("OnUpdate", nil) end
    if d.moving then self:MarkDirty() end
end
function A:UpdateOverlay(def)
    local o = def.overlay
    local visible = self.editing and not self.keybinding and self:IsEditable(def) and self:ElementEnabled(def)
    if visible and not o then o = self:MakeOverlay(def) end
    if not o then return end
    if not visible then o:Hide(); return end
    local l, b, w, h = self:ElementRect(def)
    if not l then o:Hide(); return end
    w, h = math.max(w, 20), math.max(h, 16)
    local r = def.overlayRect
    if not r or math.abs(r[1] - l) > .05 or math.abs(r[2] - b) > .05 or math.abs(r[3] - w) > .05 or math.abs(r[4] - h) > .05 then
        o:ClearAllPoints(); o:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", l, b); A.Size(o, w, h)
        def.overlayRect = { l, b, w, h }
    end
    overlayColors(o, def)
    o:Show()
end
function A:UpdateOverlays()
    for _, id in ipairs(self.order) do self:UpdateOverlay(self.elements[id]) end
end
function A:OnElementApplied(def)
    if self.editing and def.overlay and not (self.drag and self.drag.id == def.id) then self:UpdateOverlay(def) end
end

-- ============================================================ nudging
function A:SetNudge(on)
    if not self.nudgeButton then
        local b = CreateFrame("Button", "BlizzUIRebornNudge", UIParent)
        b:SetScript("OnClick", function(_, key) A:Run("Nudge", A.Nudge, A, key) end)
        self.nudgeButton = b
    end
    if A.Combat() then return end
    ClearOverrideBindings(self.nudgeButton)
    if on then
        for _, k in ipairs({ "UP", "DOWN", "LEFT", "RIGHT" }) do
            SetOverrideBindingClick(self.nudgeButton, true, k, "BlizzUIRebornNudge", k)
            SetOverrideBindingClick(self.nudgeButton, true, "SHIFT-" .. k, "BlizzUIRebornNudge", "SHIFT-" .. k)
        end
    end
end
function A:Nudge(key)
    local id = self.selected
    if not id or not self.editing or A.Combat() then return end
    local def = self.elements[id]
    local step = key:find("SHIFT") and 10 or 1
    local dx = key:find("LEFT") and -step or key:find("RIGHT") and step or 0
    local dy = key:find("DOWN") and -step or key:find("UP") and step or 0
    if def.kind == "status" then
        local e = self:EnsureEntry(id)
        local R = A.STATUS_RANGE
        e.offsetX = A.Clamp(e.offsetX + dx, -R, R); e.offsetY = A.Clamp(e.offsetY + dy, -R, R)
        self:UpdateStatus()
    else
        if def.kind == "cast" and self:Settings(def).lock then return end
        local e = self:Settings(def)
        self:SetPosition(id, e.point, e.x + dx, e.y + dy, true)
    end
    self:UpdateOverlay(def)
    self:MarkDirty()
end

-- ============================================================ selection & settings dialog
function A:SelectElement(id)
    if A.Combat() then return end
    self.selected = id
    self:SetNudge(id ~= nil)
    self:ShowSettings()
    for _, oid in ipairs(self.order) do local d = self.elements[oid]; if d.overlay then overlayColors(d.overlay, d) end end
end
function A:Deselect()
    self.selected = nil
    self:SetNudge(false)
    if self.settingsDialog then self.settingsDialog:Hide() end
    for _, oid in ipairs(self.order) do local d = self.elements[oid]; if d.overlay then overlayColors(d.overlay, d) end end
end
local function buildSettingsDialog(self)
    local p = A.Panel("BlizzUIRebornEditModeSystem", UIParent, 380, 200, "", "DIALOG")
    p:SetFrameLevel(60)
    local pos = self.db.editor.settingsPos
    if pos then p:SetPoint(pos[1], UIParent, pos[1], pos[2], pos[3]) else p:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -40, -200) end
    p.OnMoved = function(f)
        local l, b, w, h = A.Rect(f)
        local point, x, y = A.ToPosition(l, b, w, h)
        A.db.editor.settingsPos = { point, x, y }
        A.PlaceAt(f, point, x, y)
    end
    p.OnClose = function() A:Deselect() end
    p.pages = {}
    return p
end
-- Choices for a dropdown setting (some depend on other settings, like the
-- Boss Timeline's icon direction on its orientation).
local function choicesOf(opt, e)
    return opt.choicesFor and opt.choicesFor(e) or opt.choices
end
local function currentOf(opt, e)
    if opt.current then return opt.current(e) end
    return e[opt.key]
end
local ROW = { check = 28, choice = 34, slider = 30 }
local function buildPage(self, dialog, def)
    local page = CreateFrame("Frame", nil, dialog)
    page:SetAllPoints(dialog)
    page.controls = {}
    for _, opt in ipairs(def.settings) do
        if not opt.hidden then
            local ctl, label
            if opt.kind == "check" then
                ctl = A.Check(page, opt.label, function(v) A:SetSetting(def.id, opt.key, v); A:RefreshSettings() end, 330)
            elseif opt.kind == "choice" then
                label = A.Text(page, 12, C.text); label:SetText(opt.label)
                ctl = A.Dropdown(page, 180, function()
                    local e = A:Settings(def)
                    local items, cur = {}, currentOf(opt, e)
                    for _, c in ipairs(choicesOf(opt, e)) do
                        items[#items + 1] = { text = c.label, checked = c.value == cur, func = function()
                            A:SetSetting(def.id, opt.key, c.value); A:RefreshSettings()
                        end }
                    end
                    return items
                end, function()
                    local e = A:Settings(def)
                    local cur = currentOf(opt, e)
                    for _, c in ipairs(choicesOf(opt, e)) do if c.value == cur then return c.label end end
                    return tostring(cur)
                end)
            else
                ctl = A.Slider(page, opt, function(v) A:SetSetting(def.id, opt.key, v) end, 130, 120)
            end
            page.controls[#page.controls + 1] = { ctl = ctl, opt = opt, label = label }
        end
    end
    page.revert = A.Button(page, "Revert Changes", 165, function() A:RevertElement(def.id); A:RefreshSettings() end)
    page.reset = A.Button(page, "Reset To Default Position", 165, function()
        if def.kind == "status" then A:SetSetting("status", "side", "auto"); A:SetSetting("status", "offsetX", 0); A:SetSetting("status", "offsetY", 0)
        else A:ResetPosition(def.id) end
        A:RefreshSettings()
    end)
    if def.kind == "bar" or def.id == "stance" or def.id == "petbar" then
        page.keybind = A.Button(page, "Quick Keybind Mode", 340, function() A:StartQuickKeybind() end)
    end
    page.def = def
    return page
end
-- Stacks the page's controls, skipping settings that don't apply right now
-- (opt.showIf), and sizes the dialog to fit.
local function layoutPage(page, e)
    local y = -46
    for _, c in ipairs(page.controls) do
        local opt, ctl = c.opt, c.ctl
        local shown = not opt.showIf or opt.showIf(e)
        A.Visible(ctl, shown)
        if c.label then A.Visible(c.label, shown) end
        if shown then
            ctl:ClearAllPoints()
            if opt.kind == "choice" then
                c.label:ClearAllPoints(); c.label:SetPoint("TOPLEFT", page, "TOPLEFT", 22, y - 6)
                ctl:SetPoint("TOPLEFT", page, "TOPLEFT", 160, y)
            else
                ctl:SetPoint("TOPLEFT", page, "TOPLEFT", 20, y)
            end
            y = y - ROW[opt.kind == "check" and "check" or opt.kind == "choice" and "choice" or "slider"]
        end
    end
    y = y - 8
    page.revert:ClearAllPoints(); page.revert:SetPoint("TOPLEFT", page, "TOPLEFT", 20, y)
    page.reset:ClearAllPoints(); page.reset:SetPoint("TOPRIGHT", page, "TOPRIGHT", -20, y)
    y = y - 30
    if page.keybind then
        page.keybind:ClearAllPoints(); page.keybind:SetPoint("TOPLEFT", page, "TOPLEFT", 20, y)
        y = y - 30
    end
    page.height = -y + 14
end
function A:ShowSettings()
    local def = self.elements[self.selected]
    if not def then return end
    self.settingsDialog = self.settingsDialog or buildSettingsDialog(self)
    local d = self.settingsDialog
    for _, pg in pairs(d.pages) do pg:Hide() end
    d.pages[def.id] = d.pages[def.id] or buildPage(self, d, def)
    local page = d.pages[def.id]
    d.title:SetText(def.label)
    layoutPage(page, self:Settings(def))
    d:SetHeight(page.height)
    page:Show()
    d:Show()
    self:RefreshSettings()
end
function A:RefreshSettings()
    local d = self.settingsDialog
    local def = self.selected and self.elements[self.selected]
    if not d or not d:IsShown() or not def then return end
    local page = d.pages[def.id]
    local e = self:Settings(def)
    layoutPage(page, e)
    d:SetHeight(page.height)
    for _, c in ipairs(page.controls) do
        local opt, ctl = c.opt, c.ctl
        if opt.kind == "check" then ctl:SetChecked(e[opt.key] and true or false)
        elseif opt.kind == "choice" then ctl:Refresh()
        else
            ctl:SetValue(e[opt.key])
            if opt.key == "rows" then ctl:SetLabel(e.orientation == "vertical" and "# of Columns" or "# of Rows") end
        end
    end
    local changed = not A.Equal(self.draft.frames[def.id], self.saved.frames[def.id])
    page.revert:SetEnabled(changed)
end

-- ============================================================ layout menu
function A:LayoutMenu()
    local act = self.char.active
    local items = { { text = "Presets", header = true } }
    for _, name in ipairs(self.PRESETS) do
        items[#items + 1] = { text = name, checked = act.scope == "preset" and act.name == name,
            func = function() A:RequestLayout("preset", name) end,
            gear = function(row) A:LayoutGear(row, "preset", name) end }
    end
    local list = self:LayoutList()
    if #list > 0 then
        items[#items + 1] = { separator = true }
        items[#items + 1] = { text = "Layouts", header = true }
        for _, l in ipairs(list) do
            items[#items + 1] = { text = l.name .. (l.scope == "character" and " |cff999999(Character)|r" or "")
                    .. (l.scope == "account" and A.db.defaultLayout == l.name and " |cff999999(Default)|r" or ""),
                checked = act.scope == l.scope and act.name == l.name,
                func = function() A:RequestLayout(l.scope, l.name) end,
                gear = function(row) A:LayoutGear(row, l.scope, l.name) end }
        end
    end
    items[#items + 1] = { separator = true }
    items[#items + 1] = { text = "Use Account Default" .. (A.db.defaultLayout and (" |cff999999(" .. A.db.defaultLayout .. ")|r") or " |cff999999(Modern)|r"),
        checked = A.char.layoutMode == "follow", func = function() A:WithUnsaved("Switch", function() A:FollowDefault() end) end }
    items[#items + 1] = { text = "New Layout", func = function() A:NewLayoutDialog() end }
    items[#items + 1] = { text = "Import Layout", func = function() A:ImportDialog() end }
    items[#items + 1] = { text = "Share Current Layout", func = function() A:ShareDialog() end }
    return items
end
function A:LayoutGear(row, scope, name)
    local items = { { text = name, header = true } }
    if scope ~= "preset" then
        items[#items + 1] = { text = "Rename", func = function() A:RenameDialog(scope, name) end }
    end
    if scope == "account" then
        local isDefault = A.db.defaultLayout == name
        items[#items + 1] = { text = "Default for All Characters", checked = isDefault, func = function()
            A:SetDefaultLayout(not isDefault and name or nil)
            A:Print(isDefault and ("\"" .. name .. "\" is no longer the default for other characters.")
                or ("\"" .. name .. "\" is now used by your other characters until they pick a layout."))
        end }
    elseif scope == "character" then
        items[#items + 1] = { text = "Make Account-Wide", func = function()
            local ok, err = A:MakeAccountWide(name)
            if ok then A:Print("\"" .. name .. "\" is now available on all your characters.") else A:Error(err) end
        end }
    end
    items[#items + 1] = { text = "Copy Layout", func = function() A:CopyDialog(scope, name) end }
    items[#items + 1] = { text = "Share", func = function()
        local data = scope == "preset" and A:PresetData(name) or A:Store(scope)[name]
        A:ShareDialog(data, name)
    end }
    if scope ~= "preset" then
        items[#items + 1] = { text = "|cffff6060Delete|r", func = function()
            A:Confirm("Delete Layout", "Delete the layout \"" .. name .. "\"? This cannot be undone.", {
                { text = "Delete", func = function() A:DeleteLayout(scope, name) end }, { text = "Cancel" } })
        end }
    end
    A.ShowMenu(row.gear, items, "TOPLEFT", "TOPRIGHT", 6, 0, 140)
end
function A:WithUnsaved(verb, after)
    if not self.dirty then after(); return end
    local where = self:IsPreset() and ("the " .. self:ActiveName() .. " preset") or ("\"" .. self:ActiveName() .. "\"")
    self:Confirm("Unsaved Changes", "You have unsaved changes to " .. where .. ".", {
        { text = "Save and " .. verb, func = function() A:SaveThen(after) end },
        { text = verb, func = function() A:Revert(); after() end },
        { text = "Cancel" },
    })
end
function A:SaveThen(after)
    if self:IsPreset() then
        self:NewLayoutDialog(after)
    else
        local ok, err = self:Save()
        if not ok then self:Error(err); return end
        if after then after() end
    end
end
function A:RequestLayout(scope, name)
    local act = self.char.active
    if act.scope == scope and act.name == name then return end
    self:WithUnsaved("Switch", function()
        local ok, err
        if scope == "preset" then ok, err = A:LoadPreset(name) else ok, err = A:LoadLayout(scope, name) end
        if not ok then A:Error(err) end
    end)
end
function A:NewLayoutDialog(after)
    local base = self:IsPreset() and self:ActiveName() or self:ActiveName()
    self:TextDialog({ title = "New Layout", label = "Name the new layout (based on " .. base .. "):", initial = self:UniqueName(base == "Modern" and "My Layout" or base),
        check = "Character Specific Layout", checked = false, acceptText = "Create",
        accept = function(text, charOnly)
            local ok, err = A:CreateLayout(text, charOnly)
            if ok and after then after() end
            return ok, err
        end })
end
function A:RenameDialog(scope, name)
    self:TextDialog({ title = "Rename Layout", label = "New name:", initial = name, acceptText = "Rename",
        accept = function(text) return A:RenameLayout(scope, name, text) end })
end
function A:CopyDialog(scope, name)
    self:TextDialog({ title = "Copy Layout", label = "Name for the copy:", initial = self:UniqueName(name == "Modern" and "My Layout" or name),
        check = "Character Specific Layout", checked = false, acceptText = "Copy",
        accept = function(text, charOnly)
            local go = function() local ok, err = A:CopyLayout(scope, name, text, charOnly); if not ok then A:Error(err) end end
            if A.dirty and not (A.char.active.scope == scope and A.char.active.name == name) then
                A:After(0, function() A:WithUnsaved("Copy", go) end)
                return true
            end
            return A:CopyLayout(scope, name, text, charOnly)
        end })
end
function A:ImportDialog()
    self:TextDialog({ title = "Import Layout", label = "Paste a BlizzUI Reborn layout string:", multiline = true, acceptText = "Import",
        accept = function(text)
            local data, name = A:Decode(text)
            if not data then return nil, name end
            A:After(0, function()
                A:WithUnsaved("Import", function()
                    A:TextDialog({ title = "Name Imported Layout", label = "Layout name:", initial = A:UniqueName(name ~= "" and name or "Imported Layout"),
                        check = "Character Specific Layout", checked = false, acceptText = "Import",
                        accept = function(n, charOnly) return A:CreateLayout(n, charOnly, data) end })
                end)
            end)
            return true
        end })
end
function A:ShareDialog(data, name)
    self:TextDialog({ title = "Share Layout", label = "Press Ctrl+C to copy, then share it with a friend:", multiline = true,
        initial = self:Export(data, name) })
end

-- ============================================================ manager window
function A:BuildEditor()
    local p = A.Panel("BlizzUIRebornEditMode", UIParent, 460, 580, "Edit Mode", "DIALOG")
    p:SetFrameLevel(40)
    local pos = self.db.editor.managerPos
    if pos then p:SetPoint(pos[1], UIParent, pos[1], pos[2], pos[3]) else p:SetPoint("LEFT", UIParent, "LEFT", 40, 60) end
    p.OnMoved = function(f)
        local l, b, w, h = A.Rect(f)
        local point, x, y = A.ToPosition(l, b, w, h)
        A.db.editor.managerPos = { point, x, y }
        A.PlaceAt(f, point, x, y)
    end
    p.OnClose = function() A:RequestExit() end
    self.editor = p

    local lbl = A.Text(p, 12, C.gold); lbl:SetPoint("TOPLEFT", p, "TOPLEFT", 22, -48); lbl:SetText("Layout:")
    p.layout = A.Dropdown(p, 350, function() return A:LayoutMenu() end, function()
        local name = A:ActiveName()
        if A:IsPreset() then name = name .. " |cff999999(Preset)|r" elseif A.char.active.scope == "character" then name = name .. " |cff999999(Character)|r" end
        return name .. (A.dirty and " |cffffd100*|r" or "")
    end)
    p.layout:SetPoint("TOPLEFT", p, "TOPLEFT", 84, -42)

    p.grid = A.Check(p, "Show Grid", function(v) A.db.editor.grid = v; p.spacing:SetEnabled(v); A:BuildGrid() end, 110)
    p.grid:SetPoint("TOPLEFT", p, "TOPLEFT", 18, -80)
    p.spacing = A.Slider(p, { label = "", min = 20, max = 200, step = 10, key = "spacing" }, function(v) A.db.editor.spacing = v; A:BuildGrid() end, 0, 150)
    p.spacing:SetPoint("TOPLEFT", p, "TOPLEFT", 150, -79)
    p.snap = A.Check(p, "Enable Snap", function(v) A.db.editor.snap = v end, 150)
    p.snap:SetPoint("TOPLEFT", p, "TOPLEFT", 18, -106)
    p.advanced = A.Check(p, "Advanced Options", function(v) A.db.editor.advanced = v; A:BuildCategoryList(); A:UpdateOverlays() end, 170)
    p.advanced:SetPoint("TOPLEFT", p, "TOPLEFT", 240, -106)

    local sep = p:CreateTexture(nil, "ARTWORK"); sep:SetTexture(M.White); sep:SetVertexColor(.65, .65, .6, .35)
    sep:SetPoint("TOPLEFT", p, "TOPLEFT", 18, -134); sep:SetPoint("TOPRIGHT", p, "TOPRIGHT", -18, -134); sep:SetHeight(1)

    p.scroll = A.ScrollArea(p, 424, 300)
    p.scroll:SetPoint("TOPLEFT", p, "TOPLEFT", 18, -142)
    p.checks, p.headers = {}, {}

    local sep2 = p:CreateTexture(nil, "ARTWORK"); sep2:SetTexture(M.White); sep2:SetVertexColor(.65, .65, .6, .35)
    sep2:SetPoint("TOPLEFT", p, "TOPLEFT", 18, -448); sep2:SetPoint("TOPRIGHT", p, "TOPRIGHT", -18, -448); sep2:SetHeight(1)
    p.compartment = A.Check(p, "Addon Compartment", function(v) A.draft.compartment = v; A:RefreshCompartment(); A:MarkDirty(); A:UpdateOverlays() end, 200)
    p.compartment:SetPoint("TOPLEFT", p, "TOPLEFT", 18, -456)
    p.status = A.Check(p, "Status Icons by Carbonite Map", function(v) A.draft.status = v; A:UpdateStatus(); A:MarkDirty(); A:UpdateOverlays() end, 220)
    p.status:SetPoint("TOPLEFT", p, "TOPLEFT", 230, -456)

    p.keybind = A.Button(p, "Quick Keybind Mode", 205, function() A:StartQuickKeybind() end)
    p.keybind:SetPoint("BOTTOMLEFT", p, "BOTTOMLEFT", 20, 50)
    p.options = A.Button(p, "Settings", 205, function() A:OpenOptions() end)
    p.options:SetPoint("BOTTOMRIGHT", p, "BOTTOMRIGHT", -20, 50)
    p.revert = A.Button(p, "Revert Changes", 205, function() A:Revert(); A:RefreshSettings() end)
    p.revert:SetPoint("BOTTOMLEFT", p, "BOTTOMLEFT", 20, 18)
    p.save = A.Button(p, "Save", 205, function() A:SaveThen() end)
    p.save:SetPoint("BOTTOMRIGHT", p, "BOTTOMRIGHT", -20, 18)
    p:Hide()

    -- Escape closes Edit Mode through this catcher (the manager itself is
    -- not a UISpecialFrame, so an open dialog/menu closes first).
    local esc = CreateFrame("Frame", "BlizzUIRebornEditModeEscape", UIParent)
    esc:Hide()
    esc:SetScript("OnHide", function(f)
        if not A.editing or A.closing then return end
        if A:HasModal() or A.MenuShown() or A.lastDialogClose == GetTime() then f:Show(); return end
        f:Show()
        A:After(0, function() A:RequestExit() end, "exit")
    end)
    table.insert(UISpecialFrames, "BlizzUIRebornEditModeEscape")
    self.escapeCatcher = esc
end
function A:BuildCategoryList()
    local p = self.editor
    local content = p.scroll.content
    for _, c in pairs(p.checks) do c:Hide() end
    for _, h in pairs(p.headers) do h:Hide() end
    local y = -2
    for _, cat in ipairs(CATEGORIES) do
        local ids = {}
        for _, id in ipairs(self.order) do
            local def = self.elements[id]
            -- the compartment and Carbonite status icons have their own toggles below the list
            if def.category == cat and (self.db.editor.advanced or def.basic) and def.kind ~= "status" and def.kind ~= "compartment" then
                ids[#ids + 1] = id
            end
        end
        if #ids > 0 then
            local h = p.headers[cat]
            if not h then h = A.Text(content, 13, C.gold); h:SetText(cat); p.headers[cat] = h end
            h:ClearAllPoints(); h:SetPoint("TOPLEFT", content, "TOPLEFT", 2, y); h:Show()
            y = y - 20
            for i, id in ipairs(ids) do
                local def = self.elements[id]
                local c = p.checks[id]
                if not c then
                    c = A.Check(content, def.label, function(v) A:ToggleElement(id, v) end, 200)
                    p.checks[id] = c
                end
                local col = (i - 1) % 2
                c:ClearAllPoints(); c:SetPoint("TOPLEFT", content, "TOPLEFT", col * 208, y)
                c:Show()
                if col == 1 or i == #ids then y = y - 24 end
            end
            y = y - 6
        end
    end
    content:SetHeight(-y + 4)
    p.scroll:Refresh()
    self:RefreshChecks()
end
function A:ToggleElement(id, v)
    local def = self.elements[id]
    if def.kind == "bar" and def.barIndex > 1 then
        -- keep 4/5 consistent: 5 needs 4, turning 4 off turns 5 off
        if def.barIndex == 5 and v then self:SetSetting("action4", "enabled", true) end
        self:SetSetting(id, "enabled", v)
        if def.barIndex == 4 and not v then self:SetSetting("action5", "enabled", false) end
        self:RefreshChecks(); self:UpdateOverlays()
    elseif def.toggle then
        self:SetSetting(id, "enabled", v)
    else
        self.db.editor.previews[id] = v
        if not v and self.selected == id then self:Deselect() end
    end
    self:UpdateOverlay(def)
end
function A:RefreshChecks()
    local p = self.editor
    if not p then return end
    for id, c in pairs(p.checks) do
        local def = self.elements[id]
        c:SetChecked(self:ElementEnabled(def))
        c:SetEnabled(self:IsEditable(def) and true or false)
    end
end
function A:RefreshEditor()
    local p = self.editor
    if not p then return end
    p.layout:Refresh()
    p.revert:SetEnabled(self.dirty and true or false)
    p.save:SetEnabled((self.dirty or false) and true or false)
    p.grid:SetChecked(self.db.editor.grid); p.spacing:SetValue(self.db.editor.spacing); p.spacing:SetEnabled(self.db.editor.grid)
    p.snap:SetChecked(self.db.editor.snap); p.advanced:SetChecked(self.db.editor.advanced)
    p.compartment:SetChecked(self.draft.compartment)
    p.status:SetChecked(self.draft.status); A.Visible(p.status, self:CarboniteActive())
    self:RefreshChecks()
    if self.editing then self:RefreshSettings() end
end
function A:OnLayoutChanged()
    if self.settingsDialog then self.settingsDialog:Hide() end
    self.selected = nil
    if self.editing then self:SetNudge(false); self:UpdateOverlays(); self:RefreshEditor() end
end

-- ============================================================ open / exit
function A:OpenEditor()
    if A.Combat() then self:Print("Edit Mode is not available in combat."); return end
    if self:Conflict() then self:Print("Edit Mode is paused while " .. self:Conflict() .. " is loaded. Choose one UI addon."); return end
    if not self.active then self:Print("Layout management is suspended. Type /br enable to resume."); return end
    if self.editing then return end
    if not self.editor then self:BuildEditor() end
    self.editing = true
    self.editor:Show()
    self.escapeCatcher:Show()
    self:BuildCategoryList()
    self:BuildGrid()
    self:RefreshEditor()
    if self.TimelineEditModeChanged then self:TimelineEditModeChanged() end
    self:UpdateOverlays()
    if GameMenuFrame and GameMenuFrame:IsShown() then HideUIPanel(GameMenuFrame) end
end
function A:FinishExit()
    self.closing = true
    self.editing = false
    self:EndDrag()
    self.drag, self.selected = nil, nil
    self:SetNudge(false)
    if self.StopQuickKeybind then self:StopQuickKeybind() end
    A.CloseMenu()
    if self.editor then self.editor:Hide() end
    if self.escapeCatcher then self.escapeCatcher:Hide() end
    if self.settingsDialog then self.settingsDialog:Hide() end
    for _, d in pairs(self.dialogs) do d:Hide() end
    self:BuildGrid()
    self:UpdateOverlays()
    if self.TimelineEditModeChanged then self:TimelineEditModeChanged() end
    self.closing = false
end
function A:RequestExit()
    if not self.editing then return end
    if self:HasModal() then return end
    self:EndDrag()
    self:WithUnsaved("Exit", function() A:FinishExit() end)
end

-- keep overlays following frames that move on their own (a target appearing,
-- the vehicle bar, chat docking...) while editing
A:Every(.25, function()
    if A.editing and not A.drag then A:UpdateOverlays() end
end)
