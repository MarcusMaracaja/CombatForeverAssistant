-- Combat Forever Assistant — Shared rotation editor & condition picker.
-- Used by ALL class modules (Hunter, Shaman, Druid, future classes) and by
-- Equipment.lua for per-item condition rules.
local _, addon = ...
local L = addon.L
local ORANGE = { 1.0, 0.55, 0.10 }

local Editor = addon.RotationEditor or {}
addon.RotationEditor = Editor

local function translate(key, fallback)
    return (L and L[key]) or fallback or key
end

local function applyBackdrop(frame, r, g, b, a)
    if frame.SetBackdrop then
        frame:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            tile = true, tileSize = 8, edgeSize = 1,
            insets = { left = 0, right = 0, top = 0, bottom = 0 },
        })
        frame:SetBackdropColor(r, g, b, a)
        frame:SetBackdropBorderColor(ORANGE[1], ORANGE[2], ORANGE[3], 0.55)
    end
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

local function cropIconTexture(texture)
    if texture and type(texture.SetTexCoord) == "function" then
        texture:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    end
end

local function colorHexOf(colorKey)
    local map = {
        Damage    = "ff4444",
        AoE       = "ff8c19",
        Interrupt = "ffff26",
        Defensive = "33ff33",
        Utility   = "33ccff",
    }
    return map[colorKey] or "ffffff"
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

local function getFilterTable(node)
    local f = {}
    if type(node) == "table" and type(node.filter) == "table" then
        for k, v in pairs(node.filter) do f[k] = v end
    end
    return f
end

local function stripAxisNumber(label)
    return (label or ""):gsub("^%d+%.%s*", "")
end

local function axisOptionLabel(axis, value)
    for _, opt in ipairs(axis.options or {}) do
        if opt[1] == value then
            return translate(opt[2], opt[2])
        end
    end
    return tostring(value)
end

local function predicatesFor(sourceModule)
    if sourceModule == false then return {} end
    local merged = {}
    if type(addon.RotationPredicates) == "table" then
        for k, v in pairs(addon.RotationPredicates) do merged[k] = v end
    end
    if type(sourceModule) == "table" and type(sourceModule.RotationPredicates) == "table" then
        for k, v in pairs(sourceModule.RotationPredicates) do merged[k] = v end
    end
    return merged
end

local function sortedPredicateKeys(preds)
    local keys = {}
    for k in pairs(preds) do keys[#keys + 1] = k end
    table.sort(keys)
    return keys
end

-- ---------------------------------------------------------------------------
-- Shared condition text formatter (used by class editors and Equipment.lua)
-- ---------------------------------------------------------------------------
function Editor.NodeConditionText(node, sourceModule)
    if type(node) ~= "table" then return translate("rot_no_condition", "- sem condições -") end
    local parts = {}
    if node.condition and node.condition ~= "" then
        local preds = predicatesFor(sourceModule or addon.activeModule)
        local p = preds[node.condition]
        parts[#parts + 1] = translate("rot_special_prefix", "Especial: ") .. ((p and p.label) or node.condition)
    end
    if type(node.filter) == "table" then
        for _, axis in ipairs(addon.FilterAxes or {}) do
            local v = tonumber(node.filter[axis.key]) or 0
            if v ~= 0 then
                local axisName = stripAxisNumber(translate(axis.labelKey, axis.key))
                parts[#parts + 1] = axisName .. ": " .. axisOptionLabel(axis, v)
            end
        end
    end
    if #parts == 0 then return translate("rot_no_condition", "- sem condições -") end
    return translate("rot_conditions_prefix", "Condições: ") .. table.concat(parts, " · ")
end

-- ---------------------------------------------------------------------------
-- Shared opaque picker popup (parented to UIParent, TOOLTIP strata, alpha 1)
-- ---------------------------------------------------------------------------
local picker = nil

local function GetPicker()
    if picker then return picker end
    picker = CreateFrame("Frame", "CFA_SharedConditionPicker", UIParent, "BackdropTemplate")
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
    if type(UISpecialFrames) == "table" then table.insert(UISpecialFrames, "CFA_SharedConditionPicker") end
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

function Editor.ShowPicker(anchorBtn, titleText, getItems, afterAction)
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

function Editor.HidePicker()
    if picker then picker:Hide() end
end

local function BuildAddItems(targetModule, specKey, node, setter, sourceModule)
    local items = {}
    local function Header(t) items[#items + 1] = { header = t } end
    local function Item(label, active, action)
        items[#items + 1] = { label = label, checked = active and true or false, action = action }
    end
    local function apply(key, value)
        if setter then
            setter(key, value)
        elseif targetModule and targetModule.SetNodeOverride then
            targetModule:SetNodeOverride(specKey, node.id, key, value)
        end
    end
    for _, axis in ipairs(addon.FilterAxes or {}) do
        local axisKey, axisLabelKey = axis.key, axis.labelKey
        Header(translate(axisLabelKey, axisKey))
        for _, opt in ipairs(axis.options) do
            local value, lk = opt[1], opt[2]
            local label = translate(lk, lk)
            local cur = type(node.filter) == "table" and tonumber(node.filter[axisKey]) or 0
            Item(label, cur == value, function()
                local f = getFilterTable(node)
                if tonumber(f[axisKey]) == value then
                    f[axisKey] = nil
                else
                    f[axisKey] = value
                end
                if next(f) then
                    apply("filter", f)
                    node.filter = f
                else
                    apply("filter", nil)
                    node.filter = nil
                end
            end)
        end
    end
    local preds = predicatesFor(sourceModule or targetModule)
    Header(translate("rot_special_header", "Especial"))
    Item(translate("rot_always", "Sempre"), (not node.condition or node.condition == ""), function()
        apply("condition", "")
        node.condition = ""
    end)
    for _, key in ipairs(sortedPredicateKeys(preds)) do
        local predicateKey = key
        local p = preds[predicateKey]
        Item((p and p.label) or predicateKey, node.condition == predicateKey, function()
            apply("condition", predicateKey)
            node.condition = predicateKey
        end)
    end
    Header("------------------------")
    Item(translate("rot_clear_all", "Remover todas as condições"), false, function()
        apply("condition", nil)
        apply("filter", nil)
        node.condition = nil
        node.filter = nil
    end)
    return items
end

local function BuildRemoveItems(targetModule, specKey, node, setter, sourceModule)
    local items = {}
    local function Header(t) items[#items + 1] = { header = t } end
    local function Item(label, action)
        items[#items + 1] = { label = label, action = action }
    end
    local function apply(key, value)
        if setter then
            setter(key, value)
        elseif targetModule and targetModule.SetNodeOverride then
            targetModule:SetNodeOverride(specKey, node.id, key, value)
        end
    end
    local any = false
    if node.condition and node.condition ~= "" then
        local preds = predicatesFor(sourceModule or targetModule)
        local p = preds[node.condition]
        Item(translate("rot_special_prefix", "Especial: ") .. ((p and p.label) or node.condition), function()
            apply("condition", nil)
            node.condition = nil
        end)
        any = true
    end
    if type(node.filter) == "table" then
        for _, axis in ipairs(addon.FilterAxes or {}) do
            local axisKey = axis.key
            local v = tonumber(node.filter[axisKey])
            if v and v ~= 0 then
                local axisName = stripAxisNumber(translate(axis.labelKey, axisKey))
                Item(axisName .. ": " .. axisOptionLabel(axis, v), function()
                    local f = getFilterTable(node)
                    f[axisKey] = nil
                    if next(f) then
                        apply("filter", f)
                        node.filter = f
                    else
                        apply("filter", nil)
                        node.filter = nil
                    end
                end)
                any = true
            end
        end
    end
    if not any then Header(translate("rot_none_active", "(nenhuma condição ativa)")) end
    Header("------------------------")
    Item(translate("rot_clear_all", "Remover todas as condições"), function()
        apply("condition", nil)
        apply("filter", nil)
        node.condition = nil
        node.filter = nil
    end)
    return items
end

function Editor.ShowConditionPicker(anchorBtn, node, setter, afterAction, sourceModule)
    Editor.ShowPicker(anchorBtn, translate("rot_add_condition", "Adicionar condição"),
        function() return BuildAddItems(nil, nil, node, setter, sourceModule) end, afterAction)
end

function Editor.ShowRemoveConditionPicker(anchorBtn, node, setter, afterAction, sourceModule)
    Editor.ShowPicker(anchorBtn, translate("rot_remove_condition", "Remover condição"),
        function() return BuildRemoveItems(nil, nil, node, setter, sourceModule) end, afterAction)
end

-- ---------------------------------------------------------------------------
-- Per-module editor attachment
-- ---------------------------------------------------------------------------
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

    local panel, scrollChild, hintText, resetButton
    local rows, specButtons, extraButtons = {}, {}, {}
    local currentSpec, currentExtra
    local specKeys = specsFor(module, config.specOrder)
    local extraTabs = type(config.extraTabs) == "table" and config.extraTabs or {}
    if #specKeys == 0 and #extraTabs == 0 then return false end

    local extraByKey = {}
    for _, tab in ipairs(extraTabs) do
        if type(tab) == "table" and tab.key then
            extraByKey[tab.key] = tab
        end
    end

    local function effectiveNodes(specKey)
        return module:GetEffectiveNodes(specKey)
            or (module.RotationSpecs[specKey] and module.RotationSpecs[specKey].nodes)
            or {}
    end

    local renderSpec, renderExtra

    renderSpec = function(specKey)
        Editor.HidePicker()
        currentSpec = specKey
        currentExtra = nil
        for key, button in pairs(specButtons) do
            local active = key == currentSpec
            button.bg:SetVertexColor(active and ORANGE[1] or 0.09,
                active and ORANGE[2] * 0.45 or 0.09, 0, 1)
            button.label:SetTextColor(active and 1 or 0.9,
                active and 0.9 or 0.9, active and 0.6 or 0.9, 1)
        end
        for _, button in pairs(extraButtons) do
            button.bg:SetVertexColor(0.09, 0.09, 0.09, 1)
            button.label:SetTextColor(0.9, 0.9, 0.9, 1)
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
                local currentNode = node
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
                check:SetChecked(currentNode.enabled ~= false)
                check:SetScript("OnClick", function(self)
                    module:SetNodeOverride(specKey, currentNode.id, "enabled", self:GetChecked() and true or false)
                    renderSpec(specKey)
                end)

                local icon = CreateFrame("Button", nil, row)
                icon:SetSize(26, 26)
                icon:SetPoint("TOPLEFT", check, "TOPRIGHT", 2, 0)
                local tex = spellTexture(currentNode.spellID)
                icon:SetNormalTexture(tex)
                cropIconTexture(icon:GetNormalTexture())
                icon:SetScript("OnClick", function()
                    if type(addon.FlashSpell) == "function" then
                        addon:FlashSpell(currentNode.spellID, currentNode.color or "Utility")
                    end
                end)

                local name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                name:SetPoint("TOPLEFT", icon, "TOPRIGHT", 6, -3)
                name:SetWidth(175)
                name:SetJustifyH("LEFT")
                local hex = currentNode.enabled == false and "888888" or colorHexOf(currentNode.color)
                name:SetText("|cff" .. hex .. tostring(currentNode.name or currentNode.id) .. "|r")

                local addBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
                addBtn:SetSize(24, 20)
                addBtn:SetPoint("TOPLEFT", row, "TOPLEFT", 240, -2)
                addBtn:SetText("+")
                addBtn:SetScript("OnClick", function(self)
                    Editor.ShowPicker(self, translate("rot_add_condition", "Adicionar condição"),
                        function() return BuildAddItems(module, specKey, currentNode, nil, module) end,
                        function() renderSpec(specKey) end)
                end)

                local removeBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
                removeBtn:SetSize(24, 20)
                removeBtn:SetPoint("LEFT", addBtn, "RIGHT", 3, 0)
                removeBtn:SetText("-")
                removeBtn:SetScript("OnClick", function(self)
                    Editor.ShowPicker(self, translate("rot_remove_condition", "Remover condição"),
                        function() return BuildRemoveItems(module, specKey, currentNode, nil, module) end,
                        function() renderSpec(specKey) end)
                end)

                local condition = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
                condition:SetPoint("TOPLEFT", row, "TOPLEFT", 34, -26)
                condition:SetWidth(420)
                condition:SetJustifyH("LEFT")
                local conditionText = ""
                if type(config.conditionTextFn) == "function" then
                    conditionText = config.conditionTextFn(module, currentNode) or ""
                else
                    conditionText = Editor.NodeConditionText(currentNode, module)
                end
                condition:SetText(conditionText)

                local up = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
                up:SetSize(20, 20)
                up:SetPoint("TOPRIGHT", row, "TOPRIGHT", -28, -2)
                up:SetText("^")
                up:SetScript("OnClick", function()
                    module:MoveNode(specKey, currentNode.id, -1)
                    renderSpec(specKey)
                end)

                local down = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
                down:SetSize(20, 20)
                down:SetPoint("TOPRIGHT", row, "TOPRIGHT", -4, -2)
                down:SetText("v")
                down:SetScript("OnClick", function()
                    module:MoveNode(specKey, currentNode.id, 1)
                    renderSpec(specKey)
                end)

                rows[#rows + 1] = row
            end
            scrollChild:SetHeight(math.max(#nodes * 48, 1))
        end
        if resetButton then resetButton:Show() end
        hintText:SetText(translate("rotation_editor_toggle_hint",
            "Toggle abilities or move them to change their priority."))
    end

    renderExtra = function(tabKey)
        Editor.HidePicker()
        local tab = extraByKey[tabKey]
        if not tab then return end
        currentSpec = nil
        currentExtra = tabKey
        for _, b in pairs(specButtons) do
            b.bg:SetVertexColor(0.09, 0.09, 0.09, 1)
            b.label:SetTextColor(0.9, 0.9, 0.9, 1)
        end
        for key, b in pairs(extraButtons) do
            local active = key == tabKey
            b.bg:SetVertexColor(active and ORANGE[1] or 0.09,
                active and ORANGE[2] * 0.45 or 0.09, 0, 1)
            b.label:SetTextColor(active and 1 or 0.9,
                active and 0.9 or 0.9, active and 0.6 or 0.9, 1)
        end
        for _, row in ipairs(rows) do
            row:Hide()
            row:SetParent(nil)
        end
        rows = {}
        if type(tab.render) == "function" then
            tab.render(scrollChild, module, rows)
        else
            local empty = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
            empty:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 8, -8)
            empty:SetText(translate("rotation_editor_empty", "No content defined for this tab."))
            rows[1] = empty
            scrollChild:SetHeight(48)
        end
        if resetButton then resetButton:Hide() end
        hintText:SetText(tab.hint or "")
    end

    local function createPanel()
        local frameName = "CFA_RotationEditor_" .. tostring(module.classTag or config.storageKey)
        panel = CreateFrame("Frame", frameName, UIParent, "BackdropTemplate")
        panel:SetSize(560, 440)
        panel:SetPoint("CENTER")
        panel:SetFrameStrata("DIALOG")
        panel:SetToplevel(true)
        panel:SetMovable(true)
        panel:EnableMouse(true)
        panel:SetClampedToScreen(true)
        panel:SetAlpha(0.92)
        applyBackdrop(panel, 0.02, 0.02, 0.02, 1)
        local solidBg = panel:CreateTexture(nil, "BACKGROUND")
        solidBg:SetTexture("Interface\\Buttons\\WHITE8X8")
        solidBg:SetVertexColor(0.02, 0.02, 0.02, 1)
        solidBg:SetAllPoints()
        panel:SetScript("OnHide", function() Editor.HidePicker() end)
        if type(UISpecialFrames) == "table" then table.insert(UISpecialFrames, frameName) end

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
        title:SetText(config.title or (translate("rotation_editor_title", "Rotation editor")
            .. " - " .. tostring(module.classTag or "Class")))

        local close = CreateFrame("Button", nil, panel)
        close:SetSize(26, 26)
        close:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -8, -8)
        local closeLabel = close:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        closeLabel:SetPoint("CENTER", close, "CENTER", 0, 1)
        closeLabel:SetText("X")
        closeLabel:SetTextColor(1, 0.25, 0.25, 1)
        close:SetScript("OnClick", function() panel:Hide() end)

        local spacing = 6
        local totalButtons = #specKeys + #extraTabs
        local buttonWidth = math.floor((532 - spacing * (totalButtons - 1)) / totalButtons)
        local bx = 14
        for _, specKey in ipairs(specKeys) do
            local key = specKey
            local button = CreateFrame("Button", nil, panel)
            button:SetSize(buttonWidth, 30)
            button:SetPoint("TOPLEFT", panel, "TOPLEFT", bx, -40)
            button.bg = button:CreateTexture(nil, "BACKGROUND")
            button.bg:SetTexture("Interface\\Buttons\\WHITE8X8")
            button.bg:SetVertexColor(0.09, 0.09, 0.09, 1)
            button.bg:SetAllPoints()
            button.label = button:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            button.label:SetPoint("CENTER", button, "CENTER", 0, 0)
            button.label:SetText(module.RotationSpecs[key].title or key)
            button:SetScript("OnClick", function() renderSpec(key) end)
            specButtons[key] = button
            bx = bx + buttonWidth + spacing
        end
        for _, tab in ipairs(extraTabs) do
            local tabKey = tab.key
            local button = CreateFrame("Button", nil, panel)
            button:SetSize(buttonWidth, 30)
            button:SetPoint("TOPLEFT", panel, "TOPLEFT", bx, -40)
            button.bg = button:CreateTexture(nil, "BACKGROUND")
            button.bg:SetTexture("Interface\\Buttons\\WHITE8X8")
            button.bg:SetVertexColor(0.09, 0.09, 0.09, 1)
            button.bg:SetAllPoints()
            button.label = button:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            button.label:SetPoint("CENTER", button, "CENTER", 0, 0)
            button.label:SetText(tab.label or tabKey)
            button:SetScript("OnClick", function() renderExtra(tabKey) end)
            extraButtons[tabKey] = button
            bx = bx + buttonWidth + spacing
        end

        local scrollFrame = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
        scrollFrame:SetPoint("TOPLEFT", panel, "TOPLEFT", 14, -78)
        scrollFrame:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -32, 48)
        scrollChild = CreateFrame("Frame", nil, scrollFrame)
        scrollChild:SetWidth(490)
        scrollChild:SetHeight(1)
        scrollFrame:SetScrollChild(scrollChild)

        resetButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
        resetButton:SetSize(230, 24)
        resetButton:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 14, 12)
        resetButton:SetText(translate("rotation_editor_reset", "Reset this specialization"))
        resetButton:SetScript("OnClick", function()
            if currentSpec and type(module.ResetRotationOverrides) == "function" then
                module:ResetRotationOverrides(currentSpec)
                renderSpec(currentSpec)
            end
        end)

        hintText = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        hintText:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -14, 16)
        hintText:SetPoint("LEFT", resetButton, "RIGHT", 10, 0)
        hintText:SetJustifyH("RIGHT")
    end

    local function open()
        local detected = type(module.DetectSpec) == "function" and module:DetectSpec() or nil
        local initialSpec = currentSpec or detected
        local validSpec = false
        for _, specKey in ipairs(specKeys) do
            if specKey == initialSpec then validSpec = true break end
        end
        if not panel then createPanel() end
        if validSpec then
            renderSpec(initialSpec)
        elseif currentExtra and extraByKey[currentExtra] then
            renderExtra(currentExtra)
        elseif specKeys[1] then
            renderSpec(specKeys[1])
        elseif extraTabs[1] and extraTabs[1].key then
            renderExtra(extraTabs[1].key)
        else
            return false
        end
        panel:Raise()
        panel:Show()
        return true
    end

    module.OpenRotationEditor = open
    return true
end
