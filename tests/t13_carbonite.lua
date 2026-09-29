-- Carbonite adapter + Addon Compartment with LibDataBroker launchers
dofile(TESTS_DIR .. "lib.lua")
-- fake Carbonite 3.34 with a visible map and an icon dock
local mapFrame = CreateFrame("Frame", "NxMap1", UIParent)
A_Size = function(f, w, h) f:SetWidth(w); f:SetHeight(h) end
A_Size(mapFrame, 240, 240); mapFrame:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -20, -20)
local mmBut = CreateFrame("Button", "NXMiniMapBut", Minimap); A_Size(mmBut, 32, 32); mmBut:SetPoint("TOPLEFT")
local clicked
mmBut:SetScript("OnClick", function(self, btn) clicked = btn end)
Nx = { VERMAJOR = 3.34, VERSION = "3.34", Map = { Doc = { MMF1 = { GameTimeFrame, MiniMapMailFrame, mmBut } } } }
local carbMap = { Frm = mapFrame, Win1 = { Frm = mapFrame }, MMOF = {} }
function Nx.Map:GeM() return carbMap end
-- Carbonite's periodic scan (Nx.Map:MoveMinimap...): every shown Minimap child
-- it doesn't know goes into the dock and is re-parented to the dock window
local dockWin = CreateFrame("Frame", "NxMapDock", UIParent); dockWin:SetWidth(40); dockWin:SetHeight(200); dockWin:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -300, -100)
local function carboniteScan()
    for _, c in ipairs({ Minimap:GetChildren() }) do
        if c:IsShown() and not carbMap.MMOF[c] and not (c:GetName() or ""):find("^MiniMap") then
            carbMap.MMOF[c] = 0
            table.insert(Nx.Map.Doc.MMF1, c)
            c:SetParent(dockWin); c:ClearAllPoints(); c:SetPoint("CENTER", dockWin, "TOPLEFT", 20, -20 * #Nx.Map.Doc.MMF1)
        end
    end
end
-- fake LDB with one launcher
local ldbObjects = { WeakAuras = { type = "launcher", label = "WeakAuras", icon = "x", OnClick = function(frame, btn) WA_CLICK = btn end },
    Recount = { type = "data source", text = "x" } }
local iconButton = CreateFrame("Button", "LibDBIcon10_WeakAuras", Minimap); A_Size(iconButton, 31, 31); iconButton:SetPoint("CENTER")
LibStub = { GetLibrary = function(_, name)
    if name == "LibDataBroker-1.1" then return { DataObjectIterator = function() return pairs(ldbObjects) end } end
    if name == "LibDBIcon-1.0" then return { objects = { WeakAuras = iconButton } } end
end }
MOCK.loadedAddons.Carbonite = true
-- like the screenshot: a big (semi-transparent) Carbonite map window with the
-- native minimap embedded as a small square in its top-left corner
A_Size(mapFrame, 440, 220); mapFrame:ClearAllPoints(); mapFrame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 160, -70)
Minimap:SetParent(mapFrame); Minimap:ClearAllPoints(); Minimap:SetPoint("TOPLEFT", mapFrame, "TOPLEFT", 0, 0); A_Size(Minimap, 64, 64)
MinimapCluster:Hide()
MiniMapTracking:SetParent(UIParent); GameTimeFrame:SetParent(UIParent); TimeManagerClockButton:SetParent(UIParent)
-- stray addon buttons: a legacy minimap button, one in Carbonite's dock, a map pin that must stay
local stray = CreateFrame("Button", "RecountMinimapButton", Minimap); A_Size(stray, 32, 32); stray:SetPoint("CENTER", Minimap, "CENTER", 90, 0)
stray:CreateTexture("RecountMinimapButtonIcon", "ARTWORK"):SetTexture("Interface\\Icons\\INV_Misc_Book")
local strayClicked; stray:SetScript("OnClick", function(_, b) strayClicked = b end)
local docked = CreateFrame("Button", "Bagnon_MinimapButton", UIParent); A_Size(docked, 31, 31); docked:SetPoint("TOPRIGHT", mapFrame, "TOPRIGHT", 30, -40)
table.insert(Nx.Map.Doc.MMF1, docked)
local pin = CreateFrame("Button", "GatherNote12", Minimap); A_Size(pin, 12, 12); pin:SetPoint("CENTER", Minimap, "CENTER", 40, 10)
-- the screenshot glitch: Questie town pins (mailboxes) already swallowed by the dock
local docPin = CreateFrame("Button", "QuestieFrame7", Minimap); A_Size(docPin, 16, 16); docPin:SetPoint("CENTER", Minimap, "CENTER", 10, 10)
carboniteScan()
local unnamedPin = CreateFrame("Frame", nil, Minimap); A_Size(unnamedPin, 14, 14); unnamedPin:SetPoint("CENTER", Minimap, "CENTER", -10, 5)
H.login()
H.tick(0.3, 2)
local ml, mb, mw, mh = A.Rect(Minimap)
local function overlapsMinimap(f)
    local l, b, w, h = A.Rect(f)
    return l and not (l + w <= ml or l >= ml + mw or b + h <= mb or b >= mb + mh)
end
local wl, wb, ww, wh = A.Rect(mapFrame)
local function overlapsWindow(f)
    local l, b, w, h = A.Rect(f)
    return l and not (l + w <= wl + .5 or l >= wl + ww - .5 or b + h <= wb + .5 or b >= wb + wh - .5)
end
check(A.statusRef == mapFrame, "Carbonite's map window (not the embedded minimap) is the reference")
for _, n in ipairs({ "GameTimeFrame", "MiniMapTracking", "MiniMapMailFrame", "TimeManagerClockButton" }) do
    check(not overlapsWindow(_G[n]), n .. " is outside the Carbonite window")
end
for _, n in ipairs({ "GameTimeFrame", "MiniMapTracking" }) do
    local l = A.Rect(_G[n])
    check(l >= wl + ww, n .. " sits in the column on the window's right")
end
local gl, gb, gw, gh = A.Rect(GameTimeFrame)
check(math.abs((gb + gh) - (wb + wh)) < 6, "column starts level with the window's top")
check(not overlapsWindow(A.elements.compartment.frame), "Addon Compartment is outside the window")
local cl, cb, cw, ch = A.Rect(A.elements.compartment.frame)
check(cb + ch <= wb + .5 and math.abs(cl - wl) < 1, "Addon Compartment sits under the window's lower-left corner")
local tl, tb, tw, th = A.Rect(TimeManagerClockButton)
check(tb + th <= wb + .5 and wb - (tb + th) < 10, "clock sits right under the window")
check(math.abs((tl + tw / 2) - (wl + ww / 2)) < 2, "clock is centred under the window")
-- the embedded minimap moving around inside the map (flying) moves nothing
Minimap:ClearAllPoints(); Minimap:SetPoint("TOPLEFT", mapFrame, "TOPLEFT", 200, -100)
H.tick(0.3, 3)
local gl2, gb2 = A.Rect(GameTimeFrame)
local tl2, tb2 = A.Rect(TimeManagerClockButton)
check(gl2 == gl and gb2 == gb and tl2 == tl and tb2 == tb, "icons and clock stay put when the minimap moves inside the map")
Minimap:Hide(); H.tick(0.3, 2)
check(select(1, A.Rect(GameTimeFrame)) == gl, "or when Carbonite hides the minimap on mouse-over")
Minimap:Show()
-- Carbonite's dock never takes map pins; pins it already took go back
local inDockPin = false
for _, f in ipairs(Nx.Map.Doc.MMF1) do if f == docPin then inDockPin = true end end
check(not inDockPin and docPin:GetParent() == Minimap, "Questie pin taken out of Carbonite's dock and returned to the minimap")
check(carbMap.MMOF[unnamedPin] and carbMap.MMOF[pin], "pins marked so Carbonite's scan skips them")
H.click(A.elements.compartment.frame)
local pr = A.compartmentMenu:GetRight()
check(pr and pr <= wl and math.abs(A.compartmentMenu:GetTop() - (wb + wh)) < 1, "compartment menu opens beside the window, top-aligned")
A.compartmentMenu:Hide()
local before = #Nx.Map.Doc.MMF1
carboniteScan()
local pinsInDock = 0
for _, f in ipairs(Nx.Map.Doc.MMF1) do if f == unnamedPin or f == pin or f == docPin then pinsInDock = pinsInDock + 1 end end
check(pinsInDock == 0, "a later Carbonite scan docks no pins")
check(A.launchers["mm:RecountMinimapButton"] and stray:GetAlpha() == 0, "stray legacy minimap button collected and hidden")
check(A.launchers["mm:Bagnon_MinimapButton"] and docked:GetAlpha() == 0, "button in Carbonite's dock collected")
local inDock = false
for _, f in ipairs(Nx.Map.Doc.MMF1) do if f == docked then inDock = true end end
check(not inDock, "collected button removed from Carbonite's dock")
check(not A.launchers["mm:GatherNote12"] and pin:GetAlpha() == 1, "map pins are left alone")
check(A.launchers["mm:RecountMinimapButton"].label == "Recount", "readable label")
check(A:CarboniteActive(), "Carbonite detected")
check(A.elements.minimap.frame == nil, "Minimap cluster is not an editable element under Carbonite")
local mp, mrel = MinimapCluster:GetPoint(1)
check(mrel == UIParent and mp == "TOPRIGHT", "MinimapCluster untouched")
H.tick(0.3, 2)
check(A.statusLeases[GameTimeFrame] ~= nil, "calendar leased")
local found = false
for _, f in ipairs(Nx.Map.Doc.MMF1) do if f == GameTimeFrame then found = true end end
check(not found, "leased icons removed from Carbonite's dock list")
-- Carbonite trying to move a leased icon is ignored
GameTimeFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
check(select(1, A.Rect(GameTimeFrame)) == gl, "lease blocks Carbonite repositioning")
-- compartment
H.tick(5.1, 2)
check(A.launchers.weakauras and not A.launchers.recount, "only launchers collected")
check(iconButton:GetAlpha() == 0 and not iconButton:IsMouseEnabled(), "original minimap button hidden")
check(A.launchers.carbonite, "Carbonite legacy button collected")
H.click(A.elements.compartment.frame)
check(A.compartmentMenu:IsShown(), "compartment opens")
local row
for _, r in ipairs(A.compartmentMenu.rows) do if r:IsShown() and r.text:GetText() == "WeakAuras" then row = r end end
check(row, "WeakAuras row")
H.click(row, "RightButton")
check(WA_CLICK == "RightButton" and not A.compartmentMenu:IsShown(), "row click forwards the mouse button and closes")
H.click(A.elements.compartment.frame)
for _, r in ipairs(A.compartmentMenu.rows) do if r:IsShown() and r.text:GetText() == "Carbonite" then row = r end end
H.click(row, "MiddleButton")
check(clicked == "MiddleButton", "legacy button receives the click")
H.click(A.elements.compartment.frame)
for _, r in ipairs(A.compartmentMenu.rows) do if r:IsShown() and r.text:GetText() == "Recount" then row = r end end
H.click(row, "RightButton")
check(strayClicked == "RightButton", "collected minimap button receives the click")
-- edit mode: status icons movable via offsets
T.open()
A.db.editor.snap = false
check(T.overlay("status") and T.overlay("status"):IsShown(), "status icons editable with Carbonite")
T.dragElement("status", -10, -10)
check(A.draft.frames.status.offsetX == -10 and A.draft.frames.status.offsetY == -10, "dragging status icons changes offsets")
-- free movement around the map: left, above, below, and far down the side
local icons = { "GameTimeFrame", "MiniMapTracking", "MiniMapMailFrame" }
MiniMapMailFrame:Show()
local function allOutside(tag)
    local ok = true
    for _, n in ipairs(icons) do if overlapsWindow(_G[n]) then ok = false end end
    check(ok, tag .. ": icons stay outside the Carbonite window")
end
local function dragTo(x, y)
    local fx, fy = A.statusFirst[1], A.statusFirst[2]
    T.dragElement("status", x - fx, y - fy)
    H.tick(0.05, 2)
end
dragTo(wl - 30, wb + wh - 40)
check(A.draft.frames.status.side == "left", "dragged to the left side")
check(A.Rect(GameTimeFrame) + 20 <= wl + .5 and select(1, A.Rect(MiniMapTracking)) < wl, "column on the window's left")
allOutside("left")
dragTo(wl + 120, wb + wh + 30)
local _, gb = A.Rect(GameTimeFrame)
local tl = A.Rect(MiniMapTracking)
check(A.draft.frames.status.side == "top" and gb >= wb + wh - .5 and tl > A.Rect(GameTimeFrame), "row above the window")
allOutside("above")
dragTo(wl + 200, wb - 60)
local _, gb2, _, gh2 = A.Rect(GameTimeFrame)
local _, cb = A.Rect(TimeManagerClockButton)
check(A.draft.frames.status.side == "bottom" and gb2 + gh2 <= cb + .5, "row below the window, under the clock")
allOutside("below")
dragTo(wl + ww + 30, wb + 20)
check(A.draft.frames.status.side == "right" and A.draft.frames.status.offsetY < -100, "far down the right side (beyond the old +-100 limit)")
allOutside("right, low")
check(T.overlay("status"):IsShown() and near(select(1, A.Rect(T.overlay("status"))), select(1, A.Rect(GameTimeFrame)) - 2, 3), "selection follows the icons")
-- reset puts it back to Retail's column on the right
A:SetSetting("status", "side", "auto"); A:SetSetting("status", "offsetX", 0); A:SetSetting("status", "offsetY", 0)
check(A.Rect(GameTimeFrame) >= wl + ww, "reset: column on the right again")
A:RequestExit(); H.click(T.confirmButton("Exit"))
SlashCmdList.BLIZZUIREBORN("restore")
local found2 = false
for _, f in ipairs(Nx.Map.Doc.MMF1) do if f == GameTimeFrame then found2 = true end end
check(found2, "restore gives icons back to Carbonite's dock")
check(A.leases[GameTimeFrame] == nil and GameTimeFrame.SetPoint == nil or rawget(GameTimeFrame, "SetPoint") == nil, "lease wrappers removed")
check(iconButton:GetAlpha() == 1, "minimap button visible again")
