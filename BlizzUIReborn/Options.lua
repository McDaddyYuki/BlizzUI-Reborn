-- Interface > AddOns > BlizzUI Reborn
local A = BlizzUIReborn
local C = A.Colors
function A:BuildOptions()
    local parent = _G.InterfaceOptionsFramePanelContainer or UIParent
    local p = CreateFrame("Frame", "BlizzUIRebornOptions", parent)
    p.name = "BlizzUI Reborn"
    p:Hide()
    local title = A.Text(p, 16, C.gold); title:SetPoint("TOPLEFT", p, "TOPLEFT", 16, -16); title:SetText("BlizzUI Reborn " .. A.version)
    local sub = A.Text(p, 12, C.text); sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6); sub:SetWidth(560); sub:SetJustifyH("LEFT")
    sub:SetText("Retail-style HUD Edit Mode. Positions, sizes and layouts are set in Edit Mode (Escape > Edit Mode, or /br).")
    p.edit = A.Button(p, "Open Edit Mode", 180, function()
        if InterfaceOptionsFrame then HideUIPanel(InterfaceOptionsFrame) end
        if GameMenuFrame and GameMenuFrame:IsShown() then HideUIPanel(GameMenuFrame) end
        A:OpenEditor()
    end)
    p.edit:SetPoint("TOPLEFT", p, "TOPLEFT", 16, -70)
    p.keys = A.Button(p, "Quick Keybind Mode", 180, function()
        if InterfaceOptionsFrame then HideUIPanel(InterfaceOptionsFrame) end
        A:StartQuickKeybind()
    end)
    p.keys:SetPoint("LEFT", p.edit, "RIGHT", 10, 0)
    local y = -110
    local function toggle(label, desc, get, set)
        local c = A.Check(p, label, function(v) set(v) end, 320)
        c:SetPoint("TOPLEFT", p, "TOPLEFT", 16, y)
        local d = A.Text(p, 11, C.dim); d:SetPoint("TOPLEFT", p, "TOPLEFT", 44, y - 22); d:SetWidth(540); d:SetJustifyH("LEFT"); d:SetText(desc)
        c.get = get
        p.toggles = p.toggles or {}
        table.insert(p.toggles, c)
        y = y - 40
    end
    toggle("Collect all addon minimap buttons into the Addon Compartment",
        "Stray minimap buttons from other addons (and from Carbonite's dock) are gathered into the compartment.",
        function() return A.db.collectButtons ~= false end,
        function(v) A.db.collectButtons = v; A:RefreshCompartment() end)
    toggle("Show backpack currencies under Bagnon's bags",
        "Blizzard only shows 'Show on Backpack' currencies on its own backpack; this adds them under Bagnon's inventory window.",
        function() return A.db.bagnonCurrency ~= false end,
        function(v) A.db.bagnonCurrency = v; A:UpdateCurrencyStrip() end)
    -- Boss Timeline (Retail's Options > Boss Warnings settings)
    y = y - 4
    local head = A.Text(p, 14, C.gold); head:SetPoint("TOPLEFT", p, "TOPLEFT", 16, y); head:SetText("Boss Timeline")
    local note = A.Text(p, 11, C.dim); note:SetPoint("TOPLEFT", p, "TOPLEFT", 130, y - 2); note:SetWidth(460); note:SetJustifyH("LEFT")
    note:SetText("Position, size, view and visibility are in Edit Mode (Boss Timeline, Boss Warnings).")
    y = y - 24
    local function tl(key) return function() return A:TimelineDB()[key] and true or false end, function(v) A:TimelineDB()[key] = v and true or false; A:RefreshTimeline() end end
    local get, set = tl("useBossMods")
    toggle("Use Deadly Boss Mods / BigWigs timers when installed", "Optional. Their live timers follow phases; learned predictions fill in for everything else. Nothing of theirs is stored.", get, set)
    toggle("Prefer BigWigs when both time the same ability", "Off: Deadly Boss Mods' timer is shown. Either way only one entry per cast.",
        function() return A:TimelineDB().provider == "bigwigs" end,
        function(v) A:TimelineDB().provider = v and "bigwigs" or "dbm"; A:RefreshTimeline() end)
    get, set = tl("learn")
    toggle("Learn boss ability timings from your fights", "Only casts actually seen are used. Kept for all characters of this account on this computer (not synced).", get, set)
    get, set = tl("predictions")
    toggle("Show predicted abilities", "Off: only boss mod timers and casts actually in progress (useful for custom fights).", get, set)
    get, set = tl("learnHidden")
    toggle("Keep learning while both displays are hidden", "Otherwise nothing is watched or collected while Boss Timeline and Boss Warnings are both off.", get, set)
    get, set = tl("allAbilities")
    toggle("Show every boss ability", "Off: only real mechanics (timed by a boss mod, big hits, hits on 3+ players, adds, health triggers) and boss casts that aren't filler. On: everything.", get, set)
    get, set = tl("hideLong")
    toggle("Hide Long Countdowns", "Only show abilities coming within the next 12 seconds.", get, set)
    get, set = tl("hideQueued")
    toggle("Hide Queued Countdowns", "Don't list abilities further than 40 seconds away at the end of the timeline.", get, set)
    p.test = A.Button(p, "Practice Fight", 150, function()
        if InterfaceOptionsFrame then HideUIPanel(InterfaceOptionsFrame) end
        A:TestTimeline()
    end)
    p.test:SetPoint("TOPLEFT", p, "TOPLEFT", 16, y)
    p.forget = A.Button(p, "Forget Learned Timings", 180, function()
        A:Confirm("Forget Learned Timings", "Forget every boss ability timing learned from your fights (all bosses, all characters on this account)? Boss decisions and your layouts are kept.", {
            { text = "Forget", func = function() A:ForgetLearnedTimings(); A:Print("Learned boss timings cleared.") end }, { text = "Cancel" } })
    end)
    p.forget:SetPoint("LEFT", p.test, "RIGHT", 10, 0)
    p.details = A.Button(p, "Encounter Details", 150, function()
        if InterfaceOptionsFrame then HideUIPanel(InterfaceOptionsFrame) end
        A:TimelineDetails()
    end)
    p.details:SetPoint("LEFT", p.forget, "RIGHT", 10, 0)
    -- which source shows an ability both a boss mod and our learning time
    local prefLabel = A.Text(p, 12, C.text); prefLabel:SetPoint("TOPLEFT", p.test, "BOTTOMLEFT", 0, -14); prefLabel:SetText("When a boss mod and learned timings disagree:")
    local PREFS = { { "auto", "Use whichever proved more accurate" }, { "bossmods", "Always use the boss mod" }, { "learned", "Prefer learned timings" } }
    p.prefer = A.Dropdown(p, 250, function()
        local items = {}
        for _, c in ipairs(PREFS) do
            items[#items + 1] = { text = c[2], checked = A:TimelineDB().prefer == c[1], func = function() A:TimelineDB().prefer = c[1]; A:RefreshTimeline(); p.prefer:Refresh() end }
        end
        return items
    end, function()
        for _, c in ipairs(PREFS) do if A:TimelineDB().prefer == c[1] then return c[2] end end
    end)
    p.prefer:SetPoint("LEFT", prefLabel, "RIGHT", 8, 0)
    p:SetScript("OnShow", function() for _, c in ipairs(p.toggles) do c:SetChecked(c.get()) end; if p.prefer then p.prefer:Refresh() end end)
    if InterfaceOptions_AddCategory then InterfaceOptions_AddCategory(p) end
    self.optionsPanel = p
end
function A:OpenOptions()
    if not self.optionsPanel then return end
    if InterfaceOptionsFrame_OpenToCategory then
        -- 3.3.5 needs two calls the first time the category list is built
        InterfaceOptionsFrame_OpenToCategory(self.optionsPanel)
        InterfaceOptionsFrame_OpenToCategory(self.optionsPanel)
    end
end
