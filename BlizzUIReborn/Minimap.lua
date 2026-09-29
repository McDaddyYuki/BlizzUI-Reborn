-- Retail-style minimap (native minimap only) and the Carbonite status-icon
-- adapter. Carbonite's map, the native Minimap frame and MinimapCluster are
-- never re-parented, resized or re-scripted while Carbonite is loaded.
local A = BlizzUIReborn
local S = A.Schema
-- column order, top to bottom (the clock always goes last)
-- (Retail order: calendar, mail, queue eye, tracking)
local ICONS = { "GameTimeFrame", "MiniMapMailFrame", "MiniMapLFGFrame", "MiniMapBattlefieldFrame", "MiniMapTracking",
    "MiniMapInstanceDifficulty", "MiniMapVoiceChatFrame", "MiniMapWorldMapButton" }
A.StatusIconNames = ICONS
local SETTERS = { "SetParent", "SetPoint", "ClearAllPoints", "SetScale", "SetFrameStrata", "SetFrameLevel" }
A.statusLeases = {}
A.STATUS_RANGE = 600 -- offsets reach anywhere around even a large Carbonite window

A:Register({ id = "status", label = "Minimap Status Icons", category = "Misc", kind = "status",
    settings = {
        S.choice("side", "Side of Map", "auto", { { "auto", "Automatic (Right)" }, { "right", "Right" }, { "left", "Left" }, { "top", "Above" }, { "bottom", "Below" } }),
        S.slider("size", "Icon Size", 20, 40, 2, 28), S.slider("spacing", "Icon Spacing", 24, 48, 2, 32),
        S.slider("offsetX", "Horizontal Offset", -A.STATUS_RANGE, A.STATUS_RANGE, 2, 0), S.slider("offsetY", "Vertical Offset", -A.STATUS_RANGE, A.STATUS_RANGE, 2, 0),
    } })

-- Returns the frame the player sees as "the minimap" and whether it belongs
-- to Carbonite. With Carbonite that is always Carbonite's whole map window
-- (title bar included), never the native Minimap: Carbonite can embed the
-- Minimap inside its map, where it follows the player around (and fades in
-- and out on mouse-over), so anything placed relative to it would wander.
function A:MapReference()
    local map = self:CarboniteMap()
    if map ~= nil then
        local win = map and map.Win1 and map.Win1.Frm
        if win and win.IsVisible and win:IsVisible() then return win, true, win end
        local frm = map and map.Frm
        if frm and frm:IsVisible() then return frm, true, frm end
        return nil, true
    end
    if Minimap and Minimap:IsVisible() then return Minimap, false end
end
function A:CarboniteActive() return _G.Nx ~= nil and _G.Nx.Map ~= nil end

-- The native minimap keeps its stock look; nothing here restyles it.
function A:RestoreMinimapSkin() end

-- ------------------------------------------------------------- Carbonite adapter
function A:FilterCarboniteDock()
    local doc = _G.Nx and Nx.Map and Nx.Map.Doc
    if not doc or type(doc.MMF1) ~= "table" then return end
    for i = #doc.MMF1, 1, -1 do
        local f = doc.MMF1[i]
        if self.leases[f] then
            self.removedDock = self.removedDock or {}
            self.removedDock[f] = i
            table.remove(doc.MMF1, i)
        end
    end
end
function A:RestoreDock()
    local doc = _G.Nx and Nx.Map and Nx.Map.Doc
    if doc and type(doc.MMF1) == "table" and self.removedDock then
        local list = {}
        for f, i in pairs(self.removedDock) do list[#list + 1] = { f = f, i = i } end
        table.sort(list, function(a, b) return a.i < b.i end)
        local keep = {}
        for _, e in ipairs(list) do
            if self.leases[e.f] then keep[e.f] = e.i
            else
                local found = false
                for _, f in ipairs(doc.MMF1) do if f == e.f then found = true end end
                if not found then table.insert(doc.MMF1, math.min(e.i, #doc.MMF1 + 1), e.f) end
            end
        end
        self.removedDock = next(keep) and keep or nil
    else
        self.removedDock = nil
    end
end
function A:ReleaseStatusIcons()
    for f in pairs(self.statusLeases) do self:ReleaseLease(f) end
    self.statusLeases = {}
    self:RestoreDock()
end
-- Which side of the map the icons go on. Left/right keep Retail's column
-- (flipped if it would leave the screen); above/below lay them out in a row.
function A:StatusSide(e, x, w)
    local side = e.side
    if side == "top" or side == "bottom" then return side end
    if side ~= "left" and side ~= "right" then side = "right" end -- Retail: column on the right
    -- never off screen
    local W = UIParent:GetWidth()
    if side == "right" and x + w + 40 > W then side = "left" end
    if side == "left" and x - 40 < 0 then side = "right" end
    return side
end
-- Where the first icon's centre sits for a side (before offsets), and the
-- step to the next icon. The row below the map goes under the clock row.
function A:StatusOrigin(side, x, y, w, h, e, below)
    local half = e.size / 2
    if side == "left" then return x - half - 4, y + h - half, 0, -e.spacing end
    if side == "top" then return x + half, y + h + half + 4, e.spacing, 0 end
    if side == "bottom" then return x + half, y - (below or 0) - half - 4, e.spacing, 0 end
    return x + w + half + 4, y + h - half, 0, -e.spacing
end
-- Dragging: the side follows the map edge nearest to the dragged icons, and
-- the offsets keep the first icon under the cursor.
function A:StatusDragTo(fx, fy)
    local ref = self.statusRef
    if not ref then return end
    local x, y, w, h = A.Rect(ref)
    if not x then return end
    local e = self:EnsureEntry("status")
    local s = self:Settings(self.elements.status)
    local d = { left = fx - x, right = x + w - fx, top = y + h - fy, bottom = fy - y }
    -- outside the window, the side it is beyond wins
    local side, best = "right", math.huge
    for _, k in ipairs({ "right", "left", "top", "bottom" }) do
        if d[k] < best then side, best = k, d[k] end
    end
    local below = side == "bottom" and self.statusClockHeight or 0
    local ox, oy = self:StatusOrigin(side, x, y, w, h, s, below)
    local R = A.STATUS_RANGE
    e.side = side
    e.offsetX = A.Clamp(A.Round(fx - ox, 2), -R, R)
    e.offsetY = A.Clamp(A.Round(fy - oy, 2), -R, R)
    self:UpdateStatus()
end
local function place(self, lease, px, py, scale, strata)
    local key = string.format("%.1f:%.1f:%.3f", px, py, scale)
    if lease.position == key then return end
    self:WriteLease(lease, function(fr)
        fr:SetParent(UIParent); fr:SetScale(scale)
        local ratio = UIParent:GetEffectiveScale() / fr:GetEffectiveScale()
        fr:ClearAllPoints(); fr:SetPoint("CENTER", UIParent, "BOTTOMLEFT", px * ratio, py * ratio)
        fr:SetFrameStrata(strata or "MEDIUM")
    end)
    lease.position = key
end

-- ------------------------------------------------------------- map pins
-- Carbonite's dock ("Move Minimap buttons into Carbonite button window")
-- takes every shown child of the Minimap it doesn't know, which includes map
-- pins from Questie, HandyNotes, GatherMate, TomTom and similar (mailboxes,
-- portals, nodes...). Those end up as a grid of icons in the dock window.
-- Pins are marked as known to Carbonite before its scan sees them, and any
-- already docked are handed back to the Minimap.
local PIN_NAMES = { "questie", "handynotes", "gather", "tomtom", "pin", "poi", "routes", "cartographer", "questhelper", "npcscan", "waypoint" }
local function blizzardName(name)
    return name:find("^Mini[Mm]ap") or name:find("^GameTime") or name:find("^TimeManager") or name:find("^Nx") or name:find("^NX")
end
function A:IsMapPin(f, byNameOnly)
    if not f or f == Minimap or self.leases[f] or not f.GetWidth then return false end
    if f.IsObjectType and f:IsObjectType("Model") then return false end
    local name = f.GetName and f:GetName()
    if name then
        if blizzardName(name) or name:find("^LibDBIcon") or name:find("^BlizzUIReborn") then return false end
        local l = name:lower()
        if l:find("minimapbutton", 1, true) or l:find("minimapicon", 1, true) then return false end
        for _, p in ipairs(PIN_NAMES) do if l:find(p, 1, true) then return true end end
    end
    if byNameOnly then return false end
    local w, h = f:GetWidth(), f:GetHeight()
    return w > 0 and h > 0 and w <= 24 and h <= 24
end
function A:ShieldMapPins()
    local map = self:CarboniteMap()
    local doc = _G.Nx and Nx.Map and Nx.Map.Doc
    if not map or not Minimap or not doc or type(doc.MMF1) ~= "table" then return end
    if type(map.MMOF) == "table" then
        local kids = { Minimap:GetChildren() }
        for i = 1, #kids do
            local c = kids[i]
            if not map.MMOF[c] and c:GetParent() == Minimap and self:IsMapPin(c) then map.MMOF[c] = 0 end
        end
    end
    for i = #doc.MMF1, 1, -1 do
        local f = doc.MMF1[i]
        -- only pins recognisable by name are handed back (never Carbonite's own frames)
        if self:IsMapPin(f, true) then
            table.remove(doc.MMF1, i)
            if f:GetParent() ~= Minimap then
                f:SetParent(Minimap)
                -- the pin's addon moves it to its real spot on its next update
                f:ClearAllPoints(); f:SetPoint("CENTER", Minimap, "CENTER", 0, 0)
            end
            self.pinsReturned = (self.pinsReturned or 0) + 1
        end
    end
end

-- Carbonite only, laid out like Retail around Carbonite's map window: status
-- icons in a column down its right side, the Addon Compartment under its
-- lower-left corner and the clock centred under it. Everything sits outside
-- the window and only moves when the window itself moves or resizes.
function A:UpdateStatus()
    if A.Combat() then return end
    if self.active and self:CarboniteActive() then self:Run("Map pins", self.ShieldMapPins, self) end
    local def = self.elements.status
    if not self.active or not self.draft or not self.draft.status or not self:CarboniteActive() then
        if next(self.statusLeases) then self:ReleaseStatusIcons() end
        self.compartmentSlot = nil
        return
    end
    local reference = self:MapReference()
    -- a maximized Carbonite map fills the screen: use a fixed corner instead
    if reference then
        local _, _, ww = A.Rect(reference)
        if not ww or ww > UIParent:GetWidth() * .8 then reference = nil end
    end
    reference = reference or self.statusFallback
    self.statusRef = reference
    local x, y, w, h = A.Rect(reference)
    if not x then return end
    local e = self:Settings(def)
    local side = self:StatusSide(e, x, w)
    -- under the window: compartment at the lower-left, clock in the middle
    local rowY = y - 4
    local compRight = x
    local comp = self.draft.compartment and not (self.draft.frames.compartment and self.draft.frames.compartment.point)
    local rowH = 0
    if comp then
        local cs = self.elements.compartment.frame and self.elements.compartment.frame:GetWidth() or 30
        self.compartmentSlot = { x + cs / 2, rowY - cs / 2 }
        compRight = x + cs + 4
        rowH = cs + 4
    else
        self.compartmentSlot = nil
    end
    local clock = _G.TimeManagerClockButton
    if clock then
        local lease = self.statusLeases[clock]
        if not lease then lease = self:Lease(clock, SETTERS); self.statusLeases[clock] = lease end
        if lease then
            local cs = lease.snapshot.scale * .85
            local cw, ch = clock:GetWidth() * cs, clock:GetHeight() * cs -- parented to UIParent while leased
            local ccx = math.max(x + w / 2, compRight + cw / 2)
            place(self, lease, ccx, rowY - ch / 2, cs)
            rowH = math.max(rowH, ch + 4)
        end
    end
    self.statusClockHeight = rowH
    local cx, top, sx, sy = self:StatusOrigin(side, x, y, w, h, e, rowH)
    cx, top = cx + e.offsetX, top + e.offsetY
    self.statusFirst = { cx, top }
    local n = 0
    for _, name in ipairs(ICONS) do
        local f = _G[name]
        if f then
            local lease = self.statusLeases[f]
            if not lease then lease = self:Lease(f, SETTERS); self.statusLeases[f] = lease end
            if lease then
                place(self, lease, cx + n * sx, top + n * sy, e.size / math.max(f:GetWidth(), 1))
                if f:IsShown() then n = n + 1 end
            end
        end
    end
    -- the Edit Mode selection covers the shown icons
    local last = math.max(0, n - 1)
    local half = e.size / 2 + 2
    local l, r = math.min(cx, cx + last * sx) - half, math.max(cx, cx + last * sx) + half
    local b, t = math.min(top, top + last * sy) - half, math.max(top, top + last * sy) + half
    local anchor = def.frame
    A.Size(anchor, r - l, t - b)
    anchor:ClearAllPoints()
    anchor:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", l, b)
    self:FilterCarboniteDock()
    if self.PlaceCompartment then self:PlaceCompartment() end
end
A.Kinds.status = {
    apply = function(self, def) self:UpdateStatus() end,
    rect = function(self, def) if self:CarboniteActive() then return A.Rect(def.frame) end end,
}
function A:InitStatus()
    local def = self.elements.status
    def.frame = CreateFrame("Frame", "BlizzUIRebornStatusAnchor", UIParent)
    A.Size(def.frame, 32, 160)
    def.frame:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -200, -40)
    def.bound = true
    def.editable = function() return A:CarboniteActive() end
    self.statusFallback = CreateFrame("Frame", nil, UIParent)
    A.Size(self.statusFallback, 180, 180)
    self.statusFallback:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -60, -40)
end
