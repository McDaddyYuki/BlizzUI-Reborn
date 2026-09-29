-- Stance badge next to the player's level: warrior stance, DK presence,
-- paladin seal; hidden when nothing is active, in a vehicle, or switched off.
dofile(TESTS_DIR .. "lib.lua")
ShapeshiftBar_Update()
H.login()
local b = A.classBadge
check(b and b:IsShown(), "warrior: badge shown")
check(b.icon.__portrait and b.icon:GetTexture() == "Interface\\Icons\\Ability_Warrior_OffensiveStance" and b.stateName == "Battle Stance", "shows Battle Stance (round icon)")
check(b.ring:GetTexture() == "Interface\\Minimap\\MiniMap-TrackingBorder", "stock round ring border")
check(not b:IsMouseEnabled(), "never blocks clicks on the player frame")
-- geometry: the badge frame is the visible circle, mirrored from the level
-- circle across the portrait, at the level circle's height
local function geometry(tag)
    local s = PlayerFrame:GetEffectiveScale()
    local lx, ly = PlayerLevelText:GetCenter()
    local px = PlayerPortrait:GetCenter()
    local bx, by = b:GetCenter()
    local ok = near(by, ly, .5) and near(bx - px, px - lx, .5) and bx > px
    check(ok, tag .. ": right of the level, level with it, mirrored across the portrait")
    check(near(b:GetEffectiveScale(), s, .001), tag .. ": scales with the player frame")
end
geometry("default")
check(b:GetParent() == PlayerFrame, "moves, scales and hides with the player frame")
local ulx, uly, llx, lly, urx = b.ring:GetTexCoord()
local tw, th = urx - ulx, lly - uly
check(tw > .5 and tw < .6 and th > .5 and th < .6 and near(tw, th, .01), "ring cropped to its visible circle (square, padding removed)")
check(b.ring:GetNumPoints() >= 1 and near(b.ring:GetWidth(), b:GetWidth(), .01), "ring fills the badge")
check(near(b.icon:GetWidth(), b:GetWidth() * .64, .5) and b.icon.__portrait, "round icon inside the ring's opening")
-- draw order: above the player frame's art (drawn by a frame nested in PlayerFrame)
check(b:GetFrameLevel() > MOCK.playerArt:GetFrameLevel(), "drawn above the portrait/level/border art frame")
check(b:GetFrameStrata() == PlayerFrame:GetFrameStrata(), "same strata as the player frame (no TOOLTIP/FULLSCREEN shortcut)")
-- move and resize the player frame through Edit Mode, other scales, layouts
T.open()
A.db.editor.snap = false
T.dragElement("player", 120, -60)
A:SetSetting("player", "scale", 150)
geometry("moved, 150%")
A:SetSetting("player", "scale", 75)
geometry("75%")
local ui = UIParent:GetScale()
UIParent:SetScale(.64); H.tick(.05, 2)
geometry("UI scale .64")
UIParent:SetScale(ui); H.tick(.05, 2)
A:RequestExit(); if T.confirmButton("Save") then H.click(T.confirmButton("Save")) end
if T.confirmButton("Exit") then H.click(T.confirmButton("Exit")) end
A:LoadPreset("Classic"); geometry("Classic layout")
A:LoadPreset("Modern"); geometry("Modern layout")
-- the art frame raised later (another addon, a vehicle swap): stacking refreshed on the next update
MOCK.playerArt:SetFrameLevel(b:GetFrameLevel() + 3)
H.fire("UPDATE_SHAPESHIFT_FORM")
check(b:GetFrameLevel() > MOCK.playerArt:GetFrameLevel(), "stacking follows the art frame")
check(not b:IsMouseEnabled(), "still click-through")

-- stance change (fires in combat too)
H.enterCombat()
MOCK.forms[1][3], MOCK.forms[2][3] = false, true
H.fire("UPDATE_SHAPESHIFT_FORM")
check(b:IsShown() and b.stateName == "Defensive Stance", "stance change in combat updates the badge")
check(#MOCK.blocked == 0, "no blocked actions")
H.leaveCombat()
-- no stance (e.g. a low-level warrior)
MOCK.forms[2][3] = false
H.fire("UPDATE_SHAPESHIFT_FORM")
check(not b:IsShown(), "hidden with no stance active")
MOCK.forms[3][3] = true; H.fire("UPDATE_SHAPESHIFT_FORM")
check(b:IsShown() and b.stateName == "Berserker Stance", "Berserker Stance")
-- vehicle
UnitHasVehicleUI = function() return true end
H.fire("UNIT_ENTERED_VEHICLE", "player")
check(not b:IsShown(), "hidden in a vehicle")
UnitHasVehicleUI = function() return nil end
H.fire("UNIT_EXITED_VEHICLE", "player")
check(b:IsShown(), "back after the vehicle")
-- Edit Mode switch on the Player Frame
T.open()
A:SetSetting("player", "stanceBadge", false)
check(not b:IsShown(), "'Show Stance Badge' off hides it")
A:SetSetting("player", "stanceBadge", true)
check(b:IsShown(), "and on shows it again")
A:RequestExit(); if T.confirmButton("Exit") then H.click(T.confirmButton("Exit")) end
H.tick(0.05, 2)

-- death knight presences
local realClass = UnitClass
UnitClass = function() return "Death Knight", "DEATHKNIGHT" end
MOCK.forms = { { "Interface\\Icons\\Spell_Deathknight_BloodPresence", "Blood Presence", false, true },
    { "Interface\\Icons\\Spell_Deathknight_FrostPresence", "Frost Presence", true, true },
    { "Interface\\Icons\\Spell_Deathknight_UnholyPresence", "Unholy Presence", false, true } }
H.fire("UPDATE_SHAPESHIFT_FORMS")
check(b:IsShown() and b.stateName == "Frost Presence", "death knight: Frost Presence")

-- paladin: seals (buffs), not auras (which are the paladin's shapeshift forms)
UnitClass = function() return "Paladin", "PALADIN" end
MOCK.forms = { { "Interface\\Icons\\Spell_Holy_DevotionAura", "Devotion Aura", true, true } }
MOCK.spells[21084] = { name = "Seal of Righteousness" }
MOCK.spells[31801] = { name = "Seal of Vengeance" }
MOCK.buffs = { { name = "Devotion Aura", icon = "Interface\\Icons\\Spell_Holy_DevotionAura", id = 48942 },
    { name = "Blessing of Kings", icon = "Interface\\Icons\\Spell_Magic_GreaterBlessingofKings", id = 20217 } }
H.fire("UNIT_AURA", "player")
check(not b:IsShown(), "paladin without a seal: hidden (the aura is not shown)")
MOCK.buffs[3] = { name = "Seal of Righteousness", icon = "Interface\\Icons\\Ability_ThunderBolt", id = 21084 }
H.fire("UNIT_AURA", "target")
check(not b:IsShown(), "other units' auras are ignored")
H.fire("UNIT_AURA", "player")
check(b:IsShown() and b.stateName == "Seal of Righteousness" and b.icon:GetTexture() == "Interface\\Icons\\Ability_ThunderBolt", "paladin: Seal of Righteousness")
MOCK.buffs[3] = { name = "Seal of Vengeance", icon = "Interface\\Icons\\Spell_Holy_SealOfVengeance" } -- matched by name too
H.fire("UNIT_AURA", "player")
check(b:IsShown() and b.stateName == "Seal of Vengeance", "seal swap")
MOCK.buffs[3] = nil; H.fire("UNIT_AURA", "player")
check(not b:IsShown(), "seal expired: hidden")

-- other classes never show it
UnitClass = function() return "Mage", "MAGE" end
MOCK.buffs[3] = { name = "Seal of Righteousness", icon = "x", id = 21084 }
H.fire("UNIT_AURA", "player"); H.fire("UPDATE_SHAPESHIFT_FORM")
check(not b:IsShown(), "mage: never shown")
UnitClass = function() return "Paladin", "PALADIN" end
H.fire("UNIT_AURA", "player")
check(b:IsShown(), "paladin again")
-- restore (suspend) hides it, enable brings it back
SlashCmdList.BLIZZUIREBORN("restore")
check(not b:IsShown(), "hidden while BlizzUI Reborn is suspended")
SlashCmdList.BLIZZUIREBORN("enable")
check(b:IsShown(), "back when resumed")
UnitClass = realClass
check(#MOCK.errors == 0 and #A.errorLog == 0, "no Lua errors")
