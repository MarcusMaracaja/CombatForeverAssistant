-- Combat Forever Assistant — Visuals.
-- Two highlight modes, both drawn on the action button itself:
--   "circle": a colored ring over the button (own texture CFA_Circle.tga)
--   "border": a colored frame around the button (4 edge bars)
-- No glow/flash effects. Colors encode the suggestion kind.

local addonName, addon = ...
local L = addon.L

local Visuals = {}
addon.Visuals = Visuals

local COLORS = {
    Damage    = { 1.0, 0.27, 0.27 },
    AoE       = { 1.0, 0.55, 0.10 },
    Interrupt = { 1.0, 1.0, 0.15 },
    Defensive = { 0.2, 1.0, 0.2 },
    Utility   = { 0.2, 0.8, 1.0 },
}

local BUTTON_PATTERNS = {
    "ActionButton%d+",
    "MultiBarBottomLeftButton%d+",
    "MultiBarBottomRightButton%d+",
    "MultiBarRightButton%d+",
    "MultiBarLeftButton%d+",
    "PetActionButton%d+",
    "ShapeshiftButton%d+",
}

local buttonMap = {}   -- list of frames showing an action
local highlighted = {}  -- frame -> overlay frame
local mapDirty = true

local function iterActionButtons(fn)
    for _, pattern in ipairs(BUTTON_PATTERNS) do
        local prefix, suffix = pattern:match("^(.-)%%d%+$")
        for i = 1, 12 do
            local f = _G[prefix .. i]
            if f then fn(f) end
        end
    end
end

local function slotSpellID(frameBtn)
    -- Map an action button back to its slot number.
    local name = frameBtn:GetName()
    local n = name and name:match("(%d+)$")
    if not n then return nil end
    n = tonumber(n)
    -- Vanilla bar offsets (main bar 0, left 60, right 48, bottom-right 72, bottom-left 60-63 legacy)
    if name:match("^ActionButton") then return n end
    if name:match("^MultiBarRightButton") then return 48 + n end
    if name:match("^MultiBarLeftButton") then return 60 + n end
    if name:match("^MultiBarBottomLeftButton") then return 60 + n end
    if name:match("^MultiBarBottomRightButton") then return 72 + n end
    return nil -- pet/shapeshift handled separately (no slot mapping)
end

function Visuals.RefreshMap()
    mapDirty = true
end

function Visuals.BuildMap()
    buttonMap = {}
    iterActionButtons(function(f) table.insert(buttonMap, f) end)
    mapDirty = false
end

local function ensureMap()
    if mapDirty then Visuals.BuildMap() end
end

local function buttonSpellID(f)
    local slot = slotSpellID(f)
    if slot then
        local actionType, id = GetActionInfo(slot)
        if actionType == "spell" and id then
            local name = GetSpellInfo(id)
            if name then return id end
        end
    end
    return nil
end

local function makeCircleOverlay(btn, rgb)
    local t = btn:CreateTexture(nil, "OVERLAY")
    t:SetTexture("Interface\\AddOns\\CombatForeverAssistant\\Textures\\CFA_Circle.tga")
    t:SetVertexColor(rgb[1], rgb[2], rgb[3], 1)
    t:SetPoint("CENTER", btn, "CENTER", 0, 0)
    t:SetWidth(btn:GetWidth() * 1.30)
    t:SetHeight(btn:GetHeight() * 1.30)
    return t
end

local function makeBorderOverlay(btn, rgb, width)
    local f = CreateFrame("Frame", nil, btn)
    f:SetAllPoints(btn)
    local w = math.max(1, math.floor(width or 12))
    local function edge(anchor1, anchor2, orient, size)
        local tex = f:CreateTexture(nil, "OVERLAY")
        tex:SetTexture("Interface\\Buttons\\WHITE8X8")
        tex:SetVertexColor(rgb[1], rgb[2], rgb[3], 1)
        tex:SetHeight(orient == "h" and w or btn:GetHeight())
        tex:SetWidth(orient == "v" and w or btn:GetWidth())
        if orient == "h" then
            tex:SetPoint(anchor1, f, anchor1, 0, 0)
            tex:SetPoint(anchor2, f, anchor2, 0, 0)
        else
            tex:SetPoint(anchor1, f, anchor1, 0, 0)
            tex:SetPoint(anchor2, f, anchor2, 0, 0)
        end
    end
    edge("TOPLEFT", "TOPRIGHT", "h")
    edge("BOTTOMLEFT", "BOTTOMRIGHT", "h")
    edge("TOPLEFT", "BOTTOMLEFT", "v")
    edge("TOPRIGHT", "BOTTOMRIGHT", "v")
    return f
end

function Visuals.Clear()
    for btn, overlay in pairs(highlighted) do
        overlay:Hide()
        overlay:SetParent(nil)
    end
    highlighted = {}
end

function Visuals.Show(spellID, reason)
    ensureMap()
    Visuals.Clear()
    if not spellID then return end
    local rgb = COLORS[reason] or COLORS.Utility
    local mode = addon.db.visualMode or "circle"
    for _, btn in ipairs(buttonMap) do
        if buttonSpellID(btn) == spellID then
            local overlay
            if mode == "border" then
                overlay = makeBorderOverlay(btn, rgb, addon.db.borderWidth)
            else
                overlay = makeCircleOverlay(btn, rgb)
            end
            highlighted[btn] = overlay
        end
    end
end

function Visuals.Hide()
    Visuals.Clear()
end
