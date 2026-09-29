-- BlizzUI Reborn: Retail (The War Within / Midnight) style UI and Edit Mode for
-- the 3.3.5 client. Original code; Retail UI source was used only as a reference.
BlizzUIReborn = BlizzUIReborn or {}
local A = BlizzUIReborn
A.version = "0.7.0"
A.elements, A.order = {}, {}
A.leases = {}
local unpack, pairs, ipairs, type, math = unpack, pairs, ipairs, type, math

-- ------------------------------------------------------------------ utilities
function A.Copy(v)
    if type(v) ~= "table" then return v end
    local out = {}
    for k, x in pairs(v) do out[k] = A.Copy(x) end
    return out
end
function A.Equal(a, b)
    if type(a) ~= type(b) then return false end
    if type(a) ~= "table" then
        if type(a) == "number" then return math.abs(a - b) < 1e-6 end
        return a == b
    end
    for k, v in pairs(a) do if not A.Equal(v, b[k]) then return false end end
    for k in pairs(b) do if a[k] == nil then return false end end
    return true
end
function A.Clamp(v, lo, hi) if v < lo then return lo elseif v > hi then return hi end return v end
function A.Round(v, step) step = step or 1; return math.floor(v / step + .5) * step end
function A.Combat() return InCombatLockdown() and true or false end
function A.Size(f, w, h) f:SetWidth(w); f:SetHeight(h) end
function A.Visible(f, v) if v then f:Show() else f:Hide() end end
function A.Enable(f, v) if v then f:Enable() else f:Disable() end end
function A.Trim(s) return (tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", "")) end
function A.Format(n) -- number label without trailing ".0"
    if math.abs(n - math.floor(n + .5)) < 1e-6 then return string.format("%d", math.floor(n + .5)) end
    return string.format("%.1f", n)
end
function A:Print(msg)
    if DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage("|cff4fc3f7BlizzUI Reborn:|r " .. tostring(msg)) end
end
function A:Error(msg) self:Print("|cffff6060" .. tostring(msg) .. "|r") end

-- Protected-call wrapper. Errors are kept for /br report even when the
-- player's scriptErrors CVar hides them. Never replaces the global handler.
A.errorLog = {}
function A:Run(label, fn, ...)
    local n, args = select("#", ...), { ... }
    local ok, a, b, c = xpcall(function() return fn(unpack(args, 1, n)) end, function(err)
        local text = tostring(label) .. ": " .. tostring(err) .. (debugstack and ("\n" .. debugstack(2, 6, 0)) or "")
        return text
    end)
    if not ok then
        self.lastError = a
        table.insert(self.errorLog, 1, a)
        if #self.errorLog > 10 then table.remove(self.errorLog) end
        self.drag = nil
        if not self.quietErrors then self:Error(tostring(label) .. " failed. /br report shows details.") end
        return nil, a
    end
    return a, b, c
end

-- ------------------------------------------------------------------ geometry
-- All positions are expressed in UIParent units.
function A.Rect(frame)
    if not frame then return end
    local l, b = frame:GetLeft(), frame:GetBottom()
    if not l or not b then return end
    local s = frame:GetEffectiveScale() / UIParent:GetEffectiveScale()
    return l * s, b * s, frame:GetWidth() * s, frame:GetHeight() * s
end
function A.Cursor()
    local x, y = GetCursorPosition()
    local s = UIParent:GetEffectiveScale()
    return x / s, y / s
end
local function pointXY(point, l, b, w, h)
    local x = point:find("LEFT") and l or point:find("RIGHT") and l + w or l + w / 2
    local y = point:find("TOP") and b + h or point:find("BOTTOM") and b or b + h / 2
    return x, y
end
A.PointXY = pointXY
-- Retail-style anchoring: the element is attached to the nearest screen
-- region (thirds), so layouts survive resolution and aspect changes.
function A.AnchorFor(cx, cy)
    local W, H = UIParent:GetWidth(), UIParent:GetHeight()
    local h = cx < W / 3 and "LEFT" or cx > W * 2 / 3 and "RIGHT" or ""
    local v = cy > H * 2 / 3 and "TOP" or cy < H / 3 and "BOTTOM" or ""
    local p = v .. h
    return p == "" and "CENTER" or p
end
function A.ToPosition(l, b, w, h, point)
    point = point or A.AnchorFor(l + w / 2, b + h / 2)
    local fx, fy = pointXY(point, l, b, w, h)
    local ux, uy = pointXY(point, 0, 0, UIParent:GetWidth(), UIParent:GetHeight())
    return point, A.Round(fx - ux, .1), A.Round(fy - uy, .1)
end
function A.FromPosition(point, x, y, w, h)
    local ux, uy = pointXY(point, 0, 0, UIParent:GetWidth(), UIParent:GetHeight())
    local fx, fy = ux + x, uy + y
    local l = point:find("LEFT") and fx or point:find("RIGHT") and fx - w or fx - w / 2
    local b = point:find("TOP") and fy - h or point:find("BOTTOM") and fy or fy - h / 2
    return l, b
end
-- Anchor `frame` so that its `point` sits at UIParent's `point` + (x,y).
function A.PlaceAt(frame, point, x, y)
    local ratio = UIParent:GetEffectiveScale() / frame:GetEffectiveScale()
    frame:ClearAllPoints()
    frame:SetPoint(point, UIParent, point, x * ratio, y * ratio)
end

function A.Snapshot(frame)
    local t = { parent = frame:GetParent(), scale = frame:GetScale(), width = frame:GetWidth(), height = frame:GetHeight(),
        alpha = frame:GetAlpha(), points = {}, shown = frame:IsShown() and true or false }
    if frame.IsMouseEnabled then t.mouse = frame:IsMouseEnabled() and true or false end
    if frame.IsMovable then t.movable = frame:IsMovable() and true or false end
    if frame.IsUserPlaced then t.userPlaced = frame:IsUserPlaced() and true or false end
    if frame.GetFrameStrata then t.strata = frame:GetFrameStrata() end
    for i = 1, frame:GetNumPoints() do t.points[i] = { frame:GetPoint(i) } end
    return t
end
-- Restores geometry only (not visibility, which native code owns).
function A.RestoreGeometry(frame, t)
    if not frame or not t then return end
    if frame:GetParent() ~= t.parent then frame:SetParent(t.parent) end
    if t.scale then frame:SetScale(t.scale) end
    frame:ClearAllPoints()
    for _, p in ipairs(t.points) do frame:SetPoint(unpack(p)) end
    if #t.points == 0 or #t.points == 1 then
        if t.width and t.width > 0 then frame:SetWidth(t.width) end
        if t.height and t.height > 0 then frame:SetHeight(t.height) end
    end
end

-- ------------------------------------------------------------------ events & timers
local driver = CreateFrame("Frame", "BlizzUIRebornDriver")
A.driver = driver
local handlers = {}
function A:On(event, fn)
    if not handlers[event] then handlers[event] = {}; driver:RegisterEvent(event) end
    table.insert(handlers[event], fn)
end
driver:SetScript("OnEvent", function(_, event, ...)
    local list = handlers[event]
    if not list then return end
    for i = 1, #list do A:Run(event, list[i], ...) end
end)
local timers = {}
function A:After(delay, fn, key)
    if key then
        for _, t in ipairs(timers) do if t.key == key then return end end -- already queued
    end
    table.insert(timers, { at = GetTime() + (delay or 0), fn = fn, key = key })
end
local updaters = {}
function A:Every(interval, fn) table.insert(updaters, { interval = interval, fn = fn, left = interval }) end
driver:SetScript("OnUpdate", function(_, elapsed)
    if #timers > 0 then
        local now, due = GetTime(), nil
        for i = #timers, 1, -1 do
            if timers[i].at <= now then due = due or {}; table.insert(due, 1, timers[i]); table.remove(timers, i) end
        end
        if due then for _, t in ipairs(due) do A:Run("timer", t.fn) end end
    end
    for i = 1, #updaters do
        local u = updaters[i]
        u.left = u.left - elapsed
        if u.left <= 0 then u.left = u.interval; A:Run("update", u.fn, elapsed) end
    end
end)

-- ------------------------------------------------------------------ hooks
-- Post-hooks only (hooksecurefunc); nothing Blizzard owns is replaced.
function A:Hook(name, fn)
    if type(_G[name]) == "function" then hooksecurefunc(name, function(...) A:Run(name, fn, ...) end); return true end
end

-- ------------------------------------------------------------------ leases
-- A per-frame setter lease: while leased, the listed setters are no-ops for
-- other code (Carbonite's dock, for instance) and only our WriteLease writes.
function A:Lease(frame, setters)
    if A.Combat() or not frame or (frame.IsProtected and frame:IsProtected()) then return end
    if frame == Minimap or frame == MinimapCluster or frame == _G.NxMap1 then return end
    if self.leases[frame] then return self.leases[frame] end
    local lease = { frame = frame, original = {}, wrappers = {}, snapshot = A.Snapshot(frame) }
    for _, key in ipairs(setters) do
        local method = frame[key]
        if method then
            lease.original[key] = method
            local wrapper = function(f, ...) if lease.writing then return method(f, ...) end end
            lease.wrappers[key] = wrapper
            frame[key] = wrapper
        end
    end
    self.leases[frame] = lease
    return lease
end
function A:WriteLease(lease, fn)
    if not lease then return end
    lease.writing = true
    local ok, err = pcall(fn, lease.frame)
    lease.writing = false
    if not ok then self:Error(err) end
    return ok
end
function A:ReleaseLease(frame)
    local lease = self.leases[frame]
    if not lease or A.Combat() then return end
    for key, method in pairs(lease.original) do
        if rawget(frame, key) == lease.wrappers[key] then frame[key] = nil end
        if frame[key] ~= method then frame[key] = method end
    end
    self.leases[frame] = nil
    lease.writing = true
    pcall(A.RestoreGeometry, frame, lease.snapshot)
    if lease.snapshot.alpha then frame:SetAlpha(lease.snapshot.alpha) end
    if lease.snapshot.mouse ~= nil and frame.EnableMouse then frame:EnableMouse(lease.snapshot.mouse) end
    lease.writing = false
end
-- Calls a legacy (2.x-style) script with `this`/`arg1` globals set.
function A:CallLegacy(frame, script, ...)
    local fn = frame and frame:GetScript(script)
    if not fn then return end
    local oldThis, oldArg1, oldArg2 = _G.this, _G.arg1, _G.arg2
    _G.this, _G.arg1, _G.arg2 = frame, ...
    local ok, err = pcall(fn, frame, ...)
    _G.this, _G.arg1, _G.arg2 = oldThis, oldArg1, oldArg2
    if not ok then self:Error(err) end
    return ok
end

-- ------------------------------------------------------------------ registry
function A:Register(def)
    assert(not self.elements[def.id], "Duplicate element " .. def.id)
    def.settings = def.settings or {}
    self.elements[def.id] = def
    table.insert(self.order, def.id)
    return def
end
function A:Conflict()
    if IsAddOnLoaded("ElvUI") then return "ElvUI" end
    if IsAddOnLoaded("Tukui") then return "Tukui" end
end
function A:CarboniteMap()
    if _G.Nx and Nx.Map and Nx.Map.GeM then
        local ok, map = pcall(Nx.Map.GeM, Nx.Map, 1)
        if ok and map then return map end
        return false
    end
end
