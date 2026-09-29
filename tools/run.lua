-- usage: lua run.lua <test.lua> [savedvars-file]
-- paths relative to this script, so the harness runs from any checkout
local dir = (arg and arg[0] and arg[0]:match("^(.*[/\\])")) or "./"
local addon = dir .. "../BlizzUIReborn/"
TESTS_DIR = dir .. "../tests/"
TMP_DIR = os.getenv("BR_TEST_TMP") or (dir .. "../.test-tmp/")
if TMP_DIR:sub(-1) ~= "/" then TMP_DIR = TMP_DIR .. "/" end
dofile(dir .. "wowmock.lua")
dofile(dir .. "world.lua")
M, H = MOCK, MOCK.H
M.onError = function(e) io.stderr:write("SCRIPT ERROR: " .. e .. "\n") end
-- saved variables from a previous "session"
SV_FILE = arg[2]
if SV_FILE then local f = io.open(SV_FILE); if f then f:close(); dofile(SV_FILE) end end
local function loadAddon()
    for line in io.lines(addon .. "BlizzUIReborn.toc") do
        if line:match("%.lua$") then
            local chunk, err = loadfile(addon .. line)
            if not chunk then error(err) end
            chunk("BlizzUIReborn", {})
        end
    end
end
function serialize(v, indent)
    indent = indent or ""
    if type(v) == "table" then
        local keys = {}
        for k in pairs(v) do keys[#keys + 1] = k end
        table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
        local out = { "{\n" }
        for _, k in ipairs(keys) do
            local kk = type(k) == "string" and string.format("[%q]", k) or "[" .. tostring(k) .. "]"
            out[#out + 1] = indent .. "  " .. kk .. " = " .. serialize(v[k], indent .. "  ") .. ",\n"
        end
        out[#out + 1] = indent .. "}"
        return table.concat(out)
    elseif type(v) == "string" then return string.format("%q", v)
    elseif type(v) == "number" then return string.format("%.17g", v)
    else return tostring(v) end
end
function H.login()
    H.fire("ADDON_LOADED", "BlizzUIReborn")
    H.fire("VARIABLES_LOADED")
    H.fire("PLAYER_LOGIN")
    H.fire("PLAYER_ENTERING_WORLD")
    H.tick(0.05, 5)
end
function H.logout(file)
    H.fire("PLAYER_LOGOUT")
    local f = assert(io.open(file, "w"))
    f:write("BlizzUIRebornDB = " .. serialize(BlizzUIRebornDB) .. "\n")
    f:write("BlizzUIRebornCharDB = " .. serialize(BlizzUIRebornCharDB) .. "\n")
    -- layout-local.txt emulation: user-placed frame positions persist
    local layout = {}
    for name, fr in pairs(M.named) do
        if fr.__isframe and fr.__userPlaced and fr.__points[1] then
            local p = fr.__points[1]
            layout[#layout + 1] = string.format("do local f=_G[%q]; f.__userPlaced=true; f.__movable=true; f.__points={{%q, UIParent, %q, %.17g, %.17g}} end",
                name, p[1], p[3], p[4], p[5])
        end
    end
    f:write(table.concat(layout, "\n") .. "\n")
    f:close()
end
-- test helpers
PASS, FAIL = 0, 0
function check(cond, msg)
    if cond then PASS = PASS + 1 else FAIL = FAIL + 1; print("  FAIL: " .. msg) end
end
function near(a, b, tol) return a and b and math.abs(a - b) <= (tol or 0.6) end
loadAddon()
A = BlizzUIReborn
local test = assert(loadfile(arg[1]))
local ok, err = xpcall(test, debug.traceback)
if not ok then print("  TEST CRASHED: " .. err); FAIL = FAIL + 1 end
if #M.errors > 0 then
    for _, e in ipairs(M.errors) do print("  SCRIPT ERROR: " .. e:sub(1, 600)) end
    FAIL = FAIL + #M.errors
end
if #A.errorLog > 0 then
    for _, e in ipairs(A.errorLog) do print("  ADDON ERROR: " .. e:sub(1, 600)) end
    FAIL = FAIL + #A.errorLog
end
if #M.blocked > 0 then for _, b in ipairs(M.blocked) do print("  BLOCKED: " .. b) end; FAIL = FAIL + #M.blocked end
print(string.format("%s: %d passed, %d failed", arg[1]:match("[^/]+$"), PASS, FAIL))
os.exit(FAIL == 0 and 0 or 1)
