-- Backpack currencies for Bagnon users. Blizzard attaches the "Show on
-- Backpack" currencies only to its own backpack window (ManageBackpackTokenFrame
-- uses GetBackpackFrame), which Bagnon replaces. This shows the same
-- currencies in a small strip under Bagnon's inventory window. It reads
-- GetBackpackCurrencyInfo only; no Blizzard or Bagnon frame is changed.
local A = BlizzUIReborn
local C = A.Colors
local KNOWN = { "BagnonFrameinventory", "BagnonFrameInventory", "BagnonInventoryFrame", "BagnonInventory1", "Bagnon_Inventory" }
local scanned = 0

function A:BagnonInventory()
    local f = self.bagnonHost
    if f then return f end
    for _, n in ipairs(KNOWN) do if type(_G[n]) == "table" and _G[n].IsVisible then self.bagnonHost = _G[n]; return _G[n] end end
    -- unknown Bagnon build: look for its inventory frame by name (rarely)
    if GetTime() - scanned > 10 then
        scanned = GetTime()
        for k, v in pairs(_G) do
            if type(k) == "string" and type(v) == "table" and k:find("^Bagnon") and k:lower():find("inventory")
                and not k:find("Button") and type(v.IsVisible) == "function" and type(v.GetObjectType) == "function" and v:GetObjectType() == "Frame" then
                self.bagnonHost = v
                return v
            end
        end
    end
end
local function tokenIcon(button, extra, icon)
    if extra == 1 then
        button.icon:SetTexture("Interface\\PVPFrame\\PVP-ArenaPoints-Icon"); button.icon:SetTexCoord(0, 1, 0, 1)
    elseif extra == 2 then
        local faction = UnitFactionGroup and UnitFactionGroup("player")
        if faction then
            button.icon:SetTexture("Interface\\TargetingFrame\\UI-PVP-" .. faction)
            button.icon:SetTexCoord(.03125, .59375, .03125, .59375)
        end
    else
        button.icon:SetTexture(icon); button.icon:SetTexCoord(0, 1, 0, 1)
    end
end
function A:BuildCurrencyStrip()
    local s = CreateFrame("Frame", "BlizzUIRebornBagCurrency", UIParent)
    s:SetHeight(24)
    A.StylePanel(s)
    s.buttons = {}
    for i = 1, 3 do
        local b = CreateFrame("Button", nil, s)
        A.Size(b, 70, 18)
        b:SetPoint("LEFT", s, "LEFT", 8 + (i - 1) * 74, 0)
        b.icon = b:CreateTexture(nil, "ARTWORK"); A.Size(b.icon, 14, 14); b.icon:SetPoint("LEFT", b, "LEFT", 0, 0)
        b.count = A.Text(b, 12, C.text); b.count:SetPoint("LEFT", b.icon, "RIGHT", 4, 0)
        b:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            if GameTooltip.SetBackpackToken then GameTooltip:SetBackpackToken(i) else GameTooltip:SetText(self.name or "") end
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        s.buttons[i] = b
    end
    s:Hide()
    self.currencyStrip = s
end
function A:UpdateCurrencyStrip()
    local s = self.currencyStrip
    if not IsAddOnLoaded("Bagnon") or (self.db and self.db.bagnonCurrency == false) or not GetBackpackCurrencyInfo then
        if s then s:Hide() end
        return
    end
    local host = self:BagnonInventory()
    if not host or not host:IsVisible() then if s then s:Hide() end; return end
    if not s then self:BuildCurrencyStrip(); s = self.currencyStrip end
    local n = 0
    for i = 1, 3 do
        local name, count, extra, icon = GetBackpackCurrencyInfo(i)
        local b = s.buttons[i]
        if name then
            n = i
            b.name = name
            tokenIcon(b, extra, icon)
            b.count:SetText(count and count <= 99999 and count or "*")
            b:Show()
        else
            b:Hide()
        end
    end
    if n == 0 then s:Hide(); return end
    if s:GetParent() ~= host then s:SetParent(host) end
    s:ClearAllPoints()
    s:SetPoint("TOPLEFT", host, "BOTTOMLEFT", 0, 2)
    s:SetWidth(math.max(90, 16 + n * 74))
    s:SetFrameLevel(host:GetFrameLevel() + 5)
    s:Show()
end
function A:InitCurrency()
    if not IsAddOnLoaded("Bagnon") then return end
    local later = function() A:After(.05, function() A:UpdateCurrencyStrip() end, "currency") end
    for _, fn in ipairs({ "ToggleBackpack", "OpenBackpack", "ToggleAllBags", "OpenAllBags", "CloseAllBags", "CloseBackpack" }) do self:Hook(fn, later) end
    for _, ev in ipairs({ "CURRENCY_DISPLAY_UPDATE", "HONOR_CURRENCY_UPDATE", "BAG_UPDATE", "PLAYER_MONEY" }) do self:On(ev, later) end
    -- follow the bag window opening/closing by other means (key bindings, bank)
    self:Every(.5, function()
        local host = A.bagnonHost
        local shown = host and host:IsVisible() or false
        if shown ~= A.currencyHostShown then A.currencyHostShown = shown; A:UpdateCurrencyStrip() end
    end)
end
