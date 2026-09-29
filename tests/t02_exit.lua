-- Bug 3: exiting Edit Mode
dofile(TESTS_DIR .. "lib.lua")
H.login()

-- via the game menu entry
GameMenuFrame:Show()
H.click(A.menuButton)
check(A.editing and A.editor:IsShown(), "game menu > Edit Mode opens the editor")
check(not GameMenuFrame:IsShown(), "game menu closes")

-- close button with no changes
H.click(A.editor.close)
H.tick(0.02, 2)
check(not A.editing and not A.editor:IsShown(), "X closes editor when nothing changed")
check(not A.elements.player.overlay:IsShown(), "overlays hidden after exit")
check(not A.grid:IsShown(), "grid hidden after exit")

-- Escape with no changes
T.open()
H.escape(); H.tick(0.02, 3)
check(not A.editing, "Escape closes editor when nothing changed")

-- Escape while the layout menu is open closes only the menu
T.open()
H.click(A.editor.layout)
check(BlizzUIRebornMenu:IsShown(), "menu open")
H.escape(); H.tick(0.02, 3)
check(not BlizzUIRebornMenu:IsShown() and A.editing, "Escape closes the menu first, editor stays")

-- unsaved changes: Cancel keeps editing, Exit discards
local l0, b0 = T.rect("player")
T.dragElement("player", 50, 20)
local l1 = T.rect("player")
check(not near(l0, l1), "player moved")
H.click(A.editor.close); H.tick(0.02, 2)
check(A.dialogs.Confirm:IsShown(), "unsaved prompt on exit")
H.click(T.confirmButton("Cancel")); H.tick(0.02, 1)
check(A.editing and A.editor:IsShown(), "Cancel keeps editing")
H.escape(); H.tick(0.02, 3)
check(A.dialogs.Confirm:IsShown() and A.editing, "Escape with changes prompts")
H.escape(); H.tick(0.02, 3)
check(not A.dialogs.Confirm:IsShown() and A.editing, "Escape on the prompt only closes the prompt")
H.click(A.editor.close); H.tick(0.02, 2)
H.click(T.confirmButton("Exit")); H.tick(0.02, 2)
check(not A.editing, "Exit leaves edit mode")
local l2, b2 = T.rect("player")
check(near(l2, l0) and near(b2, b0), "Exit without saving restores the saved position")
check(not A.dirty, "not dirty after discarding")

-- Save and Exit on a preset asks for a name, then exits with the layout saved
T.open()
T.dragElement("player", 30, 30)
local l3, b3 = T.rect("player")
H.click(A.editor.close); H.tick(0.02, 2)
H.click(T.confirmButton("Save and Exit"))
check(A.dialogs.Name:IsShown(), "saving a preset asks for a layout name")
T.typeDialog("Name", "Exit Test")
check(not A.editing, "editor closed after Save and Exit")
check(A.char.active.name == "Exit Test", "new layout active")
local l4, b4 = T.rect("player")
check(near(l4, l3) and near(b4, b3), "position kept")

-- Save and Exit on a custom layout saves directly
T.open()
T.dragElement("player", -20, 0)
local l5 = T.rect("player")
H.click(A.editor.close); H.tick(0.02, 2)
H.click(T.confirmButton("Save and Exit")); H.tick(0.02, 2)
check(not A.editing and not A.dirty, "custom layout saved on exit")
check(near(BlizzUIRebornCharDB.layouts["Exit Test"] and 0 or 0, 0) and BlizzUIRebornDB.layouts["Exit Test"], "stored")

-- closing the name dialog of Save-and-Exit keeps editing
T.open()
T.dragElement("target", 10, 10)
A:LoadPreset("Modern")
check(not A.dirty, "loading preset clears draft")
T.dragElement("target", 10, 10)
H.click(A.editor.close); H.tick(0.02, 2)
H.click(T.confirmButton("Save and Exit"))
H.click(A.dialogs.Name.cancel); H.tick(0.02, 2)
check(A.editing and A.dirty, "cancelling the name dialog keeps editing with changes")
H.click(A.editor.revert)
check(not A.dirty, "revert")
H.click(A.editor.close); H.tick(0.02, 2)
check(not A.editing, "exit after revert")

-- /br toggles open
SlashCmdList.BLIZZUIREBORN("")
check(A.editing, "/br opens")
A:RequestExit()
check(not A.editing, "RequestExit closes")
