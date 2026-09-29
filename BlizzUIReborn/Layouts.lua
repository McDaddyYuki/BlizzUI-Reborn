local A = BlizzUIReborn
local function finite(n) return type(n) == "number" and n == n and math.abs(n) < 1e6 end
A.PRESETS = { "Modern", "Classic" }
local VALID_POINTS = { TOPLEFT = 1, TOP = 1, TOPRIGHT = 1, LEFT = 1, CENTER = 1, RIGHT = 1, BOTTOMLEFT = 1, BOTTOM = 1, BOTTOMRIGHT = 1 }
A.VALID_POINTS = VALID_POINTS

-- v2: the Buffs element is anchored by ConsolidatedBuffs instead of BuffFrame
A.LAYOUT_VERSION = 2
local function emptyLayout(base) return { frames = {}, status = true, compartment = true, base = base or "Classic", v = A.LAYOUT_VERSION } end

function A:InitDB()
    if type(BlizzUIRebornDB) ~= "table" then BlizzUIRebornDB = {} end
    if type(BlizzUIRebornCharDB) ~= "table" then BlizzUIRebornCharDB = {} end
    local db, char = BlizzUIRebornDB, BlizzUIRebornCharDB
    self.db, self.char = db, char
    self.upgradedFromV1 = (db.version == 1 or char.version == 1)
    db.layouts = type(db.layouts) == "table" and db.layouts or {}
    char.layouts = type(char.layouts) == "table" and char.layouts or {}
    db.editor = type(db.editor) == "table" and db.editor or {}
    local e = db.editor
    if e.grid == nil then e.grid = true end
    if e.snap == nil then e.snap = true end
    if e.advanced == nil then e.advanced = true end
    e.spacing = A.Clamp(tonumber(e.spacing) or 40, 20, 200)
    e.previews = type(e.previews) == "table" and e.previews or {}
    db.style = nil -- 0.3.0 art options (removed)
    -- v1 (0.1/0.2) stored screen fractions; convert lazily once elements bind.
    for _, store in ipairs({ db.layouts, char.layouts }) do
        for name, layout in pairs(store) do
            if type(layout) ~= "table" then store[name] = nil
            else
                layout.frames = type(layout.frames) == "table" and layout.frames or {}
                if layout.status == nil then layout.status = true end
                if layout.compartment == nil then layout.compartment = true end
                layout.base = layout.base or "Classic"
            end
        end
    end
    db.version, char.version = 2, 2
    if type(db.defaultLayout) == "string" and not db.layouts[db.defaultLayout] then db.defaultLayout = nil end
    -- Characters follow the account's default layout until they pick one
    -- themselves ("follow"), and keep following it when the default changes.
    if char.layoutMode ~= "follow" and char.layoutMode ~= "chosen" then
        -- migration: 0.5.2 marked explicit picks with char.chosen; earlier builds
        -- marked nothing, so an account layout other than the default was a
        -- manual pick and is kept
        local act = char.active
        if char.chosen then char.layoutMode = "chosen"
        elseif type(act) ~= "table" or not act.name or (act.scope == "preset" and act.name == "Modern")
            or (act.scope == "account" and act.name == db.defaultLayout) then char.layoutMode = "follow"
        else char.layoutMode = "chosen" end
    end
    char.chosen = nil
    if char.layoutMode == "follow" then
        if db.defaultLayout then char.active = { scope = "account", name = db.defaultLayout }
        else char.active = { scope = "preset", name = "Modern" } end
    end
    local act = char.active
    if act.scope ~= "preset" and not self:Store(act.scope)[act.name] then char.active = { scope = "preset", name = "Modern" } end
    if act.scope == "preset" and act.name ~= "Modern" and act.name ~= "Classic" then act.name = "Modern" end
end

function A:Store(scope) return scope == "account" and self.db.layouts or self.char.layouts end
function A:IsPreset() return self.char.active.scope == "preset" end
function A:ActiveName() return self.char.active.name end

-- ----------------------------------------------------------------- presets
-- Positions are anchor, x, y in UIParent units (768-unit tall reference).
-- The Modern preset follows the default Retail (The War Within) layout.
A.ModernPositions = {
    action1 = { "BOTTOM", 0, 26 }, action2 = { "BOTTOM", 0, 66 }, action3 = { "BOTTOM", 0, 106 },
    action4 = { "RIGHT", -4, -50 }, action5 = { "RIGHT", -46, -50 },
    stance = { "BOTTOM", -175, 148 }, possess = { "BOTTOM", -175, 148 }, petbar = { "BOTTOM", 175, 148 }, totems = { "BOTTOM", -175, 146 },
    cast = { "BOTTOM", 0, 192 },
    player = { "BOTTOM", -290, 208 }, target = { "BOTTOM", 290, 208 }, focus = { "BOTTOM", -340, 330 },
    party = { "TOPLEFT", 16, -210 },
    buffs = { "TOPRIGHT", -197, -12 }, minimap = { "TOPRIGHT", -12, -10 }, objectives = { "TOPRIGHT", -92, -262 },
    chat = { "BOTTOMLEFT", 34, 36 }, statusbars = { "BOTTOM", 0, 3 },
    micro = { "BOTTOMRIGHT", -6, 4 }, bags = { "BOTTOMRIGHT", -8, 52 },
}
A.ModernSettings = {
    action1 = { hideArt = true, padding = 4 }, action2 = { padding = 4 }, action3 = { padding = 4 },
    action4 = { orientation = "vertical", padding = 4 }, action5 = { orientation = "vertical", padding = 4 },
    micro = { scale = 80, padding = -2 }, bags = { scale = 85, padding = 4 }, cast = { time = true },
    statusbars = { scale = 50 }, objectives = { height = 420 },
}
function A:PresetData(name)
    local data = emptyLayout(name)
    if name == "Modern" then
        for _, id in ipairs(self.order) do
            local def = self.elements[id]
            local pos = self.ModernPositions[id]
            if pos and self:BindElement(def) then
                local entry = self:DefaultSettings(def)
                for k, v in pairs(self.ModernSettings[id] or {}) do entry[k] = v end
                entry.point, entry.x, entry.y = pos[1], pos[2], pos[3]
                data.frames[id] = entry
            end
        end
    end
    if name == "Modern" and self.elements.paging and self:BindElement(self.elements.paging) then
        data.frames.paging = { enabled = false, scale = 100 } -- Retail has no page arrows
    end
    return data
end

-- ----------------------------------------------------------------- loading
function A:StoredActive()
    local act = self.char.active
    if act.scope == "preset" then return self:PresetData(act.name) end
    return self:Store(act.scope)[act.name]
end
function A:LoadActive()
    local data = self:StoredActive() or self:PresetData("Modern")
    self:MigrateLayout(data)
    self.saved = A.Copy(data)
    self.draft = A.Copy(data)
    self.dirty = false
end
function A:MarkDirty()
    self.dirty = not A.Equal(self.draft, self.saved)
    if self.RefreshEditor then self:RefreshEditor() end
end
-- The first account-wide layout the player uses becomes the default for
-- their other characters (changeable from the layout's gear menu).
function A:NoteLayoutUse(scope, name)
    if not self.followingDefault then self.char.layoutMode = "chosen" end
    if scope == "account" and not self.db.defaultLayout then self.db.defaultLayout = name end
end
-- Go back to following the account default (from the layout menu).
function A:FollowDefault()
    if A.Combat() then return nil, "Not available in combat." end
    local target = self.db.defaultLayout
    self.followingDefault = true
    local ok, err
    if target then ok, err = self:LoadLayout("account", target) else ok, err = self:LoadPreset("Modern") end
    self.followingDefault = nil
    self.char.layoutMode = "follow"
    if self.OnLayoutChanged then self:OnLayoutChanged() end
    return ok, err
end
function A:SetDefaultLayout(name)
    if name and not self.db.layouts[name] then return nil, "Only account-wide layouts can be used on every character." end
    self.db.defaultLayout = name
    return true
end
-- Moves a character-only layout to the account so every character sees it.
function A:MakeAccountWide(name)
    local layout = self.char.layouts[name]
    if not layout then return nil, "That layout no longer exists." end
    if self.db.layouts[name] then return nil, "An account-wide layout named \"" .. name .. "\" already exists. Rename one first." end
    self.db.layouts[name], self.char.layouts[name] = layout, nil
    local act = self.char.active
    if act.scope == "character" and act.name == name then act.scope = "account" end
    if not self.db.defaultLayout then self.db.defaultLayout = name end
    if self.OnLayoutChanged then self:OnLayoutChanged() end
    return true
end
local function activate(self, scope, name)
    self.selected = nil; self.drag = nil
    self.char.active = { scope = scope, name = name }
    self:NoteLayoutUse(scope, name)
    self:LoadActive()
    self:ApplyAll(true)
    self:MarkDirty()
    if self.OnLayoutChanged then self:OnLayoutChanged() end
    return true
end
function A:LoadPreset(name)
    if A.Combat() then return nil, "Not available in combat." end
    if name ~= "Modern" and name ~= "Classic" then return nil, "Unknown preset." end
    return activate(self, "preset", name)
end
function A:LoadLayout(scope, name)
    if A.Combat() then return nil, "Not available in combat." end
    if not self:Store(scope)[name] then return nil, "That layout no longer exists." end
    return activate(self, scope, name)
end

-- ----------------------------------------------------------------- editing
function A:ValidName(name)
    name = A.Trim(name)
    if #name == 0 then return nil, "Enter a layout name." end
    if #name > 32 then return nil, "Layout names can be at most 32 characters." end
    if name:find("[%c|]") then return nil, "Layout names cannot contain | or control characters." end
    if name == "Modern" or name == "Classic" then return nil, "That name is reserved for a preset." end
    return name
end
function A:NameTaken(name)
    return self.db.layouts[name] ~= nil or self.char.layouts[name] ~= nil
end
-- Creates a layout from `data` (default: the current draft) and activates it.
function A:CreateLayout(name, characterSpecific, data)
    if A.Combat() then return nil, "Not available in combat." end
    local valid, err = self:ValidName(name)
    if not valid then return nil, err end
    if self:NameTaken(valid) then return nil, "A layout named \"" .. valid .. "\" already exists." end
    local scope = characterSpecific and "character" or "account"
    local layout = A.Copy(data or self.draft)
    if self:IsPreset() and not data then layout.base = self.char.active.name end
    layout.base = layout.base or "Classic"
    self:Store(scope)[valid] = layout
    self.char.active = { scope = scope, name = valid }
    self:NoteLayoutUse(scope, valid)
    self.saved = A.Copy(layout); self.draft = A.Copy(layout)
    self:ApplyAll()
    self:MarkDirty()
    if self.OnLayoutChanged then self:OnLayoutChanged() end
    return true
end
function A:Save()
    if A.Combat() then return nil, "Not available in combat." end
    if self:IsPreset() then return nil, "Preset layouts cannot be changed. Save as a new layout." end
    local act = self.char.active
    self:Store(act.scope)[act.name] = A.Copy(self.draft)
    self.saved = A.Copy(self.draft)
    self:MarkDirty()
    return true
end
function A:Revert()
    if A.Combat() then return nil, "Not available in combat." end
    self.drag = nil
    self.draft = A.Copy(self.saved)
    self:ApplyAll()
    self:MarkDirty()
    return true
end
function A:RenameLayout(scope, old, new)
    local store = self:Store(scope)
    if not store[old] then return nil, "That layout no longer exists." end
    local valid, err = self:ValidName(new)
    if not valid then return nil, err end
    if valid == old then return true end
    if self:NameTaken(valid) then return nil, "A layout named \"" .. valid .. "\" already exists." end
    store[valid], store[old] = store[old], nil
    if scope == "account" and self.db.defaultLayout == old then self.db.defaultLayout = valid end
    local act = self.char.active
    if act.scope == scope and act.name == old then act.name = valid end
    self:MarkDirty()
    if self.OnLayoutChanged then self:OnLayoutChanged() end
    return true
end
function A:CopyLayout(scope, name, newName, characterSpecific)
    local src
    if scope == "preset" then src = self:PresetData(name) else src = self:Store(scope)[name] end
    if not src then return nil, "That layout no longer exists." end
    -- copying the active layout includes its unsaved changes, like Retail
    local act = self.char.active
    if act.scope == scope and act.name == name then src = self.draft end
    return self:CreateLayout(newName, characterSpecific, src)
end
function A:DeleteLayout(scope, name)
    if A.Combat() then return nil, "Not available in combat." end
    local store = self:Store(scope)
    if not store[name] then return nil, "That layout no longer exists." end
    store[name] = nil
    if scope == "account" and self.db.defaultLayout == name then self.db.defaultLayout = nil end
    local act = self.char.active
    if act.scope == scope and act.name == name then
        -- a character following the default keeps following it
        local follow = self.char.layoutMode == "follow"
        self.followingDefault = follow
        if follow and self.db.defaultLayout then activate(self, "account", self.db.defaultLayout)
        else activate(self, "preset", "Modern") end
        self.followingDefault = nil
    end
    if self.OnLayoutChanged then self:OnLayoutChanged() end
    return true
end
function A:UniqueName(base)
    base = A.Trim(base):sub(1, 28)
    if base == "" then base = "Layout" end
    if not self:NameTaken(base) and self:ValidName(base) then return base end
    for i = 2, 99 do
        local n = base .. " " .. i
        if not self:NameTaken(n) then return n end
    end
    return base .. " " .. math.random(100, 999)
end
-- All user layouts, sorted: { {scope=, name=}, ... }
function A:LayoutList()
    local list = {}
    for _, scope in ipairs({ "account", "character" }) do
        for name in pairs(self:Store(scope)) do list[#list + 1] = { scope = scope, name = name } end
    end
    table.sort(list, function(a, b)
        if a.name:lower() == b.name:lower() then return a.scope < b.scope end
        return a.name:lower() < b.name:lower()
    end)
    return list
end

-- ----------------------------------------------------------------- migration
-- Converts v1 entries (x/y as screen fractions of the element centre).
function A:MigrateEntry(def, entry)
    if type(entry) ~= "table" or entry.point then return end
    if not (finite(entry.x) and finite(entry.y)) then entry.point, entry.x, entry.y = nil, nil, nil; return end
    local w, h = self:ElementSize(def)
    local cx, cy = entry.x * UIParent:GetWidth(), entry.y * UIParent:GetHeight()
    entry.point, entry.x, entry.y = A.ToPosition(cx - w / 2, cy - h / 2, w, h)
    if def.kind == "status" then entry.point, entry.x, entry.y = nil, nil, nil end
end
function A:MigrateLayout(layout)
    if type(layout) ~= "table" or type(layout.frames) ~= "table" then return end
    if (layout.v or 1) < 2 then
        local b = layout.frames.buffs
        if type(b) == "table" and b.point and b.x and b.y then
            local dx, dy = self:LegacyBuffShift(b.point)
            b.x, b.y = A.Round(b.x + dx, .1), A.Round(b.y + dy, .1)
        end
        layout.v = 2
    end
    -- "Hide Bar Scrolling" (bar 1 option in older builds) became the Page Arrows element
    local a1 = layout.frames.action1
    if type(a1) == "table" and a1.hideScrolling ~= nil then
        if not layout.frames.paging then layout.frames.paging = { enabled = not a1.hideScrolling, scale = 100 } end
        a1.hideScrolling = nil
    end
    for id, entry in pairs(layout.frames) do
        local def = self.elements[id]
        if not def then layout.frames[id] = nil
        elseif def.kind ~= "status" and not entry.point then self:MigrateEntry(def, entry) end
    end
end
function A:MigrateAll()
    for _, store in ipairs({ self.db.layouts, self.char.layouts }) do
        for _, layout in pairs(store) do self:MigrateLayout(layout) end
    end
end

-- ----------------------------------------------------------------- share strings
-- BR2: plain data, one field per line, ':' separated. Never evaluated as Lua.
-- ('|' is avoided because WoW edit boxes treat |r, |h, |t as escape codes.)
local function escape(s) return (s:gsub("([^%w _%-%.])", function(c) return string.format("%%%02X", c:byte()) end)) end
local function unescape(s) return (s:gsub("%%(%x%x)", function(h) return string.char(tonumber(h, 16)) end)) end
local function fmtNumber(v)
    if math.abs(v - math.floor(v + .5)) < 1e-9 then return string.format("%d", math.floor(v + .5)) end
    return (string.format("%.2f", v):gsub("0+$", ""):gsub("%.$", ""))
end
function A:Export(data, name)
    data = data or self.draft
    name = name or self:ActiveName()
    local out = { "BR2", "N:" .. escape(name), "O:" .. (data.status and 1 or 0) .. ":" .. (data.compartment and 1 or 0) .. ":" .. escape(data.base or "Classic") .. ":" .. (data.v or 1) }
    for _, id in ipairs(self.order) do
        local entry = data.frames[id]
        if entry then
            local keys = {}
            for k in pairs(entry) do keys[#keys + 1] = k end
            table.sort(keys)
            for _, k in ipairs(keys) do
                local v = entry[k]
                if type(v) == "boolean" then v = v and "true" or "false"
                elseif type(v) == "number" then v = fmtNumber(v) end
                out[#out + 1] = "F:" .. id .. ":" .. k .. ":" .. tostring(v)
            end
        end
    end
    return table.concat(out, "\n")
end
function A:Decode(text)
    if type(text) ~= "string" then return nil, "Paste a layout string." end
    if #text > 60000 then return nil, "That text is too long to be a layout." end
    text = text:gsub("\r", ""):gsub("^%s+", ""):gsub("%s+$", "")
    local header = text:match("^[^\n]*")
    local legacy = false
    if header == "BR1" then
        legacy = true
        text = text:gsub("||", "|"):gsub("|", ":")
    elseif header ~= "BR2" then
        return nil, "That is not a BlizzUI Reborn layout. (Retail Edit Mode strings cannot be imported on this client.)"
    end
    local data = emptyLayout("Classic")
    data.v = 1 -- until the string says otherwise
    local name, seen, count = "Imported Layout", {}, 0
    for line in text:gmatch("[^\n]+") do
        line = A.Trim(line)
        count = count + 1
        if count > 800 then return nil, "Too many fields." end
        if line == "BR1" or line == "BR2" or line == "BR2" or line:sub(1, 3) == "BR1" or line == "" then
            -- header
        elseif line:sub(1, 2) == "N:" then
            name = unescape(line:sub(3))
        elseif line:sub(1, 2) == "O:" then
            local s, c, rest = line:match("^O:([01]):([01]):?(.*)$")
            if not s then return nil, "Malformed options line." end
            data.status, data.compartment = s == "1", c == "1"
            local base, ver = (rest or ""):match("^([^:]*):?(%d*)$")
            data.v = tonumber(ver) or 1
            base = unescape(base or "")
            if base == "Modern" or base == "Classic" then data.base = base end
        else
            local id, key, raw = line:match("^F:([%w_]+):([%w_]+):([^:]+)$")
            local def = id and self.elements[id]
            if not def then return nil, "Unknown element or malformed line: " .. line:sub(1, 40) end
            if seen[id .. ":" .. key] then return nil, "Duplicate setting " .. id .. "." .. key end
            seen[id .. ":" .. key] = true
            local v
            if key == "point" then
                if not VALID_POINTS[raw] then return nil, "Invalid anchor point." end
                v = raw
            elseif key == "x" or key == "y" then
                v = tonumber(raw)
                if not finite(v) or math.abs(v) > 5000 then return nil, "Invalid position." end
            else
                local schema
                for _, o in ipairs(def.settings) do if o.key == key then schema = o end end
                if not schema then return nil, "Unsupported setting " .. id .. "." .. key end
                if schema.kind == "check" then
                    if raw ~= "true" and raw ~= "false" then return nil, "Invalid checkbox value." end
                    v = raw == "true"
                elseif schema.kind == "choice" then
                    for _, c in ipairs(schema.choices) do if raw == tostring(c.value) then v = c.value end end
                    if v == nil then return nil, "Invalid choice for " .. key end
                else
                    v = tonumber(raw)
                    if not finite(v) or v < schema.min - 1e-6 or v > schema.max + 1e-6 then return nil, "Invalid value for " .. key end
                    v = A.Clamp(A.Round((v - schema.min) / schema.step) * schema.step + schema.min, schema.min, schema.max)
                end
            end
            data.frames[id] = data.frames[id] or {}
            data.frames[id][key] = v
        end
    end
    for id, entry in pairs(data.frames) do
        local def = self.elements[id]
        if def.kind ~= "status" then
            -- a position is optional (missing = the frame's normal spot) but must be complete
            local parts = (entry.point and 1 or 0) + (entry.x and 1 or 0) + (entry.y and 1 or 0)
            if legacy then
                if entry.point then return nil, "Malformed legacy layout." end
                if parts == 1 then return nil, "An element has no complete position." end
            elseif parts ~= 0 and parts ~= 3 then
                return nil, "An element has no complete position."
            end
        end
        for _, o in ipairs(def.settings) do if entry[o.key] == nil then entry[o.key] = o.default end end
    end
    self:MigrateLayout(data)
    return data, A.Trim(name)
end
