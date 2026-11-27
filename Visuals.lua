-- Combat Forever Assistant — Visuals.
-- Two highlight modes, drawn on the action button itself:
--   "circle": a dashed colored ring over the button (native textures, no art files)
--   "border": a colored frame around the button (4 edge bars)
--   "flame"/"lightning": animated custom overlays; "zoom": pulsing frame.
-- Colors: per suggestion kind, or a single user-picked color (Options > Button).

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
local shownSignature

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
    if name:match("^MultiBarRightButton") then return 24 + n end
    if name:match("^MultiBarLeftButton") then return 36 + n end
    if name:match("^MultiBarBottomLeftButton") then return 60 + n end
    if name:match("^MultiBarBottomRightButton") then return 48 + n end
    return nil
end

function Visuals.RefreshMap()
    mapDirty = true
    itemButtonMap = nil
    shownSignature = nil
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

local function bagButtonItemID(button)
    if not button then return nil end
    local bagID, slotID
    -- Modern Dragonflight/Midnight ContainerFrameItemButtonMixin
    if type(button.GetSlotAndBagID) == "function" then
        local ok, s, b = pcall(button.GetSlotAndBagID, button)
        if ok and type(s) == "number" and type(b) == "number" then
            slotID, bagID = s, b
        end
    end
    if bagID == nil and type(button.GetBagID) == "function" then
        local ok, b = pcall(button.GetBagID, button)
        if ok and type(b) == "number" then bagID = b end
    end
    if bagID == nil and type(button.bagID) == "number" then
        bagID = button.bagID
    end
    if bagID == nil and type(button.GetParent) == "function" then
        local parent = button:GetParent()
        if parent then
            if type(parent.GetBagID) == "function" then
                local ok, b = pcall(parent.GetBagID, parent)
                if ok and type(b) == "number" then bagID = b end
            end
            if bagID == nil and type(parent.GetID) == "function" then
                local ok, b = pcall(parent.GetID, parent)
                if ok and type(b) == "number" then bagID = b end
            end
        end
    end
    if slotID == nil and type(button.GetID) == "function" then
        local ok, s = pcall(button.GetID, button)
        if ok and type(s) == "number" then slotID = s end
    end
    if slotID == nil and type(button.slotID) == "number" then
        slotID = button.slotID
    end
    if bagID == nil or slotID == nil or slotID <= 0 then return nil end

    if C_Container and type(C_Container.GetContainerItemID) == "function" then
        local ok, id = pcall(C_Container.GetContainerItemID, bagID, slotID)
        if ok and type(id) == "number" then return id end
    end
    if C_Container and type(C_Container.GetContainerItemInfo) == "function" then
        local ok, info = pcall(C_Container.GetContainerItemInfo, bagID, slotID)
        if ok and type(info) == "table" and type(info.itemID) == "number" then return info.itemID end
    end
    if type(GetContainerItemID) == "function" then
        local ok, id = pcall(GetContainerItemID, bagID, slotID)
        if ok and type(id) == "number" then return id end
    end
    return nil
end

local function isFrameVisible(f)
    if not f then return false end
    if type(f.IsVisible) == "function" then
        local ok, v = pcall(f.IsVisible, f)
        if ok then return v == true end
    end
    if type(f.IsShown) == "function" then
        local ok, v = pcall(f.IsShown, f)
        if ok then return v == true end
    end
    return false
end

local function collectVisibleBagButtons(wantItemID)
    local out = {}
    local seen = {}
    local function inspectButton(btn)
        if type(btn) ~= "table" or seen[btn] then return end
        if not isFrameVisible(btn) then return end
        seen[btn] = true
        if wantItemID == nil then
            out[#out + 1] = btn
        else
            local id = bagButtonItemID(btn)
            if id == wantItemID then out[#out + 1] = btn end
        end
    end

    local function inspectContainer(container)
        if not isFrameVisible(container) then return end
        local foundAny = false
        if type(container.EnumerateValidItems) == "function" then
            pcall(function()
                for a, b in container:EnumerateValidItems() do
                    local btn = type(b) == "table" and b or a
                    if type(btn) == "table" then
                        foundAny = true
                        inspectButton(btn)
                    end
                end
            end)
        end
        if not foundAny and type(container.Items) == "table" then
            for _, btn in ipairs(container.Items) do
                foundAny = true
                inspectButton(btn)
            end
        end
        if not foundAny then
            local name = type(container.GetName) == "function" and container:GetName() or nil
            if name then
                for slot = 1, 36 do
                    local btn = _G[name .. "Item" .. slot]
                    if btn then inspectButton(btn) end
                end
            end
        end
    end

    -- 1) Modern combined bag frame (Retail / Interface 16001)
    if _G.ContainerFrameCombinedBags then
        inspectContainer(_G.ContainerFrameCombinedBags)
    end
    -- 2) Individual Blizzard bag frames (split bags / classic layout)
    local maxFrames = tonumber(_G.NUM_CONTAINER_FRAMES) or 13
    for i = 1, maxFrames do
        local cf = _G["ContainerFrame" .. i]
        if cf then inspectContainer(cf) end
    end
    -- 3) ElvUI unified bag frame
    if isFrameVisible(_G.ElvUI_ContainerFrame) then
        local numBags = tonumber(_G.NUM_BAG_SLOTS) or 4
        for bag = 0, numBags do
            for slot = 1, 40 do
                local btn = _G["ElvUI_ContainerFrameBag" .. bag .. "Slot" .. slot]
                if btn then inspectButton(btn) end
            end
        end
    end
    -- 4) Bagnon inventory frame
    if isFrameVisible(_G.BagnonInventoryFrame1) then
        local frameObj = _G.BagnonInventoryFrame1
        if type(frameObj.itemFrame) == "table" and type(frameObj.itemFrame.buttons) == "table" then
            for _, btn in pairs(frameObj.itemFrame.buttons) do
                inspectButton(btn)
            end
        end
    end
    return out
end

function Visuals.GetOpenBagSources()
    local sources = {}
    if isFrameVisible(_G.ContainerFrameCombinedBags) then sources[#sources + 1] = "ContainerFrameCombinedBags" end
    local maxFrames = tonumber(_G.NUM_CONTAINER_FRAMES) or 13
    for i = 1, maxFrames do
        local cf = _G["ContainerFrame" .. i]
        if isFrameVisible(cf) then sources[#sources + 1] = "ContainerFrame" .. i end
    end
    if isFrameVisible(_G.ElvUI_ContainerFrame) then sources[#sources + 1] = "ElvUI_ContainerFrame" end
    if isFrameVisible(_G.BagnonInventoryFrame1) then sources[#sources + 1] = "BagnonInventoryFrame1" end
    return sources
end

function Visuals.IsAnyBagOpen()
    return #Visuals.GetOpenBagSources() > 0
end

function Visuals.FindBagItemButtons(itemID)
    if type(itemID) ~= "number" then return {} end
    return collectVisibleBagButtons(itemID)
end

-- ---------------------------------------------------------------------------
-- Party / Raid / Player unit-frame discovery & non-tainting visual overlay
-- Supports Blizzard default (modern PartyFrame & classic PartyMemberFrame),
-- CompactPartyFrame / CompactRaidFrame, ElvUI, Cell, Grid2 and VuhDo.
-- ---------------------------------------------------------------------------
local function frameUnitMatches(frameObj, wantUnit)
    if type(frameObj) ~= "table" or not isFrameVisible(frameObj) then return false end
    local fUnit
    pcall(function()
        fUnit = frameObj.displayedUnit or frameObj.unit
        if not fUnit and type(frameObj.GetAttribute) == "function" then
            fUnit = frameObj:GetAttribute("unit")
        end
    end)
    if type(fUnit) ~= "string" or fUnit == "" then return false end
    if addon.UnitIsSame then return addon.UnitIsSame(fUnit, wantUnit) end
    if type(UnitIsUnit) == "function" then
        local ok, same = pcall(UnitIsUnit, fUnit, wantUnit)
        return ok and same == true
    end
    return fUnit == wantUnit
end

local function findPortraitRegion(frameObj)
    if type(frameObj) ~= "table" then return nil end
    local name = (type(frameObj.GetName) == "function") and frameObj:GetName() or nil
    local candidates = {}
    pcall(function()
        if frameObj.PlayerFrameContainer and frameObj.PlayerFrameContainer.PlayerPortrait then
            candidates[#candidates + 1] = frameObj.PlayerFrameContainer.PlayerPortrait
        end
        if frameObj.Portrait then candidates[#candidates + 1] = frameObj.Portrait end
        if frameObj.portrait then candidates[#candidates + 1] = frameObj.portrait end
        if name and _G[name .. "Portrait"] then
            candidates[#candidates + 1] = _G[name .. "Portrait"]
        end
        if frameObj == _G.PlayerFrame and _G.PlayerPortrait then
            candidates[#candidates + 1] = _G.PlayerPortrait
        end
    end)
    for _, p in ipairs(candidates) do
        if type(p) == "table" and isFrameVisible(p) and type(p.GetWidth) == "function" then
            local okW, w = pcall(p.GetWidth, p)
            local okH, h = pcall(p.GetHeight, p)
            if okW and okH and type(w) == "number" and type(h) == "number"
                and w >= 20 and w <= 120 and math.abs(w - h) <= 18 then
                return p
            end
        end
    end
    return nil
end

function Visuals.FindUnitFrames(unit)
    if type(unit) ~= "string" or unit == "" then return {} end
    local out = {}
    local seen = {}

    local function consider(frameObj, forceMatch)
        if type(frameObj) ~= "table" or seen[frameObj] then return end
        if not isFrameVisible(frameObj) then return end
        if not forceMatch and not frameUnitMatches(frameObj, unit) then return end
        seen[frameObj] = true
        local name = (type(frameObj.GetName) == "function") and frameObj:GetName() or "UnitFrame"
        out[#out + 1] = {
            frame = frameObj,
            portrait = findPortraitRegion(frameObj),
            name = name,
        }
    end

    local isSelf = (addon.UnitIsSame and addon.UnitIsSame(unit, "player")) or (unit == "player")
    if isSelf then
        if _G.PlayerFrame then consider(_G.PlayerFrame, true) end
        if _G.ElvUF_Player then consider(_G.ElvUF_Player, true) end
    end

    -- 1) Blizzard modern PartyFrame pool (Dragonflight / Interface 16001)
    if _G.PartyFrame and _G.PartyFrame.PartyMemberFramePool
        and type(_G.PartyFrame.PartyMemberFramePool.EnumerateActive) == "function" then
        pcall(function()
            for memberFrame in _G.PartyFrame.PartyMemberFramePool:EnumerateActive() do
                consider(memberFrame)
            end
        end)
    end

    -- 2) Blizzard classic PartyMemberFrame1..4
    for i = 1, 4 do
        consider(_G["PartyMemberFrame" .. i])
    end

    -- 3) Blizzard Raid-Style Party Frames (CompactPartyFrameMember1..5)
    for i = 1, 5 do
        consider(_G["CompactPartyFrameMember" .. i])
    end

    -- 4) Blizzard CompactRaidFrames (flat 1..40 and grouped 1..8 x 1..5)
    for i = 1, 40 do
        consider(_G["CompactRaidFrame" .. i])
    end
    for g = 1, 8 do
        for m = 1, 5 do
            consider(_G["CompactRaidGroup" .. g .. "Member" .. m])
        end
    end

    -- 5) ElvUI Party & Raid frames
    for m = 1, 5 do
        consider(_G["ElvUF_PartyGroup1UnitButton" .. m])
    end
    local elvPrefixes = { "ElvUF_Raid1Group", "ElvUF_Raid2Group", "ElvUF_Raid3Group", "ElvUF_RaidGroup", "ElvUF_Raid40Group" }
    for _, pref in ipairs(elvPrefixes) do
        for g = 1, 8 do
            for m = 1, 5 do
                consider(_G[pref .. g .. "UnitButton" .. m])
            end
        end
    end

    -- 6) Cell / Grid2 / VuhDo popular healer raid frames
    for m = 1, 5 do
        consider(_G["CellPartyFrameMember" .. m])
    end
    for i = 1, 40 do
        consider(_G["CellRaidFrameHeader0UnitButton" .. i])
        consider(_G["Grid2LayoutHeader1UnitButton" .. i])
        consider(_G["Vd1H" .. i])
    end

    return out
end

-- public so the minimap button (and others) can reuse the same dashed ring
function Visuals.DashRing(parent, radius, thickness, rgb, segments)
    segments = segments or 14
    local group = CreateFrame("Frame", nil, parent)
    group:SetAllPoints(parent)
    pcall(function()
        group:SetFrameStrata(parent:GetFrameStrata())
        group:SetFrameLevel(parent:GetFrameLevel() + 10)
    end)
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
    pcall(function()
        f:SetFrameStrata(btn:GetFrameStrata())
        f:SetFrameLevel(btn:GetFrameLevel() + 10)
    end)
    local w = math.max(2, math.floor(width or 12))
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

local function makeTextureOverlay(btn, textureFile, rgb)
    local f = CreateFrame("Frame", nil, btn)
    pcall(function()
        f:SetFrameStrata(btn:GetFrameStrata())
        f:SetFrameLevel(btn:GetFrameLevel() + 10)
    end)
    local size = math.max(btn:GetWidth(), btn:GetHeight()) * 1.35
    f:SetSize(size, size)
    f:SetPoint("CENTER", btn, "CENTER")
    local texture = f:CreateTexture(nil, "OVERLAY")
    texture:SetAllPoints(f)
    texture:SetTexture("Interface\\AddOns\\" .. addonName .. "\\Textures\\" .. textureFile)
    texture:SetBlendMode("ADD")
    texture:SetVertexColor(rgb[1], rgb[2], rgb[3], 1)

    local pulse = f:CreateAnimationGroup()
    pulse:SetLooping("BOUNCE")
    local alpha = pulse:CreateAnimation("Alpha")
    alpha:SetFromAlpha(0.55)
    alpha:SetToAlpha(1)
    alpha:SetDuration(0.42)
    f.pulse = pulse
    pulse:Play()
    return f
end

local function makeZoomOverlay(btn, rgb, width)
    local f = makeBorderOverlay(btn, rgb, width)
    local pulse = f:CreateAnimationGroup()
    pulse:SetLooping("BOUNCE")
    local scale = pulse:CreateAnimation("Scale")
    local scaleFrom = scale and (scale.SetScaleFrom or scale.SetFromScale)
    local scaleTo = scale and (scale.SetScaleTo or scale.SetToScale)
    if type(scaleFrom) == "function" and type(scaleTo) == "function"
        and type(scale.SetDuration) == "function" then
        scaleFrom(scale, 1, 1)
        scaleTo(scale, 1.18, 1.18)
        scale:SetDuration(0.36)
    else
        pulse:Stop()
        pulse = f:CreateAnimationGroup()
        pulse:SetLooping("BOUNCE")
        local alpha = pulse:CreateAnimation("Alpha")
        if alpha and type(alpha.SetFromAlpha) == "function"
            and type(alpha.SetToAlpha) == "function" and type(alpha.SetDuration) == "function" then
            alpha:SetFromAlpha(0.55)
            alpha:SetToAlpha(1)
            alpha:SetDuration(0.42)
        else
            pulse = nil
        end
    end
    if pulse then
        f.pulse = pulse
        pulse:Play()
    end
    return f
end

function Visuals.Clear()
    for btn, overlay in pairs(highlighted) do
        if overlay.pulse then overlay.pulse:Stop() end
        overlay:Hide()
        overlay:SetParent(nil)
    end
    highlighted = {}
    shownSignature = nil
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
            elseif mode == "flame" then
                overlay = makeTextureOverlay(btn, "Highlight_Flame.tga", rgb)
            elseif mode == "lightning" then
                overlay = makeTextureOverlay(btn, "Highlight_Lightning.tga", rgb)
            elseif mode == "zoom" then
                overlay = makeZoomOverlay(btn, rgb, width)
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

local function showItem(itemID, reason, highlightBags)
    if not itemID then return end
    showButtons(Visuals.FindItemButtons(itemID), reason)
    if highlightBags then
        showButtons(Visuals.FindBagItemButtons(itemID), reason)
    end
end

-- Purely visual, non-interactive overlay parented to UIParent (zero taint in combat lockdown!).
-- Uses a pulsing ring around round portraits (Blizzard Party/Player) or a crisp pulsing
-- colored border around rectangular party/raid unit cards (CompactRaid, ElvUI, Cell, etc.).
local function makeUnitFrameOverlay(entry, rgb, urgent)
    local target = entry.portrait or entry.frame
    local f = CreateFrame("Frame", nil, UIParent)
    f:EnableMouse(false)
    f:SetAllPoints(target)
    pcall(function()
        f:SetFrameStrata(entry.frame:GetFrameStrata() or "HIGH")
        f:SetFrameLevel((entry.frame:GetFrameLevel() or 1) + 12)
    end)

    if entry.portrait then
        local w = target:GetWidth() or 48
        local radius = w * 0.56
        local thick = urgent and 5 or 4
        local segments = 16
        local chord = (2 * math.pi * radius / segments) * 0.78
        for i = 1, segments do
            local a = (i / segments) * math.pi * 2
            local dx, dy = math.cos(a), math.sin(a)
            local tex = f:CreateTexture(nil, "OVERLAY")
            tex:SetTexture("Interface\\Buttons\\WHITE8X8")
            tex:SetVertexColor(rgb[1], rgb[2], rgb[3], 1)
            tex:SetWidth(chord)
            tex:SetHeight(thick)
            tex:SetPoint("CENTER", f, "CENTER", dx * radius, dy * radius)
            pcall(function() tex:SetRotation(a + math.pi / 2) end)
        end
    else
        local edgeW = urgent and 5 or 4
        local function edge(point, horiz)
            local tex = f:CreateTexture(nil, "OVERLAY")
            tex:SetTexture("Interface\\Buttons\\WHITE8X8")
            tex:SetVertexColor(rgb[1], rgb[2], rgb[3], 1)
            if horiz then
                tex:SetHeight(edgeW)
                tex:SetPoint(point .. "LEFT", f, point .. "LEFT", -1, 0)
                tex:SetPoint(point .. "RIGHT", f, point .. "RIGHT", 1, 0)
            else
                tex:SetWidth(edgeW)
                tex:SetPoint("TOP" .. point, f, "TOP" .. point, 0, 1)
                tex:SetPoint("BOTTOM" .. point, f, "BOTTOM" .. point, 0, -1)
            end
        end
        edge("TOP", true)
        edge("BOTTOM", true)
        edge("LEFT", false)
        edge("RIGHT", false)
    end

    local pulse = f:CreateAnimationGroup()
    pulse:SetLooping("BOUNCE")
    local alpha = pulse:CreateAnimation("Alpha")
    if alpha and type(alpha.SetFromAlpha) == "function" then
        alpha:SetFromAlpha(urgent and 0.40 or 0.55)
        alpha:SetToAlpha(1.0)
        alpha:SetDuration(urgent and 0.28 or 0.45)
        f.pulse = pulse
        pulse:Play()
    end
    return f
end

local function showUnitFrame(unit, reason, urgent)
    if not unit then return end
    local rgb = COLORS[reason] or COLORS.Defensive
    local entries = Visuals.FindUnitFrames(unit)
    for _, entry in ipairs(entries) do
        local keyObj = entry.portrait or entry.frame
        if keyObj and not highlighted[keyObj] then
            highlighted[keyObj] = makeUnitFrameOverlay(entry, rgb, urgent)
        end
    end
end

function Visuals.ShowMany(suggestions)
    ensureMap()
    if type(suggestions) ~= "table" then
        Visuals.Clear()
        return
    end
    local bagOpen = Visuals.IsAnyBagOpen()
    local signature = {
        tostring(addon.db.visualMode or "circle"),
        tostring(addon.db.borderWidth or 12),
        tostring(addon.db.useSingleColor),
        tostring(addon.db.singleColorIndex or 2),
        tostring(bagOpen),
    }
    for _, suggestion in ipairs(suggestions) do
        if type(suggestion) == "table" then
            local extraSig = ""
            if suggestion.kind == "item" and suggestion.highlightBags and bagOpen and suggestion.itemID then
                local bagBtns = Visuals.FindBagItemButtons(suggestion.itemID)
                local ptrs = {}
                for _, bb in ipairs(bagBtns) do ptrs[#ptrs + 1] = tostring(bb) end
                extraSig = table.concat(ptrs, ",")
            elseif suggestion.kind == "unitframe" and suggestion.unit then
                local uEntries = Visuals.FindUnitFrames(suggestion.unit)
                local ptrs = {}
                for _, ue in ipairs(uEntries) do ptrs[#ptrs + 1] = tostring(ue.portrait or ue.frame) end
                extraSig = tostring(suggestion.unit) .. ":" .. tostring(suggestion.urgent and "1" or "0") .. ":" .. table.concat(ptrs, ",")
            end
            signature[#signature + 1] = table.concat({
                tostring(suggestion.kind or "spell"),
                tostring(suggestion.spellID or ""),
                tostring(suggestion.itemID or ""),
                tostring(suggestion.color or suggestion.reason or "Utility"),
                tostring(suggestion.highlightBags and "bag" or "bar"),
                extraSig,
            }, ":")
        end
    end
    local key = table.concat(signature, "|")
    if key == shownSignature then return end
    Visuals.Clear()
    shownSignature = key
    for _, suggestion in ipairs(suggestions) do
        if type(suggestion) == "table" then
            if suggestion.kind == "item" then
                showItem(suggestion.itemID, suggestion.color or suggestion.reason, suggestion.highlightBags)
            elseif suggestion.kind == "unitframe" then
                showUnitFrame(suggestion.unit, suggestion.color or suggestion.reason, suggestion.urgent)
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
