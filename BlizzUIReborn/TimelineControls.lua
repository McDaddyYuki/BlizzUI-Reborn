-- Boss Timeline controls: right-click menu on an ability, the Encounter
-- Details window (what was learned, with per-ability controls), and sharing
-- boss knowledge as a data-only string.
local A = BlizzUIReborn
local T, K = A.Timeline, A.TimelineKB
local C = A.Colors

-- The knowledge record behind an entry: ability -> (context, creature, spell).
-- Abilities known only from a boss mod timer have no record until the boss
-- is seen casting them (settings that need one are then greyed out).
local function target(ev)
    local E = T:Encounter()
    local ab = ev.ability
    if not ab and E then
        for _, x in ipairs((E.byKey or {})[ev.pkey or T.IdKey(ev.spellId, ev.name)] or {}) do ab = x end
    end
    local npc = ab and (ab.recNpc or (ab.casters and ab.casters[1]))
    if not npc and E then for n in pairs(E.npcs) do npc = n end end
    local ctx = E and E.ctx or K:Context()
    local rec = ab and ab.recNpc and ab.recId and K:Rec(ctx, ab.recNpc, ab.recId, true) or nil
    if rec and ab then rec.n = rec.n or ab.spellName or ab.name; ab.rec = rec end
    return { npc = npc, rec = rec, id = ab and ab.recId, name = ab and (ab.spellName or ab.name) or ev.name, label = ev.name, ab = ab }
end
A.TimelineTarget = target

local function number(title, label, initial, min, max, apply)
    A:TextDialog({ title = title, label = label, initial = initial and tostring(initial) or "", acceptText = "Set",
        accept = function(text)
            local v = tonumber(A.Trim(text))
            if not v or v < min or v > max then return nil, string.format("Enter a number from %d to %d.", min, max) end
            apply(v)
            T:Changed()
            return true
        end })
end
-- the actions shared by the right-click menu and the details window
function A:TimelineActions(t)
    local items = { { text = t.label, header = true } }
    local b = t.npc and K:Boss(t.npc, true)
    local hidden = b and b.hide and b.hide[t.name]
    items[#items + 1] = { text = hidden and "Show This Ability" or "Hide This Ability", disabled = not b, func = function()
        b.hide = b.hide or {}
        b.hide[t.name] = (not hidden) and true or nil
        T:Changed()
    end }
    local pinned = b and b.pin and b.pin[t.name]
    items[#items + 1] = { text = "Always Show (a mechanic)", checked = pinned, disabled = not b, func = function()
        b.pin = b.pin or {}
        b.pin[t.name] = (not pinned) and true or nil
        T:Changed()
    end }
    local rec = t.rec
    items[#items + 1] = { separator = true }
    items[#items + 1] = { text = "Set Repeat Time...", disabled = not rec, func = function()
        number("Set Repeat Time", "Seconds between casts of " .. t.label .. ":", rec.override and rec.override.cd, 3, 600, function(v) K:Override(rec, "cd", v) end)
    end }
    items[#items + 1] = { text = "Set HP Threshold...", disabled = not rec, func = function()
        number("Set HP Threshold", "Boss health (%) at which " .. t.label .. " happens:", rec.override and rec.override.hp, 1, 99, function(v) K:Override(rec, "hp", v) end)
    end }
    if rec and rec.override then
        items[#items + 1] = { text = "Clear My Settings", func = function() rec.override = nil; T:Changed() end }
    end
    items[#items + 1] = { text = "Lock Learned Timing", checked = rec and rec.lock, disabled = not rec, func = function() K:Lock(rec, not rec.lock) end }
    items[#items + 1] = { text = "Use Previous Timing", disabled = not (rec and rec.prev), func = function() K:Rollback(rec); T:Changed() end }
    items[#items + 1] = { text = "Always Use Boss Mod Timing", checked = rec and rec.useProvider, disabled = not rec, func = function()
        K:UseProvider(rec, not rec.useProvider); T:Changed()
    end }
    items[#items + 1] = { text = "|cffff6060Forget This Ability|r", disabled = not (rec and t.npc and t.id), func = function()
        A:Confirm("Forget Ability", "Forget everything learned about " .. t.label .. " (all difficulties)?", {
            { text = "Forget", func = function() K:ForgetSpell(t.npc, t.id); if t.ab then t.ab.rec = nil end; T:Changed() end }, { text = "Cancel" } })
    end }
    return items
end
function A:TimelineAbilityMenu(ev, anchor)
    if ev.source == "test" then return end
    A.ShowMenu(anchor, self:TimelineActions(target(ev)), "TOPLEFT", "TOPRIGHT", 4, 0, 200)
end

-- ------------------------------------------------------------ details window
local function describe(rec)
    if not rec then return "not seen yet", C.dim end
    local parts = {}
    if rec.override and rec.override.cd then parts[#parts + 1] = "manual: every " .. rec.override.cd .. "s" end
    if rec.override and rec.override.hp then parts[#parts + 1] = "manual: at " .. rec.override.hp .. "% HP" end
    local m = rec.acc
    if m then
        parts[#parts + 1] = (m.kind == "window" and string.format("learned: every %d-%ds", m.lo, m.hi) or ("learned: every " .. m.cd .. "s"))
            .. string.format(" (%d intervals)", m.n or 0) .. (rec.reval and ", re-checking" or "")
    elseif rec.cand then
        parts[#parts + 1] = string.format("checking: every ~%ss (%d/%d checks)", rec.cand.cd, #rec.cv, K.VALIDATE) .. (rec.cand.imported and ", imported" or "")
    else
        parts[#parts + 1] = string.format("learning (%d intervals, %d pulls)", #rec.g, rec.pulls or 0)
    end
    if rec.thr then parts[#parts + 1] = "at " .. rec.thr.hp .. "% HP" elseif rec.ambiguous then parts[#parts + 1] = "HP or time? unclear" end
    if rec.first then parts[#parts + 1] = "opens at ~" .. rec.first.t .. "s" end
    if rec.lock then parts[#parts + 1] = "locked" end
    if rec.useProvider then parts[#parts + 1] = "boss mod timing preferred" end
    if m and rec.audit then parts[#parts + 1] = "carried over from 0.6, re-checking" end
    return table.concat(parts, " - "), (m or rec.override) and C.text or C.dim
end
-- the fight shown: the current one, else the last one
local function subject()
    local E = T:Encounter()
    if E then return E.npcs, E.ctx, E.name end
    local last = T.lastEnd
    if last and last.npcs then return last.npcs, last.ctx, last.name end
end
function A:TimelineDetails()
    local npcs, ctx, name = subject()
    if not npcs or not next(npcs) then self:Print("Fight a boss first; its details show here afterwards."); return end
    local p = self.timelineDetails
    if not p then
        p = A.Panel("BlizzUIRebornTimelineDetails", UIParent, 560, 200, "", "DIALOG")
        p:SetFrameLevel(30)
        p:SetPoint("CENTER", UIParent, "CENTER", 0, 60)
        p.rows = {}
        p.note = A.Text(p, 11, C.dim); p.note:SetPoint("TOPLEFT", p, "TOPLEFT", 20, -36); p.note:SetWidth(520); p.note:SetJustifyH("LEFT")
        p.share = A.Button(p, "Share Boss Data", 130, function() A:TimelineShare() end)
        p.import = A.Button(p, "Import", 90, function() A:TimelineImport() end)
        p.forget = A.Button(p, "Forget This Boss", 130, function()
            A:Confirm("Forget Boss", "Forget everything learned about this boss (all difficulties)?", {
                { text = "Forget", func = function() for n in pairs(p.npcs) do K:ForgetBoss(n) end; T:Changed(); p:Hide() end }, { text = "Cancel" } })
        end)
        p.notboss = A.Button(p, "Not a Boss...", 110, function()
            local list = {}
            for n in pairs(p.npcs or {}) do
                local b = K:Boss(n)
                list[#list + 1] = { text = (b and b.name) or ("Creature " .. n), func = function()
                    A:Confirm("Not a Boss", "Stop treating " .. ((b and b.name) or ("creature " .. n)) .. " as a boss here? Nothing more is learned from it; its data can be removed with Forget This Boss.", {
                        { text = "Not a Boss", func = function() A:SetBossDecision(n, b and b.name, false); p:Hide() end }, { text = "Cancel" } })
                end }
            end
            A.ShowMenu(p.notboss, list, "TOPLEFT", "BOTTOMLEFT", 0, -2, 200)
        end)
        p.server = A.Button(p, "Server Changed...", 130, function()
            A:Confirm("Server Changed", "Did the server change boss timings (a patch)? Learned timings are kept but re-checked, and replaced only once new ones prove better.", {
                { text = "Re-check All", func = function() K:MarkServerChange(); T:Changed(); A:TimelineDetails() end }, { text = "Cancel" } })
        end)
        table.insert(UISpecialFrames, "BlizzUIRebornTimelineDetails")
        self.timelineDetails = p
    end
    p.npcs, p.ctx = npcs, ctx
    p.title:SetText((name or "Boss") .. " - Boss Timeline")
    p.note:SetText("This server, " .. (ctx or ""):gsub("^[^|]*|", ""):gsub("|", " difficulty ") .. ". Right-click or use the buttons to adjust an ability.")
    -- rows: what this account observed for these bosses here
    local rows = {}
    for npc in pairs(npcs) do
        for id, rec in pairs(K:Recs(ctx, npc) or {}) do
            rows[#rows + 1] = { name = rec.n or ("Spell " .. id), rec = rec, npc = npc, id = id }
        end
    end
    table.sort(rows, function(a, b) return a.name < b.name end)
    for _, r in ipairs(p.rows) do r:Hide() end
    local y = -56
    for i, r in ipairs(rows) do
        if i > 20 then break end
        local row = p.rows[i]
        if not row then
            row = CreateFrame("Frame", nil, p); A.Size(row, 520, 20)
            row.name = A.Text(row, 12, C.gold); row.name:SetPoint("LEFT", row, "LEFT", 0, 0); row.name:SetWidth(170); row.name:SetJustifyH("LEFT")
            row.info = A.Text(row, 11, C.text); row.info:SetPoint("LEFT", row, "LEFT", 176, 0); row.info:SetWidth(300); row.info:SetJustifyH("LEFT")
            row.gear = A.Button(row, "...", 32, function(btn) local d = btn:GetParent().data; A.ShowMenu(btn, A:TimelineActions(d), "TOPLEFT", "TOPRIGHT", 4, 0, 200) end, 18)
            row.gear:SetPoint("RIGHT", row, "RIGHT", 0, 0)
            p.rows[i] = row
        end
        local b = K:Boss(r.npc)
        local hidden = b and b.hide and b.hide[r.name]
        row.name:SetText(r.name .. (hidden and " |cff999999(hidden)|r" or ""))
        local text, color = describe(r.rec)
        row.info:SetText(text); row.info:SetTextColor(color[1], color[2], color[3])
        row.data = { npc = r.npc, rec = r.rec, id = r.id, name = r.name, label = r.name }
        row:ClearAllPoints(); row:SetPoint("TOPLEFT", p, "TOPLEFT", 20, y)
        row:Show()
        y = y - 22
    end
    if #rows == 0 then
        p.empty = p.empty or A.Text(p, 12, C.dim)
        p.empty:ClearAllPoints(); p.empty:SetPoint("TOPLEFT", p, "TOPLEFT", 20, y)
        p.empty:SetText("Nothing learned yet: casts are recorded as this boss is fought.")
        p.empty:Show()
        y = y - 20
    elseif p.empty then p.empty:Hide() end
    y = y - 10
    p.share:ClearAllPoints(); p.share:SetPoint("TOPLEFT", p, "TOPLEFT", 20, y)
    p.import:ClearAllPoints(); p.import:SetPoint("LEFT", p.share, "RIGHT", 6, 0)
    p.forget:ClearAllPoints(); p.forget:SetPoint("LEFT", p.import, "RIGHT", 6, 0)
    p.notboss:ClearAllPoints(); p.notboss:SetPoint("LEFT", p.forget, "RIGHT", 6, 0)
    p.server:ClearAllPoints(); p.server:SetPoint("TOPLEFT", p.share, "BOTTOMLEFT", 0, -6)
    y = y - 28
    p:SetHeight(-y + 40)
    A.RaiseChildren(p)
    p:Show()
end
function A:TimelineShare()
    local npcs = subject()
    if not npcs then return end
    self:TextDialog({ title = "Share Boss Data", label = "Press Ctrl+C to copy. It only contains learned timings (checked again on import):",
        multiline = true, initial = K:Export(npcs) })
end
function A:TimelineImport()
    self:TextDialog({ title = "Import Boss Data", label = "Paste a BlizzUI Reborn boss data string:", multiline = true, acceptText = "Import",
        accept = function(text)
            local n, err = K:Import(text)
            if not n then return nil, err end
            A:Print(n .. " imported timing(s) will be used once your own fights confirm them.")
            T:Changed()
            return true
        end })
end

-- ------------------------------------------------------------ boss question
-- A creature that may be a boss but carries no boss flag (skull or 2+ levels
-- above you, elite, in a dungeon or raid; or named by a BigWigs module): one
-- small question, once per creature per session. The answer is remembered
-- for this server and instance and can be changed in Encounter Details.
local asked = {}
function A:TimelineBossPrompt(npc, name)
    if not npc or asked[npc] or not self.active or not self:TimelineEnabled() then return end
    if K:BossDecision(npc) ~= nil then return end
    asked[npc] = true
    local f = self.bossPrompt
    if not f then
        f = A.Panel("BlizzUIRebornBossPrompt", UIParent, 300, 64, nil, "MEDIUM")
        f.text = A.Text(f, 12, C.text); f.text:SetPoint("TOP", f, "TOP", 0, -12); f.text:SetWidth(280)
        f.yes = A.Button(f, "Track as Boss", 120, function() A:SetBossDecision(f.npc, f.name, true) end, 20)
        f.no = A.Button(f, "Not a Boss", 100, function() A:SetBossDecision(f.npc, f.name, false) end, 20)
        f.later = A.Button(f, "Later", 60, function() f:Hide() end, 20)
        f.yes:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 10, 8)
        f.no:SetPoint("LEFT", f.yes, "RIGHT", 4, 0)
        f.later:SetPoint("LEFT", f.no, "RIGHT", 4, 0)
        if f.title then f.title:Hide() end
        f:SetScript("OnUpdate", function(self) if GetTime() > (self.expireAt or 0) then self:Hide() end end)
        self.bossPrompt = f
    end
    f.npc, f.name, f.expireAt = npc, name, GetTime() + 20
    f.text:SetText("Is " .. (name or "this creature") .. " a boss? (Boss Timeline)")
    f:ClearAllPoints()
    local root = A.TimelineView and A.TimelineView.root
    if root and root:IsShown() then f:SetPoint("BOTTOMLEFT", root, "TOPLEFT", 0, 6)
    else f:SetPoint("TOP", UIParent, "TOP", 0, -150) end
    A.RaiseChildren(f)
    f:Show()
end
function A:HideBossPrompt(npc)
    local f = self.bossPrompt
    if f and (not npc or f.npc == npc) then f:Hide() end
end
