-- Retail-style Quick Keybind Mode: hover an action button and press a key.
local A = BlizzUIReborn
local C = A.Colors
local COMMANDS = {
    ActionButton = "ACTIONBUTTON", BonusActionButton = "ACTIONBUTTON",
    MultiBarBottomLeftButton = "MULTIACTIONBAR1BUTTON", MultiBarBottomRightButton = "MULTIACTIONBAR2BUTTON",
    MultiBarRightButton = "MULTIACTIONBAR3BUTTON", MultiBarLeftButton = "MULTIACTIONBAR4BUTTON",
    ShapeshiftButton = "SHAPESHIFTBUTTON", PetActionButton = "BONUSACTIONBUTTON",
}
local IGNORE = { LSHIFT = 1, RSHIFT = 1, LCTRL = 1, RCTRL = 1, LALT = 1, RALT = 1, UNKNOWN = 1 }

function A:BindingCommand(frame)
    local name = frame and frame.GetName and frame:GetName()
    if not name then return end
    local prefix, n = name:match("^(%a+)(%d+)$")
    if prefix and COMMANDS[prefix] then return COMMANDS[prefix] .. n end
end
local function keyName(key)
    local mods = (IsAltKeyDown() and "ALT-" or "") .. (IsControlKeyDown() and "CTRL-" or "") .. (IsShiftKeyDown() and "SHIFT-" or "")
    return mods .. key
end
local function keysText(cmd)
    local keys = { GetBindingKey(cmd) }
    if #keys == 0 then return "|cff999999Not bound|r" end
    return table.concat(keys, ", ")
end

function A:BuildQuickKeybind()
    local f = A.Panel("BlizzUIRebornQuickKeybind", UIParent, 460, 120, "Quick Keybind Mode", "FULLSCREEN_DIALOG")
    f:SetPoint("TOP", UIParent, "TOP", 0, -90)
    f.info = A.Text(f, 12, C.text); f.info:SetPoint("TOP", f, "TOP", 0, -40); f.info:SetWidth(420)
    f.info:SetText("Hover over an action button and press a key to bind it.\nPress the same key again to unbind it. Press Escape when done.")
    f.status = A.Text(f, 12, C.gold); f.status:SetPoint("TOP", f.info, "BOTTOM", 0, -8); f.status:SetWidth(420)
    f.done = A.Button(f, "Done", 110, function() A:StopQuickKeybind() end)
    f.done:SetPoint("BOTTOM", f, "BOTTOM", 0, 12)
    f.OnClose = function() A:StopQuickKeybind() end
    -- keyboard catcher: no mouse, so the hovered action button stays the mouse focus
    local k = CreateFrame("Frame", "BlizzUIRebornQuickKeybindKeys", UIParent)
    k:SetFrameStrata("FULLSCREEN_DIALOG")
    k:EnableMouse(false)
    k:SetScript("OnKeyDown", function(_, key) A:Run("Quick Keybind", A.QuickKeyPressed, A, key) end)
    local elapsed = 0
    k:SetScript("OnUpdate", function(_, e)
        elapsed = elapsed + e
        if elapsed < .1 then return end
        elapsed = 0
        local cmd = A:BindingCommand(GetMouseFocus())
        if cmd ~= f.hover then
            f.hover = cmd
            if cmd then f.status:SetText(cmd .. ": " .. keysText(cmd)) elseif not f.sticky then f.status:SetText("") end
        end
    end)
    k:Hide(); f:Hide()
    f.keys = k
    self.quickKeybind = f
end
function A:StartQuickKeybind()
    if A.Combat() then self:Print("Key bindings cannot be changed in combat."); return end
    if not self.quickKeybind then self:BuildQuickKeybind() end
    self.keybinding = true
    A.CloseMenu()
    if self.settingsDialog then self.settingsDialog:Hide() end
    if self.editor then self.editor:Hide() end
    self:SetNudge(false)
    self:UpdateOverlays()
    self.quickKeybind.status:SetText("")
    self.quickKeybind:Show()
    self.quickKeybind.keys:Show()
    self.quickKeybind.keys:EnableKeyboard(true)
end
function A:StopQuickKeybind()
    if not self.keybinding then return end
    self.keybinding = nil
    local f = self.quickKeybind
    f.keys:EnableKeyboard(false); f.keys:Hide(); f:Hide()
    if self.editing then
        self.editor:Show()
        self:UpdateOverlays()
        if self.selected then self:ShowSettings(); self:SetNudge(true) end
    end
end
function A:QuickKeyPressed(key)
    if key == "ESCAPE" then self:StopQuickKeybind(); return end
    if IGNORE[key] or A.Combat() then return end
    local f = self.quickKeybind
    local cmd = self:BindingCommand(GetMouseFocus())
    if not cmd then
        f.status:SetText("|cffff6060Hover over an action button first.|r"); return
    end
    if key == "LeftButton" or key == "RightButton" then return end
    local full = keyName(key)
    if GetBindingAction(full) == cmd then
        SetBinding(full)
        f.status:SetText("Unbound " .. full .. " from " .. cmd)
    else
        SetBinding(full, cmd)
        f.status:SetText("Bound " .. full .. " to " .. cmd)
    end
    SaveBindings(GetCurrentBindingSet())
end
