-- Boss Timeline display and Boss Warnings, as Edit Mode elements. Modelled on
-- Retail's Blizzard_EncounterTimeline: a track with Short (0-5s), Medium
-- (5-15s) and Long (15-40s) sections plus a queue for later abilities, a
-- diamond at the 5 second highlight point, icons travelling toward the "now"
-- end; or a Bars view. Settings follow Retail's Edit Mode (ranges/defaults).
-- Stock 3.3.5 art only (minimap-button rings, cast bar textures).
local A = BlizzUIReborn
local T = A.Timeline
local S = A.Schema
local V = {}
A.TimelineView = V
local GetTime, math, ipairs, pairs = GetTime, math, ipairs, pairs

local BASE_LENGTH, BASE_CROSS, BASE_ICON = 380, 56, 40
local PAD = 18
local QUEUE_SLOTS = 3
local HIDE_LONG = 12 -- Retail "Hide Long Countdowns": only the next 12 seconds
local RING = "Interface\\Minimap\\MiniMap-TrackingBorder"
local GLOW = "Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight"
local BAR = "Interface\\TargetingFrame\\UI-StatusBar"
local SPARK = "Interface\\CastingBar\\UI-CastingBar-Spark"
local DIAMOND = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_3"
local FONT = A.Media.Font
local BAR_COLOR, CAST_COLOR = { 1, .7, 0 }, { .9, .22, .12 } -- CastingBarFrame yellow / failed red

-- ------------------------------------------------------------ elements
local timelineOnly = function(e) return e.view ~= "bars" end
local barsOnly = function(e) return e.view == "bars" end
local verticalText = function(e) return e.view ~= "bars" and e.orientation == "vertical" end
local direction = S.choice("direction", "Icon Direction", "down", { { "right", "Right" }, { "left", "Left" }, { "down", "Down" }, { "up", "Up" } })
direction.showIf = timelineOnly
direction.choicesFor = function(e)
    if e.orientation == "horizontal" then return { { value = "right", label = "Right" }, { value = "left", label = "Left" } } end
    return { { value = "down", label = "Down" }, { value = "up", label = "Up" } }
end
direction.current = function(e) return V.Direction(e) end
local function with(opt, fields) for k, v in pairs(fields) do opt[k] = v end; return opt end
A:Register({ id = "bosstimeline", label = "Boss Timeline", category = "Combat", kind = "timeline", toggle = true, basic = true,
    preview = { 56, 380 },
    settings = {
        S.choice("view", "View", "timeline", { { "timeline", "Timeline" }, { "bars", "Bars" } }),
        with(S.choice("orientation", "Orientation", "vertical", { { "horizontal", "Horizontal" }, { "vertical", "Vertical" } }), { showIf = timelineOnly }),
        direction,
        S.slider("iconSize", "Icon Size", 50, 200, 10, 100, "%"),
        S.slider("scale", "Overall Size", 50, 200, 10, 100, "%"),
        with(S.slider("padding", "Padding", 0, 20, 1, 2), { showIf = barsOnly }),
        with(S.slider("barWidth", "Bar Width", 50, 200, 5, 100, "%"), { showIf = barsOnly }),
        S.slider("background", "Background", 0, 100, 5, 0, "%"),
        S.slider("alpha", "Transparency", 50, 100, 5, 100, "%"),
        S.choice("visibility", "Visibility", "encounter", { { "always", "Always" }, { "encounter", "In Encounter" } }),
        S.choice("tooltips", "Tooltips", "cursor", { { "none", "None" }, { "hud", "HUD" }, { "cursor", "Cursor" } }),
        with(S.check("flip", "Flip Horizontally", false), { showIf = verticalText }),
        with(S.check("showName", "Show Spell Name", false), { showIf = verticalText }),
        S.check("showTimer", "Show Timer", true),
        S.check("enabled", "Enabled", nil, true),
    } })
A:Register({ id = "bosswarnings", label = "Boss Warnings", category = "Combat", kind = "bosswarn", toggle = true, basic = true,
    preview = { 420, 64 },
    settings = {
        S.slider("scale", "Size", 50, 200, 10, 100, "%"),
        S.slider("iconSize", "Icon Size", 50, 200, 10, 100, "%"),
        S.slider("alpha", "Transparency", 50, 100, 5, 100, "%"),
        S.choice("priority", "Show", "all", { { "all", "All Warnings" }, { "critical", "Critical Only" } }),
        S.check("sound", "Play Sound", true),
        S.check("enabled", "Enabled", nil, true),
    } })

-- Retail's default spots (Edit Mode preset): timeline left of the action
-- bars, warnings top centre.
A.ModernPositions.bosstimeline = { "BOTTOM", -457 - BASE_CROSS / 2, 336 }
A.ModernPositions.bosswarnings = { "TOP", 0, -185 }

local function settingsOf(id)
    local def = A.elements[id]
    if not def or not A.draft then return A:DefaultSettings(def) end
    return A:Settings(def)
end
function A:TimelineShown()
    return self.active and self.draft and settingsOf("bosstimeline").enabled ~= false or false
end
function A:WarningsShown()
    return self.active and self.draft and settingsOf("bosswarnings").enabled ~= false or false
end
-- the engine runs when either display is on (or, if the player chose so,
-- to keep learning while both are hidden; "Learn" off stops collection)
function A:TimelineEnabled()
    if self:TimelineShown() or self:WarningsShown() then return true end
    local db = self.db and self:TimelineDB()
    return self.active and db and db.learn and db.learnHidden and true or false
end

function V.Direction(e)
    local d = e.direction or "down"
    if e.orientation == "horizontal" then
        if d == "down" then return "right" elseif d == "up" then return "left" end
        return d
    end
    if d == "right" then return "down" elseif d == "left" then return "up" end
    return d
end

-- ------------------------------------------------------------ geometry
-- Distance of an event from the "now" end, along the track (0..1 of the
-- linear part), following Retail's track sections.
local BREAKS = { { 0, 0 }, { T.SHORT, .40 }, { T.MEDIUM, .72 }, { T.LONG, 1 } }
function V.TrackFraction(rem)
    if rem <= 0 then return 0 end
    for i = 2, #BREAKS do
        local a, b = BREAKS[i - 1], BREAKS[i]
        if rem <= b[1] then return a[2] + (rem - a[1]) / (b[1] - a[1]) * (b[2] - a[2]) end
    end
    return 1
end

-- ------------------------------------------------------------ building
local function fontString(parent, size, layer)
    local fs = parent:CreateFontString(nil, layer or "OVERLAY")
    fs:SetFont(FONT, size, "OUTLINE")
    fs:SetShadowOffset(0, 0)
    return fs
end
function V:Build()
    if self.root then return self.root end
    local f = CreateFrame("Frame", "BlizzUIRebornBossTimeline", UIParent)
    f:SetFrameStrata("MEDIUM")
    f:SetFrameLevel(5)
    f:SetClampedToScreen(true)
    A.Size(f, BASE_CROSS, BASE_LENGTH)
    f:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOM", -457, 336)
    f.bg = f:CreateTexture(nil, "BACKGROUND")
    f.bg:SetTexture(A.Media.Chat); f.bg:SetVertexColor(0, 0, 0); f.bg:SetAllPoints(f)
    f.shadow = f:CreateTexture(nil, "BORDER"); f.shadow:SetTexture(0, 0, 0, .55)
    f.line = f:CreateTexture(nil, "ARTWORK"); f.line:SetTexture(.74, .62, .38, .9)
    f.divider = f:CreateTexture(nil, "ARTWORK"); f.divider:SetTexture(.74, .62, .38, .9)
    f.pip = f:CreateTexture(nil, "OVERLAY"); f.pip:SetTexture(DIAMOND); f.pip:SetDesaturated(true); f.pip:SetVertexColor(1, .82, .3)
    f.pipText = fontString(f, 10); f.pipText:SetText(tostring(T.HIGHLIGHT)); f.pipText:SetTextColor(1, .82, 0)
    f.hint = fontString(f, 10); f.hint:SetTextColor(.6, .6, .6); f.hint:SetText("Learning this fight...")
    f.hint:Hide()
    f.icons, f.bars = {}, {}
    f:Hide()
    -- ~30 redraws a second is smooth for icons moving a few pixels a second
    local acc = 0
    f:SetScript("OnUpdate", function(_, elapsed)
        acc = acc + elapsed
        if acc < .033 then return end
        acc = 0
        A:Run("Boss Timeline display", V.OnUpdate, V)
    end)
    self.root = f
    return f
end
local function iconTooltip(owner)
    local ev = owner.event
    if not ev then return end
    local mode = V.settings and V.settings.tooltips or "cursor"
    if mode == "none" then return end
    if mode == "hud" then GameTooltip_SetDefaultAnchor(GameTooltip, owner) else GameTooltip:SetOwner(owner, "ANCHOR_CURSOR") end
    if ev.spellId and ev.source ~= "test" and not V.previewing then GameTooltip:SetHyperlink("spell:" .. ev.spellId) else GameTooltip:SetText(ev.name or "") end
    local rem = ev.remaining or 0
    local now = GetTime()
    if ev.threshold then
        GameTooltip:AddLine(string.format("At %d%% boss health", math.floor(ev.hp + .5)), 1, .82, 0)
        if ev.state == "eta" then
            if ev.lo and ev.hi and ev.hi - ev.lo >= 2 then GameTooltip:AddLine(string.format("About %d-%d seconds at the current damage", math.max(0, math.floor(ev.lo - now)), math.ceil(ev.hi - now)), 1, 1, 1)
            else GameTooltip:AddLine(string.format("About %d seconds at the current damage", math.ceil(rem)), 1, 1, 1) end
        elseif ev.state == "reached" then GameTooltip:AddLine("Threshold reached - waiting for the ability", 1, .82, 0)
        elseif ev.state == "waiting" then GameTooltip:AddLine("Waiting for damage", .8, .8, .8)
        else GameTooltip:AddLine("Boss health not visible: target or focus it for an estimate", .8, .8, .8) end
    elseif ev.state == "cast" then GameTooltip:AddLine((ev.caster and (ev.caster .. ": ") or "") .. "casting now", 1, .3, .3)
    elseif ev.state == "soon" then GameTooltip:AddLine("Expected any moment (not confirmed)", 1, .82, 0)
    elseif ev.lo and ev.hi and ev.hi - ev.lo >= 2 then
        GameTooltip:AddLine(string.format("Expected in %d-%d seconds", math.max(0, math.floor(ev.lo - now)), math.ceil(ev.hi - now)), 1, 1, 1)
    else GameTooltip:AddLine(string.format("In %s%.0f seconds", ev.estimate and ev.source ~= "dbm" and ev.source ~= "bigwigs" and "about " or "", rem), 1, 1, 1) end
    local src = ({ dbm = "Deadly Boss Mods timer", bigwigs = "BigWigs timer" })[ev.source]
    if not src and ev.source == "cast" then src = ev.estimate and "Live cast (time estimated from the combat log)" or "Live cast (cast bar)" end
    if not src and ev.source == "predict" then
        local rec = ev.ability and ev.ability.rec
        src = ({ practice = "Practice fight", provisional = "Learning: estimated from this pull",
            revalidating = "Learned timing, being re-checked after changes", manual = "Your manual setting",
            learned = "Learned on this server" .. ((rec and rec.acc and rec.acc.n) and string.format(" (%d intervals)", rec.acc.n) or "") })[ev.prov]
    end
    if src then GameTooltip:AddLine(src, .6, .6, .6) end
    if ev.danger then GameTooltip:AddLine("Dangerous", 1, .3, .3) end
    if ev.source ~= "test" and A.TimelineAbilityMenu then GameTooltip:AddLine("Right-click for options", .5, .5, .5) end
    GameTooltip:Show()
end
function V:Icon(i)
    local f = self.root
    local b = f.icons[i]
    if b then return b end
    b = CreateFrame("Button", nil, f)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.ring = b:CreateTexture(nil, "OVERLAY"); b.ring:SetTexture(RING)
    b.glow = b:CreateTexture(nil, "OVERLAY"); b.glow:SetTexture(GLOW); b.glow:SetBlendMode("ADD"); b.glow:Hide()
    b.timer = fontString(b, 12)
    b.name = fontString(b, 11); b.name:SetTextColor(1, .82, 0)
    b:RegisterForClicks("RightButtonUp")
    b:SetScript("OnClick", function(self) if self.event and A.TimelineAbilityMenu then A:TimelineAbilityMenu(self.event, self) end end)
    b:SetScript("OnEnter", iconTooltip)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    f.icons[i] = b
    return b
end
function V:Bar(i)
    local f = self.root
    local b = f.bars[i]
    if b then return b end
    b = CreateFrame("Button", nil, f)
    b.icon = b:CreateTexture(nil, "ARTWORK"); b.icon:SetTexCoord(.08, .92, .08, .92)
    b.bg = b:CreateTexture(nil, "BACKGROUND"); b.bg:SetTexture(0, 0, 0, .55)
    b.bar = CreateFrame("StatusBar", nil, b); b.bar:SetStatusBarTexture(BAR); b.bar:SetMinMaxValues(0, 1)
    b.spark = b.bar:CreateTexture(nil, "OVERLAY"); b.spark:SetTexture(SPARK); b.spark:SetBlendMode("ADD")
    b.name = fontString(b.bar, 11); b.name:SetJustifyH("LEFT"); b.name:SetTextColor(1, 1, 1)
    b.timer = fontString(b.bar, 11); b.timer:SetJustifyH("RIGHT"); b.timer:SetTextColor(1, 1, 1)
    b:RegisterForClicks("RightButtonUp")
    b:SetScript("OnClick", function(self) if self.event and A.TimelineAbilityMenu then A:TimelineAbilityMenu(self.event, self) end end)
    b:SetScript("OnEnter", iconTooltip)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    f.bars[i] = b
    return b
end

-- ------------------------------------------------------------ settings -> layout
function V:Apply(e)
    local f = self:Build()
    self.settings = e
    local k = (e.iconSize or 100) / 100
    self.iconPx = BASE_ICON * k
    f:SetScale((e.scale or 100) / 100)
    f:SetAlpha((e.alpha or 100) / 100)
    f.bg:SetAlpha((e.background or 0) / 100)
    if e.view == "bars" then
        local h = 22 * k
        self.barH, self.barW = h, 200 * (e.barWidth or 100) / 100
        self.maxBars = 6
        A.Size(f, self.barW + h + 2, self.maxBars * (h + (e.padding or 2)) - (e.padding or 2))
        for _, t in ipairs({ f.shadow, f.line, f.divider, f.pip, f.pipText }) do t:Hide() end
    else
        local cross = math.max(BASE_CROSS, self.iconPx + 16)
        self.vertical = e.orientation ~= "horizontal"
        self.dir = V.Direction(e)
        self.cross = cross
        self.length = BASE_LENGTH
        if self.vertical then A.Size(f, cross, BASE_LENGTH) else A.Size(f, BASE_LENGTH, cross) end
        self:LayoutTrack()
    end
    for _, b in ipairs(f.icons) do b:Hide() end
    for _, b in ipairs(f.bars) do b:Hide() end
    self:SizeWidgets()
    self.dirty = true
end
-- point on the track at distance `s` from the now end, cross offset `c`
function V:Point(s, c)
    local L, C = self.length, self.cross
    local d = self.dir
    c = c or 0
    if d == "right" then return L - PAD - s, C / 2 + c
    elseif d == "left" then return PAD + s, C / 2 + c
    elseif d == "up" then return C / 2 + c, L - PAD - s
    else return C / 2 + c, PAD + s end
end
function V:Linear()
    local q = (A:TimelineDB().hideQueued) and 0 or (QUEUE_SLOTS * (self.iconPx * .8 + 4) + 12)
    return self.length - 2 * PAD - q, q
end
function V:LayoutTrack()
    local f = self.root
    local lin, q = self:Linear()
    local x1, y1 = self:Point(0)
    local x2, y2 = self:Point(lin + q)
    local thick = 2
    f.line:ClearAllPoints(); f.shadow:ClearAllPoints()
    if self.vertical then
        f.line:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", x1 - thick / 2, math.min(y1, y2))
        A.Size(f.line, thick, math.abs(y2 - y1))
        f.shadow:SetPoint("CENTER", f.line, "CENTER", 1, 0); A.Size(f.shadow, thick + 4, math.abs(y2 - y1) + 4)
    else
        f.line:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", math.min(x1, x2), y1 - thick / 2)
        A.Size(f.line, math.abs(x2 - x1), thick)
        f.shadow:SetPoint("CENTER", f.line, "CENTER", 0, -1); A.Size(f.shadow, math.abs(x2 - x1) + 4, thick + 4)
    end
    -- the 5 second diamond + label (Retail "pip")
    local px, py = self:Point(V.TrackFraction(T.HIGHLIGHT) * lin)
    A.Size(f.pip, 12, 12)
    f.pip:ClearAllPoints(); f.pip:SetPoint("CENTER", f, "BOTTOMLEFT", px, py)
    f.pipText:ClearAllPoints()
    if self.vertical then f.pipText:SetPoint("LEFT", f.pip, "RIGHT", 2, 0) else f.pipText:SetPoint("TOP", f.pip, "BOTTOM", 0, -2) end
    -- divider before the queue
    f.divider:ClearAllPoints()
    if q > 0 then
        local dx, dy = self:Point(lin + 6)
        if self.vertical then A.Size(f.divider, 14, 2) else A.Size(f.divider, 2, 14) end
        f.divider:SetPoint("CENTER", f, "BOTTOMLEFT", dx, dy)
        f.divider:Show()
    else
        f.divider:Hide()
    end
    f.hint:ClearAllPoints()
    local hx, hy = self:Point(lin * .5)
    f.hint:SetPoint("CENTER", f, "BOTTOMLEFT", hx, hy + (self.vertical and 0 or 16))
    for _, t in ipairs({ f.shadow, f.line, f.pip, f.pipText }) do t:Show() end
end
function V:SizeWidgets()
    local k = self.iconPx / 32 -- minimap-button geometry: 32px button, 20px icon, 54px ring
    for _, b in ipairs(self.root.icons) do self:SizeIcon(b, k) end
    for _, b in ipairs(self.root.bars) do self:SizeBar(b) end
end
function V:SizeIcon(b, k)
    k = k or self.iconPx / 32
    A.Size(b, 32 * k, 32 * k)
    -- same arrangement as the minimap tracking button: 20px icon centred in a
    -- 32px button, the 54px ring texture anchored at its top-left
    b.icon:ClearAllPoints(); A.Size(b.icon, 20 * k, 20 * k); b.icon:SetPoint("CENTER", b, "CENTER", 0, 0)
    b.ring:ClearAllPoints(); A.Size(b.ring, 54 * k, 54 * k); b.ring:SetPoint("TOPLEFT", b, "TOPLEFT", 0, 0)
    b.glow:ClearAllPoints(); A.Size(b.glow, 32 * k, 32 * k); b.glow:SetPoint("CENTER", b, "CENTER", 0, 0)
    b.timer:SetFont(FONT, math.max(9, 12 * k), "OUTLINE")
    b.timer:ClearAllPoints(); b.timer:SetPoint("CENTER", b, "CENTER", 0, 0)
    local e = self.settings or {}
    b.name:ClearAllPoints()
    if e.flip then b.name:SetPoint("RIGHT", b, "LEFT", -2, 0); b.name:SetJustifyH("RIGHT")
    else b.name:SetPoint("LEFT", b, "RIGHT", 2, 0); b.name:SetJustifyH("LEFT") end
    b.sized = self.iconPx
end
function V:SizeBar(b)
    local h, w = self.barH or 22, self.barW or 200
    A.Size(b, w + h + 2, h)
    b.icon:ClearAllPoints(); A.Size(b.icon, h, h); b.icon:SetPoint("LEFT", b, "LEFT", 0, 0)
    b.bar:ClearAllPoints(); b.bar:SetPoint("TOPLEFT", b, "TOPLEFT", h + 2, 0); b.bar:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 0, 0)
    b.bg:ClearAllPoints(); b.bg:SetAllPoints(b.bar)
    A.Size(b.spark, 16, h * 2)
    b.name:ClearAllPoints(); b.name:SetPoint("LEFT", b.bar, "LEFT", 4, 0); b.name:SetPoint("RIGHT", b.bar, "RIGHT", -40, 0)
    b.timer:ClearAllPoints(); b.timer:SetPoint("RIGHT", b.bar, "RIGHT", -4, 0)
    b.sized = h .. ":" .. w
end

-- ------------------------------------------------------------ drawing
-- Countdown text. "~" marks an estimate (learned, combat-log cast
-- time, HP projection); boss mod timers and cast bars are shown as they are.
local function timerText(ev)
    local rem, state = ev.remaining or 0, ev.state
    if ev.threshold then
        if state == "eta" then return string.format("~%d", math.ceil(rem - .05)) end
        if state == "reached" then return "!" end
        return string.format("%d%%", math.floor(ev.hp + .5))
    end
    if state == "soon" then return "" end
    local t = rem >= 3 and string.format("%d", math.ceil(rem - .05)) or string.format("%.1f", rem)
    if ev.estimate and (ev.source == "predict" or ev.source == "cast") and rem >= 3 then t = "~" .. t end
    return t
end
V.TimerText = timerText
local PROV = { practice = "practice", learned = "learned", provisional = "learning", revalidating = "re-checking", manual = "manual",
    dbm = "DBM", bigwigs = "BigWigs", live = "live" }
function V.SourceTag(ev)
    if ev.source == "test" then return nil end
    if ev.threshold then return "HP" end
    return PROV[ev.prov or ev.source]
end
local PREVIEW = {
    { "Cleave", "Interface\\Icons\\Ability_Warrior_Cleave", 11, 2 },
    { "Shadow Bolt Volley", "Interface\\Icons\\Spell_Shadow_ShadowBolt", 20, 9 },
    { "Frost Nova", "Interface\\Icons\\Spell_Frost_FrostNova", 32, 5 },
    { "Summon Adds", "Interface\\Icons\\Spell_Shadow_RaiseDead", 47, 30 },
    { "Enrage", "Interface\\Icons\\Spell_Shadow_UnholyFrenzy", 90, 20 },
}
function V:PreviewList()
    local t = GetTime()
    local out = {}
    for i, p in ipairs(PREVIEW) do
        local rem = p[3] - ((t + p[4]) % p[3])
        out[#out + 1] = { key = "preview" .. i, name = p[1], icon = p[2], remaining = rem, expires = t + rem, total = p[3], state = "timer", source = "test" }
    end
    table.sort(out, function(a, b) return a.remaining < b.remaining end)
    return out
end
function V:List()
    if T:Active() then self.previewing = false; return T:DisplayList() end
    if A.editing then self.previewing = true; return self:PreviewList() end
    self.previewing = false
    return {}
end
local function filter(list)
    local db = A:TimelineDB()
    if not db.hideLong then return list end
    local out = {}
    for _, ev in ipairs(list) do if ev.remaining <= HIDE_LONG or ev.state ~= "timer" then out[#out + 1] = ev end end
    return out
end
function V:DrawTimeline(list)
    local f, e = self.root, self.settings
    local lin, q = self:Linear()
    local k = self.iconPx / 32
    local used, lastS = 0, {}
    local queued = 0
    local now = GetTime()
    local showNames = e.showName and self.vertical
    for _, ev in ipairs(list) do
        if used >= 8 then break end -- the 8 soonest; more would only clutter
        local s, alpha
        if ev.remaining > T.LONG then
            if q > 0 and queued < QUEUE_SLOTS then
                queued = queued + 1
                s = lin + 12 + (queued - .5) * (self.iconPx * .8 + 4)
            end
            alpha = 1
        else
            s = V.TrackFraction(ev.remaining) * lin
            alpha = ev.remaining > T.MEDIUM and .6 or 1 -- Retail: Long track at 60%
        end
        if s and showNames then
            -- with names beside the icons, keep them apart along the track so
            -- the names stay readable (the countdown gives the exact time)
            if lastS[0] and s - lastS[0] < self.iconPx * .8 then s = lastS[0] + self.iconPx * .8 end
            if s > lin + q then s = nil else lastS[0] = s end -- no room left: counted in "+N"
        end
        if s then
            used = used + 1
            local b = self:Icon(used)
            if b.sized ~= self.iconPx then self:SizeIcon(b, k) end
            b.event = ev
            local offset = 0
            if showNames then
                -- (spaced out above)
            else
                -- stagger icons that would overlap (Retail bumps by severity)
                local lane = 0
                for l = 0, 2 do
                    local prev = lastS[l]
                    if not prev or math.abs(prev - s) >= self.iconPx * .75 then lane = l; break end
                    lane = l
                end
                lastS[lane] = s
                offset = (lane == 1 and 1 or lane == 2 and -1 or 0) * self.iconPx * .45
            end
            local x, y = self:Point(s, offset)
            b:ClearAllPoints(); b:SetPoint("CENTER", f, "BOTTOMLEFT", x, y)
            if b.tex ~= ev.icon then
                b.tex = ev.icon
                if SetPortraitToTexture then SetPortraitToTexture(b.icon, ev.icon) else b.icon:SetTexture(ev.icon) end
            end
            local imminent = ev.state ~= "timer" or ev.remaining <= T.HIGHLIGHT
            local pulse = (ev.state == "soon" or ev.state == "cast") and (.65 + .35 * math.abs(math.sin(now * 5))) or 1
            b:SetAlpha(alpha * pulse)
            -- dangerous mechanics (one-shots, DBM special warnings): red ring
            if ev.danger then b.ring:SetVertexColor(1, .3, .25) else b.ring:SetVertexColor(1, 1, 1) end
            A.Visible(b.glow, imminent)
            if ev.state == "cast" then b.glow:SetVertexColor(1, .35, .25) else b.glow:SetVertexColor(1, .85, .4) end
            if e.showTimer ~= false then
                b.timer:SetText(timerText(ev))
                if ev.state == "cast" then b.timer:SetTextColor(1, .35, .3) elseif imminent then b.timer:SetTextColor(1, .82, 0) else b.timer:SetTextColor(1, 1, 1) end
                b.timer:Show()
            else
                b.timer:Hide()
            end
            if showNames then
                b.name:SetText(ev.state == "cast" and ((ev.name or "") .. " (casting)") or ev.name or "")
                if ev.state == "cast" then b.name:SetTextColor(1, .35, .3) else b.name:SetTextColor(1, .82, 0) end
                b.name:Show()
            else
                b.name:Hide()
            end
            b:EnableMouse(e.tooltips ~= "none")
            b:Show()
        end
    end
    for i = used + 1, #f.icons do f.icons[i]:Hide(); f.icons[i].event = nil end
    self:Hint(used == 0 and T:Active() and not self.previewing)
    -- abilities beyond the 8 drawn (or the full queue)
    local listed = 0
    for _, ev in ipairs(list) do if ev.remaining <= T.LONG or q > 0 then listed = listed + 1 end end
    local ox, oy = self:Point(lin + q + 4)
    self:Overflow(listed - used, ox - 6, oy)
end
function V:DrawBars(list)
    local f, e = self.root, self.settings
    local used = 0
    local pad = e.padding or 2
    for _, ev in ipairs(list) do
        if used >= self.maxBars then break end
        used = used + 1
        local b = self:Bar(used)
        if b.sized ~= self.barH .. ":" .. self.barW then self:SizeBar(b) end
        b.event = ev
        b:ClearAllPoints()
        b:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 0, (used - 1) * (self.barH + pad))
        b.icon:SetTexture(ev.icon)
        local c = ev.state == "cast" and CAST_COLOR or BAR_COLOR
        b.bar:SetStatusBarColor(c[1], c[2], c[3])
        local frac = ev.state == "soon" and 0 or math.min(1, ev.remaining / math.max(ev.total or ev.remaining, .1))
        if ev.threshold and ev.state ~= "eta" then frac = ev.state == "reached" and 0 or 1 end
        b.bar:SetValue(frac)
        b.spark:ClearAllPoints(); b.spark:SetPoint("CENTER", b.bar, "LEFT", frac * self.barW, 0)
        A.Visible(b.spark, frac > 0 and frac < 1)
        local tag = V.SourceTag(ev)
        local label = ev.state == "cast" and ((ev.name or "") .. " (casting)") or ev.name or ""
        if ev.threshold then label = label .. string.format(" \194\183 %d%% HP", math.floor(ev.hp + .5)) end
        b.name:SetText(label .. (tag and ("  |cff999999" .. tag .. "|r") or ""))
        local tt = ev.state == "soon" and "Soon" or timerText(ev)
        if ev.threshold and ev.state == "eta" and ev.lo and ev.hi and ev.hi - ev.lo >= 2 then
            local now = GetTime()
            tt = string.format("%d-%ds", math.max(0, math.floor(ev.lo - now)), math.ceil(ev.hi - now))
        elseif ev.threshold and ev.state == "waiting" then tt = "waiting"
        elseif ev.threshold and ev.state == "reached" then tt = "any time" end
        if e.showTimer ~= false then b.timer:SetText(tt); b.timer:Show() else b.timer:Hide() end
        b:SetAlpha((ev.state == "soon") and (.65 + .35 * math.abs(math.sin(GetTime() * 5))) or 1)
        b:EnableMouse(e.tooltips ~= "none")
        b:Show()
    end
    for i = used + 1, #f.bars do f.bars[i]:Hide(); f.bars[i].event = nil end
    self:Hint(used == 0 and T:Active() and not self.previewing)
    self:Overflow(#list - used, 0, used * (self.barH + pad) + 2)
end
-- Nothing to show during a tracked fight: "Learning" (nothing is known about
-- this boss yet, so nothing is invented) or "No mechanics expected".
function V:Hint(on)
    local f = self.root
    if not on then f.hint:Hide(); return end
    local E = T:Encounter()
    local name = E and E.name
    if T:HasKnowledge() then f.hint:SetText("No mechanics expected yet")
    else f.hint:SetText("Learning" .. (name and (": " .. name) or "") .. "...") end
    f.hint:Show()
end
-- "+N more" when not everything fits
function V:Overflow(n, x, y)
    local f = self.root
    if not f.more then f.more = fontString(f, 11); f.more:SetTextColor(.8, .8, .8) end
    if n <= 0 then f.more:Hide(); return end
    f.more:SetText("+" .. n)
    f.more:ClearAllPoints()
    f.more:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", x, y)
    f.more:Show()
end
function V:OnUpdate()
    if not self.settings then return end
    local list = filter(self:List())
    if self.settings.view == "bars" then self:DrawBars(list) else self:DrawTimeline(list) end
end

-- Shown while a boss fight is tracked, in Edit Mode (preview), or always.
function V:Refresh()
    local f = self.root
    if not f then return end
    local shown = A:TimelineShown()
    T:Enable(A:TimelineEnabled())
    local e = self.settings or {}
    local visible = shown and (A.editing or T:Active() or e.visibility == "always")
    if visible then
        if not f:IsShown() then f:Show() end
        self:OnUpdate()
    else
        f:Hide()
        if GameTooltip:GetOwner() and GameTooltip:GetOwner():GetParent() == f then GameTooltip:Hide() end
    end
end

A.Kinds.timeline = {
    bind = function(self, def)
        local f = V:Build()
        def.native = A.Snapshot(f)
        def.nativeRect = A.UnionRect({ f })
        V:Apply(self:DefaultSettings(def))
        return f
    end,
    apply = function(self, def, e)
        V:Apply(e)
        self:PlaceClamped(def.frame, e.point, e.x, e.y)
        V:Refresh()
    end,
    restore = function(self, def)
        V:Apply(self:DefaultSettings(def))
        A.RestoreGeometry(def.frame, def.native)
        V:Refresh()
    end,
    rect = function(self, def) return A.Rect(def.frame) end,
}

-- ------------------------------------------------------------ warnings
local W = {}
V.warnings = W
function W:Build()
    if self.root then return self.root end
    local f = CreateFrame("Frame", "BlizzUIRebornBossWarnings", UIParent)
    f:SetFrameStrata("HIGH")
    f:SetClampedToScreen(true)
    A.Size(f, 420, 64)
    f:SetPoint("TOP", UIParent, "TOP", 0, -185)
    f.lines = {}
    for i, sev in ipairs({ "critical", "medium" }) do
        local l = CreateFrame("Frame", nil, f)
        A.Size(l, 420, 30)
        l:SetPoint("TOP", f, "TOP", 0, -(i - 1) * 32)
        l.icon = l:CreateTexture(nil, "ARTWORK"); l.icon:SetTexCoord(.08, .92, .08, .92)
        l.text = fontString(l, sev == "critical" and 20 or 16)
        if sev == "critical" then l.text:SetTextColor(1, .28, .24) else l.text:SetTextColor(1, .82, 0) end
        l.text:SetPoint("CENTER", l, "CENTER", 14, 0)
        l.icon:SetPoint("RIGHT", l.text, "LEFT", -6, 0)
        l:Hide()
        f.lines[sev] = l
    end
    f:SetScript("OnUpdate", function(_, elapsed) W:OnUpdate(elapsed) end)
    f:Hide()
    self.root = f
    return f
end
function W:Apply(e)
    local f = self:Build()
    self.settings = e
    f:SetScale((e.scale or 100) / 100)
    f:SetAlpha((e.alpha or 100) / 100)
    local s = 24 * (e.iconSize or 100) / 100
    for _, l in pairs(f.lines) do A.Size(l.icon, s, s) end
end
local function warnText(sev, name, caster, expires, hp)
    if sev == "critical" then return caster and (caster .. ": " .. name) or name end
    local rem = expires and (expires - GetTime()) or 0
    if hp then return string.format("%s at %d%% HP (~%ds)", name, math.floor(hp + .5), math.max(0, math.ceil(rem - .05))) end
    if rem > .5 then return string.format("%s in %d", name, math.ceil(rem - .05)) end
    return name .. " soon" -- a prediction reaching zero is not a confirmed cast
end
-- Retail text warnings: medium = an ability is about to happen, critical =
-- a boss is casting it now.
W.recent = {}
function A:TimelineWarn(sev, name, icon, caster, expires, hp)
    if not self:WarningsShown() or not name then return end
    local e = W.settings or {}
    if e.priority == "critical" and sev ~= "critical" then return end
    -- the same ability at most once every 6 seconds (multi-target casts, spam)
    local now = GetTime()
    local k = sev .. name
    if W.recent[k] and now - W.recent[k] < 6 then return end
    W.recent[k] = now
    local f = W:Build()
    local l = f.lines[sev]
    l.name, l.caster, l.expires, l.hp = name, caster, expires, hp
    l.until_ = (sev == "medium" and expires and math.max(expires, GetTime()) + .8) or GetTime() + 3
    l.icon:SetTexture(icon or "Interface\\Icons\\INV_Misc_QuestionMark")
    l.text:SetText(warnText(sev, name, caster, expires, hp))
    l:SetAlpha(1)
    l:Show()
    f:Show()
    if e.sound ~= false and sev == "critical" and (not W.lastSound or GetTime() - W.lastSound > 1.5) then
        W.lastSound = GetTime()
        PlaySound("RaidWarning")
    end
end
function W:OnUpdate()
    local f = self.root
    local now = GetTime()
    local any = false
    for sev, l in pairs(f.lines) do
        if l:IsShown() and not l.preview then
            local left = l.until_ - now
            if left <= 0 then l:Hide()
            else
                if sev == "medium" then l.text:SetText(warnText(sev, l.name, nil, l.expires, l.hp)) end
                l:SetAlpha(math.min(1, left / .5))
                any = true
            end
        elseif l:IsShown() then
            any = true
        end
    end
    if not any and not A.editing then f:Hide() end
end
function W:Refresh()
    local f = self.root
    if not f then return end
    local shown = A:WarningsShown()
    T:Enable(A:TimelineEnabled())
    for _, l in pairs(f.lines) do
        if l.preview then l.preview = nil; l:Hide() end
    end
    if not shown then f:Hide(); return end
    if A.editing then
        -- Edit Mode sample
        local c, m = f.lines.critical, f.lines.medium
        c.icon:SetTexture("Interface\\Icons\\Spell_Shadow_ShadowBolt"); c.text:SetText("Boss: Shadow Bolt Volley"); c.preview = true; c:SetAlpha(1); c:Show()
        m.icon:SetTexture("Interface\\Icons\\Spell_Frost_FrostNova"); m.text:SetText("Frost Nova in 5"); m.preview = true; m:SetAlpha(1); m:Show()
        f:Show()
    end
end
A.Kinds.bosswarn = {
    bind = function(self, def)
        local f = W:Build()
        def.native = A.Snapshot(f)
        def.nativeRect = A.UnionRect({ f })
        W:Apply(self:DefaultSettings(def))
        return f
    end,
    apply = function(self, def, e)
        W:Apply(e)
        self:PlaceClamped(def.frame, e.point, e.x, e.y)
        W:Refresh()
    end,
    restore = function(self, def)
        W:Apply(self:DefaultSettings(def))
        A.RestoreGeometry(def.frame, def.native)
        W:Refresh()
    end,
    rect = function(self, def) return A.Rect(def.frame) end,
}

-- ------------------------------------------------------------ glue
function A:RefreshTimeline()
    T:Changed()
    if V.settings then V:Apply(V.settings) end -- options such as Hide Queued change the track
    V:Refresh()
    W:Refresh()
end
function A:OnTimelineChanged(what)
    V:Refresh()
    if what == "end" then
        for _, l in pairs((W.root and W.root.lines) or {}) do if not l.preview then l:Hide() end end
    end
end
function A:TimelineEditModeChanged()
    self:RefreshTimeline()
end

-- A 40 second practice fight through the real engine (/br timeline test).
function A:TestTimeline()
    if not self:TimelineEnabled() then self:Print("Turn on Boss Timeline or Boss Warnings in Edit Mode first."); return end
    if T:Active() and T:Encounter().source ~= "test" then self:Print("A boss fight is in progress."); return end
    if T:Active() then T:EndEncounter("test") end
    T:Enable(true)
    local E = T:StartEncounter(nil, nil, "Practice Boss", GetTime(), "test")
    local spells = {
        { "Cleave", "Interface\\Icons\\Ability_Warrior_Cleave", 4, 9 },
        { "Shadow Bolt Volley", "Interface\\Icons\\Spell_Shadow_ShadowBolt", 8, 14, 2 },
        { "Frost Nova", "Interface\\Icons\\Spell_Frost_FrostNova", 17, 22 },
        { "Summon Adds", "Interface\\Icons\\Spell_Shadow_RaiseDead", 30, 45 },
    }
    for i, sp in ipairs(spells) do
        local ab = { key = "test" .. i, name = sp[1], spellName = sp[1], icon = sp[2], first = sp[3], cd = sp[4], practice = true, opened = true }
        T:AddAbility(ab)
        T:Schedule(ab, E.start + sp[3], "practice")
    end
    T:AddAbility({ key = "enrage", name = "Enrage", icon = "Interface\\Icons\\Spell_Shadow_UnholyFrenzy", first = 60, practice = true, enrage = true, opened = true })
    T:Schedule(E.abilities.enrage, E.start + 60, "practice")
    -- make the practice boss "cast" on time
    local function castLoop(sp, at)
        if at > 40 then return end
        self:After(at - (GetTime() - E.start), function()
            if T:Encounter() ~= E then return end
            if sp[5] then T:CastStarted("cast:test", sp[1], sp[2], nil, GetTime() + sp[5], sp[5], "Practice Boss") end
            self:After(sp[5] or 0, function()
                if T:Encounter() ~= E then return end
                T:CastStopped("cast:test")
                T:OnCast(sp[5] and "S" or "C", nil, sp[1], nil, nil)
                castLoop(sp, at + sp[4])
            end)
        end)
    end
    for _, sp in ipairs(spells) do castLoop(sp, sp[3] - (sp[5] or 0)) end
    self:After(40, function() if T:Encounter() == E then T:EndEncounter("test") end end)
    V:Refresh()
    self:Print("Practice fight started (40 seconds).")
end
