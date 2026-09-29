-- Retail-style Addon Compartment: one button by the minimap listing addon
-- launchers (LibDataBroker launchers + known legacy minimap buttons).
local A = BlizzUIReborn
local M, C = A.Media, A.Colors
A.launchers, A.launcherLeases = {}, {}
A:Register({ id = "compartment", label = "Addon Compartment", category = "Misc", kind = "compartment",
    settings = { A.Schema.slider("scale", "Button Size", 70, 150, 10, 100, "%") } })

local legacy = {
    { id = "carbonite", label = "Carbonite", frame = "NXMiniMapBut", icon = "Interface\\AddOns\\Carbonite\\Gfx\\MMBut" },
    { id = "dbm", label = "Deadly Boss Mods", frame = "DBMMinimapButton", icon = "Interface\\Icons\\INV_Helmet_87" },
    { id = "healbot", label = "HealBot", frame = "HealBot_MMButton", container = "HealBot_ButtonFrame", icon = "Interface\\Icons\\Spell_Holy_Heal" },
    { id = "restocompare", label = "RestoCompare", frame = "RestoCompareMinimap", icon = "Interface\\Icons\\INV_Misc_Book_09" },
}
local function library(name)
    if not LibStub or not LibStub.GetLibrary then return end
    local ok, lib = pcall(LibStub.GetLibrary, LibStub, name, true)
    if ok then return lib end
end
local function canonical(name) return (name:lower():gsub("[^%w]", ""):gsub("launcher$", "")) end
function A:DiscoverLaunchers()
    if self.db and self.db.collectButtons == false then
        for id, e in pairs(self.launchers) do
            if e.generic then
                self.launchers[id] = nil
                if e.frame and self.launcherLeases[e.frame] then self:ReleaseLease(e.frame); self.launcherLeases[e.frame] = nil end
            end
        end
    end
    local ldb, icons = library("LibDataBroker-1.1"), library("LibDBIcon-1.0")
    if ldb and ldb.DataObjectIterator then
        for name, obj in ldb:DataObjectIterator() do
            if obj.type == "launcher" or name == "GearScore" then
                local id = canonical(name)
                local frame = icons and ((icons.GetMinimapButton and icons:GetMinimapButton(name)) or (icons.objects and icons.objects[name]))
                local old = self.launchers[id]
                if old and old.obj == obj then old.frame = frame or old.frame; old.icon = obj.icon
                else self.launchers[id] = { id = id, label = obj.label or name, obj = obj, frame = frame, icon = obj.icon } end
            end
        end
    end
    for _, entry in ipairs(legacy) do
        if not self.launchers[entry.id] and _G[entry.frame] then
            self.launchers[entry.id] = { id = entry.id, label = entry.label, frame = _G[entry.frame],
                container = entry.container and _G[entry.container], icon = entry.icon, legacy = true }
        end
    end
    local known = {}
    for _, e in pairs(self.launchers) do
        if e.frame and not e.generic then known[e.frame] = true end
        if e.container then known[e.container] = true end
    end
    self:CollectMinimapButtons(known)
end
-- Generic minimap launcher buttons (the "stray icons" around the minimap and
-- in Carbonite's dock). Only named Buttons that look like addon launchers are
-- taken; Blizzard status icons, map pins and anonymous frames are left alone.
local BLIZZARD = {}
for _, n in ipairs({ "GameTimeFrame", "MiniMapMailFrame", "MiniMapLFGFrame", "MiniMapBattlefieldFrame", "MiniMapTracking", "MiniMapTrackingButton",
    "MiniMapWorldMapButton", "MiniMapVoiceChatFrame", "MiniMapInstanceDifficulty", "TimeManagerClockButton", "MinimapZoomIn", "MinimapZoomOut",
    "MinimapZoneTextButton", "MinimapBackdrop", "MiniMapPing", "MinimapPing", "BlizzUIRebornCompartment", "MiniMapCompassRing", "MinimapCompassTexture" }) do
    BLIZZARD[n] = true
end
local function launcherName(name)
    if name:find("^LibDBIcon10_") then return true end
    local l = name:lower()
    if l:find("^blizzuireborn") or l:find("^nxmap") or l:find("gathernote") then return false end
    if l:find("minimap") or l:find("mmbut") or l:find("mmbutton") then
        return l:find("button") or l:find("but$") or l:find("icon") or l:find("launcher")
    end
    return false
end
local function prettify(name)
    local n = name:gsub("^LibDBIcon10_", ""):gsub("_?[Mm]ini[Mm]ap[Bb]utton", ""):gsub("_?MMButton", ""):gsub("_?MMBut$", "")
    n = n:gsub("_?[Mm]ini[Mm]ap", ""):gsub("Button$", ""):gsub("_", " ")
    n = n:gsub("(%l)(%u)", "%1 %2")
    return A.Trim(n) ~= "" and A.Trim(n) or name
end
local function iconOf(f)
    local best
    for _, r in ipairs({ f:GetRegions() }) do
        if r.GetObjectType and r:GetObjectType() == "Texture" then
            local t, n = r:GetTexture(), r:GetName() or ""
            if type(t) == "string" then
                if t:find("[Ii]cons") or n:find("[Ii]con$") then return t end
                if not best and not t:find("Border") and not t:find("Highlight") and not t:find("Background") then best = t end
            end
        end
    end
    return best
end
function A:CollectMinimapButtons(known)
    if self.db and self.db.collectButtons == false then return end
    local sources = {}
    for _, parent in ipairs({ Minimap, MinimapBackdrop, MinimapCluster }) do
        if parent then for _, c in ipairs({ parent:GetChildren() }) do sources[#sources + 1] = c end end
    end
    local doc = _G.Nx and Nx.Map and Nx.Map.Doc
    if doc and type(doc.MMF1) == "table" then for _, c in ipairs(doc.MMF1) do sources[#sources + 1] = c end end
    for _, f in ipairs(sources) do
        local name = f.GetName and f:GetName()
        if name and not BLIZZARD[name] and not known[f] and launcherName(name) and f:IsObjectType("Button") then
            local w, h = f:GetWidth(), f:GetHeight()
            local id = "mm:" .. name
            if self.launchers[id] or (f:IsShown() and w >= 12 and w <= 48 and h >= 12 and h <= 48) then
                if not self.launchers[id] then
                    self.launchers[id] = { id = id, label = prettify(name), frame = f, icon = iconOf(f), legacy = true, generic = true }
                end
                known[f] = true
            end
        end
    end
end

function A:ClickLauncher(entry, row, button)
    self.compartmentMenu:Hide()
    if entry.obj then
        if type(entry.obj.OnClick) == "function" then
            local ok, err = pcall(entry.obj.OnClick, row, button)
            if not ok then self:Error(err) end
        end
    elseif entry.frame then
        -- forward the click the way the button expects it (never both)
        if entry.frame:GetScript("OnClick") then
            self:CallLegacy(entry.frame, "OnClick", button, false)
        else
            self:CallLegacy(entry.frame, "OnMouseDown", button)
            self:CallLegacy(entry.frame, "OnMouseUp", button)
        end
    end
end
function A:LauncherTooltip(entry, row)
    GameTooltip:SetOwner(row, "ANCHOR_LEFT")
    if entry.obj and type(entry.obj.OnTooltipShow) == "function" then
        local ok, err = pcall(entry.obj.OnTooltipShow, GameTooltip); if not ok then self:Error(err) end
        GameTooltip:Show()
    elseif entry.obj and type(entry.obj.OnEnter) == "function" then
        local ok, err = pcall(entry.obj.OnEnter, row); if not ok then self:Error(err) end
    elseif entry.frame and entry.frame:GetScript("OnEnter") then
        self:CallLegacy(entry.frame, "OnEnter")
        if GameTooltip:IsShown() then GameTooltip:ClearAllPoints(); GameTooltip:SetPoint("TOPRIGHT", row, "TOPLEFT", -4, 0) end
    else
        GameTooltip:SetText(entry.label); GameTooltip:Show()
    end
end

function A:InitCompartment()
    local b = CreateFrame("Button", "BlizzUIRebornCompartment", UIParent)
    A.Size(b, 30, 30)
    b:SetFrameStrata("MEDIUM"); b:SetFrameLevel(20)
    A.StylePanel(b)
    b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square")
    for row = 0, 2 do for col = 0, 2 do
        local dot = b:CreateTexture(nil, "ARTWORK"); A.Size(dot, 4, 4)
        dot:SetPoint("TOPLEFT", b, "TOPLEFT", 7 + col * 6, -7 - row * 6); dot:SetTexture(.9, .76, .35, 1)
    end end
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:SetScript("OnClick", function() if A.compartmentMenu:IsShown() then A.compartmentMenu:Hide() else A:ShowCompartment() end end)
    b:SetScript("OnEnter", function(f) GameTooltip:SetOwner(f, "ANCHOR_LEFT"); GameTooltip:SetText("Addon Compartment"); GameTooltip:AddLine("Click to browse your addons.", 1, 1, 1); GameTooltip:Show() end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    local def = self.elements.compartment
    def.frame, def.bound = b, true
    local menu = CreateFrame("Frame", "BlizzUIRebornCompartmentMenu", UIParent)
    menu:SetFrameStrata("DIALOG"); menu:SetClampedToScreen(true); menu:EnableMouse(true)
    A.StylePanel(menu)
    menu.title = A.Text(menu, 13, C.gold); menu.title:SetPoint("TOPLEFT", menu, "TOPLEFT", 14, -12)
    menu.rows = {}
    menu:Hide()
    table.insert(UISpecialFrames, "BlizzUIRebornCompartmentMenu")
    self.compartmentMenu = menu
end
-- Where the button sits when the layout has no custom position.
function A:CompartmentAutoPosition()
    if self.compartmentSlot then
        return "CENTER", UIParent, "BOTTOMLEFT", self.compartmentSlot[1], self.compartmentSlot[2]
    end
    local ref = self:MapReference()
    if ref then return "TOPRIGHT", ref, "BOTTOMLEFT", 12, 10 end -- just outside the minimap's lower-left
    return "TOPRIGHT", UIParent, "TOPRIGHT", -190, -200
end
function A:PlaceCompartment()
    local def = self.elements.compartment
    local b = def.frame
    if not b then return end
    local e = self.draft and self.draft.frames.compartment
    local scale = e and e.scale and e.scale / 100 or 1
    local key
    if e and e.point then key = "c:" .. e.point .. e.x .. ":" .. e.y .. ":" .. scale
    else
        local p, rel, rp, x, y = self:CompartmentAutoPosition()
        key = "a:" .. tostring(rel) .. p .. x .. y .. scale
    end
    if def.placed == key then return end
    def.placed = key
    b:SetScale(scale)
    if e and e.point then self:PlaceClamped(b, e.point, e.x, e.y)
    else
        local p, rel, rp, x, y = self:CompartmentAutoPosition()
        b:ClearAllPoints(); b:SetPoint(p, rel, rp, x, y)
    end
end
function A:RefreshCompartment()
    if A.Combat() then return end
    local def = self.elements.compartment
    if not def.frame then return end
    local enabled = self.active and self.draft and self.draft.compartment
    A.Visible(def.frame, enabled)
    if not enabled then
        self.compartmentMenu:Hide()
        for f in pairs(self.launcherLeases) do self:ReleaseLease(f) end
        self.launcherLeases = {}
        return
    end
    self:DiscoverLaunchers()
    for _, entry in pairs(self.launchers) do
        for _, target in ipairs({ entry.frame, entry.container }) do
            if target and not self.launcherLeases[target] then
                local lease = self:Lease(target, { "SetAlpha", "EnableMouse" })
                if lease then
                    self.launcherLeases[target] = lease
                    self:WriteLease(lease, function(f) f:SetAlpha(0); f:EnableMouse(false) end)
                end
            end
        end
    end
    self:FilterCarboniteDock()
    self:PlaceCompartment()
end
A.Kinds.compartment = {
    apply = function(self, def) self:RefreshCompartment(); def.placed = nil; self:PlaceCompartment() end,
    rect = function(self, def) return A.Rect(def.frame) end,
}
function A:ShowCompartment()
    local panel = self.compartmentMenu
    self:DiscoverLaunchers()
    local entries = {}
    for _, e in pairs(self.launchers) do entries[#entries + 1] = e end
    table.sort(entries, function(a, b) return a.label:lower() < b.label:lower() end)
    for _, r in ipairs(panel.rows) do r:Hide() end
    local perColumn = math.max(1, math.floor((UIParent:GetHeight() - 120) / 26))
    for i, entry in ipairs(entries) do
        local row = panel.rows[i]
        if not row then
            row = CreateFrame("Button", nil, panel); A.Size(row, 190, 24)
            row:RegisterForClicks("LeftButtonUp", "RightButtonUp", "MiddleButtonUp")
            row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
            row.icon = row:CreateTexture(nil, "ARTWORK"); A.Size(row.icon, 20, 20); row.icon:SetPoint("LEFT", row, "LEFT", 4, 0)
            row.text = A.Text(row, 12, C.text); row.text:SetPoint("LEFT", row.icon, "RIGHT", 8, 0); row.text:SetWidth(150); row.text:SetJustifyH("LEFT")
            panel.rows[i] = row
        end
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", panel, "TOPLEFT", 10 + math.floor((i - 1) / perColumn) * 196, -34 - ((i - 1) % perColumn) * 26)
        row.icon:SetTexture(entry.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
        row.text:SetText(entry.label)
        row:SetScript("OnClick", function(f, button) A:ClickLauncher(entry, f, button) end)
        row:SetScript("OnEnter", function(f) A:LauncherTooltip(entry, f) end)
        row:SetScript("OnLeave", function(f)
            if entry.obj and type(entry.obj.OnLeave) == "function" then pcall(entry.obj.OnLeave, f)
            elseif entry.frame then A:CallLegacy(entry.frame, "OnLeave") end
            GameTooltip:Hide()
        end)
        row:Show()
    end
    panel.title:SetText(#entries > 0 and "Addons" or "No addon launchers found")
    A.Size(panel, math.max(220, 20 + 196 * math.max(1, math.ceil(#entries / perColumn))), 44 + 26 * math.max(1, math.min(#entries, perColumn)))
    panel:ClearAllPoints()
    if self.compartmentSlot and self.statusRef and self.statusRef ~= self.statusFallback then
        -- Carbonite: open beside the map window, top-aligned (Retail-like)
        panel:SetPoint("TOPRIGHT", self.statusRef, "TOPLEFT", -4, 0)
    else
        panel:SetPoint("TOPRIGHT", self.elements.compartment.frame, "BOTTOMLEFT", 0, -4)
    end
    panel:Show()
end
