-- Boss Timeline engine: Retail's Boss Abilities timeline for 3.3.5.
--
-- Which boss: boss units (boss1-4), world-boss classification, the active
-- encounter module of Deadly Boss Mods, and creatures the player confirmed
-- (remembered per server and instance). Never trash. No boss list ships
-- with the addon.
--
-- Forecast sources, per ability (one display entry per occurrence):
--   * optional boss mod timers (DBM, BigWigs), read only and transient; they
--     own an ability once they time it, and a cancelled boss mod timer never
--     brings back an old local estimate (only a freshly observed cast can);
--   * this server's validated models (TimelineKnowledge.lua), manual
--     overrides, and in-pull provisional estimates ("Learning");
--   * HP thresholds with a live ETA from that boss's own net health loss;
--   * casts in progress (combat log estimate, or exact from a cast bar).
-- A boss with no knowledge and no boss mod shows "Learning": nothing is
-- invented. Boss mod timers are never evidence for learning.
local A = BlizzUIReborn
local T = {}
A.Timeline = T
local K = A.TimelineKB
local GetTime, pairs, ipairs, type, tonumber, math, select = GetTime, pairs, ipairs, type, tonumber, math, select

T.SHORT, T.MEDIUM, T.LONG = 5, 15, 40   -- track breakpoints (seconds)
T.HIGHLIGHT = 5                         -- imminent: highlight + warning
T.DEADLY = .35
local ENRAGE_SPELL = 26662               -- "Berserk"
local ENRAGE_ICON = "Interface\\Icons\\Spell_Shadow_UnholyFrenzy"
local DEFAULT_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"
local CLEU_CODES = { SPELL_CAST_START = "S", SPELL_CAST_SUCCESS = "C", SPELL_SUMMON = "U" } -- auras are not casts
local frame = CreateFrame("Frame")
frame:Hide() -- shown (OnUpdate running) only while a fight is tracked
T.frame = frame
local generation = 0

-- ------------------------------------------------------------ options
function A:TimelineDB()
    local db = self.db
    if type(db.timeline) ~= "table" then db.timeline = {} end
    local t = db.timeline
    if t.useBossMods == nil then t.useBossMods = true end
    if t.learn == nil then t.learn = true end
    if t.predictions == nil then t.predictions = true end
    if t.prefer ~= "auto" and t.prefer ~= "bossmods" and t.prefer ~= "learned" then t.prefer = "auto" end
    if t.provider ~= "dbm" and t.provider ~= "bigwigs" then t.provider = "dbm" end
    return t
end

-- ------------------------------------------------------------ helpers
local npcCache, cached = {}, 0
-- 3.3.5 GUIDs: "0xF130008F14000A3B"; type digit 3 = creature, 5 = vehicle
function T.NpcID(guid)
    if type(guid) ~= "string" then return nil end
    local c = npcCache[guid]
    if c ~= nil then return c or nil end
    local kind = tonumber(guid:sub(5, 5), 16)
    local id = (kind == 3 or kind == 5) and tonumber(guid:sub(8, 12), 16) or false
    if id == 0 then id = false end
    if cached > 4000 then wipe(npcCache); cached = 0 end
    cached = cached + 1
    npcCache[guid] = id
    return id or nil
end
function T.SpellInfo(id)
    if not id or id == 0 then return nil end
    local name, _, icon, _, _, _, castTime = GetSpellInfo(id)
    return name, icon, castTime
end
function T:Changed() self.version = (self.version or 0) + 1 end
function T:Active() return self.encounter ~= nil end
function T:Encounter() return self.encounter end

-- ------------------------------------------------------------ bosses
-- A boss by the game's own flags (boss frame / world boss), by the player's
-- decision for this server and instance, or (legacy) confirmed earlier.
-- A "not a boss" decision always wins in its context.
function T:IsKnownBoss(npc)
    if not npc then return false end
    local d = K:BossDecision(npc)
    if d ~= nil then return d end
    local b = K:Boss(npc)
    return b and (b.auto or b.confirmed) and true or false
end
-- stable identity for an ability across sources: its spell ID, else its label
function T.IdKey(spellId, name)
    if spellId and spellId ~= 0 then return "id:" .. spellId end
    return "label:" .. tostring(name or ""):lower()
end
function T.AbKey(ab) return T.IdKey(ab.spellId or ab.recId, ab.spellName or ab.name) end

-- ------------------------------------------------------------ events
local function newEvent(key, name, icon, spellId, expires, total, source)
    return { key = key, name = name, icon = icon or DEFAULT_ICON, spellId = spellId, expires = expires, total = math.max(total or 0, .1),
        state = "timer", source = source }
end
T.NewEvent = newEvent

-- ------------------------------------------------------------ encounter
function T:StartEncounter(npc, guid, name, pullTime, source, trust)
    if self.encounter then
        self:AddBoss(npc, guid, trust)
        return self.encounter
    end
    local now = GetTime()
    local late = false
    if not pullTime then
        local c, g = self.combatStart, self.engageTime
        if g and now - g <= 1 then pullTime = g          -- boss frames just engaged
        elseif c and now - c <= 5 then pullTime = c      -- we entered combat just now
        else late = true end
    end
    generation = generation + 1
    local db = A:TimelineDB()
    if source ~= "test" then db.pull = (tonumber(db.pull) or 0) + 1 end
    local E = { gen = generation, start = pullTime or now, npcs = {}, allowed = {}, guids = {}, dead = {}, abilities = {}, byName = {},
        events = {}, owner = {}, lastTrigger = {}, source = source or "auto", name = name, late = late, important = {}, hits = {},
        phase = 1, phaseStart = pullTime or now, pending = {}, obs = {}, perr = {}, lerr = {}, provExpect = {}, warned = {},
        occCount = {}, ctx = K:Context(), pull = db.pull, hp = {}, unitOf = {}, trusted = {}, aliases = {}, filler = {}, broken = {} }
    self.encounter = E
    frame:Show()
    self:AddBoss(npc, guid, trust)
    self.endCheck = nil
    self:Changed()
    if A.OnTimelineChanged then A:OnTimelineChanged("start") end
    return E
end

-- Adds a boss creature to the fight (council fights, bosses that join later).
-- trust: false for a creature only a boss mod's engage message points at
-- (its bars show, nothing is learned until it is confirmed).
function T:AddBoss(npc, guid, trust)
    local E = self.encounter
    if not E then return end
    if npc and K:BossDecision(npc) == false then return end -- "not a boss" always wins
    if guid and not E.guids[guid] then E.guids[guid] = true; E.killedAt = nil end
    if not npc then return end
    if trust ~= false and not E.trusted[npc] then E.trusted[npc] = true; self:Changed() end
    if E.npcs[npc] then return end
    E.npcs[npc] = true
    E.allowed[npc] = true
    -- this server's knowledge for the creature (this realm/instance/difficulty only)
    local recs = K:Recs(E.ctx, npc)
    if recs then
        for id, rec in pairs(recs) do self:LinkRec(npc, id, rec) end
    end
    -- openers (learned only: an unfamiliar boss gets no invented first cast)
    if not E.late then
        for _, ab in pairs(E.abilities) do
            if not ab.opened and (not ab.casters or E.npcs[npc]) then
                ab.opened = true
                self:Open(ab)
            end
        end
    end
    self:Changed()
end
-- Is anything known about this fight? (else the display says "Learning")
function T:HasKnowledge()
    local E = self.encounter
    if not E then return false end
    for _, ab in pairs(E.abilities) do
        if ab.rec and (K:Repeat(ab.rec) or K:Threshold(ab.rec) or K:First(ab.rec, 1)) then return true end
    end
    return false
end
-- A learned record is an ability of its own: creature + spell ID (difficulty
-- variants of one spell stay separate records).
function T:LinkRec(npc, id, rec)
    local E = self.encounter
    if not rec.n then rec.n = T.SpellInfo(id) end
    if not rec.n then return end
    local key = "l" .. npc .. ":" .. id
    local ab = E.abilities[key]
    if not ab then
        ab = { key = key, name = rec.n, spellName = rec.n, spellId = id, icon = rec.icon or select(2, T.SpellInfo(id)) or DEFAULT_ICON,
            casters = { npc }, rec = rec, recNpc = npc, recId = id, learned = true }
        self:AddAbility(ab)
    end
    return ab
end
local function index(list, key, ab)
    list[key] = list[key] or {}
    for _, x in ipairs(list[key]) do if x == ab then return end end
    table.insert(list[key], ab)
end
function T:AddAbility(ab)
    local E = self.encounter
    E.abilities[ab.key] = ab
    E.byKey = E.byKey or {}
    index(E.byName, ab.spellName or ab.name, ab)
    index(E.byKey, T.AbKey(ab), ab)
    -- a boss mod already timing it under a variant spell ID
    for _, ev in pairs(E.events) do
        if ev.pkey and ev.spellId and ev.spellName == (ab.spellName or ab.name) then self:Alias(ev.spellId, ev.spellName, ev.pkey) end
    end
end
function T:CastBy(ab, npc)
    if not ab.casters then return true end
    for _, n in ipairs(ab.casters) do if n == npc then return true end end
    return false
end

-- ------------------------------------------------------------ forecasts
-- Pull opener: learned opener (3+ pulls); HP threshold
-- abilities become threshold entries instead.
function T:Open(ab)
    local E = self.encounter
    local thr = K:Threshold(ab.rec)
    if thr then return self:Threshold(ab, thr) end
    local first = K:First(ab.rec, 1)
    if first then return self:Schedule(ab, E.start + first.t, "learned", E.start + first.lo, E.start + first.hi) end
    if ab.practice and ab.first then return self:Schedule(ab, E.start + ab.first, "practice") end
end
-- Next occurrence after the ability happened at `t` (its own cast).
function T:AfterOwn(ab, t, o)
    local model, reval = K:Repeat(ab.rec, self.encounter.phase)
    if model then
        local prov = model.manual and "manual" or (reval and "revalidating" or "learned")
        if model.kind == "window" then return self:Schedule(ab, t + model.lo, prov, t + model.lo, t + model.hi) end
        return self:Schedule(ab, t + model.cd, prov, model.lo and t + model.lo, model.hi and t + model.hi)
    end
    if ab.practice and ab.cd then return self:Schedule(ab, t + ab.cd, "practice") end
    -- provisional: the last three clean intervals of this pull agree
    local est = o and K:Provisional(o, self.encounter.phase)
    if est then return self:Schedule(ab, t + est, "provisional") end
end
-- one display entry per ability occurrence
function T:Schedule(ab, at, prov, lo, hi)
    local E = self.encounter
    local now = GetTime()
    if not E or at < now - 1 then return end
    E.occCount[ab.key] = (E.occCount[ab.key] or 0) + 1
    local ev = newEvent(ab.key, ab.name, ab.icon, ab.spellId, at, at - now, "predict")
    ev.ability, ev.prov, ev.lo, ev.hi = ab, prov or "learned", lo, hi
    ev.estimate, ev.created = true, now
    ev.occ = ab.key .. "#" .. E.occCount[ab.key]
    local window = (hi and lo and hi - lo) or (hi and hi - at) or 0
    ev.grace = math.max(3, window + 2, (at - now) * .1)
    ev.enrage = ab.enrage
    E.events[ab.key] = ev
    self:Changed()
    return ev
end
-- HP threshold entry: the ETA is recomputed from the boss's health loss.
function T:Threshold(ab, model)
    local E = self.encounter
    if E.latched and E.latched[ab.key] then return end
    local ev = newEvent(ab.key, ab.name, ab.icon, ab.spellId, GetTime() + 600, 600, "predict")
    ev.ability, ev.prov, ev.kind, ev.hp = ab, model.manual and "manual" or "learned", "threshold", model.hp
    ev.estimate, ev.threshold = true, true
    ev.occ = ab.key .. "#hp"
    ev.state = "waiting"
    E.events[ab.key] = ev
    self:Changed()
    return ev
end
function T:CancelLocal(keepEnrage)
    local E = self.encounter
    for key, ev in pairs(E.events) do
        -- HP thresholds don't depend on phase timing: they stay armed
        if ev.source == "predict" and not ev.threshold and not (keepEnrage and ev.enrage) then E.events[key] = nil end
    end
    self:Changed()
end

-- ------------------------------------------------------------ phases
-- Boss mods tell us about phase changes (DBM_SetStage). Old predictions end,
-- chains restart, phase openers learned for this phase are scheduled.
function T:PhaseChange(stage)
    local E = self.encounter
    if not E then return end
    local now = GetTime()
    stage = tonumber(stage)
    -- DBM stage numbers are the phase (and repeat: Anub'arak 1,2,1,2,1,3);
    -- SetStage(1) at the pull or a repeated stage is not a change
    if stage and stage == E.phase then E.phaseKnown = true; return end
    E.phase = stage or E.phase + 1
    E.seg = (E.seg or 1) + 1
    E.phaseStart, E.phaseKnown = now, true
    self:CancelLocal(true)
    wipe(E.lastTrigger)
    for _, ab in pairs(E.abilities) do
        local pf = K:First(ab.rec, E.phase)
        local cur = E.events[ab.key]
        if pf and not (cur and cur.threshold) then self:Schedule(ab, now + pf.t, "learned", now + pf.lo, now + pf.hi) end
    end
end

-- ------------------------------------------------------------ importance
-- Shown: what a boss mod times this pull, learned dangerous hits (35%+
-- health or a kill), AoE on 3+ players, adds, health-triggered or manually
-- set abilities, and anything the player pinned. Casts in progress by the
-- bosses show unless they are filler (cast again every few seconds).
-- Hidden: everything the player hid.
function T:Flag(ab, name)
    local E = self.encounter
    local b
    local id = ab and (ab.recId or ab.spellId)
    for npc in pairs(E.npcs) do
        b = K:Boss(npc)
        if b then
            if id and b.spells[id] then return b.spells[id], b end
            if not id and name then for _, f in pairs(b.spells) do if f.n == name then return f, b end end end
        end
    end
    return nil, b
end
function T:Hidden(name)
    local E = self.encounter
    for npc in pairs(E.npcs) do
        local b = K:Boss(npc)
        if b and b.hide and b.hide[name] then return true end
    end
    return false
end
function T:Importance(name, ab, spellId)
    local E = self.encounter
    if not E or not name then return 0 end
    local key = T.IdKey((ab and (ab.spellId or ab.recId)) or spellId, name)
    local level = E.important[key] or 0
    local f = self:Flag(ab or (spellId and { spellId = spellId }), name)
    if f then
        if f.deadly then return 2 end
        if f.aoe or f.summon or f.pin then level = math.max(level, 1) end
    end
    for npc in pairs(E.npcs) do
        local b = K:Boss(npc)
        if b and b.pin and b.pin[name] then level = math.max(level, 1) end
    end
    -- happens at a health threshold (a scripted mechanic), or the player set it up
    local rec = ab and ab.rec
    if rec and (rec.thr or rec.override) then level = math.max(level, 1) end
    return level
end
-- a boss spell cast again every few seconds (this pull, or learned) is filler
function T:Filler(npc, spellId)
    local E = self.encounter
    if not E or not spellId then return false end
    if npc and E.filler[npc .. ":" .. spellId] then return true end
    for n in pairs(E.npcs) do
        local f = K:Flags(n, spellId)
        if f and f.filler and not (f.deadly or f.aoe or f.summon or f.pin) then return true end
    end
    return false
end
function T:Shows(ev)
    local db = A:TimelineDB()
    if ev.source == "test" then return true end
    local ab = ev.ability
    local name = ab and (ab.spellName or ab.name) or ev.name
    if self:Hidden(ev.name) or (name ~= ev.name and self:Hidden(name)) then return false end
    if ev.source == "dbm" or ev.source == "bigwigs" then return db.useBossMods and true or false end
    if ev.source == "predict" and not db.predictions then return false end
    if db.allAbilities then return true end
    if ab and ab.practice then return true end
    local level = self:Importance(name, ab, ev.spellId)
    if level > 0 then return true end
    if ev.source == "cast" then return not self:Filler(ev.npc, ev.spellId) end
    return false
end
function T:Danger(ev)
    local ab = ev.ability
    return (ab and ab.danger) or self:Importance(ab and (ab.spellName or ab.name) or ev.name, ab, ev.spellId) >= 2
end
-- group members' max health, to judge how hard a hit was
function T:GroupHealth(guid)
    local E = self.encounter
    if not E.units then
        E.units = {}
        local function add(u) local g = UnitGUID(u); if g then E.units[g] = u end end
        add("player")
        local raid = GetNumRaidMembers and GetNumRaidMembers() or 0
        if raid > 0 then for i = 1, raid do add("raid" .. i) end
        else for i = 1, (GetNumPartyMembers and GetNumPartyMembers() or 0) do add("party" .. i) end end
    end
    local u = E.units[guid]
    return u and UnitHealthMax(u) or nil
end
function T:OnDamage(npc, spellId, name, destGUID, amount, overkill)
    if not name or not destGUID or not spellId then return end
    local E = self.encounter
    local maxHp = self:GroupHealth(destGUID)
    if not maxHp then return end -- pets, adds, totems
    local now = GetTime()
    local key = npc .. ":" .. spellId
    local h = E.hits[key]
    if not h or now - h.t > 1.5 then h = { t = now, n = 0, seen = {} }; E.hits[key] = h end
    if not h.seen[destGUID] then h.seen[destGUID] = true; h.n = h.n + 1 end
    local deadly = (tonumber(overkill) or 0) > 0 or (maxHp > 0 and (tonumber(amount) or 0) / maxHp >= T.DEADLY)
    if not deadly and h.n < 3 then return end
    if not A:TimelineDB().learn or E.source == "test" then return end
    local f = K:Flags(npc, spellId, name, true)
    if deadly and not f.deadly then f.deadly = true; self:Changed() end
    if h.n >= 3 and not f.aoe then f.aoe = true; self:Changed() end
end

-- ------------------------------------------------------------ observations
-- A boss cast happened (the start time for cast-time spells, confirmed by
-- its success; the time itself for instants/summons).
function T:Occurrence(npc, guid, spellId, name, icon, t, code)
    local E = self.encounter
    if not E or not name then return end
    local db = A:TimelineDB()
    local idk = T.IdKey(spellId, name)
    -- boss mod accuracy on this server (their timer vs the real cast): a
    -- comparison only, never a learning sample
    local pk = E.aliases[idk] or idk
    local pe = E.provExpect[pk]
    if pe then
        if math.abs(t - pe) <= 20 then E.perr[pk] = E.perr[pk] or {}; table.insert(E.perr[pk], math.abs(t - pe)) end
        E.provExpect[pk] = nil
    end
    -- learning: only the confirmed bosses themselves (adds and creatures a
    -- boss mod merely points at are not evidence)
    local o
    if npc and spellId and E.npcs[npc] and E.trusted[npc] and E.source ~= "test" then
        local bk = npc .. ":" .. spellId
        local fresh
        o, fresh = K:Observe(E, npc, spellId, name, icon, code, t, self:HealthPct(guid), E.broken[bk])
        if not fresh then return end
        E.broken[bk] = nil
        -- cast again within a few seconds, again and again: filler
        local n = #o.occ
        if n >= 4 and o.occ[n][1] - o.occ[n - 3][1] < 24 and not E.filler[bk] then E.filler[bk] = true; self:Changed() end
        if db.learn then
            if code == "U" then local f = K:Flags(npc, spellId, name, true); if not f.summon then f.summon = true; self:Changed() end end
            -- a spell seen for the first time on this boss becomes an ability
            if not E.abilities["l" .. npc .. ":" .. spellId] then
                self:LinkRec(npc, spellId, K:Rec(E.ctx, npc, spellId) or { n = name, icon = icon })
            end
        end
    end
    for _, ab in ipairs((E.byKey or {})[idk] or {}) do
        if not npc or self:CastBy(ab, npc) then
            local ev = E.events[ab.key]
            -- our own forecast accuracy (for boss mod vs learned preference)
            if ev and ev.source == "predict" and ev.prov == "learned" and ab.recNpc then
                local k = ab.recNpc .. ":" .. ab.recId
                E.lerr[k] = E.lerr[k] or {}
                table.insert(E.lerr[k], math.abs(t - ev.expires))
            end
            if ev and ev.threshold then
                E.latched = E.latched or {}
                E.latched[ab.key] = true
            end
            -- it happened: the entry it answers is done (not one this very
            -- cast already scheduled for next time)
            if ev and ev.source == "predict" and (ev.created or 0) < t - .05 then E.events[ab.key] = nil; self:Changed() end
            self:AfterOwn(ab, t, o)
            self:ProviderCheck(ab, idk)
        end
    end
end
-- Practice fights: a named cast from the encounter.
function T:OnCast(code, spellId, name, guid, npc)
    local E = self.encounter
    if not E then return end
    if code == "S" or code == "C" or code == "U" then self:Occurrence(npc, guid, spellId, name, nil, GetTime(), code) end
end

-- ------------------------------------------------------------ casts in progress
function T:CastStarted(key, name, icon, spellId, endTime, duration, sourceName, exact, npc)
    local E = self.encounter
    if not E then return end
    local ev = E.events[key]
    local now = GetTime()
    if ev and ev.name ~= name then E.events[key] = nil; ev = nil end
    if not ev then
        ev = newEvent(key, name, icon, spellId, endTime, duration, "cast")
        ev.state, ev.caster, ev.prov, ev.npc = "cast", sourceName, "live", npc
        E.events[key] = ev
        local level = self:Importance(name, nil, spellId)
        ev.danger = level >= 2
        -- warned only for known mechanics; unfamiliar casts are shown, not alarmed
        if A.TimelineWarn and level > 0 and self:Shows(ev) then A:TimelineWarn("critical", name, icon, sourceName) end
    end
    ev.expires, ev.total = endTime, math.max(duration or (endTime - now), .1)
    ev.estimate = not exact
    self:Changed()
end
function T:CastStopped(key)
    local E = self.encounter
    if E and E.events[key] then E.events[key] = nil; self:Changed() end
end

-- ------------------------------------------------------------ boss mods
local function modLabel(name, spellId, msg)
    return (type(name) == "string" and name ~= "" and name) or (spellId and T.SpellInfo(spellId)) or msg
end
-- Aliases: a boss mod may time a mechanic by one spell ID while the boss
-- casts a difficulty variant with another ID. They are joined only when the
-- name AND the icon match, for abilities of this fight's own bosses.
function T:Alias(spellId, spellName, key)
    local E = self.encounter
    if not spellId or not spellName then return end
    local icon = select(2, T.SpellInfo(spellId))
    for _, ab in ipairs(E.byName[spellName] or {}) do
        local id = ab.spellId or ab.recId
        if id and id ~= spellId and icon and select(2, T.SpellInfo(id)) == icon then E.aliases[T.IdKey(id)] = key end
    end
end
-- ability identity key -> the key boss mod timers use for it
function T:ProvKey(ab) local k = T.AbKey(ab); return self.encounter.aliases[k] or k end
-- A boss mod timer (transient): it owns the ability from now on in this pull.
function T:ModTimer(key, name, icon, spellId, duration, keep, source)
    local E = self.encounter
    if not E then return end
    if type(icon) == "number" then icon = select(3, GetSpellInfo(icon)) end
    if (not icon or icon == "") and spellId then icon = select(3, GetSpellInfo(spellId)) end
    local ev = newEvent(key, name, icon, spellId, GetTime() + duration, duration, source)
    ev.keep, ev.prov, ev.estimate = keep, source, true
    ev.occ = key .. "#" .. tostring(GetTime())
    local spellName = spellId and T.SpellInfo(spellId) or name
    ev.spellName = spellName
    -- identity: the spell ID; bars without one (phases, adds) only by their own label
    local pk = T.IdKey(spellId, name)
    ev.pkey = pk
    E.events[key] = ev
    E.owner[pk] = E.owner[pk] or {}
    E.owner[pk][source] = true
    if spellId then
        self:Alias(spellId, spellName, pk)
        E.important[pk] = math.max(E.important[pk] or 0, 1)
    end
    E.provExpect[pk] = GetTime() + duration
    self:Changed()
end
function T:ModTimerStop(key)
    local E = self.encounter
    if not E then return end
    local ev = E.events[key]
    if ev then
        E.events[key] = nil
        if ev.pkey then E.provExpect[ev.pkey] = nil end
        self:Changed()
    end
    -- ownership stays: a cancelled timer (phase change) must not revive our
    -- older estimate for the same ability
end
function T:ModTimerUpdate(key, elapsed, total)
    local E = self.encounter
    local ev = E and E.events[key]
    if not ev then return end
    ev.expires = GetTime() + (total - elapsed)
    ev.total = math.max(total, .1)
    ev.state, ev.paused, ev.lo, ev.hi = "timer", nil, nil, nil
    if ev.pkey then E.provExpect[ev.pkey] = ev.expires end
    self:Changed()
end
function T:ModTimerPause(key, paused)
    local E = self.encounter
    local ev = E and E.events[key]
    if not ev then return end
    if paused and not ev.paused then ev.paused = ev.expires - GetTime(); ev.lo, ev.hi = nil, nil
    elseif not paused and ev.paused then ev.expires = GetTime() + ev.paused; ev.paused = nil end
    self:Changed()
end
-- a running boss mod timer for this key (the preferred provider's first)
function T:LiveMod(pk, except)
    local E = self.encounter
    local found
    for _, ev in pairs(E.events) do
        if (ev.source == "dbm" or ev.source == "bigwigs") and ev.pkey == pk and ev ~= except then
            local r, fr = self:ProviderRank(ev.source), found and self:ProviderRank(found.source)
            if not found or r < fr or (r == fr and (ev.expires < found.expires or (ev.expires == found.expires and ev.key < found.key))) then found = ev end
        end
    end
    return found
end
function T:ProviderRank(source)
    local first = A:TimelineDB().provider == "bigwigs" and "bigwigs" or "dbm"
    return source == first and 1 or 2
end
function T:BossModActive()
    local E = self.encounter
    if not E then return false end
    for _, ev in pairs(E.events) do if ev.source == "dbm" or ev.source == "bigwigs" then return true end end
    return false
end
-- After a boss-mod-owned ability is cast, the boss mod normally restarts its
-- timer at once. If it doesn't within 2 seconds, the boss mod has let go of
-- that ability and our fresh estimate (from this cast) is shown.
function T:ProviderCheck(ab, idk, castTime)
    local E = self.encounter
    local pk = E.aliases[idk] or idk
    if not E.owner[pk] then return end
    local gen = E.gen
    -- boss mods restart some timers only when a long cast completes
    A:After(math.max(2, (castTime or 0) + 1.5), function()
        local cur = T.encounter
        if not cur or cur.gen ~= gen then return end
        if not T:LiveMod(pk) then cur.owner[pk] = nil; T:Changed() end
    end)
end
-- Which source shows this ability: "mod" or "local".
function T:Owner(ev)
    local E = self.encounter
    local ab = ev.ability
    local pk = ab and self:ProvKey(ab) or ev.pkey or T.IdKey(ev.spellId, ev.name)
    if not E.owner[pk] or not A:TimelineDB().useBossMods then return "local" end
    local pref = A:TimelineDB().prefer
    if pref == "bossmods" then return "mod" end
    local rec = ab and ab.rec
    if rec and rec.useProvider then return "mod" end
    if pref == "learned" and rec and K:Repeat(rec) then return "local" end
    if pref == "auto" and K:PrefersLocal(rec) then return "local" end
    return "mod"
end

-- DBM (DBM-Warmane and other backports with callbacks)
local DBM_TYPES = { cd = true, next = true, cast = true, stage = true, berserk = true, adds = true, ai = true, var = true,
    cdcount = true, nextcount = true, cdsource = true, nextsource = true, cdspecial = true, nextspecial = true, addscustom = true }
local function getMod(modId)
    if not modId or type(DBM.GetModByName) ~= "function" then return nil end
    local ok, mod = pcall(DBM.GetModByName, DBM, modId)
    return ok and type(mod) == "table" and mod or nil
end
-- the module's own boss creatures (its creature IDs; not the extra mobs
-- that only trigger its pull detection, which are often adds); creatures the
-- player said are not bosses are left out
local function modCreatures(mod)
    local list, seen = {}, {}
    local function add(n)
        n = tonumber(n)
        if n and not seen[n] and K:BossDecision(n) ~= false then seen[n] = true; list[#list + 1] = n end
    end
    local c = mod.creatureId
    if type(c) == "table" then for _, n in ipairs(c) do add(n) end else add(c) end
    if type(mod.combatInfo) == "table" then add(mod.combatInfo.mob) end
    return list
end
-- Is this boss mod module the one for the fight we track?
function T:ModBelongs(mod, modId)
    local E = self.encounter
    if not E or type(mod) ~= "table" then return false end
    if mod.isTrashMod then return false end
    if E.modId then return E.modId == (modId or mod.id) end
    if not mod.inCombat then return false end
    local creatures = modCreatures(mod)
    if #creatures == 0 then return false end
    for _, n in ipairs(creatures) do
        if E.allowed[n] or E.npcs[n] then
            E.modId = modId or mod.id
            E.modCreatures = {}
            for _, c in ipairs(creatures) do E.modCreatures[c] = true end
            return true
        end
    end
    return false
end
function T:HookDBM()
    if self.dbmHooked or type(_G.DBM) ~= "table" or type(DBM.RegisterCallback) ~= "function" then return end
    self.dbmHooked = true
    local function enabled() return A.active and A:TimelineEnabled() and A:TimelineDB().useBossMods end
    -- DBM-Warmane: (event, id, msg, timer, icon, simpType, spellId or special key,
    -- colorId, modId, keep, fade, name, guid, count, isPriority, type, hasVariance, maxTimer)
    DBM:RegisterCallback("DBM_TimerStart", function(_, id, msg, timer, icon, simpType, spellId, _, modId, keep, _, name, _, _, _, _, hasVariance, maxTimer)
        if not enabled() or not id or not tonumber(timer) then return end
        if simpType and not DBM_TYPES[simpType] then return end
        local mod = getMod(modId)
        if not mod or mod.isTrashMod then return end
        if not T.encounter then
            if not mod.inCombat then return end
            T:StartFromMod(mod)
        end
        -- every timer must come from this fight's module
        if not T:ModBelongs(mod, modId) then return end
        spellId = tonumber(spellId)
        local label = modLabel(name, spellId, msg)
        if simpType == "berserk" then label = T.SpellInfo(ENRAGE_SPELL) or label; icon = icon or ENRAGE_ICON end
        T:ModTimer("dbm:" .. tostring(id), label, icon, spellId, tonumber(timer), keep, "dbm")
        local ev = T.encounter.events["dbm:" .. tostring(id)]
        if ev and simpType == "cast" then ev.state = "cast" end
        -- a variable timer: DBM gives the earliest time and the latest
        if ev and hasVariance and tonumber(maxTimer) and tonumber(maxTimer) > tonumber(timer) then
            ev.lo, ev.hi = ev.expires, GetTime() + tonumber(maxTimer)
        end
    end)
    DBM:RegisterCallback("DBM_TimerStop", function(_, id) if id then T:ModTimerStop("dbm:" .. tostring(id)) end end)
    DBM:RegisterCallback("DBM_TimerUpdate", function(_, id, elapsed, total)
        if id and tonumber(elapsed) and tonumber(total) then T:ModTimerUpdate("dbm:" .. tostring(id), tonumber(elapsed), tonumber(total)) end
    end)
    DBM:RegisterCallback("DBM_TimerPause", function(_, id) if id then T:ModTimerPause("dbm:" .. tostring(id), true) end end)
    DBM:RegisterCallback("DBM_TimerResume", function(_, id) if id then T:ModTimerPause("dbm:" .. tostring(id), false) end end)
    DBM:RegisterCallback("DBM_Pull", function(_, mod, delay)
        if enabled() and type(mod) == "table" and not mod.isTrashMod then
            local E = T:StartFromMod(mod, tonumber(delay))
            if E and not E.modId then
                E.modId = mod.id
                E.modCreatures = {}
                for _, c in ipairs(modCreatures(mod)) do E.modCreatures[c] = true end
            end
        end
    end)
    DBM:RegisterCallback("DBM_SetStage", function(_, mod, modId, stage)
        if T.encounter and T:ModBelongs(mod, modId) then T:PhaseChange(stage) end
    end)
    local function ends(reason)
        return function(_, mod)
            if T.encounter and T:ModBelongs(mod, type(mod) == "table" and mod.id or nil) then T:EndEncounter(reason) end
        end
    end
    DBM:RegisterCallback("DBM_Kill", ends("kill"))
    DBM:RegisterCallback("DBM_Wipe", ends("wipe"))
end
function T:StartFromMod(mod, delay)
    local creatures = modCreatures(mod)
    -- DBM's active encounter module (not a trash module) names its bosses
    if #creatures == 0 and not self.encounter then return nil end
    local E = self:StartEncounter(creatures[1], nil, mod.localization and mod.localization.general and mod.localization.general.name or mod.id,
        delay and (GetTime() - delay) or nil, "dbm", true)
    for i = 2, #creatures do self:AddBoss(creatures[i], nil, true) end
    return E
end

-- BigWigs (3.3.5 BigWigs sends AceEvent messages; its core is load on demand)
function T:HookBigWigs()
    if self.bwHooked or not _G.LibStub then return end
    local ok, AceEvent = pcall(LibStub, "AceEvent-3.0", true)
    if not ok or not AceEvent then return end
    self.bwHooked = true
    local target = {}
    AceEvent:Embed(target)
    self.bwTarget = target
    local function enabled() return A.active and A:TimelineEnabled() and A:TimelineDB().useBossMods end
    local function key(module, k) return "bw:" .. tostring(module and module.moduleName or module) .. ":" .. tostring(k) end
    -- the creatures a BigWigs module is for (its enable mobs), when known
    local function mobs(module)
        local bwc = _G.BigWigs
        if type(bwc) ~= "table" or type(bwc.GetEnableMobs) ~= "function" or type(module) ~= "table" then return nil end
        local ok, list = pcall(bwc.GetEnableMobs, bwc)
        if not ok or type(list) ~= "table" then return nil end
        local out = {}
        for mob, owner in pairs(list) do
            if owner == module.moduleName then out[#out + 1] = mob
            elseif type(owner) == "table" then for _, n in ipairs(owner) do if n == module.moduleName then out[#out + 1] = mob end end end
        end
        return out
    end
    -- the module that engaged (or whose creatures are this fight's) owns its bars
    local function belongs(module)
        local E = T.encounter
        if not E or type(module) ~= "table" or module == _G.BigWigs then return false end
        if E.bwModule then return E.bwModule == module end
        local list = mobs(module)
        for _, n in ipairs(list or {}) do
            if E.allowed[tonumber(n) or 0] then E.bwModule = module; return true end
        end
        return false
    end
    -- An engage message alone does not prove a boss (some modules cover
    -- trash): a fight starts only if one of the module's creatures is a boss
    -- (game flags seen before, or the player's confirmation). Otherwise the
    -- module is adopted later if a boss of its own is detected in the fight.
    target:RegisterMessage("BigWigs_OnBossEngage", function(_, module, name)
        if not enabled() or type(module) ~= "table" or module == _G.BigWigs then return end
        local E = T.encounter
        if E and E.bwModule and E.bwModule ~= module then return end
        local bosses = {}
        for _, n in ipairs(mobs(module) or {}) do
            n = tonumber(n)
            if n and T:IsKnownBoss(n) then bosses[#bosses + 1] = n end
        end
        if #bosses == 0 then return end
        local label = (type(module.displayName) == "string" and module.displayName) or name or module.moduleName
        E = E or T:StartEncounter(bosses[1], nil, label, nil, "bigwigs")
        if E.bwModule == nil then E.bwModule = module end
        for _, n in ipairs(bosses) do T:AddBoss(n) end
    end)
    target:RegisterMessage("BigWigs_StartBar", function(_, module, k, text, time, icon)
        if not enabled() or not T.encounter or not tonumber(time) or not text or not belongs(module) then return end
        local spellId = type(k) == "number" and k or nil
        -- BigWigs bars carry no type: a bar about a player (a debuff on
        -- someone) is not a boss ability timer
        if type(text) == "string" and T:NamesGroupMember(text) then return end
        -- the bar is that spell's timer when its text names the spell ("~Bone
        -- Storm", "Next Bone Storm (2)"); otherwise it is kept under its own label
        if spellId then
            local sn = T.SpellInfo(spellId)
            if not sn or not (text:find(sn, 1, true) or sn:find(text, 1, true)) then spellId = nil end
        end
        T:ModTimer(key(module, text), modLabel(nil, spellId, text), icon, spellId, tonumber(time), nil, "bigwigs")
        T.encounter.bwKeys = T.encounter.bwKeys or {}
        if k ~= nil then T.encounter.bwKeys[key(module, k)] = key(module, text) end
    end)
    target:RegisterMessage("BigWigs_StopBar", function(_, module, text)
        local E = T.encounter
        if not E or not belongs(module) then return end
        local k = key(module, text)
        T:ModTimerStop((E.bwKeys and E.bwKeys[k]) or k)
    end)
    local function stopAll(_, module)
        local E = T.encounter
        if not E or not belongs(module) then return end
        local prefix = key(module, "")
        for k in pairs(E.events) do if k:sub(1, #prefix) == prefix then T:ModTimerStop(k) end end
    end
    target:RegisterMessage("BigWigs_StopBars", stopAll)
    target:RegisterMessage("BigWigs_OnBossDisable", stopAll)
    -- stage messages exist in some 3.3.5 BigWigs versions (BigWigs_SetStage(module, phase))
    target:RegisterMessage("BigWigs_SetStage", function(_, module, phase)
        if T.encounter and not T.encounter.modId and belongs(module) then T:PhaseChange(phase) end
    end)
    target:RegisterMessage("BigWigs_OnBossWin", function(_, module) if belongs(module) then T:EndEncounter("kill") end end)
    target:RegisterMessage("BigWigs_OnBossWipe", function(_, module) if belongs(module) then T:EndEncounter("wipe") end end)
end

-- ------------------------------------------------------------ detection
-- Real bosses only: boss frames and world bosses (the game's own flags),
-- DBM's encounter module, and creatures the player confirmed for this
-- server and instance. A "not a boss" decision always wins. Being elite or
-- targeted is never proof: such a creature (skull level, or 2+ levels above
-- the player, in a dungeon or raid) only offers a one-time question.
function T:IsBossUnit(unit)
    if not UnitExists(unit) or UnitIsPlayer(unit) or not UnitCanAttack("player", unit) or UnitIsDead(unit) then return false end
    local npc = T.NpcID(UnitGUID(unit))
    if not npc then return false end
    if K:BossDecision(npc) == false then return false end
    if unit:find("^boss%d") then return true, npc, "frame" end
    if UnitClassification(unit) == "worldboss" then return true, npc, "frame" end
    if self:IsKnownBoss(npc) then return true, npc end
    return false, npc
end
function T:MaybeBoss(unit, npc)
    if not npc or K:BossDecision(npc) ~= nil then return false end
    local _, kind = IsInInstance()
    if kind ~= "party" and kind ~= "raid" then return false end
    local c = UnitClassification(unit)
    if c ~= "elite" and c ~= "rareelite" then return false end
    local lvl, mine = UnitLevel(unit) or 0, UnitLevel("player") or 0
    return lvl == -1 or lvl >= mine + 2
end
local SCAN = { "boss1", "boss2", "boss3", "boss4", "target", "focus", "targettarget", "focustarget", "pettarget" }
function T:EachScanUnit(fn)
    for _, u in ipairs(SCAN) do fn(u) end
    local raid = GetNumRaidMembers and GetNumRaidMembers() or 0
    if raid > 0 then for i = 1, raid do fn("raid" .. i .. "target") end
    else for i = 1, (GetNumPartyMembers and GetNumPartyMembers() or 0) do fn("party" .. i .. "target") end end
end
function T:ScanUnits()
    local found = false
    self:EachScanUnit(function(unit)
        local isBoss, npc, how = self:IsBossUnit(unit)
        if isBoss and UnitAffectingCombat(unit) then
            local guid = UnitGUID(unit)
            if not self.encounter then self:StartEncounter(npc, guid, UnitName(unit), nil, "auto") else self:AddBoss(npc, guid) end
            if self.encounter and self.encounter.guids[guid] then self.encounter.unitOf[guid] = unit end
            -- boss frames/world bosses are bosses by the game's own flags
            if how == "frame" then
                local b = K:Boss(npc, true)
                if not b.auto then b.auto = true end
                b.name = UnitName(unit)
            end
            found = true
        elseif not self.encounter and npc and UnitAffectingCombat(unit) and (unit == "target" or unit == "focus") and self:MaybeBoss(unit, npc) then
            if A.TimelineBossPrompt then A:TimelineBossPrompt(npc, UnitName(unit)) end
        end
    end)
    return found
end
-- does this bar text name someone in the group?
function T:NamesGroupMember(text)
    local function has(u)
        local n = UnitName(u)
        return n and n ~= "" and text:find(n, 1, true)
    end
    if has("player") then return true end
    local raid = GetNumRaidMembers and GetNumRaidMembers() or 0
    if raid > 0 then for i = 1, raid do if has("raid" .. i) then return true end end
    else for i = 1, (GetNumPartyMembers and GetNumPartyMembers() or 0) do if has("party" .. i) then return true end end end
    return false
end
function T:GroupInCombat()
    if UnitAffectingCombat("player") then return true end
    local raid = GetNumRaidMembers and GetNumRaidMembers() or 0
    if raid > 0 then
        for i = 1, raid do if UnitAffectingCombat("raid" .. i) then return true end end
    else
        for i = 1, (GetNumPartyMembers and GetNumPartyMembers() or 0) do if UnitAffectingCombat("party" .. i) then return true end end
    end
    return false
end
function T:EndEncounter(reason)
    local E = self.encounter
    if not E then return end
    self.encounter = nil
    frame:Hide()
    if not UnitAffectingCombat("player") then self:Listen(false) end
    -- fold this pull into the account's knowledge (between pulls only)
    if E.source ~= "test" then A:Run("Boss Timeline learning", K.Commit, K, E) end
    self.lastEnd = { reason = reason, time = GetTime(), name = E.name, npcs = E.npcs, ctx = E.ctx }
    self:Changed()
    if A.OnTimelineChanged then A:OnTimelineChanged("end", reason) end
end

-- ------------------------------------------------------------ boss health
-- Sampled at 4 Hz from boss/target/focus/group-target units. The rate is the
-- boss's actual health loss (healing and absorbs included), from a short and
-- a long window; jumps (resets, scripted changes) restart the history.
function T:BossUnit(guid)
    local E = self.encounter
    local u = E.unitOf[guid]
    if u and UnitGUID(u) == guid then return u end
    u = nil
    self:EachScanUnit(function(unit) if not u and UnitGUID(unit) == guid then u = unit end end)
    E.unitOf[guid] = u
    return u
end
function T:SampleHealth()
    local E = self.encounter
    local now = GetTime()
    for guid in pairs(E.guids) do
        if not E.dead[guid] then
            local u = self:BossUnit(guid)
            if u then
                local max = UnitHealthMax(u) or 0
                if max > 0 then
                    local pct = (UnitHealth(u) or 0) / max * 100
                    local h = E.hp[guid]
                    if not h or h.max ~= max then h = { max = max, s = {} }; E.hp[guid] = h end
                    local last = h.s[#h.s]
                    -- a jump in health (reset, heal to full, scripted change): new history
                    if last and math.abs(pct - last[2]) > 8 and now - last[1] < 1 then h.s = {} end
                    h.s[#h.s + 1] = { now, pct }
                    while #h.s > 64 do table.remove(h.s, 1) end
                end
            end
        end
    end
end
function T:HealthPct(guid)
    local E = self.encounter
    local h = guid and E and E.hp[guid]
    local last = h and h.s[#h.s]
    if last and GetTime() - last[1] <= 1.5 then return last[2] end
    local u = guid and E and self:BossUnit(guid)
    if u and (UnitHealthMax(u) or 0) > 0 then return UnitHealth(u) / UnitHealthMax(u) * 100 end
end
-- least-squares slope (percentage points per second, positive = losing)
local function lossRate(s, since)
    local n, sx, sy, sxx, sxy = 0, 0, 0, 0, 0
    for i = #s, 1, -1 do
        local p = s[i]
        if p[1] < since then break end
        n = n + 1; sx = sx + p[1]; sy = sy + p[2]; sxx = sxx + p[1] * p[1]; sxy = sxy + p[1] * p[2]
    end
    if n < 4 then return nil end
    local d = n * sxx - sx * sx
    if d == 0 then return nil end
    return -(n * sxy - sx * sy) / d
end
-- ETA to `thr` percent: eta, lo, hi, state ("eta", "waiting", "reached", "unknown")
function T:ThresholdETA(guid, thr)
    local E = self.encounter
    local h = E.hp[guid]
    local last = h and h.s[#h.s]
    local now = GetTime()
    if not last or now - last[1] > 1.5 then return nil, nil, nil, "unknown" end
    local pct = last[2]
    if pct <= thr then return 0, 0, 0, "reached" end
    local short, long = lossRate(h.s, now - 4), lossRate(h.s, now - 12)
    -- the recent trend decides: damage stopped (immunity, add phase) = waiting
    local lead = short or long
    if not lead or lead <= .05 then return nil, nil, nil, "waiting" end
    local rates = { lead }
    if short and long and long > .05 then rates[2] = long end
    local etas = {}
    for i, r in ipairs(rates) do etas[i] = (pct - thr) / r end
    table.sort(etas)
    -- a projection this far out (or from rates that disagree wildly) is not
    -- a forecast: shown as waiting, never as a huge or negative countdown
    if etas[1] > 300 then return nil, nil, nil, "waiting" end
    local hi = math.min(etas[#etas], 300)
    if hi > etas[1] * 3 + 10 then return nil, nil, nil, "waiting" end
    local mid = etas[1] + (hi - etas[1]) / 2
    return math.max(0, mid), math.max(0, etas[1]), math.max(0, hi), "eta"
end
-- which boss a threshold ability belongs to
function T:ThresholdGuid(ab)
    local E = self.encounter
    local best
    for guid in pairs(E.guids) do
        local npc = T.NpcID(guid)
        if not E.dead[guid] and (not ab.recNpc or npc == ab.recNpc) then best = guid end
    end
    return best
end
function T:UpdateThresholds()
    local E = self.encounter
    local now = GetTime()
    for _, ev in pairs(E.events) do
        if ev.threshold then
            local guid = self:ThresholdGuid(ev.ability)
            local eta, lo, hi, state = self:ThresholdETA(guid, ev.hp)
            if state ~= ev.state then ev.state = state; self:Changed() end
            if state == "eta" then
                -- hysteresis: small wobbles don't move the icon or re-sort
                local shown = ev.expires - now
                if not ev.etaAt or math.abs(eta - shown) > .5 or now - ev.etaAt > 1 then
                    ev.expires, ev.lo, ev.hi, ev.etaAt = now + eta, now + lo, now + hi, now
                    ev.total = math.max(ev.total or 0, eta)
                end
            elseif state == "reached" then
                ev.expires, ev.lo, ev.hi = now, nil, nil
            else
                ev.expires, ev.lo, ev.hi = now + 600, nil, nil
            end
        end
    end
end

-- ------------------------------------------------------------ combat log
local function hostileNpc(flags)
    -- COMBATLOG_OBJECT_REACTION_FRIENDLY = 0x10; players/pets are never bosses here
    return flags and (flags % 32) < 16
end
function T:ClearCast(guid)
    local E = self.encounter
    E.pending[guid] = nil
    self:CastStopped("cast:" .. guid)
end
function T:CLEU(_, event, sourceGUID, sourceName, sourceFlags, destGUID, _, _, spellId, spellName, _, a12, a13)
    local E = self.encounter
    if event == "SPELL_DAMAGE" then
        local npc = E and T.NpcID(sourceGUID)
        if npc and E.npcs[npc] then self:OnDamage(npc, spellId, spellName, destGUID, a12, a13) end
        return
    end
    if event == "SPELL_INTERRUPT" then
        -- the interrupted caster is the destination; an interrupted attempt
        -- is not a cast (no occurrence, no cooldown restart)
        if E and E.pending[destGUID] or (E and E.events["cast:" .. destGUID]) then
            -- the next cast of that spell comes after a recast, not a cooldown:
            -- the interval up to it is not a sample
            local p = E.pending[destGUID]
            local npc = T.NpcID(destGUID)
            local id = (p and p.id) or tonumber(a12)
            if npc and id then E.broken[npc .. ":" .. id] = true end
            self:ClearCast(destGUID)
        end
        return
    end
    if event == "UNIT_DIED" then
        if not E then return end
        if E.pending[destGUID] or E.events["cast:" .. destGUID] then self:ClearCast(destGUID) end
        if E.guids[destGUID] then
            E.dead[destGUID] = true
            -- with a boss mod attached, its kill message ends the fight
            -- (Northrend Beasts: the first boss dying is not the end)
            if E.modId or E.bwModule then return end
            for g in pairs(E.guids) do if not E.dead[g] then return end end
            E.killedAt = GetTime() -- wait a moment in case another boss joins
        end
        return
    end
    local code = CLEU_CODES[event]
    if not code then return end
    local npc = T.NpcID(sourceGUID)
    if not npc or not hostileNpc(sourceFlags) then return end
    if not E then
        if not self:IsKnownBoss(npc) or not (UnitAffectingCombat("player") or self:GroupInCombat()) then return end
        E = self:StartEncounter(npc, sourceGUID, sourceName, nil, "auto")
    elseif not E.allowed[npc] then
        -- a creature of this fight's DBM module joins it (Mimiron's vehicles,
        -- Halion's twilight form); a known boss joins a fight no boss mod
        -- owns; anything else is trash or an add
        if E.modCreatures and E.modCreatures[npc] then
            self:AddBoss(npc, sourceGUID, true)
        elseif not E.modId and not E.bwModule and self:IsKnownBoss(npc) then
            self:AddBoss(npc, sourceGUID)
        else
            return
        end
    elseif not E.npcs[npc] then
        self:AddBoss(npc, sourceGUID)
    elseif not E.guids[sourceGUID] then
        E.guids[sourceGUID] = true
    end
    -- creatures only a boss mod's engage message points at: nothing shown or learned
    if not E.trusted[npc] then return end
    local now = GetTime()
    if code == "S" then
        local _, icon, castTime = T.SpellInfo(spellId)
        castTime = (castTime or 0) / 1000
        E.pending[sourceGUID] = { id = spellId, name = spellName, t = now, icon = icon, npc = npc, ends = now + castTime }
        if castTime > 0 then self:CastStarted("cast:" .. sourceGUID, spellName, icon, spellId, now + castTime, castTime, sourceName, nil, npc) end
        self:ProviderCheck(nil, T.IdKey(spellId, spellName), castTime)
    elseif code == "C" then
        local p = E.pending[sourceGUID]
        E.pending[sourceGUID] = nil
        self:CastStopped("cast:" .. sourceGUID)
        if p and p.id == spellId then
            -- completes a cast started earlier: the occurrence is the start
            self:Occurrence(npc, sourceGUID, spellId, spellName, p.icon, p.t, "S")
        else
            self:Occurrence(npc, sourceGUID, spellId, spellName, select(2, T.SpellInfo(spellId)), now, "C")
        end
    elseif code == "U" then
        self:Occurrence(npc, sourceGUID, spellId, spellName, select(2, T.SpellInfo(spellId)), now, "U")
    end
    -- auras applied/removed are not casts: they are not observed
end
-- pending casts that finished without a logged success (and weren't interrupted)
function T:FlushPending()
    local E = self.encounter
    local now = GetTime()
    for guid, p in pairs(E.pending) do
        if now > p.ends + 1.5 then
            E.pending[guid] = nil
            self:Occurrence(p.npc, guid, p.id, p.name, p.icon, p.t, "S")
        end
    end
end

-- boss unit cast bars (exact timing, channels too)
function T:UnitCast(unit, event)
    local E = self.encounter
    if not E then return end
    local guid = UnitGUID(unit)
    if not guid or not (E.guids[guid] or E.npcs[T.NpcID(guid) or 0]) then return end
    E.unitOf[guid] = unit
    local name, _, _, icon, startMs, endMs = UnitCastingInfo(unit)
    if not name then name, _, _, icon, startMs, endMs = UnitChannelInfo(unit) end
    if name and endMs then
        self:CastStarted("cast:" .. guid, name, icon, nil, endMs / 1000, (endMs - startMs) / 1000, UnitName(unit), true)
    else
        if event == "UNIT_SPELLCAST_INTERRUPTED" or event == "UNIT_SPELLCAST_FAILED" then E.pending[guid] = nil end
        self:CastStopped("cast:" .. guid)
    end
end

-- ------------------------------------------------------------ ticking
function T:Update()
    local E = self.encounter
    if not E then return end
    local now = GetTime()
    self:FlushPending()
    for key, ev in pairs(E.events) do
        if ev.threshold then
            -- never "cast now" from an HP projection; warn once when it's close
        elseif not ev.paused and ev.expires <= now then
            if ev.source == "cast" then
                if now - ev.expires > .4 then E.events[key] = nil; self:Changed() end
            elseif ev.keep then
                ev.state = "soon"
            elseif ev.source == "predict" then
                if ev.state ~= "soon" then ev.state = "soon"; self:Changed() end
                if now - ev.expires > (ev.grace or 3) then E.events[key] = nil; self:Changed() end
            else
                if now - ev.expires > 1 then E.events[key] = nil; self:Changed() end
            end
        end
        -- imminent warning, once per occurrence (never replayed by an ETA wobbling around 5s)
        local occ = ev.occ or key
        if ev.source ~= "cast" and not E.warned[occ] and not ev.paused and ev.state ~= "waiting" and ev.state ~= "unknown"
            and ev.expires - now <= T.HIGHLIGHT and (ev.expires > now or ev.state == "reached") then
            E.warned[occ] = true
            local model = ev.ability and (K:Repeat(ev.ability.rec) or (ev.ability.cd and { cd = ev.ability.cd }))
            local every = model and model.cd or ev.total or 0
            if A.TimelineWarn and self:Visible(ev) and (ev.enrage or ev.threshold or every >= 12) then
                A:TimelineWarn("medium", ev.name, ev.icon, nil, ev.expires, ev.threshold and ev.hp)
            end
        end
    end
end

-- ------------------------------------------------------------ display list
-- Which entries show: importance and hide/pin, predictions switch, and one
-- source per ability (boss mod or local), casts we see live over boss mod
-- cast bars. Rebuilt only when something changed; remaining times are
-- refreshed by the display every frame.
function T:Visible(ev)
    if not self:Shows(ev) then return false end
    local E = self.encounter
    if ev.source == "predict" then
        -- owned by a boss mod: no local estimate unless the boss mod let go
        if ev.ability and self:Owner(ev) == "mod" and E.owner[self:ProvKey(ev.ability)] then return false end
    elseif ev.source == "dbm" or ev.source == "bigwigs" then
        -- both boss mods timing it: one entry (the preferred boss mod's)
        if self:LiveMod(ev.pkey) ~= ev then return false end
        -- our validated model wins where it has proven more accurate on this server
        for _, list in pairs(E.byKey or {}) do
            for _, ab in ipairs(list) do
                if self:ProvKey(ab) == ev.pkey then
                    local lev = E.events[ab.key]
                    if lev and lev.source == "predict" and self:Owner(lev) == "local" then return false end
                end
            end
        end
    end
    return true
end
local function byRemaining(a, b)
    if a.remaining ~= b.remaining then return a.remaining < b.remaining end
    return a.key < b.key
end
function T:DisplayList(now)
    local E = self.encounter
    local out = self.outBuf or {}
    self.outBuf = out
    for i = #out, 1, -1 do out[i] = nil end
    if not E then return out end
    now = now or GetTime()
    if self.cacheVersion ~= self.version or self.cacheGen ~= E.gen then
        local live
        for _, ev in pairs(E.events) do if ev.source == "cast" then live = live or {}; live[ev.name] = true end end
        local list = {}
        for _, ev in pairs(E.events) do
            -- a cast in progress replaces its boss mod cast bar and its own imminent countdown
            local dup = live and ev.source ~= "cast" and live[ev.name] and (ev.state == "cast" or (ev.source == "predict" and ev.expires - now < 10))
            if self:Visible(ev) and not dup then
                ev.danger = self:Danger(ev)
                list[#list + 1] = ev
            end
        end
        self.cache, self.cacheVersion, self.cacheGen = list, self.version, E.gen
    end
    for i, ev in ipairs(self.cache) do
        local rem = ev.paused or (ev.expires - now)
        if rem < 0 then rem = 0 end
        ev.remaining = rem
        out[i] = ev
    end
    table.sort(out, byRemaining)
    return out
end

-- ------------------------------------------------------------ driver
local function cleuError(err)
    A.lastError = "Boss Timeline: " .. tostring(err)
    table.insert(A.errorLog, 1, A.lastError)
    if #A.errorLog > 10 then table.remove(A.errorLog) end
end
frame:SetScript("OnEvent", function(_, event, ...)
    if event == "COMBAT_LOG_EVENT_UNFILTERED" then
        -- hot path: most combat log events are not ours; no allocation for them
        local sub = select(2, ...)
        if sub == "SPELL_DAMAGE" then
            -- the busiest event: only a tracked boss's own hits matter
            local E = T.encounter
            local npc = E and T.NpcID((select(3, ...)))
            if not npc or not E.npcs[npc] then return end
        end
        if CLEU_CODES[sub] or sub == "UNIT_DIED" or ((sub == "SPELL_DAMAGE" or sub == "SPELL_INTERRUPT") and T.encounter) then
            local ok, err = pcall(T.CLEU, T, ...)
            if not ok then cleuError(err) end
        end
        return
    end
    A:Run("Boss Timeline", T.OnEvent, T, event, ...)
end)
function T:OnEvent(event, ...)
    if event == "PLAYER_REGEN_DISABLED" then
        self.combatStart = GetTime()
        if self.encounter and self.encounter.source == "test" then self:EndEncounter("test") end
    end
    if event == "INSTANCE_ENCOUNTER_ENGAGE_UNIT" then self.engageTime = GetTime() end
    if event == "PLAYER_REGEN_DISABLED" or event == "INSTANCE_ENCOUNTER_ENGAGE_UNIT" then
        self:Listen(true)
        self:ScanUnits()
    elseif event == "PLAYER_REGEN_ENABLED" then
        if not self.encounter then self:Listen(false) end
    elseif event == "PLAYER_TARGET_CHANGED" or event == "PLAYER_FOCUS_CHANGED" then
        if UnitAffectingCombat("player") then self:ScanUnits() end
    elseif event:find("^UNIT_SPELLCAST") then
        local unit = ...
        if unit and (unit:find("^boss") or unit == "target" or unit == "focus") then self:UnitCast(unit, event) end
    elseif event == "PLAYER_ENTERING_WORLD" then
        if self.encounter then self:EndEncounter("zone") end
    end
end
local CAST_EVENTS = { "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_FAILED", "UNIT_SPELLCAST_INTERRUPTED",
    "UNIT_SPELLCAST_DELAYED", "UNIT_SPELLCAST_CHANNEL_START", "UNIT_SPELLCAST_CHANNEL_UPDATE", "UNIT_SPELLCAST_CHANNEL_STOP" }
function T:Listen(on)
    if on == self.listening then return end
    self.listening = on
    local fn = on and frame.RegisterEvent or frame.UnregisterEvent
    fn(frame, "COMBAT_LOG_EVENT_UNFILTERED")
    fn(frame, "PLAYER_TARGET_CHANGED")
    fn(frame, "PLAYER_FOCUS_CHANGED")
    for _, e in ipairs(CAST_EVENTS) do fn(frame, e) end
end
function T:Enable(on)
    on = on and true or false
    if on == self.enabled then return end
    self.enabled = on
    local fn = on and frame.RegisterEvent or frame.UnregisterEvent
    for _, e in ipairs({ "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "INSTANCE_ENCOUNTER_ENGAGE_UNIT", "PLAYER_ENTERING_WORLD" }) do fn(frame, e) end
    if on then
        if InCombatLockdown() or UnitAffectingCombat("player") then self:Listen(true); self:ScanUnits() end
    else
        self:Listen(false)
        if self.encounter then self:EndEncounter("disabled") end
    end
end
-- 10 Hz bookkeeping and 4 Hz health samples while a fight is tracked.
local acc, hpAcc, slow = 0, 0, 0
frame:SetScript("OnUpdate", function(_, elapsed)
    local E = T.encounter
    if not E then return end
    acc, hpAcc, slow = acc + elapsed, hpAcc + elapsed, slow + elapsed
    if hpAcc >= .25 and E.source ~= "test" then
        hpAcc = 0
        A:Run("Boss Timeline", function() T:SampleHealth(); T:UpdateThresholds() end)
    end
    if acc >= .1 then acc = 0; A:Run("Boss Timeline", T.Update, T) end
    if slow >= 1 then
        slow = 0
        A:Run("Boss Timeline", function()
            if not T.encounter or T.encounter.source == "test" then return end
            if T.encounter.killedAt and GetTime() - T.encounter.killedAt >= 3 then T:EndEncounter("kill"); return end
            if not T.listening then T:Listen(true) end
            if not T:GroupInCombat() then
                T.endCheck = (T.endCheck or 0) + 1
                if T.endCheck >= 3 then T:EndEncounter("combat") end
            else
                T.endCheck = nil
                T:ScanUnits()
            end
        end)
    end
end)

-- boss mods loaded later (load-on-demand BigWigs, DBM loading after us)
A:On("ADDON_LOADED", function()
    if not A.ready then return end
    T:HookDBM()
    T:HookBigWigs()
end)
function A:InitTimeline()
    self:TimelineDB()
    K:Init()
    T:HookDBM()
    T:HookBigWigs()
end
function A:ForgetLearnedTimings() K:ForgetAll() end
-- The player's decision about a creature, for this server and instance
-- (/br timeline boss | notboss, the one-time question, Encounter Details).
function T:RejectBoss(npc)
    local E = self.encounter
    if not E or not E.npcs[npc] then return end
    -- what it cast this pull is not boss evidence
    for k, o in pairs(E.obs) do if o.npc == npc then E.obs[k] = nil end end
    E.trusted[npc], E.npcs[npc], E.allowed[npc] = nil, nil, nil
    if E.modCreatures then E.modCreatures[npc] = nil end
    for guid in pairs(E.guids) do
        if T.NpcID(guid) == npc then E.guids[guid] = nil; E.pending[guid] = nil; E.events["cast:" .. guid] = nil end
    end
    local function drop(list)
        for k, l in pairs(list or {}) do
            for i = #l, 1, -1 do if l[i].casters and #l[i].casters == 1 and l[i].casters[1] == npc then table.remove(l, i) end end
            if #l == 0 then list[k] = nil end
        end
    end
    drop(E.byKey); drop(E.byName)
    for key, ab in pairs(E.abilities) do
        if ab.casters and #ab.casters == 1 and ab.casters[1] == npc then E.abilities[key] = nil; E.events[key] = nil end
    end
    -- nothing left that is a boss: the fight (and any boss mod module's bars) ends
    if not next(E.npcs) then self:EndEncounter("notboss") else self:Changed() end
end
function A:SetBossDecision(npc, name, isBoss)
    if not npc then return end
    K:SetBossDecision(npc, isBoss, name)
    if isBoss then
        if T.encounter then T:AddBoss(npc, nil, true)
        elseif UnitAffectingCombat("player") then T:StartEncounter(npc, nil, name, nil, "auto", true) end
        self:Print((name or "It") .. " is now treated as a boss here (Boss Timeline).")
    else
        T:RejectBoss(npc)
        self:Print((name or "It") .. " will not be treated as a boss here (Boss Timeline).")
    end
    if self.HideBossPrompt then self:HideBossPrompt(npc) end
    T:Changed()
end
function A:ConfirmBossTarget(isBoss)
    local npc = T.NpcID(UnitGUID("target"))
    if not npc or UnitIsPlayer("target") then self:Print("Target the creature first."); return end
    self:SetBossDecision(npc, UnitName("target"), isBoss ~= false)
end
