-- Combat Forever Assistant — Key Button.
-- Small draggable widget that shows the key bound to the same slot the
-- suggested spell is on. Toggled via /cfa key or the General tab.
-- Can be locked from the General tab ("Lock the key button position") —
-- locked means: not draggable and fully click-through.

local addonName, addon = ...
local L = addon.L

local KeyButton = {}
addon.KeyButton = KeyButton

local frame

local ACTION_BINDINGS = {
    { prefix = "ACTIONBUTTON", offset = 0 },
    { prefix = "MULTIACTIONBAR1BUTTON", offset = 60 },   -- bottom left bar (shift)
    { prefix = "MULTIACTIONBAR2BUTTON", offset = 48 },   -- right bar (ctrl)
    { prefix = "MULTIACTIONBAR3BUTTON", offset = 72 },   -- bottom right bar
    { prefix = "MULTIACTIONBAR4BUTTON", offset = 84 },   -- extra bar (if present)
}

local function bindingForSlot(slot)
    for _, block in ipairs(ACTION_BINDINGS) do
        local i = slot - block.offset
        if i >= 1 and i <= 12 then
            local key1, key2 = GetBindingKey(block.prefix .. i)
            return key1 or key2
        end
    end
    return nil
end

local function findKeyForSpell(spellID)
    for slot = 1, 96 do
        local actionType, id = GetActionInfo(slot)
        if actionType == "spell" and id == spellID then
            local key = bindingForSlot(slot)
            if key then return key end
        end
    end
    return nil
end

local function applySavedPosition(self)
    local db = addon.charDb
    self:ClearAllPoints()
    self:SetPoint("CENTER", UIParent, "CENTER", db.keyX or 240, db.keyY or -180)
end

KeyButton.FontList = {
    { file = "Fonts\\FRIZQT__.TTF", name = "Friz Quadrata" },
    { file = "Fonts\\ARIALN.TTF",   name = "Arial Narrow" },
    { file = "Fonts\\MORPHEUS.TTF", name = "Morpheus" },
    { file = "Fonts\\SKURRI.TTF",   name = "Skurri" },
    { file = "Fonts\\2002.TTF",     name = "2002" },
    { file = "Fonts\\2002B.TTF",    name = "2002 Bold" },
}

local DEFAULTS = {
    keySize = 46,
    keyFont = "Fonts\\FRIZQT__.TTF",
    keyBgColor = { 0.05, 0.05, 0.05 },
    keyBgAlpha = 0.72,
    keyTextColor = { 1.0, 0.9, 0.3 },
}
KeyButton.Defaults = DEFAULTS

function KeyButton.FontDisplayName(file)
    for _, f in ipairs(KeyButton.FontList) do
        if f.file == file then return f.name end
    end
    return (file and file:match("[^\\]+$")) or "?"
end

function KeyButton.ApplyLook()
    local db = addon.db
    if not frame then return end
    local size = math.max(24, math.min(128, tonumber(db.keySize) or DEFAULTS.keySize))
    frame:SetWidth(size)
    frame:SetHeight(size)
    local scale = size / DEFAULTS.keySize
    frame.border:SetHeight(math.max(2, math.floor(2 * scale + 0.5)))
    local textSize = math.max(12, math.floor(size * 0.42))
    pcall(frame.text.SetFont, frame.text, db.keyFont or DEFAULTS.keyFont, textSize, "OUTLINE")
    local tc = db.keyTextColor or DEFAULTS.keyTextColor
    frame.text:SetTextColor(tc[1] or 1, tc[2] or 0.9, tc[3] or 0.3, 1)
    local bg = db.keyBgColor or DEFAULTS.keyBgColor
    local a = db.keyBgAlpha
    if a == nil then a = DEFAULTS.keyBgAlpha end
    frame.bg:SetVertexColor(bg[1] or 0.05, bg[2] or 0.05, bg[3] or 0.05, a)
end

function KeyButton.ResetPosition()
    addon.charDb.keyX, addon.charDb.keyY = nil, nil
    if frame then applySavedPosition(frame) end
end

function KeyButton.ResetAll()
    local db = addon.db
    db.keySize = DEFAULTS.keySize
    db.keyFont = DEFAULTS.keyFont
    db.keyBgColor = { DEFAULTS.keyBgColor[1], DEFAULTS.keyBgColor[2], DEFAULTS.keyBgColor[3] }
    db.keyBgAlpha = DEFAULTS.keyBgAlpha
    db.keyTextColor = { DEFAULTS.keyTextColor[1], DEFAULTS.keyTextColor[2], DEFAULTS.keyTextColor[3] }
    KeyButton.ResetPosition()
    KeyButton.ApplyLook()
    KeyButton.ApplyLock()
end

local function manualDragStart(self)
    if addon.db.keyButtonLocked then return end
    local mx, my = GetCursorPosition()
    local scale = self:GetEffectiveScale()
    local cx, cy = self:GetCenter()
    self.isDown = true
    self.dragDX = cx - mx / scale
    self.dragDY = cy - my / scale
end

local function manualDragUpdate(self)
    if not self.isDown then return end
    if not IsMouseButtonDown("LeftButton") then
        self.isDown = false
        return
    end
    local mx, my = GetCursorPosition()
    local scale = self:GetEffectiveScale()
    local ux, uy = UIParent:GetCenter()
    local nx = mx / scale + self.dragDX - ux
    local ny = my / scale + self.dragDY - uy
    self:ClearAllPoints()
    self:SetPoint("CENTER", UIParent, "CENTER", nx, ny)
    addon.charDb.keyX, addon.charDb.keyY = nx, ny
end

local function createFrame()
    frame = CreateFrame("Button", "CFA_KeyButton", UIParent)
    frame:SetWidth(46)
    frame:SetHeight(46)
    frame:SetFrameStrata("MEDIUM")
    frame:EnableMouse(true)

    frame.bg = frame:CreateTexture(nil, "BACKGROUND")
    frame.bg:SetTexture("Interface\\Buttons\\WHITE8X8")
    frame.bg:SetVertexColor(0.05, 0.05, 0.05, 0.72)
    frame.bg:SetAllPoints()

    frame.border = frame:CreateTexture(nil, "BORDER")
    frame.border:SetTexture("Interface\\Buttons\\WHITE8X8")
    frame.border:SetVertexColor(1.0, 0.55, 0.10, 0.9)
    frame.border:SetHeight(2)
    frame.border:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    frame.border:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)

    frame.text = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    frame.text:SetPoint("CENTER", frame, "CENTER", 0, 0)
    frame.text:SetTextColor(1, 0.9, 0.3)
    frame.text:SetText("")

    frame:SetScript("OnMouseDown", manualDragStart)
    frame:SetScript("OnMouseUp", function(self) self.isDown = false end)
    frame:SetScript("OnUpdate", manualDragUpdate)

    applySavedPosition(frame)
    KeyButton.ApplyLook()
    KeyButton.ApplyLock()
    return frame
end

function KeyButton.ApplyLock()
    if not frame then return end
    if addon.db.keyButtonLocked then
        frame.isDown = false
        frame:EnableMouse(false) -- clicks pass through to whatever is behind
    else
        frame:EnableMouse(true)
    end
end

function KeyButton.ShowPlaceholder()
    if not frame then createFrame() end
    frame.text:SetText("?")
    frame:Show()
    KeyButton.ApplyLock()
    return true
end

function KeyButton.ShowFor(spellID)
    local key = findKeyForSpell(spellID)
    if not key then
        KeyButton.Hide()
        return false
    end
    if not frame then createFrame() end
    frame.text:SetText(key)
    frame:Show()
    KeyButton.ApplyLock()
    return true
end

function KeyButton.Hide()
    if frame then frame:Hide() end
end
