-- Combat Forever Assistant — Hunter module: rotation editor window.
-- Dark panel + orange accent + red close X. Shows the rotation nodes for a
-- chosen spec and lets the player:
--   * toggle nodes on/off per character;
--   * add/remove conditions per node (6 cascade filter axes + special
--     predicates) — the "under which conditions this ability is called" option;
--   * click a node's icon to flash the button on the action bar (test).
-- Per-character overrides live in charDb.hunterRotation[spec][nodeId] and are
-- merged over the declared defaults by the module (see Scripts.lua).
local moduleName, module = ...

module.Hunter = module.Hunter or module
local Hunter = module.Hunter

local frame, scrollChild
local tabButtons = {}
local currentSpec = "SV"
local cardFrames = {}
local selectSpec  -- forward declaration (card buttons re-render the tab)
local resetButton, hintText

local PANEL_W, PANEL_H = 560, 440
local ROW_H = 46
local ORANGE = { 1.0, 0.55, 0.10 }
-- Opaque: the previous translucent panel let the window behind bleed through
local BG = { 0.02, 0.02, 0.02, 1.0 }

local L = module.L

local PTBR = (GetLocale and GetLocale() or "enUS") == "ptBR"
local function Loc(key, fallback)
    if L and L[key] then return L[key] end
    return fallback or key
end

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

-- ---------------------------------------------------------------------------
-- Condition text (line 2 of a card)
-- ---------------------------------------------------------------------------
local function stripAxisNumber(label)
    return (label or ""):gsub("^%d+%.%s*", "")
end

local function axisOptionLabel(axis, value)
    for _, opt in ipairs(axis.options or {}) do
        if opt[1] == value then
            local lk = opt[2]
            return (L and L[lk]) or lk
        end
    end
    return tostring(value)
end

local function NodeConditionText(node)
    local parts = {}
    if node.condition and node.condition ~= "" then
        local p = Hunter.RotationPredicates and Hunter.RotationPredicates[node.condition]
        parts[#parts + 1] = Loc("rot_special_prefix", "Especial: ") .. ((p and p.label) or node.condition)
    end
    if type(node.filter) == "table" then
        for _, axis in ipairs(module.FilterAxes or {}) do
            local v = tonumber(node.filter[axis.key]) or 0
            if v ~= 0 then
                local axisName = stripAxisNumber(Loc(axis.labelKey, axis.key))
                parts[#parts + 1] = axisName .. ": " .. axisOptionLabel(axis, v)
            end
        end
    end
    if #parts == 0 then return Loc("rot_no_condition", "- sem condições -") end
    return Loc("rot_conditions_prefix", "Condições: ") .. table.concat(parts, " · ")
end

module.NodeConditionText = NodeConditionText

local function getFilterTable(node)
    if type(node.filter) == "table" then
        local f = {}
        for k, v in pairs(node.filter) do f[k] = v end
        return f
    end
    return {}
end

-- ---------------------------------------------------------------------------
-- Picker popup (shared) — used by the [+] and [-] buttons of every card
-- ---------------------------------------------------------------------------
local picker = nil

local function GetPicker()
    if picker then return picker end
    picker = CreateFrame("Frame", "CFA_HunterRotationPicker", UIParent, "BackdropTemplate")
    picker:SetWidth(250)
    picker:SetFrameStrata("TOOLTIP")
    picker:SetAlpha(1)
    picker:EnableMouse(true)
    applyBackdrop(picker, 0.04, 0.04, 0.04, 1.0)
    local solidBg = picker:CreateTexture(nil, "BACKGROUND")
    solidBg:SetTexture("Interface\\Buttons\\WHITE8X8")
    solidBg:SetVertexColor(0.04, 0.04, 0.04, 1.0)
    solidBg:SetAllPoints()
    picker.rows = {}
    local title = picker:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    title:SetPoint("TOPLEFT", 10, -8)
    title:SetTextColor(ORANGE[1], ORANGE[2], ORANGE[3], 1)
    picker.title = title
    local sf = CreateFrame("ScrollFrame", nil, picker, "UIPanelScrollFrameTemplate")
    sf:SetPoint("TOPLEFT", 8, -26)
    sf:SetPoint("BOTTOMRIGHT", -28, 8)
    sf:EnableMouseWheel(true)
    sf:SetScript("OnMouseWheel", function(self, delta)
        local cur = self:GetVerticalScroll() or 0
        local childH = picker.child and picker.child:GetHeight() or 0
        local visible = self:GetHeight() or 0
        local maxScroll = math.max(0, childH - visible)
        self:SetVerticalScroll(math.max(0, math.min(maxScroll, cur - (delta > 0 and 30 or -30))))
    end)
    picker.scroll = sf
    local child = CreateFrame("Frame", nil, sf)
    child:SetWidth(212)
    sf:SetScrollChild(child)
    picker.child = child
    if type(UISpecialFrames) == "table" then tinsert(UISpecialFrames, "CFA_HunterRotationPicker") end
    return picker
end

local function RebuildPickerRows(p, titleText, getItems, afterAction)
    p.title:SetText(titleText)
    for _, r in ipairs(p.rows) do r:Hide(); r:SetParent(nil) end
    p.rows = {}
    local y = 0
    for _, item in ipairs(getItems()) do
        local pickerItem = item
        local row = CreateFrame(pickerItem.header and "Frame" or "Button", nil, p.child)
        local h = pickerItem.header and 16 or 20
        row:SetHeight(h)
        row:SetPoint("TOPLEFT", p.child, "TOPLEFT", 0, -y)
        row:SetWidth(206)
        if pickerItem.header then
            local fs = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
            fs:SetPoint("LEFT", 2, 0)
            fs:SetText(pickerItem.header)
        else
            row.mark = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            row.mark:SetPoint("LEFT", 6, 0)
            row.mark:SetText(pickerItem.checked and "|cffff8800●|r" or "")
            local fs = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            fs:SetPoint("LEFT", 20, 0)
            fs:SetPoint("RIGHT", -2, 0)
            fs:SetJustifyH("LEFT")
            fs:SetText(pickerItem.label)
            row:SetHighlightTexture("Interface\\Buttons\\WHITE8X8", "ADD")
            local hl = row:GetHighlightTexture()
            if hl then hl:SetVertexColor(0.35, 0.2, 0.05, 0.5) end
            row:SetScript("OnClick", function()
                pickerItem.action()
                if afterAction then afterAction() end
                RebuildPickerRows(p, titleText, getItems, afterAction)
            end)
        end
        y = y + h + 1
        p.rows[#p.rows + 1] = row
    end
    p.child:SetHeight(math.max(1, y))
    p:SetHeight(math.min(400, math.max(64, 34 + y)))
end

local function ShowPicker(anchorBtn, titleText, getItems, afterAction)
    local p = GetPicker()
    if p:IsShown() and p.owner == anchorBtn then
        p:Hide()
        return
    end
    p.owner = anchorBtn
    RebuildPickerRows(p, titleText, getItems, afterAction)
    p:ClearAllPoints()
    p:SetPoint("TOPLEFT", anchorBtn, "BOTTOMLEFT", 0, -2)
    p:Show()
end

local function sortedPredicateKeys(preds)
    local keys = {}
    for k in pairs(preds) do keys[#keys + 1] = k end
    table.sort(keys)
    return keys
end

local function setConditionValue(specKey, node, key, value, setter)
    if setter then
        setter(key, value)
    else
        module:SetNodeOverride(specKey, node.id, key, value)
    end
end

local function predicatesFor(sourceModule)
    if sourceModule == false then return {} end
    if type(sourceModule) == "table" then
        return type(sourceModule.RotationPredicates) == "table" and sourceModule.RotationPredicates or {}
    end
    return Hunter.RotationPredicates or {}
end

local function BuildAddItems(specKey, node, setter, sourceModule)
    local items = {}
    local function Header(t) items[#items + 1] = { header = t } end
    local function Item(label, active, action)
        items[#items + 1] = { label = label, checked = active and true or false, action = action }
    end
    for _, axis in ipairs(module.FilterAxes or {}) do
        local axisKey, axisLabelKey = axis.key, axis.labelKey
        Header(Loc(axisLabelKey, axisKey))
        for _, opt in ipairs(axis.options) do
            local value, lk = opt[1], opt[2]
            local label = (L and L[lk]) or lk
            local cur = type(node.filter) == "table" and tonumber(node.filter[axisKey]) or 0
            Item(label, cur == value, function()
                local f = getFilterTable(node)
                if tonumber(f[axisKey]) == value then
                    f[axisKey] = nil
                else
                    f[axisKey] = value
                end
                if next(f) then
                    setConditionValue(specKey, node, "filter", f, setter)
                else
                    setConditionValue(specKey, node, "filter", nil, setter)
                end
            end)
        end
    end
    local preds = predicatesFor(sourceModule)
    Header(Loc("rot_special_header", "Especial"))
    Item(Loc("rot_always", "Sempre"), (not node.condition or node.condition == ""), function()
        setConditionValue(specKey, node, "condition", "", setter)
    end)
    for _, key in ipairs(sortedPredicateKeys(preds)) do
        local predicateKey = key
        local p = preds[predicateKey]
        Item((p and p.label) or predicateKey, node.condition == predicateKey, function()
            setConditionValue(specKey, node, "condition", predicateKey, setter)
        end)
    end
    Header("------------------------")
    Item(Loc("rot_clear_all", "Remover todas as condições"), false, function()
        setConditionValue(specKey, node, "condition", nil, setter)
        setConditionValue(specKey, node, "filter", nil, setter)
    end)
    return items
end

local function BuildRemoveItems(specKey, node, setter, sourceModule)
    local items = {}
    local function Header(t) items[#items + 1] = { header = t } end
    local function Item(label, action)
        items[#items + 1] = { label = label, action = action }
    end
    local any = false
    if node.condition and node.condition ~= "" then
        local predicates = predicatesFor(sourceModule)
        local p = predicates and predicates[node.condition]
        Item(Loc("rot_special_prefix", "Especial: ") .. ((p and p.label) or node.condition), function()
            setConditionValue(specKey, node, "condition", nil, setter)
        end)
        any = true
    end
    if type(node.filter) == "table" then
        for _, axis in ipairs(module.FilterAxes or {}) do
            local axisKey = axis.key
            local v = tonumber(node.filter[axisKey])
            if v and v ~= 0 then
                local axisName = stripAxisNumber(Loc(axis.labelKey, axisKey))
                Item(axisName .. ": " .. axisOptionLabel(axis, v), function()
                    local f = getFilterTable(node)
                    f[axisKey] = nil
                    if next(f) then
                        setConditionValue(specKey, node, "filter", f, setter)
                    else
                        setConditionValue(specKey, node, "filter", nil, setter)
                    end
                end)
                any = true
            end
        end
    end
    if not any then Header(Loc("rot_none_active", "(nenhuma condição ativa)")) end
    Header("------------------------")
    Item(Loc("rot_clear_all", "Remover todas as condições"), function()
        setConditionValue(specKey, node, "condition", nil, setter)
        setConditionValue(specKey, node, "filter", nil, setter)
    end)
    return items
end

function module.ShowPicker(anchorBtn, titleText, getItems, afterAction)
    ShowPicker(anchorBtn, titleText, getItems, afterAction)
end

function module.HidePicker()
    if picker then picker:Hide() end
end

function module.ShowConditionPicker(anchorBtn, node, setter, afterAction, sourceModule)
    ShowPicker(anchorBtn, Loc("rot_add_condition", "Adicionar condição"),
        function() return BuildAddItems(nil, node, setter, sourceModule) end, afterAction)
end

function module.ShowRemoveConditionPicker(anchorBtn, node, setter, afterAction, sourceModule)
    ShowPicker(anchorBtn, Loc("rot_remove_condition", "Remover condição"),
        function() return BuildRemoveItems(nil, node, setter, sourceModule) end, afterAction)
end

-- ---------------------------------------------------------------------------
-- Cards
-- ---------------------------------------------------------------------------
local function cardDesaturate(iconBtn, disabled)
    local n = iconBtn:GetNormalTexture()
    if n and n.SetDesaturated then n:SetDesaturated(disabled and true or false) end
end

local function cropIconTexture(texture)
    if texture and type(texture.SetTexCoord) == "function" then
        texture:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    end
end

local function createCard(parent, specKey, node, y)
    local card = CreateFrame("Frame", nil, parent)
    card:SetHeight(ROW_H)
    card:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, y)
    card:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, y)
    card.bg = card:CreateTexture(nil, "BACKGROUND")
    card.bg:SetTexture("Interface\\Buttons\\WHITE8X8")
    card.bg:SetVertexColor(0.09, 0.09, 0.09, 1.0)
    card.bg:SetAllPoints()

    local cb = CreateFrame("CheckButton", nil, card, "UICheckButtonTemplate")
    cb:SetWidth(20)
    cb:SetHeight(20)
    cb:SetPoint("TOPLEFT", card, "TOPLEFT", 4, -2)

    -- Icon = click to flash the action-bar button (test)
    local iconBtn = CreateFrame("Button", nil, card)
    iconBtn:SetWidth(26)
    iconBtn:SetHeight(26)
    iconBtn:SetPoint("TOPLEFT", cb, "TOPRIGHT", 2, 0)
    local tex = specIcon(node.spellID)
    iconBtn:SetNormalTexture(tex)
    iconBtn:SetPushedTexture(tex)
    iconBtn:SetHighlightTexture(tex, "ADD")
    cropIconTexture(iconBtn:GetNormalTexture())
    cropIconTexture(iconBtn:GetPushedTexture())
    cropIconTexture(iconBtn:GetHighlightTexture())
    iconBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(tostring(node.name or node.id), 1, 1, 1)
        GameTooltip:AddLine(Loc("rot_click_test", "Clique para testar o flash na barra."), 0.6, 0.8, 1)
        GameTooltip:Show()
    end)
    iconBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    iconBtn:SetScript("OnClick", function()
        if module.FlashSpell then
            module:FlashSpell(node.spellID, node.color or "Utility")
        end
    end)

    local rgb = colorOf(node.color)
    local hex = string.format("%02x%02x%02x", rgb[1] * 255, rgb[2] * 255, rgb[3] * 255)
    local nameFS = card:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    nameFS:SetPoint("TOPLEFT", iconBtn, "TOPRIGHT", 6, -3)
    nameFS:SetWidth(170)
    nameFS:SetJustifyH("LEFT")
    nameFS:SetJustifyV("MIDDLE")

    local addBtn = CreateFrame("Button", nil, card, "UIPanelButtonTemplate")
    addBtn:SetWidth(26)
    addBtn:SetHeight(20)
    addBtn:SetPoint("TOPLEFT", card, "TOPLEFT", 240, -2)
    addBtn:SetText("+")

    local removeBtn = CreateFrame("Button", nil, card, "UIPanelButtonTemplate")
    removeBtn:SetWidth(26)
    removeBtn:SetHeight(20)
    removeBtn:SetPoint("LEFT", addBtn, "RIGHT", 3, 0)
    removeBtn:SetText("-")

    -- reorder: move this node one position up/down in the rotation chain
    local up = CreateFrame("Button", nil, card, "UIPanelButtonTemplate")
    up:SetWidth(18)
    up:SetHeight(18)
    up:SetPoint("TOPLEFT", card, "TOPLEFT", 302, -2)
    up:SetText("^")
    local down = CreateFrame("Button", nil, card, "UIPanelButtonTemplate")
    down:SetWidth(18)
    down:SetHeight(18)
    down:SetPoint("TOPLEFT", card, "TOPLEFT", 324, -2)
    down:SetText("v")
    up:SetScript("OnClick", function()
        if module.MoveNode then module:MoveNode(specKey, node.id, -1) end
        selectSpec(specKey)
    end)
    down:SetScript("OnClick", function()
        if module.MoveNode then module:MoveNode(specKey, node.id, 1) end
        selectSpec(specKey)
    end)

    local condFS = card:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    condFS:SetPoint("TOPLEFT", card, "TOPLEFT", 46, -24)
    condFS:SetWidth(PANEL_W - 70)
    condFS:SetJustifyH("LEFT")
    condFS:SetJustifyV("MIDDLE")

    local function refresh()
        local effective = {}
        if Hunter.GetEffectiveNodes then
            local nodes = Hunter:GetEffectiveNodes(specKey)
            if nodes then
                for _, n in ipairs(nodes) do effective[n.id] = n end
            end
        end
        local cur = effective[node.id] or node
        local disabled = (cur.enabled == false)
        cb:SetChecked(not disabled)
        cardDesaturate(iconBtn, disabled)
        nameFS:SetText((disabled and "|cff888888" or ("|cff" .. hex)) .. (node.name or node.id) .. "|r")
        condFS:SetText(NodeConditionText(cur))
    end

    cb:SetScript("OnClick", function(self)
        if self:GetChecked() then
            module:SetNodeOverride(specKey, node.id, "enabled", true)
        else
            module:SetNodeOverride(specKey, node.id, "enabled", false)
        end
        refresh()
    end)
    local function freshNode()
        local nodes = Hunter:GetEffectiveNodes(specKey) or {}
        for _, n in ipairs(nodes) do if n.id == node.id then return n end end
        return node
    end
    addBtn:SetScript("OnClick", function(self)
        ShowPicker(self, Loc("rot_add_condition", "Adicionar condição"),
            function() return BuildAddItems(specKey, freshNode()) end, refresh)
    end)
    removeBtn:SetScript("OnClick", function(self)
        ShowPicker(self, Loc("rot_remove_condition", "Remover condição"),
            function() return BuildRemoveItems(specKey, freshNode()) end, refresh)
    end)

    refresh()
    return card
end

local function layoutSpec()
    if not scrollChild then return end
    for _, c in ipairs(cardFrames) do c:Hide(); c:SetParent(nil) end
    cardFrames = {}
    local nodes = Hunter:GetEffectiveNodes(currentSpec)
    if not nodes then
        nodes = Hunter.RotationSpecs and Hunter.RotationSpecs[currentSpec] and Hunter.RotationSpecs[currentSpec].nodes or {}
    end
    local y = 0
    for _, n in ipairs(nodes) do
        cardFrames[#cardFrames + 1] = createCard(scrollChild, currentSpec, n, y)
        y = y - (ROW_H + 4)
    end
    scrollChild:SetHeight(math.max(-y, 1))
end

local function layoutExtra()
    if not scrollChild then return end
    for _, c in ipairs(cardFrames) do c:Hide(); c:SetParent(nil) end
    cardFrames = {}
    local aspects = {
        { "Cheetah", "extra_aspect_cheetah", "Aspect of the Cheetah" },
        { "Pack", "extra_aspect_pack", "Aspect of the Pack" },
        { "Monkey", "extra_aspect_monkey", "Aspect of the Monkey" },
        { "Beast", "extra_aspect_beast", "Aspect of the Beast" },
        { "Hawk", "extra_aspect_hawk", "Aspect of the Hawk" },
    }
    local y = -4
    for _, aspect in ipairs(aspects) do
        local aspectKey, labelKey, fallback = aspect[1], aspect[2], aspect[3]
        local row = CreateFrame("Frame", nil, scrollChild)
        row:SetHeight(30)
        row:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, y)
        row:SetPoint("TOPRIGHT", scrollChild, "TOPRIGHT", 0, y)
        local check = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
        check:SetPoint("TOPLEFT", row, "TOPLEFT", 2, -2)
        check:SetChecked(Hunter:IsAspectSuggestionEnabled(aspectKey))
        local label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        label:SetPoint("LEFT", check, "RIGHT", 4, 0)
        label:SetText(Loc(labelKey, fallback))
        check:SetScript("OnClick", function(self)
            Hunter:SetAspectSuggestionEnabled(aspectKey, self:GetChecked())
        end)
        cardFrames[#cardFrames + 1] = row
        y = y - 34
    end
    scrollChild:SetHeight(math.max(-y, 1))
end

selectSpec = function(specKey)
    currentSpec = specKey
    for k, b in pairs(tabButtons) do
        local active = (k == currentSpec)
        b.bg:SetVertexColor(active and ORANGE[1] or 0.09, active and ORANGE[2] * 0.45 or 0.09, 0, 1.0)
        b.txt:SetTextColor(active and 1.0 or 0.9, active and 0.9 or 0.9, active and 0.6 or 0.9, 1)
    end
    if currentSpec == "EXTRA" then
        if resetButton then resetButton:Hide() end
        if hintText then hintText:SetText(Loc("extra_hint", "Aspectos são independentes da rotação. Marque os que deseja receber; as condições de uso são automáticas.")) end
        layoutExtra()
    else
        if resetButton then resetButton:Show() end
        if hintText then hintText:SetText("Clique para ligar/desligar.") end
        layoutSpec()
    end
end

local function createPanel()
    frame = CreateFrame("Frame", "CFA_HunterRotationEditor", UIParent, "BackdropTemplate")
    frame:SetWidth(PANEL_W)
    frame:SetHeight(PANEL_H)
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    frame:SetFrameStrata("DIALOG")
    frame:SetAlpha(0.85)
    frame:SetToplevel(true)
    frame:EnableMouse(true)
    if type(UISpecialFrames) == "table" then tinsert(UISpecialFrames, "CFA_HunterRotationEditor") end
    applyBackdrop(frame, BG[1], BG[2], BG[3], BG[4])
    -- explicit solid background (see Options.lua: backdrop may silently no-op)
    local solidBg = frame:CreateTexture(nil, "BACKGROUND")
    solidBg:SetTexture("Interface\\Buttons\\WHITE8X8")
    solidBg:SetVertexColor(BG[1], BG[2], BG[3], 1)
    solidBg:SetAllPoints()
    -- closing the editor also dismisses the floating picker menu
    frame:SetScript("OnHide", function() if picker then picker:Hide() end end)

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

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 14, -12)
    title:SetTextColor(ORANGE[1], ORANGE[2], ORANGE[3], 1)
    title:SetText("Editor de rotação — Hunter")

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

    -- Spec tabs and talent-independent extra recommendations
    local defs = {
        { "BM", "Beast Mastery", 140 },
        { "MM", "Marksmanship", 140 },
        { "SV", "Survival", 140 },
        { "EXTRA", "Extra", 82 },
    }
    local sx = 14
    for _, def in ipairs(defs) do
        local key, label, width = def[1], def[2], def[3]
        local b = CreateFrame("Button", nil, frame)
        b:SetWidth(width)
        b:SetHeight(30)
        b:SetPoint("TOPLEFT", frame, "TOPLEFT", sx, -40)
        b.bg = b:CreateTexture(nil, "BACKGROUND")
        b.bg:SetTexture("Interface\\Buttons\\WHITE8X8")
        b.bg:SetVertexColor(0.09, 0.09, 0.09, 1.0)
        b.bg:SetAllPoints()
        b.txt = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        b.txt:SetPoint("CENTER", 0, 0)
        b.txt:SetText(label)
        b:SetScript("OnClick", function() selectSpec(key) end)
        tabButtons[key] = b
        sx = sx + width + 8
    end

    local scrollFrame = CreateFrame("ScrollFrame", "CFA_HunterRotationEditorScroll", frame, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 14, -76)
    scrollFrame:SetPoint("BOTTOMRIGHT", -32, 46)
    scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollChild:SetWidth(PANEL_W - 70)
    scrollChild:SetHeight(400)
    scrollFrame:SetScrollChild(scrollChild)

    resetButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    resetButton:SetWidth(230)
    resetButton:SetHeight(24)
    resetButton:SetPoint("BOTTOMLEFT", 14, 12)
    resetButton:SetText("Restaurar rotação padrão")
    resetButton:SetScript("OnClick", function()
        if module.ResetRotationOverrides then
            module:ResetRotationOverrides(currentSpec)
        end
        selectSpec(currentSpec)
    end)

    hintText = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hintText:SetPoint("BOTTOMRIGHT", -14, 16)
    hintText:SetText("Clique para ligar/desligar.")

    local det = Hunter.DetectSpec and Hunter:DetectSpec()
    if det and Hunter.RotationSpecs[det] then currentSpec = det else currentSpec = "SV" end
    selectSpec(currentSpec)
end

function module.OpenRotationEditor()
    if not frame then createPanel() end
    frame:Raise()
    frame:Show()
end
