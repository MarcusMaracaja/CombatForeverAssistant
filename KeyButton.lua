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
