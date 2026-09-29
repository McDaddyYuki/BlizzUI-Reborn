-- Bug 1 (switching layouts does nothing) and bug 2 (custom-named layouts)
dofile(TESTS_DIR .. "lib.lua")
H.login()
local nativeP = { 19, 4 }
T.open()
check(A.editor:IsShown(), "editor opens")

-- Modern -> Classic restores native positions
T.chooseLayout("Classic")
check(A.char.active.name == "Classic", "switched to Classic preset")
local p, rel, rp, x, y = PlayerFrame:GetPoint(1)
check(p == "TOPLEFT" and rel == UIParent and near(x, -19) and near(y, -4), "Classic puts player frame at native spot (got " .. tostring(p) .. " " .. tostring(x) .. "," .. tostring(y) .. ")")
check(A.editor.layout.text:GetText():find("Classic"), "dropdown shows Classic")

-- Classic -> Modern moves it to the Modern spot
T.chooseLayout("Modern")
local l, b = T.rect("player")
local el, eb = T.expectedRect("player", "BOTTOM", -290, 208)
check(near(l, el) and near(b, eb), "Modern puts player frame at the Modern spot")

-- changing something then switching prompts
T.dragElement("target", 40, 30)
check(A.dirty, "drag marks layout dirty")
T.chooseLayout("Classic")
check(A.dialogs.Confirm:IsShown(), "unsaved-changes prompt shown when switching")
H.click(T.confirmButton("Cancel"))
check(A.char.active.name == "Modern" and A.dirty, "cancel keeps layout and changes")
T.chooseLayout("Classic")
H.click(T.confirmButton("Switch"))
check(A.char.active.name == "Classic" and not A.dirty, "Switch discards and switches")

-- New Layout with a custom name (bug 2)
H.click(A.editor.layout)
H.click(T.menuRow("New Layout"))
check(A.dialogs.Name:IsShown(), "New Layout dialog opens")
T.typeDialog("Name", "My Raid UI", true)
check(A.char.active.scope == "character" and A.char.active.name == "My Raid UI", "custom layout created and active")
check(A.editor.layout.text:GetText():find("My Raid UI"), "dropdown shows the new layout name")
check(BlizzUIRebornCharDB.layouts["My Raid UI"] ~= nil, "layout stored per character")

-- invalid and duplicate names are rejected with a message
H.click(A.editor.layout); H.click(T.menuRow("New Layout"))
T.typeDialog("Name", "   ")
check(A.dialogs.Name:IsShown() and A.dialogs.Name.err:GetText() ~= "", "empty name rejected with error")
T.typeDialog("Name", "My Raid UI")
check(A.dialogs.Name:IsShown() and A.dialogs.Name.err:GetText():find("already exists"), "duplicate name rejected")
T.typeDialog("Name", "Healer")
check(A.char.active.name == "Healer" and A.char.active.scope == "account", "account-wide layout created")

-- save a change into Healer, then switch around and verify it sticks
T.dragElement("target", -60, 40)
local tl, tb = T.rect("target")
H.click(A.editor.save)
check(not A.dirty, "save clears dirty")
T.chooseLayout("Modern")
local ml, mb = T.rect("target")
check(not near(ml, tl) or not near(mb, tb), "Modern target differs from Healer target")
T.chooseLayout("Healer")
local hl, hb = T.rect("target")
check(near(hl, tl) and near(hb, tb), "switching back to Healer restores its saved target position")

-- rename, copy, delete through the gear menu
T.gear("Healer", "Rename")
T.typeDialog("Name", "Healer Main")
check(A.char.active.name == "Healer Main" and BlizzUIRebornDB.layouts["Healer Main"] and not BlizzUIRebornDB.layouts["Healer"], "rename works")
T.gear("Healer Main", "Copy Layout")
T.typeDialog("Name", "Healer Alt")
check(A.char.active.name == "Healer Alt" and BlizzUIRebornDB.layouts["Healer Alt"], "copy creates and activates new layout")
local cl, cb = T.rect("target")
check(near(cl, tl) and near(cb, tb), "copy keeps positions")
T.gear("Healer Alt", "Delete")
check(A.dialogs.Confirm:IsShown(), "delete asks for confirmation")
H.click(T.confirmButton("Delete"))
check(not BlizzUIRebornDB.layouts["Healer Alt"] and A.char.active.name == "Modern", "delete removes layout and falls back to Modern")

-- copying a preset
T.gear("Modern", "Copy Layout")
T.typeDialog("Name", "Modern Copy")
check(A.char.active.name == "Modern Copy", "preset copy becomes an editable layout")
check(not A.dirty, "fresh copy is clean")
