-- Builds a simulated 3.3.5 default UI (names/anchors follow FrameXML) plus
-- harness helpers. Loaded after wowmock.lua.
local M = MOCK

UIParent = CreateFrame("Frame", "UIParent")
UIParent.__points = {}
UIParent:SetScale(M.uiScale or (1080 / 768))
WorldFrame = CreateFrame("Frame", "WorldFrame")

local function F(ftype, name, parent, w, h, point, rel, rp, x, y, template)
    local f = CreateFrame(ftype, name, parent, template)
    if w then f:SetWidth(w) end
    if h then f:SetHeight(h) end
    if point then f:SetPoint(point, rel or parent, rp or point, x or 0, y or 0) end
    return f
end
local function T(parent, name, layer, w, h, point, rel, rp, x, y)
    local t = parent:CreateTexture(name, layer)
    if w then t:SetWidth(w) end
    if h then t:SetHeight(h) end
    if point then t:SetPoint(point, rel or parent, rp or point, x or 0, y or 0) end
    return t
end
local function S(parent, name, layer, point, rel, rp, x, y)
    local t = parent:CreateFontString(name, layer, "GameFontNormalSmall")
    if point then t:SetPoint(point, rel or parent, rp or point, x or 0, y or 0) end
    return t
end

-- Chat
DEFAULT_CHAT_FRAME = F("Frame", "ChatFrame1", UIParent, 430, 120, "BOTTOMLEFT", UIParent, "BOTTOMLEFT", 32, 95)
function DEFAULT_CHAT_FRAME:AddMessage(m) M.messages[#M.messages + 1] = m end
DEFAULT_CHAT_FRAME:SetMovable(true)
function FCF_RestorePositionAndDimensions(f) f:ClearAllPoints(); f:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", 32, 95) end

-- Main menu bar
MainMenuBar = F("Frame", "MainMenuBar", UIParent, 1024, 53, "BOTTOM", UIParent, "BOTTOM", 0, 0)
MainMenuBarArtFrame = F("Frame", "MainMenuBarArtFrame", MainMenuBar, 1024, 53, "BOTTOM", MainMenuBar, "BOTTOM", 0, 0)
for i = 0, 3 do T(MainMenuBarArtFrame, "MainMenuBarTexture" .. i, "BACKGROUND", 256, 43, "BOTTOMLEFT", MainMenuBarArtFrame, "BOTTOMLEFT", i * 256, 0) end
T(MainMenuBarArtFrame, "MainMenuBarLeftEndCap", "OVERLAY", 128, 128, "BOTTOM", MainMenuBar, "BOTTOM", -544, 0)
T(MainMenuBarArtFrame, "MainMenuBarRightEndCap", "OVERLAY", 128, 128, "BOTTOM", MainMenuBar, "BOTTOM", 544, 0)
MainMenuBarPageNumber = S(MainMenuBarArtFrame, "MainMenuBarPageNumber", "OVERLAY", "CENTER", MainMenuBarArtFrame, "BOTTOMLEFT", 522, 25)
F("Button", "ActionBarUpButton", MainMenuBarArtFrame, 32, 32, "CENTER", MainMenuBarArtFrame, "TOPLEFT", 522, -22)
F("Button", "ActionBarDownButton", MainMenuBarArtFrame, 32, 32, "CENTER", MainMenuBarArtFrame, "TOPLEFT", 522, -42)
T(MainMenuBar, "MainMenuBarMaxLevelBar", "BACKGROUND", 1024, 7, "TOP", MainMenuBar, "TOP", 0, -11)
F("Frame", "MainMenuBarMicroExtension", MainMenuBarArtFrame, 10, 10, "BOTTOMLEFT")

MainMenuExpBar = F("StatusBar", "MainMenuExpBar", MainMenuBar, 1024, 13, "TOP", MainMenuBar, "TOP", 0, 0)
for i = 0, 3 do T(MainMenuExpBar, "MainMenuXPBarTexture" .. i, "OVERLAY", 256, 10, "BOTTOMLEFT", MainMenuExpBar, "BOTTOMLEFT", i * 256, 0) end
for i = 1, 19 do T(MainMenuExpBar, "MainMenuXPBarDiv" .. i, "OVERLAY", 9, 9, "LEFT", MainMenuExpBar, "LEFT", i * 51, 1) end
F("Frame", "ExhaustionTick", MainMenuExpBar, 32, 32, "CENTER", MainMenuExpBar, "LEFT", 100, 0)
T(MainMenuExpBar, "ExhaustionLevelFillBar", "BORDER", 10, 10, "TOPLEFT", MainMenuExpBar, "TOPLEFT", 0, 0)
MainMenuBarExpText = S(MainMenuExpBar, "MainMenuBarExpText", "OVERLAY", "CENTER")
MainMenuExpBar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")

ReputationWatchBar = F("Frame", "ReputationWatchBar", MainMenuBar, 1024, 7, "BOTTOM", MainMenuBar, "TOP", 0, -3)
ReputationWatchStatusBar = F("StatusBar", "ReputationWatchStatusBar", ReputationWatchBar, 1024, 7, "TOPLEFT", ReputationWatchBar, "TOPLEFT", 0, 0)
ReputationWatchStatusBar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
for i = 0, 3 do T(ReputationWatchStatusBar, "ReputationWatchBarTexture" .. i, "ARTWORK", 256, 10, "TOPLEFT", ReputationWatchStatusBar, "TOPLEFT", i * 256, 0) end
for i = 0, 3 do T(ReputationWatchStatusBar, "ReputationXPBarTexture" .. i, "ARTWORK", 256, 10, "TOPLEFT", ReputationWatchStatusBar, "TOPLEFT", i * 256, 0) end
ReputationWatchStatusBarText = S(ReputationWatchStatusBar, "ReputationWatchStatusBarText", "OVERLAY", "CENTER")
M.repWatched = true
function ReputationWatchBar_Update()
    if M.repWatched then ReputationWatchBar:Show() else ReputationWatchBar:Hide() end
    ReputationWatchBar:ClearAllPoints()
    if MainMenuExpBar:IsShown() then ReputationWatchBar:SetPoint("BOTTOM", MainMenuBar, "TOP", 0, -3)
    else ReputationWatchBar:SetPoint("TOP", MainMenuBar, "TOP", 0, 0) end
    ReputationWatchStatusBar:SetWidth(1024)
end
function MainMenuExpBar_Update() MainMenuExpBar:SetValue(10) end

local function actionButtons(prefix, parent, first, count, xoff, yoff, vertical, template, size)
    for i = 1, count or 12 do
        local b = CreateFrame("CheckButton", prefix .. i, parent, template or "ActionBarButtonTemplate")
        b:SetID(i)
        if size then b:SetWidth(size); b:SetHeight(size) end
        if i == 1 then b:SetPoint(first[1], parent, first[2], first[3], first[4])
        elseif vertical then b:SetPoint("TOP", prefix .. (i - 1), "BOTTOM", 0, -6)
        else b:SetPoint("LEFT", prefix .. (i - 1), "RIGHT", xoff or 6, 0) end
    end
end
actionButtons("ActionButton", MainMenuBarArtFrame, { "BOTTOMLEFT", "BOTTOMLEFT", 8, 4 })
for i = 1, 12 do _G["ActionButton" .. i].action = i end
BonusActionBarFrame = F("Frame", "BonusActionBarFrame", MainMenuBar, 1024, 43, "TOPLEFT", MainMenuBarArtFrame, "BOTTOMLEFT", 0, 43)
BonusActionBarFrame:Hide()
T(BonusActionBarFrame, "BonusActionBarTexture0", "BACKGROUND", 256, 43, "BOTTOMLEFT")
T(BonusActionBarFrame, "BonusActionBarTexture1", "BACKGROUND", 256, 43, "BOTTOMLEFT", BonusActionBarFrame, "BOTTOMLEFT", 256, 0)
actionButtons("BonusActionButton", BonusActionBarFrame, { "BOTTOMLEFT", "BOTTOMLEFT", 4, 4 })
function ShowBonusActionBar() BonusActionBarFrame:Show() end
function HideBonusActionBar() BonusActionBarFrame:Hide() end

MultiBarBottomLeft = F("Frame", "MultiBarBottomLeft", MainMenuBar, 500, 38, "BOTTOMLEFT", ActionButton1, "TOPLEFT", 0, 6)
MultiBarBottomRight = F("Frame", "MultiBarBottomRight", MainMenuBar, 500, 38, "LEFT", MultiBarBottomLeft, "RIGHT", -6, 0)
MultiBarRight = F("Frame", "MultiBarRight", UIParent, 38, 500, "BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -6, 98)
MultiBarLeft = F("Frame", "MultiBarLeft", UIParent, 38, 500, "TOPRIGHT", MultiBarRight, "TOPLEFT", -5, 0)
for _, f in ipairs({ MultiBarBottomLeft, MultiBarBottomRight, MultiBarRight, MultiBarLeft }) do f.__protected = true; f:Hide() end
actionButtons("MultiBarBottomLeftButton", MultiBarBottomLeft, { "BOTTOMLEFT", "BOTTOMLEFT", 0, 0 })
actionButtons("MultiBarBottomRightButton", MultiBarBottomRight, { "BOTTOMLEFT", "BOTTOMLEFT", 0, 0 })
actionButtons("MultiBarRightButton", MultiBarRight, { "TOPRIGHT", "TOPRIGHT", 0, 0 }, 12, nil, nil, true)
actionButtons("MultiBarLeftButton", MultiBarLeft, { "TOPRIGHT", "TOPRIGHT", 0, 0 }, 12, nil, nil, true)
function MultiActionBar_Update()
    local vis = { SHOW_MULTI_ACTIONBAR_1, SHOW_MULTI_ACTIONBAR_2, SHOW_MULTI_ACTIONBAR_3, SHOW_MULTI_ACTIONBAR_4 }
    vis[4] = vis[3] and vis[4] -- MultiBarLeft requires MultiBarRight (FrameXML)
    for i, f in ipairs({ MultiBarBottomLeft, MultiBarBottomRight, MultiBarRight, MultiBarLeft }) do
        if vis[i] then f:Show() else f:Hide() end
    end
    if VehicleSeatIndicator then VehicleSeatIndicator:SetPoint("TOPRIGHT", MinimapCluster, "BOTTOMRIGHT", 0, -13) end
end
-- FrameXML action ids: bottom left 61-72, bottom right 49-60, right 25-36, left 37-48
for prefix, base in pairs({ MultiBarBottomLeftButton = 60, MultiBarBottomRightButton = 48, MultiBarRightButton = 24, MultiBarLeftButton = 36, BonusActionButton = 72 }) do
    for i = 1, 12 do _G[prefix .. i].action = base + i end
end
-- by default every slot holds something (tests empty slots on purpose)
M.actions = M.actions or {}
for i = 1, 120 do M.actions[i] = true end
function ActionButton_Update(self)
    local action = self.action or self:GetID()
    if HasAction(action) then self:SetNormalTexture("Interface\\Buttons\\UI-Quickslot2")
    else self:SetNormalTexture("Interface\\Buttons\\UI-Quickslot") end
end
function ActionButton_UpdateHotkeys(self) end
function ActionButton_ShowGrid(b) b:SetAttribute("showgrid", (b:GetAttribute("showgrid") or 0) + 1) end
function ActionButton_HideGrid(b) b:SetAttribute("showgrid", math.max(0, (b:GetAttribute("showgrid") or 0) - 1)) end
for _, b in ipairs({ "ActionButton", "BonusActionButton", "MultiBarBottomLeftButton", "MultiBarBottomRightButton", "MultiBarRightButton", "MultiBarLeftButton" }) do
    for i = 1, 12 do _G[b .. i]:SetAttribute("showgrid", 0) end
end

ShapeshiftBarFrame = F("Frame", "ShapeshiftBarFrame", MainMenuBar, 29, 32, "BOTTOMLEFT", MainMenuBar, "TOPLEFT", 30, 0)
actionButtons("ShapeshiftButton", ShapeshiftBarFrame, { "BOTTOMLEFT", "BOTTOMLEFT", 11, 3 }, 10, 7, nil, false, "ActionBarButtonTemplate", 30)
T(ShapeshiftBarFrame, "ShapeshiftBarLeft", "BACKGROUND", 16, 64, "BOTTOMLEFT")
T(ShapeshiftBarFrame, "ShapeshiftBarMiddle", "BACKGROUND", 16, 64, "LEFT", ShapeshiftBarLeft, "RIGHT", 0, 0)
T(ShapeshiftBarFrame, "ShapeshiftBarRight", "BACKGROUND", 16, 64, "LEFT", ShapeshiftBarMiddle, "RIGHT", 0, 0)
-- forms: { icon, name, active, castable } (warrior stances by default)
M.forms = M.forms or {
    { "Interface\\Icons\\Ability_Warrior_OffensiveStance", "Battle Stance", true, true },
    { "Interface\\Icons\\Ability_Warrior_DefensiveStance", "Defensive Stance", false, true },
    { "Interface\\Icons\\Ability_Racial_Avatar", "Berserker Stance", false, true },
}
-- FrameXML (3.3.5) ShapeshiftBar_Update: re-anchors button 1 with SetPoint
-- (no ClearAllPoints), shows/hides the bar and calls the frame manager.
function ShapeshiftBar_Update()
    local n = GetNumShapeshiftForms()
    if n > 0 then
        if n <= 2 then ShapeshiftButton1:SetPoint("BOTTOMLEFT", "ShapeshiftBarFrame", "BOTTOMLEFT", 12, 3)
        else ShapeshiftButton1:SetPoint("BOTTOMLEFT", "ShapeshiftBarFrame", "BOTTOMLEFT", 10, 3) end
        ShapeshiftBarFrame:Show()
    else
        ShapeshiftBarFrame:Hide()
    end
    for i = 1, 10 do
        local b = _G["ShapeshiftButton" .. i]
        if i <= n then b:Show(); _G["ShapeshiftButton" .. i .. "Icon"]:SetTexture(M.forms[i][1]); b:SetChecked(M.forms[i][3]) else b:Hide() end
    end
    UIParent_ManageFramePositions()
end
ShapeshiftBarFrame:RegisterEvent("UPDATE_SHAPESHIFT_FORMS")
ShapeshiftBarFrame:SetScript("OnEvent", function() ShapeshiftBar_Update() end)
PetActionBarFrame = F("Frame", "PetActionBarFrame", UIParent, 509, 43, "TOPLEFT", MainMenuBar, "BOTTOMLEFT", 36, 88)
actionButtons("PetActionButton", PetActionBarFrame, { "BOTTOMLEFT", "BOTTOMLEFT", 36, 2 }, 10, 8, nil, false, "ActionBarButtonTemplate", 30)
PossessBarFrame = F("Frame", "PossessBarFrame", UIParent, 60, 32, "BOTTOMLEFT", MainMenuBar, "TOPLEFT", 30, 0)
actionButtons("PossessButton", PossessBarFrame, { "BOTTOMLEFT", "BOTTOMLEFT", 10, 3 }, 2, 8, nil, false, "ActionBarButtonTemplate", 30)
MultiCastActionBarFrame = F("Frame", "MultiCastActionBarFrame", UIParent, 230, 38, "BOTTOMLEFT", MainMenuBar, "TOPLEFT", 30, 0)
for _, n in ipairs({ "ShapeshiftBarFrame", "PetActionBarFrame", "PossessBarFrame", "MultiCastActionBarFrame" }) do
    _G[n].__protected = true
end
PossessBarFrame:Hide(); MultiCastActionBarFrame:Hide()
-- Totem bar (shaman): summon button + 3 pages (Elements / Ancestors / Spirits) of 4
-- secure buttons, a page flyout, and a slide animation run from OnUpdate
-- that re-anchors the bar every frame while it slides in.
MultiCastSummonSpellButton = F("CheckButton", "MultiCastSummonSpellButton", MultiCastActionBarFrame, 30, 30, "BOTTOMLEFT", MultiCastActionBarFrame, "BOTTOMLEFT", 3, 3)
MultiCastSummonSpellButton.__protected = true
for p = 1, 3 do
    local page = F("Frame", "MultiCastActionPage" .. p, MultiCastActionBarFrame, 150, 30, "BOTTOMLEFT", MultiCastActionBarFrame, "BOTTOMLEFT", 36, 3)
    page.__protected = true
    for i = 1, 4 do
        local n = (p - 1) * 4 + i
        local b = F("CheckButton", "MultiCastActionButton" .. n, page, 30, 30, "BOTTOMLEFT", page, "BOTTOMLEFT", (i - 1) * 36, 0)
        b.__protected = true
    end
    if p > 1 then page:Hide() end
end
MultiCastFlyoutFrame = F("Frame", "MultiCastFlyoutFrame", UIParent, 30, 100); MultiCastFlyoutFrame:Hide()
MultiCastActionBarFrame.currentPage = 1
MOCK.totemSpells = { "Call of the Elements", "Call of the Ancestors", "Call of the Spirits" }
function MultiCastActionBarFrame_Update(self)
    self = self or MultiCastActionBarFrame
    for p = 1, 3 do
        local page = _G["MultiCastActionPage" .. p]
        if p == self.currentPage then page:Show() else page:Hide() end
    end
    MultiCastSummonSpellButton:SetAttribute("spell", MOCK.totemSpells[self.currentPage])
    ShowMultiCastActionBar()
end
function ShowMultiCastActionBar()
    MultiCastActionBarFrame:Show()
    MultiCastActionBarFrame.slideTimer = 0; MultiCastActionBarFrame.timeToSlide = 0.25
end
function MultiCastActionBarFrame_OnUpdate(self, elapsed)
    if self.slideTimer and self.slideTimer < self.timeToSlide then
        self.slideTimer = self.slideTimer + elapsed
        local y = -40 * (1 - math.min(1, self.slideTimer / self.timeToSlide))
        self:ClearAllPoints(); self:SetPoint("BOTTOMLEFT", MainMenuBar, "TOPLEFT", 30, y)
        MOCK.totemSlideFrames = (MOCK.totemSlideFrames or 0) + 1
        if self.slideTimer >= self.timeToSlide and self.mode == "hide" then self:Hide() end
    end
end
MultiCastActionBarFrame:SetScript("OnUpdate", function(self, e) MultiCastActionBarFrame_OnUpdate(self, e) end)
MultiCastActionBarFrame:SetScript("OnShow", function() UIParent_ManageFramePositions() end)
MultiCastActionBarFrame:SetScript("OnHide", function() UIParent_ManageFramePositions() end)
-- choosing a "Call of the ..." spell from the flyout switches the page
function MultiCastFlyoutButton_OnClick(page)
    MultiCastActionBarFrame.currentPage = page
    MultiCastActionBarFrame_Update(MultiCastActionBarFrame)
end
PETACTIONBAR_XPOS = 36
function PetActionBar_OnUpdate(self) -- slide animation re-anchors every frame while sliding
    if self.slideTimer then
        self:ClearAllPoints(); self:SetPoint("TOPLEFT", MainMenuBar, "BOTTOMLEFT", PETACTIONBAR_XPOS, 88)
        self.slideTimer = nil
    end
end

-- Default UIParent frame manager: repositions frames that are listed in
-- UIPARENT_MANAGED_FRAME_POSITIONS and not user-placed.
local managedDefaults = {
    ShapeshiftBarFrame = { "BOTTOMLEFT", MainMenuBar, "TOPLEFT", 30, 0 },
    PossessBarFrame = { "BOTTOMLEFT", MainMenuBar, "TOPLEFT", 30, 0 },
    MultiCastActionBarFrame = { "BOTTOMLEFT", MainMenuBar, "TOPLEFT", 30, 0 },
    CastingBarFrame = { "BOTTOM", UIParent, "BOTTOM", 0, 110 },
    PetActionBarFrame = { "TOPLEFT", MainMenuBar, "BOTTOMLEFT", 36, 88 },
    MultiBarRight = { "BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -6, 98 },
    ChatFrame1 = { "BOTTOMLEFT", UIParent, "BOTTOMLEFT", 32, 95 },
}
for k in pairs(managedDefaults) do UIPARENT_MANAGED_FRAME_POSITIONS[k] = { baseY = true } end
function UIParent_ManageFramePositions()
    M.manageCalls = (M.manageCalls or 0) + 1
    for name, def in pairs(managedDefaults) do
        local f = _G[name]
        if f and UIPARENT_MANAGED_FRAME_POSITIONS[name] and not f:IsUserPlaced() and not f.ignoreFramePositionManager then
            if not (M.combat and f:IsProtected()) then
                f:ClearAllPoints(); f:SetPoint(def[1], def[2], def[3], def[4], def[5])
            end
        end
    end
    if DurabilityFrame then DurabilityFrame:SetPoint("TOPRIGHT", MinimapCluster, "BOTTOMRIGHT", -40, 15) end
    if Boss1TargetFrame then Boss1TargetFrame:SetPoint("TOPRIGHT", MinimapCluster, "BOTTOMRIGHT", -40, 0) end
    if WatchFrame and not WatchFrame:IsUserPlaced() then
        WatchFrame:ClearAllPoints(); WatchFrame:SetPoint("TOPRIGHT", MinimapCluster, "BOTTOMRIGHT", -15, 0)
        WatchFrame:SetHeight(500)
    end
end

-- Micro menu
local micro = { "CharacterMicroButton", "SpellbookMicroButton", "TalentMicroButton", "AchievementMicroButton", "QuestLogMicroButton",
    "SocialsMicroButton", "PVPMicroButton", "LFDMicroButton", "CollectionsMicroButton", "StoreMicroButton", "MainMenuMicroButton", "HelpMicroButton" }
for i, n in ipairs(micro) do
    local b = F("Button", n, MainMenuBarArtFrame, 28, 58)
    if i == 1 then b:SetPoint("BOTTOMLEFT", MainMenuBarArtFrame, "BOTTOMLEFT", 552, 2)
    else b:SetPoint("BOTTOMLEFT", micro[i - 1], "BOTTOMRIGHT", -3, 0) end
end
VehicleMenuBar = F("Frame", "VehicleMenuBar", UIParent, 800, 60, "BOTTOM")
VehicleMenuBar:Hide()
function MoveMicroButtons(anchor, anchorTo, relAnchor, x, y, isStacked)
    CharacterMicroButton:ClearAllPoints(); CharacterMicroButton:SetPoint(anchor, anchorTo, relAnchor, x, y)
    for _, n in ipairs(micro) do _G[n]:SetParent(anchorTo == VehicleMenuBar and VehicleMenuBar or MainMenuBarArtFrame) end
end
function UpdateMicroButtons() end

-- Bags
local bags = { "MainMenuBarBackpackButton", "CharacterBag0Slot", "CharacterBag1Slot", "CharacterBag2Slot", "CharacterBag3Slot" }
for i, n in ipairs(bags) do
    local b = F("CheckButton", n, MainMenuBarArtFrame, i == 1 and 37 or 30, i == 1 and 37 or 30)
    T(b, n .. "IconTexture", "BORDER", 30, 30, "TOPLEFT")
    b:SetNormalTexture("Interface\\Buttons\\UI-Quickslot2")
    if i == 1 then b:SetPoint("BOTTOMRIGHT", MainMenuBarArtFrame, "BOTTOMRIGHT", -6, 2)
    else b:SetPoint("RIGHT", bags[i - 1], "LEFT", -5, 0) end
end
KeyRingButton = F("CheckButton", "KeyRingButton", MainMenuBarArtFrame, 18, 39, "RIGHT", "CharacterBag3Slot", "LEFT", -5, 0)
function MainMenuBar_UpdateKeyRing() end

-- Unit frames
local function unitFrame(name, point, x, y, target)
    local f = F("Button", name, UIParent, 232, 100, "TOPLEFT", UIParent, "TOPLEFT", x, y)
    f.__protected = true
    f:SetMovable(false)
    return f
end
PlayerFrame = unitFrame("PlayerFrame", "TOPLEFT", -19, -4)
-- 3.3.5 PlayerFrame.xml: the border art, name and level text are drawn by a
-- frame nested two levels inside PlayerFrame, above its own children
local playerArtHolder = F("Frame", nil, PlayerFrame, 232, 100, "TOPLEFT")
local playerArt = F("Frame", nil, playerArtHolder, 232, 100, "TOPLEFT")
M.playerArt = playerArt
T(playerArt, "PlayerFrameTexture", "BORDER", 232, 100, "TOPLEFT", PlayerFrame, "TOPLEFT")
T(playerArt, "PlayerFrameVehicleTexture", "BORDER", 240, 120, "CENTER", PlayerFrame, "CENTER")
T(PlayerFrame, "PlayerFrameBackground", "BACKGROUND", 119, 41, "TOPLEFT", PlayerFrame, "TOPLEFT", 106, -22)
T(PlayerFrame, "PlayerPortrait", "BACKGROUND", 64, 64, "TOPLEFT", PlayerFrame, "TOPLEFT", 42, -12)
T(PlayerFrame, "PlayerStatusTexture", "BORDER", 190, 66, "TOPLEFT", PlayerFrame, "TOPLEFT", 35, -9)
T(PlayerFrame, "PlayerStatusGlow", "OVERLAY", 32, 32, "TOPLEFT", PlayerFrame, "TOPLEFT", 35, -9)
T(PlayerFrame, "PlayerRestGlow", "OVERLAY", 32, 32, "TOPLEFT")
T(PlayerFrame, "PlayerAttackGlow", "OVERLAY", 32, 32, "TOPLEFT")
T(PlayerFrame, "PlayerAttackBackground", "OVERLAY", 32, 32, "TOPLEFT")
T(PlayerFrame, "PlayerRestIcon", "OVERLAY", 31, 34, "TOPLEFT", PlayerFrame, "TOPLEFT", 39, -50)
T(PlayerFrame, "PlayerAttackIcon", "OVERLAY", 32, 31, "TOPLEFT", PlayerFrame, "TOPLEFT", 36, -52)
T(PlayerFrame, "PlayerPVPIcon", "OVERLAY", 64, 64, "TOPLEFT", PlayerFrame, "TOPLEFT", 18, -20)
T(PlayerFrame, "PlayerLeaderIcon", "OVERLAY", 16, 16, "TOPLEFT", PlayerFrame, "TOPLEFT", 40, -12)
T(PlayerFrame, "PlayerMasterIcon", "OVERLAY", 16, 16, "TOPLEFT", PlayerFrame, "TOPLEFT", 80, -10)
T(PlayerFrame, "PlayerFrameFlash", "OVERLAY", 242, 93, "TOPLEFT", PlayerFrame, "TOPLEFT", -4, -2)
F("Frame", "PlayerFrameGroupIndicator", PlayerFrame, 20, 16, "BOTTOMLEFT", PlayerFrame, "TOPLEFT", 97, -20)
F("Frame", "PlayerHitIndicator", PlayerFrame, 20, 16, "CENTER", PlayerFrame, "TOPLEFT", 73, -42)
S(playerArt, "PlayerName", "OVERLAY", "CENTER", PlayerFrame, "CENTER", 50, 19)
S(playerArt, "PlayerLevelText", "OVERLAY", "CENTER", PlayerFrame, "CENTER", -63, -16)
S(PlayerFrame, "PlayerPVPTimerText", "OVERLAY", "CENTER", PlayerFrame, "CENTER", 0, 0)
F("StatusBar", "PlayerFrameHealthBar", PlayerFrame, 119, 12, "TOPLEFT", PlayerFrame, "TOPLEFT", 106, -41)
F("StatusBar", "PlayerFrameManaBar", PlayerFrame, 119, 12, "TOPLEFT", PlayerFrame, "TOPLEFT", 106, -52)
S(PlayerFrame, "PlayerFrameHealthBarText", "OVERLAY", "CENTER", PlayerFrame, "TOPLEFT", 166, -46)
S(PlayerFrame, "PlayerFrameManaBarText", "OVERLAY", "CENTER", PlayerFrame, "TOPLEFT", 166, -57)
PlayerFrameHealthBar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
PlayerFrameManaBar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
function PlayerFrame_ToPlayerArt(self)
    PlayerFrameTexture:Show(); PlayerFrameVehicleTexture:Hide()
    PlayerName:ClearAllPoints(); PlayerName:SetPoint("CENTER", PlayerFrame, "CENTER", 50, 19)
    PlayerFrameHealthBar:SetWidth(119); PlayerFrameHealthBar:ClearAllPoints(); PlayerFrameHealthBar:SetPoint("TOPLEFT", PlayerFrame, "TOPLEFT", 106, -41)
    PlayerFrameManaBar:SetWidth(119); PlayerFrameManaBar:ClearAllPoints(); PlayerFrameManaBar:SetPoint("TOPLEFT", PlayerFrame, "TOPLEFT", 106, -52)
    PlayerFrameBackground:SetWidth(119)
    PlayerLevelText:Show()
end
function PlayerFrame_ToVehicleArt(self)
    PlayerFrameTexture:Hide(); PlayerFrameVehicleTexture:Show()
    PlayerFrameHealthBar:SetWidth(100)
end
function PlayerFrame_UpdateStatus() PlayerStatusTexture:Show() end

local function targetLike(name, x, y)
    local f = unitFrame(name, "TOPLEFT", x, y)
    local tf = F("Frame", name .. "TextureFrame", f, 232, 100, "TOPLEFT")
    T(tf, name .. "TextureFrameTexture", "BORDER", 232, 100, "TOPLEFT")
    T(f, name .. "Background", "BACKGROUND", 119, 25, "BOTTOMLEFT", f, "BOTTOMLEFT", 7, 35)
    T(f, name .. "NameBackground", "BACKGROUND", 119, 19, "BOTTOMLEFT", f, "BOTTOMLEFT", 7, 60)
    T(f, name .. "Portrait", "BORDER", 64, 64, "TOPRIGHT", f, "TOPRIGHT", -42, -12)
    T(f, name .. "Flash", "BACKGROUND", 242, 93, "TOPLEFT")
    S(tf, name .. "TextureFrameName", "ARTWORK", "CENTER", tf, "CENTER", -50, 19)
    S(tf, name .. "TextureFrameLevelText", "ARTWORK", "CENTER", tf, "CENTER", 63, -16)
    S(tf, name .. "TextureFrameDeadText", "ARTWORK", "CENTER", tf, "CENTER", -50, 3)
    T(tf, name .. "TextureFrameHighLevelTexture", "ARTWORK", 16, 16, "CENTER", tf, "CENTER", 63, -16)
    T(tf, name .. "TextureFramePVPIcon", "ARTWORK", 64, 64, "TOPRIGHT", tf, "TOPRIGHT", 3, -20)
    T(tf, name .. "TextureFrameLeaderIcon", "ARTWORK", 16, 16, "TOPRIGHT", tf, "TOPRIGHT", -44, -10)
    T(tf, name .. "TextureFrameRaidTargetIcon", "ARTWORK", 26, 26, "CENTER", f, "TOPRIGHT", -73, -14)
    S(tf, name .. "TextureFrameHealthBarText", "OVERLAY", "CENTER", tf, "CENTER", -50, 3)
    S(tf, name .. "TextureFrameManaBarText", "OVERLAY", "CENTER", tf, "CENTER", -50, -8)
    F("StatusBar", name .. "HealthBar", f, 119, 12, "TOPLEFT", f, "TOPLEFT", 6, -41)
    F("StatusBar", name .. "ManaBar", f, 119, 12, "TOPLEFT", f, "TOPLEFT", 6, -52)
    _G[name .. "HealthBar"]:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    _G[name .. "ManaBar"]:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    f.borderTexture = _G[name .. "TextureFrameTexture"]
    f.nameBackground = _G[name .. "NameBackground"]
    f.portrait = _G[name .. "Portrait"]
    f:Hide()
    return f
end
TargetFrame = targetLike("TargetFrame", 250, -4)
FocusFrame = targetLike("FocusFrame", 250, -240)
function TargetFrame_CheckClassification(self, force)
    self.borderTexture:SetTexture("Interface\\TargetingFrame\\UI-TargetingFrame")
end
function TargetFrame_Update(self) if UnitExists("target") then self:Show() else self:Hide() end end
function FocusFrame_SetSmallSize(small) FocusFrame:SetScale(small and 0.75 or 1) end
TargetFrameToT = F("Button", "TargetFrameToT", TargetFrame, 93, 45, "BOTTOMRIGHT", TargetFrame, "BOTTOMRIGHT", -35, -10); TargetFrameToT.__protected = true
FocusFrameToT = F("Button", "FocusFrameToT", FocusFrame, 93, 45, "BOTTOMRIGHT", FocusFrame, "BOTTOMRIGHT", -35, -10); FocusFrameToT.__protected = true
TargetFrameSpellBar = F("StatusBar", "TargetFrameSpellBar", TargetFrame, 150, 10, "TOPLEFT", TargetFrame, "BOTTOMLEFT", 25, 5)
PetFrame = F("Button", "PetFrame", PlayerFrame, 128, 53, "TOPLEFT", PlayerFrame, "TOPLEFT", 80, -60); PetFrame.__protected = true
PetFrame:Hide()
TotemFrame = F("Frame", "TotemFrame", PlayerFrame, 128, 53, "TOPLEFT", PlayerFrame, "TOPLEFT", 99, -78)
for i = 1, 4 do F("Button", "TotemFrameTotem" .. i, TotemFrame, 37, 37, "TOPLEFT", TotemFrame, "TOPLEFT", (i - 1) * 37, 0) end
TotemFrame:Hide()
M.playerClass = M.playerClass or "SHAMAN"
function TotemFrame_Update()
    if M.playerClass == "DEATHKNIGHT" then TotemFrame:SetPoint("TOPLEFT", PlayerFrame, "TOPLEFT", 65, -55) end
    if M.totems and M.totems > 0 then TotemFrame:Show() else TotemFrame:Hide() end
end
for i = 1, 4 do
    local p = F("Button", "PartyMemberFrame" .. i, UIParent, 128, 53)
    p.__protected = true
    if i == 1 then p:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 10, -160) else p:SetPoint("TOPLEFT", "PartyMemberFrame" .. (i - 1), "BOTTOMLEFT", 0, -10) end
    p:Hide()
    local b = F("Button", "Boss" .. i .. "TargetFrame", UIParent, 232, 100)
    b.__protected = true
    if i == 1 then b:SetPoint("TOPLEFT", UIParent, "TOPRIGHT", -275, -250) else b:SetPoint("TOPLEFT", "Boss" .. (i - 1) .. "TargetFrame", "BOTTOMLEFT", 0, 20) end
    b:Hide()
end

-- Cast bar
CastingBarFrame = F("StatusBar", "CastingBarFrame", UIParent, 195, 13, "BOTTOM", UIParent, "BOTTOM", 0, 110)
T(CastingBarFrame, "CastingBarFrameBorder", "ARTWORK", 256, 64, "TOP", CastingBarFrame, "TOP", 0, 28)
T(CastingBarFrame, "CastingBarFrameFlash", "OVERLAY", 256, 64, "TOP", CastingBarFrame, "TOP", 0, 28)
T(CastingBarFrame, "CastingBarFrameSpark", "OVERLAY", 32, 32, "CENTER")
T(CastingBarFrame, "CastingBarFrameIcon", "ARTWORK", 16, 16, "RIGHT", CastingBarFrame, "LEFT", -5, 0)
S(CastingBarFrame, "CastingBarFrameText", "ARTWORK", "TOP", CastingBarFrame, "TOP", 0, 5)
CastingBarFrame:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
CastingBarFrame:Hide()
CastingBarFrame.maxValue, CastingBarFrame.value = 2, 0

-- Buffs (anchoring as in BuffFrame.lua: everything hangs off ConsolidatedBuffs)
ConsolidatedBuffs = F("Button", "ConsolidatedBuffs", UIParent, 30, 30, "TOPRIGHT", UIParent, "TOPRIGHT", -180, -13)
BuffFrame = F("Frame", "BuffFrame", UIParent, 50, 50, "TOPRIGHT", UIParent, "TOPRIGHT", -205, -13)
TemporaryEnchantFrame = F("Frame", "TemporaryEnchantFrame", UIParent, 60, 30, "TOPRIGHT", ConsolidatedBuffs, "TOPRIGHT", 0, 0)
for i = 1, 3 do
    local b = F("Button", "BuffButton" .. i, BuffFrame, 30, 30)
    if i == 1 then b:SetPoint("TOPRIGHT", TemporaryEnchantFrame, "TOPLEFT", -5, 0) else b:SetPoint("RIGHT", "BuffButton" .. (i - 1), "LEFT", -5, 0) end
end
function BuffFrame_UpdateAllBuffAnchors()
    TemporaryEnchantFrame:SetPoint("TOPRIGHT", ConsolidatedBuffs, "TOPRIGHT", 0, 0)
    BuffFrame:SetPoint("TOPRIGHT", ConsolidatedBuffs, "TOPRIGHT", 0, 0)
    BuffButton1:ClearAllPoints(); BuffButton1:SetPoint("TOPRIGHT", TemporaryEnchantFrame, "TOPLEFT", -5, 0)
end
-- misc HUD frames
DurabilityFrame = F("Frame", "DurabilityFrame", UIParent, 60, 75); DurabilityFrame:Hide() -- anchored below, once MinimapCluster exists
VehicleSeatIndicator = F("Frame", "VehicleSeatIndicator", UIParent, 128, 128, "TOPRIGHT", UIParent, "TOPRIGHT", 0, -200); VehicleSeatIndicator:Hide()
for i = 1, 3 do
    local t = F("Frame", "MirrorTimer" .. i, UIParent, 206, 26)
    if i == 1 then t:SetPoint("TOP", UIParent, "TOP", 0, -96) else t:SetPoint("TOP", "MirrorTimer" .. (i - 1), "BOTTOM", 0, 0) end
    t:Hide()
end
RaidWarningFrame = F("Frame", "RaidWarningFrame", UIParent, 512, 70, "TOP", UIParent, "TOP", 0, -260)
CONTAINER_OFFSET_X, CONTAINER_OFFSET_Y = 0, 70
function GameTooltip_SetDefaultAnchor(tooltip, parent)
    tooltip:SetOwner(parent, "ANCHOR_NONE")
    tooltip:SetPoint("BOTTOMRIGHT", "UIParent", "BOTTOMRIGHT", -CONTAINER_OFFSET_X - 13, CONTAINER_OFFSET_Y)
end
MOCK.currencies = {}
function GetBackpackCurrencyInfo(i) local c = MOCK.currencies[i]; if c then return c[1], c[2], c[3], c[4] end end
function UnitFactionGroup() return "Alliance" end
function HideMultiCastActionBar() MultiCastActionBarFrame.mode = "hide"; MultiCastActionBarFrame.slideTimer = 0; MultiCastActionBarFrame.timeToSlide = .25 end

-- Minimap
MinimapCluster = F("Frame", "MinimapCluster", UIParent, 192, 192, "TOPRIGHT", UIParent, "TOPRIGHT", 0, 0)
Minimap = CreateFrame("Minimap", "Minimap", MinimapCluster)
Minimap:SetWidth(140); Minimap:SetHeight(140); Minimap:SetPoint("CENTER", MinimapCluster, "TOP", 9, -92)
MinimapBackdrop = F("Frame", "MinimapBackdrop", MinimapCluster, 192, 192, "CENTER", Minimap, "CENTER", -10, -18)
T(MinimapBackdrop, "MinimapBorder", "ARTWORK", 192, 192, "TOPLEFT")
T(MinimapCluster, "MinimapBorderTop", "ARTWORK", 175, 32, "TOPRIGHT", MinimapCluster, "TOPRIGHT", 0, 0)
MinimapNorthTag = T(MinimapBackdrop, "MinimapNorthTag", "ARTWORK", 16, 16, "CENTER", Minimap, "TOP", 0, 0)
F("Button", "MinimapZoneTextButton", MinimapCluster, 140, 12, "CENTER", MinimapCluster, "TOP", 8, -10)
S(MinimapZoneTextButton, "MinimapZoneText", "BACKGROUND", "TOP", MinimapZoneTextButton, "TOP", 0, 0)
F("Button", "MinimapZoomIn", MinimapBackdrop, 32, 32, "CENTER", MinimapBackdrop, "CENTER", 77, -25)
F("Button", "MinimapZoomOut", MinimapBackdrop, 32, 32, "CENTER", MinimapBackdrop, "CENTER", 55, -47)
F("Button", "MiniMapWorldMapButton", MinimapBackdrop, 32, 32, "CENTER", MinimapBackdrop, "CENTER", -35, 68)
F("Frame", "MiniMapTracking", MinimapBackdrop, 32, 32, "TOPLEFT", MinimapBackdrop, "TOPLEFT", 9, -45)
F("Button", "MiniMapTrackingButton", MiniMapTracking, 32, 32, "TOPLEFT")
T(MiniMapTracking, "MiniMapTrackingIcon", "ARTWORK", 20, 20, "TOPLEFT", MiniMapTracking, "TOPLEFT", 6, -6)
T(MiniMapTracking, "MiniMapTrackingBackground", "BACKGROUND", 32, 32, "TOPLEFT")
T(MiniMapTrackingButton, "MiniMapTrackingButtonBorder", "BORDER", 54, 54, "TOPLEFT")
F("Button", "GameTimeFrame", MinimapCluster, 40, 40, "TOPRIGHT", MinimapCluster, "TOPRIGHT", -2, -2)
F("Frame", "MiniMapMailFrame", MinimapBackdrop, 33, 33, "TOPRIGHT", Minimap, "TOPRIGHT", 24, -37); MiniMapMailFrame:Hide()
F("Button", "MiniMapLFGFrame", MinimapBackdrop, 33, 33, "TOPLEFT", MinimapBackdrop, "TOPLEFT", 25, -100); MiniMapLFGFrame:Hide()
F("Button", "MiniMapBattlefieldFrame", MinimapBackdrop, 33, 33, "CENTER", MinimapBackdrop, "CENTER", -74, -24); MiniMapBattlefieldFrame:Hide()
F("Button", "MiniMapVoiceChatFrame", MinimapBackdrop, 33, 33, "CENTER", MinimapBackdrop, "CENTER", -50, -50); MiniMapVoiceChatFrame:Hide()
F("Frame", "MiniMapInstanceDifficulty", MinimapCluster, 64, 46, "TOPLEFT", MinimapCluster, "TOPLEFT", 22, -15); MiniMapInstanceDifficulty:Hide()
F("Button", "TimeManagerClockButton", Minimap, 60, 28, "CENTER", Minimap, "BOTTOM", 0, -2)

DurabilityFrame:SetPoint("TOPRIGHT", MinimapCluster, "BOTTOMRIGHT", -40, 15)
WatchFrame = F("Frame", "WatchFrame", UIParent, 204, 500, "TOPRIGHT", MinimapCluster, "BOTTOMRIGHT", -15, 0)
WatchFrame:SetMovable(true)

-- Game menu
GameMenuFrame = F("Frame", "GameMenuFrame", UIParent, 195, 248, "CENTER")
GameMenuFrame:Hide()
local menu = { "GameMenuButtonHelp", "GameMenuButtonStore", "GameMenuButtonOptions", "GameMenuButtonSoundOptions", "GameMenuButtonUIOptions",
    "GameMenuButtonKeybindings", "GameMenuButtonMacros", "GameMenuButtonLogout", "GameMenuButtonQuit", "GameMenuButtonContinue" }
for i, n in ipairs(menu) do
    local b = F("Button", n, GameMenuFrame, 144, 21)
    if i == 1 then b:SetPoint("TOP", GameMenuFrame, "TOP", 0, -37)
    elseif n == "GameMenuButtonContinue" then b:SetPoint("TOP", menu[i - 1], "BOTTOM", 0, -16)
    else b:SetPoint("TOP", menu[i - 1], "BOTTOM", 0, -1) end
end
GameMenuFrame:SetScript("OnShow", function(self) self:SetHeight(248) end) -- server script resets the height on show

GameTooltip = CreateFrame("GameTooltip", "GameTooltip", UIParent)
function GameTooltip:SetBackpackToken(i) self.__lines = { "token " .. i } end
GameTooltip:Hide()
KeyBindingFrame = CreateFrame("Frame", "KeyBindingFrame", UIParent); KeyBindingFrame:Hide()
InterfaceOptionsFrame = CreateFrame("Frame", "InterfaceOptionsFrame", UIParent); InterfaceOptionsFrame:Hide()

-- Blizzard FrameXML functions execute securely (they may touch protected
-- frames in combat); addon post-hooks added later run insecurely.
for _, n in ipairs({ "UIParent_ManageFramePositions", "ReputationWatchBar_Update", "MainMenuExpBar_Update", "ShowBonusActionBar", "HideBonusActionBar",
    "MultiActionBar_Update", "ActionButton_Update", "TotemFrame_Update", "ActionButton_ShowGrid", "ActionButton_HideGrid", "PetActionBar_OnUpdate", "MoveMicroButtons",
    "UpdateMicroButtons", "MainMenuBar_UpdateKeyRing", "PlayerFrame_ToPlayerArt", "PlayerFrame_ToVehicleArt", "PlayerFrame_UpdateStatus",
    "TargetFrame_CheckClassification", "TargetFrame_Update", "FocusFrame_SetSmallSize", "FCF_RestorePositionAndDimensions",
    "MultiCastActionBarFrame_Update", "ShowMultiCastActionBar", "MultiCastActionBarFrame_OnUpdate", "MultiCastFlyoutButton_OnClick",
    "BuffFrame_UpdateAllBuffAnchors", "GameTooltip_SetDefaultAnchor", "HideMultiCastActionBar", "ShapeshiftBar_Update" }) do
    local f = _G[n]
    _G[n] = function(...)
        M.secureDepth = M.secureDepth + 1
        local r = { pcall(f, ...) }
        M.secureDepth = M.secureDepth - 1
        if not r[1] then error(r[2], 2) end
        return unpack(r, 2)
    end
end

-- textures that FrameXML creates hidden
for _, n in ipairs({ "PlayerFrameFlash", "TargetFrameFlash", "FocusFrameFlash", "CastingBarFrameFlash", "PlayerStatusTexture", "PlayerStatusGlow",
    "PlayerRestGlow", "PlayerAttackGlow", "PlayerAttackBackground", "PlayerRestIcon", "PlayerAttackIcon", "PlayerPVPIcon", "PlayerLeaderIcon",
    "PlayerMasterIcon", "PlayerFrameVehicleTexture", "TargetFrameTextureFramePVPIcon", "TargetFrameTextureFrameLeaderIcon",
    "TargetFrameTextureFrameRaidTargetIcon", "TargetFrameTextureFrameHighLevelTexture", "CastingBarFrameIcon" }) do
    if _G[n] then _G[n]:Hide() end
end
for _, n in ipairs({ "ActionButton", "BonusActionButton", "MultiBarBottomLeftButton", "MultiBarBottomRightButton", "MultiBarRightButton", "MultiBarLeftButton" }) do
    for i = 1, 12 do local f = _G[n .. i .. "Flash"]; if f then f:Hide() end; local b = _G[n .. i .. "Border"]; if b then b:Hide() end end
end

-- ------------------------------------------------------------ harness API
local H = {}
M.H = H
function H.fire(event, ...)
    local list = {}
    for f in pairs(M.events[event] or {}) do list[#list + 1] = f end
    for _, f in ipairs(list) do
        local fn = f.__scripts.OnEvent
        if fn then M.call(fn, f, event, ...) end
    end
end
function H.tick(dt, n)
    for _ = 1, n or 1 do
        M.time = M.time + (dt or 0.02)
        for f in pairs(M.onupdate) do
            if f.__moving then M.updateMoving(f) end
        end
        local list = {}
        for f in pairs(M.onupdate) do if f:IsVisible() and f.__scripts.OnUpdate then list[#list + 1] = f end end
        for _, f in ipairs(list) do M.call(f.__scripts.OnUpdate, f, dt or 0.02) end
    end
end
local function clickable(f)
    if not f:IsVisible() then return false, "not visible" end
    if f.IsEnabled and not f:IsEnabled() then return false, "disabled" end
    return true
end
function H.click(f, btn)
    if type(f) == "string" then f = _G[f] end
    assert(f, "click: nil frame")
    local ok, why = clickable(f)
    if not ok then error("cannot click " .. tostring(f:GetName()) .. ": " .. why, 2) end
    if f.__type == "CheckButton" then f.__checked = not f.__checked end
    local fn = f.__scripts.PreClick; if fn then M.call(fn, f, btn or "LeftButton", false) end
    fn = f.__scripts.OnClick
    if fn then M.call(fn, f, btn or "LeftButton", false) end
    fn = f.__scripts.PostClick; if fn then M.call(fn, f, btn or "LeftButton", false) end
end
function H.center(f)
    local l, b, w, h = M.rect(f)
    return l + w / 2, b + h / 2
end
function H.cursor(x, y) M.cursorX, M.cursorY = x, y end
-- drag frame f by (dx,dy) screen pixels in `steps` frames
function H.drag(f, dx, dy, steps)
    steps = steps or 10
    local x, y = H.center(f)
    H.cursor(x, y)
    local start = f.__scripts.OnMouseDown
    if start then M.call(start, f, "LeftButton") end
    local ds = f.__scripts.OnDragStart
    if ds then M.call(ds, f, "LeftButton") end
    for i = 1, steps do
        H.cursor(x + dx * i / steps, y + dy * i / steps)
        H.tick(0.016)
    end
    local de = f.__scripts.OnDragStop
    if de then M.call(de, f) end
    local up = f.__scripts.OnMouseUp
    if up then M.call(up, f, "LeftButton") end
    H.tick(0.016)
end
-- CloseSpecialWindows(): hides every shown special frame, in list order
function H.escape()
    local found = false
    for i = 1, #UISpecialFrames do
        local f = _G[UISpecialFrames[i]]
        if f and f:IsShown() then f:Hide(); found = true end
    end
    return found
end
function H.pressKey(key) -- override bindings first, like the client
    local o = M.overrides[key]
    if o then local b = _G[o.button]; local fn = b and b.__scripts.OnClick; if fn then M.call(fn, b, o.mouse or "LeftButton", false) end; return true end
    return false
end
function H.type(box, text)
    box.__text = text
    local fn = box.__scripts.OnTextChanged; if fn then M.call(fn, box, true) end
end
function H.enter(box) local fn = box.__scripts.OnEnterPressed; if fn then M.call(fn, box) end end
function H.key(f, key) local fn = f.__scripts.OnKeyDown; if fn then M.call(fn, f, key) end end
function H.hover(f)
    if M.mouseFocus and M.mouseFocus ~= f then local fn = M.mouseFocus.__scripts and M.mouseFocus.__scripts.OnLeave; if fn then M.call(fn, M.mouseFocus) end end
    M.mouseFocus = f
    if f then local fn = f.__scripts.OnEnter; if fn then M.call(fn, f) end end
end
function H.wheel(f, d) local fn = f.__scripts.OnMouseWheel; if fn then M.call(fn, f, d) end end
function H.enterCombat() H.fire("PLAYER_REGEN_DISABLED"); M.combat = true end
function H.leaveCombat() M.combat = false; H.fire("PLAYER_REGEN_ENABLED") end
function H.findText(root, text)
    -- depth-first search of visible frames whose text equals `text`
    local found
    local function walk(f)
        if found or not f.__shown then return end
        if f.__isframe and f.GetText and f:GetText() == text then found = f; return end
        if f.__isframe and f.__fs and f.__fs.__text == text then found = f; return end
        for _, c in ipairs(f.__children or {}) do walk(c) end
    end
    walk(root or UIParent)
    return found
end
function H.clearErrors() M.errors = {}; M.blocked = {} end
return H
