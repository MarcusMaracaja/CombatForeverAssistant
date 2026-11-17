-- Combat Forever Assistant — Key Button.
-- Small draggable widget that shows the key bound to the same slot the
-- suggested spell is on. Entirely optional, toggled via the General tab or /cfa key.

local addonName, addon = ...
local L = addon.L

local KeyButton = {}
addon.KeyButton = KeyButton

local frame
local db = addon.charDb

local ACTION_BINDINGS = {
    { prefix = "ACTIONBUTTON", offset = 0 },
    { prefix = "MULTIACTIONBAR1BUTTON", offset = 60 },   -- bottom left bar
    { prefix = "MULTIACTIONBAR2BUTTON", offset = 48 },   -- right bar
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
    -- Iterate real slots; returns key of the first slot showing that spell.
    for slot = 1, 96 do
        local actionType, id = GetActionInfo(slot)
        if actionType == "spell" and id == spellID then
            local key = bindingForSlot(slot)
            if key then return key end
        end
    end
    return nil
end

local function createFrame()
    frame = CreateFrame("Button", "CFA_KeyButton", UIParent)
    frame:SetWidth(46)
    frame:SetHeight(46)
    frame:SetFrameStrata("MEDIUM")
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")

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

    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local x, y = self:GetCenter()
        local ux, uy = UIParent:GetCenter()
        db.keyX, db.keyY = (x or 0) - (ux or 0), (y or 0) - (uy or 0)
    end)

    frame:SetPoint("CENTER", UIParent, "CENTER", db.keyX or 240, db.keyY or -180)
    return frame
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
    return true
end

function KeyButton.Hide()
    if frame then frame:Hide() end
end
