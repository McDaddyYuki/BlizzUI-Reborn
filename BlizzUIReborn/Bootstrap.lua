local A = BlizzUIReborn

-- ------------------------------------------------------------ game menu entry
function A:AddMenuEntry()
    if A.Combat() or not GameMenuFrame or not GameMenuButtonContinue then return end
    if not self.menuButton then
        local b = CreateFrame("Button", "BlizzUIRebornGameMenuButton", GameMenuFrame, "GameMenuButtonTemplate")
        b:SetText("Edit Mode")
        b:SetScript("OnClick", function() HideUIPanel(GameMenuFrame); A:OpenEditor() end)
        self.menuButton = b
    end
    local point, rel, relPoint, x, y = GameMenuButtonContinue:GetPoint(1)
    if rel ~= self.menuButton then
        self.menuButton:ClearAllPoints(); self.menuButton:SetPoint(point, rel, relPoint, x, y)
        self.menuButton:SetWidth(GameMenuButtonContinue:GetWidth())
        GameMenuButtonContinue:ClearAllPoints(); GameMenuButtonContinue:SetPoint("TOP", self.menuButton, "BOTTOM", 0, -2)
    end
    -- grow only when the height is not the one we set (server menus reset it)
    local h = GameMenuFrame:GetHeight()
    if not self.menuHeight or math.abs(h - self.menuHeight) > .5 then
        self.menuHeight = h + self.menuButton:GetHeight() + 2
        GameMenuFrame:SetHeight(self.menuHeight)
    end
end

-- ------------------------------------------------------------ lifecycle
function A:Initialize()
    if self.ready then return end
    self:InitDB()
    self:InitStatus()
    self:InitCompartment()
    self:Run("Bagnon currency", self.InitCurrency, self)
    self:Run("Boss Timeline", self.InitTimeline, self)
    self:BuildOptions()
    self.active = not self.char.suspended and not self:Conflict()
    for _, id in ipairs(self.order) do self:BindElement(self.elements[id]) end
    self:MigrateAll()
    self:LoadActive()
    -- The 0.1/0.2 builds left frames user-placed, so the client's layout cache
    -- may hold old positions as "defaults". Tell the player once how to clear it.
    if self.upgradedFromV1 and not self.db.cacheNotice then
        local polluted = false
        for _, id in ipairs(self.order) do
            local def = self.elements[id]
            if def.native and def.native.userPlaced then polluted = true end
        end
        if polluted then
            self.db.cacheNotice = true
            self:After(3, function()
                A:Print("Upgraded from an older build. If Classic or Reset To Default Position puts frames in odd places, log out and delete WTF\\Account\\<account>\\<realm>\\<character>\\layout-local.txt once (the old build saved frame positions there).")
            end)
        end
    end
    self.ready = true
    if self.active then
        self:ApplyAll(true)
        self:RefreshCompartment()
        self:UpdateStatus()
    end
    self:Run("Stance badge", self.UpdateClassBadge, self)
    self:Run("Boss Timeline", self.RefreshTimeline, self)
    self:AddMenuEntry()
    if GameMenuFrame then GameMenuFrame:HookScript("OnShow", function() A:Run("Menu", A.AddMenuEntry, A) end) end
    -- Blizzard re-anchors some frames; re-apply only what actually moved.
    -- (PlayerFrame_AnimFinished/SequenceFinished: end of the vehicle slide, which
    -- moves the player frame to its Blizzard spot)
    for _, fn in ipairs({ "UIParent_ManageFramePositions", "MultiActionBar_Update", "PlayerFrame_ToPlayerArt", "ShowBonusActionBar", "HideBonusActionBar",
        "PlayerFrame_AnimFinished", "PlayerFrame_SequenceFinished", "ShowPetActionBar", "HidePetActionBar", "PossessBar_Update" }) do
        self:Hook(fn, function() if A.active then A:After(0, function() A:CheckDrift() end, "drift") end end)
    end
    self:Every(.5, function() if A.active then A:CheckDrift() end end)
    self:Every(.25, function() if A.active and A:CarboniteActive() and not A.Combat() then A:UpdateStatus() end end)
    self:Every(5, function() if A.active and not A.Combat() then A:RefreshCompartment() end end)
    self:Every(1, function() if A.active and not A.Combat() then A:PlaceCompartment() end end)
    if self:Conflict() then
        self:Print("Layout management paused because " .. self:Conflict() .. " is loaded.")
    else
        self:Print("v" .. self.version .. " loaded. Escape > Edit Mode, or /br. Type /br help for commands.")
    end
end

-- The client saves SetUserPlaced() frames to layout-local.txt at logout.
-- Put managed frames back first so the next session sees true defaults.
function A:PrepareLogout()
    if A.Combat() then return end
    for _, id in ipairs(self.order) do
        local def = self.elements[id]
        if def.applied and def.userPlaced then
            self:RestoreElement(id)
            local f = def.frame
            pcall(function()
                local m = f:IsMovable(); f:SetMovable(true); f:SetUserPlaced(false); f:SetMovable(m)
            end)
        end
    end
end

function A:RestoreAll()
    if A.Combat() then self.restorePending = true; self:Print("Restore queued until combat ends."); return end
    if self.editing then self:FinishExit() end
    self:RestoreAllElements()
    self.active = false
    self.char.suspended = true
    self:ReleaseStatusIcons()
    for f in pairs(self.launcherLeases) do self:ReleaseLease(f) end
    self.launcherLeases = {}
    self.elements.compartment.frame:Hide(); self.compartmentMenu:Hide()
    self:RefreshTimeline()
    self:UpdateClassBadge()
    self:Print("Original positions restored and layout management suspended. /br enable resumes it. ")
end
function A:Resume()
    if A.Combat() then self:Print("Wait until combat ends."); return end
    if self:Conflict() then self:Print("Choose one UI addon: " .. self:Conflict() .. " is loaded."); return end
    self.char.suspended = nil
    self.active = true
    self:ApplyAll(true)
    self:RefreshCompartment()
    self:RefreshTimeline()
    self:UpdateClassBadge()
    self:Print("Layout management resumed.")
end

function A:Diagnostics()
    local lines = { "BlizzUI Reborn " .. self.version, "Mode: " .. (self.active and "active" or "suspended") }
    local v, b = GetBuildInfo()
    lines[#lines + 1] = "Client: " .. tostring(v) .. " / " .. tostring(b)
    lines[#lines + 1] = "Layout: " .. self.char.active.scope .. " / " .. self.char.active.name .. (self.dirty and " (unsaved changes)" or "")
    lines[#lines + 1] = "Carbonite: " .. (self:CarboniteActive() and tostring(Nx.VERSION or Nx.VERMAJOR) or "not loaded")
    for _, id in ipairs(self.order) do
        local def = self.elements[id]
        local f = def.frame
        lines[#lines + 1] = string.format("%s: %s%s%s", id, f and "found" or "missing", def.applied and ", applied" or "",
            f and f.IsProtected and f:IsProtected() and ", protected" or "")
    end
    local T = self.Timeline
    local E = T and T:Encounter()
    lines[#lines + 1] = "Boss Timeline: " .. (self:TimelineShown() and "on" or "off") .. ", warnings " .. (self:WarningsShown() and "on" or "off")
        .. (E and (", fighting " .. tostring(E.name) .. " (" .. E.source .. ")") or "")
        .. (T and T.lastEnd and (", last fight ended: " .. tostring(T.lastEnd.reason)) or "")
        .. ((_G.DBM and T and T.dbmHooked) and ", DBM timers" or "") .. ((T and T.bwHooked) and ", BigWigs timers" or "")
    local learned = 0
    for _ in pairs(self:TimelineDB().bosses or {}) do learned = learned + 1 end
    lines[#lines + 1] = "Boss knowledge: " .. learned .. " creatures, " .. tostring(self:TimelineDB().pull or 0) .. " pulls"
    lines[#lines + 1] = "Recent errors:"
    if #self.errorLog == 0 then lines[#lines + 1] = "  none" end
    for _, e in ipairs(self.errorLog) do lines[#lines + 1] = e end
    self:TextDialog({ title = "Diagnostic Report", label = "Press Ctrl+C to copy:", multiline = true, initial = table.concat(lines, "\n") })
end

-- ------------------------------------------------------------ events
A:On("PLAYER_LOGIN", function() A:Initialize() end)
A:On("PLAYER_ENTERING_WORLD", function()
    if not A.ready then return end
    A:After(.1, function() if A.active and not A.Combat() then A:ApplyAll(true) end end, "pew")
end)
A:On("PLAYER_REGEN_DISABLED", function()
    if not A.ready then return end
    -- this fires just before lockdown: last chance for protected cleanup
    if A.keybinding then A:StopQuickKeybind() end
    if A.active then A:UpdateBarVisibility(true) end
    if A.editing then
        A:FinishExit()
        A:Print("Edit Mode closed for combat. Your unsaved changes are kept; reopen it with /br after combat.")
    end
    A:SetNudge(false)
end)
A:On("PLAYER_REGEN_ENABLED", function()
    if not A.ready then return end
    if A.restorePending then A.restorePending = nil; A:RestoreAll(); return end
    if A.active then A:UpdateBarVisibility(false) end
    if A.active then
        local pending = A.pendingApply
        A.pendingApply = nil
        for _, id in ipairs(A.order) do
            local def = A.elements[id]
            if def.pending or pending then A:ApplyElement(id, true) end
        end
        A:RefreshCompartment()
    end
end)
A:On("PLAYER_LOGOUT", function() if A.ready then A:PrepareLogout() end end)
local function rescale()
    if not A.ready or not A.active then return end
    A:After(.05, function()
        if A.Combat() then A.pendingApply = true; return end
        A:ApplyAll(true); A:BuildGrid(); if A.editing then A:UpdateOverlays() end
    end, "rescale")
end
A:On("DISPLAY_SIZE_CHANGED", rescale)
A:On("UI_SCALE_CHANGED", rescale)
A:On("ADDON_LOADED", function(name)
    if not A.ready then return end
    if (name == "ElvUI" or name == "Tukui") and A.active then A:RestoreAll() end
end)

-- ------------------------------------------------------------ slash commands
SLASH_BLIZZUIREBORN1, SLASH_BLIZZUIREBORN2 = "/br", "/blizzui"
SlashCmdList.BLIZZUIREBORN = function(msg)
    msg = A.Trim(msg):lower()
    if not A.ready then A:Print("Still loading."); return end
    if msg == "" or msg == "edit" then A:OpenEditor()
    elseif msg == "restore" then A:RestoreAll()
    elseif msg == "enable" then A:Resume()
    elseif msg == "report" then A:Diagnostics()
    elseif msg == "keybind" or msg == "kb" then A:StartQuickKeybind()
    elseif msg == "options" or msg == "config" then A:OpenOptions()
    elseif msg == "timeline" or msg == "timeline test" or msg == "test" then A:TestTimeline()
    elseif msg == "timeline details" or msg == "details" then A:TimelineDetails()
    elseif msg == "timeline boss" then A:ConfirmBossTarget(true)
    elseif msg == "timeline notboss" then A:ConfirmBossTarget(false)
    elseif msg == "timeline reset" then
        A:Confirm("Forget Learned Timings", "Forget every boss ability timing learned from your fights (all bosses, all characters on this account)? Boss decisions and your layouts are kept.", {
            { text = "Forget", func = function() A:ForgetLearnedTimings(); A:Print("Learned boss timings cleared.") end }, { text = "Cancel" } })
    elseif msg == "status" then
        A:Print((A.active and "Active" or "Suspended") .. "; layout " .. A.char.active.name .. (A.dirty and " (unsaved)" or "") .. ".")
    elseif msg == "resetwindows" then
        A.db.editor.managerPos, A.db.editor.settingsPos = nil, nil
        A:Print("Edit Mode window positions reset (applies next time they are built; /reload).")
    else
        A:Print("/br - Edit Mode | /br keybind - Quick Keybind | /br options - settings | /br timeline test - practice Boss Timeline | /br timeline details - what was learned | /br timeline boss - treat target as a boss | /br timeline reset - forget learned timings | /br restore - original UI | /br enable | /br report")
    end
end
