-- Boss Timeline knowledge: what this account has learned about boss
-- abilities on this server. Account-wide (BlizzUIRebornDB), independent of
-- layouts and characters.
--
-- Evidence rules (see README "Adaptive encounter knowledge"):
--  * Only real boss casts are evidence. Boss mod timers and our own
--    predictions never are; practice fights never are.
--  * Everything is kept per context: realm | instance type | difficulty.
--    Keys are creature ID + spell ID (no merging by spell name).
--  * In-fight observations are buffered and only written between pulls.
--  * Three layers per ability: candidate model -> validated/accepted model
--    (+ the previous accepted model for rollback). A candidate needs 5+
--    intervals over 3+ pulls, then is checked on 3+ later occurrences from
--    2+ later pulls it was not fitted on: small average error, 75%+ of them
--    within tolerance, and better than the current accepted model. No boss
--    mod is needed for this; boss mod timers are never samples. Accepted
--    models that keep missing go back to revalidation.
--  * Intervals broken by an interrupt, and gaps long enough to hide a
--    missed or skipped cast, are not samples; phase downtime never is.
--  * HP thresholds: learned as a health percentage (never as fight time),
--    only when the trigger health is stable across 3+ pulls while the time
--    it took varied; if both are stable it is ambiguous and not claimed.
local A = BlizzUIReborn
local K = {}
A.TimelineKB = K
local pairs, ipairs, type, tonumber, math, tostring = pairs, ipairs, type, tonumber, math, tostring

K.SCHEMA = 3
K.MAX_SAMPLES = 24
K.MIN_GAP = 4              -- shorter "intervals" are multi-hits of one cast
K.PROVISIONAL_GAPS = 3     -- in-pull provisional estimate
K.CANDIDATE_GAPS, K.CANDIDATE_PULLS = 5, 3
K.VALIDATE = 3             -- held-out occurrences before promotion
K.VALIDATE_PULLS = 2       -- ... from this many different later pulls
K.COVERAGE = .75           -- share of held-out occurrences within tolerance
K.FIRST_PULLS = 3
K.THRESHOLD_PULLS = 3

-- ------------------------------------------------------------ statistics
local function sorted(list, f)
    local t = {}
    for i = 1, #list do t[i] = f and f(list[i]) or list[i] end
    table.sort(t)
    return t
end
local function quantile(s, q)
    local n = #s
    if n == 0 then return nil end
    local pos = 1 + (n - 1) * q
    local lo = math.floor(pos)
    local hi = math.min(n, lo + 1)
    return s[lo] + (s[hi] - s[lo]) * (pos - lo)
end
local function median(list, f) return quantile(sorted(list, f), .5) end
local function mad(list, m, f)
    local d = {}
    for i = 1, #list do d[i] = math.abs((f and f(list[i]) or list[i]) - m) end
    return median(d) or 0
end
local function mean(list)
    if #list == 0 then return nil end
    local s = 0
    for i = 1, #list do s = s + list[i] end
    return s / #list
end
K.Median, K.Quantile, K.Mean, K.Sorted = median, quantile, mean, sorted
local function round(v, step) step = step or .1; return math.floor(v / step + .5) * step end
local function push(list, v, max)
    list[#list + 1] = v
    while #list > (max or K.MAX_SAMPLES) do table.remove(list, 1) end
end
local function V(s) return s[1] end

-- ------------------------------------------------------------ storage
function K:DB() return A:TimelineDB() end
local function isnum(v) return type(v) == "number" and v == v and math.abs(v) < 1e7 end
local function cleanList(list, width)
    if type(list) ~= "table" then return {} end
    local out = {}
    for _, s in ipairs(list) do
        if type(s) == "table" then
            local ok = true
            for i = 1, width do if not isnum(s[i]) then ok = false end end
            if ok then out[#out + 1] = s end
        end
    end
    while #out > K.MAX_SAMPLES do table.remove(out, 1) end
    return out
end
local function cleanModel(m)
    if type(m) ~= "table" then return nil end
    if m.kind == "repeat" or m.kind == "window" then
        if not (isnum(m.cd) and m.cd > 0) then return nil end
        -- a range must be numbers around the timing, or it is dropped
        if not (isnum(m.lo) and isnum(m.hi) and m.lo <= m.cd + 1e-6 and m.cd <= m.hi + 1e-6 and m.lo > 0) then
            if m.kind == "window" then return nil end
            m.lo, m.hi = nil, nil
        end
        if m.n ~= nil and not isnum(m.n) then m.n = nil end
        if m.pull ~= nil and not isnum(m.pull) then m.pull = nil end
        return m
    elseif m.kind == "threshold" then
        if isnum(m.hp) and m.hp > 0 and m.hp < 100 then return m end
    elseif m.kind == "first" then
        if isnum(m.t) and m.t > 0 and isnum(m.lo) and isnum(m.hi) then return m end
    end
end
K.CleanModel = cleanModel
local function cleanSlot(slot)
    slot.cand, slot.acc, slot.prev = cleanModel(slot.cand), cleanModel(slot.acc), cleanModel(slot.prev)
    slot.cv = cleanList(slot.cv, 3)          -- { candidate error, accepted error or -1, pull }
    if slot.audit ~= nil and slot.audit ~= true then slot.audit = nil end
    local l = {}
    for _, v in ipairs(type(slot.ae) == "table" and slot.ae or {}) do if isnum(v) then l[#l + 1] = v end end
    while #l > 8 do table.remove(l, 1) end
    slot.ae = l
    if slot.since ~= nil and not isnum(slot.since) then slot.since = nil end
end
-- Repairs anything malformed (hand-edited or damaged saved variables).
function K:CleanRec(rec)
    if type(rec) ~= "table" then return nil end
    rec.g = cleanList(rec.g, 2)          -- intervals { seconds, pull }
    rec.f = cleanList(rec.f, 2)          -- openers { seconds after pull, pull }
    rec.h = cleanList(rec.h, 3)          -- thresholds { hp %, seconds after pull, pull }
    rec.pe = type(rec.pe) == "table" and rec.pe or {}   -- boss-mod timer errors
    rec.le = type(rec.le) == "table" and rec.le or {}   -- our live forecast errors
    for _, k in ipairs({ "pe", "le" }) do
        local l = {}
        for _, v in ipairs(rec[k]) do if isnum(v) then l[#l + 1] = v end end
        while #l > 8 do table.remove(l, 1) end
        rec[k] = l
    end
    rec.first, rec.thr = cleanModel(rec.first), cleanModel(rec.thr)
    cleanSlot(rec)
    -- phase openers (samples) and their models, per phase
    local pf, pfm = {}, {}
    for p, list in pairs(type(rec.pf) == "table" and rec.pf or {}) do if type(p) == "string" then pf[p] = cleanList(list, 2) end end
    for p, m in pairs(type(rec.pfm) == "table" and rec.pfm or {}) do if type(p) == "string" then pfm[p] = cleanModel(m) end end
    rec.pf, rec.pfm = pf, pfm
    -- repeat models of later phases (phase 1 uses the record itself)
    local ph = {}
    for p, slot in pairs(type(rec.ph) == "table" and rec.ph or {}) do
        if type(p) == "string" and type(slot) == "table" then cleanSlot(slot); ph[p] = slot end
    end
    rec.ph = ph
    if type(rec.override) == "table" then
        if not (isnum(rec.override.cd) or isnum(rec.override.hp)) then rec.override = nil end
    else rec.override = nil end
    if type(rec.n) ~= "string" then rec.n = nil end
    if rec.useProvider ~= nil and rec.useProvider ~= true then rec.useProvider = nil end
    return rec
end
local function copy(v, depth)
    if type(v) ~= "table" then return v end
    if (depth or 0) > 12 then return nil end
    local t = {}
    for k, x in pairs(v) do t[k] = copy(x, (depth or 0) + 1) end
    return t
end
-- 0.6 -> 0.7: the built-in (DBM-derived) timings are gone. Validation
-- scores that compared against them are recalculated from fresh evidence;
-- the observed intervals, openers and thresholds they came from are kept.
-- A copy of the old records is kept once (timelineBackup) before changing.
function K:Backup(db)
    if not db.timelineBackup then
        db.timelineBackup = { schema = tonumber(db.schema) or 1, time = time and time() or 0, kb = copy(db.kb), bosses = copy(db.bosses), learned = copy(db.learned) }
    end
end
function K:MigrateV3(db)
    self:Backup(db)
    for _, bucket in pairs(db.kb) do
        if type(bucket) == "table" then
            for _, spells in pairs(bucket) do
                if type(spells) == "table" then
                    for _, rec in pairs(spells) do
                        if type(rec) == "table" then
                            if rec.useBaseline then rec.useProvider = true end
                            rec.useBaseline = nil
                            local slots = { rec }
                            for _, sl in pairs(type(rec.ph) == "table" and rec.ph or {}) do slots[#slots + 1] = sl end
                            for _, sl in ipairs(slots) do
                                if type(sl) == "table" then
                                    sl.cv, sl.ae = {}, {}           -- scored before, partly against the removed baseline
                                    if sl.acc then sl.audit = true end -- re-checked on the next observed casts
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    for _, b in pairs(db.bosses) do
        if type(b) == "table" and b.confirmed then b.legacy = true end
    end
end
function K:Init()
    local db = self:DB()
    -- a new account has nothing to migrate
    if db.schema == nil and type(db.learned) ~= "table" and not (type(db.kb) == "table" and next(db.kb)) and not (type(db.bosses) == "table" and next(db.bosses)) then
        db.schema = K.SCHEMA
    end
    db.kb = type(db.kb) == "table" and db.kb or {}
    db.bosses = type(db.bosses) == "table" and db.bosses or {}
    db.pull = tonumber(db.pull) or 0
    -- v1 (0.5.0-0.5.2): timings were stored without realm/difficulty, so
    -- they can't be trusted in any context: keep only which creatures are
    -- bosses and which of their spells are dangerous/AoE/summons.
    if (tonumber(db.schema) or 1) < K.SCHEMA then self:Backup(db) end
    if (tonumber(db.schema) or 1) < 2 then
        if type(db.learned) == "table" then
            for npc, L in pairs(db.learned) do
                if type(npc) == "number" and type(L) == "table" then
                    local b = self:Boss(npc, true)
                    b.name = b.name or L.name
                    if L.boss then b.confirmed = true end -- recognised (or confirmed) as a boss before
                    if type(L.spells) == "table" then
                        for name, s in pairs(L.spells) do
                            if type(s) == "table" and type(name) == "string" and isnum(s.id) and (s.deadly or s.aoe or s.summon) then
                                local fl = self:Flags(npc, s.id, name, true)
                                fl.deadly, fl.aoe, fl.summon = s.deadly or nil, s.aoe or nil, s.summon or nil
                            end
                        end
                    end
                end
            end
        end
        db.learned = nil
        db.schema = 2
    end
    if (tonumber(db.schema) or 1) < 3 then
        self:MigrateV3(db)
        db.schema = 3
    end
    -- validate and prune (a year unseen and not pinned by the player)
    local now = time and time() or 0
    for ctx, bucket in pairs(db.kb) do
        if type(bucket) ~= "table" or type(ctx) ~= "string" then db.kb[ctx] = nil
        else
            for npc, spells in pairs(bucket) do
                if type(spells) ~= "table" then bucket[npc] = nil
                else
                    for id, rec in pairs(spells) do
                        rec = self:CleanRec(rec)
                        if not rec or (rec.seen and now - rec.seen > 365 * 86400 and not rec.lock and not rec.override) then spells[id] = nil
                        else spells[id] = rec end
                    end
                end
            end
        end
    end
    for npc, b in pairs(db.bosses) do
        if type(b) ~= "table" then db.bosses[npc] = nil
        elseif b.decide ~= nil and type(b.decide) ~= "table" then b.decide = nil end
    end
end

-- realm | instance type | difficulty (3.3.5 raid difficulty encodes 10/25)
function K:Context()
    local realm = GetRealmName and GetRealmName() or "?"
    local _, kind = IsInInstance()
    local diff = GetInstanceDifficulty and GetInstanceDifficulty() or 1
    return realm .. "|" .. tostring(kind or "none") .. "|" .. tostring(diff)
end
-- where a "this is / is not a boss" decision applies: server + instance
-- (cached until the zone changes: it is read for every boss cast)
function K:DecisionContext()
    if self.decisionCtx then return self.decisionCtx end
    local realm = GetRealmName and GetRealmName() or "?"
    local zone = GetInstanceInfo and GetInstanceInfo() or nil
    if type(zone) ~= "string" or zone == "" then zone = GetRealZoneText and GetRealZoneText() or "?" end
    self.decisionCtx = realm .. "|" .. tostring(zone)
    return self.decisionCtx
end
for _, ev in ipairs({ "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA" }) do A:On(ev, function() K.decisionCtx = nil end) end
-- true / false (the player decided here) or nil (no decision)
function K:BossDecision(npc)
    local b = npc and self:DB().bosses[npc]
    if not b or type(b.decide) ~= "table" then return nil end
    local d = b.decide[self:DecisionContext()]
    if d == nil then return nil end
    return d and true or false
end
function K:SetBossDecision(npc, isBoss, name)
    local b = self:Boss(npc, true)
    b.decide = type(b.decide) == "table" and b.decide or {}
    b.decide[self:DecisionContext()] = isBoss and true or false
    if name then b.name = name end
    if not isBoss then b.confirmed, b.legacy = nil, nil end
end
function K:Boss(npc, create)
    local db = self:DB()
    local b = db.bosses[npc]
    if not b and create then b = { spells = {} }; db.bosses[npc] = b end
    if b and type(b.spells) ~= "table" then b.spells = {} end
    return b
end
-- per-creature ability flags (not per difficulty: a mechanic is a mechanic)
function K:Flags(npc, spellId, name, create)
    local b = self:Boss(npc, create)
    if not b then return nil end
    local f = b.spells[spellId]
    if not f and create then f = {}; b.spells[spellId] = f end
    if f and name then f.n = name end
    return f
end
function K:Rec(ctx, npc, spellId, create)
    local db = self:DB()
    local bucket = db.kb[ctx]
    if not bucket then
        if not create then return nil end
        bucket = {}; db.kb[ctx] = bucket
    end
    local spells = bucket[npc]
    if not spells then
        if not create then return nil end
        spells = {}; bucket[npc] = spells
    end
    local rec = spells[spellId]
    if not rec and create then rec = self:CleanRec({}); spells[spellId] = rec end
    return rec
end
function K:Recs(ctx, npc)
    local bucket = self:DB().kb[ctx]
    return bucket and bucket[npc] or nil
end

-- ------------------------------------------------------------ in-fight observations
-- E.obs[npc..":"..id] = { npc, id, name, icon, ev, occ = { { t, phase, phaseT, hp } ... } }
function K:Observe(E, npc, id, name, icon, code, t, hp, broken)
    local key = npc .. ":" .. id
    local o = E.obs[key]
    if not o then
        o = { npc = npc, id = id, name = name, icon = icon, ev = code, occ = {} }
        E.obs[key] = o
    end
    local last = o.occ[#o.occ]
    if last and t - last[1] < 3 then return o, false end -- one cast hitting several players
    -- { time, phase, time into the phase, boss health, phase stretch }
    -- broken: an interrupt came before it (the gap up to it is a recast)
    o.occ[#o.occ + 1] = { t, E.phase or 1, t - (E.phaseStart or E.start), hp, E.seg or 1, broken and true or nil }
    return o, true
end
-- clean in-pull intervals { seconds, phase }, within one phase stretch
-- (Anub'arak's phases 1,2,1: the two phase-1 stretches are not joined)
function K:PullGaps(o, phase, strict)
    local gaps = {}
    for i = 2, #o.occ do
        local a, b = o.occ[i - 1], o.occ[i]
        if (a[5] or 1) == (b[5] or 1) and (not phase or b[2] == phase) and not b[6] then
            local g = b[1] - a[1]
            if g >= K.MIN_GAP then gaps[#gaps + 1] = { g, b[2] } end
        end
    end
    -- strict (for learning): a gap about twice the others hides a missed or
    -- skipped cast (out of range, boss immune or busy): not a cooldown sample
    if strict and #gaps >= 3 then
        local m = median(gaps, V)
        local out = {}
        for _, g in ipairs(gaps) do if g[1] < m * 1.8 then out[#out + 1] = g end end
        gaps = out
    end
    return gaps
end
-- Provisional estimate inside one pull: the last 3 clean intervals agree.
function K:Provisional(o, phase)
    local gaps = self:PullGaps(o, phase)
    if #gaps < K.PROVISIONAL_GAPS then return nil end
    local last = {}
    for i = #gaps - K.PROVISIONAL_GAPS + 1, #gaps do last[#last + 1] = gaps[i][1] end
    local m = median(last)
    if m < 6 then return nil end
    for _, g in ipairs(last) do if math.abs(g - m) > math.max(1.5, m * .15) then return nil end end
    return m
end

-- ------------------------------------------------------------ models
local function distinctPulls(list, col)
    local seen, n = {}, 0
    for _, s in ipairs(list) do if not seen[s[col]] then seen[s[col]] = true; n = n + 1 end end
    return n
end
-- repeat model (tight) or window model (bounded variation), or nil
function K:FitRepeat(gaps)
    if #gaps < K.CANDIDATE_GAPS or distinctPulls(gaps, 2) < K.CANDIDATE_PULLS then return nil end
    local s = sorted(gaps, V)
    local m = quantile(s, .5)
    local lo, hi = quantile(s, .1), quantile(s, .9)
    if m < 6 then return nil end
    if hi - lo <= math.max(3, m * .15) and mad(gaps, m, V) <= math.max(1.5, m * .07) then
        return { kind = "repeat", cd = round(m), lo = round(lo), hi = round(hi), n = #gaps }
    end
    if hi - lo <= math.max(8, m * .6) then
        return { kind = "window", cd = round(lo), lo = round(lo), hi = round(hi), n = #gaps }
    end
    return nil -- unstructured: no timing claim
end
function K:FitFirst(firsts)
    if distinctPulls(firsts, 2) < K.FIRST_PULLS then return nil end
    local m = median(firsts, V)
    if mad(firsts, m, V) > math.max(2, m * .15) then return nil end
    local s = sorted(firsts, V)
    return { kind = "first", t = round(m), lo = round(s[1]), hi = round(s[#s]) }
end
-- hp samples { hp, t, pull }: a health threshold when the health at the cast
-- is stable while the time it took varied, and the boss had clearly lost
-- health (an early timed ability on a slow-dropping boss is not a threshold)
function K:FitThreshold(hps)
    if distinctPulls(hps, 3) < K.THRESHOLD_PULLS then return nil, nil end
    local hs, ts = sorted(hps, V), sorted(hps, function(s) return s[2] end)
    local hSpread, tSpread = hs[#hs] - hs[1], ts[#ts] - ts[1]
    local hMed, tMed = quantile(hs, .5), quantile(ts, .5)
    if hs[#hs] > 95 or hSpread > 4 then return nil, nil end
    if tSpread < math.max(8, tMed * .2) then return nil, "ambiguous" end
    -- if it were timed, health at the cast would spread by about rate * time spread
    local rate = (100 - hMed) / math.max(tMed, 1)
    if hSpread > .35 * rate * tSpread then return nil, nil end
    -- the trigger was crossed at or above the highest health seen at the cast
    return { kind = "threshold", hp = round(hs[#hs], .5), lo = round(hs[1], .5), n = #hps }, nil
end
-- error of a model on one interval (inside a window counts as right)
local function err(model, g)
    if model.kind == "window" and model.lo and model.hi then
        if g < model.lo then return model.lo - g elseif g > model.hi then return g - model.hi end
        return 0
    end
    return math.abs(g - model.cd)
end
K.Err = err
local function center(m) return (m.kind == "window" and m.lo and m.hi) and (m.lo + m.hi) / 2 or m.cd end
local function similar(a, b)
    return a.kind == b.kind and math.abs(center(a) - center(b)) <= math.max(1, center(a) * .12)
end
-- Repeat models live per phase: phase 1 in the record, later phases in rec.ph.
function K:Slot(rec, phase, create)
    if not phase or phase == 1 then return rec end
    local k = tostring(phase)
    if not rec.ph then
        if not create then return nil end
        rec.ph = {}
    end
    local slot = rec.ph[k]
    if not slot and create then slot = { cv = {}, ae = {} }; rec.ph[k] = slot end
    return slot
end

-- Called once per pull, after the fight: fold the buffered observations in.
function K:Commit(E)
    local db = self:DB()
    if not db.learn or E.source == "test" then return end
    local ctx, pull = E.ctx, E.pull
    local now = time and time() or 0
    for _, o in pairs(E.obs) do
        local rec = self:Rec(ctx, o.npc, o.id, true)
        rec.n, rec.icon, rec.ev, rec.seen = o.name, o.icon or rec.icon, rec.ev or o.ev, now
        rec.pulls = (rec.pulls or 0) + 1
        local phases = {}
        -- intervals inside one phase stretch only (downtime is not a cooldown)
        for _, gp in ipairs(self:PullGaps(o, nil, true)) do
            local g, phase = gp[1], gp[2]
            local slot = self:Slot(rec, phase, true)
            local cand, acc = slot.cand, slot.acc
            -- held-out validation: models fitted on earlier pulls only
            if cand and (cand.pull or 0) < pull then
                push(slot.cv, { err(cand, g), acc and err(acc, g) or -1, pull }, 12)
            end
            if acc and (acc.pull or 0) < pull then push(slot.ae, err(acc, g), 8) end
            push(rec.g, { round(g), pull, phase })
            phases[phase] = true
        end
        -- opener (phase 1 from the pull) and phase openers
        local firstOcc = o.occ[1]
        if firstOcc and not E.late then
            if firstOcc[2] == 1 and firstOcc[5] == 1 then push(rec.f, { round(firstOcc[1] - E.start), pull })
            elseif E.phaseKnown and firstOcc[2] ~= 1 then
                local p = tostring(firstOcc[2])
                rec.pf[p] = rec.pf[p] or {}
                push(rec.pf[p], { round(firstOcc[3]), pull })
            end
            if firstOcc[4] then push(rec.h, { round(firstOcc[4], .5), round(firstOcc[1] - E.start), pull }) end
        end
        -- filler: cast again and again within seconds
        local n = #o.occ
        if n >= 4 and o.occ[n][1] - o.occ[n - 3][1] < 24 then
            local f = self:Flags(o.npc, o.id, o.name, true)
            f.filler = true
        end
        local pk = E.aliases and E.aliases["id:" .. o.id] or ("id:" .. o.id)
        for _, e in ipairs(E.perr[pk] or {}) do push(rec.pe, e, 8) end
        for _, e in ipairs(E.lerr[o.npc .. ":" .. o.id] or {}) do push(rec.le, e, 8) end
        self:Refit(rec, pull, phases)
    end
end

-- Candidate -> accepted, revalidation (per phase slot), openers, thresholds.
function K:RefitSlot(rec, slot, phase, pull)
    local since = slot.since or 0
    local gaps = {}
    for _, s in ipairs(rec.g) do
        if s[2] >= since and (s[3] or 1) == phase then gaps[#gaps + 1] = s end
    end
    local fit = self:FitRepeat(gaps)
    if fit then
        fit.pull = pull
        local c = slot.cand
        -- a clearly different fit restarts validation; a similar one keeps its
        -- timing (fitted before the validation samples) and only widens its range
        if not c or not similar(c, fit) then
            slot.cand, slot.cv = fit, {}
        else
            c.lo, c.hi, c.n = math.min(c.lo or c.cd, fit.lo), math.max(c.hi or c.cd, fit.hi), fit.n
            if c.kind == "window" then c.cd = c.lo end
        end
    end
    local c = slot.cand
    if c and not rec.lock and #slot.cv >= K.VALIDATE and distinctPulls(slot.cv, 3) >= K.VALIDATE_PULLS then
        local tol = math.max(1.5, center(c) * .15)
        local ce, ae, an, within = 0, 0, 0, 0
        for _, v in ipairs(slot.cv) do
            ce = ce + v[1]
            if v[1] <= tol then within = within + 1 end
            if v[2] >= 0 then ae = ae + v[2]; an = an + 1 end
        end
        ce = ce / #slot.cv
        -- absolute accuracy and coverage on occurrences it was not fitted on
        local good = ce <= tol and within / #slot.cv >= K.COVERAGE
        local ok = good
        if an > 0 then ok = ok and ce <= (ae / an) * .7 + .25 end          -- and better than the current accepted model
        local acc = slot.acc
        if acc and similar(acc, c) and good then ok = true end             -- confirms it
        if ok then
            if acc and not similar(acc, c) then slot.prev = acc end
            c.accepted = pull
            slot.acc, slot.cand, slot.cv, slot.ae, slot.reval, slot.audit = c, nil, {}, {}, nil, nil
        end
    end
    -- carried over from 0.6: confirmed again by 3 observed intervals, else revalidated below
    if slot.audit and slot.acc and #slot.ae >= 3 and mean(slot.ae) <= math.max(1.5, center(slot.acc) * .15) then slot.audit = nil end
    -- accepted model keeps missing: revalidate (kept as "previous" for rollback)
    local acc = slot.acc
    if acc and not rec.lock and #slot.ae >= 4 then
        local m = mean(slot.ae)
        if m > math.max(3, center(acc) * .25) then
            slot.prev, slot.acc, slot.ae = acc, nil, {}
            slot.reval, slot.since, slot.audit = true, pull, nil
        end
    end
end
function K:Refit(rec, pull, phases)
    phases = phases or { [1] = true }
    for phase in pairs(phases) do self:RefitSlot(rec, self:Slot(rec, phase, true), phase, pull) end
    -- openers/thresholds: after a server change, old ones stay until 3 new
    -- pulls either confirm a replacement or show there is none
    local since = rec.fsince or 0
    local function after(list, col)
        local out = {}
        for _, s in ipairs(list) do if s[col] >= since then out[#out + 1] = s end end
        return out
    end
    local f, h = after(rec.f, 2), after(rec.h, 3)
    local nf = self:FitFirst(f)
    if nf or distinctPulls(f, 2) >= K.FIRST_PULLS then rec.first = nf end
    local pfm = rec.pfm or {}
    for p, list in pairs(rec.pf) do
        local l = after(list, 2)
        local m = self:FitFirst(l)
        if m or distinctPulls(l, 2) >= K.FIRST_PULLS then pfm[p] = m end
    end
    rec.pfm = pfm
    local nt, amb = self:FitThreshold(h)
    if nt or distinctPulls(h, 3) >= K.THRESHOLD_PULLS then rec.thr, rec.ambiguous = nt, amb end
end

-- What should be believed about this ability now (manual beats everything).
function K:Repeat(rec, phase)
    if not rec then return nil end
    if rec.override and rec.override.cd then return { kind = "repeat", cd = rec.override.cd, manual = true } end
    local slot = self:Slot(rec, phase)
    return slot and slot.acc, slot and (slot.reval or slot.audit)
end
function K:Threshold(rec)
    if not rec then return nil end
    if rec.override and rec.override.hp then return { kind = "threshold", hp = rec.override.hp, manual = true } end
    return rec.thr
end
function K:First(rec, phase)
    if not rec then return nil end
    if not phase or phase == 1 then return rec.first end
    return rec.pfm and rec.pfm[tostring(phase)] or nil
end
-- boss mod vs our accepted model, from their real errors on this server
function K:PrefersLocal(rec)
    if not rec or not rec.acc or rec.reval then return false end
    if #rec.pe < 3 or #rec.le < 3 then return false end
    local p, l = mean(rec.pe), mean(rec.le)
    return l <= p * .7 and p - l >= 1
end

-- ------------------------------------------------------------ player controls
function K:Lock(rec, on) rec.lock = on and true or nil end
-- Rolling back sticks: the newer timing only returns on fresh evidence.
function K:Rollback(rec, phase)
    local slot = self:Slot(rec, phase)
    if slot and slot.prev then
        slot.acc, slot.prev = slot.prev, slot.acc
        slot.reval, slot.audit = nil, nil
        slot.cand, slot.cv, slot.ae = nil, {}, {}
        slot.since = self:DB().pull + 1
        return true
    end
    return false
end
-- show the boss mod's timer for this ability even where the learned one is better
function K:UseProvider(rec, on) rec.useProvider = on and true or nil end
function K:Override(rec, what, value)
    if value == nil then
        if rec.override then rec.override[what] = nil end
        if rec.override and not rec.override.cd and not rec.override.hp then rec.override = nil end
        return
    end
    rec.override = rec.override or {}
    rec.override[what] = value
end
-- A server patch/ruleset change: stage replacements, keep the old models
-- (labelled as revalidating) until new ones are validated.
function K:MarkServerChange()
    local db = self:DB()
    db.serverChange = db.pull
    for _, bucket in pairs(db.kb) do
        for _, spells in pairs(bucket) do
            for _, rec in pairs(spells) do
                local slots = { rec }
                for _, sl in pairs(rec.ph or {}) do slots[#slots + 1] = sl end
                for _, sl in ipairs(slots) do
                    sl.since = db.pull + 1
                    if sl.acc then sl.reval = true end
                    sl.cand, sl.cv, sl.ae = nil, {}, {}
                end
                rec.fsince = db.pull + 1
            end
        end
    end
end
function K:ForgetSpell(npc, id)
    local db = self:DB()
    for _, bucket in pairs(db.kb) do if bucket[npc] then bucket[npc][id] = nil end end
    local b = self:Boss(npc)
    if b then b.spells[id] = nil end
end
function K:ForgetBoss(npc)
    local db = self:DB()
    for _, bucket in pairs(db.kb) do bucket[npc] = nil end
    db.bosses[npc] = nil
end
-- Forget learned timings and learned flags. Kept: which creatures are
-- bosses (game flags and the player's decisions), hidden and pinned abilities.
function K:ForgetAll()
    local db = self:DB()
    db.kb = {}
    for _, b in pairs(db.bosses) do
        if type(b) == "table" then
            for id, f in pairs(b.spells or {}) do
                if type(f) == "table" and not f.pin then b.spells[id] = nil
                elseif type(f) == "table" then f.deadly, f.aoe, f.summon, f.filler = nil, nil, nil, nil end
            end
        end
    end
end

-- ------------------------------------------------------------ share (data only)
-- A tiny serializer/parser for plain data. Never loads code.
local function ser(v, out)
    local t = type(v)
    if t == "number" then out[#out + 1] = string.format("%.6g", v)
    elseif t == "boolean" then out[#out + 1] = v and "T" or "F"
    elseif t == "string" then out[#out + 1] = "s" .. #v .. ":" .. v
    elseif t == "table" then
        out[#out + 1] = "{"
        for k, x in pairs(v) do
            if (type(k) == "string" or type(k) == "number") and type(x) ~= "function" then ser(k, out); ser(x, out) end
        end
        out[#out + 1] = "}"
    end
end
function K.Serialize(v) local out = {}; ser(v, out); return table.concat(out, " ") end
function K.Deserialize(text)
    local pos, depth = 1, 0
    local function skip() while text:sub(pos, pos) == " " do pos = pos + 1 end end
    local parse
    parse = function()
        skip()
        local c = text:sub(pos, pos)
        if c == "{" then
            depth = depth + 1
            if depth > 12 then error("too deep") end
            pos = pos + 1
            local t = {}
            while true do
                skip()
                if text:sub(pos, pos) == "}" then pos = pos + 1; depth = depth - 1; return t end
                if pos > #text then error("unterminated") end
                local k = parse()
                if type(k) ~= "string" and type(k) ~= "number" then error("bad key") end
                t[k] = parse()
            end
        elseif c == "T" or c == "F" then pos = pos + 1; return c == "T"
        elseif c == "s" then
            local len, after = text:match("^s(%d+):()", pos)
            len = tonumber(len)
            if not len or len > 200 then error("bad string") end
            pos = after + len
            return text:sub(after, after + len - 1)
        else
            local num, after = text:match("^([%-%d%.eE+]+)()", pos)
            if not num or not tonumber(num) then error("bad value") end
            pos = after
            return tonumber(num)
        end
    end
    local ok, v = pcall(parse)
    if not ok then return nil, tostring(v) end
    return v
end
-- Export: this account's validated models only (learned from observed
-- casts), per creature and context. No raw samples, no boss mod timings,
-- no imported candidates that were never validated here.
K.EXPORT_MAX_BOSSES, K.EXPORT_MAX_SPELLS = 60, 120
function K:Export(npcs)
    if type(npcs) == "number" then npcs = { [npcs] = true } end
    local db = self:DB()
    local out = { v = K.SCHEMA, src = "observed", bosses = {} }
    local nb = 0
    for npc in pairs(npcs) do
        if nb >= K.EXPORT_MAX_BOSSES then break end
        nb = nb + 1
        local one = { name = (db.bosses[npc] or {}).name, ctx = {} }
        for ctx, bucket in pairs(db.kb) do
            if bucket[npc] then
                local spells, ns = {}, 0
                for id, rec in pairs(bucket[npc]) do
                    local m = rec.acc
                    -- only models validated here (not carried over, not being re-checked)
                    if m and not rec.audit and not rec.reval and ns < K.EXPORT_MAX_SPELLS then
                        ns = ns + 1
                        spells[id] = { n = rec.n, acc = { kind = m.kind, cd = m.cd, lo = m.lo, hi = m.hi, n = m.n } }
                    end
                end
                if ns > 0 then one.ctx[ctx] = spells end
            end
        end
        out.bosses[npc] = one
    end
    return "BRK3:" .. self.Serialize(out)
end
-- Import: data only (never code). Models become candidates that must
-- validate on this account's own observed casts before they are used.
function K:Import(text)
    text = A.Trim(text or "")
    local ver = text:sub(1, 5)
    if ver ~= "BRK1:" and ver ~= "BRK2:" and ver ~= "BRK3:" then return nil, "Not a BlizzUI Reborn boss data string." end
    if #text > 60000 then return nil, "That string is too long." end
    local data, e = self.Deserialize(text:sub(6))
    if type(data) ~= "table" then return nil, "Damaged boss data." .. (e and (" (" .. e .. ")") or "") end
    local bosses = data.bosses
    if ver == "BRK1:" and type(data.npc) == "number" then bosses = { [data.npc] = { name = data.name, ctx = data.ctx } } end
    if type(bosses) ~= "table" then return nil, "Damaged boss data." end
    local n, nb = 0, 0
    for npc, one in pairs(bosses) do
        nb = nb + 1
        if nb > K.EXPORT_MAX_BOSSES then return nil, "Too many bosses in one string." end
        if type(npc) == "number" and npc > 0 and npc < 1e6 and npc == math.floor(npc) and type(one) == "table" and type(one.ctx) == "table" then
            for ctx, spells in pairs(one.ctx) do
                if type(ctx) == "string" and #ctx < 80 and ctx:find("|", 1, true) and type(spells) == "table" then
                    local ns = 0
                    for id, m in pairs(spells) do
                        ns = ns + 1
                        if ns > K.EXPORT_MAX_SPELLS then break end
                        local model = type(id) == "number" and id > 0 and id < 1e7 and type(m) == "table" and cleanModel(copy(m.acc))
                        if model and (model.kind == "repeat" or model.kind == "window") and model.cd <= 900 then
                            local rec = self:Rec(ctx, npc, id, true)
                            rec.n = rec.n or (type(m.n) == "string" and #m.n <= 80 and m.n or nil)
                            if not rec.acc or not similar(rec.acc, model) then
                                rec.cand = { kind = model.kind, cd = model.cd, lo = model.lo, hi = model.hi, n = 0, pull = self:DB().pull, imported = true }
                                rec.cv = {}
                                n = n + 1
                            end
                        end
                    end
                end
            end
            -- known by name only; it is still detected as a boss the usual ways
            local b = self:Boss(npc, true)
            b.name = b.name or (type(one.name) == "string" and #one.name <= 80 and one.name or nil)
        end
    end
    return n
end
