local addonName, addon = ...
local L = addon.L
local ORANGE = { 1.0, 0.55, 0.10 }

local Editor = addon.RotationEditor or {}
addon.RotationEditor = Editor

local function translate(key, fallback)
    return (L and L[key]) or fallback or key
end

local function spellTexture(spellID)
    if type(spellID) == "number" then
        if C_Spell and type(C_Spell.GetSpellTexture) == "function" then
            local ok, texture = pcall(C_Spell.GetSpellTexture, spellID)
            if ok and texture then return texture end
        end
        if type(GetSpellTexture) == "function" then
            local ok, texture = pcall(GetSpellTexture, spellID)
            if ok and texture then return texture end
        end
    end
    return "Interface\\Icons\\INV_Misc_QuestionMark"
end

local function copyNode(node)
    local copy = {}
    for key, value in pairs(node) do
        if key == "filter" and type(value) == "table" then
            local filter = {}
            for filterKey, filterValue in pairs(value) do
                filter[filterKey] = filterValue
            end
            copy.filter = filter
        else
            copy[key] = value
        end
    end
    return copy
end

local function specsFor(module, preferredOrder)
    local specs, seen = {}, {}
    for _, key in ipairs(preferredOrder or {}) do
        if module.RotationSpecs[key] then
            specs[#specs + 1] = key
            seen[key] = true
        end
    end
    local remaining = {}
    for key, spec in pairs(module.RotationSpecs) do
        if not seen[key] and type(spec) == "table" then
            remaining[#remaining + 1] = key
        end
    end
    table.sort(remaining, function(a, b)
        local titleA = tostring(module.RotationSpecs[a].title or a)
        local titleB = tostring(module.RotationSpecs[b].title or b)
        return titleA < titleB
    end)
    for _, key in ipairs(remaining) do specs[#specs + 1] = key end
    return specs
end

local function settingsFor(storageKey, create)
    if type(addon.charDb) ~= "table" then return nil end
    local settings = addon.charDb[storageKey]
    if type(settings) ~= "table" and create then
        settings = {}
        addon.charDb[storageKey] = settings
    end
    return type(settings) == "table" and settings or nil
end

local function installNodeOverrides(module, storageKey)
    if type(module.GetEffectiveNodes) ~= "function" then
        function module:GetEffectiveNodes(specKey)
            local spec = self.RotationSpecs and self.RotationSpecs[specKey]
            if type(spec) ~= "table" or type(spec.nodes) ~= "table" then return nil end
            local settings = settingsFor(storageKey, false)
            local overrides = settings and settings.overrides and settings.overrides[specKey]
            local order = settings and settings.order and settings.order[specKey]
            local orderIndex, nodes, defaultIndex = {}, {}, {}
            if type(order) == "table" then
                for index, nodeID in ipairs(order) do orderIndex[nodeID] = index end
            end
            for index, base in ipairs(spec.nodes) do
                defaultIndex[base.id] = index
                local node = copyNode(base)
                local override = type(overrides) == "table" and overrides[base.id] or nil
                if type(override) == "table" then
                    for _, key in ipairs({ "enabled", "condition", "filter" }) do
                        if override[key] ~= nil then node[key] = override[key] end
                    end
                    if type(override.filter) == "table" then
                        local filter = {}
                        for key, value in pairs(override.filter) do filter[key] = value end
                        node.filter = next(filter) and filter or nil
                    end
                end
                nodes[#nodes + 1] = node
            end
            if next(orderIndex) then
                table.sort(nodes, function(a, b)
                    local aOrder, bOrder = orderIndex[a.id], orderIndex[b.id]
                    if aOrder and bOrder then return aOrder < bOrder end
                    if aOrder then return true end
                    if bOrder then return false end
                    return (defaultIndex[a.id] or 0) < (defaultIndex[b.id] or 0)
                end)
            end
            return nodes
        end
    end

    if type(module.SetNodeOverride) ~= "function" then
        function module:SetNodeOverride(specKey, nodeID, key, value)
            local spec = self.RotationSpecs and self.RotationSpecs[specKey]
            if type(spec) ~= "table" or type(spec.nodes) ~= "table" then return false end
            local found = false
            for _, node in ipairs(spec.nodes) do
                if node.id == nodeID then found = true break end
            end
            if not found then return false end
            if key == "enabled" then
                if value ~= nil and type(value) ~= "boolean" then return false end
            elseif key == "condition" then
                if value ~= nil and type(value) ~= "string" then return false end
            elseif key == "filter" then
                if value ~= nil and type(value) ~= "table" then return false end
            else
                return false
            end

            local settings = settingsFor(storageKey, value ~= nil)
            if not settings then return value == nil end
            local overrides = settings.overrides and settings.overrides[specKey]
            if value == nil and (not overrides or not overrides[nodeID]) then return true end
            settings.overrides = settings.overrides or {}
            settings.overrides[specKey] = settings.overrides[specKey] or {}
            overrides = settings.overrides[specKey]
            local override = overrides[nodeID]
            if value == nil then
                override[key] = nil
                if not next(override) then overrides[nodeID] = nil end
                if not next(overrides) then settings.overrides[specKey] = nil end
                if not next(settings.overrides) then settings.overrides = nil end
                if not next(settings) then addon.charDb[storageKey] = nil end
                return true
            end
            if not override then override = {}; overrides[nodeID] = override end
            if key == "filter" then
                local filter = {}
                for filterKey, filterValue in pairs(value) do filter[filterKey] = filterValue end
                override[key] = filter
            else
                override[key] = value
            end
            return true
        end
    end

    if type(module.MoveNode) ~= "function" then
        function module:MoveNode(specKey, nodeID, delta)
            local nodes = self:GetEffectiveNodes(specKey)
            if type(nodes) ~= "table" then return false end
            local order, index = {}, nil
            for i, node in ipairs(nodes) do
                order[i] = node.id
                if node.id == nodeID then index = i end
            end
            local target = index and index + delta
            if not target or target < 1 or target > #order then return false end
            order[index], order[target] = order[target], order[index]
            local settings = settingsFor(storageKey, true)
            if not settings then return false end
            settings.order = settings.order or {}
            settings.order[specKey] = order
            return true
        end
    end

    if type(module.ResetRotationOverrides) ~= "function" then
        function module:ResetRotationOverrides(specKey)
            local settings = settingsFor(storageKey, false)
            if not settings then return end
            if type(settings.overrides) == "table" then settings.overrides[specKey] = nil end
            if type(settings.order) == "table" then settings.order[specKey] = nil end
            if settings.overrides and not next(settings.overrides) then settings.overrides = nil end
            if settings.order and not next(settings.order) then settings.order = nil end
            if not next(settings) then addon.charDb[storageKey] = nil end
        end
    end
end

function Editor.Attach(module, config)
    config = config or {}
    if type(module) ~= "table" or type(module.RotationSpecs) ~= "table"
        or type(config.storageKey) ~= "string" then
        return false
    end
    installNodeOverrides(module, config.storageKey)

    local panel, scrollChild, hintText
    local rows, specButtons = {}, {}
    local currentSpec
    local specKeys = specsFor(module, config.specOrder)
    if #specKeys == 0 then return false end

    local function effectiveNodes(specKey)
        return module:GetEffectiveNodes(specKey)
            or (module.RotationSpecs[specKey] and module.RotationSpecs[specKey].nodes)
            or {}
    end

    local function renderSpec(specKey)
        currentSpec = specKey
        for key, button in pairs(specButtons) do
            local active = key == currentSpec
            button.bg:SetVertexColor(active and ORANGE[1] or 0.09,
                active and ORANGE[2] * 0.45 or 0.09, 0, 1)
            button.label:SetTextColor(active and 1 or 0.9,
                active and 0.9 or 0.9, active and 0.6 or 0.9, 1)
        end
        for _, row in ipairs(rows) do
            row:Hide()
            row:SetParent(nil)
        end
        rows = {}

        local nodes = effectiveNodes(specKey)
        if #nodes == 0 then
            local empty = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
            empty:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 8, -8)
            empty:SetText(translate("rotation_editor_empty", "No rotation abilities are defined."))
            rows[1] = empty
            scrollChild:SetHeight(48)
        else
            for index, node in ipairs(nodes) do
                local row = CreateFrame("Frame", nil, scrollChild)
                row:SetHeight(46)
                row:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, -((index - 1) * 48))
                row:SetPoint("TOPRIGHT", scrollChild, "TOPRIGHT", 0, -((index - 1) * 48))
                row.bg = row:CreateTexture(nil, "BACKGROUND")
                row.bg:SetTexture("Interface\\Buttons\\WHITE8X8")
                row.bg:SetVertexColor(0.09, 0.09, 0.09, 1)
                row.bg:SetAllPoints()

                local check = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
                check:SetSize(20, 20)
                check:SetPoint("TOPLEFT", row, "TOPLEFT", 4, -2)
                check:SetChecked(node.enabled ~= false)
                check:SetScript("OnClick", function(self)
                    module:SetNodeOverride(specKey, node.id, "enabled", self:GetChecked())
                    renderSpec(specKey)
                end)

                local icon = CreateFrame("Button", nil, row)
                icon:SetSize(26, 26)
                icon:SetPoint("LEFT", check, "RIGHT", 2, 0)
                icon:SetNormalTexture(spellTexture(node.spellID))
                icon:SetScript("OnClick", function()
                    if type(addon.FlashSpell) == "function" then
                        addon:FlashSpell(node.spellID, node.color or "Utility")
                    end
                end)

                local name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                name:SetPoint("LEFT", icon, "RIGHT", 6, 0)
                name:SetWidth(180)
                name:SetJustifyH("LEFT")
                name:SetText((node.enabled == false and "|cff888888" or "|cffffffff")
                    .. tostring(node.name or node.id) .. "|r")

                local condition = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
                condition:SetPoint("TOPLEFT", row, "TOPLEFT", 34, -26)
                condition:SetWidth(390)
                condition:SetJustifyH("LEFT")
                local predicate = node.condition and module.RotationPredicates
                    and module.RotationPredicates[node.condition]
                local conditionLabel = predicate and predicate.label or node.condition
                condition:SetText(conditionLabel and
                    (translate("rotation_editor_condition", "Condition") .. ": " .. tostring(conditionLabel)) or "")

                local up = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
                up:SetSize(20, 20)
                up:SetPoint("TOPRIGHT", row, "TOPRIGHT", -28, -2)
                up:SetText("^")
                up:SetScript("OnClick", function()
                    module:MoveNode(specKey, node.id, -1)
                    renderSpec(specKey)
                end)
                local down = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
                down:SetSize(20, 20)
                down:SetPoint("TOPRIGHT", row, "TOPRIGHT", -4, -2)
                down:SetText("v")
                down:SetScript("OnClick", function()
                    module:MoveNode(specKey, node.id, 1)
                    renderSpec(specKey)
                end)
                rows[#rows + 1] = row
            end
            scrollChild:SetHeight(math.max(#nodes * 48, 1))
        end
        hintText:SetText(translate("rotation_editor_toggle_hint",
            "Toggle abilities or move them to change their priority."))
    end

    local function createPanel()
        panel = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
        panel:SetSize(560, 440)
        panel:SetPoint("CENTER")
        panel:SetFrameStrata("DIALOG")
        panel:SetMovable(true)
        panel:EnableMouse(true)
        panel:SetClampedToScreen(true)
        panel:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            tile = true, tileSize = 8, edgeSize = 1,
            insets = { left = 0, right = 0, top = 0, bottom = 0 },
        })
        panel:SetBackdropColor(0.02, 0.02, 0.02, 1)
        panel:SetBackdropBorderColor(ORANGE[1], ORANGE[2], ORANGE[3], 0.55)

        local drag = CreateFrame("Frame", nil, panel)
        drag:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, 0)
        drag:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -40, 0)
        drag:SetHeight(34)
        drag:EnableMouse(true)
        drag:SetScript("OnMouseDown", function(_, button)
            if button == "LeftButton" then panel:StartMoving() end
        end)
        drag:SetScript("OnMouseUp", function() panel:StopMovingOrSizing() end)

        local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        title:SetPoint("TOPLEFT", panel, "TOPLEFT", 14, -12)
        title:SetTextColor(ORANGE[1], ORANGE[2], ORANGE[3], 1)
        title:SetText(translate("rotation_editor_title", "Rotation editor")
            .. " - " .. tostring(config.title or module.classTag or "Class"))

        local close = CreateFrame("Button", nil, panel)
        close:SetSize(26, 26)
        close:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -8, -8)
        local closeLabel = close:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        closeLabel:SetPoint("CENTER", close, "CENTER", 0, 1)
        closeLabel:SetText("X")
        closeLabel:SetTextColor(1, 0.25, 0.25, 1)
        close:SetScript("OnClick", function() panel:Hide() end)

        local spacing = 6
        local buttonWidth = math.floor((532 - spacing * (#specKeys - 1)) / #specKeys)
        for index, specKey in ipairs(specKeys) do
            local button = CreateFrame("Button", nil, panel)
            button:SetSize(buttonWidth, 30)
            button:SetPoint("TOPLEFT", panel, "TOPLEFT",
                14 + (index - 1) * (buttonWidth + spacing), -40)
            button.bg = button:CreateTexture(nil, "BACKGROUND")
            button.bg:SetTexture("Interface\\Buttons\\WHITE8X8")
            button.bg:SetVertexColor(0.09, 0.09, 0.09, 1)
            button.bg:SetAllPoints()
            button.label = button:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            button.label:SetPoint("CENTER", button, "CENTER", 0, 0)
            button.label:SetText(module.RotationSpecs[specKey].title or specKey)
            button:SetScript("OnClick", function() renderSpec(specKey) end)
            specButtons[specKey] = button
        end

        local scrollFrame = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
        scrollFrame:SetPoint("TOPLEFT", panel, "TOPLEFT", 14, -78)
        scrollFrame:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -32, 48)
        scrollChild = CreateFrame("Frame", nil, scrollFrame)
        scrollChild:SetWidth(490)
        scrollChild:SetHeight(1)
        scrollFrame:SetScrollChild(scrollChild)

        local reset = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
        reset:SetSize(230, 24)
        reset:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 14, 12)
        reset:SetText(translate("rotation_editor_reset", "Reset this specialization"))
        reset:SetScript("OnClick", function()
            if type(module.ResetRotationOverrides) == "function" then
                module:ResetRotationOverrides(currentSpec)
            end
            renderSpec(currentSpec)
        end)

        hintText = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        hintText:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -14, 16)
        hintText:SetJustifyH("RIGHT")
    end

    local function open()
        local detected = type(module.DetectSpec) == "function" and module:DetectSpec() or nil
        local initialSpec = currentSpec or detected
        local validSpec = false
        for _, specKey in ipairs(specKeys) do
            if specKey == initialSpec then validSpec = true break end
        end
        if not validSpec then initialSpec = specKeys[1] end
        if not panel then createPanel() end
        renderSpec(initialSpec)
        panel:Raise()
        panel:Show()
        return true
    end

    module.OpenRotationEditor = open
    return true
end
