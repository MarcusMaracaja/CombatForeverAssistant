-- Combat Forever Assistant — Hunter module: rotation editor window.
-- Dark panel + orange accent + red close X, in the visual language of the
-- rest of the addon. Shows the rotation nodes for a chosen spec and lets the
-- player toggle nodes on/off per character ("Rotation cards").
local moduleName, module = ...

module.Hunter = module.Hunter or module
local Hunter = module.Hunter

local frame, content, scrollChild
local tabButtons = {}
local currentSpec = "SV"
local cardFrames = {}

local PANEL_W, PANEL_H = 560, 440
local ORANGE = { 1.0, 0.55, 0.10 }
local BG = { 0.02, 0.02, 0.02, 0.90 }

local function applyBackdrop(f, r, g, b, a)
    if f.SetBackdrop then
        f:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            tile = true, tileSize = 8, edgeSize = 1,
            insets = { left = 0, right = 0, top = 0, bottom = 0 },
        })
        f:SetBackdropColor(r, g, b, a)
        f:SetBackdropBorderColor(ORANGE[1], ORANGE[2], ORANGE[3], 0.55)
    end
end

local function specTitle(specKey)
    local spec = Hunter.RotationSpecs and Hunter.RotationSpecs[specKey]
    return (spec and spec.title) or specKey
end

-- Per-character toggles: module.charDb.hunterDisabled[spec][nodeId] = true (off)
local function getDisabledMap(specKey)
    if not module.charDb then module.charDb = {} end
    module.charDb.hunterDisabled = module.charDb.hunterDisabled or {}
    module.charDb.hunterDisabled[specKey] = module.charDb.hunterDisabled[specKey] or {}
    return module.charDb.hunterDisabled[specKey]
end

function module.GetRotationDisabled(specKey)
    return getDisabledMap(specKey)
end

local function specIcon(spellID)
    if C_Spell and C_Spell.GetSpellTexture then
        local ok, tex = pcall(C_Spell.GetSpellTexture, spellID)
        if ok and tex then return tex end
    end
    if type(GetSpellTexture) == "function" then
        local ok, tex = pcall(GetSpellTexture, spellID)
        if ok and tex then return tex end
    end
    return "Interface\\Icons\\INV_Misc_QuestionMark"
end

local function colorOf(c)
    local map = {
        Damage    = { 1.0, 0.27, 0.27 },
        AoE       = { 1.0, 0.55, 0.10 },
        Interrupt = { 1.0, 1.0,  0.15 },
        Defensive = { 0.2, 1.0,  0.2  },
        Utility   = { 0.2, 0.8,  1.0  },
    }
    return map[c] or map.Utility
end

local function toggleNode(specKey, nodeId, enabled)
    local map = getDisabledMap(specKey)
    if enabled then
        map[nodeId] = nil
    else
        map[nodeId] = true
    end
end

local function createCard(parent, node, y)
    local card = CreateFrame("Button", nil, parent)
    card:SetHeight(34)
    card:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, y)
    card:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, y)
    card.bg = card:CreateTexture(nil, "BACKGROUND")
    card.bg:SetTexture("Interface\\Buttons\\WHITE8X8")
    card.bg:SetVertexColor(0.09, 0.09, 0.09, 0.95)
    card.bg:SetAllPoints()

    local cb = CreateFrame("CheckButton", nil, card, "UICheckButtonTemplate")
    cb:SetWidth(22)
    cb:SetHeight(22)
    cb:SetPoint("LEFT", 6, 0)

    local icon = card:CreateTexture(nil, "ARTWORK")
    icon:SetWidth(26)
    icon:SetHeight(26)
    icon:SetPoint("LEFT", cb, "RIGHT", 8, 0)
    icon:SetTexture(specIcon(node.spellID))

    local rgb = colorOf(node.color)
    local fs = card:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fs:SetPoint("LEFT", icon, "RIGHT", 8, 0)
    fs:SetHeight(22)
    local hex = string.format("%02x%02x%02x", rgb[1] * 255, rgb[2] * 255, rgb[3] * 255)
    fs:SetText("|cff" .. hex .. (node.name or node.id) .. "|r")

    local disabled = getDisabledMap(currentSpec)
    cb:SetChecked(not disabled[node.id])
    cb:SetScript("OnClick", function(self)
        toggleNode(currentSpec, node.id, self:GetChecked() and true or false)
    end)
    return card
end

local function layoutSpec()
    if not scrollChild then return end
    for _, c in ipairs(cardFrames) do c:Hide() end
    cardFrames = {}
    local nodes = Hunter.RotationSpecs[currentSpec] and Hunter.RotationSpecs[currentSpec].nodes or {}
    local y = 0
    for _, n in ipairs(nodes) do
        cardFrames[#cardFrames + 1] = createCard(scrollChild, n, y)
        y = y - 38
    end
    scrollChild:SetHeight(math.max(-y, 1))
end

local function selectSpec(specKey)
    currentSpec = specKey
    for k, b in pairs(tabButtons) do
        local active = (k == currentSpec)
        b.bg:SetVertexColor(active and ORANGE[1] or 0.09, active and ORANGE[2] * 0.45 or 0.09, 0, active and 0.55 or 0.95)
        b.txt:SetTextColor(active and 1.0 or 0.9, active and 0.9 or 0.9, active and 0.6 or 0.9, 1)
    end
    layoutSpec()
end

local function createPanel()
    frame = CreateFrame("Frame", "CFA_HunterRotationEditor", UIParent, "BackdropTemplate")
    frame:SetWidth(PANEL_W)
    frame:SetHeight(PANEL_H)
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    frame:SetFrameStrata("DIALOG")
    frame:EnableMouse(true)
    applyBackdrop(frame, BG[1], BG[2], BG[3], BG[4])

    -- Drag bar
    local drag = CreateFrame("Frame", nil, frame)
    drag:SetPoint("TOPLEFT", 0, 0)
    drag:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -40, 0)
    drag:SetHeight(34)
    drag:EnableMouse(true)
    drag:SetScript("OnMouseDown", function(self)
        local mx, my = GetCursorPosition()
        local scale = self:GetEffectiveScale()
        local cx, cy = frame:GetCenter()
        if cx and cy then
            self.isDown = true
            self.dx = cx - mx / scale
            self.dy = cy - my / scale
        end
    end)
    drag:SetScript("OnMouseUp", function(self) self.isDown = false end)
    drag:SetScript("OnUpdate", function(self)
        if not self.isDown then return end
        if not IsMouseButtonDown("LeftButton") then self.isDown = false return end
        local mx, my = GetCursorPosition()
        local scale = self:GetEffectiveScale()
        local ux, uy = UIParent:GetCenter()
        local nx = mx / scale + self.dx - ux
        local ny = my / scale + self.dy - uy
        frame:ClearAllPoints()
        frame:SetPoint("CENTER", UIParent, "CENTER", nx, ny)
    end)

    -- Title
    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 14, -12)
    title:SetTextColor(ORANGE[1], ORANGE[2], ORANGE[3], 1)
    title:SetText("Editor de rotação — Hunter")

    -- Close X
    local close = CreateFrame("Button", nil, frame)
    close:SetWidth(26)
    close:SetHeight(26)
    close:SetPoint("TOPRIGHT", -8, -8)
    close:SetFrameLevel(frame:GetFrameLevel() + 20)
    close.txt = close:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    close.txt:SetPoint("CENTER", 0, 1)
    close.txt:SetText("X")
    close.txt:SetTextColor(1, 0.25, 0.25, 1)
    close:SetScript("OnClick", function() frame:Hide() end)
    close:SetScript("OnEnter", function(self) self.txt:SetTextColor(1, 0.45, 0.45, 1) end)
    close:SetScript("OnLeave", function(self) self.txt:SetTextColor(1, 0.25, 0.25, 1) end)

    -- Spec tabs
    local defs = { { "BM", "Beast Mastery" }, { "MM", "Marksmanship" }, { "SV", "Survival" } }
    local sx = 14
    for _, def in ipairs(defs) do
        local key, label = def[1], def[2]
        local b = CreateFrame("Button", nil, frame)
        b:SetWidth(140)
        b:SetHeight(30)
        b:SetPoint("TOPLEFT", frame, "TOPLEFT", sx, -40)
        b.bg = b:CreateTexture(nil, "BACKGROUND")
        b.bg:SetTexture("Interface\\Buttons\\WHITE8X8")
        b.bg:SetVertexColor(0.09, 0.09, 0.09, 0.95)
        b.bg:SetAllPoints()
        b.txt = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        b.txt:SetPoint("CENTER", 0, 0)
        b.txt:SetText(label)
        b:SetScript("OnClick", function() selectSpec(key) end)
        tabButtons[key] = b
        sx = sx + 148
    end

    -- Scroll child
    local scrollFrame = CreateFrame("ScrollFrame", "CFA_HunterRotationEditorScroll", frame, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 14, -76)
    scrollFrame:SetPoint("BOTTOMRIGHT", -32, 46)
    scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollChild:SetWidth(PANEL_W - 70)
    scrollChild:SetHeight(400)
    scrollFrame:SetScrollChild(scrollChild)

    local reset = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    reset:SetWidth(220)
    reset:SetHeight(24)
    reset:SetPoint("BOTTOMLEFT", 14, 12)
    reset:SetText("Restaurar rotação padrão")
    reset:SetScript("OnClick", function()
        if module.charDb and module.charDb.hunterDisabled then module.charDb.hunterDisabled[currentSpec] = nil end
        selectSpec(currentSpec)
    end)

    local hint = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("BOTTOMRIGHT", -14, 16)
    hint:SetText("Clique para ligar/desligar.")

    local det = module:DetectSpec()
    if det and Hunter.RotationSpecs[det] then currentSpec = det else currentSpec = "SV" end
    selectSpec(currentSpec)
end

function module.OpenRotationEditor()
    if not frame then createPanel() end
    frame:Show()
end
