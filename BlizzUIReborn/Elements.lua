local A = BlizzUIReborn
local unpack = unpack

-- ----------------------------------------------------------------- schema helpers
local function slider(key, label, min, max, step, default, suffix)
    return { key = key, label = label, kind = "slider", min = min, max = max, step = step, default = default, suffix = suffix }
end
local function check(key, label, default, hidden) return { key = key, label = label, kind = "check", default = default, hidden = hidden } end
local function choice(key, label, default, list)
    local choices = {}
    for _, v in ipairs(list) do choices[#choices + 1] = { value = v[1], label = v[2] } end
    return { key = key, label = label, kind = "choice", default = default, choices = choices }
end
A.Schema = { slider = slider, check = check, choice = choice }
local frameSize = function() return slider("scale", "Frame Size", 50, 150, 5, 100, "%") end
local orientation = function() return choice("orientation", "Orientation", "horizontal", { { "horizontal", "Horizontal" }, { "vertical", "Vertical" } }) end

-- ----------------------------------------------------------------- registry
-- Categories and setting ranges follow the Retail Edit Mode (Blizzard_EditMode
-- EditModeSettingDisplayInfo). Frame behaviour follows the 3.3.5 FrameXML:
-- * player/target/focus are never re-anchored by Blizzard in 3.3.5 (except the
--   vehicle slide of the player frame), so they are not marked user-placed;
-- * frames listed in UIPARENT_MANAGED_FRAME_POSITIONS are taken out of that
--   table while managed (no fields are written on Blizzard frames: the secure
--   frame manager reading addon-written fields would spread taint);
-- * boss frames are re-anchored by the secure frame manager every update with
--   no opt-out, and they only exist in combat, so they cannot be moved reliably
--   on 3.3.5 and are not offered.
local reg = function(t) return A:Register(t) end
local unitSize = function() return slider("scale", "Frame Size", 50, 200, 5, 100, "%") end
local opacity = function(min) return slider("alpha", "Opacity", min or 50, 100, 1, 100, "%") end
reg({ id = "player", label = "Player Frame", category = "Frames", kind = "frame", name = "PlayerFrame", basic = true, settings = { unitSize() } })
reg({ id = "target", label = "Target Frame", category = "Frames", kind = "frame", name = "TargetFrame", basic = true, settings = { unitSize() } })
reg({ id = "focus", label = "Focus Frame", category = "Frames", kind = "frame", name = "FocusFrame", basic = true, settings = { unitSize() } })
reg({ id = "pet", label = "Pet Frame", category = "Frames", kind = "frame", name = "PetFrame", settings = { unitSize() } })
-- Totem timers (shaman totems, death knight ghoul) hang under the player
-- frame. TotemFrame_Update re-anchors it for death knights; the hook lets the
-- drift check put it back.
local playerClass = select(2, UnitClass("player"))
reg({ id = "totemtimers", label = "Totem Timers", category = "Frames", kind = "frame", name = "TotemFrame", preview = { 128, 53 },
    basic = playerClass == "SHAMAN" or playerClass == "DEATHKNIGHT", hooks = { "TotemFrame_Update" }, settings = { unitSize() } })
reg({ id = "targettarget", label = "Target of Target", category = "Frames", kind = "frame", name = "TargetFrameToT", settings = { unitSize() } })
reg({ id = "focustarget", label = "Target of Focus", category = "Frames", kind = "frame", name = "FocusFrameToT", settings = { unitSize() } })
reg({ id = "party", label = "Party Frames", category = "Frames", kind = "frame", name = "PartyMemberFrame1", preview = { 128, 250 }, basic = true, settings = { unitSize() } })

local visibility = function()
    return choice("visibility", "Bar Visible", "always", { { "always", "Always" }, { "combat", "In Combat" }, { "nocombat", "Out of Combat" }, { "hidden", "Hidden" } })
end
for i, prefix in ipairs({ "Action", "MultiBarBottomLeft", "MultiBarBottomRight", "MultiBarRight", "MultiBarLeft" }) do
    local settings = {
        orientation(),
        slider("rows", "# of Rows", 1, 4, 1, 1), slider("icons", "# of Icons", 6, 12, 1, 12),
        slider("scale", "Icon Size", 50, 200, 10, 100, "%"), slider("padding", "Icon Padding", 0, 10, 1, 2),
    }
    if i > 1 then settings[#settings + 1] = visibility() end
    settings[#settings + 1] = check("always", "Always Show Buttons", false)
    if i == 1 then
        settings[#settings + 1] = check("hideArt", "Hide Bar Art", false)
        settings[#settings + 1] = check("hideScrolling", "Hide Bar Scrolling", nil, true) -- old layouts; moved to "paging"
    else
        settings[#settings + 1] = check("enabled", "Enabled", nil, true) -- nil = keep the player's own setting
    end
    reg({ id = "action" .. i, label = "Action Bar " .. i, category = "Action Bars", kind = "bar", secure = true, prefix = prefix,
        barIndex = i, bonusPrefix = i == 1 and "BonusActionButton" or nil, basic = i <= 3, settings = settings })
end
local function names(prefix, n) local t = {}; for i = 1, n do t[i] = prefix .. i end; return t end
local groupSettings = function(default, orderLabel, orderChoices, min, max)
    local t = { orientation() }
    if orderLabel then t[#t + 1] = choice("order", orderLabel, "default", orderChoices) end
    t[#t + 1] = slider("scale", "Size", min or 50, max or 150, 5, 100, "%")
    t[#t + 1] = slider("padding", "Padding", -4, 10, 1, default or 0)
    return t
end
-- Stances, paladin auras, presences, forms: the whole Blizzard bar moves (like
-- the totem bar), so Blizzard's own updates can never pull a button back.
local STANCE_CLASSES = { WARRIOR = true, PALADIN = true, DEATHKNIGHT = true, DRUID = true, ROGUE = true, PRIEST = true }
reg({ id = "stance", label = "Stance Bar", category = "Action Bars", kind = "stancebar", secure = true, preview = { 190, 30 },
    basic = STANCE_CLASSES[playerClass] or false, hooks = { "ShapeshiftBar_Update" }, settings = groupSettings(4) })
reg({ id = "petbar", label = "Pet Bar", category = "Action Bars", kind = "group", secure = true, names = names("PetActionButton", 10), preview = { 330, 30 }, settings = groupSettings(4) })
reg({ id = "possess", label = "Possess Bar", category = "Action Bars", kind = "group", secure = true, names = names("PossessButton", 2), preview = { 64, 30 }, settings = groupSettings(4) })
reg({ id = "paging", label = "Action Bar Page Arrows", category = "Action Bars", kind = "paging", toggle = true, basic = true,
    settings = { slider("scale", "Size", 50, 150, 5, 100, "%"), check("enabled", "Shown", nil, true) } })
reg({ id = "totems", label = "Totem Bar", category = "Action Bars", kind = "totembar", secure = true, preview = { 230, 38 }, settings = { frameSize() } })

reg({ id = "cast", label = "Cast Bar", category = "Combat", kind = "cast", name = "CastingBarFrame", managed = "CastingBarFrame", basic = true,
    preview = { 208, 14 }, settings = { slider("scale", "Bar Size", 100, 150, 10, 100, "%"), check("lock", "Lock to Player Frame", false), check("time", "Show Cast Time", false) } })
-- ConsolidatedBuffs is the root Blizzard anchors BuffFrame and the weapon
-- enchant frame to (BuffFrame_UpdateAllBuffAnchors), so it is what moves.
reg({ id = "buffs", label = "Buffs and Debuffs", category = "Combat", kind = "frame", name = "ConsolidatedBuffs", followers = { "BuffFrame", "TemporaryEnchantFrame" },
    preview = { 300, 110 }, previewAnchor = "TOPRIGHT", basic = true, settings = { unitSize(), opacity() } })
reg({ id = "timers", label = "Timer Bars", category = "Combat", kind = "frame", name = "MirrorTimer1", preview = { 206, 60 }, previewAnchor = "TOP",
    settings = { slider("scale", "Size", 100, 150, 10, 100, "%") } })
reg({ id = "raidwarning", label = "Raid Warnings", category = "Combat", kind = "frame", name = "RaidWarningFrame", preview = { 420, 48 }, previewAnchor = "TOP",
    settings = { slider("scale", "Size", 50, 150, 5, 100, "%") } })

reg({ id = "minimap", label = "Minimap", category = "Misc", kind = "frame", name = "MinimapCluster", noCarbonite = true, basic = true,
    settings = { slider("scale", "Size", 50, 200, 10, 100, "%"), check("rotate", "Rotate Minimap", false) } })
-- WatchFrame is the one frame 3.3.5's frame manager skips when user-placed.
reg({ id = "objectives", label = "Objective Tracker", category = "Misc", kind = "frame", name = "WatchFrame", userPlaced = true, basic = true,
    settings = { slider("height", "Height", 200, 1000, 10, 500), frameSize(), opacity(0) } })
reg({ id = "chat", label = "Chat Frame", category = "Misc", kind = "frame", name = "ChatFrame1", managed = "ChatFrame1", hooks = { "FCF_RestorePositionAndDimensions", "FCF_DockUpdate" }, basic = true,
    settings = { slider("width", "Width", 250, 800, 10, 430), slider("height", "Height", 120, 800, 10, 120) } })
reg({ id = "statusbars", label = "Experience & Reputation Bars", category = "Misc", kind = "statusbars", basic = true,
    settings = { slider("scale", "Bar Size", 30, 130, 5, 100, "%") } })
reg({ id = "micro", label = "Micro Menu", category = "Misc", kind = "group",
    names = { "CharacterMicroButton", "SpellbookMicroButton", "TalentMicroButton", "AchievementMicroButton", "QuestLogMicroButton", "ParagonMicroButton",
        "SocialsMicroButton", "PVPMicroButton", "LFDMicroButton", "CollectionsMicroButton", "StoreMicroButton", "MainMenuMicroButton", "HelpMicroButton" },
    hooks = { "MoveMicroButtons", "UpdateMicroButtons" }, basic = true,
    settings = groupSettings(-2, "Order", { { "default", "Default" }, { "reverse", "Reverse" } }, 50, 200) })
reg({ id = "bags", label = "Bags", category = "Misc", kind = "group",
    names = { "KeyRingButton", "CharacterBag3Slot", "CharacterBag2Slot", "CharacterBag1Slot", "CharacterBag0Slot", "MainMenuBarBackpackButton" },
    hooks = { "MainMenuBar_UpdateKeyRing" }, basic = true,
    settings = groupSettings(2, "Direction", { { "default", "Left" }, { "reverse", "Right" } }, 75, 200) })
reg({ id = "durability", label = "Durability Figure", category = "Misc", kind = "frame", name = "DurabilityFrame", preview = { 60, 75 },
    settings = { slider("scale", "Size", 75, 200, 5, 100, "%") } })
reg({ id = "vehicleseat", label = "Vehicle Seat Indicator", category = "Misc", kind = "frame", name = "VehicleSeatIndicator", preview = { 128, 128 },
    settings = { slider("scale", "Size", 50, 100, 5, 100, "%") } })
reg({ id = "tooltip", label = "HUD Tooltip", category = "Misc", kind = "tooltip", preview = { 220, 90 }, settings = {} })

-- ----------------------------------------------------------------- settings
function A:DefaultSettings(def)
    local t = {}
    for _, o in ipairs(def.settings) do t[o.key] = o.default end
    if def.id == "chat" and def.frame then t.width, t.height = A.Round(def.native.width), A.Round(def.native.height) end
    if def.id == "minimap" then t.rotate = GetCVar("rotateMinimap") == "1" end -- keep the player's own preference
    return t
end
-- Effective settings for an element (defaults + draft entry + position).
function A:Settings(def)
    local t = self:DefaultSettings(def)
    local e = self.draft and self.draft.frames[def.id]
    if e then for k, v in pairs(e) do t[k] = v end end
    if not t.point and def.nativeRect then
        local r = def.nativeRect
        t.point, t.x, t.y = A.ToPosition(r[1], r[2], r[3], r[4])
    end
    return t
end
function A:EnsureEntry(id)
    local def = self.elements[id]
    local e = self.draft.frames[id]
    if not e then
        e = self:Settings(def)
        self.draft.frames[id] = e
    end
    return e
end
function A:SetSetting(id, key, value)
    if A.Combat() and self:IsSecure(self.elements[id]) then return nil, "Not available in combat." end
    local e = self:EnsureEntry(id)
    e[key] = value
    self:ApplyElement(id)
    self:MarkDirty()
    return true
end
function A:SetPosition(id, point, x, y, quiet)
    local e = self:EnsureEntry(id)
    e.point, e.x, e.y = point, A.Round(x, .1), A.Round(y, .1)
    self:ApplyElement(id)
    if not quiet then self:MarkDirty() end
end
function A:ResetPosition(id)
    local def = self.elements[id]
    local e = self:EnsureEntry(id)
    local base = self.draft.base
    local pos = base == "Modern" and self.ModernPositions[id]
    if pos then e.point, e.x, e.y = pos[1], pos[2], pos[3]
    elseif def.nativeRect then
        local r = def.nativeRect
        e.point, e.x, e.y = A.ToPosition(r[1], r[2], r[3], r[4])
    end
    self:ApplyElement(id, true)
    self:MarkDirty()
end
function A:RevertElement(id)
    local saved = self.saved.frames[id]
    self.draft.frames[id] = A.Copy(saved)
    if not saved then self:RestoreElement(id) else self:ApplyElement(id, true) end
    self:MarkDirty()
end

-- ----------------------------------------------------------------- binding
local function unionRect(frames)
    local L, B, R, T
    for _, f in ipairs(frames) do
        local l, b, w, h = A.Rect(f)
        if l then
            L, B = math.min(L or l, l), math.min(B or b, b)
            R, T = math.max(R or l + w, l + w), math.max(T or b + h, b + h)
        end
    end
    if L then return { L, B, R - L, T - B } end
end
A.UnionRect = unionRect
function A:BindElement(def)
    if def.bound then return def.frame end
    if def.kind == "status" or def.kind == "compartment" then return def.frame end
    if A.Combat() and def.secure then return end
    local kind = self.Kinds[def.kind]
    local ok, frame = pcall(kind.bind, self, def)
    if not ok then self.lastError = "Bind " .. def.id .. ": " .. tostring(frame); return end
    if not frame then return end
    def.frame, def.bound = frame, true
    for _, fn in ipairs(def.hooks or {}) do
        self:Hook(fn, function() self:QueueElement(def.id) end)
    end
    return frame
end
function A:ElementSize(def)
    if def.kind == "bar" or def.kind == "group" or def.kind == "stancebar" then
        local e = self:Settings(def)
        local w, h = self.Kinds[def.kind].measure(self, def, e)
        local parent = def.frame and def.frame:GetParent()
        local rel = parent and parent:GetEffectiveScale() / UIParent:GetEffectiveScale() or 1
        local s = (e.scale or 100) / 100 * rel
        return w * s, h * s
    end
    local f = def.frame
    local w, h
    if f then
        local rel = f:GetEffectiveScale() / UIParent:GetEffectiveScale()
        w, h = f:GetWidth() * rel, f:GetHeight() * rel
    end
    if (not w or w < 4 or h < 4) and def.preview then w, h = def.preview[1], def.preview[2] end
    return math.max(w or 100, 4), math.max(h or 40, 4)
end
-- The rectangle a stored position refers to (the frame or bar holder).
function A:AnchorRect(def)
    local f = def.frame
    if f then
        local l, b, w, h = A.Rect(f)
        if l and w > 1 and h > 1 then return l, b, w, h end
    end
    local e = self:Settings(def)
    if not e.point then return end
    local w, h = self:ElementSize(def)
    local l, b = A.FromPosition(e.point, e.x, e.y, w, h)
    return l, b, w, h
end
-- The rectangle shown as the edit-mode selection (UIParent units). Frames
-- whose visible content extends beyond them (buffs, party/boss chains) use a
-- preview box sharing one corner with the real frame.
function A:ElementRect(def)
    local kind = self.Kinds[def.kind]
    if kind.rect then local l, b, w, h = kind.rect(self, def); if l then return l, b, w, h end end
    local l, b, w, h = self:AnchorRect(def)
    if not l then return end
    if def.preview and def.kind == "frame" then
        local rel = def.frame and def.frame:GetEffectiveScale() / UIParent:GetEffectiveScale() or 1
        local pw, ph = def.preview[1] * rel, def.preview[2] * rel
        local corner = def.previewAnchor or "TOPLEFT"
        local cx, cy = A.PointXY(corner, l, b, w, h)
        l = corner:find("RIGHT") and cx - pw or corner:find("LEFT") and cx or cx - pw / 2
        b = corner:find("TOP") and cy - ph or corner:find("BOTTOM") and cy or cy - ph / 2
        w, h = pw, ph
    end
    return l, b, w, h
end

-- ----------------------------------------------------------------- apply engine
-- Secure/protected elements can only be changed out of combat.
function A:IsSecure(def)
    if def.secure then return true end
    local f = def.frame
    if f and f.IsProtected and f:IsProtected() then return true end
    for _, list in ipairs({ def.buttons or {}, def.followerData or {} }) do
        for _, e in ipairs(list) do if e.frame.IsProtected and e.frame:IsProtected() then return true end end
    end
    return false
end
function A:ApplyElement(id, force)
    local def = self.elements[id]
    if not def or not self.active then return end
    if id == "player" and self.UpdateClassBadge then self:UpdateClassBadge() end
    if def.kind == "status" or def.kind == "compartment" then
        return self.Kinds[def.kind].apply(self, def, self:Settings(def))
    end
    if not self:BindElement(def) then return end
    if A.Combat() and self:IsSecure(def) then def.pending = true; self.pendingApply = true; return end
    local entry = self.draft.frames[id]
    if not entry then
        if def.applied then self:RestoreElement(id) end
        return
    end
    if not entry.point and entry.x then self:MigrateEntry(def, entry) end
    if not force and def.applied and A.Equal(def.appliedEntry, entry) then return end
    local settings = self:Settings(def)
    self.applying = true
    self:Run("Apply " .. def.label, self.Kinds[def.kind].apply, self, def, settings)
    self.applying = nil
    def.pending = nil
    -- even a partial apply is recorded so Restore can undo it
    def.applied = true
    def.appliedEntry = A.Copy(entry)
    self:RecordAnchors(def)
    if self.OnElementApplied then self:OnElementApplied(def) end
end
function A:RestoreElement(id)
    local def = self.elements[id]
    if not def or not def.applied then return end
    if A.Combat() and self:IsSecure(def) then def.pending = true; self.pendingApply = true; return end
    local kind = self.Kinds[def.kind]
    -- cleared first: Blizzard functions called while restoring fire our hooks
    def.applied, def.appliedEntry, def.anchors = nil, nil, nil
    if kind.restore then self:Run("Restore " .. def.label, kind.restore, self, def) end
    if self.OnElementApplied then self:OnElementApplied(def) end
end
function A:RestoreAllElements()
    for _, id in ipairs(self.order) do self:RestoreElement(id) end
end
function A:ApplyAll(force)
    if not self.active then return end
    self.pendingApply = nil
    for _, id in ipairs(self.order) do self:ApplyElement(id, force) end
end
-- Re-apply one element on the next frame (after Blizzard code finished).
function A:QueueElement(id)
    local def = self.elements[id]
    if not def or not def.applied then return end
    self:After(0, function() self:ApplyElement(id, true) end, "q:" .. id)
end

-- Anchor bookkeeping for drift detection: Blizzard code (vehicle, pet bar
-- slide, chat docking, reputation updates...) sometimes re-anchors frames.
function A:RecordAnchors(def)
    local list = {}
    for _, f in ipairs(self.Kinds[def.kind].watch and self.Kinds[def.kind].watch(self, def) or { def.frame }) do
        if f and f:GetNumPoints() > 0 then list[#list + 1] = { f, { f:GetPoint(1) }, f:GetNumPoints() } end
    end
    def.anchors = list
end
function A:CheckDrift()
    local combat = A.Combat()
    for _, id in ipairs(self.order) do
        local def = self.elements[id]
        if def.applied and def.anchors and not (combat and self:IsSecure(def)) then
            for _, a in ipairs(def.anchors) do
                local f, e = a[1], a[2]
                local p, rel, rp, x, y = f:GetPoint(1)
                -- Blizzard often calls SetPoint without ClearAllPoints, adding a
                -- second anchor: a changed point count is drift too
                if f:GetNumPoints() ~= a[3] or p ~= e[1] or rel ~= e[2] or rp ~= e[3]
                    or math.abs((x or 0) - (e[4] or 0)) > .5 or math.abs((y or 0) - (e[5] or 0)) > .5 then
                    self:ApplyElement(id, true)
                    break
                end
            end
        end
    end
end

-- ----------------------------------------------------------------- kinds
A.Kinds = {}
local managedSaved = {}
local function unmanage(name)
    if name and UIPARENT_MANAGED_FRAME_POSITIONS and UIPARENT_MANAGED_FRAME_POSITIONS[name] then
        managedSaved[name] = UIPARENT_MANAGED_FRAME_POSITIONS[name]
        UIPARENT_MANAGED_FRAME_POSITIONS[name] = nil
    end
end
local function remanage(name)
    if name and managedSaved[name] and UIPARENT_MANAGED_FRAME_POSITIONS then
        UIPARENT_MANAGED_FRAME_POSITIONS[name] = managedSaved[name]
        managedSaved[name] = nil
    end
end
local function setUserPlaced(f, v)
    if not f.SetUserPlaced then return end
    local movable = f:IsMovable()
    if not movable then f:SetMovable(true) end
    f:SetUserPlaced(v and true or false)
    if not movable and not v then f:SetMovable(false) end
end
-- Place with the element kept on screen (the stored position is unchanged).
function A:PlaceClamped(frame, point, x, y)
    local rel = frame:GetEffectiveScale() / UIParent:GetEffectiveScale()
    local w, h = frame:GetWidth() * rel, frame:GetHeight() * rel
    local W, H = UIParent:GetWidth(), UIParent:GetHeight()
    local l, b = A.FromPosition(point, x, y, w, h)
    local cl, cb = A.Clamp(l, 0, math.max(0, W - w)), A.Clamp(b, 0, math.max(0, H - h))
    x, y = x + (cl - l), y + (cb - b)
    A.PlaceAt(frame, point, x, y)
end

-- frame ------------------------------------------------------------
A.Kinds.frame = {
    bind = function(self, def)
        if def.noCarbonite and _G.Nx then return end
        local f = _G[def.name]
        if not f then return end
        def.native = A.Snapshot(f)
        def.nativeRect = unionRect({ f })
        def.followerData = {}
        local ml, mb, mw, mh = A.Rect(f)
        for _, n in ipairs(def.followers or {}) do
            local fo = _G[n]
            if fo and fo:GetNumPoints() > 0 then
                local l, b, w, h = A.Rect(fo)
                if l and ml then
                    -- followers hang off the root's TOPRIGHT, the same point
                    -- Blizzard uses, so its own re-anchoring never conflicts
                    local k = UIParent:GetEffectiveScale() / fo:GetEffectiveScale()
                    def.followerData[#def.followerData + 1] = { frame = fo, native = A.Snapshot(fo), rect = { l, b, w, h },
                        dx = ((l + w) - (ml + mw)) * k, dy = ((b + h) - (mb + mh)) * k }
                end
            end
        end
        return f
    end,
    apply = function(self, def, e)
        local f = def.frame
        unmanage(def.managed)
        if def.userPlaced then setUserPlaced(f, true) end
        local k = (e.scale or 100) / 100
        f:SetScale(def.native.scale * k)
        if def.id == "chat" then A.Size(f, e.width, e.height) end
        if def.id == "objectives" then f:SetHeight(e.height) end
        if e.alpha then f:SetAlpha(e.alpha / 100) end
        self:PlaceClamped(f, e.point, e.x, e.y)
        for _, fd in ipairs(def.followerData) do
            fd.frame:SetScale(fd.native.scale * k)
            fd.frame:ClearAllPoints()
            fd.frame:SetPoint("TOPRIGHT", f, "TOPRIGHT", fd.dx, fd.dy)
            if e.alpha then fd.frame:SetAlpha(e.alpha / 100) end
        end
        if def.id == "minimap" and e.rotate ~= nil then
            local want = e.rotate and "1" or "0"
            if GetCVar("rotateMinimap") ~= want then
                def.nativeRotate = def.nativeRotate or GetCVar("rotateMinimap")
                SetCVar("rotateMinimap", want)
                if Minimap_UpdateRotationSetting then Minimap_UpdateRotationSetting() end
            end
        end
    end,
    restore = function(self, def)
        local f = def.frame
        A.RestoreGeometry(f, def.native)
        f:SetAlpha(def.native.alpha or 1)
        if def.userPlaced then setUserPlaced(f, def.native.userPlaced) end
        if f.SetMovable and def.native.movable ~= nil then f:SetMovable(def.native.movable) end
        remanage(def.managed)
        for _, fd in ipairs(def.followerData) do A.RestoreGeometry(fd.frame, fd.native); fd.frame:SetAlpha(fd.native.alpha or 1) end
        if def.nativeRotate then SetCVar("rotateMinimap", def.nativeRotate); def.nativeRotate = nil
            if Minimap_UpdateRotationSetting then Minimap_UpdateRotationSetting() end end
    end,
}
-- Where a stored position for the old "buffs" root (BuffFrame, before 0.4)
-- lands relative to the new root (ConsolidatedBuffs), for a given anchor point.
function A:LegacyBuffShift(point)
    local def = self.elements.buffs
    if not def.bound then return 0, 0 end
    local old
    for _, fd in ipairs(def.followerData) do if fd.frame == _G.BuffFrame then old = fd.rect end end
    local new = def.nativeRect
    if not old or not new then return 0, 0 end
    local ox, oy = A.PointXY(point, old[1], old[2], old[3], old[4])
    local nx, ny = A.PointXY(point, new[1], new[2], new[3], new[4])
    return nx - ox, ny - oy
end

-- cast bar ---------------------------------------------------------
A.Kinds.cast = {
    bind = function(self, def)
        local f = A.Kinds.frame.bind(self, def)
        if not f then return end
        def.native.width, def.native.height = nil, nil -- size belongs to the cast bar style, not the layout
        def.timer = f:CreateFontString(nil, "OVERLAY")
        def.timer:SetFontObject(A.Font(10, "OUTLINE"))
        def.timer:SetPoint("RIGHT", f, "RIGHT", -3, 0)
        def.timer:Hide()
        f:HookScript("OnUpdate", function(bar)
            local e = def.applied and def.appliedEntry
            if e and e.time and bar.maxValue and bar.value and (bar.casting or bar.channeling) then
                local left = bar.channeling and bar.value or (bar.maxValue - bar.value)
                def.timer:SetText(string.format("%.1f", math.max(0, left))); def.timer:Show()
            elseif def.timer:IsShown() then def.timer:Hide() end
        end)
        return f
    end,
    apply = function(self, def, e)
        local f = def.frame
        unmanage(def.managed)
        f:SetScale(def.native.scale * e.scale / 100)
        if e.lock and PlayerFrame then
            f:ClearAllPoints()
            f:SetPoint("TOP", PlayerFrame, "BOTTOM", 0, -12)
        else
            self:PlaceClamped(f, e.point, e.x, e.y)
        end
        if not e.time then def.timer:Hide() end
    end,
    restore = function(self, def)
        A.Kinds.frame.restore(self, def)
        def.timer:Hide()
    end,
}

-- action bars ------------------------------------------------------
local artNames = { "MainMenuBarTexture0", "MainMenuBarTexture1", "MainMenuBarTexture2", "MainMenuBarTexture3", "MainMenuBarLeftEndCap",
    "MainMenuBarRightEndCap", "MainMenuBarMaxLevelBar", "BonusActionBarTexture0", "BonusActionBarTexture1", "MainMenuBarMicroExtension" }
local function setArt(list, hide, store)
    for _, n in ipairs(list) do
        local r = _G[n]
        if r then
            if not store[n] then store[n] = { alpha = r:GetAlpha(), mouse = r.IsMouseEnabled and r:IsMouseEnabled() } end
            r:SetAlpha(hide and 0 or store[n].alpha)
            if r.EnableMouse and store[n].mouse ~= nil then r:EnableMouse((not hide) and store[n].mouse and true or false) end
        end
    end
end
local barToggleIndex = { [2] = 1, [3] = 2, [4] = 3, [5] = 4 }
local function barVisibleSetting(i) return _G["SHOW_MULTI_ACTIONBAR_" .. barToggleIndex[i]] and true or false end
-- 3.3.5 only shows MultiBarLeft (bar 5) when MultiBarRight (bar 4) is on too.
-- The toggles are saved with SetActionBarToggles (so they load cleanly next
-- session); the globals are updated so the change shows immediately.
local function setBarEnabled(i, v)
    local changed = false
    local function set(idx, val)
        if barVisibleSetting(idx) ~= val then _G["SHOW_MULTI_ACTIONBAR_" .. barToggleIndex[idx]] = val and 1 or nil; changed = true end
    end
    set(i, v)
    if i == 5 and v then set(4, true) end
    if i == 4 and not v then set(5, false) end
    if not changed then return end
    SetActionBarToggles(SHOW_MULTI_ACTIONBAR_1, SHOW_MULTI_ACTIONBAR_2, SHOW_MULTI_ACTIONBAR_3, SHOW_MULTI_ACTIONBAR_4, ALWAYS_SHOW_MULTIBARS)
    if MultiActionBar_Update then MultiActionBar_Update() end
end
A.SetBarEnabled, A.BarVisibleSetting = setBarEnabled, barVisibleSetting
local function gridLayout(count, rows, vertical)
    local cols = math.ceil(count / rows)
    rows = math.ceil(count / cols)
    if vertical then return rows, cols end
    return cols, rows
end
A.Kinds.bar = {
    bind = function(self, def)
        local buttons = {}
        for i = 1, 12 do
            local b = _G[def.prefix .. "Button" .. i]
            if not b then return end
            buttons[i] = { frame = b, native = A.Snapshot(b) }
        end
        def.buttons = buttons
        def.bonus = {}
        if def.bonusPrefix then
            for i = 1, 12 do
                local b = _G[def.bonusPrefix .. i]
                if b then def.bonus[#def.bonus + 1] = { frame = b, native = A.Snapshot(b) } end
            end
        end
        def.nativeEnabled = def.barIndex > 1 and barVisibleSetting(def.barIndex) or nil
        local frames = {}
        for _, e in ipairs(buttons) do frames[#frames + 1] = e.frame end
        def.nativeRect = unionRect(frames) or { 300, 20, 454, 36 }
        local holder = CreateFrame("Frame", "BlizzUIRebornBar" .. def.id, buttons[1].native.parent)
        A.Size(holder, def.nativeRect[3], def.nativeRect[4])
        holder:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", def.nativeRect[1], def.nativeRect[2])
        def.native = A.Snapshot(holder)
        def.art = {}
        return holder
    end,
    measure = function(self, def, e)
        local bw, bh = def.buttons[1].native.width, def.buttons[1].native.height
        local cols, rows = gridLayout(e.icons, e.rows, e.orientation == "vertical")
        return cols * (bw + e.padding) - e.padding, rows * (bh + e.padding) - e.padding
    end,
    apply = function(self, def, e)
        local holder = def.frame
        local bw, bh = def.buttons[1].native.width, def.buttons[1].native.height
        local vertical = e.orientation == "vertical"
        local cols = math.ceil(e.icons / e.rows)
        local w, h = A.Kinds.bar.measure(self, def, e)
        holder:SetScale(e.scale / 100)
        A.Size(holder, w, h)
        self:PlaceClamped(holder, e.point, e.x, e.y)
        local visible = self:BarVisibleNow(e)
        local function layout(list, slots)
            for i, entry in ipairs(list) do
                local b = entry.frame
                b:SetScale(holder:GetEffectiveScale() / b:GetParent():GetEffectiveScale())
                b:ClearAllPoints()
                local col, row = (i - 1) % cols, math.floor((i - 1) / cols)
                if vertical then col, row = row, col end
                local x, y = col * (bw + e.padding), -row * (bh + e.padding)
                b:SetPoint("TOPLEFT", holder, "TOPLEFT", x, y)
                local shown = i <= e.icons
                self.barButtons[b] = { def = def, entry = entry, index = i }
                b:SetAlpha(self:ButtonAlpha(def, e, entry, i, visible))
                if b.EnableMouse then b:EnableMouse(shown and visible and entry.native.mouse ~= false) end
                if slots then self:SetEmptySlot(def, i, x, y, bw, bh, e.always and shown and visible) end
            end
        end
        layout(def.buttons, true)
        layout(def.bonus, false)
        for i = e.icons + 1, 12 do self:SetEmptySlot(def, i, 0, 0, bw, bh, false) end
        -- LOW strata: moved bars must not draw over windows (Carbonite quest log,
        -- character panels) that open in MEDIUM strata
        holder:SetFrameStrata("LOW")
        for _, list in ipairs({ def.buttons, def.bonus }) do
            for _, entry in ipairs(list) do entry.frame:SetFrameStrata("LOW") end
        end
        if def.barIndex == 1 then
            setArt(artNames, e.hideArt, def.art)
            -- the invisible bar strip must not keep eating world clicks
            for _, f in ipairs({ MainMenuBar, MainMenuBarArtFrame }) do
                if f and f.EnableMouse then
                    if def.art[f] == nil then def.art[f] = f:IsMouseEnabled() and true or false end
                    pcall(f.EnableMouse, f, (not e.hideArt) and def.art[f])
                end
            end
        elseif e.enabled ~= nil then
            setBarEnabled(def.barIndex, e.enabled)
        end
    end,
    watch = function(self, def) return { def.buttons[1].frame, def.bonus[1] and def.bonus[1].frame } end,
    restore = function(self, def)
        for i = 1, 12 do self:SetEmptySlot(def, i, 0, 0, 0, 0, false) end
        for _, entry in ipairs(def.buttons) do
            A.RestoreGeometry(entry.frame, entry.native)
            entry.frame:SetAlpha(entry.native.alpha)
            if entry.native.mouse ~= nil then entry.frame:EnableMouse(entry.native.mouse) end
        end
        for _, list in ipairs({ def.buttons, def.bonus }) do
            for _, entry in ipairs(list) do if entry.native.strata then entry.frame:SetFrameStrata(entry.native.strata) end end
        end
        for _, entry in ipairs(def.bonus) do
            A.RestoreGeometry(entry.frame, entry.native)
            entry.frame:SetAlpha(entry.native.alpha)
            if entry.native.mouse ~= nil then entry.frame:EnableMouse(entry.native.mouse) end
        end
        if def.barIndex == 1 then
            setArt(artNames, false, def.art)
            for _, f in ipairs({ MainMenuBar, MainMenuBarArtFrame }) do
                if f and def.art[f] ~= nil then pcall(f.EnableMouse, f, def.art[f]) end
            end
        elseif def.nativeEnabled ~= nil then
            setBarEnabled(def.barIndex, def.nativeEnabled)
        end
    end,
}
-- "Always Show Buttons" without touching the secure buttons: an empty-slot
-- picture (the stock UI-Quickslot art) sits under every slot of the bar. A
-- button with an action covers it; an empty slot shows it. Dragging a spell
-- still reveals Blizzard's own grid as usual. (Setting the buttons' "showgrid"
-- attribute from an addon would taint ActionButton_Update in combat.)
function A:SetEmptySlot(def, i, x, y, bw, bh, shown)
    def.slots = def.slots or {}
    local t = def.slots[i]
    if not shown then if t then t:Hide() end; return end
    if not def.slotFrame then
        def.slotFrame = CreateFrame("Frame", nil, def.frame)
        def.slotFrame:SetAllPoints(def.frame)
        def.slotFrame:SetFrameLevel(math.max(0, def.buttons[1].frame:GetFrameLevel() - 1))
    end
    if not t then
        t = def.slotFrame:CreateTexture(nil, "BACKGROUND")
        t:SetTexture("Interface\\Buttons\\UI-Quickslot")
        def.slots[i] = t
    end
    -- the stock slot art is 66px for a 36px button, centred on it
    local k = 66 / 36
    t:ClearAllPoints()
    t:SetPoint("CENTER", def.frame, "TOPLEFT", x + bw / 2, y - bh / 2)
    A.Size(t, bw * k, bh * k)
    t:Show()
end
-- "Always Show Buttons" off: empty slots are blank, like Retail, even when
-- Blizzard's grid is showing them (the "Always Show ActionBars" interface
-- option, or stock bar art). Alpha only, so it also works in combat when a
-- stance or page change empties or fills a slot. While a spell is on the
-- cursor every slot shows, so it can be dropped anywhere.
A.barButtons = {}
local function hasAction(b)
    local id = b.action
    if not id and ActionButton_GetPagedID then id = ActionButton_GetPagedID(b) end
    if not id and b.GetID then id = b:GetID() end
    return id and HasAction(id) and true or false
end
function A:ButtonAlpha(def, e, entry, i, visible)
    if i > e.icons or not visible then return 0 end
    if e.always or self.cursorGrid or hasAction(entry.frame) then return entry.native.alpha end
    return 0
end
function A:RefreshButtonAlpha(b)
    local info = self.barButtons[b]
    if not info or not info.def.applied then return end
    local e = self:Settings(info.def)
    b:SetAlpha(self:ButtonAlpha(info.def, e, info.entry, info.index, self:BarVisibleNow(e)))
end
function A:RefreshAllButtonAlpha()
    for b in pairs(self.barButtons) do self:RefreshButtonAlpha(b) end
end
A:Hook("ActionButton_Update", function(b) if A.active and b then A:RefreshButtonAlpha(b) end end)
A:On("ACTIONBAR_SHOWGRID", function() A.cursorGrid = true; if A.active then A:RefreshAllButtonAlpha() end end)
A:On("ACTIONBAR_HIDEGRID", function() A.cursorGrid = nil; if A.active then A:RefreshAllButtonAlpha() end end)
for _, ev in ipairs({ "ACTIONBAR_SLOT_CHANGED", "ACTIONBAR_PAGE_CHANGED", "UPDATE_BONUS_ACTIONBAR", "PLAYER_ENTERING_WORLD" }) do
    A:On(ev, function() if A.active then A:After(0, function() A:RefreshAllButtonAlpha() end, "buttonAlpha") end end)
end

-- Retail "Bar Visible": Always / In Combat / Out of Combat / Hidden. Applied
-- with alpha + mouse only, at the combat edges (PLAYER_REGEN_DISABLED fires
-- just before lockdown), so key bindings keep working like on Retail.
function A:BarVisibleNow(e, inCombat)
    local v = e.visibility or "always"
    if inCombat == nil then inCombat = A.Combat() end
    if v == "hidden" then return false end
    if v == "combat" then return inCombat end
    if v == "nocombat" then return not inCombat end
    return true
end
function A:UpdateBarVisibility(inCombat)
    for _, id in ipairs(self.order) do
        local def = self.elements[id]
        if def.kind == "bar" and def.applied then
            local e = self:Settings(def)
            if e.visibility and e.visibility ~= "always" then
                local visible = self:BarVisibleNow(e, inCombat)
                for i, entry in ipairs(def.buttons) do
                    local shown = i <= e.icons and visible
                    entry.frame:SetAlpha(self:ButtonAlpha(def, e, entry, i, visible))
                    entry.frame:EnableMouse(shown and entry.native.mouse ~= false)
                    if def.slots and def.slots[i] then A.Visible(def.slots[i], shown and e.always) end
                end
            end
        end
    end
end

-- button groups (micro menu, bags, stance/pet/possess) ------------
A.Kinds.group = {
    bind = function(self, def)
        local list = {}
        for _, n in ipairs(def.names) do
            local b = _G[n]
            if b then list[#list + 1] = { frame = b, native = A.Snapshot(b), name = n } end
        end
        if #list == 0 then return end
        def.buttons = list
        local frames = {}
        for _, e in ipairs(list) do frames[#frames + 1] = e.frame end
        def.nativeRect = unionRect(frames) or { 300, 100, def.preview and def.preview[1] or 200, def.preview and def.preview[2] or 30 }
        if def.preview and (def.nativeRect[3] < def.preview[1] / 2) then def.nativeRect[3] = def.preview[1] end
        local holder = CreateFrame("Frame", "BlizzUIRebornGroup" .. def.id, list[1].native.parent)
        A.Size(holder, def.nativeRect[3], def.nativeRect[4])
        holder:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", def.nativeRect[1], def.nativeRect[2])
        def.native = A.Snapshot(holder)
        return holder
    end,
    visible = function(def)
        local out = {}
        for _, e in ipairs(def.buttons) do if e.frame:IsShown() then out[#out + 1] = e end end
        if #out == 0 then return def.buttons end
        return out
    end,
    measure = function(self, def, e)
        local w, h = 0, 0
        local list = A.Kinds.group.visible(def)
        for i, entry in ipairs(list) do
            local bw, bh = entry.native.width, entry.native.height
            if e.orientation == "vertical" then h = h + bh + (i > 1 and e.padding or 0); w = math.max(w, bw)
            else w = w + bw + (i > 1 and e.padding or 0); h = math.max(h, bh) end
        end
        return math.max(w, 8), math.max(h, 8)
    end,
    apply = function(self, def, e)
        local holder = def.frame
        local w, h = A.Kinds.group.measure(self, def, e)
        holder:SetScale(e.scale / 100)
        A.Size(holder, w, h)
        self:PlaceClamped(holder, e.point, e.x, e.y)
        local offset = 0
        local list = A.Kinds.group.visible(def)
        if e.order == "reverse" then
            local r = {}
            for i = #list, 1, -1 do r[#r + 1] = list[i] end
            list = r
        end
        for _, entry in ipairs(list) do
            local b = entry.frame
            -- the vehicle UI temporarily re-parents micro buttons; leave those alone
            if b:GetParent() == entry.native.parent then
                b:SetScale(holder:GetEffectiveScale() / b:GetParent():GetEffectiveScale())
                b:ClearAllPoints()
                if e.orientation == "vertical" then b:SetPoint("TOPLEFT", holder, "TOPLEFT", 0, -offset)
                else b:SetPoint("BOTTOMLEFT", holder, "BOTTOMLEFT", offset, 0) end
            end
            offset = offset + (e.orientation == "vertical" and entry.native.height or entry.native.width) + e.padding
            if def.secure and b:GetParent() == entry.native.parent then b:SetFrameStrata("LOW") end
        end
    end,
    watch = function(self, def)
        local list = {}
        for _, e in ipairs(def.buttons) do if e.frame:GetParent() == e.native.parent and e.frame:IsShown() then list[#list + 1] = e.frame end end
        return list
    end,
    restore = function(self, def)
        -- restore in native order (chains anchor to earlier buttons)
        for _, entry in ipairs(def.buttons) do
            if entry.frame:GetParent() == entry.native.parent then
                A.RestoreGeometry(entry.frame, entry.native)
                if def.secure and entry.native.strata then entry.frame:SetFrameStrata(entry.native.strata) end
            end
        end
    end,
}

-- shaman totem bar ------------------------------------------------
-- The bar slides itself into Blizzard's default spot from its OnUpdate
-- every time it refreshes (e.g. switching Call of the Elements/Ancestors/
-- Spirits). Moving it by re-anchoring fights that animation. Instead (as
-- Bartender4 does on 3.3.5) it is parented to our holder, its slide script is
-- paused and it is taken out of the frame manager while managed. No Blizzard
-- method is replaced (that would spread taint); paging, flyouts and secure
-- buttons are untouched.
local TOTEM_SCRIPTS = { "OnUpdate" }
A.Kinds.totembar = {
    bind = function(self, def)
        local f = _G.MultiCastActionBarFrame
        if not f then return end
        def.bar = f
        def.barNative = A.Snapshot(f)
        def.nativeRect = unionRect({ f }) or { 300, 100, 230, 38 }
        -- with the slide paused, finish Blizzard's "hide" ourselves (it normally
        -- hides the bar at the end of the slide)
        self:Hook("HideMultiCastActionBar", function()
            if def.locked and f.mode == "hide" and not A.Combat() then f:Hide() end
        end)
        local holder = CreateFrame("Frame", "BlizzUIRebornTotemBar", def.barNative.parent or UIParent)
        A.Size(holder, 230, 38)
        holder:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", def.nativeRect[1], def.nativeRect[2])
        def.native = A.Snapshot(holder)
        return holder
    end,
    apply = function(self, def, e)
        local f, holder = def.bar, def.frame
        holder:SetScale(e.scale / 100)
        A.Size(holder, 230, 38)
        self:PlaceClamped(holder, e.point, e.x, e.y)
        if not def.locked then
            def.scripts = {}
            for _, s in ipairs(TOTEM_SCRIPTS) do def.scripts[s] = f:GetScript(s); f:SetScript(s, nil) end
            f:SetParent(holder)
            f:SetScale(1)
            f:ClearAllPoints()
            def.locked = true
        end
        unmanage("MultiCastActionBarFrame")
        if f:GetParent() ~= holder then f:SetParent(holder) end
        f:ClearAllPoints()
        f:SetPoint("BOTTOMLEFT", holder, "BOTTOMLEFT", 0, 0)
    end,
    watch = function(self, def) return { def.bar } end,
    restore = function(self, def)
        local f = def.bar
        if not def.locked then return end
        def.locked = nil
        remanage("MultiCastActionBarFrame")
        A.RestoreGeometry(f, def.barNative)
        for _, s in ipairs(TOTEM_SCRIPTS) do f:SetScript(s, def.scripts[s]) end
    end,
}

-- stance / aura / presence / form bar ----------------------------------
-- ShapeshiftBar_Update re-anchors ShapeshiftButton1 to ShapeshiftBarFrame
-- (SetPoint without ClearAllPoints) whenever the forms change, even in combat,
-- and the frame manager moves ShapeshiftBarFrame. Moving the buttons one by
-- one fights both: button 1 snapped back while the rest stayed. So, like the
-- totem bar, ShapeshiftBarFrame itself is parented to our holder and taken
-- out of the frame manager; button 1 stays where Blizzard puts it inside the
-- bar, and only buttons 2-10 (which Blizzard never re-anchors) follow the
-- layout's orientation and padding.
local STANCE_ART = { "ShapeshiftBarLeft", "ShapeshiftBarMiddle", "ShapeshiftBarRight" }
local function stanceCount(def)
    local n = GetNumShapeshiftForms and GetNumShapeshiftForms() or 0
    if n <= 0 then
        for _, e in ipairs(def.buttons) do if e.frame:IsShown() then n = n + 1 end end
    end
    if n <= 0 then n = 4 end -- preview size for classes without forms
    return math.min(n, #def.buttons)
end
local function stanceOrigin(def)
    local b1 = def.buttons[1].frame
    for i = 1, b1:GetNumPoints() do
        local p, rel, rp, x, y = b1:GetPoint(i)
        if p == "BOTTOMLEFT" and rel == def.bar and rp == "BOTTOMLEFT" then return x or 0, y or 0 end
    end
    return 11, 3
end
A.Kinds.stancebar = {
    bind = function(self, def)
        local f = _G.ShapeshiftBarFrame
        if not f or not _G.ShapeshiftButton1 then return end
        def.bar = f
        def.barNative = A.Snapshot(f)
        local list, shown = {}, {}
        for i = 1, 10 do
            local b = _G["ShapeshiftButton" .. i]
            if b then
                list[#list + 1] = { frame = b, native = A.Snapshot(b), name = "ShapeshiftButton" .. i }
                if b:IsShown() then shown[#shown + 1] = b end
            end
        end
        def.buttons = list
        def.art = {}
        for _, n in ipairs(STANCE_ART) do
            local t = _G[n]
            if t and t.SetAlpha then def.art[#def.art + 1] = { t, t:GetAlpha() } end
        end
        local r = unionRect(shown)
        if not r then
            local l, b = A.Rect(f)
            local ox, oy = stanceOrigin(def)
            r = { (l or 300) + ox, (b or 100) + oy, def.preview[1], def.preview[2] }
        end
        def.nativeRect = r
        local holder = CreateFrame("Frame", "BlizzUIRebornStanceBar", def.barNative.parent or UIParent)
        A.Size(holder, r[3], r[4])
        holder:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", r[1], r[2])
        def.native = A.Snapshot(holder)
        return holder
    end,
    measure = function(self, def, e)
        local n = stanceCount(def)
        local bw, bh = def.buttons[1].native.width, def.buttons[1].native.height
        if e.orientation == "vertical" then return bw, n * bh + (n - 1) * e.padding end
        return n * bw + (n - 1) * e.padding, bh
    end,
    apply = function(self, def, e)
        local f, holder = def.bar, def.frame
        local w, h = A.Kinds.stancebar.measure(self, def, e)
        holder:SetScale(e.scale / 100)
        A.Size(holder, w, h)
        self:PlaceClamped(holder, e.point, e.x, e.y)
        unmanage("ShapeshiftBarFrame")
        if f:GetParent() ~= holder then f:SetParent(holder) end
        f:SetScale(1)
        def.locked = true
        -- button 1 sits at (ox, oy) inside the bar: put it on the holder's corner
        local ox, oy = stanceOrigin(def)
        local bh = def.buttons[1].native.height
        f:ClearAllPoints()
        if e.orientation == "vertical" then f:SetPoint("BOTTOMLEFT", holder, "TOPLEFT", -ox, -oy - bh)
        else f:SetPoint("BOTTOMLEFT", holder, "BOTTOMLEFT", -ox, -oy) end
        for i = 2, #def.buttons do
            local b, prev = def.buttons[i].frame, def.buttons[i - 1].frame
            b:ClearAllPoints()
            if e.orientation == "vertical" then b:SetPoint("TOP", prev, "BOTTOM", 0, -e.padding)
            else b:SetPoint("LEFT", prev, "RIGHT", e.padding, 0) end
        end
        -- the stock strip behind the buttons only fits a horizontal row
        for _, a in ipairs(def.art) do a[1]:SetAlpha(e.orientation == "vertical" and 0 or a[2]) end
        holder:SetFrameStrata("LOW"); f:SetFrameStrata("LOW")
        for _, entry in ipairs(def.buttons) do entry.frame:SetFrameStrata("LOW") end
    end,
    watch = function(self, def) return { def.bar, def.buttons[1].frame, def.buttons[2] and def.buttons[2].frame } end,
    restore = function(self, def)
        if not def.locked then return end
        def.locked = nil
        local f = def.bar
        A.RestoreGeometry(f, def.barNative)
        if def.barNative.strata then f:SetFrameStrata(def.barNative.strata) end
        for i, entry in ipairs(def.buttons) do
            if i > 1 then A.RestoreGeometry(entry.frame, entry.native) end
            if entry.native.strata then entry.frame:SetFrameStrata(entry.native.strata) end
        end
        for _, a in ipairs(def.art) do a[1]:SetAlpha(a[2]) end
        remanage("ShapeshiftBarFrame")
    end,
}

-- HUD tooltip: GameTooltip's default anchor (GameTooltip_SetDefaultAnchor)
A.Kinds.tooltip = {
    bind = function(self, def)
        local h = CreateFrame("Frame", "BlizzUIRebornTooltipAnchor", UIParent)
        A.Size(h, def.preview[1], def.preview[2])
        -- 3.3.5 default: BOTTOMRIGHT of UIParent, above the bags area
        h:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -((_G.CONTAINER_OFFSET_X or 0) + 13), _G.CONTAINER_OFFSET_Y or 70)
        def.native = A.Snapshot(h)
        def.nativeRect = unionRect({ h })
        self:Hook("GameTooltip_SetDefaultAnchor", function(tooltip)
            if def.applied and self.active and tooltip then
                local e = self:Settings(def)
                tooltip:ClearAllPoints()
                tooltip:SetPoint(e.point, h, e.point, 0, 0)
            end
        end)
        return h
    end,
    apply = function(self, def, e) self:PlaceClamped(def.frame, e.point, e.x, e.y) end,
    watch = function() return {} end,
    restore = function(self, def) A.RestoreGeometry(def.frame, def.native) end,
}

-- action bar page arrows (not secure: can change any time) ---------
A.Kinds.paging = {
    bind = function(self, def)
        local up, down, num = _G.ActionBarUpButton, _G.ActionBarDownButton, _G.MainMenuBarPageNumber
        if not (up and down) then return end
        def.up = { frame = up, native = A.Snapshot(up), alpha = up:GetAlpha(), mouse = up:IsMouseEnabled() and true or false }
        def.down = { frame = down, native = A.Snapshot(down), alpha = down:GetAlpha(), mouse = down:IsMouseEnabled() and true or false }
        if num then
            local pts = {}
            for i = 1, num:GetNumPoints() do pts[i] = { num:GetPoint(i) } end
            def.num = { frame = num, points = pts, alpha = num:GetAlpha() }
        end
        def.nativeRect = unionRect({ up, down })
        local holder = CreateFrame("Frame", "BlizzUIRebornPaging", up:GetParent())
        local r = def.nativeRect or { 500, 10, 32, 40 }
        A.Size(holder, r[3], r[4])
        holder:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", r[1], r[2])
        def.native = A.Snapshot(holder)
        return holder
    end,
    apply = function(self, def, e)
        local holder = def.frame
        local shown = e.enabled ~= false
        for _, t in ipairs({ def.up, def.down }) do
            t.frame:SetAlpha(shown and t.alpha or 0)
            t.frame:EnableMouse(shown and t.mouse)
        end
        if def.num then def.num.frame:SetAlpha(shown and def.num.alpha or 0) end
        local w, h = def.up.native.width, def.up.native.height + def.down.native.height - 12
        holder:SetScale(e.scale / 100)
        A.Size(holder, w + 12, h)
        self:PlaceClamped(holder, e.point, e.x, e.y)
        for _, t in ipairs({ def.up, def.down }) do t.frame:SetScale(holder:GetEffectiveScale() / t.frame:GetParent():GetEffectiveScale()) end
        def.up.frame:ClearAllPoints(); def.up.frame:SetPoint("TOPLEFT", holder, "TOPLEFT", 0, 0)
        def.down.frame:ClearAllPoints(); def.down.frame:SetPoint("BOTTOMLEFT", holder, "BOTTOMLEFT", 0, 0)
        if def.num then def.num.frame:ClearAllPoints(); def.num.frame:SetPoint("LEFT", def.up.frame, "RIGHT", -6, -10) end
    end,
    watch = function(self, def) return { def.up.frame } end,
    restore = function(self, def)
        for _, t in ipairs({ def.up, def.down }) do
            A.RestoreGeometry(t.frame, t.native)
            t.frame:SetAlpha(t.alpha); t.frame:EnableMouse(t.mouse)
        end
        if def.num then
            local n = def.num.frame
            n:ClearAllPoints()
            for _, p in ipairs(def.num.points) do n:SetPoint(unpack(p)) end
            n:SetAlpha(def.num.alpha)
        end
    end,
}

-- experience + reputation bars (native art, moved and scaled together) ----
A.Kinds.statusbars = {
    bind = function(self, def)
        if not (MainMenuExpBar and ReputationWatchBar) then return end
        def.xp = { frame = MainMenuExpBar, native = A.Snapshot(MainMenuExpBar) }
        def.rep = { frame = ReputationWatchBar, native = A.Snapshot(ReputationWatchBar) }
        def.nativeRect = unionRect({ MainMenuExpBar })
        local holder = CreateFrame("Frame", "BlizzUIRebornStatusBars", UIParent)
        A.Size(holder, def.xp.native.width, def.xp.native.height)
        holder:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", def.nativeRect and def.nativeRect[1] or 0, def.nativeRect and def.nativeRect[2] or 0)
        def.native = A.Snapshot(holder)
        local relayout = function() if def.applied then self:LayoutStatusBars(def) end end
        for _, fn in ipairs({ "ReputationWatchBar_Update", "MainMenuExpBar_Update", "MainMenuBar_UpdateExperienceBars" }) do self:Hook(fn, relayout) end
        return holder
    end,
    apply = function(self, def, e) self:LayoutStatusBars(def, e) end,
    watch = function(self, def) return { MainMenuExpBar, ReputationWatchBar } end,
    restore = function(self, def)
        for _, t in ipairs({ def.xp, def.rep }) do A.RestoreGeometry(t.frame, t.native) end
        if ReputationWatchBar_Update then pcall(ReputationWatchBar_Update) end
    end,
}
function A:LayoutStatusBars(def, e)
    e = e or self:Settings(def)
    local holder, xp, rep = def.frame, MainMenuExpBar, ReputationWatchBar
    local k = e.scale / 100
    xp:SetScale(def.xp.native.scale * k); rep:SetScale(def.rep.native.scale * k)
    local w = def.xp.native.width
    local h = (xp:IsShown() and def.xp.native.height or 0) + (rep:IsShown() and def.rep.native.height or 0)
    holder:SetScale(k)
    A.Size(holder, w, math.max(h, def.xp.native.height))
    self:PlaceClamped(holder, e.point, e.x, e.y)
    xp:ClearAllPoints(); xp:SetPoint("BOTTOM", holder, "BOTTOM", 0, 0)
    rep:ClearAllPoints()
    if xp:IsShown() then rep:SetPoint("BOTTOM", xp, "TOP", 0, 0) else rep:SetPoint("BOTTOM", holder, "BOTTOM", 0, 0) end
    self:RecordAnchors(def)
end
