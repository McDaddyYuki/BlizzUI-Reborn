local A = BlizzUIReborn
local M, C = A.Media, A.Colors
local seq = 0
function A.Name(prefix) seq = seq + 1; return "BlizzUIReborn" .. prefix .. seq end

-- --------------------------------------------------------------- panel
function A.Panel(name, parent, w, h, title, strata)
    local p = CreateFrame("Frame", name, parent or UIParent)
    A.Size(p, w, h)
    p:SetFrameStrata(strata or "DIALOG")
    p:SetClampedToScreen(true)
    p:EnableMouse(true)
    p:SetMovable(true)
    p:SetToplevel(true)
    A.StylePanel(p)
    if title then
        p.title = A.Text(p, 14, C.gold)
        p.title:SetPoint("TOP", p, "TOP", 0, -14)
        p.title:SetText(title)
    end
    -- drag by the top strip (retail dialogs are movable by their header)
    local grip = CreateFrame("Frame", nil, p)
    grip:SetPoint("TOPLEFT", p, "TOPLEFT", 8, -4); grip:SetPoint("TOPRIGHT", p, "TOPRIGHT", -30, -4); grip:SetHeight(30)
    grip:EnableMouse(true); grip:RegisterForDrag("LeftButton")
    grip:SetScript("OnDragStart", function() p:StartMoving() end)
    grip:SetScript("OnDragStop", function() p:StopMovingOrSizing(); if p.OnMoved then p:OnMoved() end end)
    p.grip = grip
    local close = CreateFrame("Button", nil, p)
    A.Size(close, 32, 32); close:SetPoint("TOPRIGHT", p, "TOPRIGHT", 2, 2)
    close:SetNormalTexture(M.CloseUp); close:SetPushedTexture(M.CloseDown)
    close:SetHighlightTexture(M.CloseHighlight); close:GetHighlightTexture():SetBlendMode("ADD")
    close:SetScript("OnClick", function() if p.OnClose then A:Run("Close", p.OnClose, p) else p:Hide() end end)
    p.close = close
    return p
end

-- --------------------------------------------------------------- button
function A.Button(parent, text, w, fn, h)
    local b = CreateFrame("Button", A.Name("Button"), parent, "UIPanelButtonTemplate")
    A.Size(b, w or 140, h or 22)
    b:SetText(text or "")
    b.text = b:GetFontString()
    b:RegisterForClicks("LeftButtonUp")
    b:SetScript("OnClick", function(self, ...) PlaySound("igMainMenuOptionCheckBoxOn"); A:Run(text or "Button", fn, self, ...) end)
    function b:SetEnabled(v) A.Enable(self, v) end
    return b
end

-- --------------------------------------------------------------- checkbox
function A.Check(parent, label, fn, width)
    local b = CreateFrame("CheckButton", nil, parent)
    A.Size(b, 22, 22)
    A.Size(b, 24, 24)
    b:SetNormalTexture(M.CheckUp)
    b:SetPushedTexture(M.CheckDown)
    b:SetCheckedTexture(M.CheckMark)
    b:SetHighlightTexture(M.CheckHighlight); b:GetHighlightTexture():SetBlendMode("ADD")
    b.text = A.Text(b, 12, C.text)
    b.text:SetPoint("LEFT", b, "RIGHT", 4, 0)
    b.text:SetText(label or "")
    b.text:SetJustifyH("LEFT")
    if width then b.text:SetWidth(width - 28) end
    b:SetHitRectInsets(0, -((width or 150) - 24), 0, 0) -- clicking the label toggles too
    b:SetScript("OnClick", function(self)
        PlaySound(self:GetChecked() and "igMainMenuOptionCheckBoxOn" or "igMainMenuOptionCheckBoxOff")
        if fn then A:Run(label or "Checkbox", fn, self:GetChecked() and true or false, self) end
    end)
    function b:SetValue(v) self:SetChecked(v and true or false) end
    function b:SetEnabled(v)
        A.Enable(self, v)
        local c = v and C.text or C.dim
        self.text:SetTextColor(c[1], c[2], c[3])
    end
    return b
end

-- --------------------------------------------------------------- slider
-- Retail slider: label | [<] track [>] | value
function A.Slider(parent, opt, fn, labelWidth, trackWidth)
    local f = CreateFrame("Frame", nil, parent)
    labelWidth, trackWidth = labelWidth or 120, trackWidth or 130
    A.Size(f, labelWidth + trackWidth + 90, 24)
    f.label = A.Text(f, 12, C.text)
    f.label:SetPoint("LEFT", f, "LEFT", 0, 0); f.label:SetWidth(labelWidth); f.label:SetJustifyH("LEFT")
    f.label:SetText(opt.label or "")
    local s = CreateFrame("Slider", nil, f)
    A.Size(s, trackWidth, 16)
    s:SetPoint("LEFT", f, "LEFT", labelWidth + 6, 0)
    s:SetOrientation("HORIZONTAL")
    s:EnableMouse(true); s:EnableMouseWheel(true)
    s:SetBackdrop({ bgFile = M.SliderBg, edgeFile = M.SliderBorder, tile = true, tileSize = 8, edgeSize = 8,
        insets = { left = 3, right = 3, top = 6, bottom = 6 } })
    s:SetThumbTexture(M.SliderThumb)
    local thumb = s:GetThumbTexture(); A.Size(thumb, 32, 32)
    s:SetMinMaxValues(opt.min, opt.max)
    s:SetValueStep(opt.step)
    f.slider = s
    f.value = A.Text(f, 12, C.gold)
    f.value:SetPoint("LEFT", s, "RIGHT", 10, 0)
    local function snap(v) return A.Clamp(A.Round((v - opt.min) / opt.step) * opt.step + opt.min, opt.min, opt.max) end
    function f:SetValue(v)
        v = snap(v or opt.min)
        self.current = v
        self.loading = true; s:SetValue(v); self.loading = false
        self.value:SetText(A.Format(v) .. (opt.suffix or ""))
    end
    function f:GetValue() return self.current end
    function f:Step(dir) self:Commit(snap((self.current or opt.min) + dir * opt.step)) end
    function f:Commit(v)
        if v == self.current then return end
        self.current = v
        self.loading = true; s:SetValue(v); self.loading = false
        self.value:SetText(A.Format(v) .. (opt.suffix or ""))
        if fn then A:Run(opt.label or "Slider", fn, v) end
    end
    s:SetScript("OnValueChanged", function(_, v)
        if f.loading then return end
        f:Commit(snap(v))
    end)
    s:SetScript("OnMouseWheel", function(_, d) f:Step(d > 0 and 1 or -1) end)
    function f:SetEnabled(v)
        A.Enable(s, v)
        local c = v and C.text or C.dim
        self.label:SetTextColor(c[1], c[2], c[3]); self:SetAlpha(v and 1 or .6)
    end
    function f:SetLabel(t) self.label:SetText(t) end
    f:SetValue(opt.default or opt.min)
    return f
end

-- --------------------------------------------------------------- popup menu
-- Single shared menu used by every dropdown; closes on selection, Escape or
-- a click anywhere else (via a fullscreen catcher behind it).
local menu, catcher
local function buildMenu()
    catcher = CreateFrame("Button", "BlizzUIRebornMenuCatcher", UIParent)
    catcher:SetFrameStrata("FULLSCREEN_DIALOG"); catcher:SetFrameLevel(35)
    catcher:SetAllPoints(UIParent); catcher:EnableMouse(true); catcher:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    catcher:SetScript("OnClick", function() A.CloseMenu() end)
    catcher:Hide()
    menu = CreateFrame("Frame", "BlizzUIRebornMenu", UIParent)
    menu:SetFrameStrata("FULLSCREEN_DIALOG"); menu:SetFrameLevel(40); menu:SetClampedToScreen(true); menu:EnableMouse(true)
    A.StylePanel(menu)
    menu.rows = {}
    menu:SetScript("OnHide", function() catcher:Hide(); if menu.owner and menu.owner.arrow then menu.owner.arrow:SetVertexColor(1, 1, 1) end end)
    menu:Hide()
    table.insert(UISpecialFrames, "BlizzUIRebornMenu")
end
function A.CloseMenu() if menu and menu:IsShown() then menu:Hide() end end
function A.MenuShown() return menu and menu:IsShown() end
local function menuRow(i)
    local r = menu.rows[i]
    if r then return r end
    r = CreateFrame("Button", nil, menu)
    r:SetHeight(20)
    r.hl = r:CreateTexture(nil, "HIGHLIGHT"); r.hl:SetTexture(M.RowHighlight); r.hl:SetBlendMode("ADD"); r.hl:SetAllPoints(r)
    r.check = r:CreateTexture(nil, "ARTWORK"); A.Size(r.check, 14, 14); r.check:SetPoint("LEFT", r, "LEFT", 4, 0); r.check:SetTexture(M.CheckMark)
    r.text = A.Text(r, 12, C.text); r.text:SetPoint("LEFT", r, "LEFT", 22, 0); r.text:SetJustifyH("LEFT")
    -- "..." options button on each layout row
    r.gear = CreateFrame("Button", nil, r); A.Size(r.gear, 22, 16); r.gear:SetPoint("RIGHT", r, "RIGHT", -2, 0)
    r.gear.label = A.Text(r.gear, 12, C.gold); r.gear.label:SetPoint("CENTER", r.gear, "CENTER", 0, 3); r.gear.label:SetText("...")
    local gh = r.gear:CreateTexture(nil, "HIGHLIGHT"); gh:SetTexture(M.RowHighlight); gh:SetBlendMode("ADD"); gh:SetAllPoints(r.gear)
    r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    menu.rows[i] = r
    return r
end
-- items: { text=, header=, disabled=, checked=, func=, gear=function(row) } ; separator = { separator=true }
function A.ShowMenu(owner, items, anchorPoint, relPoint, x, y, minWidth)
    if not menu then buildMenu() end
    if menu:IsShown() and menu.owner == owner then menu:Hide(); return end
    -- a submenu opened from a row of this same menu cannot anchor to that row
    -- (it would anchor the menu to its own child), so pin it to screen coords
    local inside, p = false, owner
    while p do if p == menu then inside = true break end; p = p:GetParent() end
    local sx, sy
    if inside then
        local l, b, w, h = A.Rect(owner)
        if l then sx, sy = l + w + (x or 0), b + h + (y or 0) end
    end
    menu.owner = owner
    local width, yoff = minWidth or 160, -8
    for _, r in ipairs(menu.rows) do r:Hide() end
    for i, item in ipairs(items) do
        local r = menuRow(i)
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", menu, "TOPLEFT", 6, yoff); r:SetPoint("RIGHT", menu, "RIGHT", -6, 0)
        if item.separator then
            r:SetHeight(8); r.text:SetText(""); r.check:Hide(); r.gear:Hide(); r:EnableMouse(false); r.hl:Hide()
            yoff = yoff - 8
        else
            r:SetHeight(20); r.hl:Show()
            r.text:SetText(item.text)
            local c = item.header and C.gold or item.disabled and C.dim or C.text
            r.text:SetTextColor(c[1], c[2], c[3])
            r.text:SetPoint("LEFT", r, "LEFT", item.header and 6 or 22, 0)
            A.Visible(r.check, item.checked)
            r:EnableMouse(not item.header and not item.disabled)
            if item.gear then
                r.gear:Show()
                r.gear:SetScript("OnClick", function() A:Run("Layout options", item.gear, r) end)
            else r.gear:Hide() end
            r:SetScript("OnClick", function(_, button)
                if item.gear and button == "RightButton" then A:Run("Layout options", item.gear, r); return end
                menu:Hide()
                if item.func then A:Run(item.text or "Menu", item.func, item) end
            end)
            width = math.max(width, r.text:GetStringWidth() + (item.gear and 60 or 40))
            yoff = yoff - 20
        end
        r:Show()
    end
    A.Size(menu, width + 12, -yoff + 8)
    menu:ClearAllPoints()
    if sx then menu:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", sx, sy)
    else menu:SetPoint(anchorPoint or "TOPLEFT", owner, relPoint or "BOTTOMLEFT", x or 0, y or -2) end
    catcher:Show(); menu:Show()
    if owner.arrow then owner.arrow:SetVertexColor(1, .82, 0) end
    return menu
end

-- --------------------------------------------------------------- dropdown
function A.Dropdown(parent, width, getItems, getText)
    local d = CreateFrame("Button", nil, parent)
    A.Size(d, width, 26)
    A.StyleField(d)
    local hl = d:CreateTexture(nil, "HIGHLIGHT"); hl:SetTexture(M.RowHighlight); hl:SetBlendMode("ADD")
    hl:SetPoint("TOPLEFT", d, "TOPLEFT", 3, -3); hl:SetPoint("BOTTOMRIGHT", d, "BOTTOMRIGHT", -3, 3)
    d.text = A.Text(d, 12, C.text); d.text:SetPoint("LEFT", d, "LEFT", 10, 0); d.text:SetPoint("RIGHT", d, "RIGHT", -26, 0); d.text:SetJustifyH("LEFT")
    d.arrow = d:CreateTexture(nil, "ARTWORK"); A.Size(d.arrow, 22, 22); d.arrow:SetPoint("RIGHT", d, "RIGHT", -6, 0); d.arrow:SetTexture(M.Arrow)
    d:RegisterForClicks("LeftButtonUp")
    d:SetScript("OnClick", function(self)
        PlaySound("igMainMenuOptionCheckBoxOn")
        A.ShowMenu(self, getItems(), "TOPLEFT", "BOTTOMLEFT", 0, -2, width - 12)
    end)
    function d:Refresh() self.text:SetText(getText and getText() or "") end
    function d:SetEnabled(v) A.Enable(self, v); self:SetAlpha(v and 1 or .5) end
    d:Refresh()
    return d
end

-- --------------------------------------------------------------- edit box
function A.EditBox(parent, w, h, multiline)
    local holder = CreateFrame("Frame", nil, parent)
    A.Size(holder, w, h)
    A.StyleField(holder)
    local box = CreateFrame("EditBox", nil, multiline and nil or holder)
    box:SetFontObject(A.Font(12)); box:SetAutoFocus(false); box:SetMultiLine(multiline and true or false); box:EnableMouse(true)
    box:SetTextInsets(6, 6, 4, 4)
    box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    if multiline then
        local scroll = CreateFrame("ScrollFrame", nil, holder)
        scroll:SetPoint("TOPLEFT", holder, "TOPLEFT", 4, -4); scroll:SetPoint("BOTTOMRIGHT", holder, "BOTTOMRIGHT", -4, 4)
        box:SetWidth(w - 12); box:SetHeight(h - 8)
        scroll:SetScrollChild(box)
        scroll:EnableMouse(true); scroll:EnableMouseWheel(true)
        scroll:SetScript("OnMouseDown", function() box:SetFocus() end)
        scroll:SetScript("OnMouseWheel", function(self, d)
            local range = math.max(0, box:GetHeight() - self:GetHeight())
            self:SetVerticalScroll(A.Clamp(self:GetVerticalScroll() - d * 30, 0, range))
        end)
        box:SetScript("OnTextChanged", function(self)
            local _, lines = self:GetText():gsub("\n", "")
            self:SetHeight(math.max(h - 8, (lines + 2) * 14))
        end)
        box:SetScript("OnCursorChanged", function(self, _, y, _, ch)
            y = -(y or 0)
            local top = scroll:GetVerticalScroll()
            if y < top then scroll:SetVerticalScroll(y)
            elseif y + (ch or 14) > top + scroll:GetHeight() then scroll:SetVerticalScroll(y + (ch or 14) - scroll:GetHeight()) end
        end)
        holder.scroll = scroll
    else
        box:SetAllPoints(holder)
    end
    holder.box = box
    return holder
end

-- --------------------------------------------------------------- scroll area
function A.ScrollArea(parent, w, h)
    local scroll = CreateFrame("ScrollFrame", nil, parent)
    A.Size(scroll, w, h)
    local content = CreateFrame("Frame", nil, scroll)
    A.Size(content, w - 14, h)
    scroll:SetScrollChild(content)
    scroll:EnableMouseWheel(true)
    local bar = CreateFrame("Frame", nil, scroll)
    bar:SetPoint("TOPRIGHT", scroll, "TOPRIGHT", 0, 0); bar:SetPoint("BOTTOMRIGHT", scroll, "BOTTOMRIGHT", 0, 0); bar:SetWidth(6)
    local track = bar:CreateTexture(nil, "BACKGROUND"); track:SetTexture(M.White); track:SetVertexColor(1, 1, 1, .06); track:SetAllPoints(bar)
    local thumb = bar:CreateTexture(nil, "ARTWORK"); thumb:SetTexture(M.White); thumb:SetVertexColor(.6, .6, .6, .7); thumb:SetWidth(6)
    function scroll:Refresh()
        local range = math.max(0, content:GetHeight() - h)
        local v = A.Clamp(self:GetVerticalScroll(), 0, range)
        self:SetVerticalScroll(v)
        if range <= 0 then bar:Hide() else
            bar:Show()
            local th = math.max(20, h * h / content:GetHeight())
            thumb:SetHeight(th); thumb:ClearAllPoints(); thumb:SetPoint("TOP", bar, "TOP", 0, -(h - th) * v / range)
        end
    end
    scroll:SetScript("OnMouseWheel", function(self, d)
        local range = math.max(0, content:GetHeight() - h)
        self:SetVerticalScroll(A.Clamp(self:GetVerticalScroll() - d * 40, 0, range)); self:Refresh()
    end)
    scroll.content = content
    return scroll
end

-- --------------------------------------------------------------- dialogs
-- Every dialog is registered with UISpecialFrames, so Escape closes it. A
-- dialog closing never leaves modal state behind.
A.dialogs = {}
function A:HasModal()
    for _, d in pairs(self.dialogs) do if d:IsShown() then return true end end
    return false
end
-- Children must sit above their parent or they draw (and click) underneath it.
function A.RaiseChildren(f)
    local lvl = f:GetFrameLevel()
    for _, c in ipairs({ f:GetChildren() }) do
        if c:GetFrameLevel() <= lvl then c:SetFrameLevel(lvl + 1) end
        A.RaiseChildren(c)
    end
end
local function dialogFrame(key, w, h)
    local name = "BlizzUIRebornDialog" .. key
    local f = A.Panel(name, UIParent, w, h, "", "FULLSCREEN_DIALOG")
    -- low levels: 3.3.5 caps frame levels, and children of a frame at the cap
    -- draw under it (edit boxes and buttons hidden behind the dialog)
    f:SetFrameLevel(20)
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 80)
    f.OnClose = function(self) self:Hide() end
    f:SetScript("OnHide", function(self)
        A.lastDialogClose = GetTime()
        if self.box then self.box.box:ClearFocus() end
        local cb = self.onDismiss; self.onDismiss = nil
        if cb and not self.accepted then A:Run("Dialog", cb) end
    end)
    f:Hide()
    table.insert(UISpecialFrames, name)
    A.dialogs[key] = f
    return f
end
-- buttons = { {text=, func=}, ... } ; onDismiss runs when closed without a choice
function A:Confirm(title, body, buttons, onDismiss)
    local f = self.dialogs.Confirm or dialogFrame("Confirm", 420, 150)
    if not f.body then
        f.body = A.Text(f, 12, C.text); f.body:SetPoint("TOPLEFT", f, "TOPLEFT", 22, -44); f.body:SetPoint("TOPRIGHT", f, "TOPRIGHT", -22, -44)
        f.body:SetJustifyH("CENTER")
        f.buttons = {}
    end
    f.title:SetText(title); f.body:SetText(body)
    for _, b in ipairs(f.buttons) do b:Hide() end
    local n = #buttons
    local bw = math.min(130, (390 - (n - 1) * 8) / n)
    local total = n * bw + (n - 1) * 8
    for i, def in ipairs(buttons) do
        local b = f.buttons[i]
        if not b then
            b = A.Button(f, "", bw, function(btn) local d = btn.def; f.accepted = true; f:Hide(); f.accepted = nil; if d.func then d.func() end end)
            f.buttons[i] = b
        end
        b:SetWidth(bw); b.def = def; b.text:SetText(def.text); b:SetEnabled(true)
        b:ClearAllPoints(); b:SetPoint("BOTTOMLEFT", f, "BOTTOM", -total / 2 + (i - 1) * (bw + 8), 16)
        b:Show()
    end
    f.onDismiss = onDismiss
    A.RaiseChildren(f)
    f:Show()
    f:Raise()
    return f
end
-- opts: title, label, initial, multiline, readonly, check (label), checked, acceptText, accept(text, checked) -> ok, err
function A:TextDialog(opts)
    local key = opts.multiline and "Text" or "Name"
    local f = self.dialogs[key]
    if not f then
        f = dialogFrame(key, 460, opts.multiline and 360 or 190)
        f.label = A.Text(f, 12, C.text); f.label:SetPoint("TOPLEFT", f, "TOPLEFT", 22, -42); f.label:SetJustifyH("LEFT")
        f.box = A.EditBox(f, 416, opts.multiline and 220 or 28, opts.multiline)
        f.box:SetPoint("TOPLEFT", f, "TOPLEFT", 22, -60)
        f.check = A.Check(f, "", nil, 300)
        f.check:SetPoint("TOPLEFT", f.box, "BOTTOMLEFT", -2, -8)
        f.err = A.Text(f, 12, C.red); f.err:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 22, 48); f.err:SetJustifyH("LEFT"); f.err:SetWidth(416)
        f.ok = A.Button(f, "Accept", 120, function() f:Submit() end)
        f.ok:SetPoint("BOTTOMRIGHT", f, "BOTTOM", -4, 16)
        f.cancel = A.Button(f, "Cancel", 120, function() f:Hide() end)
        f.cancel:SetPoint("BOTTOMLEFT", f, "BOTTOM", 4, 16)
        function f:Submit()
            local o = self.opts
            if not o.accept then self:Hide(); return end
            local ok, err = o.accept(self.box.box:GetText(), self.check:GetChecked() and true or false)
            if ok and self.opts ~= o then return end -- the callback reopened this dialog for a follow-up step
            if ok then self.accepted = true; self:Hide(); self.accepted = nil
            else self.err:SetText(err or "Invalid value.") end
        end
        f.box.box:SetScript("OnEnterPressed", function(self) if not self:IsMultiLine() then A:Run("Accept", f.Submit, f) end end)
        f.box.box:SetScript("OnEscapePressed", function() f:Hide() end)
    end
    f.opts = opts
    f.title:SetText(opts.title or "")
    f.label:SetText(opts.label or "")
    f.err:SetText("")
    f.check:SetChecked(opts.checked and true or false)
    f.check.text:SetText(opts.check or "")
    A.Visible(f.check, opts.check ~= nil)
    f.ok.text:SetText(opts.acceptText or (opts.accept and "Accept" or "Close"))
    A.Visible(f.cancel, opts.accept ~= nil)
    f.ok:ClearAllPoints()
    if opts.accept then f.ok:SetPoint("BOTTOMRIGHT", f, "BOTTOM", -4, 16) else f.ok:SetPoint("BOTTOM", f, "BOTTOM", 0, 16) end
    f.onDismiss = opts.onDismiss
    A.RaiseChildren(f)
    f:Show()
    f:Raise()
    f.box.box:SetText(opts.initial or "")
    f.box.box:SetFocus(); f.box.box:HighlightText()
    return f
end
