dofile(TESTS_DIR .. "lib.lua")
MOCK.loadedAddons.Bagnon = true
local inv = CreateFrame("Frame", "BagnonFrameinventory", UIParent); inv:SetWidth(300); inv:SetHeight(400); inv:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -40, 120); inv:Hide()
function ToggleBackpack() if inv:IsShown() then inv:Hide() else inv:Show() end end
H.login()
MOCK.currencies = { { "Emblem of Frost", 42, 0, "Interface\\Icons\\Frost" }, { "Honor Points", 12000, 2, nil } }
ToggleBackpack(); H.tick(0.1, 3)
local s = A.currencyStrip
check(s and s:IsShown(), "currency strip shows under Bagnon's bags")
check(s:GetParent() == inv, "attached to Bagnon's inventory window")
check(s.buttons[1].count:GetText() == "42" and s.buttons[2]:IsShown() and not s.buttons[3]:IsShown(), "shows the watched currencies")
local _, rel, rp = s:GetPoint(1)
check(rel == inv and rp == "BOTTOMLEFT", "sits below the bag window")
H.hover(s.buttons[1]); check(GameTooltip.__lines[1] == "token 1", "tooltip")
ToggleBackpack(); H.tick(0.6, 2)
check(not s:IsShown(), "hides with the bags")
MOCK.currencies = {}
ToggleBackpack(); H.tick(0.1, 3)
check(not s:IsShown(), "nothing shown when no currency is watched")
A.db.bagnonCurrency = false
MOCK.currencies = { { "Emblem", 1, 0, "x" } }
A:UpdateCurrencyStrip()
check(not s:IsShown(), "option turns it off")
