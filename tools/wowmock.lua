-- Minimal WoW 3.3.5a API mock for headless testing of BlizzUI Reborn.
-- Only APIs that exist in 3.3.5 are provided: using a retail-only API
-- (SetShown, SetSize, SetColorTexture, C_Timer, Mixin, SetAtlas ...) errors.
-- The game runs Lua 5.1. The harness runs under Lua 5.1 (as in CI) or a
-- newer Lua; under a newer one, 5.1 globals are provided and the most
-- common 5.2+ conveniences are removed or made as strict as in 5.1, so code
-- that only works on newer Lua fails here too.
if _VERSION ~= "Lua 5.1" then
    unpack = unpack or table.unpack
    table.getn = table.getn or function(t) return #t end
    loadstring = loadstring or load
    math.mod = math.mod or math.fmod
    local load54, format54 = load, string.format
    -- 5.1's load() only takes a function
    load = function(chunk, ...)
        if type(chunk) ~= "function" then error("bad argument #1 to 'load' (function expected, got " .. type(chunk) .. ")", 2) end
        return load54(chunk, ...)
    end
    table.unpack, table.pack, table.move, math.type, rawlen, utf8 = nil, nil, nil, nil, nil, nil
    string.pack, string.unpack, string.packsize = nil, nil, nil
    -- 5.1's %s only accepts strings and numbers (5.2+ calls tostring on anything)
    string.format = function(fmt, ...)
        local n, i = select("#", ...), 0
        for spec in tostring(fmt):gmatch("%%[-+ #0]*%d*%.?%d*([%a%%])") do
            if spec ~= "%" then
                i = i + 1
                local v = select(i, ...)
                if spec == "s" and type(v) ~= "string" and type(v) ~= "number" then
                    error("bad argument #" .. (i + 1) .. " to 'format' (string expected, got " .. (i > n and "no value" or type(v)) .. ")", 2)
                end
            end
        end
        return format54(fmt, ...)
    end
    format = string.format
end

local M = { frames = {}, named = {}, blocked = {}, messages = {}, errors = {}, onupdate = {}, events = {}, hooks = {} }
MOCK = M
M.combat = false
M.cursorX, M.cursorY = 0, 0
M.time = 0
M.screenW, M.screenH = 1920, 1080

local strataOrder = { BACKGROUND=1, LOW=2, MEDIUM=3, HIGH=4, DIALOG=5, FULLSCREEN=6, FULLSCREEN_DIALOG=7, TOOLTIP=8 }

-- ---------------------------------------------------------------- objects
local Object = {}
Object.__index = function(t, k)
    local cls = rawget(t, "__class")
    local v = cls and cls[k]
    if v ~= nil then return v end
    return nil
end

local classes = {}
local function class(name, parent)
    local c = {}
    classes[name] = c
    if parent then setmetatable(c, { __index = classes[parent] }) end
    return c
end

local UIObject = class("UIObject")
function UIObject:GetName() return self.__name end
function UIObject:GetObjectType() return self.__type end
function UIObject:IsObjectType(t) return self.__type == t or (t == "Frame" and self.__isframe) or (t=="Region") end
function UIObject:GetParent() return self.__parent end

local function newObject(cls, otype, name, parent)
    local o = { __class = classes[cls], __type = otype, __name = name, __parent = parent, __points = {},
        __shown = true, __alpha = 1, __scale = 1, __scripts = {} }
    setmetatable(o, Object)
    if name then _G[name] = o; M.named[name] = o end
    M.frames[#M.frames + 1] = o
    return o
end
M.newObject = newObject

-- ------------------------------------------------------------ region basics
local Region = class("Region", "UIObject")

M.secureDepth = 0
local function protectedCheck(self, method)
    if M.combat and M.secureDepth == 0 and self:IsProtected() then
        M.blocked[#M.blocked + 1] = (self:GetName() or "anon") .. ":" .. method
        error("ADDON_ACTION_BLOCKED: " .. tostring(self:GetName()) .. ":" .. method, 3)
    end
end
M.protectedCheck = protectedCheck

function Region:IsProtected()
    if self.__protected then return true, true end
    if self.__anchoredProtected then return true, false end
    return nil
end
function Region:SetParent(p)
    protectedCheck(self, "SetParent")
    if type(p) == "string" then p = _G[p] end
    local wasVisible = self:IsVisible()
    if self.__parent and self.__parent.__children then
        for i, c in ipairs(self.__parent.__children) do if c == self then table.remove(self.__parent.__children, i) break end end
    end
    self.__parent = p
    if p then p.__children = p.__children or {}; table.insert(p.__children, self) end
    if self.__isframe then M.visibilityChanged(self, wasVisible) end
end

local function resolveRel(rel)
    if type(rel) == "string" then
        local r = _G[rel]; if not r then error("SetPoint: unknown relative frame " .. rel, 3) end
        return r
    end
    return rel
end
local validPoints = { TOPLEFT=1, TOP=1, TOPRIGHT=1, LEFT=1, CENTER=1, RIGHT=1, BOTTOMLEFT=1, BOTTOM=1, BOTTOMRIGHT=1 }
function Region:SetPoint(point, a, b, c, d)
    protectedCheck(self, "SetPoint")
    if not validPoints[point] then error("SetPoint: invalid point " .. tostring(point), 2) end
    local rel, relPoint, x, y
    if a == nil then rel, relPoint, x, y = self.__parent, point, 0, 0
    elseif type(a) == "number" then rel, relPoint, x, y = self.__parent, point, a, b or 0
    else
        rel = resolveRel(a)
        if type(b) == "number" or b == nil then relPoint, x, y = point, b or 0, c or 0
        else relPoint, x, y = b, c or 0, d or 0 end
    end
    if rel == nil then rel = UIParent end
    if not validPoints[relPoint] then error("SetPoint: invalid relative point " .. tostring(relPoint), 2) end
    if rel == self then error("SetPoint: cannot anchor to itself", 2) end
    -- dependency cycle check
    local seen = {}
    local function dependsOn(f, target, depth)
        if depth > 60 then return true end
        if f == target then return true end
        if not f or seen[f] then return false end
        seen[f] = true
        for _, p in ipairs(f.__points or {}) do if dependsOn(p[2], target, depth + 1) then return true end end
        return false
    end
    if dependsOn(rel, self, 0) then error("SetPoint: anchor family connection would create a loop", 2) end
    if type(x) ~= "number" or type(y) ~= "number" then error("SetPoint: bad offsets", 2) end
    if x ~= x or y ~= y then error("SetPoint: NaN offset", 2) end
    for i, p in ipairs(self.__points) do
        if p[1] == point then table.remove(self.__points, i) break end
    end
    table.insert(self.__points, { point, rel, relPoint, x, y })
    if self:IsProtected() and rel and rel.__isframe and not rel.__protected then rel.__anchoredProtected = true end
end
function Region:ClearAllPoints() protectedCheck(self, "ClearAllPoints"); self.__points = {} end
function Region:SetAllPoints(rel)
    rel = resolveRel(rel) or self.__parent
    self:ClearAllPoints(); self:SetPoint("TOPLEFT", rel, "TOPLEFT", 0, 0); self:SetPoint("BOTTOMRIGHT", rel, "BOTTOMRIGHT", 0, 0)
end
function Region:GetNumPoints() return #self.__points end
function Region:GetPoint(i)
    local p = self.__points[i or 1]
    if not p then return nil end
    return p[1], p[2], p[3], p[4], p[5]
end
function Region:SetWidth(w)
    protectedCheck(self, "SetWidth")
    if type(w) ~= "number" or w ~= w then error("SetWidth: bad value", 2) end
    self.__width = w
end
function Region:SetHeight(h)
    protectedCheck(self, "SetHeight")
    if type(h) ~= "number" or h ~= h then error("SetHeight: bad value", 2) end
    self.__height = h
end
function Region:GetEffectiveScale()
    local s = self.__scale or 1
    local p = self.__parent
    if self.__isframe then
        while p do s = s * (p.__scale or 1); p = p.__parent end
    else
        return p and p:GetEffectiveScale() or 1
    end
    return s
end

-- rect in screen pixels
function M.rect(f, depth)
    depth = (depth or 0) + 1
    if depth > 80 then error("anchor recursion") end
    if f == UIParent or f == WorldFrame then
        return 0, 0, M.screenW, M.screenH
    end
    local s = f:GetEffectiveScale()
    if #f.__points == 0 then return nil end
    local L, R, CX, T, B, CY
    for _, p in ipairs(f.__points) do
        local rl, rb, rw, rh = M.rect(p[2], depth)
        if not rl then return nil end
        local rp = p[3]
        local ax = rp:find("LEFT") and rl or rp:find("RIGHT") and rl + rw or rl + rw / 2
        local ay = rp:find("TOP") and rb + rh or rp:find("BOTTOM") and rb or rb + rh / 2
        ax, ay = ax + p[4] * s, ay + p[5] * s
        local pt = p[1]
        if pt:find("LEFT") then L = ax elseif pt:find("RIGHT") then R = ax else CX = ax end
        if pt:find("TOP") then T = ay elseif pt:find("BOTTOM") then B = ay else CY = ay end
    end
    local w = (f.__width or 0) * s
    local h = (f.__height or 0) * s
    local l, b
    if L and R then l, w = L, R - L elseif L then l = L elseif R then l = R - w elseif CX then l = CX - w / 2 else return nil end
    if B and T then b, h = B, T - B elseif B then b = B elseif T then b = T - h elseif CY then b = CY - h / 2 else return nil end
    return l, b, w, h
end
function Region:GetLeft() local l, b, w, h = M.rect(self); if l then return l / self:GetEffectiveScale() end end
function Region:GetRight() local l, b, w, h = M.rect(self); if l then return (l + w) / self:GetEffectiveScale() end end
function Region:GetBottom() local l, b, w, h = M.rect(self); if l then return b / self:GetEffectiveScale() end end
function Region:GetTop() local l, b, w, h = M.rect(self); if l then return (b + h) / self:GetEffectiveScale() end end
function Region:GetCenter()
    local l, b, w, h = M.rect(self); if not l then return end
    local s = self:GetEffectiveScale(); return (l + w / 2) / s, (b + h / 2) / s
end
function Region:GetRect()
    local l, b, w, h = M.rect(self); if not l then return end
    local s = self:GetEffectiveScale(); return l / s, b / s, w / s, h / s
end
function Region:GetWidth()
    if self == UIParent then return M.screenW / self:GetEffectiveScale() end
    local l, b, w, h = M.rect(self)
    if l and #self.__points > 1 then return w / self:GetEffectiveScale() end
    return self.__width or 0
end
function Region:GetHeight()
    if self == UIParent then return M.screenH / self:GetEffectiveScale() end
    local l, b, w, h = M.rect(self)
    if l and #self.__points > 1 then return h / self:GetEffectiveScale() end
    return self.__height or 0
end
function Region:SetAlpha(a)
    if type(a) ~= "number" then error("SetAlpha: number expected", 2) end
    self.__alpha = math.max(0, math.min(1, a))
end
function Region:GetAlpha() return self.__alpha end
function Region:IsShown() return self.__shown and 1 or nil end
function Region:IsVisible()
    if not self.__shown then return nil end
    local p = self.__parent
    while p do if not p.__shown then return nil end; p = p.__parent end
    return 1
end
function Region:Show()
    if self.__isframe then protectedCheck(self, "Show") end
    if self.__shown then return end
    local was = self:IsVisible()
    self.__shown = true
    if self.__isframe then M.visibilityChanged(self, was) end
end
function Region:Hide()
    if self.__isframe then protectedCheck(self, "Hide") end
    if not self.__shown then return end
    local was = self:IsVisible()
    self.__shown = false
    if self.__isframe then M.visibilityChanged(self, was) end
end
function Region:SetDrawLayer(layer) self.__layer = layer end
function Region:GetDrawLayer() return self.__layer or "ARTWORK" end
function Region:SetVertexColor(r, g, b, a) self.__vc = { r, g, b, a or 1 } end
function Region:GetVertexColor() local v = self.__vc or { 1, 1, 1, 1 }; return v[1], v[2], v[3], v[4] end

function M.visibilityChanged(frame, wasVisible)
    local now = frame:IsVisible()
    if (now and true or false) == (wasVisible and true or false) then return end
    local function walk(f, show)
        if f.__isframe then
            if show and f.__shown then
                local fn = f.__scripts.OnShow; if fn then M.call(fn, f) end
            elseif not show and f.__shown then
                local fn = f.__scripts.OnHide; if fn then M.call(fn, f) end
            end
            if f.__shown then for _, c in ipairs(f.__children or {}) do walk(c, show) end end
        end
    end
    -- the frame itself toggled: fire on it and visible descendants
    local fn
    if now then fn = frame.__scripts.OnShow else fn = frame.__scripts.OnHide end
    if fn then M.call(fn, frame) end
    for _, c in ipairs(frame.__children or {}) do walk(c, now) end
end

function M.call(fn, ...)
    -- 5.1's xpcall passes no extra arguments
    local n, args = select("#", ...), { ... }
    local ok, err = xpcall(function() return fn(unpack(args, 1, n)) end, debug.traceback)
    if not ok then M.errors[#M.errors + 1] = err; if M.onError then M.onError(err) end end
    return ok
end

-- ------------------------------------------------------------ texture/font
local Texture = class("Texture", "Region")
function Texture:SetTexture(a, g, b, al)
    if type(a) == "number" then self.__color = { a, g, b, al or 1 }; self.__tex = nil
    else
        if a ~= nil and type(a) ~= "string" then error("SetTexture: bad path", 2) end
        self.__tex = a; self.__color = nil
    end
    return 1
end
function Texture:GetTexture() return self.__tex end
function Texture:SetTexCoord(...)
    local n = select("#", ...)
    if n ~= 4 and n ~= 8 then error("SetTexCoord: 4 or 8 args", 2) end
    local a = { ... }
    -- 4 args are (left, right, top, bottom); stored as the 8 corner values the client returns
    if n == 4 then a = { a[1], a[3], a[1], a[4], a[2], a[3], a[2], a[4] } end
    self.__coords = a
end
function Texture:GetTexCoord() return unpack(self.__coords or { 0, 0, 0, 1, 1, 0, 1, 1 }) end
function Texture:SetBlendMode(m) self.__blend = m end
function Texture:SetDesaturated(d) self.__desat = d; return 1 end
function Texture:SetGradient(o, ...) self.__grad = { o, ... } end
function Texture:SetGradientAlpha(o, ...) self.__grad = { o, ... } end
function Texture:SetNonBlocking() end
function Texture:SetRotation(r) self.__rot = r end

local FontString = class("FontString", "Region")
function FontString:SetText(t) self.__text = t ~= nil and tostring(t) or nil end
function FontString:GetText() return self.__text end
function FontString:SetFormattedText(fmt, ...) self.__text = string.format(fmt, ...) end
function FontString:SetFont(path, size, flags)
    if type(path) ~= "string" or type(size) ~= "number" then error("SetFont: bad args", 2) end
    self.__font = { path, size, flags }; return 1
end
function FontString:GetFont() local f = self.__font or { "Fonts\\FRIZQT__.TTF", 12 }; return f[1], f[2], f[3] end
function FontString:SetFontObject(o)
    if type(o) == "string" then o = _G[o] end
    if type(o) ~= "table" then error("SetFontObject: bad font object", 2) end
    self.__fontObject = o
end
function FontString:GetFontObject() return self.__fontObject end
function FontString:SetTextColor(r, g, b, a) self.__textColor = { r, g, b, a } end
function FontString:GetTextColor() local c = self.__textColor or { 1, 1, 1, 1 }; return c[1], c[2], c[3], c[4] end
function FontString:SetJustifyH(j) self.__jh = j end
function FontString:SetJustifyV(j) self.__jv = j end
function FontString:GetStringWidth() return #(self.__text or "") * 6 end
function FontString:GetStringHeight() return 12 end
function FontString:SetShadowOffset() end
function FontString:SetShadowColor() end
function FontString:SetNonSpaceWrap() end
function FontString:SetSpacing() end

-- ------------------------------------------------------------ frames
local Frame = class("Frame", "Region")
function Frame:SetScript(name, fn)
    if fn ~= nil and type(fn) ~= "function" then error("SetScript: function expected", 2) end
    if not self.__validScripts[name] then error(self.__type .. " has no script " .. tostring(name), 2) end
    self.__scripts[name] = fn
    if name == "OnUpdate" then M.onupdate[self] = fn and true or nil end
end
function Frame:GetScript(name) return self.__scripts[name] end
function Frame:HookScript(name, fn)
    if not self.__validScripts[name] then error(self.__type .. " has no script " .. tostring(name), 2) end
    local old = self.__scripts[name]
    if old then self.__scripts[name] = function(...) old(...); return fn(...) end
    else self.__scripts[name] = fn end
    if name == "OnUpdate" then M.onupdate[self] = true end
end
function Frame:RegisterEvent(e) M.events[e] = M.events[e] or {}; M.events[e][self] = true end
function Frame:UnregisterEvent(e) if M.events[e] then M.events[e][self] = nil end end
function Frame:UnregisterAllEvents() for _, t in pairs(M.events) do t[self] = nil end end
function Frame:IsEventRegistered(e) return M.events[e] and M.events[e][self] and 1 or nil end
function Frame:SetScale(s)
    protectedCheck(self, "SetScale")
    if type(s) ~= "number" or s <= 0 or s ~= s then error("SetScale: bad scale " .. tostring(s), 2) end
    self.__scale = s
end
function Frame:GetScale() return self.__scale end
function Frame:SetFrameStrata(s) if not strataOrder[s] then error("bad strata " .. tostring(s), 2) end; self.__strata = s end
function Frame:GetFrameStrata() return self.__strata or (self.__parent and self.__parent.GetFrameStrata and self.__parent:GetFrameStrata()) or "MEDIUM" end
-- 3.3.5 caps frame levels; a frame at the cap has children at the same level
M.MAX_FRAME_LEVEL = 129
function Frame:SetFrameLevel(l) self.__level = math.min(l, M.MAX_FRAME_LEVEL) end
function Frame:GetFrameLevel()
    return self.__level or math.min(M.MAX_FRAME_LEVEL, (self.__parent and self.__parent.GetFrameLevel and self.__parent:GetFrameLevel() or 0) + 1)
end
function Frame:EnableMouse(e) protectedCheck(self, "EnableMouse"); self.__mouse = e and true or false end
function Frame:IsMouseEnabled() return self.__mouse and 1 or nil end
function Frame:EnableMouseWheel(e) self.__wheel = e and true or false end
function Frame:IsMouseWheelEnabled() return self.__wheel and 1 or nil end
function Frame:EnableKeyboard(e) self.__keyboard = e and true or false end
function Frame:IsKeyboardEnabled() return self.__keyboard and 1 or nil end
function Frame:SetMovable(m) self.__movable = m and true or false end
function Frame:IsMovable() return self.__movable and 1 or nil end
function Frame:SetResizable(m) self.__resizable = m end
function Frame:SetUserPlaced(u)
    if not self.__movable then error("Frame " .. tostring(self.__name) .. " is not movable", 2) end
    self.__userPlaced = u and true or false
end
function Frame:IsUserPlaced() return self.__userPlaced and 1 or nil end
function Frame:SetClampedToScreen(c) self.__clamped = c end
function Frame:SetClampRectInsets() end
function Frame:SetToplevel(t) self.__toplevel = t end
function Frame:Raise() end
function Frame:Lower() end
function Frame:SetHitRectInsets() end
function Frame:RegisterForDrag(...) self.__drag = { ... } end
function Frame:StartMoving()
    local l, b = M.rect(self)
    if not l then return end
    self.__moving = { l - M.cursorX, b - M.cursorY }
end
function Frame:StopMovingOrSizing()
    if self.__moving then M.updateMoving(self); self.__moving = nil end
end
function M.updateMoving(f)
    local mv = f.__moving
    if not mv then return end
    local s = f:GetEffectiveScale()
    f.__points = {}
    table.insert(f.__points, { "BOTTOMLEFT", UIParent, "BOTTOMLEFT", (M.cursorX + mv[1]) / s, (M.cursorY + mv[2]) / s })
end
function Frame:SetBackdrop(b) self.__backdrop = b end
function Frame:GetBackdrop() return self.__backdrop end
function Frame:SetBackdropColor(...) self.__bdColor = { ... } end
function Frame:SetBackdropBorderColor(...) self.__bdBorder = { ... } end
function Frame:GetBackdropColor() return unpack(self.__bdColor or { 1, 1, 1, 1 }) end
function Frame:SetAttribute(k, v) protectedCheck(self, "SetAttribute"); self.__attr = self.__attr or {}; self.__attr[k] = v end
function Frame:GetAttribute(k) return self.__attr and self.__attr[k] end
function Frame:SetID(i) self.__id = i end
function Frame:GetID() return self.__id or 0 end
function Frame:GetChildren() return unpack(self.__children or {}) end
function Frame:GetNumChildren() return #(self.__children or {}) end
function Frame:GetRegions() return unpack(self.__regions or {}) end
function Frame:IsMouseOver() return self.__mouseOver and 1 or nil end
function Frame:SetMaxResize() end
function Frame:SetMinResize() end
function Frame:CreateTexture(name, layer, template)
    if template then error("mock: texture templates unsupported", 2) end
    local t = newObject("Texture", "Texture", name, self)
    t.__layer = layer
    self.__regions = self.__regions or {}; table.insert(self.__regions, t)
    return t
end
function Frame:CreateFontString(name, layer, template)
    local t = newObject("FontString", "FontString", name, self)
    if template then
        local fo = _G[template]
        if type(fo) ~= "table" then error("unknown font template " .. tostring(template), 2) end
        t.__fontObject = fo
    end
    t.__layer = layer
    self.__regions = self.__regions or {}; table.insert(self.__regions, t)
    return t
end
function Frame:CreateTitleRegion() return self:CreateTexture() end

local Button = class("Button", "Frame")
function Button:SetText(t)
    if not self.__fs then self.__fs = self:CreateFontString() end
    self.__fs:SetText(t)
end
function Button:GetText() return self.__fs and self.__fs:GetText() end
function Button:SetFontString(fs) self.__fs = fs end
function Button:GetFontString() return self.__fs end
function Button:SetFormattedText(...) self:SetText(string.format(...)) end
local function texSetter(key)
    return function(self, t)
        if type(t) == "table" then self[key] = t; return end
        if t == nil then self[key] = nil; return end
        if not self[key] then self[key] = self:CreateTexture(); self[key]:SetAllPoints(self) end
        self[key]:SetTexture(t)
    end
end
Button.SetNormalTexture = texSetter("__normal")
Button.SetPushedTexture = texSetter("__pushed")
Button.SetHighlightTexture = texSetter("__highlight")
Button.SetDisabledTexture = texSetter("__disabled")
function Button:GetNormalTexture() return self.__normal end
function Button:GetPushedTexture() return self.__pushed end
function Button:GetHighlightTexture() return self.__highlight end
function Button:GetDisabledTexture() return self.__disabled end
function Button:SetNormalFontObject(o) self.__nfo = o end
function Button:SetHighlightFontObject(o) self.__hfo = o end
function Button:SetDisabledFontObject(o) self.__dfo = o end
function Button:SetTextFontObject(o) self.__nfo = o end
function Button:RegisterForClicks(...) self.__clicks = { ... } end
function Button:Enable() self.__disabledState = false end
function Button:Disable() self.__disabledState = true end
function Button:IsEnabled() return (not self.__disabledState) and 1 or nil end
function Button:LockHighlight() end
function Button:UnlockHighlight() end
function Button:SetButtonState(s) self.__state = s end
function Button:GetButtonState() return self.__state or "NORMAL" end
function Button:Click(btn)
    local fn = self.__scripts.OnClick
    if fn then fn(self, btn or "LeftButton", false) end
end

local CheckButton = class("CheckButton", "Button")
function CheckButton:SetChecked(c) self.__checked = c and true or false end
function CheckButton:GetChecked() return self.__checked and 1 or nil end
CheckButton.SetCheckedTexture = texSetter("__checkedTex")
CheckButton.SetDisabledCheckedTexture = texSetter("__dcheckedTex")
function CheckButton:GetCheckedTexture() return self.__checkedTex end

local Slider = class("Slider", "Frame")
function Slider:SetMinMaxValues(a, b) self.__min, self.__max = a, b; if self.__value then self:SetValue(self.__value) end end
function Slider:GetMinMaxValues() return self.__min or 0, self.__max or 0 end
function Slider:SetValueStep(s) self.__step = s end
function Slider:GetValueStep() return self.__step or 0 end
function Slider:SetValue(v)
    if type(v) ~= "number" then error("Slider:SetValue number expected, got " .. type(v), 2) end
    v = math.max(self.__min or v, math.min(self.__max or v, v))
    local changed = v ~= self.__value
    self.__value = v
    if changed and self.__scripts.OnValueChanged then self.__scripts.OnValueChanged(self, v) end
end
function Slider:GetValue() return self.__value or 0 end
function Slider:SetOrientation(o) self.__orient = o end
function Slider:SetThumbTexture(t)
    if type(t) == "table" then self.__thumb = t else
        if not self.__thumb then self.__thumb = self:CreateTexture(); self.__thumb:SetPoint("CENTER", self, "LEFT", 0, 0) end
        self.__thumb:SetTexture(t)
    end
end
function Slider:GetThumbTexture() return self.__thumb end
function Slider:Enable() self.__disabledState = false end
function Slider:Disable() self.__disabledState = true end
function Slider:IsEnabled() return (not self.__disabledState) and 1 or nil end

local StatusBar = class("StatusBar", "Frame")
function StatusBar:SetStatusBarTexture(t, layer)
    if type(t) == "table" then self.__sbt = t else
        if not self.__sbt then self.__sbt = self:CreateTexture(); self.__sbt:SetAllPoints(self) end
        self.__sbt:SetTexture(t)
    end
end
function StatusBar:GetStatusBarTexture() return self.__sbt end
function StatusBar:SetStatusBarColor(...) self.__sbc = { ... } end
function StatusBar:GetStatusBarColor() return unpack(self.__sbc or { 1, 1, 1, 1 }) end
StatusBar.SetMinMaxValues = Slider.SetMinMaxValues
StatusBar.GetMinMaxValues = Slider.GetMinMaxValues
function StatusBar:SetValue(v) self.__value = v end
function StatusBar:GetValue() return self.__value or 0 end
function StatusBar:SetOrientation(o) end

local EditBox = class("EditBox", "Frame")
function EditBox:SetText(t)
    self.__text = tostring(t or "")
    if self.__maxLetters and self.__maxLetters > 0 and #self.__text > self.__maxLetters then self.__text = self.__text:sub(1, self.__maxLetters) end
    if self.__scripts.OnTextChanged then self.__scripts.OnTextChanged(self, false) end
end
function EditBox:GetText() return self.__text or "" end
function EditBox:Insert(t) self:SetText(self:GetText() .. t) end
function EditBox:SetFocus() if M.focus and M.focus ~= self then M.focus:ClearFocus() end; M.focus = self end
function EditBox:ClearFocus() if M.focus == self then M.focus = nil; if self.__scripts.OnEditFocusLost then self.__scripts.OnEditFocusLost(self) end end end
function EditBox:HasFocus() return M.focus == self and 1 or nil end
function EditBox:HighlightText() end
function EditBox:SetAutoFocus(a) self.__autofocus = a end
function EditBox:SetMultiLine(m) self.__multi = m end
function EditBox:IsMultiLine() return self.__multi and 1 or nil end
function EditBox:SetMaxLetters(n) self.__maxLetters = n end
function EditBox:SetFontObject(o) if type(o) == "string" then o = _G[o] end; if type(o) ~= "table" then error("SetFontObject bad", 2) end end
function EditBox:SetFont() end
function EditBox:SetTextInsets() end
function EditBox:SetJustifyH() end
function EditBox:SetNumeric() end
function EditBox:SetCursorPosition() end
function EditBox:SetTextColor() end
function EditBox:SetAltArrowKeyMode() end
function EditBox:GetNumber() return tonumber(self.__text) or 0 end

local ScrollFrame = class("ScrollFrame", "Frame")
function ScrollFrame:SetScrollChild(c)
    self.__child = c; c:SetParent(self)
    c.__points = { { "TOPLEFT", self, "TOPLEFT", 0, 0 } }
end
function ScrollFrame:GetScrollChild() return self.__child end
function ScrollFrame:SetVerticalScroll(v)
    self.__vs = v
    if self.__child then self.__child.__points = { { "TOPLEFT", self, "TOPLEFT", 0, v } } end
end
function ScrollFrame:GetVerticalScroll() return self.__vs or 0 end
function ScrollFrame:GetVerticalScrollRange()
    local c = self.__child; if not c then return 0 end
    return math.max(0, c:GetHeight() - self:GetHeight())
end
function ScrollFrame:UpdateScrollChildRect() end
function ScrollFrame:SetHorizontalScroll() end

local Cooldown = class("Cooldown", "Frame")
function Cooldown:SetCooldown() end
function Cooldown:SetReverse() end
function Cooldown:SetDrawEdge() end
local Model = class("Model", "Frame")
function Model:SetModel() end
local Minimap = class("Minimap", "Frame")
function Minimap:SetMaskTexture(t) self.__mask = t end
function Minimap:SetZoom(z) self.__zoom = z end
function Minimap:GetZoom() return self.__zoom or 0 end
function Minimap:GetZoomLevels() return 6 end
function Minimap:SetBlipTexture() end
local GameTooltipC = class("GameTooltip", "Frame")
function GameTooltipC:SetOwner(o, a) self.__owner = o; self.__lines = {} end
function GameTooltipC:SetText(t) self.__lines = { t } end
function GameTooltipC:AddLine(t) self.__lines = self.__lines or {}; table.insert(self.__lines, t) end
function GameTooltipC:AddDoubleLine(a, b) self:AddLine(tostring(a) .. " " .. tostring(b)) end
function GameTooltipC:ClearLines() self.__lines = {} end
function GameTooltipC:NumLines() return #(self.__lines or {}) end
function GameTooltipC:IsOwned(o) return self.__owner == o and 1 or nil end
function GameTooltipC:GetOwner() return self.__owner end
function GameTooltipC:SetAction() end
function GameTooltipC:SetHyperlink(link) self.__lines = { link }; M.lastHyperlink = link end

local frameTypes = { Frame = "Frame", Button = "Button", CheckButton = "CheckButton", Slider = "Slider", StatusBar = "StatusBar",
    EditBox = "EditBox", ScrollFrame = "ScrollFrame", Cooldown = "Cooldown", Model = "Model", PlayerModel = "Model",
    GameTooltip = "GameTooltip", Minimap = "Minimap" }
local baseScripts = { "OnShow", "OnHide", "OnUpdate", "OnEvent", "OnEnter", "OnLeave", "OnMouseDown", "OnMouseUp", "OnMouseWheel",
    "OnDragStart", "OnDragStop", "OnKeyDown", "OnKeyUp", "OnSizeChanged", "OnLoad", "OnAttributeChanged", "OnReceiveDrag" }
local extraScripts = { Button = { "OnClick", "PreClick", "PostClick", "OnDoubleClick" }, CheckButton = { "OnClick", "PreClick", "PostClick" },
    Slider = { "OnValueChanged", "OnMinMaxChanged" }, StatusBar = { "OnValueChanged" },
    EditBox = { "OnTextChanged", "OnEnterPressed", "OnEscapePressed", "OnEditFocusLost", "OnEditFocusGained", "OnChar", "OnCursorChanged", "OnTabPressed", "OnSpacePressed" },
    ScrollFrame = { "OnVerticalScroll", "OnScrollRangeChanged", "OnHorizontalScroll" }, GameTooltip = { "OnTooltipSetItem", "OnTooltipCleared", "OnTooltipSetUnit" } }
local scriptSets = {}
for t in pairs(frameTypes) do
    local s = {}
    for _, n in ipairs(baseScripts) do s[n] = true end
    for _, n in ipairs(extraScripts[t] or extraScripts[frameTypes[t]] or {}) do s[n] = true end
    scriptSets[t] = s
end

M.templates = {}
function CreateFrame(ftype, name, parent, template)
    local cls = frameTypes[ftype]
    if not cls then error("CreateFrame: unknown frame type " .. tostring(ftype), 2) end
    if type(parent) == "string" then parent = _G[parent] end
    local f = newObject(cls, ftype, name, nil)
    f.__isframe = true
    f.__validScripts = scriptSets[ftype]
    f.__parent = parent
    if parent then parent.__children = parent.__children or {}; table.insert(parent.__children, f) end
    if template then
        for tpl in tostring(template):gmatch("[^,%s]+") do
            local fn = M.templates[tpl]
            if not fn then error("CreateFrame: template not available in mock/3.3.5: " .. tpl, 2) end
            fn(f, name)
        end
    end
    return f
end

M.templates.GameMenuButtonTemplate = function(f) f:SetWidth(144); f:SetHeight(21) end
M.templates.SecureActionButtonTemplate = function(f) f.__protected = true end
M.templates.ActionBarButtonTemplate = function(f, name)
    f.__protected = true
    f.__mouse = true
    f:SetWidth(36); f:SetHeight(36)
    local icon = f:CreateTexture(name and name .. "Icon", "BACKGROUND")
    f:SetNormalTexture("Interface\\Buttons\\UI-Quickslot2")
    f:CreateFontString(name and name .. "HotKey", "ARTWORK", "NumberFontNormalSmallGray")
    f:CreateFontString(name and name .. "Count", "ARTWORK", "NumberFontNormal")
    f:CreateFontString(name and name .. "Name", "OVERLAY", "GameFontHighlightSmallOutline")
    f:CreateTexture(name and name .. "Border", "OVERLAY")
    f:CreateTexture(name and name .. "Flash", "ARTWORK")
    CreateFrame("Cooldown", name and name .. "Cooldown", f)
    f:SetPushedTexture("Interface\\Buttons\\UI-Quickslot-Depress")
    f:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square")
    f:SetCheckedTexture("Interface\\Buttons\\CheckButtonHilight")
end
M.templates.UIPanelButtonTemplate = function(f) f:SetWidth(100); f:SetHeight(22) end

-- ------------------------------------------------------------ globals
function hooksecurefunc(a, b, c)
    local tbl, name, fn
    if type(a) == "table" then tbl, name, fn = a, b, c else tbl, name, fn = _G, a, b end
    local orig = tbl[name]
    if type(orig) ~= "function" then error("hooksecurefunc: " .. tostring(name) .. " is not a function", 2) end
    tbl[name] = function(...)
        local r = { orig(...) }
        fn(...)
        return unpack(r)
    end
    M.hooks[name] = (M.hooks[name] or 0) + 1
end
function InCombatLockdown() return M.combat and 1 or nil end
function GetCursorPosition() return M.cursorX, M.cursorY end
function GetTime() return M.time end
function time() return 1790000000 + math.floor(M.time) end
function debugstack() return "(mock stack)" end
function issecure() return nil end
function securecall(fn, ...) if type(fn) == "string" then fn = _G[fn] end; return fn(...) end
function geterrorhandler() return function(e) M.errors[#M.errors + 1] = e end end
function seterrorhandler() end
M.loadedAddons = {}
function IsAddOnLoaded(n) return M.loadedAddons[n] and 1 or nil end
function GetAddOnInfo(n) return n, n, "", M.loadedAddons[n] and 1 or nil end
function GetBuildInfo() return "3.3.5", "12340", "Jun 24 2010", 30300 end
M.cvars = { rotateMinimap = "0", uiScale = "1", useUiScale = "0", alwaysShowActionBars = "0" }
function GetCVar(k) return M.cvars[k] end
function SetCVar(k, v) M.cvars[k] = tostring(v) end
function GetCVarBool(k) return M.cvars[k] == "1" and 1 or nil end
M.bindings = {}
function GetBindingKey(cmd)
    local keys = {}
    for k, c in pairs(M.bindings) do if c == cmd then keys[#keys + 1] = k end end
    table.sort(keys)
    return unpack(keys)
end
function GetBindingAction(key) return M.bindings[key] or "" end
function SetBinding(key, cmd)
    if M.combat then error("SetBinding blocked in combat", 2) end
    if cmd == nil or cmd == "" then M.bindings[key] = nil else M.bindings[key] = cmd end
    return 1
end
function SaveBindings(set) M.savedBindings = set end
function GetCurrentBindingSet() return 2 end
function GetBindingText(k) return k end
function GetMouseFocus() return M.mouseFocus end
function IsShiftKeyDown() return M.shift and 1 or nil end
function IsControlKeyDown() return M.ctrl and 1 or nil end
function IsAltKeyDown() return M.alt and 1 or nil end
function PlaySound() end
function UnitExists(u) return (u == "player" or (u == "target" and M.hasTarget)) and 1 or nil end
function UnitName(u) return u == "player" and "Tester" or (M.hasTarget and u == "target" and "Target") or nil end
function UnitLevel() return 80 end
function UnitClass() return "Warrior", "WARRIOR" end
function UnitClassification() return "normal" end
function UnitIsPlayer(u) return u == "player" and 1 or nil end
function UnitHealth() return 100 end
function UnitHealthMax() return 100 end
function UnitPower() return 50 end
function UnitPowerMax() return 100 end
function UnitPowerType() return 1, "RAGE" end
function UnitHasVehicleUI() return nil end
function UnitAffectingCombat() return M.combat and 1 or nil end
function GetZoneText() return "Dalaran" end
function GetMinimapZoneText() return "Krasus' Landing" end
function GetZonePVPInfo() return "sanctuary" end
function GetGameTime() return 12, 30 end
function SetPortraitTexture() end
function HasAction(a) return M.actions and M.actions[a] and 1 or nil end
function GetActionTexture(a) return HasAction(a) and "Interface\\Icons\\Spell_Nature_Heal" or nil end
function GetNumShapeshiftForms() return M.forms and #M.forms or 3 end
function GetShapeshiftFormInfo(i) local f = M.forms and M.forms[i]; if f then return f[1], f[2], f[3], f[4] end end
function GetShapeshiftForm() for i, f in ipairs(M.forms or {}) do if f[3] then return i end end; return 0 end
M.buffs = M.buffs or {}
function UnitBuff(u, i)
    if u ~= "player" then return nil end
    local b = M.buffs[i]
    if b then return b.name, "", b.icon, 0, nil, 0, 0, "player", nil, nil, b.id end
end
function UnitAura(u, i, filter) if not filter or filter:find("HELPFUL") then return UnitBuff(u, i) end end
function CloseDropDownMenus() end
function HideUIPanel(f) f:Hide() end
function ShowUIPanel(f) f:Show() end
function KeyBindingFrame_LoadUI() end
function InterfaceOptions_AddCategory(p) M.optionsPanels = M.optionsPanels or {}; table.insert(M.optionsPanels, p) end
function InterfaceOptionsFrame_OpenToCategory(p) M.openedOptions = p end
function GetScreenWidth() return UIParent:GetWidth() end
function GetScreenHeight() return UIParent:GetHeight() end
function wipe(t) for k in pairs(t) do t[k] = nil end; return t end
table.wipe = wipe
function strtrim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
function strsplit(d, s) local out = {}; for p in (s .. d):gmatch("(.-)" .. d:gsub("%p", "%%%0")) do out[#out + 1] = p end; return unpack(out) end
tinsert, tremove, format, strlower, strupper, strfind, strsub, strlen = table.insert, table.remove, string.format, string.lower, string.upper, string.find, string.sub, string.len
floor, ceil, abs, min, max, sqrt = math.floor, math.ceil, math.abs, math.min, math.max, math.sqrt
function RegisterStateDriver(f, s, v) f.__stateDriver = { s, v } end
function UnregisterStateDriver(f, s) f.__stateDriver = nil end
function Minimap_ZoomIn() Minimap:SetZoom(math.min(5, Minimap:GetZoom() + 1)) end
function Minimap_ZoomOut() Minimap:SetZoom(math.max(0, Minimap:GetZoom() - 1)) end
function GetFramerate() return 60 end
function collectgarbage_mock() end
STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"
NUM_ACTIONBAR_BUTTONS = 12
UISpecialFrames = {}
UIPARENT_MANAGED_FRAME_POSITIONS = {}
SHOW_MULTI_ACTIONBAR_1, SHOW_MULTI_ACTIONBAR_2, SHOW_MULTI_ACTIONBAR_3, SHOW_MULTI_ACTIONBAR_4 = nil, nil, nil, nil
function SetActionBarToggles(a, b, c, d, e) M.barToggles = { a, b, c, d, e } end
function GetActionBarToggles() local t = M.barToggles or {}; return t[1], t[2], t[3], t[4], t[5] end

-- font objects
local function fontObject(name, size)
    local o = { __name = name, __size = size or 12 }
    function o:GetFont() return "Fonts\\FRIZQT__.TTF", self.__size, self.__flags or "" end
    function o:GetName() return name end
    function o:SetFont(path, sz, flags) self.__size = sz or self.__size; self.__flags = flags end
    function o:SetTextColor() end
    function o:SetShadowOffset() end
    _G[name] = o
end
for _, n in ipairs({ "GameFontNormal", "GameFontNormalSmall", "GameFontNormalLarge", "GameFontHighlight", "GameFontHighlightSmall",
    "GameFontHighlightLarge", "GameFontDisable", "GameFontDisableSmall", "GameFontGreen", "GameFontRed", "NumberFontNormal",
    "NumberFontNormalSmall", "NumberFontNormalSmallGray", "GameFontHighlightSmallOutline", "ChatFontNormal", "GameFontNormalHuge",
    "SystemFont_Shadow_Med1", "TextStatusBarText", "GameFontWhite" }) do fontObject(n) end
function CreateFont(name) fontObject(name); return _G[name] end

M.overrides = {}
function SetOverrideBindingClick(owner, prio, key, button, mouse)
    if M.combat then error("SetOverrideBindingClick blocked in combat", 2) end
    M.overrides[key] = { owner = owner, button = button, mouse = mouse }
end
function ClearOverrideBindings(owner)
    if M.combat then error("ClearOverrideBindings blocked in combat", 2) end
    for k, v in pairs(M.overrides) do if v.owner == owner then M.overrides[k] = nil end end
end
function ReloadUI() M.reloadRequested = true end
SlashCmdList = {}
-- ---------------------------------------------------------------- units & spells (Boss Timeline)
-- M.units[token] = { guid, name, level, class, combat, dead, friendly, player, cast = { name, icon, startMs, endMs, channel } }
M.units = {}
M.spells = {} -- [id] = { name, icon, castMs }
local function U(u) return M.units[u] end
local baseExists, baseName, baseLevel, baseClass, baseCombat = UnitExists, UnitName, UnitLevel, UnitClassification, UnitAffectingCombat
function UnitExists(u) if U(u) then return 1 end; return baseExists(u) end
function UnitName(u) if U(u) then return U(u).name end; return baseName(u) end
function UnitLevel(u) if U(u) then return U(u).level or 80 end; return baseLevel(u) end
function UnitClassification(u) if U(u) then return U(u).class or "normal" end; return baseClass(u) end
function UnitAffectingCombat(u) if U(u) then return U(u).combat and 1 or nil end; return baseCombat(u) end
function UnitGUID(u)
    if U(u) then return U(u).guid end
    if u == "player" then return "0x0000000000000001" end
end
function UnitIsDead(u) return U(u) and U(u).dead and 1 or nil end
local baseHealth, baseHealthMax = UnitHealth, UnitHealthMax
function UnitHealth(u) if U(u) and U(u).hp then return U(u).hp end; return baseHealth(u) end
function UnitHealthMax(u) if U(u) and U(u).maxhp then return U(u).maxhp end; return baseHealthMax(u) end
function UnitCanAttack(a, u) local x = U(u); return x and not x.friendly and not x.player and 1 or nil end
local basePlayer = UnitIsPlayer
function UnitIsPlayer(u) if U(u) then return U(u).player and 1 or nil end; return basePlayer(u) end
function UnitIsUnit(a, b) return a == b or (UnitGUID(a) ~= nil and UnitGUID(a) == UnitGUID(b)) end
function UnitCastingInfo(u)
    local c = U(u) and U(u).cast
    if c and not c.channel then return c.name, nil, c.name, c.icon, c.startMs, c.endMs, nil, 1, nil end
end
function UnitChannelInfo(u)
    local c = U(u) and U(u).cast
    if c and c.channel then return c.name, nil, c.name, c.icon, c.startMs, c.endMs, nil, nil end
end
function GetSpellInfo(id)
    local s = M.spells[id]
    if s then return s.name, "", s.icon or "Interface\\Icons\\Spell_Nature_Heal", 0, nil, 0, s.castMs or 0, 0, 0 end
    if type(id) == "number" and id > 0 then return "Spell " .. id, "", "Interface\\Icons\\Spell_Nature_Heal", 0, nil, 0, 0, 0, 0 end
end
function SetPortraitToTexture(tex, path) tex:SetTexture(path); tex.__portrait = true end
function IsInInstance() return M.inInstance and 1 or nil, M.inInstance and "raid" or "none" end
function GetRealmName() return M.realm or "Frostmourne" end
function GetInstanceDifficulty() return M.difficulty or 1 end
function GetNumRaidMembers() return M.raidSize or 0 end
function GetNumPartyMembers() return 0 end
-- a creature GUID the way 3.3.5 builds it
function M.creatureGUID(npc, spawn) return string.format("0xF1300%05X%06X", npc, spawn or 1) end
return M
