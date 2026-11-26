-- Combat Forever Assistant — equipment item recommendations.
local addonName, addon = ...
local L = addon.L

local Equipment = {}
addon.Equipment = Equipment

local QUESTION_MARK = "Interface\\Icons\\INV_Misc_QuestionMark"
local SLOT_DEFS = {
    { key = "HeadSlot", api = "HeadSlot", label = "equip_slot_head", equip = { INVTYPE_HEAD = true } },
    { key = "NeckSlot", api = "NeckSlot", label = "equip_slot_neck", equip = { INVTYPE_NECK = true } },
    { key = "ShoulderSlot", api = "ShoulderSlot", label = "equip_slot_shoulder", equip = { INVTYPE_SHOULDER = true } },
    { key = "ShirtSlot", api = "ShirtSlot", label = "equip_slot_shirt", equip = { INVTYPE_BODY = true } },
    { key = "ChestSlot", api = "ChestSlot", label = "equip_slot_chest", equip = { INVTYPE_CHEST = true, INVTYPE_ROBE = true } },
    { key = "WaistSlot", api = "WaistSlot", label = "equip_slot_waist", equip = { INVTYPE_WAIST = true } },
    { key = "LegsSlot", api = "LegsSlot", label = "equip_slot_legs", equip = { INVTYPE_LEGS = true } },
    { key = "FeetSlot", api = "FeetSlot", label = "equip_slot_feet", equip = { INVTYPE_FEET = true } },
    { key = "WristSlot", api = "WristSlot", label = "equip_slot_wrist", equip = { INVTYPE_WRIST = true } },
    { key = "HandsSlot", api = "HandsSlot", label = "equip_slot_hands", equip = { INVTYPE_HAND = true } },
    { key = "Finger0Slot", api = "Finger0Slot", label = "equip_slot_finger0", equip = { INVTYPE_FINGER = true } },
    { key = "Finger1Slot", api = "Finger1Slot", label = "equip_slot_finger1", equip = { INVTYPE_FINGER = true } },
    { key = "Trinket0Slot", api = "Trinket0Slot", label = "equip_slot_trinket0", equip = { INVTYPE_TRINKET = true } },
    { key = "Trinket1Slot", api = "Trinket1Slot", label = "equip_slot_trinket1", equip = { INVTYPE_TRINKET = true } },
    { key = "BackSlot", api = "BackSlot", label = "equip_slot_back", equip = { INVTYPE_CLOAK = true } },
    { key = "MainHandSlot", api = "MainHandSlot", label = "equip_slot_mainhand", equip = { INVTYPE_WEAPON = true, INVTYPE_2HWEAPON = true, INVTYPE_WEAPONMAINHAND = true } },
    { key = "SecondaryHandSlot", api = "SecondaryHandSlot", label = "equip_slot_offhand", equip = { INVTYPE_WEAPON = true, INVTYPE_WEAPONOFFHAND = true, INVTYPE_SHIELD = true, INVTYPE_HOLDABLE = true } },
    { key = "RangedSlot", api = "RangedSlot", label = "equip_slot_ranged", equip = { INVTYPE_RANGED = true, INVTYPE_RANGEDRIGHT = true, INVTYPE_THROWN = true, INVTYPE_RELIC = true } },
    { key = "TabardSlot", api = "TabardSlot", label = "equip_slot_tabard", equip = { INVTYPE_TABARD = true } },
}

local function safeCall(fn, ...)
    if type(fn) ~= "function" then return false end
    return pcall(fn, ...)
end

local function inventorySlotID(slotName)
    local ok, id = safeCall(GetInventorySlotInfo, slotName)
    if ok and type(id) == "number" then return id end
    return nil
end

local function itemInfo(itemID)
    local getter = GetItemInfo
    if C_Item and type(C_Item.GetItemInfo) == "function" then getter = C_Item.GetItemInfo end
    local ok, name, link, quality, _, _, _, _, _, equipLoc, texture = safeCall(getter, itemID)
    if not ok then return nil end
    return {
        name = type(name) == "string" and name or ("Item " .. tostring(itemID)),
        link = link,
        quality = quality,
        equipLoc = equipLoc,
        texture = texture,
    }
end

local function itemEquipLoc(itemID, info)
    if info and info.equipLoc then return info.equipLoc end
    local getter = GetItemInfoInstant
    if C_Item and type(C_Item.GetItemInfoInstant) == "function" then getter = C_Item.GetItemInfoInstant end
    local ok, _, _, _, equipLoc = safeCall(getter, itemID)
    if ok then return equipLoc end
    return nil
end

local function itemLinkID(link)
    if type(link) ~= "string" then return nil end
    return tonumber(link:match("item:(%d+)"))
end

local function containerItemID(bag, slot)
    local container = C_Container
    if container and type(container.GetContainerItemID) == "function" then
        local ok, id = safeCall(container.GetContainerItemID, bag, slot)
        if ok and type(id) == "number" then return id end
    end
    if type(GetContainerItemID) == "function" then
        local ok, id = safeCall(GetContainerItemID, bag, slot)
        if ok and type(id) == "number" then return id end
    end
    local getLink = container and container.GetContainerItemLink or GetContainerItemLink
    local ok, link = safeCall(getLink, bag, slot)
    if ok then return itemLinkID(link) end
    return nil
end

-- Verifica se um item está em cooldown. Usa C_Item.GetItemCooldown (moderna)
-- com fallback para GetItemCooldown (legada). Retorna true se estiver em CD.
local function itemIsOnCooldown(itemID)
    if type(itemID) ~= "number" then return false end
    local start, duration, enable = 0, 0, 1
    if C_Item and type(C_Item.GetItemCooldown) == "function" then
        local ok, s, d, e = pcall(C_Item.GetItemCooldown, itemID)
        if ok then start, duration, enable = s, d, e end
    elseif type(GetItemCooldown) == "function" then
        local ok, s, d, e = pcall(GetItemCooldown, itemID)
        if ok then start, duration, enable = s, d, e end
    end
    if enable == 0 then return false end -- item não pode ser usado
    local now = GetTime() or 0
    if type(start) == "number" and type(duration) == "number" and duration > 0 then
        local remaining = start + duration - now
        if remaining > 0.5 then return true end
    end
    return false
end

local function containerSlotCount(bag)
    local container = C_Container
    local getter = container and container.GetContainerNumSlots or GetContainerNumSlots
    local ok, count = safeCall(getter, bag)
    if ok and type(count) == "number" then return count end
    return 0
end

local function collectOwnedItemIDs()
    local owned = {}
    if type(GetInventoryItemID) == "function" then
        for _, def in ipairs(SLOT_DEFS) do
            local slotID = inventorySlotID(def.api)
            if slotID then
                local ok, itemID = safeCall(GetInventoryItemID, "player", slotID)
                if ok and type(itemID) == "number" then owned[itemID] = true end
            end
        end
    end
    local bagCount = tonumber(NUM_BAG_SLOTS) or 4
    for bag = 0, bagCount do
        for slot = 1, containerSlotCount(bag) do
            local itemID = containerItemID(bag, slot)
            if itemID then owned[itemID] = true end
        end
    end
    return owned
end

local ownedCache
local ownedCacheTime = 0
local function cachedOwnedItemIDs()
    local now = GetTime()
    if ownedCache and now - ownedCacheTime < 1 then return ownedCache end
    ownedCache = collectOwnedItemIDs()
    ownedCacheTime = now
    return ownedCache
end

local function itemsForSlot(def, selectedItemID)
    local owned = collectOwnedItemIDs()
    local items = {}
    for itemID in pairs(owned) do
        local info = itemInfo(itemID)
        if def.equip[itemEquipLoc(itemID, info)] or itemID == selectedItemID then
            items[#items + 1] = {
                itemID = itemID,
                name = info and info.name or ("Item " .. tostring(itemID)),
                texture = info and info.texture,
            }
        end
    end
    table.sort(items, function(a, b) return a.name:lower() < b.name:lower() end)
    return items
end

local function genericEnvironment()
    local env = {
        inCombat = false,
        isPvP = false,
        hasActiveEnemy = false,
        targetCasting = false,
        isMelee = false,
        tooCloseForRanged = false,
        isDeadZone = false,
        targetDistance = nil,
        isAoE = false,
        manaPct = 0,
        rage = 0,
        energy = 0,
        combo = 0,
    }
    if type(UnitAffectingCombat) == "function" then
        local ok, value = safeCall(UnitAffectingCombat, "player")
        env.inCombat = ok and value == true
    end
    if type(GetInstanceInfo) == "function" then
        local ok, _, instanceType = safeCall(GetInstanceInfo)
        env.isPvP = ok and (instanceType == "pvp" or instanceType == "arena")
    end
    local targetExists = false
    if type(UnitExists) == "function" then
        local ok, exists = safeCall(UnitExists, "target")
        targetExists = ok and exists == true
    end
    if targetExists then
        local ok, attackable = safeCall(UnitCanAttack, "player", "target")
        env.hasActiveEnemy = ok and attackable == true
        if type(UnitCastingInfo) == "function" then
            local castOK, castName = safeCall(UnitCastingInfo, "target")
            env.targetCasting = castOK and castName ~= nil
        end
        if not env.targetCasting and type(UnitChannelInfo) == "function" then
            local castOK, castName = safeCall(UnitChannelInfo, "target")
            env.targetCasting = castOK and castName ~= nil
        end
        if type(addon.TargetDistance) == "function" then
            local ok, distance = pcall(addon.TargetDistance, addon, "target")
            if ok then env.targetDistance = distance end
        end
        if type(addon.IsInMeleeRange) == "function" then
            local ok, inMelee = pcall(addon.IsInMeleeRange, addon, "target")
            env.isMelee = ok and inMelee == true
        end
        if type(addon.IsInDeadZoneRange) == "function" then
            local ok, inDeadZone = pcall(addon.IsInDeadZoneRange, addon, "target")
            env.isDeadZone = ok and inDeadZone == true
        end
        env.tooCloseForRanged = env.isMelee or env.isDeadZone
    end
    if type(addon.PopulateEnvResources) == "function" then
        addon.PopulateEnvResources(env, "player")
    end
    return env
end

local function buildEnvironment(module)
    if type(module) == "table" and type(module.BuildEnv) == "function" then
        local env = module:BuildEnv()
        if type(env) ~= "table" then error("active module BuildEnv must return a table") end
        return env
    end
    return genericEnvironment()
end

function Equipment.GetSuggestions(module)
    local rules = addon.charDb and addon.charDb.equipmentRules
    if type(rules) ~= "table" then return {} end
    local inventory = cachedOwnedItemIDs()
    local candidates = {}
    for _, def in ipairs(SLOT_DEFS) do
        local rule = rules[def.key]
        local itemID = type(rule) == "table" and tonumber(rule.itemID) or nil
        if itemID and inventory[itemID] and addon.Visuals and addon.Visuals.FindItemButtons then
            local buttons = addon.Visuals.FindItemButtons(itemID)
            if #buttons > 0 then candidates[#candidates + 1] = { itemID = itemID, rule = rule } end
        end
    end
    if #candidates == 0 then return {} end
    local env = buildEnvironment(module)
    local suggestions = {}
    for _, candidate in ipairs(candidates) do
        if addon.NodeConditionPass(module, env, candidate.rule, true) then
            -- Não sugere item se estiver em cooldown (ex: trinket já usado)
            if not itemIsOnCooldown(candidate.itemID) then
                suggestions[#suggestions + 1] = {
                    kind = "item",
                    itemID = candidate.itemID,
                    color = "Utility",
                }
            end
        end
    end
    return suggestions
end

local function ruleFor(slotKey, create)
    local charDB = addon.charDb
    if not charDB then return nil end
    if create then charDB.equipmentRules = charDB.equipmentRules or {} end
    local rules = charDB.equipmentRules
    if not rules then return nil end
    if create then rules[slotKey] = rules[slotKey] or {} end
    return rules[slotKey]
end

local function saveRule(slotKey, rule)
    if not addon.charDb then return end
    addon.charDb.equipmentRules = addon.charDb.equipmentRules or {}
    if not rule.itemID and not rule.condition and not (type(rule.filter) == "table" and next(rule.filter)) then
        addon.charDb.equipmentRules[slotKey] = nil
        if not next(addon.charDb.equipmentRules) then addon.charDb.equipmentRules = nil end
    else
        addon.charDb.equipmentRules[slotKey] = rule
    end
end

local function buildEquipmentTab(parent)
    local hint = parent:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("TOPLEFT", parent, "TOPLEFT", 6, -6)
    hint:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -6, -6)
    hint:SetJustifyH("LEFT")
    hint:SetWordWrap(true)
    hint:SetText(L["equip_hint"])

    local scroll = CreateFrame("ScrollFrame", nil, parent, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", parent, "TOPLEFT", 6, -32)
    scroll:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -26, 4)
    scroll:EnableMouseWheel(true)
    local child = CreateFrame("Frame", nil, scroll)
    local contentWidth = parent:GetWidth()
    if not contentWidth or contentWidth < 150 then contentWidth = 374 end
    child:SetWidth(contentWidth - 30)
    child:SetHeight(1)
    local function updateChildWidth()
        local width = parent:GetWidth()
        if not width or width < 150 then width = 374 end
        child:SetWidth(math.max(120, width - 30))
    end
    parent:HookScript("OnSizeChanged", updateChildWidth)
    parent:HookScript("OnShow", updateChildWidth)
    scroll:SetScrollChild(child)
    scroll:SetScript("OnMouseWheel", function(self, delta)
        local current = self:GetVerticalScroll() or 0
        local maxScroll = math.max(0, child:GetHeight() - self:GetHeight())
        self:SetVerticalScroll(math.max(0, math.min(maxScroll, current - (delta > 0 and 40 or -40))))
    end)

    local function refreshRow(row, def)
        local rule = ruleFor(def.key, false) or {}
        local info = rule.itemID and itemInfo(tonumber(rule.itemID))
        row.itemIcon:SetTexture(info and info.texture or QUESTION_MARK)
        row.itemText:SetText(info and info.name or L["equip_select_item"])
        row.summary:SetText(addon.RotationEditor and addon.RotationEditor.NodeConditionText
            and addon.RotationEditor.NodeConditionText(rule, addon.activeModule) or L["rot_no_condition"])
        row.removeButton:SetEnabled(rule.condition ~= nil or (type(rule.filter) == "table" and next(rule.filter) ~= nil))
    end

    local function itemChoices(def, row)
        local rule = ruleFor(def.key, false) or {}
        local choices = {
            { header = L[def.label] or def.label },
            {
                label = L["equip_no_item"],
                checked = not rule.itemID,
                action = function()
                    local updated = ruleFor(def.key, true)
                    updated.itemID = nil
                    saveRule(def.key, updated)
                end,
            },
        }
        for _, item in ipairs(itemsForSlot(def, tonumber(rule.itemID))) do
            local itemChoice = item
            choices[#choices + 1] = {
                label = string.format("|T%s:16:16|t %s", itemChoice.texture or QUESTION_MARK, itemChoice.name),
                checked = tonumber(rule.itemID) == itemChoice.itemID,
                action = function()
                    local updated = ruleFor(def.key, true)
                    updated.itemID = itemChoice.itemID
                    saveRule(def.key, updated)
                end,
            }
        end
        if #choices == 2 then
            choices[#choices + 1] = { header = L["equip_no_items"] }
        end
        return choices
    end

    local y = -2
    for _, def in ipairs(SLOT_DEFS) do
        local slotDef = def
        local row = CreateFrame("Frame", nil, child)
        row:SetHeight(44)
        row:SetPoint("TOPLEFT", child, "TOPLEFT", 0, y)
        row:SetPoint("TOPRIGHT", child, "TOPRIGHT", 0, y)

        local slotIcon = row:CreateTexture(nil, "ARTWORK")
        slotIcon:SetSize(22, 22)
        slotIcon:SetPoint("TOPLEFT", row, "TOPLEFT", 2, -3)
        local _, _, slotTexture = safeCall(GetInventorySlotInfo, slotDef.api)
        slotIcon:SetTexture(type(slotTexture) == "string" and slotTexture or QUESTION_MARK)

        local slotLabel = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        slotLabel:SetPoint("LEFT", slotIcon, "RIGHT", 4, 0)
        slotLabel:SetWidth(68)
        slotLabel:SetJustifyH("LEFT")
        slotLabel:SetText(L[slotDef.label] or slotDef.label)

        local itemButton = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
        itemButton:SetSize(154, 22)
        itemButton:SetPoint("TOPLEFT", row, "TOPLEFT", 100, -3)
        row.itemIcon = itemButton:CreateTexture(nil, "ARTWORK")
        row.itemIcon:SetSize(16, 16)
        row.itemIcon:SetPoint("LEFT", itemButton, "LEFT", 4, 0)
        row.itemText = itemButton:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.itemText:SetPoint("LEFT", row.itemIcon, "RIGHT", 4, 0)
        row.itemText:SetPoint("RIGHT", itemButton, "RIGHT", -4, 0)
        row.itemText:SetJustifyH("LEFT")
        itemButton:SetScript("OnClick", function()
            local picker = addon.RotationEditor and addon.RotationEditor.ShowPicker
            if picker then
                picker(itemButton, L["equip_select_item"], function() return itemChoices(slotDef, row) end,
                    function() refreshRow(row, slotDef) end)
            end
        end)

        row.addButton = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
        row.addButton:SetSize(24, 22)
        row.addButton:SetPoint("LEFT", itemButton, "RIGHT", 4, 0)
        row.addButton:SetText("+")
        row.addButton:SetScript("OnClick", function()
            local rule = ruleFor(slotDef.key, true)
            local picker = addon.RotationEditor and addon.RotationEditor.ShowConditionPicker
            if picker then
                picker(row.addButton, rule, function(key, value)
                    local updated = ruleFor(slotDef.key, true)
                    updated[key] = value
                    saveRule(slotDef.key, updated)
                end, function() refreshRow(row, slotDef) end, addon.activeModule or false)
            end
        end)

        row.removeButton = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
        row.removeButton:SetSize(24, 22)
        row.removeButton:SetPoint("LEFT", row.addButton, "RIGHT", 3, 0)
        row.removeButton:SetText("-")
        row.removeButton:SetScript("OnClick", function()
            local rule = ruleFor(slotDef.key, false)
            local picker = addon.RotationEditor and addon.RotationEditor.ShowRemoveConditionPicker
            if rule and picker then
                picker(row.removeButton, rule, function(key, value)
                    local updated = ruleFor(slotDef.key, true)
                    updated[key] = value
                    saveRule(slotDef.key, updated)
                end, function() refreshRow(row, slotDef) end, addon.activeModule or false)
            end
        end)

        row.summary = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        row.summary:SetPoint("TOPLEFT", row, "TOPLEFT", 30, -27)
        row.summary:SetPoint("TOPRIGHT", row, "TOPRIGHT", -2, -27)
        row.summary:SetJustifyH("LEFT")
        refreshRow(row, slotDef)
        y = y - 45
    end
    child:SetHeight(math.max(1, -y))
end

if addon.Options and addon.Options.RegisterTab then
    addon.Options.RegisterTab("equipment", L["opt_tab_equipment"], nil, buildEquipmentTab)
end
