-- Stance badge: a round badge to the right of the player's level (mirroring
-- the level circle across the portrait) showing the active warrior stance,
-- death knight presence or paladin seal. Hidden when none is active, in a
-- vehicle, and for other classes. Stock art only: the round gold ring used by
-- minimap buttons and a round-cropped spell icon. It never takes the mouse,
-- so clicks on the player frame (target, menu) are never blocked.
local A = BlizzUIReborn
local BADGE_CLASSES = { WARRIOR = "form", DEATHKNIGHT = "form", PALADIN = "seal" }
-- 3.3.5 seals (spell IDs; names come from the client, so any locale works)
local SEALS = { 21084, 20154, 20164, 20165, 20166, 20375, 31801, 53736, 31892, 53720 }
local sealIds, sealNames = {}, nil
for _, id in ipairs(SEALS) do sealIds[id] = true end

local playerClass = select(2, UnitClass("player"))
table.insert(A.elements.player.settings, A.Schema.check("stanceBadge", "Show Stance Badge", true, not BADGE_CLASSES[playerClass]))

local function seal()
    if not sealNames or not next(sealNames) then
        sealNames = {}
        for _, id in ipairs(SEALS) do local n = GetSpellInfo(id); if n then sealNames[n] = true end end
    end
    for i = 1, 40 do
        local name, _, icon, _, _, _, _, _, _, _, id = UnitBuff("player", i)
        if not name then break end
        if (id and sealIds[id]) or sealNames[name] then return icon, name end
    end
end
local function form()
    local n = GetNumShapeshiftForms and GetNumShapeshiftForms() or 0
    local cur = GetShapeshiftForm and GetShapeshiftForm() or 0
    if cur and cur > 0 and cur <= n then
        local icon, name, active = GetShapeshiftFormInfo(cur)
        if icon and active ~= false then return icon, name end
    end
    for i = 1, n do
        local icon, name, active = GetShapeshiftFormInfo(i)
        if active then return icon, name end
    end
end
-- the icon and name of what is active now, or nil
function A:ActiveClassState()
    local kind = BADGE_CLASSES[select(2, UnitClass("player"))]
    if kind == "seal" then return seal() end
    if kind == "form" then return form() end
end

-- Geometry. The ring is the stock minimap-button border cropped to its
-- visible circle (the file has transparent padding right and below: in
-- LibDBIcon's 53px overlay the ring is the top-left 31px, centred at
-- 15.5/14.5), so the badge frame IS the visible circle.
local RING_TEX = { .011, .575, 0, .564 }
local SIZE = 27        -- visible circle, the size of the level circle
local HOLE = .64       -- the ring's inner opening, as a share of its diameter
-- The level circle's centre mirrored across the portrait's centre (3.3.5
-- PlayerFrame: level text at (-63,-16) and portrait at (-42,+6) from the
-- frame's centre). Measured from the live frames when they are laid out.
local FALLBACK_DX, FALLBACK_DY = 21, -22
local function mirror()
    local px, py, lx, ly
    if PlayerPortrait then px, py = PlayerPortrait:GetCenter() end
    if PlayerLevelText then lx, ly = PlayerLevelText:GetCenter() end
    if px and py and lx and ly then
        local dx, dy = px - lx, ly - py
        if dx >= 8 and dx <= 45 and dy <= 5 and dy >= -45 then return dx, dy end
    end
    return FALLBACK_DX, FALLBACK_DY
end
-- Draw order: the portrait ring, level circle and frame border are drawn by
-- child frames of PlayerFrame (not by PlayerFrame itself), so a child of
-- PlayerFrame at the default level sits under them. The badge goes one
-- level above the highest of those (PlayerFrame's own strata, never higher).
local function artLevel()
    local top = PlayerFrame:GetFrameLevel()
    for _, r in ipairs({ PlayerLevelText, PlayerFrameTexture, PlayerPortrait, PlayerFrameHealthBar, PlayerFrameManaBar }) do
        local parent = r and r.GetParent and r:GetParent()
        if parent and parent.GetFrameLevel then top = math.max(top, parent:GetFrameLevel(), r.GetFrameLevel and r:GetFrameLevel() or 0) end
    end
    return math.min(top + 1, 128)
end
local function build()
    local b = CreateFrame("Frame", "BlizzUIRebornStanceBadge", PlayerFrame)
    A.Size(b, SIZE, SIZE)
    b:EnableMouse(false)
    b.bg = b:CreateTexture(nil, "BACKGROUND")
    b.bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    A.Size(b.bg, SIZE * HOLE, SIZE * HOLE); b.bg:SetPoint("CENTER", b, "CENTER", 0, 0)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    A.Size(b.icon, SIZE * HOLE, SIZE * HOLE); b.icon:SetPoint("CENTER", b, "CENTER", 0, 0)
    b.ring = b:CreateTexture(nil, "OVERLAY")
    b.ring:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    b.ring:SetTexCoord(RING_TEX[1], RING_TEX[2], RING_TEX[3], RING_TEX[4])
    b.ring:SetAllPoints(b)
    b:Hide()
    return b
end
-- position and stacking: our own frame only (nothing protected is touched),
-- redone when shown and when the player frame's layout changes
function A:PlaceClassBadge()
    local b = self.classBadge
    if not b then return end
    local dx, dy = mirror()
    if b.dx ~= dx or b.dy ~= dy then
        b:ClearAllPoints()
        if PlayerPortrait then b:SetPoint("CENTER", PlayerPortrait, "CENTER", dx, dy)
        else b:SetPoint("CENTER", PlayerFrame, "CENTER", -42 + dx, 6 + dy) end
        b.dx, b.dy = dx, dy
    end
    local lvl = artLevel()
    if b:GetFrameLevel() ~= lvl then b:SetFrameLevel(lvl) end
    if b:GetFrameStrata() ~= PlayerFrame:GetFrameStrata() then b:SetFrameStrata(PlayerFrame:GetFrameStrata()) end
end
function A:UpdateClassBadge()
    if not PlayerFrame then return end
    local want
    if self.active and self.draft and BADGE_CLASSES[select(2, UnitClass("player"))] and not (UnitHasVehicleUI and UnitHasVehicleUI("player")) then
        want = self:Settings(self.elements.player).stanceBadge ~= false
    end
    local icon, name
    if want then icon, name = self:ActiveClassState() end
    local b = self.classBadge
    if not icon then
        if b then b:Hide(); b.state = nil end
        return
    end
    if not b then b = build(); self.classBadge = b end
    if b.state ~= icon then
        b.state = icon
        if SetPortraitToTexture then SetPortraitToTexture(b.icon, icon) else b.icon:SetTexture(icon) end
    end
    b.stateName = name
    self:PlaceClassBadge()
    b:Show()
end
local function refresh() if A.ready then A:UpdateClassBadge() end end
for _, ev in ipairs({ "UPDATE_SHAPESHIFT_FORM", "UPDATE_SHAPESHIFT_FORMS", "PLAYER_ENTERING_WORLD", "PLAYER_ALIVE" }) do A:On(ev, refresh) end
for _, ev in ipairs({ "UNIT_AURA", "UNIT_ENTERED_VEHICLE", "UNIT_EXITED_VEHICLE" }) do
    A:On(ev, function(unit) if unit == "player" then refresh() end end)
end
