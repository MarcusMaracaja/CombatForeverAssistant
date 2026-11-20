-- Combat Forever Assistant — Visuals.
-- Two highlight modes, drawn on the action button itself:
--   "circle": a dashed colored ring over the button (native textures, no art files)
--   "border": a colored frame around the button (4 edge bars)
-- No glow/flash effects. Border width applies to both modes.
-- Colors: per suggestion kind, or a single user-picked color (Options > General).

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

Visuals.PresetColors = {
    { 1.0, 0.25, 0.25 },  -- red
    { 1.0, 0.55, 0.10 },  -- orange
    { 1.0, 0.95, 0.20 },  -- yellow
    { 0.25, 1.0, 0.35 },  -- green
    { 0.25, 0.85, 1.0 },  -- cyan
    { 1.0, 1.0, 1.0 },    -- white
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

local buttonMap = {}
local itemButtonMap
local highlighted = {}
local mapDirty = true

local function iterActionButtons(fn)
    for _, pattern in ipairs(BUTTON_PATTERNS) do
        local prefix = pattern:match("^(.-)%%d%+$")
        for i = 1, 12 do
            local f = _G[prefix .. i]
            if f then fn(f) end
        end
    end
end

local function slotSpellID(frameBtn)
    if frameBtn and type(frameBtn.GetAttribute) == "function" then
        local ok, slot = pcall(function()
            return tonumber(frameBtn:GetAttribute("action"))
        end)
        if ok and slot and slot > 0 then return slot end
    end
    local name = frameBtn:GetName()
    local n = name and name:match("(%d+)$")
    if not n then return nil end
    n = tonumber(n)
    if name:match("^ActionButton") then return n end
    if name:match("^MultiBarRightButton") then return 48 + n end
    if name:match("^MultiBarLeftButton") then return 60 + n end
    if name:match("^MultiBarBottomLeftButton") then return 60 + n end
    if name:match("^MultiBarBottomRightButton") then return 72 + n end
    return nil
end

function Visuals.RefreshMap()
    mapDirty = true
    itemButtonMap = nil
end

function Visuals.BuildMap()
    buttonMap = {}
    iterActionButtons(function(f) table.insert(buttonMap, f) end)
    mapDirty = false
    itemButtonMap = nil
end

local function ensureMap()
    if mapDirty then Visuals.BuildMap() end
end

local function buttonAction(f)
    local slot = slotSpellID(f)
    if not slot or type(GetActionInfo) ~= "function" then return nil end
    local ok, actionType, id = pcall(GetActionInfo, slot)
    if not ok then return nil end
    return actionType, id
end

local function buttonSpellID(f)
    local actionType, id = buttonAction(f)
    if actionType == "spell" then return id end
    return nil
end

local function actionItemID(id)
    if type(id) == "number" then return id end
    if type(id) == "string" then
        return tonumber(id:match("item:(%d+)")) or tonumber(id)
    end
    return nil
end

local function buttonItemID(f)
    local actionType, id = buttonAction(f)
    if actionType == "item" then return actionItemID(id) end
    return nil
end

local function baseName(n)
    return n and n:gsub("%s*%b()%s*$", ""):lower() or nil
end

local function spellBaseName(id)
    if not id or not (addon.Compat and addon.Compat.SpellInfoByID) then return nil end
    return baseName(addon.Compat.SpellInfoByID(id))
end

-- rank-insensitive match: same base name, or same id
local function spellMatches(barID, wantID)
    if not barID or not wantID then return false end
    if barID == wantID then return true end
    local barBase, wantBase = spellBaseName(barID), spellBaseName(wantID)
    return barBase ~= nil and barBase == wantBase
end

-- public: buttons on the action bars bound to this spell (id or family name)
function Visuals.FindButtons(spellID)
    ensureMap()
    local out = {}
    for _, btn in ipairs(buttonMap) do
        local barID = buttonSpellID(btn)
        if spellMatches(barID, spellID) then out[#out + 1] = btn end
    end
    return out
end

function Visuals.FindItemButtons(itemID)
    ensureMap()
    if not itemButtonMap then
        itemButtonMap = {}
        for _, btn in ipairs(buttonMap) do
            local id = buttonItemID(btn)
            if id then
                itemButtonMap[id] = itemButtonMap[id] or {}
                table.insert(itemButtonMap[id], btn)
            end
        end
    end
    return itemButtonMap[itemID] or {}
end

-- public so the minimap button (and others) can reuse the same dashed ring
function Visuals.DashRing(parent, radius, thickness, rgb, segments)
    segments = segments or 14
    local group = CreateFrame("Frame", nil, parent)
    group:SetAllPoints(parent)
    local chord = (2 * math.pi * radius / segments) * 0.72
    local thick = math.max(2, math.floor(thickness))
    for i = 1, segments do
        local a = (i / segments) * math.pi * 2
        local dx, dy = math.cos(a), math.sin(a)
        local tex = group:CreateTexture(nil, "OVERLAY")
        tex:SetTexture("Interface\\Buttons\\WHITE8X8")
        tex:SetVertexColor(rgb[1], rgb[2], rgb[3], 1)
        tex:SetWidth(chord)
        tex:SetHeight(thick)
        tex:SetPoint("CENTER", group, "CENTER", dx * radius, dy * radius)
        pcall(function() tex:SetRotation(a + math.pi / 2) end)
    end
    return group
end

local function makeBorderOverlay(btn, rgb, width)
    local f = CreateFrame("Frame", nil, btn)
    f:SetAllPoints(btn)
    local w = math.max(1, math.floor(width or 12))
    local bw = btn:GetWidth()
    local bh = btn:GetHeight()
    local function edge(point, horiz)
        local tex = f:CreateTexture(nil, "OVERLAY")
        tex:SetTexture("Interface\\Buttons\\WHITE8X8")
        tex:SetVertexColor(rgb[1], rgb[2], rgb[3], 1)
        if horiz then
            tex:SetHeight(w)
            tex:SetWidth(bw)
            tex:SetPoint(point .. "LEFT", f, point .. "LEFT", 0, 0)
            tex:SetPoint(point .. "RIGHT", f, point .. "RIGHT", 0, 0)
        else
            tex:SetWidth(w)
            tex:SetHeight(bh)
            tex:SetPoint("TOP" .. point, f, "TOP" .. point, 0, 0)
            tex:SetPoint("BOTTOM" .. point, f, "BOTTOM" .. point, 0, 0)
        end
    end
    edge("TOP", true)
    edge("BOTTOM", true)
    edge("LEFT", false)
    edge("RIGHT", false)
    return f
end

function Visuals.Clear()
    for btn, overlay in pairs(highlighted) do
        overlay:Hide()
        overlay:SetParent(nil)
    end
    highlighted = {}
end

local function showButtons(buttons, reason)
    local rgb
    if addon.db.useSingleColor then
        rgb = Visuals.PresetColors[addon.db.singleColorIndex or 2]
    else
        rgb = COLORS[reason] or COLORS.Utility
    end
    local mode = addon.db.visualMode or "circle"
    local width = math.max(0, math.min(60, tonumber(addon.db.borderWidth) or 12))
    for _, btn in ipairs(buttons) do
        if not highlighted[btn] then
            local overlay
            if mode == "border" then
                overlay = makeBorderOverlay(btn, rgb, width)
            else
                local btnW = btn:GetWidth()
                overlay = Visuals.DashRing(btn, btnW * 0.68, math.max(3, math.min(24, width * 0.5 + 3)), rgb, 14)
            end
            highlighted[btn] = overlay
        end
    end
end

local function showSpell(spellID, reason)
    if not spellID then return end
    local buttons = {}
    for _, btn in ipairs(buttonMap) do
        if spellMatches(buttonSpellID(btn), spellID) then buttons[#buttons + 1] = btn end
    end
    showButtons(buttons, reason)
end

local function showItem(itemID, reason)
    if not itemID then return end
    showButtons(Visuals.FindItemButtons(itemID), reason)
end

function Visuals.ShowMany(suggestions)
    ensureMap()
    Visuals.Clear()
    if type(suggestions) ~= "table" then return end
    for _, suggestion in ipairs(suggestions) do
        if type(suggestion) == "table" then
            if suggestion.kind == "item" then
                showItem(suggestion.itemID, suggestion.color or suggestion.reason)
            else
                showSpell(suggestion.spellID, suggestion.color or suggestion.reason)
            end
        end
    end
end

function Visuals.Show(spellID, reason)
    Visuals.ShowMany({ { spellID = spellID, color = reason } })
end

function Visuals.Hide()
    Visuals.Clear()
end
