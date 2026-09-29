-- Layouts across characters; Import/Share dialogs usable (3.3.5 frame levels).
dofile(TESTS_DIR .. "lib.lua")
H.login()
T.open()

-- ------------------------------------------------------------ dialogs
local function allAbove(f)
    local ok = true
    local function walk(p)
        for _, c in ipairs({ p:GetChildren() }) do
            if c:IsShown() and c:GetFrameLevel() <= p:GetFrameLevel() then ok = false end
            walk(c)
        end
    end
    walk(f)
    return ok
end
A:ImportDialog()
local d = A.dialogs.Text
check(d:IsShown() and d:GetFrameStrata() == "FULLSCREEN_DIALOG", "Import dialog open on top")
check(d:GetFrameLevel() < MOCK.MAX_FRAME_LEVEL - 10, "dialog is well below the 3.3.5 frame level cap")
check(allAbove(d), "every part of the dialog (text box, buttons) draws above the dialog itself")
check(d.box.box:HasFocus(), "text box has focus: ready to paste")
H.escape()
A:ShareDialog(A.draft, "Modern")
check(A.dialogs.Text:IsShown() and allAbove(A.dialogs.Text) and A.dialogs.Text.box.box:GetText():find("^BR2"), "Share dialog shows a copyable string")
H.escape()
A:SelectElement("player")
check(allAbove(A.settingsDialog) and allAbove(A.editor), "settings and Edit Mode windows: children above their panel")
A:Deselect()

-- ------------------------------------------------------------ account layouts on every character
check(A:CreateLayout("Raid", false), "account-wide layout created")
check(BlizzUIRebornDB.defaultLayout == "Raid", "first account layout becomes the default for other characters")
local function newCharacter(chardb)
    BlizzUIRebornCharDB = chardb or {}
    A:InitDB(); A:LoadActive(); A:ApplyAll(true)
    return A.char.active
end
local mainChar = BlizzUIRebornCharDB
local act = newCharacter()
check(act.scope == "account" and act.name == "Raid", "a new character starts on the account's layout")
act = newCharacter({ active = { scope = "preset", name = "Modern" } })
check(act.name == "Raid", "an alt still on the untouched Modern preset gets it too")
act = newCharacter({ active = { scope = "preset", name = "Classic" } })
check(act.scope == "preset" and act.name == "Classic", "an alt that picked Classic keeps it")
act = newCharacter({ active = { scope = "preset", name = "Modern" }, chosen = true })
check(act.name == "Modern", "an alt that picked Modern keeps it")
-- explicit default
newCharacter(mainChar)
A:CreateLayout("Healer", false)
check(BlizzUIRebornDB.defaultLayout == "Raid", "the default doesn't change by itself")
check(A:SetDefaultLayout("Healer") and newCharacter().name == "Healer", "'Default for All Characters' picks another")
newCharacter(mainChar)
A:RenameLayout("account", "Healer", "Heals")
check(BlizzUIRebornDB.defaultLayout == "Heals", "renaming keeps it the default")
A:DeleteLayout("account", "Heals")
check(BlizzUIRebornDB.defaultLayout == nil and newCharacter().name == "Modern", "deleting it: new characters use Modern again")
-- character-only layouts can be shared with the account
newCharacter(mainChar)
A:CreateLayout("Solo", true)
check(A.char.layouts.Solo and not A.db.layouts.Solo, "character-only layout")
check(A:MakeAccountWide("Solo"), "Make Account-Wide")
check(A.db.layouts.Solo and not A.char.layouts.Solo and A.char.active.scope == "account", "moved to the account and still active")
check(newCharacter().name == "Solo" or A.db.defaultLayout == "Solo", "now usable on other characters")
-- the gear menu has the new entries
newCharacter(mainChar)
A:OpenEditor()
H.click(A.editor.layout)
local row = T.menuRow("Raid")
check(row and row.gear, "layout row with gear")
H.click(row.gear)
check(T.menuRow("Default for All Characters"), "gear menu: Default for All Characters")
A.CloseMenu()
check(#MOCK.errors == 0, "no Lua errors")
