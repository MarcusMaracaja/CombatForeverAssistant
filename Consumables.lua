-- Combat Forever Assistant — Food, Potions & Items module.
-- Independent from class rotation modules: scans bags and action bars for:
--   1) Best Food (HP) and Drink/Water (Mana, mana classes only) out of combat while standing still
--   2) Long-duration (5+ min) bonus potions, elixirs, flasks and scrolls missing from player buffs
--   3) User-configured situational item rules ([+] button): water breath, engineering bombs,
--      emergency HP/Mana potions, or triggering an item right after casting a chosen ability.
-- Highlights items on open bags, on action bars, or both simultaneously.

local addonName, addon = ...
local L = addon.L

local Consumables = {}
addon.Consumables = Consumables

local ORANGE = { 1.0, 0.55, 0.10 }
local QUESTION_MARK = "Interface\\Icons\\INV_Misc_QuestionMark"

-- ---------------------------------------------------------------------------
-- Safe API helpers (WoW Forever secret-safe)
-- ---------------------------------------------------------------------------
local function safeCall(fn, ...)
    if type(fn) ~= "function" then return false end
    return pcall(fn, ...)
end

local function isSecret(v)
    if type(addon.IsSecretValue) == "function" then return addon.IsSecretValue(v) end
    if v == nil or type(_G.issecretvalue) ~= "function" then return false end
    local ok, s = pcall(_G.issecretvalue, v)
    return ok and s == true
end

local function safeNum(v, fallback)
    if type(addon.SafeNumber) == "function" then return addon.SafeNumber(v, fallback) end
    if type(v) ~= "number" or isSecret(v) or v ~= v or v == math.huge or v == -math.huge then
        return fallback
    end
    return v
end

local function safeStr(v)
    if type(v) ~= "string" or isSecret(v) or v == "" then return nil end
    return v
end

local function safeBool(v)
    if type(v) ~= "boolean" or isSecret(v) then return nil end
    return v
end

local function now()
    local ok, t = safeCall(GetTime)
    return ok and safeNum(t, 0) or 0
end

local function normalizeText(s)
    s = safeStr(s)
    if not s then return "" end
    return (s:lower():gsub("%s*%b()%s*$", ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

local function loc(key, fallback)
    return (L and L[key]) or fallback or key
end

-- ---------------------------------------------------------------------------
-- Player state helpers (mana class, HP/Mana, combat, moving, eating/drinking,
-- underwater breath)
-- ---------------------------------------------------------------------------
local MANA_CLASSES = {
    MAGE = true, PRIEST = true, WARLOCK = true, PALADIN = true,
    SHAMAN = true, DRUID = true, HUNTER = true,
}

function Consumables.PlayerHasMana()
    if type(addon.GetMana) == "function" then
        local _, maxMana = addon.GetMana("player")
        if maxMana and maxMana > 0 then return true end
    end
    local _, cls = UnitClass("player")
    return cls ~= nil and MANA_CLASSES[cls] == true
end

local function playerLevel()
    local ok, lvl = safeCall(UnitLevel, "player")
    return ok and safeNum(lvl, 60) or 60
end

local function playerInCombat()
    if type(UnitAffectingCombat) == "function" then
        local ok, v = safeCall(UnitAffectingCombat, "player")
        local b = ok and safeBool(v)
        if b ~= nil then return b end
    end
    if type(InCombatLockdown) == "function" then
        local ok, v = safeCall(InCombatLockdown)
        local b = ok and safeBool(v)
        if b ~= nil then return b end
    end
    return false
end

local function playerIsMoving()
    if type(GetUnitSpeed) == "function" then
        local ok, speed = safeCall(GetUnitSpeed, "player")
        local s = ok and safeNum(speed, nil) or nil
        if s ~= nil then return s > 0 end
    end
    if type(IsPlayerMoving) == "function" then
        local ok, moving = safeCall(IsPlayerMoving)
        local b = ok and safeBool(moving)
        if b ~= nil then return b end
    end
    return false
end

local function playerIsMounted()
    if type(IsMounted) == "function" then
        local ok, m = safeCall(IsMounted)
        local b = ok and safeBool(m)
        if b == true then return true end
    end
    return false
end

local function playerHealthPct()
    local okC, cur = safeCall(UnitHealth, "player")
    local okM, maxV = safeCall(UnitHealthMax, "player")
    cur = okC and safeNum(cur, nil) or nil
    maxV = okM and safeNum(maxV, nil) or nil
    if cur and maxV and maxV > 0 then
        return math.max(0, math.min(100, (cur / maxV) * 100))
    end
    return nil
end

local function playerManaPct()
    if type(addon.GetManaPct) == "function" then
        local pct, readable = addon.GetManaPct("player")
        if readable and pct ~= nil then return pct end
    end
    return nil
end

local function playerUnderwaterAndBreath()
    local swimming = false
    if type(IsSwimming) == "function" then
        local ok, v = safeCall(IsSwimming)
        if ok and safeBool(v) == true then swimming = true end
    end
    if not swimming and type(IsSubmerged) == "function" then
        local ok, v = safeCall(IsSubmerged)
        if ok and safeBool(v) == true then swimming = true end
    end

    local breathPct = nil
    if type(GetMirrorTimerInfo) == "function" then
        for i = 1, 3 do
            local ok, timerType, value, maxValue = safeCall(GetMirrorTimerInfo, i)
            if ok and safeStr(timerType) == "BREATH" then
                swimming = true
                local cur = safeNum(value, nil)
                local maxV = safeNum(maxValue, nil)
                if type(GetMirrorTimerProgress) == "function" then
                    local okP, prog = safeCall(GetMirrorTimerProgress, "BREATH")
                    local p = okP and safeNum(prog, nil) or nil
                    if p ~= nil then cur = p end
                end
                if cur and maxV and maxV > 0 then
                    breathPct = math.max(0, math.min(100, (cur / maxV) * 100))
                end
                break
            end
        end
    end
    return swimming, breathPct
end

-- ---------------------------------------------------------------------------
-- Food & Drink detection (known aura IDs + localized names + scanned item spells + beliefs)
-- ---------------------------------------------------------------------------
local FOOD_AURA_IDS = {
    [433] = true, [434] = true, [435] = true, [1127] = true, [1129] = true, [1131] = true,
    [2639] = true, [5004] = true, [5005] = true, [5006] = true, [5007] = true,
    [10256] = true, [10257] = true, [18229] = true, [18230] = true, [18231] = true,
    [18232] = true, [18233] = true, [18234] = true, [22731] = true, [24800] = true,
    [25660] = true, [25700] = true, [25886] = true, [26026] = true, [26402] = true,
    [29073] = true, [33261] = true, [33263] = true, [33265] = true, [33268] = true,
    [35272] = true, [43180] = true, [45548] = true, [45619] = true,
}

local DRINK_AURA_IDS = {
    [430] = true, [431] = true, [432] = true, [1133] = true, [1135] = true, [1137] = true,
    [10250] = true, [22734] = true, [24355] = true, [25696] = true, [26261] = true,
    [26473] = true, [27089] = true, [29007] = true, [30024] = true, [34291] = true,
    [43182] = true, [43183] = true, [45279] = true, [57073] = true,
}

local HYBRID_FOOD_DRINK_IDS = {
    [25990] = true, [43180] = true, [43182] = true, [43183] = true, [45548] = true,
}

-- Dynamically discovered spellIDs from scanned food/drink items in bags
local knownFoodSpellIDs = {}
local knownDrinkSpellIDs = {}

-- Beliefs populated on UNIT_SPELLCAST_SUCCEEDED / SENT so glow stops immediately
local state = {
    eatingBeliefUntil = 0,
    drinkingBeliefUntil = 0,
    usedItemUntil = {},      -- [itemID] = timestamp
    usedCategoryUntil = {},  -- [category] = timestamp
    lastCastByID = {},       -- [spellID] = timestamp
    lastCastByName = {},     -- [normalizedName] = timestamp
    lastCastSummary = nil,
}

local function nameLooksLikeFood(lowerName)
    return lowerName == "food" or lowerName == "comida"
        or lowerName:find("food", 1, true) ~= nil
        or lowerName:find("comida", 1, true) ~= nil
        or lowerName:find("refei", 1, true) ~= nil
        or lowerName:find("aliment", 1, true) ~= nil
end

local function nameLooksLikeDrink(lowerName)
    return lowerName == "drink" or lowerName == "bebida"
        or lowerName:find("drink", 1, true) ~= nil
        or lowerName:find("bebida", 1, true) ~= nil
        or lowerName:find("refresco", 1, true) ~= nil
        or lowerName:find("refreshment", 1, true) ~= nil
        or lowerName:find("água", 1, true) ~= nil
        or lowerName:find("agua", 1, true) ~= nil
end

local function collectPlayerAuras()
    local byID, byName = {}, {}
    local readable = false
    if C_UnitAuras and type(C_UnitAuras.GetAuraDataByIndex) == "function" then
        for i = 1, 60 do
            local ok, aura = pcall(C_UnitAuras.GetAuraDataByIndex, "player", i, "HELPFUL")
            if not ok or type(aura) ~= "table" then break end
            readable = true
            local okID, sid = pcall(function() return aura.spellId or aura.spellID end)
            sid = okID and safeNum(sid, nil) or nil
            if sid then byID[sid] = true end
            local okN, nm = pcall(function() return aura.name end)
            nm = okN and safeStr(nm) or nil
            if nm then byName[normalizeText(nm)] = true end
        end
    elseif type(UnitBuff) == "function" then
        for i = 1, 60 do
            local ok, nm, _, _, _, _, _, _, _, _, sid = pcall(UnitBuff, "player", i)
            if not ok or not nm then break end
            readable = true
            sid = safeNum(sid, nil)
            if sid then byID[sid] = true end
            nm = safeStr(nm)
            if nm then byName[normalizeText(nm)] = true end
        end
    end
    return byID, byName, readable
end

local function checkEatingDrinking(aurasByID, aurasByName)
    local t = now()
    local eating = (t < state.eatingBeliefUntil)
    local drinking = (t < state.drinkingBeliefUntil)

    for sid in pairs(aurasByID) do
        if FOOD_AURA_IDS[sid] or HYBRID_FOOD_DRINK_IDS[sid] or knownFoodSpellIDs[sid] then
            eating = true
        end
        if DRINK_AURA_IDS[sid] or HYBRID_FOOD_DRINK_IDS[sid] or knownDrinkSpellIDs[sid] then
            drinking = true
        end
    end
    for nm in pairs(aurasByName) do
        -- Ignore "Well Fed" / "Bem Alimentado" for active eating check
        local isWellFed = nm:find("well fed", 1, true) or nm:find("bem alimentado", 1, true)
        if not isWellFed then
            if nameLooksLikeFood(nm) then eating = true end
            if nameLooksLikeDrink(nm) then drinking = true end
        end
    end
    return eating, drinking
end

function Consumables.IsEatingOrDrinking()
    local okC, inComb = safeCall(UnitAffectingCombat, "player")
    if okC and not isSecret(inComb) and inComb == true then return false end
    local okL, locked = safeCall(InCombatLockdown)
    if okL and not isSecret(locked) and locked == true then return false end
    local aurasByID, aurasByName = collectPlayerAuras()
    local eating, drinking = checkEatingDrinking(aurasByID, aurasByName)
    return (eating or drinking) and true or false
end

-- ---------------------------------------------------------------------------
-- Curated database of WoW Vanilla / Forever long-duration (5+ min) bonus items
-- (Flasks, Elixirs, Scrolls). Custom Forever items are also detected dynamically
-- via tooltip inspection below!
-- ---------------------------------------------------------------------------
local LONG_BUFF_ITEMS = {
    -- Flasks (2h)
    [13510] = { category = "flask", group = "elixir", duration = 7200, buffs = { 17628 } }, -- Flask of the Titans
    [13511] = { category = "flask", group = "elixir", duration = 7200, buffs = { 17627 } }, -- Flask of Distilled Wisdom
    [13512] = { category = "flask", group = "elixir", duration = 7200, buffs = { 17626 } }, -- Flask of Supreme Power
    [13513] = { category = "flask", group = "elixir", duration = 7200, buffs = { 17629 } }, -- Flask of Chromatic Resistance

    -- Guardian Elixirs: Armor / Defense (60 min)
    [5997]  = { category = "armor_elixir", group = "elixir", duration = 3600, buffs = { 673, 3166, 3220, 11348, 17534 } }, -- Elixir of Minor Defense
    [3389]  = { category = "armor_elixir", group = "elixir", duration = 3600, buffs = { 673, 3166, 3220, 11348, 17534 } }, -- Elixir of Defense
    [8951]  = { category = "armor_elixir", group = "elixir", duration = 3600, buffs = { 673, 3166, 3220, 11348, 17534 } }, -- Elixir of Greater Defense
    [13445] = { category = "armor_elixir", group = "elixir", duration = 3600, buffs = { 673, 3166, 3220, 11348, 17534 } }, -- Elixir of Superior Defense

    -- Guardian Elixirs: Health / Fortitude / HP5 / MP5
    [2458]  = { category = "health_elixir", group = "elixir", duration = 3600, buffs = { 2378, 3593 } }, -- Elixir of Minor Fortitude
    [3825]  = { category = "health_elixir", group = "elixir", duration = 3600, buffs = { 2378, 3593 } }, -- Elixir of Fortitude
    [3382]  = { category = "troll_blood",   group = "elixir", duration = 3600, buffs = { 3219, 3222, 3223, 24361 } }, -- Weak Troll's Blood
    [3388]  = { category = "troll_blood",   group = "elixir", duration = 3600, buffs = { 3219, 3222, 3223, 24361 } }, -- Strong Troll's Blood
    [3826]  = { category = "troll_blood",   group = "elixir", duration = 3600, buffs = { 3219, 3222, 3223, 24361 } }, -- Mighty Troll's Blood
    [20004] = { category = "troll_blood",   group = "elixir", duration = 3600, buffs = { 3219, 3222, 3223, 24361 } }, -- Major Troll's Blood
    [20007] = { category = "mp5_elixir",    group = "elixir", duration = 3600, buffs = { 24363 } }, -- Mageblood Potion/Elixir
    [9088]  = { category = "gift_arthas",   group = "elixir", duration = 1800, buffs = { 11371 } }, -- Gift of Arthas

    -- Battle Elixirs: Agility / Strength / Stats / Spell Power
    [2457]  = { category = "agility_elixir", group = "elixir", duration = 3600, buffs = { 2374, 3160, 11328, 11334, 17538 } }, -- Minor Agility
    [3390]  = { category = "agility_elixir", group = "elixir", duration = 3600, buffs = { 2374, 3160, 11328, 11334, 17538 } }, -- Lesser Agility
    [8949]  = { category = "agility_elixir", group = "elixir", duration = 3600, buffs = { 2374, 3160, 11328, 11334, 17538 } }, -- Agility
    [9187]  = { category = "agility_elixir", group = "elixir", duration = 3600, buffs = { 2374, 3160, 11328, 11334, 17538 } }, -- Greater Agility
    [13452] = { category = "agility_elixir", group = "elixir", duration = 3600, buffs = { 2374, 3160, 11328, 11334, 17538 } }, -- Elixir of the Mongoose

    [2454]  = { category = "strength_elixir", group = "elixir", duration = 3600, buffs = { 2367, 3164, 11405, 17537 } }, -- Lion's Strength
    [3391]  = { category = "strength_elixir", group = "elixir", duration = 3600, buffs = { 2367, 3164, 11405, 17537 } }, -- Ogre's Strength
    [9206]  = { category = "strength_elixir", group = "elixir", duration = 3600, buffs = { 2367, 3164, 11405, 17537 } }, -- Elixir of Giants
    [13444] = { category = "strength_elixir", group = "elixir", duration = 3600, buffs = { 2367, 3164, 11405, 17537 } }, -- Elixir of Brute Force

    [3383]  = { category = "intellect_elixir", group = "elixir", duration = 3600, buffs = { 3166, 11396, 17535 } }, -- Elixir of Wisdom
    [9179]  = { category = "intellect_elixir", group = "elixir", duration = 3600, buffs = { 11396, 17535 } }, -- Elixir of Greater Intellect
    [13447] = { category = "intellect_elixir", group = "elixir", duration = 3600, buffs = { 11396, 17535 } }, -- Elixir of the Sages

    [9155]  = { category = "spell_power_elixir", group = "elixir", duration = 1800, buffs = { 11390, 17539 } }, -- Arcane Elixir
    [13454] = { category = "spell_power_elixir", group = "elixir", duration = 3600, buffs = { 11390, 17539 } }, -- Greater Arcane Elixir
    [6373]  = { category = "fire_power_elixir",  group = "elixir", duration = 1800, buffs = { 7844, 26276 } }, -- Elixir of Firepower
    [21546] = { category = "fire_power_elixir",  group = "elixir", duration = 1800, buffs = { 7844, 26276 } }, -- Elixir of Greater Firepower
    [9264]  = { category = "shadow_power_elixir", group = "elixir", duration = 1800, buffs = { 11474 } }, -- Elixir of Shadow Power
    [17708] = { category = "frost_power_elixir", group = "elixir", duration = 1800, buffs = { 21920 } }, -- Elixir of Frost Power

    -- Scrolls (30 min, Ranks I-V)
    [3013]  = { category = "scroll_armor", group = "scroll", duration = 1800, buffs = { 8091, 8094, 8095, 12175, 33079 } },
    [1478]  = { category = "scroll_armor", group = "scroll", duration = 1800, buffs = { 8091, 8094, 8095, 12175, 33079 } },
    [4421]  = { category = "scroll_armor", group = "scroll", duration = 1800, buffs = { 8091, 8094, 8095, 12175, 33079 } },
    [10305] = { category = "scroll_armor", group = "scroll", duration = 1800, buffs = { 8091, 8094, 8095, 12175, 33079 } },
    [27500] = { category = "scroll_armor", group = "scroll", duration = 1800, buffs = { 8091, 8094, 8095, 12175, 33079 } },

    [1180]  = { category = "scroll_stamina", group = "scroll", duration = 1800, buffs = { 8099, 8100, 8101, 12178, 33081 } },
    [1711]  = { category = "scroll_stamina", group = "scroll", duration = 1800, buffs = { 8099, 8100, 8101, 12178, 33081 } },
    [4422]  = { category = "scroll_stamina", group = "scroll", duration = 1800, buffs = { 8099, 8100, 8101, 12178, 33081 } },
    [10307] = { category = "scroll_stamina", group = "scroll", duration = 1800, buffs = { 8099, 8100, 8101, 12178, 33081 } },
    [27502] = { category = "scroll_stamina", group = "scroll", duration = 1800, buffs = { 8099, 8100, 8101, 12178, 33081 } },

    [954]   = { category = "scroll_strength", group = "scroll", duration = 1800, buffs = { 8118, 8119, 8120, 12179, 33082 } },
    [2289]  = { category = "scroll_strength", group = "scroll", duration = 1800, buffs = { 8118, 8119, 8120, 12179, 33082 } },
    [4426]  = { category = "scroll_strength", group = "scroll", duration = 1800, buffs = { 8118, 8119, 8120, 12179, 33082 } },
    [10310] = { category = "scroll_strength", group = "scroll", duration = 1800, buffs = { 8118, 8119, 8120, 12179, 33082 } },
    [27503] = { category = "scroll_strength", group = "scroll", duration = 1800, buffs = { 8118, 8119, 8120, 12179, 33082 } },

    [3012]  = { category = "scroll_agility", group = "scroll", duration = 1800, buffs = { 8115, 8116, 8117, 12174, 33077 } },
    [1477]  = { category = "scroll_agility", group = "scroll", duration = 1800, buffs = { 8115, 8116, 8117, 12174, 33077 } },
    [4425]  = { category = "scroll_agility", group = "scroll", duration = 1800, buffs = { 8115, 8116, 8117, 12174, 33077 } },
    [10309] = { category = "scroll_agility", group = "scroll", duration = 1800, buffs = { 8115, 8116, 8117, 12174, 33077 } },
    [27498] = { category = "scroll_agility", group = "scroll", duration = 1800, buffs = { 8115, 8116, 8117, 12174, 33077 } },

    [955]   = { category = "scroll_intellect", group = "scroll", duration = 1800, buffs = { 8096, 8097, 8098, 12176, 33078 } },
    [2290]  = { category = "scroll_intellect", group = "scroll", duration = 1800, buffs = { 8096, 8097, 8098, 12176, 33078 } },
    [4427]  = { category = "scroll_intellect", group = "scroll", duration = 1800, buffs = { 8096, 8097, 8098, 12176, 33078 } },
    [10308] = { category = "scroll_intellect", group = "scroll", duration = 1800, buffs = { 8096, 8097, 8098, 12176, 33078 } },
    [27499] = { category = "scroll_intellect", group = "scroll", duration = 1800, buffs = { 8096, 8097, 8098, 12176, 33078 } },

    [1181]  = { category = "scroll_spirit", group = "scroll", duration = 1800, buffs = { 8112, 8113, 8114, 12177, 33080 } },
    [1712]  = { category = "scroll_spirit", group = "scroll", duration = 1800, buffs = { 8112, 8113, 8114, 12177, 33080 } },
    [4424]  = { category = "scroll_spirit", group = "scroll", duration = 1800, buffs = { 8112, 8113, 8114, 12177, 33080 } },
    [10306] = { category = "scroll_spirit", group = "scroll", duration = 1800, buffs = { 8112, 8113, 8114, 12177, 33080 } },
    [27501] = { category = "scroll_spirit", group = "scroll", duration = 1800, buffs = { 8112, 8113, 8114, 12177, 33080 } },
}

-- Situational long-duration potions excluded from generic auto-buff (best used via custom rules [+])
local EXCLUDED_AUTO_BUFF_ITEMS = {
    [5996] = true, [18294] = true, [9279] = true, -- Water Breathing
    [6372] = true, -- Swim Speed
    [3823] = true, [9172] = true, -- Invisibility
    [9224] = true, -- Demonslaying
    [9154] = true, [3828] = true, [9197] = true, -- Detect Undead / Detect Invis / Dream Vision
    [13506] = true, -- Flask of Petrification
}

-- ---------------------------------------------------------------------------
-- Tooltip scanner & item classification cache
-- ---------------------------------------------------------------------------
local scanTooltip
local itemMetaCache = {}

local function getScanTooltip()
    if scanTooltip then return scanTooltip end
    scanTooltip = CreateFrame("GameTooltip", "CFA_ConsumablesScanTooltip", UIParent, "GameTooltipTemplate")
    scanTooltip:SetOwner(UIParent, "ANCHOR_NONE")
    return scanTooltip
end

local function readTooltipText(itemID, bag, slot)
    local lines = {}
    if C_TooltipInfo then
        local data
        if bag ~= nil and slot ~= nil and type(C_TooltipInfo.GetBagItem) == "function" then
            local ok, res = pcall(C_TooltipInfo.GetBagItem, bag, slot)
            if ok and type(res) == "table" then data = res end
        end
        if not data and type(C_TooltipInfo.GetItemByID) == "function" then
            local ok, res = pcall(C_TooltipInfo.GetItemByID, itemID)
            if ok and type(res) == "table" then data = res end
        end
        if data and type(data.lines) == "table" then
            for _, line in ipairs(data.lines) do
                local t = type(line) == "table" and safeStr(line.leftText) or nil
                if t then lines[#lines + 1] = t end
            end
        end
    end
    if #lines == 0 then
        local tip = getScanTooltip()
        tip:ClearLines()
        local ok = false
        if bag ~= nil and slot ~= nil and type(tip.SetBagItem) == "function" then
            ok = pcall(tip.SetBagItem, tip, bag, slot)
        end
        if not ok and type(tip.SetItemByID) == "function" then
            pcall(tip.SetItemByID, tip, itemID)
        end
        local n = tip:NumLines() or 0
        for i = 1, math.min(n, 16) do
            local fs = _G["CFA_ConsumablesScanTooltipTextLeft" .. i]
            local t = fs and safeStr(fs:GetText()) or nil
            if t then lines[#lines + 1] = t end
        end
    end
    return table.concat(lines, "\n")
end

local function parseDurationSeconds(lowerText)
    if not lowerText or lowerText == "" then return 0 end
    local best = 0
    for h in lowerText:gmatch("(%d+)%s*h[or][ua]?r") do
        best = math.max(best, (tonumber(h) or 0) * 3600)
    end
    for h in lowerText:gmatch("(%d+)%s*hora") do
        best = math.max(best, (tonumber(h) or 0) * 3600)
    end
    for m in lowerText:gmatch("(%d+)%s*min") do
        best = math.max(best, (tonumber(m) or 0) * 60)
    end
    return best
end

local function parseRestoreAmount(lowerText, keywordPatterns)
    if not lowerText or lowerText == "" then return 0 end
    local best = 0
    for _, pat in ipairs(keywordPatterns) do
        for num in lowerText:gmatch(pat) do
            local cleaned = num:gsub("[%.,]", "")
            local val = tonumber(cleaned) or 0
            if val > best then best = val end
        end
    end
    return best
end

local function inferDynamicLongBuffCategory(lowerText, nameLower, subClassID, spellID)
    -- Skip situational buffs (underwater breath, swim speed, invisibility, protection vs school)
    if lowerText:find("breathe underwater", 1, true) or lowerText:find("respirar debaixo", 1, true)
        or lowerText:find("swim speed", 1, true) or lowerText:find("velocidade de nado", 1, true)
        or lowerText:find("invisib", 1, true) or lowerText:find("slow fall", 1, true)
        or lowerText:find("queda lenta", 1, true) or lowerText:find("detect ", 1, true)
        or lowerText:find("detectar ", 1, true) then
        return nil, nil
    end
    local isScroll = (subClassID == 3 or subClassID == 4)
        and (nameLower:find("scroll", 1, true) or nameLower:find("pergaminho", 1, true))
    local group = isScroll and "scroll" or "elixir"
    local prefix = isScroll and "scroll_" or "elixir_"

    if lowerText:find("armor", 1, true) or lowerText:find("armadura", 1, true) then
        return prefix .. "armor", group
    elseif lowerText:find("agility", 1, true) or lowerText:find("agilidade", 1, true) then
        return prefix .. "agility", group
    elseif lowerText:find("strength", 1, true) or lowerText:find("força", 1, true) or lowerText:find("forca", 1, true) then
        return prefix .. "strength", group
    elseif lowerText:find("intellect", 1, true) or lowerText:find("intelecto", 1, true) then
        return prefix .. "intellect", group
    elseif lowerText:find("stamina", 1, true) or lowerText:find("vigor", 1, true) then
        return prefix .. "stamina", group
    elseif lowerText:find("spirit", 1, true) or lowerText:find("espírito", 1, true) or lowerText:find("espirito", 1, true) then
        return prefix .. "spirit", group
    elseif lowerText:find("spell damage", 1, true) or lowerText:find("poder mágico", 1, true)
        or lowerText:find("poder magico", 1, true) or lowerText:find("dano mágico", 1, true)
        or lowerText:find("dano de feitiço", 1, true) then
        return "spell_power_elixir", group
    elseif lowerText:find("mana per", 1, true) or lowerText:find("mana a cada", 1, true) then
        return "mp5_elixir", group
    elseif lowerText:find("maximum health", 1, true) or lowerText:find("vida máxima", 1, true)
        or lowerText:find("vida maxima", 1, true) or lowerText:find("saúde máxima", 1, true) then
        return "health_elixir", group
    elseif lowerText:find("attack power", 1, true) or lowerText:find("poder de ataque", 1, true) then
        return "attack_power_elixir", group
    elseif lowerText:find("critical", 1, true) or lowerText:find("crítico", 1, true) or lowerText:find("critico", 1, true) then
        return "crit_elixir", group
    elseif spellID then
        return prefix .. "spell_" .. tostring(spellID), group
    end
    return nil, nil
end

local function inspectItem(itemID, bag, slot)
    if type(itemID) ~= "number" then return nil end
    local cached = itemMetaCache[itemID]
    if cached and cached.loaded then return cached end

    local getter = (C_Item and type(C_Item.GetItemInfo) == "function") and C_Item.GetItemInfo or GetItemInfo
    local ok, name, link, quality, itemLevel, minLevel, itemType, itemSubType,
        _, equipLoc, texture, sellPrice, classID, subClassID = safeCall(getter, itemID)
    if not ok or not safeStr(name) then
        return { itemID = itemID, name = "Item " .. tostring(itemID), loaded = false }
    end

    local spellGetter = (C_Item and type(C_Item.GetItemSpell) == "function") and C_Item.GetItemSpell or GetItemSpell
    local okSp, spellName, spellID = safeCall(spellGetter, itemID)
    spellName = okSp and safeStr(spellName) or nil
    spellID = okSp and safeNum(spellID, nil) or nil

    local tipText = readTooltipText(itemID, bag, slot)
    local lowerText = tipText:lower()
    local nameLower = name:lower()

    local meta = {
        itemID = itemID,
        name = name,
        link = link,
        quality = safeNum(quality, 1) or 1,
        itemLevel = safeNum(itemLevel, 0) or 0,
        minLevel = safeNum(minLevel, 0) or 0,
        itemType = safeStr(itemType) or "",
        itemSubType = safeStr(itemSubType) or "",
        equipLoc = safeStr(equipLoc) or "",
        texture = texture or QUESTION_MARK,
        sellPrice = safeNum(sellPrice, 0) or 0,
        classID = safeNum(classID, -1) or -1,
        subClassID = safeNum(subClassID, -1) or -1,
        spellName = spellName,
        spellID = spellID,
        usable = (spellID ~= nil or spellName ~= nil or lowerText:find("use:", 1, true) ~= nil
            or lowerText:find("uso:", 1, true) ~= nil),
        isFood = false,
        isDrink = false,
        foodRestore = 0,
        drinkRestore = 0,
        longBuff = nil,
        loaded = true,
    }

    -- Classify Food / Drink (Consumable class 0, excluding Potions/Bandages/Elixirs)
    local isConsumable = (meta.classID == 0)
    local subLower = meta.itemSubType:lower()
    local isFoodDrinkSub = isConsumable and (
        meta.subClassID == 4 or meta.subClassID == 5
        or subLower:find("food", 1, true) ~= nil
        or subLower:find("drink", 1, true) ~= nil
        or subLower:find("comida", 1, true) ~= nil
        or subLower:find("bebida", 1, true) ~= nil
    )
    local seatedHint = lowerText:find("seated", 1, true) ~= nil
        or lowerText:find("sentado", 1, true) ~= nil
        or lowerText:find("permanecer sentado", 1, true) ~= nil
        or (spellID ~= nil and (FOOD_AURA_IDS[spellID] or DRINK_AURA_IDS[spellID] or HYBRID_FOOD_DRINK_IDS[spellID]))
        or (spellName ~= nil and (nameLooksLikeFood(normalizeText(spellName)) or nameLooksLikeDrink(normalizeText(spellName))))

    if isConsumable and (isFoodDrinkSub or seatedHint) and meta.subClassID ~= 1 and meta.subClassID ~= 2 then
        local mentionsHealth = lowerText:find("health", 1, true) ~= nil
            or lowerText:find("vida", 1, true) ~= nil
            or lowerText:find("saúde", 1, true) ~= nil
            or lowerText:find("saude", 1, true) ~= nil
        local mentionsMana = lowerText:find("mana", 1, true) ~= nil

        if (mentionsHealth and seatedHint)
            or (spellID and (FOOD_AURA_IDS[spellID] or HYBRID_FOOD_DRINK_IDS[spellID]))
            or (spellName and nameLooksLikeFood(normalizeText(spellName))) then
            meta.isFood = true
            meta.foodRestore = parseRestoreAmount(lowerText, {
                "restores?%s+([%d%.,]+)%s+health",
                "restaura%s+([%d%.,]+)%s+p?o?n?t?o?s?%s*d?e?%s*vida",
                "restaura%s+([%d%.,]+)%s+de%s+vida",
                "([%d%.,]+)%s+health",
                "([%d%.,]+)%s+de%s+vida",
            })
            if spellID then knownFoodSpellIDs[spellID] = true end
        end

        if (mentionsMana and seatedHint)
            or (spellID and (DRINK_AURA_IDS[spellID] or HYBRID_FOOD_DRINK_IDS[spellID]))
            or (spellName and nameLooksLikeDrink(normalizeText(spellName))) then
            meta.isDrink = true
            meta.drinkRestore = parseRestoreAmount(lowerText, {
                "restores?%s+([%d%.,]+)%s+mana",
                "restaura%s+([%d%.,]+)%s+p?o?n?t?o?s?%s*d?e?%s*mana",
                "restaura%s+([%d%.,]+)%s+de%s+mana",
                "([%d%.,]+)%s+mana",
                "([%d%.,]+)%s+de%s+mana",
            })
            if spellID then knownDrinkSpellIDs[spellID] = true end
        end
    end

    -- Classify Long-duration (5+ min) bonus potions, elixirs, flasks and scrolls
    if not EXCLUDED_AUTO_BUFF_ITEMS[itemID] then
        local curated = LONG_BUFF_ITEMS[itemID]
        if curated then
            local buffs = {}
            for _, bid in ipairs(curated.buffs or {}) do buffs[#buffs + 1] = bid end
            if spellID then buffs[#buffs + 1] = spellID end
            meta.longBuff = {
                category = curated.category,
                group = curated.group,
                duration = curated.duration,
                buffs = buffs,
                buffName = spellName and normalizeText(spellName) or nil,
            }
        elseif isConsumable and not meta.isFood and not meta.isDrink then
            local dur = parseDurationSeconds(lowerText)
            local looksLikeBuff = lowerText:find("increases", 1, true) ~= nil
                or lowerText:find("aumenta", 1, true) ~= nil
                or lowerText:find("regenerates", 1, true) ~= nil
                or lowerText:find("regenera", 1, true) ~= nil
                or lowerText:find("restores", 1, true) ~= nil
                or lowerText:find("restaura", 1, true) ~= nil
                or nameLower:find("elixir", 1, true) ~= nil
                or nameLower:find("flask", 1, true) ~= nil
                or nameLower:find("frasco", 1, true) ~= nil
                or nameLower:find("scroll", 1, true) ~= nil
                or nameLower:find("pergaminho", 1, true) ~= nil
            if dur >= 300 and looksLikeBuff then
                local cat, grp = inferDynamicLongBuffCategory(lowerText, nameLower, meta.subClassID, spellID)
                if cat then
                    meta.longBuff = {
                        category = cat,
                        group = grp,
                        duration = dur,
                        buffs = spellID and { spellID } or {},
                        buffName = spellName and normalizeText(spellName) or nil,
                    }
                end
            end
        end
    end

    itemMetaCache[itemID] = meta
    return meta
end

-- ---------------------------------------------------------------------------
-- Inventory scanning (bags + action bar items) & cooldown/in-use checks
-- ---------------------------------------------------------------------------
local function containerNumSlots(bag)
    local fn = (C_Container and type(C_Container.GetContainerNumSlots) == "function" and C_Container.GetContainerNumSlots)
        or (type(GetContainerNumSlots) == "function" and GetContainerNumSlots)
    local ok, n = safeCall(fn, bag)
    return ok and safeNum(n, 0) or 0
end

local function containerItemID(bag, slot)
    if C_Container and type(C_Container.GetContainerItemID) == "function" then
        local ok, id = safeCall(C_Container.GetContainerItemID, bag, slot)
        if ok and type(id) == "number" then return id end
    end
    if type(GetContainerItemID) == "function" then
        local ok, id = safeCall(GetContainerItemID, bag, slot)
        if ok and type(id) == "number" then return id end
    end
    return nil
end

local function isItemOnCooldown(itemID, bag, slot)
    local t = now()
    if state.usedItemUntil[itemID] and t < state.usedItemUntil[itemID] then
        return true, "just_used"
    end

    local function checkStartDur(startVal, durVal, enableVal)
        local s = safeNum(startVal, nil)
        local d = safeNum(durVal, nil)
        local e = safeNum(enableVal, 1)
        if e == 0 then return false end
        if s and d and d > 0 then
            if (s + d - t) > 0.3 then return true end
        end
        return false
    end

    if C_Item and type(C_Item.GetItemCooldown) == "function" then
        local ok, s, d, e = safeCall(C_Item.GetItemCooldown, itemID)
        if ok and checkStartDur(s, d, e) then return true, "C_Item.GetItemCooldown" end
    elseif type(GetItemCooldown) == "function" then
        local ok, s, d, e = safeCall(GetItemCooldown, itemID)
        if ok and checkStartDur(s, d, e) then return true, "GetItemCooldown" end
    end

    if bag ~= nil and slot ~= nil then
        local fn = (C_Container and type(C_Container.GetContainerItemCooldown) == "function" and C_Container.GetContainerItemCooldown)
            or (type(GetContainerItemCooldown) == "function" and GetContainerItemCooldown)
        if fn then
            local ok, s, d, e = safeCall(fn, bag, slot)
            if ok and checkStartDur(s, d, e) then return true, "GetContainerItemCooldown" end
        end
    end

    -- Check if currently casting/channeling the item's spell
    local meta = itemMetaCache[itemID]
    if meta and meta.spellName then
        if addon.Compat and addon.Compat.CastingOrChanneling then
            local rem = addon.Compat.CastingOrChanneling(meta.spellName, "player")
            if rem and safeNum(rem, 0) > 0 then return true, "casting" end
        end
        if addon.Compat and addon.Compat.IsCurrentSpell and addon.Compat.IsCurrentSpell(meta.spellID or meta.spellName) then
            return true, "current_spell"
        end
    end

    return false, nil
end

local bagScanCache
local bagScanTime = 0

local function scanOwnedBagItems(force)
    local t = now()
    if not force and bagScanCache and (t - bagScanTime) < 0.8 then
        return bagScanCache
    end
    local items = {} -- [itemID] = { itemID, bag, slot, onBar, meta }
    local bagCount = tonumber(_G.NUM_BAG_SLOTS) or 4
    for bag = 0, bagCount do
        local slots = containerNumSlots(bag)
        for slot = 1, slots do
            local itemID = containerItemID(bag, slot)
            if itemID and not items[itemID] then
                local meta = inspectItem(itemID, bag, slot)
                local barButtons = addon.Visuals and addon.Visuals.FindItemButtons
                    and addon.Visuals.FindItemButtons(itemID) or {}
                items[itemID] = {
                    itemID = itemID,
                    bag = bag,
                    slot = slot,
                    onBar = (#barButtons > 0),
                    meta = meta,
                }
            end
        end
    end
    bagScanCache = items
    bagScanTime = t
    return items
end

-- ---------------------------------------------------------------------------
-- SavedVariables helpers (per-character)
-- ---------------------------------------------------------------------------
local function getConfig(create)
    if type(addon.charDb) ~= "table" then return nil end
    local cfg = addon.charDb.consumables
    if type(cfg) ~= "table" then
        if not create then return nil end
        cfg = {
            foodEnabled = false,
            foodThreshold = 50,
            drinkEnabled = false,
            drinkThreshold = 50,
            bonusEnabled = false,
            bonusElixirs = true,
            bonusScrolls = true,
            customRules = {},
            nextRuleId = 1,
        }
        addon.charDb.consumables = cfg
    end
    if cfg.foodThreshold == nil then cfg.foodThreshold = 50 end
    if cfg.drinkThreshold == nil then cfg.drinkThreshold = 50 end
    if cfg.bonusElixirs == nil then cfg.bonusElixirs = true end
    if cfg.bonusScrolls == nil then cfg.bonusScrolls = true end
    if type(cfg.customRules) ~= "table" then cfg.customRules = {} end
    if type(cfg.nextRuleId) ~= "number" then cfg.nextRuleId = #cfg.customRules + 1 end
    return cfg
end

function Consumables.GetConfig()
    return getConfig(true)
end

-- ---------------------------------------------------------------------------
-- Custom rules conditions (independent from class modules)
-- ---------------------------------------------------------------------------
local RULE_AXES = {
    {
        key = "combat",
        labelKey = "cons_axis_combat",
        fallback = "1. Combate",
        options = {
            { 1, "axis_in_combat",  "Em combate" },
            { 2, "axis_out_combat", "Fora de combate" },
        },
    },
    {
        key = "env",
        labelKey = "cons_axis_env",
        fallback = "2. Ambiente",
        options = {
            { 1, "PvE",                 "PvE" },
            { 2, "PvP",                 "PvP" },
            { 3, "cons_env_underwater", "Na água / submerso" },
        },
    },
    {
        key = "breath",
        labelKey = "cons_axis_breath",
        fallback = "3. Fôlego (água)",
        options = {
            { 1, "cons_breath_50", "Fôlego < 50%" },
            { 2, "cons_breath_30", "Fôlego < 30%" },
        },
    },
    {
        key = "hp",
        labelKey = "cons_axis_hp",
        fallback = "4. Vida do jogador",
        options = {
            { 1, "cons_hp_25", "Vida <= 25%" },
            { 2, "cons_hp_40", "Vida <= 40%" },
            { 3, "cons_hp_60", "Vida <= 60%" },
            { 4, "cons_hp_75", "Vida <= 75%" },
        },
    },
    {
        key = "mana",
        labelKey = "cons_axis_mana",
        fallback = "5. Mana do jogador",
        manaOnly = true,
        options = {
            { 1, "cons_mana_25", "Mana <= 25%" },
            { 2, "cons_mana_40", "Mana <= 40%" },
            { 3, "cons_mana_60", "Mana <= 60%" },
        },
    },
    {
        key = "target",
        labelKey = "cons_axis_target",
        fallback = "6. Alvo / Alcance",
        options = {
            { 1, "axis_attackable", "Inimigo atacável" },
            { 2, "axis_melee",      "Em alcance melee" },
            { 3, "axis_ranged",     "À distância (ranged)" },
            { 4, "axis_aoe_2",      "Área (2+ inimigos)" },
        },
    },
}

local function buildConsumableEnv()
    local inCombat = playerInCombat()
    local moving = playerIsMoving()
    local hpPct = playerHealthPct()
    local manaPct = playerManaPct()
    local swimming, breathPct = playerUnderwaterAndBreath()
    local isPvP = (type(addon.IsPvPInstance) == "function" and addon.IsPvPInstance()) or false
    local hasEnemy = (type(addon.UnitTargetExistsAndAttackable) == "function" and addon.UnitTargetExistsAndAttackable()) or false
    local isMelee = false
    if hasEnemy and type(addon.IsInMeleeRange) == "function" then
        local ok, m = pcall(addon.IsInMeleeRange, addon, "target")
        isMelee = ok and m == true
    end
    local enemies = hasEnemy and 1 or 0
    if C_NamePlate and type(C_NamePlate.EnumerateUnits) == "function" then
        local ok, units = pcall(function() return { C_NamePlate.EnumerateUnits() } end)
        if ok and type(units) == "table" then
            local c = 0
            for _, u in ipairs(units) do
                if addon.Enemy and addon:Enemy(u) then c = c + 1 end
            end
            if c > enemies then enemies = c end
        end
    end
    return {
        inCombat = inCombat,
        moving = moving,
        mounted = playerIsMounted(),
        hpPct = hpPct,
        manaPct = manaPct,
        hasMana = Consumables.PlayerHasMana(),
        swimming = swimming,
        breathPct = breathPct,
        isPvP = isPvP,
        hasEnemy = hasEnemy,
        isMelee = isMelee,
        isAoE = enemies >= 2,
        enemyCount = enemies,
        bagOpen = (addon.Visuals and addon.Visuals.IsAnyBagOpen and addon.Visuals.IsAnyBagOpen()) or false,
    }
end

local function isTriggerSpellRecent(rule)
    local trigID = tonumber(rule.triggerSpellID)
    local trigName = safeStr(rule.triggerSpellName)
    if not trigID and not trigName then return true end
    local window = tonumber(rule.triggerWindow) or 8
    local t = now()
    if trigID then
        local ts = state.lastCastByID[trigID]
        if ts and (t - ts) <= window then return true end
        local fam = addon.Compat and addon.Compat.FamilyOf and addon.Compat.FamilyOf[trigID]
        if fam then
            for _, id in ipairs(fam) do
                local fts = state.lastCastByID[id]
                if fts and (t - fts) <= window then return true end
            end
        end
    end
    if trigName then
        local ts = state.lastCastByName[normalizeText(trigName)]
        if ts and (t - ts) <= window then return true end
    end
    return false
end

local function ruleHasAnyCondition(rule)
    if type(rule) ~= "table" then return false end
    if rule.triggerSpellID or safeStr(rule.triggerSpellName) then return true end
    if type(rule.conditions) == "table" then
        for _, v in pairs(rule.conditions) do
            if tonumber(v) and tonumber(v) ~= 0 then return true end
        end
    end
    return false
end

local function evaluateCustomRule(rule, env)
    if type(rule) ~= "table" or rule.enabled == false or not tonumber(rule.itemID) then
        return false, "disabled_or_no_item"
    end
    local conds = type(rule.conditions) == "table" and rule.conditions or {}

    local vCombat = tonumber(conds.combat) or 0
    if vCombat == 1 and not env.inCombat then return false, "need_combat" end
    if vCombat == 2 and env.inCombat then return false, "need_out_of_combat" end

    local vEnv = tonumber(conds.env) or 0
    if vEnv == 1 and env.isPvP then return false, "need_pve" end
    if vEnv == 2 and not env.isPvP then return false, "need_pvp" end
    if vEnv == 3 and not env.swimming then return false, "need_underwater" end

    local vBreath = tonumber(conds.breath) or 0
    if vBreath == 1 then
        if not env.breathPct or env.breathPct >= 50 then return false, "breath_ok" end
    elseif vBreath == 2 then
        if not env.breathPct or env.breathPct >= 30 then return false, "breath_ok" end
    end

    local vHP = tonumber(conds.hp) or 0
    if vHP > 0 then
        local limits = { 25, 40, 60, 75 }
        local lim = limits[vHP]
        if not env.hpPct or env.hpPct > lim then return false, "hp_above_limit" end
    end

    local vMana = tonumber(conds.mana) or 0
    if vMana > 0 then
        local limits = { 25, 40, 60 }
        local lim = limits[vMana]
        if not env.hasMana or not env.manaPct or env.manaPct > lim then return false, "mana_above_limit" end
    end

    local vTarget = tonumber(conds.target) or 0
    if vTarget == 1 and not env.hasEnemy then return false, "need_enemy" end
    if vTarget == 2 and not (env.hasEnemy and env.isMelee) then return false, "need_melee" end
    if vTarget == 3 and not (env.hasEnemy and not env.isMelee) then return false, "need_ranged" end
    if vTarget == 4 and not (env.hasEnemy and env.isAoE) then return false, "need_aoe" end

    if rule.triggerSpellID or safeStr(rule.triggerSpellName) then
        if not isTriggerSpellRecent(rule) then return false, "waiting_trigger_spell" end
    end

    return true, "ok"
end

-- ---------------------------------------------------------------------------
-- Candidate ranking & buff matching
-- ---------------------------------------------------------------------------
local function isBetterCandidate(a, b, restoreField)
    if not b then return true end
    local ma, mb = a.meta, b.meta
    -- Highest value (sellPrice) first, as requested by the user
    if (ma.sellPrice or 0) ~= (mb.sellPrice or 0) then
        return (ma.sellPrice or 0) > (mb.sellPrice or 0)
    end
    -- Tie-breaker (e.g. conjured mage food/water with sellPrice == 0): restore amount -> itemLevel -> minLevel
    if restoreField and (ma[restoreField] or 0) ~= (mb[restoreField] or 0) then
        return (ma[restoreField] or 0) > (mb[restoreField] or 0)
    end
    if (ma.itemLevel or 0) ~= (mb.itemLevel or 0) then
        return (ma.itemLevel or 0) > (mb.itemLevel or 0)
    end
    return (ma.minLevel or 0) > (mb.minLevel or 0)
end

local function isLongBuffActive(entry, aurasByID, aurasByName)
    local lb = entry.meta and entry.meta.longBuff
    if not lb then return false end
    local t = now()
    if state.usedCategoryUntil[lb.category] and t < state.usedCategoryUntil[lb.category] then
        return true
    end
    for _, bid in ipairs(lb.buffs or {}) do
        if aurasByID[bid] then return true end
    end
    if entry.meta.spellID and aurasByID[entry.meta.spellID] then
        return true
    end
    if lb.buffName and lb.buffName ~= "" and aurasByName[lb.buffName] then
        return true
    end
    -- If a Flask is active, treat flask category as satisfied
    if lb.category == "flask" then
        for _, fid in ipairs({ 17626, 17627, 17628, 17629 }) do
            if aurasByID[fid] then return true end
        end
    end
    return false
end

local function itemIsEligibleToShow(entry, bagOpen)
    if not entry or not entry.meta then return false end
    if (entry.meta.minLevel or 0) > playerLevel() then return false end
    -- When bag is open: can highlight in bag (and on bar if also bound).
    -- When bag is closed: only suggest if the item is on an action bar.
    if not bagOpen and not entry.onBar then return false end
    local onCD = isItemOnCooldown(entry.itemID, entry.bag, entry.slot)
    if onCD then return false end
    return true
end

-- ---------------------------------------------------------------------------
-- Main independent suggestion generator (called by Core every tick)
-- ---------------------------------------------------------------------------
function Consumables.GetSuggestions()
    local cfg = getConfig(false)
    if not cfg then return {} end

    local env = buildConsumableEnv()
    local owned = scanOwnedBagItems(false)
    local aurasByID, aurasByName = collectPlayerAuras()
    local eating, drinking = checkEatingDrinking(aurasByID, aurasByName)

    local suggestions = {}
    local addedItemIDs = {}
    local function addSuggestion(itemID, color, reasonTag)
        if addedItemIDs[itemID] then return end
        addedItemIDs[itemID] = true
        suggestions[#suggestions + 1] = {
            kind = "item",
            itemID = itemID,
            color = color or "Utility",
            highlightBags = true,
            source = reasonTag,
        }
    end

    -- 1) Food (HP) and Drink/Water (Mana) — out of combat, standing still, not mounted.
    --    Both can glow simultaneously!
    if not env.inCombat and not env.moving and not env.mounted then
        if cfg.foodEnabled and not eating and env.hpPct ~= nil and env.hpPct < (cfg.foodThreshold or 50) then
            local bestFood
            for _, entry in pairs(owned) do
                if entry.meta and entry.meta.isFood and itemIsEligibleToShow(entry, env.bagOpen) then
                    if isBetterCandidate(entry, bestFood, "foodRestore") then
                        bestFood = entry
                    end
                end
            end
            if bestFood then addSuggestion(bestFood.itemID, "Defensive", "food") end
        end

        if cfg.drinkEnabled and env.hasMana and not drinking
            and env.manaPct ~= nil and env.manaPct < (cfg.drinkThreshold or 50) then
            local bestDrink
            for _, entry in pairs(owned) do
                if entry.meta and entry.meta.isDrink and itemIsEligibleToShow(entry, env.bagOpen) then
                    if isBetterCandidate(entry, bestDrink, "drinkRestore") then
                        bestDrink = entry
                    end
                end
            end
            if bestDrink then addSuggestion(bestDrink.itemID, "Utility", "drink") end
        end
    end

    -- 2) Long-duration (5+ min) bonus potions, elixirs, flasks and scrolls
    if cfg.bonusEnabled and not env.mounted then
        local bestByCategory = {}
        for _, entry in pairs(owned) do
            local lb = entry.meta and entry.meta.longBuff
            if lb and itemIsEligibleToShow(entry, env.bagOpen) then
                local groupAllowed = (lb.group == "scroll" and cfg.bonusScrolls ~= false)
                    or (lb.group ~= "scroll" and cfg.bonusElixirs ~= false)
                if groupAllowed and not isLongBuffActive(entry, aurasByID, aurasByName) then
                    local curBest = bestByCategory[lb.category]
                    if isBetterCandidate(entry, curBest, nil) then
                        bestByCategory[lb.category] = entry
                    end
                end
            end
        end
        for cat, entry in pairs(bestByCategory) do
            addSuggestion(entry.itemID, "Utility", "bonus:" .. tostring(cat))
        end
    end

    -- 3) User-configured situational rules ([+] button)
    for _, rule in ipairs(cfg.customRules or {}) do
        local itemID = tonumber(rule.itemID)
        local entry = itemID and owned[itemID] or nil
        if entry and itemIsEligibleToShow(entry, env.bagOpen) then
            local okRule = evaluateCustomRule(rule, env)
            if okRule then
                -- Skip if this rule's item already has its own buff active
                local alreadyBuffed = false
                if entry.meta and entry.meta.spellID and aurasByID[entry.meta.spellID] then
                    alreadyBuffed = true
                elseif entry.meta and entry.meta.longBuff and isLongBuffActive(entry, aurasByID, aurasByName) then
                    alreadyBuffed = true
                end
                if not alreadyBuffed then
                    addSuggestion(itemID, "AoE", "rule:" .. tostring(rule.id))
                end
            end
        end
    end

    return suggestions
end

-- ---------------------------------------------------------------------------
-- Event tracking: immediate stop on cast/use, spell triggers, bag changes
-- ---------------------------------------------------------------------------
local tracker = CreateFrame("Frame", "CFA_ConsumablesTracker", UIParent)
tracker:RegisterEvent("BAG_UPDATE_DELAYED")
tracker:RegisterEvent("PLAYER_ENTERING_WORLD")
tracker:RegisterEvent("PLAYER_DEAD")
tracker:RegisterEvent("PLAYER_REGEN_DISABLED")
tracker:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
tracker:RegisterUnitEvent("UNIT_SPELLCAST_SENT", "player")

tracker:SetScript("OnEvent", function(_, event, arg1, arg2, arg3, arg4)
    if event == "BAG_UPDATE_DELAYED" then
        bagScanCache = nil
    elseif event == "PLAYER_ENTERING_WORLD" or event == "PLAYER_DEAD" then
        bagScanCache = nil
        state.eatingBeliefUntil = 0
        state.drinkingBeliefUntil = 0
        wipe(state.usedItemUntil)
        wipe(state.usedCategoryUntil)
        wipe(state.lastCastByID)
        wipe(state.lastCastByName)
    elseif event == "PLAYER_REGEN_DISABLED" then
        state.eatingBeliefUntil = 0
        state.drinkingBeliefUntil = 0
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" or event == "UNIT_SPELLCAST_SENT" then
        local unit = arg1
        if unit ~= "player" then return end
        local rawSpellID = (event == "UNIT_SPELLCAST_SENT") and arg4 or arg3
        local spellID = safeNum(rawSpellID, nil)
        local spellName = spellID and addon.SpellName and addon.SpellName(spellID) or nil
        local normName = spellName and normalizeText(spellName) or nil
        local t = now()

        if event == "UNIT_SPELLCAST_SUCCEEDED" then
            if spellID then state.lastCastByID[spellID] = t end
            if normName and normName ~= "" then state.lastCastByName[normName] = t end
            state.lastCastSummary = tostring(spellName or spellID)
        end

        if spellID and (FOOD_AURA_IDS[spellID] or HYBRID_FOOD_DRINK_IDS[spellID] or knownFoodSpellIDs[spellID]) then
            state.eatingBeliefUntil = t + 3
        end
        if spellID and (DRINK_AURA_IDS[spellID] or HYBRID_FOOD_DRINK_IDS[spellID] or knownDrinkSpellIDs[spellID]) then
            state.drinkingBeliefUntil = t + 3
        end
        if normName and normName ~= "" then
            if nameLooksLikeFood(normName) then state.eatingBeliefUntil = t + 3 end
            if nameLooksLikeDrink(normName) then state.drinkingBeliefUntil = t + 3 end
        end

        -- Match against owned items' spellIDs to stop their glow immediately & clear triggered rules
        local owned = bagScanCache
        if owned and spellID then
            for itemID, entry in pairs(owned) do
                if entry.meta and entry.meta.spellID == spellID then
                    state.usedItemUntil[itemID] = t + 1.5
                    if entry.meta.isFood then state.eatingBeliefUntil = t + 3 end
                    if entry.meta.isDrink then state.drinkingBeliefUntil = t + 3 end
                    if entry.meta.longBuff then
                        state.usedCategoryUntil[entry.meta.longBuff.category] = t + math.min(entry.meta.longBuff.duration or 300, 3600)
                    end
                    -- If this item was triggered by a spell rule, consume the trigger
                    local cfg = getConfig(false)
                    if cfg then
                        for _, rule in ipairs(cfg.customRules or {}) do
                            if tonumber(rule.itemID) == itemID and rule.triggerSpellID then
                                state.lastCastByID[tonumber(rule.triggerSpellID)] = nil
                                if safeStr(rule.triggerSpellName) then
                                    state.lastCastByName[normalizeText(rule.triggerSpellName)] = nil
                                end
                            end
                        end
                    end
                end
            end
        end
    end
end)

-- ---------------------------------------------------------------------------
-- Chat diagnostic command: /cfa items (and /cfa food, /cfa consumables)
-- ---------------------------------------------------------------------------
function Consumables.DebugDump()
    local function P(...)
        local parts = {}
        for i = 1, select("#", ...) do parts[#parts + 1] = tostring((select(i, ...))) end
        print("|cff44ddff[CFA items]|r " .. table.concat(parts, " "))
    end

    local cfg = getConfig(true)
    local env = buildConsumableEnv()
    local owned = scanOwnedBagItems(true)
    local aurasByID, aurasByName, auraReadable = collectPlayerAuras()
    local eating, drinking = checkEatingDrinking(aurasByID, aurasByName)

    P("===== DIAGNÓSTICO FOOD, POTIONS & ITENS =====")
    P(string.format("combat=%s moving=%s mounted=%s bagOpen=%s hp=%s mana=%s hasMana=%s",
        tostring(env.inCombat), tostring(env.moving), tostring(env.mounted), tostring(env.bagOpen),
        env.hpPct and string.format("%.1f%%", env.hpPct) or "nil",
        env.manaPct and string.format("%.1f%%", env.manaPct) or "nil",
        tostring(env.hasMana)))
    P(string.format("eating=%s drinking=%s aurasReadable=%s swimming=%s breath=%s lastCast=%s",
        tostring(eating), tostring(drinking), tostring(auraReadable),
        tostring(env.swimming), env.breathPct and string.format("%.1f%%", env.breathPct) or "nil",
        tostring(state.lastCastSummary)))
    P(string.format("config: food=%s(<%d%%) drink=%s(<%d%%) bonus=%s(elix=%s,scroll=%s) customRules=%d",
        tostring(cfg.foodEnabled), cfg.foodThreshold or 50,
        tostring(cfg.drinkEnabled), cfg.drinkThreshold or 50,
        tostring(cfg.bonusEnabled), tostring(cfg.bonusElixirs), tostring(cfg.bonusScrolls),
        #(cfg.customRules or {})))

    local bestFood, bestDrink
    local bonusList = {}
    for _, entry in pairs(owned) do
        local m = entry.meta
        if m then
            if m.isFood and isBetterCandidate(entry, bestFood, "foodRestore") then bestFood = entry end
            if m.isDrink and isBetterCandidate(entry, bestDrink, "drinkRestore") then bestDrink = entry end
            if m.longBuff then bonusList[#bonusList + 1] = entry end
        end
    end

    if bestFood then
        local cd, cdSrc = isItemOnCooldown(bestFood.itemID, bestFood.bag, bestFood.slot)
        P(string.format("  Melhor Comida: [%d] %s (valor=%dc restore=%d lvl=%d onBar=%s cd=%s/%s)",
            bestFood.itemID, bestFood.meta.name, bestFood.meta.sellPrice, bestFood.meta.foodRestore,
            bestFood.meta.minLevel, tostring(bestFood.onBar), tostring(cd), tostring(cdSrc)))
    else
        P("  Melhor Comida: nenhuma encontrada na bolsa")
    end

    if bestDrink then
        local cd, cdSrc = isItemOnCooldown(bestDrink.itemID, bestDrink.bag, bestDrink.slot)
        P(string.format("  Melhor Bebida: [%d] %s (valor=%dc restore=%d lvl=%d onBar=%s cd=%s/%s)",
            bestDrink.itemID, bestDrink.meta.name, bestDrink.meta.sellPrice, bestDrink.meta.drinkRestore,
            bestDrink.meta.minLevel, tostring(bestDrink.onBar), tostring(cd), tostring(cdSrc)))
    else
        P("  Melhor Bebida: nenhuma encontrada na bolsa")
    end

    P("  Poções/Pergaminhos 5+ min na bolsa:", #bonusList)
    for _, entry in ipairs(bonusList) do
        local lb = entry.meta.longBuff
        local active = isLongBuffActive(entry, aurasByID, aurasByName)
        local cd = isItemOnCooldown(entry.itemID, entry.bag, entry.slot)
        P(string.format("    [%d] %s | cat=%s grp=%s dur=%ds valor=%dc buffAtivo=%s onBar=%s cd=%s",
            entry.itemID, entry.meta.name, lb.category, lb.group, lb.duration,
            entry.meta.sellPrice, tostring(active), tostring(entry.onBar), tostring(cd)))
    end

    P("  Regras personalizadas:", #(cfg.customRules or {}))
    for _, rule in ipairs(cfg.customRules or {}) do
        local okR, why = evaluateCustomRule(rule, env)
        local itemID = tonumber(rule.itemID)
        local entry = itemID and owned[itemID]
        local nm = entry and entry.meta and entry.meta.name or tostring(itemID)
        local cd = entry and isItemOnCooldown(itemID, entry.bag, entry.slot) or false
        P(string.format("    #%s [%s] %s | en=%s pass=%s (%s) inBag=%s onBar=%s cd=%s trig=%s",
            tostring(rule.id), tostring(itemID or "-"), nm, tostring(rule.enabled ~= false),
            tostring(okR), tostring(why), tostring(entry ~= nil), tostring(entry and entry.onBar or false),
            tostring(cd), tostring(rule.triggerSpellName or rule.triggerSpellID or "-")))
    end

    local activeSugs = Consumables.GetSuggestions()
    P("  Sugestões ativas agora:", #activeSugs)
    for _, s in ipairs(activeSugs) do
        P("    -> itemID=", s.itemID, "color=", s.color, "source=", s.source)
    end
    P("===== FIM DIAGNÓSTICO =====")
end

-- ---------------------------------------------------------------------------
-- Options Tab UI: "Food, Potions, Itens"
-- ---------------------------------------------------------------------------
local function collectKnownPlayerSpells()
    local spells = {}
    local seen = {}
    local function addSpell(id, name)
        id = safeNum(id, nil)
        name = safeStr(name)
        if not name and id and addon.SpellName then name = addon.SpellName(id) end
        if not name then return end
        local key = normalizeText(name)
        if key == "" or seen[key] then return end
        seen[key] = true
        local tex = QUESTION_MARK
        if id and C_Spell and type(C_Spell.GetSpellTexture) == "function" then
            local ok, t = pcall(C_Spell.GetSpellTexture, id)
            if ok and t then tex = t end
        elseif id and type(GetSpellTexture) == "function" then
            local ok, t = pcall(GetSpellTexture, id)
            if ok and t then tex = t end
        end
        spells[#spells + 1] = { spellID = id, name = name, texture = tex }
    end

    -- 1) Action bar spells (most relevant abilities the player actually uses)
    if type(GetActionInfo) == "function" then
        for slot = 1, 180 do
            local ok, actionType, id = safeCall(GetActionInfo, slot)
            if ok and actionType == "spell" and type(id) == "number" then
                addSpell(id)
            end
        end
    end

    -- 2) Active class module rotation spells
    local mod = addon.activeModule
    if mod and type(mod.RotationSpecs) == "table" then
        for _, spec in pairs(mod.RotationSpecs) do
            if type(spec) == "table" and type(spec.nodes) == "table" then
                for _, node in ipairs(spec.nodes) do
                    if type(node.spellID) == "number" then
                        local knownID = (addon.Compat and addon.Compat.HighestKnownSpellID
                            and addon.Compat.HighestKnownSpellID(node.spellID)) or node.spellID
                        if not (addon.Compat and addon.Compat.SpellKnown) or addon.Compat.SpellKnown(knownID) then
                            addSpell(knownID)
                        end
                    end
                end
            end
        end
    end

    -- 3) Spellbook scan fallback
    if C_SpellBook and type(C_SpellBook.GetSpellBookItemInfo) == "function" then
        for i = 1, 200 do
            local ok, info = safeCall(C_SpellBook.GetSpellBookItemInfo, i, "spell")
            if ok and type(info) == "table" and info.name then
                addSpell(info.spellID or info.actionID or info.id, info.name)
            end
        end
    end

    table.sort(spells, function(a, b) return a.name:lower() < b.name:lower() end)
    return spells
end

local function collectUsableBagItems(selectedItemID)
    local owned = scanOwnedBagItems(true)
    local list = {}
    local seen = {}
    for itemID, entry in pairs(owned) do
        local m = entry.meta
        if m and (m.usable or m.classID == 0 or itemID == selectedItemID) then
            seen[itemID] = true
            list[#list + 1] = {
                itemID = itemID,
                name = m.name or ("Item " .. tostring(itemID)),
                texture = m.texture or QUESTION_MARK,
            }
        end
    end
    if selectedItemID and not seen[selectedItemID] then
        local m = inspectItem(selectedItemID)
        list[#list + 1] = {
            itemID = selectedItemID,
            name = (m and m.name or ("Item " .. tostring(selectedItemID))) .. " (" .. loc("cons_not_in_bag", "fora da bolsa") .. ")",
            texture = m and m.texture or QUESTION_MARK,
        }
    end
    table.sort(list, function(a, b) return a.name:lower() < b.name:lower() end)
    return list
end

local function formatRuleSummary(rule)
    local parts = {}
    local conds = type(rule.conditions) == "table" and rule.conditions or {}
    for _, axis in ipairs(RULE_AXES) do
        local v = tonumber(conds[axis.key]) or 0
        if v ~= 0 then
            for _, opt in ipairs(axis.options) do
                if opt[1] == v then
                    local axisTitle = loc(axis.labelKey, axis.fallback):gsub("^%d+%.%s*", "")
                    parts[#parts + 1] = axisTitle .. ": " .. loc(opt[2], opt[3])
                    break
                end
            end
        end
    end
    if rule.triggerSpellID or safeStr(rule.triggerSpellName) then
        local spName = safeStr(rule.triggerSpellName)
            or (rule.triggerSpellID and addon.SpellName and addon.SpellName(rule.triggerSpellID))
            or tostring(rule.triggerSpellID)
        parts[#parts + 1] = loc("cons_after_spell_prefix", "Após habilidade: ") .. tostring(spName)
    end
    if #parts == 0 then
        return loc("rot_no_condition", "- sem condições -")
    end
    return loc("rot_conditions_prefix", "Condições: ") .. table.concat(parts, " · ")
end

local function buildConsumablesTab(host)
    local parent, setContentHeight = addon.Options.CreateScrollableTab(host)
    local cfg = getConfig(true)
    local dynamicRows = {}

    local function makeHeader(yPos, text)
        local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        fs:SetPoint("TOPLEFT", parent, "TOPLEFT", 6, yPos)
        fs:SetTextColor(ORANGE[1], ORANGE[2], ORANGE[3], 1)
        fs:SetText(text)
        return yPos - 22
    end

    local function makeCompactSlider(anchorFrame, minV, maxV, initial, onChange)
        local slider = CreateFrame("Slider", nil, parent)
        slider:SetOrientation("HORIZONTAL")
        slider:SetMinMaxValues(minV, maxV)
        slider:SetValueStep(5)
        pcall(function() slider:SetObeyStepOnDrag(true) end)
        slider:SetWidth(118)
        slider:SetHeight(16)
        slider:SetPoint("LEFT", anchorFrame, "RIGHT", 8, 0)

        local track = slider:CreateTexture(nil, "BACKGROUND")
        track:SetTexture("Interface\\Buttons\\WHITE8X8")
        track:SetVertexColor(0.20, 0.20, 0.20, 0.95)
        track:SetPoint("LEFT", slider, "LEFT", 0, 0)
        track:SetPoint("RIGHT", slider, "RIGHT", 0, 0)
        track:SetHeight(6)

        slider:SetThumbTexture("Interface\\Buttons\\WHITE8X8")
        local thumb = slider:GetThumbTexture()
        if thumb then
            thumb:SetWidth(10)
            thumb:SetHeight(16)
            thumb:SetVertexColor(ORANGE[1], ORANGE[2], ORANGE[3], 1)
        end

        local valFS = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        valFS:SetPoint("LEFT", slider, "RIGHT", 6, 0)
        valFS:SetTextColor(1, 0.9, 0.6, 1)

        slider:SetScript("OnValueChanged", function(_, v)
            local rounded = math.floor((v + 2.5) / 5) * 5
            rounded = math.max(minV, math.min(maxV, rounded))
            onChange(rounded)
            valFS:SetText(tostring(rounded) .. "%")
        end)
        slider:EnableMouseWheel(true)
        slider:SetScript("OnMouseWheel", function(self, delta)
            self:SetValue(math.max(minV, math.min(maxV, self:GetValue() + (delta > 0 and 5 or -5))))
        end)
        slider:SetValue(initial)
        return slider
    end

    local function makeThresholdRow(yPos, labelText, checked, threshold, onToggle, onThreshold)
        local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
        cb:SetSize(22, 22)
        cb:SetPoint("TOPLEFT", parent, "TOPLEFT", 6, yPos)
        cb:SetChecked(checked and true or false)
        cb:SetScript("OnClick", function(self) onToggle(self:GetChecked() == true) end)

        local lbl = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        lbl:SetPoint("LEFT", cb, "RIGHT", 4, 0)
        lbl:SetWidth(150)
        lbl:SetJustifyH("LEFT")
        lbl:SetText(labelText)

        makeCompactSlider(lbl, 5, 95, threshold or 50, onThreshold)
        return yPos - 28
    end

    local y = -8
    -- Section 1: Food & Drink (HP / Mana)
    y = makeHeader(y, loc("cons_section_food_drink", "Comida e Água (fora de combate, parado)"))

    y = makeThresholdRow(y, loc("cons_food_enable", "Recomendar Comida (Vida)"),
        cfg.foodEnabled, cfg.foodThreshold,
        function(v) cfg.foodEnabled = v end,
        function(v) cfg.foodThreshold = v end)

    if Consumables.PlayerHasMana() then
        y = makeThresholdRow(y, loc("cons_drink_enable", "Recomendar Água (Mana)"),
            cfg.drinkEnabled, cfg.drinkThreshold,
            function(v) cfg.drinkEnabled = v end,
            function(v) cfg.drinkThreshold = v end)
    end

    local fdHint = parent:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    fdHint:SetPoint("TOPLEFT", parent, "TOPLEFT", 8, y)
    fdHint:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -8, y)
    fdHint:SetJustifyH("LEFT")
    fdHint:SetWordWrap(true)
    fdHint:SetText(loc("cons_food_drink_hint",
        "Bolsa aberta: destaca o item de maior valor na bolsa (e na barra se estiver nela). Bolsa fechada: destaca na barra. Comida e água podem brilhar juntas e param ao comer/beber."))
    y = y - 34

    -- Section 2: Long-duration (5+ min) bonus potions, elixirs and scrolls
    y = makeHeader(y, loc("cons_section_bonus", "Poções de bônus e pergaminhos (5+ min)"))

    local function makeSimpleCheck(yPos, indent, labelText, checked, onToggle)
        local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
        cb:SetSize(22, 22)
        cb:SetPoint("TOPLEFT", parent, "TOPLEFT", 6 + indent, yPos)
        cb:SetChecked(checked and true or false)
        cb:SetScript("OnClick", function(self) onToggle(self:GetChecked() == true) end)
        local lbl = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        lbl:SetPoint("LEFT", cb, "RIGHT", 4, 0)
        lbl:SetPoint("RIGHT", parent, "RIGHT", -6, 0)
        lbl:SetJustifyH("LEFT")
        lbl:SetWordWrap(true)
        lbl:SetText(labelText)
        return yPos - 24
    end

    y = makeSimpleCheck(y, 0, loc("cons_bonus_enable", "Recomendar poções de bônus / pergaminhos faltantes"),
        cfg.bonusEnabled, function(v) cfg.bonusEnabled = v end)
    y = makeSimpleCheck(y, 18, loc("cons_bonus_elixirs", "Elixires, frascos e poções de bônus (5+ min)"),
        cfg.bonusElixirs ~= false, function(v) cfg.bonusElixirs = v end)
    y = makeSimpleCheck(y, 18, loc("cons_bonus_scrolls", "Pergaminhos de atributos/armadura (30 min)"),
        cfg.bonusScrolls ~= false, function(v) cfg.bonusScrolls = v end)

    local bonusHint = parent:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    bonusHint:SetPoint("TOPLEFT", parent, "TOPLEFT", 8, y)
    bonusHint:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -8, y)
    bonusHint:SetJustifyH("LEFT")
    bonusHint:SetWordWrap(true)
    bonusHint:SetText(loc("cons_bonus_hint",
        "Compara a bolsa com seus buffs ativos e destaca a poção/pergaminho mais caro de cada tipo faltante."))
    y = y - 28

    -- Section 3: Custom situational items & short-duration potions ([+] button)
    y = makeHeader(y, loc("cons_section_custom", "Poções situacionais e itens usáveis"))

    local addRuleBtn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    addRuleBtn:SetSize(165, 22)
    addRuleBtn:SetPoint("TOPLEFT", parent, "TOPLEFT", 6, y)
    addRuleBtn:SetText(loc("cons_add_rule", "+ Adicionar item / regra"))
    y = y - 28

    local rulesStartY = y
    local rebuildCustomRows

    local function showItemChoices(anchor, rule)
        local picker = addon.RotationEditor and addon.RotationEditor.ShowPicker
        if not picker then return end
        picker(anchor, loc("equip_select_item", "Selecionar item"), function()
            local choices = {
                { header = loc("cons_bag_items_header", "Itens usáveis na bolsa") },
                {
                    label = loc("equip_no_item", "(nenhum item selecionado)"),
                    checked = not rule.itemID,
                    action = function() rule.itemID = nil end,
                },
            }
            for _, item in ipairs(collectUsableBagItems(tonumber(rule.itemID))) do
                local choice = item
                choices[#choices + 1] = {
                    label = string.format("|T%s:16:16|t %s", choice.texture or QUESTION_MARK, choice.name),
                    checked = tonumber(rule.itemID) == choice.itemID,
                    action = function() rule.itemID = choice.itemID end,
                }
            end
            return choices
        end, function() rebuildCustomRows() end)
    end

    local function showTriggerSpellChoices(anchor, rule)
        local picker = addon.RotationEditor and addon.RotationEditor.ShowPicker
        if not picker then return end
        picker(anchor, loc("cons_pick_spell", "Habilidade gatilho"), function()
            local choices = {
                { header = loc("cons_pick_spell_header", "Disparar após usar habilidade") },
                {
                    label = loc("cons_no_trigger_spell", "(nenhuma habilidade gatilho)"),
                    checked = not rule.triggerSpellID and not safeStr(rule.triggerSpellName),
                    action = function()
                        rule.triggerSpellID = nil
                        rule.triggerSpellName = nil
                    end,
                },
            }
            for _, sp in ipairs(collectKnownPlayerSpells()) do
                local spellChoice = sp
                choices[#choices + 1] = {
                    label = string.format("|T%s:16:16|t %s", spellChoice.texture or QUESTION_MARK, spellChoice.name),
                    checked = (rule.triggerSpellID ~= nil and rule.triggerSpellID == spellChoice.spellID)
                        or (safeStr(rule.triggerSpellName) == spellChoice.name),
                    action = function()
                        rule.triggerSpellID = spellChoice.spellID
                        rule.triggerSpellName = spellChoice.name
                        rule.triggerWindow = rule.triggerWindow or 8
                    end,
                }
            end
            return choices
        end, function() rebuildCustomRows() end)
    end

    local function showAddRuleCondition(anchor, rule)
        local picker = addon.RotationEditor and addon.RotationEditor.ShowPicker
        if not picker then return end
        local hasMana = Consumables.PlayerHasMana()
        picker(anchor, loc("rot_add_condition", "Adicionar condição"), function()
            local items = {}
            for _, axis in ipairs(RULE_AXES) do
                if not axis.manaOnly or hasMana then
                    local axisKey = axis.key
                    items[#items + 1] = { header = loc(axis.labelKey, axis.fallback) }
                    for _, opt in ipairs(axis.options) do
                        local val, lk, fb = opt[1], opt[2], opt[3]
                        local cur = type(rule.conditions) == "table" and tonumber(rule.conditions[axisKey]) or 0
                        items[#items + 1] = {
                            label = loc(lk, fb),
                            checked = (cur == val),
                            action = function()
                                rule.conditions = rule.conditions or {}
                                if tonumber(rule.conditions[axisKey]) == val then
                                    rule.conditions[axisKey] = nil
                                else
                                    rule.conditions[axisKey] = val
                                end
                            end,
                        }
                    end
                end
            end
            items[#items + 1] = { header = loc("cons_axis_spell_trigger", "7. Gatilho de habilidade") }
            items[#items + 1] = {
                label = loc("cons_choose_trigger_spell", "Escolher habilidade X..."),
                checked = (rule.triggerSpellID ~= nil or safeStr(rule.triggerSpellName) ~= nil),
                action = function()
                    if C_Timer and type(C_Timer.After) == "function" then
                        C_Timer.After(0, function() showTriggerSpellChoices(anchor, rule) end)
                    else
                        showTriggerSpellChoices(anchor, rule)
                    end
                end,
            }
            items[#items + 1] = { header = "------------------------" }
            items[#items + 1] = {
                label = loc("rot_clear_all", "Remover todas as condições"),
                checked = false,
                action = function()
                    rule.conditions = {}
                    rule.triggerSpellID = nil
                    rule.triggerSpellName = nil
                end,
            }
            return items
        end, function() rebuildCustomRows() end)
    end

    local function showRemoveRuleCondition(anchor, rule)
        local picker = addon.RotationEditor and addon.RotationEditor.ShowPicker
        if not picker then return end
        picker(anchor, loc("rot_remove_condition", "Remover condição"), function()
            local items = {}
            local any = false
            local conds = type(rule.conditions) == "table" and rule.conditions or {}
            for _, axis in ipairs(RULE_AXES) do
                local v = tonumber(conds[axis.key]) or 0
                if v ~= 0 then
                    local axisKey = axis.key
                    local optLabel = tostring(v)
                    for _, opt in ipairs(axis.options) do
                        if opt[1] == v then optLabel = loc(opt[2], opt[3]); break end
                    end
                    local axisName = loc(axis.labelKey, axis.fallback):gsub("^%d+%.%s*", "")
                    items[#items + 1] = {
                        label = axisName .. ": " .. optLabel,
                        action = function()
                            if type(rule.conditions) == "table" then rule.conditions[axisKey] = nil end
                        end,
                    }
                    any = true
                end
            end
            if rule.triggerSpellID or safeStr(rule.triggerSpellName) then
                local spName = safeStr(rule.triggerSpellName) or tostring(rule.triggerSpellID)
                items[#items + 1] = {
                    label = loc("cons_after_spell_prefix", "Após habilidade: ") .. spName,
                    action = function()
                        rule.triggerSpellID = nil
                        rule.triggerSpellName = nil
                    end,
                }
                any = true
            end
            if not any then
                items[#items + 1] = { header = loc("rot_none_active", "(nenhuma condição ativa)") }
            end
            return items
        end, function() rebuildCustomRows() end)
    end

    rebuildCustomRows = function()
        for _, r in ipairs(dynamicRows) do
            r:Hide()
            r:SetParent(nil)
        end
        dynamicRows = {}

        local ry = rulesStartY
        if #(cfg.customRules or {}) == 0 then
            local empty = parent:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
            empty:SetPoint("TOPLEFT", parent, "TOPLEFT", 8, ry)
            empty:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -8, ry)
            empty:SetJustifyH("LEFT")
            empty:SetWordWrap(true)
            empty:SetText(loc("cons_custom_empty",
                "Nenhuma regra criada. Clique em '+ Adicionar item / regra' para configurar poções de vida/mana, respiração aquática, bombas de engenharia ou itens após usar uma habilidade."))
            dynamicRows[1] = empty
            setContentHeight(-ry + 48)
            return
        end

        for idx, rule in ipairs(cfg.customRules) do
            local currentRule = rule
            local currentIdx = idx
            local row = CreateFrame("Frame", nil, parent)
            row:SetHeight(48)
            row:SetPoint("TOPLEFT", parent, "TOPLEFT", 4, ry)
            row:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -4, ry)
            local bg = row:CreateTexture(nil, "BACKGROUND")
            bg:SetTexture("Interface\\Buttons\\WHITE8X8")
            bg:SetVertexColor(0.08, 0.08, 0.08, 0.85)
            bg:SetAllPoints()

            local cb = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
            cb:SetSize(22, 22)
            cb:SetPoint("TOPLEFT", row, "TOPLEFT", 2, -2)
            cb:SetChecked(currentRule.enabled ~= false)
            cb:SetScript("OnClick", function(self)
                currentRule.enabled = (self:GetChecked() == true)
            end)

            local itemBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
            itemBtn:SetSize(166, 22)
            itemBtn:SetPoint("LEFT", cb, "RIGHT", 2, 0)
            local itemIcon = itemBtn:CreateTexture(nil, "ARTWORK")
            itemIcon:SetSize(16, 16)
            itemIcon:SetPoint("LEFT", itemBtn, "LEFT", 4, 0)
            local itemMeta = currentRule.itemID and inspectItem(tonumber(currentRule.itemID)) or nil
            itemIcon:SetTexture(itemMeta and itemMeta.texture or QUESTION_MARK)
            local itemText = itemBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            itemText:SetPoint("LEFT", itemIcon, "RIGHT", 4, 0)
            itemText:SetPoint("RIGHT", itemBtn, "RIGHT", -4, 0)
            itemText:SetJustifyH("LEFT")
            itemText:SetText(itemMeta and itemMeta.name or loc("equip_select_item", "Selecionar item"))
            itemBtn:SetScript("OnClick", function(self) showItemChoices(self, currentRule) end)

            local addCondBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
            addCondBtn:SetSize(24, 22)
            addCondBtn:SetPoint("LEFT", itemBtn, "RIGHT", 4, 0)
            addCondBtn:SetText("+")
            addCondBtn:SetScript("OnClick", function(self) showAddRuleCondition(self, currentRule) end)

            local remCondBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
            remCondBtn:SetSize(24, 22)
            remCondBtn:SetPoint("LEFT", addCondBtn, "RIGHT", 3, 0)
            remCondBtn:SetText("-")
            remCondBtn:SetEnabled(ruleHasAnyCondition(currentRule))
            remCondBtn:SetScript("OnClick", function(self) showRemoveRuleCondition(self, currentRule) end)

            local delBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
            delBtn:SetSize(24, 22)
            delBtn:SetPoint("LEFT", remCondBtn, "RIGHT", 4, 0)
            delBtn:SetText("X")
            delBtn:SetScript("OnClick", function()
                table.remove(cfg.customRules, currentIdx)
                if addon.RotationEditor and addon.RotationEditor.HidePicker then
                    addon.RotationEditor.HidePicker()
                end
                rebuildCustomRows()
            end)

            local summary = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
            summary:SetPoint("TOPLEFT", row, "TOPLEFT", 28, -26)
            summary:SetPoint("TOPRIGHT", row, "TOPRIGHT", -4, -26)
            summary:SetJustifyH("LEFT")
            summary:SetText(formatRuleSummary(currentRule))

            dynamicRows[#dynamicRows + 1] = row
            ry = ry - 52
        end
        setContentHeight(-ry + 16)
    end

    addRuleBtn:SetScript("OnClick", function()
        local id = cfg.nextRuleId or (#cfg.customRules + 1)
        cfg.nextRuleId = id + 1
        cfg.customRules[#cfg.customRules + 1] = {
            id = id,
            enabled = true,
            itemID = nil,
            conditions = {},
            triggerSpellID = nil,
            triggerSpellName = nil,
            triggerWindow = 8,
        }
        rebuildCustomRows()
    end)

    rebuildCustomRows()
end

if addon.Options and addon.Options.RegisterTab then
    addon.Options.RegisterTab("consumables", loc("opt_tab_consumables", "Food, Potions, Itens"), nil, buildConsumablesTab)
end
