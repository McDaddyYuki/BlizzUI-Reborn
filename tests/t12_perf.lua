-- Idle cost: after login nothing should be re-applied while idle.
dofile(TESTS_DIR .. "lib.lua")
H.login()
local applies = 0
for _, k in pairs(A.Kinds) do
    if k.apply then local f = k.apply; k.apply = function(...) applies = applies + 1; return f(...) end end
end
local setPoints = 0
local orig = MOCK.newObject
local t0 = os.clock()
H.tick(1 / 60, 600) -- 10 seconds at 60 fps
local idle = os.clock() - t0
check(applies <= 2, "idle for 10s: " .. applies .. " element re-applies (compartment/status only)")
print(string.format("    10s idle simulation: %.3fs CPU in the mock, %d applies", idle, applies))
-- repeated Blizzard refreshes only cost a drift check
applies = 0
for i = 1, 50 do UIParent_ManageFramePositions(); H.tick(1 / 60) end
check(applies <= 5, "50 frame-manager calls caused " .. applies .. " re-applies")
-- editing: dragging 120 frames of motion
T.open()
applies = 0
local t1 = os.clock()
H.drag(T.overlay("player"), 200, 100, 120)
print(string.format("    120-frame drag: %.3fs CPU, %d applies", os.clock() - t1, applies))
check(applies <= 121, "one apply per drag frame at most")
