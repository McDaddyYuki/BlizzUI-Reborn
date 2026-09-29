-- Stock 3.3.5 textures only: BlizzUI Reborn keeps the game's own look.
local A = BlizzUIReborn
A.Media = {
    White = "Interface\\Buttons\\WHITE8X8", Chat = "Interface\\ChatFrame\\ChatFrameBackground",
    TooltipBorder = "Interface\\Tooltips\\UI-Tooltip-Border", Font = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF",
    CheckUp = "Interface\\Buttons\\UI-CheckBox-Up", CheckDown = "Interface\\Buttons\\UI-CheckBox-Down",
    CheckMark = "Interface\\Buttons\\UI-CheckBox-Check", CheckHighlight = "Interface\\Buttons\\UI-CheckBox-Highlight",
    SliderThumb = "Interface\\Buttons\\UI-SliderBar-Button-Horizontal", SliderBg = "Interface\\Buttons\\UI-SliderBar-Background",
    SliderBorder = "Interface\\Buttons\\UI-SliderBar-Border", Arrow = "Interface\\ChatFrame\\UI-ChatIcon-ScrollDown-Up",
    CloseUp = "Interface\\Buttons\\UI-Panel-MinimizeButton-Up", CloseDown = "Interface\\Buttons\\UI-Panel-MinimizeButton-Down",
    CloseHighlight = "Interface\\Buttons\\UI-Panel-MinimizeButton-Highlight", RowHighlight = "Interface\\QuestFrame\\UI-QuestTitleHighlight",
}
A.Colors = { gold = { 1, .82, 0 }, text = { 1, 1, 1 }, dim = { .5, .5, .5 }, red = { 1, .3, .3 } }

-- The dark tooltip-border panel used by the original build.
function A.StylePanel(frame)
    frame:SetBackdrop({ bgFile = A.Media.Chat, edgeFile = A.Media.TooltipBorder, tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 } })
    frame:SetBackdropColor(.035, .04, .045, .95)
    frame:SetBackdropBorderColor(.65, .65, .6, 1)
end
-- Dark input field (edit boxes, dropdown buttons).
function A.StyleField(frame)
    frame:SetBackdrop({ bgFile = A.Media.Chat, edgeFile = A.Media.TooltipBorder, tile = true, tileSize = 16, edgeSize = 10,
        insets = { left = 2, right = 2, top = 2, bottom = 2 } })
    frame:SetBackdropColor(0, 0, 0, .8)
    frame:SetBackdropBorderColor(.5, .5, .5, 1)
end

local fonts = {}
function A.Font(size, flags)
    local key = size .. (flags or "")
    if not fonts[key] then
        fonts[key] = CreateFont("BlizzUIRebornFont" .. size .. (flags or ""):gsub("[^%w]", ""))
        fonts[key]:SetFont(A.Media.Font, size, flags or "")
        fonts[key]:SetShadowOffset(1, -1)
    end
    return fonts[key]
end
function A.Text(parent, size, color, layer, flags)
    local fs = parent:CreateFontString(nil, layer or "OVERLAY")
    fs:SetFontObject(A.Font(size or 12, flags))
    local c = color or A.Colors.text
    fs:SetTextColor(c[1], c[2], c[3], c[4] or 1)
    return fs
end
