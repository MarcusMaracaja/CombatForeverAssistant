local addonName, addon = ...

local module = {
    classTag = "SHAMAN",
    RotationPredicates = {},
    RotationSpecs = {},
    buffBeliefs = {},
}
local L = addon.L
local Compat = addon.Compat
local TREE_ORDER = { "ELE", "ENH", "REST" }
local EXTRA_KEYS = {
    lightning_shield = true,
    flametongue_weapon = true,
    windfury_weapon = true,
    strength_of_earth = true,
    mana_spring = true,
}
local MAELSTROM_AURAS = { [408498] = true, [408505] = true }
local talentCache
local lastTalentAttempt = 0
local combatStartedAt
local flameShockBelief

addon.modules.SHAMAN = module
module.addon = addon
module.Compat = Compat

local function isSecret(value)
    if type(_G.issecretvalue) ~= "function" then return false end
    local ok, secret = pcall(_G.issecretvalue, value)
    return ok and secret == true
end

local function numberValue(value)
    if type(value) ~= "number" or isSecret(value) or value ~= value
        or value == math.huge or value == -math.huge then
        return nil
    end
    return value
end

local function now()
    if type(GetTime) ~= "function" then return 0 end
    local ok, value = pcall(GetTime)
    return ok and numberValue(value) or 0
end

local function percentage(unit, valueFunc, maxFunc)
    if type(valueFunc) ~= "function" or type(maxFunc) ~= "function" then return 0 end
    local okValue, value = pcall(valueFunc, unit, 0)
    local okMax, maximum = pcall(maxFunc, unit, 0)
    value, maximum = okValue and numberValue(value) or nil, okMax and numberValue(maximum) or nil
    if not value or not maximum or maximum <= 0 then return 0 end
    return math.max(0, math.min(100, value / maximum * 100))
end

local function classifyTree(name)
    if type(name) ~= "string" or isSecret(name) then return nil end
    name = name:lower()
    if name:find("element", 1, true) or name:find("elementar", 1, true) then return "ELE" end
    if name:find("enhanc", 1, true) or name:find("aperfe", 1, true) then return "ENH" end
    if name:find("restor", 1, true) or name:find("restaur", 1, true) or name:find("heal", 1, true) then
        return "REST"
    end
    return nil
end

local function invalidateTalentCache()
    talentCache = nil
    lastTalentAttempt = 0
end

local function talentPoints()
    if talentCache then return talentCache end
    local timestamp = now()
    if timestamp - lastTalentAttempt < 2 then return nil end
    lastTalentAttempt = timestamp
    if not (C_ClassTalents and C_Traits and C_ClassTalents.GetActiveConfigID
        and C_Traits.GetConfigInfo and C_Traits.GetTreeNodes and C_Traits.GetNodeInfo) then
        return nil
    end

    local okConfig, configID = pcall(C_ClassTalents.GetActiveConfigID)
    if not okConfig or type(configID) ~= "number" or isSecret(configID) then return nil end
    local okInfo, configInfo = pcall(C_Traits.GetConfigInfo, configID)
    if not okInfo or type(configInfo) ~= "table" or type(configInfo.treeIDs) ~= "table" then return nil end

    local counts = {}
    for index, treeID in ipairs(configInfo.treeIDs) do
        local specKey
        if C_Traits.GetTreeInfo then
            local okTree, treeInfo = pcall(C_Traits.GetTreeInfo, configID, treeID)
            if okTree and type(treeInfo) == "table" then
                specKey = classifyTree(treeInfo.displayName or treeInfo.name)
            end
        end
        specKey = specKey or TREE_ORDER[index]
        if specKey then
            local okNodes, nodeIDs = pcall(C_Traits.GetTreeNodes, treeID)
            local total = 0
            if okNodes and type(nodeIDs) == "table" then
                for _, nodeID in ipairs(nodeIDs) do
                    local okNode, nodeInfo = pcall(C_Traits.GetNodeInfo, configID, nodeID)
                    if okNode and type(nodeInfo) == "table" then
                        local rank = numberValue(nodeInfo.currentRank)
                            or numberValue(nodeInfo.ranksPurchased)
                            or numberValue(nodeInfo.activeRank)
                        total = total + (rank or 0)
                    end
                end
            end
            counts[specKey] = (counts[specKey] or 0) + total
        end
    end
    if next(counts) then
        talentCache = counts
        return counts
    end
    return nil
end

function module:SetSpecOverride(specKey)
    if specKey == "auto" then
        addon.charDb.shamanSpec = nil
        return true
    end
    if specKey ~= "ELE" and specKey ~= "ENH" and specKey ~= "REST" then return false end
    addon.charDb.shamanSpec = specKey
    return true
end

function module:DetectSpec()
    local override = addon.charDb.shamanSpec
    if override == "ELE" or override == "ENH" or override == "REST" then
        return override, "override"
    end

    local counts = talentPoints()
    if counts then
        local bestKey, bestPoints, hasPoints = "ELE", 0, false
        for _, key in ipairs(TREE_ORDER) do
            local points = numberValue(counts[key]) or 0
            if points > bestPoints then
                bestKey, bestPoints = key, points
            end
            if points > 0 then hasPoints = true end
        end
        if hasPoints then
            return bestKey, string.format("C_Traits ELE=%d ENH=%d REST=%d",
                numberValue(counts.ELE) or 0, numberValue(counts.ENH) or 0,
                numberValue(counts.REST) or 0)
        end
    end

    if Compat.SpellKnown(17364) or Compat.SpellKnown(425336) or Compat.SpellKnown(16256) then
        return "ENH", "talent signature"
    end
    if Compat.SpellKnown(16166) then
        return "ELE", "talent signature"
    end
    if Compat.SpellKnown(16188) then
        return "REST", "talent signature"
    end
    return "ELE", "default"
end

function module:IsExtraSuggestionEnabled(key)
    if not EXTRA_KEYS[key] then return false end
    local settings = addon.charDb.shamanExtras
    return type(settings) ~= "table" or settings[key] ~= false
end

function module:SetExtraSuggestionEnabled(key, enabled)
    if not EXTRA_KEYS[key] or type(enabled) ~= "boolean" then return false end
    if type(addon.charDb.shamanExtras) ~= "table" then
        addon.charDb.shamanExtras = {}
    end
    local settings = addon.charDb.shamanExtras
    if enabled then
        settings[key] = nil
        if not next(settings) then addon.charDb.shamanExtras = nil end
    else
        settings[key] = false
    end
    return true
end

local function sameFamily(spellID, familyBase)
    if spellID == familyBase then return true end
    local families = Compat.FamilyOf
    return families and families[spellID] ~= nil and families[spellID] == families[familyBase]
end

local function spellName(spellID)
    local knownID = Compat.HighestKnownSpellID(spellID) or spellID
    return Compat.SpellName(knownID) or Compat.SpellName(spellID)
end

local function buffActive(spellID, beliefKey, requirePlayerSource, auraFamily)
    local status
    if auraFamily and addon.BuffLib and addon.BuffLib.Status then
        local ok, result = pcall(addon.BuffLib.Status, addon.BuffLib, "player", auraFamily)
        if ok and type(result) == "table" then
            status = result
            if status.present then return true end
        end
    end
    local name = spellName(spellID)
    local mine = requirePlayerSource ~= false
    if auraFamily then mine = false end
    if name and Compat.CheckBuff and Compat.CheckBuff(name, "player", mine) then
        return true
    end
    local belief = module.buffBeliefs[beliefKey]
    if status and status.readable then
        if type(belief) == "table" and type(belief.appliedAt) == "number"
            and now() - belief.appliedAt < 2 then
            return true
        end
        module.buffBeliefs[beliefKey] = nil
        return false
    end
    local expires = type(belief) == "table" and belief.expires or belief
    if type(belief) == "table" and expires == nil then return true end
    return expires ~= nil and now() < expires
end

local function normalizedName(name)
    if type(name) ~= "string" or isSecret(name) then return nil end
    return name:lower():gsub("%s*%b()%s*$", ""):gsub("^%s+", ""):gsub("%s+$", "")
end

local function totemActive(spellID)
    if type(GetTotemInfo) ~= "function" then return false end
    local names = {}
    local family = Compat.FamilyOf[spellID] or { spellID }
    for _, id in ipairs(family) do
        local name = spellName(id)
        local normalized = normalizedName(name)
        if normalized then names[normalized] = true end
    end
    if not next(names) then return false end
    for slot = 1, 4 do
        local ok, haveTotem, currentName = pcall(GetTotemInfo, slot)
        if ok and not isSecret(haveTotem) and (haveTotem == true or haveTotem == 1) then
            local current = normalizedName(currentName)
            if current then
                for wanted in pairs(names) do
                    if current == wanted or current:find(wanted, 1, true) then return true end
                end
            end
        end
    end
    return false
end

local function flameShockActive()
    local name = spellName(8050)
    if name and Compat.CheckDebuff and Compat.CheckDebuff(name, "target", true) then return true end
    local targetGUID
    if type(UnitGUID) == "function" then
        local ok, guid = pcall(UnitGUID, "target")
        if ok and type(guid) == "string" and not isSecret(guid) then targetGUID = guid end
    end
    return flameShockBelief ~= nil and targetGUID ~= nil
        and flameShockBelief.guid == targetGUID and now() < flameShockBelief.expires
end

local function clearcastingActive()
    local name = spellName(16246)
    return name ~= nil and Compat.CheckBuff and Compat.CheckBuff(name, "player", true) or false
end

local function lightningMasteryActive()
    return buffActive(16166, "lightning_mastery")
end

local function maelstromStacks()
    if not (C_UnitAuras and type(C_UnitAuras.GetAuraDataByIndex) == "function") then return 0 end
    for index = 1, 40 do
        local ok, aura = pcall(C_UnitAuras.GetAuraDataByIndex, "player", index, "HELPFUL")
        if not ok or not aura then break end
        local okID, spellID = pcall(function() return aura.spellId end)
        if okID and type(spellID) == "number" and not isSecret(spellID) and MAELSTROM_AURAS[spellID] then
            local okStacks, stacks = pcall(function() return aura.applications end)
            local count = okStacks and numberValue(stacks) or nil
            return count or 1
        end
    end
    return 0
end

local function isTargetInterruptible()
    local okExists, exists = pcall(UnitExists, "target")
    if not okExists or not exists then return false end
    if type(UnitCastingInfo) == "function" then
        local ok, name, _, _, _, _, _, _, notInterruptible = pcall(UnitCastingInfo, "target")
        if ok and type(name) == "string" and name ~= "" and not isSecret(name)
            and not isSecret(notInterruptible) then
            return notInterruptible ~= true
        end
    end
    if type(UnitChannelInfo) == "function" then
        local ok, name, _, _, _, _, _, notInterruptible = pcall(UnitChannelInfo, "target")
        if ok and type(name) == "string" and name ~= "" and not isSecret(name)
            and not isSecret(notInterruptible) then
            return notInterruptible ~= true
        end
    end
    return false
end

local function playerInCombat()
    if type(UnitAffectingCombat) == "function" then
        local ok, value = pcall(UnitAffectingCombat, "player")
        if ok and not isSecret(value) then return value == true end
    end
    if type(InCombatLockdown) == "function" then
        local ok, value = pcall(InCombatLockdown)
        return ok and not isSecret(value) and value == true or false
    end
    return false
end

local function playerMoving()
    if type(GetUnitSpeed) == "function" then
        local ok, speed = pcall(GetUnitSpeed, "player")
        speed = ok and numberValue(speed) or nil
        if speed then return speed > 0 end
    end
    if type(IsPlayerMoving) == "function" then
        local ok, moving = pcall(IsPlayerMoving)
        return ok and not isSecret(moving) and moving == true or false
    end
    return false
end

local function enemyCount(hasEnemy)
    local count = 0
    if C_NamePlate and type(C_NamePlate.EnumerateUnits) == "function" then
        local ok, units = pcall(function() return { C_NamePlate.EnumerateUnits() } end)
        if ok and type(units) == "table" then
            for _, unit in ipairs(units) do
                local okExists, exists = pcall(UnitExists, unit)
                local okAttack, canAttack = pcall(UnitCanAttack, "player", unit)
                if okExists and exists and okAttack and not isSecret(canAttack) and canAttack == true then
                    count = count + 1
                end
            end
        end
    end
    if hasEnemy and count < 1 then return 1 end
    return count
end

local function targetMeleeRange(distance)
    if distance ~= nil then return distance <= 5 end
    local attackSlot = addon:FindActionSlot(6603)
    local attackRange = addon:ActionSlotRange(attackSlot, "target")
    if attackRange ~= nil then return attackRange end
    local stormstrikeID = Compat.HighestKnownSpellID(17364) or 17364
    return addon:IsSpellInRangeEx(stormstrikeID, "target")
end

function module:BuildEnv(specKey)
    local hasEnemy = addon:Enemy("target") == true
    local distance = addon:TargetDistance("target")
    local melee = targetMeleeRange(distance)
    local inCombat = playerInCombat()
    local timeInCombat = inCombat and combatStartedAt and math.max(0, now() - combatStartedAt) or 0
    local enemies = enemyCount(hasEnemy)
    local manaPct = percentage("player", UnitPower, UnitPowerMax)
    local env = {
        spec = specKey,
        hasActiveEnemy = hasEnemy,
        inCombat = inCombat,
        isMelee = melee,
        targetDistance = distance,
        tooCloseForRanged = melee == true,
        targetInterruptible = hasEnemy and isTargetInterruptible() or false,
        isMoving = playerMoving(),
        isAoE = enemies >= 2,
        enemies = enemies,
        manaPct = manaPct,
        combatTime = timeInCombat,
    }
    env.searingTotemActive = totemActive(3599)
    env.magmaTotemActive = totemActive(8190)
    env.fireTotemActive = env.searingTotemActive or env.magmaTotemActive
    return env
end

local P = module.RotationPredicates
P.has_enemy = { label = "Attackable target", fn = function(env) return env.hasActiveEnemy end }
P.enemy_casting = { label = "Interruptible enemy cast", fn = function(env) return env.targetInterruptible end }
P.in_combat_enemy = {
    label = "In combat with an enemy",
    fn = function(env) return env.inCombat and env.hasActiveEnemy end,
}
P.melee_combat = {
    label = "Melee combat",
    fn = function(env) return env.inCombat and env.hasActiveEnemy and env.isMelee end,
}
P.not_melee = {
    label = "Target outside melee",
    fn = function(env) return env.hasActiveEnemy and env.isMelee == false end,
}
P.flame_shock_missing = {
    label = "Flame Shock missing and mana above 15%",
    fn = function(env)
        return env.hasActiveEnemy and env.manaPct > 15 and not flameShockActive()
    end,
}
P.earth_shock_moving = {
    label = "Moving and target is not casting",
    fn = function(env)
        return env.hasActiveEnemy and env.isMoving and not env.targetInterruptible
    end,
}
P.lightning_mastery = {
    label = "Lightning Mastery ready in combat",
    fn = function(env)
        return env.inCombat and env.hasActiveEnemy and not lightningMasteryActive()
    end,
}
P.chain_lightning_ok = {
    label = "AoE, enough mana, Clearcasting, or Lightning Mastery",
    fn = function(env)
        if not env.hasActiveEnemy then return false end
        if env.isAoE and env.manaPct > 15 then return true end
        return env.manaPct >= 50 or clearcastingActive() or lightningMasteryActive()
    end,
}
P.searing_totem_missing = {
    label = "Single target and no Searing Totem",
    fn = function(env)
        return env.hasActiveEnemy and not env.isAoE and not env.searingTotemActive
    end,
}
P.magma_totem_missing = {
    label = "AoE, mana above 15%, and no Magma Totem",
    fn = function(env)
        return env.hasActiveEnemy and env.isAoE and env.manaPct > 15 and not env.magmaTotemActive
    end,
}
P.fire_nova_ready = {
    label = "AoE with an active fire totem",
    fn = function(env)
        return env.hasActiveEnemy and env.isAoE and env.manaPct > 15 and env.fireTotemActive
    end,
}
P.maelstrom_five = {
    label = "Maelstrom Weapon at five stacks",
    fn = function(env) return env.hasActiveEnemy and maelstromStacks() >= 5 end,
}
P.rage_of_farseer_ready = {
    label = "Enhancement burst ready",
    fn = function(env)
        return env.inCombat and env.hasActiveEnemy and env.isMelee
            and not buffActive(425336, "rage_of_farseer")
    end,
}

local COMMON_NODES = {
    {
        id = "earth_shock_interrupt", spellID = 8042, name = "Earth Shock",
        color = "Interrupt", condition = "enemy_casting",
    },
}

local function casterNodes(includeMastery)
    local nodes = {}
    nodes[#nodes + 1] = {
        id = "earth_shock_moving", spellID = 8042, name = "Earth Shock",
        color = "Damage", condition = "earth_shock_moving",
    }
    if includeMastery then
        nodes[#nodes + 1] = {
            id = "lightning_mastery", spellID = 16166, name = "Lightning Mastery",
            color = "Damage", condition = "lightning_mastery",
            opts = { noEnemy = true, noRangeCheck = true },
        }
    end
    nodes[#nodes + 1] = {
        id = "magma_totem", spellID = 8190, name = "Magma Totem", color = "Damage",
        condition = "magma_totem_missing", opts = { noEnemy = true, noRangeCheck = true },
    }
    nodes[#nodes + 1] = {
        id = "searing_totem", spellID = 3599, name = "Searing Totem", color = "Damage",
        condition = "searing_totem_missing", opts = { noEnemy = true, noRangeCheck = true },
    }
    nodes[#nodes + 1] = {
        id = "flame_shock", spellID = 8050, name = "Flame Shock", color = "Damage",
        condition = "flame_shock_missing",
    }
    nodes[#nodes + 1] = {
        id = "chain_lightning", spellID = 421, name = "Chain Lightning",
        color = "Damage", condition = "chain_lightning_ok",
    }
    nodes[#nodes + 1] = {
        id = "fire_nova", spellID = 1535, name = "Fire Nova",
        color = "Damage", condition = "fire_nova_ready",
        opts = { noEnemy = true, noRangeCheck = true },
    }
    nodes[#nodes + 1] = {
        id = "lightning_bolt", spellID = 403, name = "Lightning Bolt",
        color = "Damage", condition = "has_enemy",
    }
    return nodes
end

local elementalNodes = casterNodes(true)
local restorationNodes = casterNodes(false)

module.RotationSpecs = {
    ELE = {
        title = "Elemental",
        nodes = addon:ConcatCommonNodes(COMMON_NODES, elementalNodes),
    },
    ENH = {
        title = "Enhancement",
        nodes = addon:ConcatCommonNodes(COMMON_NODES, {
            { id = "stormstrike", spellID = 17364, name = "Stormstrike",
                color = "Damage", condition = "melee_combat" },
            { id = "lightning_bolt_maelstrom", spellID = 403, name = "Lightning Bolt (Maelstrom)",
                color = "Damage", condition = "maelstrom_five" },
            { id = "rage_of_farseer", spellID = 425336, name = "Rage of the Farseer",
                color = "Damage", condition = "rage_of_farseer_ready",
                opts = { noEnemy = true, noRangeCheck = true } },
            { id = "flame_shock", spellID = 8050, name = "Flame Shock",
                color = "Damage", condition = "flame_shock_missing" },
            { id = "chain_lightning", spellID = 421, name = "Chain Lightning",
                color = "Damage", condition = "chain_lightning_ok" },
            { id = "lightning_bolt_ranged", spellID = 403, name = "Lightning Bolt",
                color = "Damage", condition = "not_melee" },
        }),
    },
    REST = {
        title = "Restoration (caster DPS fallback)",
        nodes = addon:ConcatCommonNodes(COMMON_NODES, restorationNodes),
    },
}

function module:TryFlash(spellID, color, condition, nodeName, env, opts)
    if self.TickFlashUsed then return false end
    opts = opts or {}
    local knownID = Compat.HighestKnownSpellID(spellID) or spellID
    local name = Compat.SpellName(knownID) or Compat.SpellName(spellID)
    if not name then return false end
    local details = {}
    local castable = addon:CheckIfSpellCastable({
        SpellID = knownID,
        SpellName = name,
        EnemyTargetNeeded = opts.noEnemy ~= true,
        Unit = opts.unit or (opts.noEnemy and "player" or "target"),
        NoRangeCheck = opts.noRangeCheck == true,
        Debug = details,
    })
    if not castable then
        if addon.debugMode then
            addon:DebugPrint("Shaman", tostring(nodeName or spellID), "rejected:",
                tostring(details.reason))
        end
        return false
    end
    self.PendingSuggestion = { spellID = knownID, color = color or "Damage" }
    self.TickFlashUsed = true
    return true
end

local function canSuggestBuff(spellID)
    local knownID = Compat.HighestKnownSpellID(spellID) or spellID
    local name = Compat.SpellName(knownID) or Compat.SpellName(spellID)
    if not name then return nil end
    if addon:CheckIfSpellCastable({
        SpellID = knownID,
        SpellName = name,
        EnemyTargetNeeded = false,
        Unit = "player",
        NoRangeCheck = true,
    }) then
        return { spellID = knownID, color = "Utility" }
    end
    return nil
end

local function manaSpringNeeded(env)
    return not env.inCombat or env.manaPct < 50 or env.combatTime >= 60
end

local function nextExtraSuggestion(env, specKey)
    if module:IsExtraSuggestionEnabled("lightning_shield")
        and not buffActive(324, "lightning_shield", true, "LightningShield") then
        local suggestion = canSuggestBuff(324)
        if suggestion then return suggestion end
    end

    local weaponKey, weaponID
    if specKey == "ENH" then
        weaponKey, weaponID = "windfury_weapon", 8232
    else
        weaponKey, weaponID = "flametongue_weapon", 8024
    end
    if module:IsExtraSuggestionEnabled(weaponKey) and not buffActive(weaponID, weaponKey) then
        local suggestion = canSuggestBuff(weaponID)
        if suggestion then return suggestion end
    end

    if module:IsExtraSuggestionEnabled("strength_of_earth")
        and not buffActive(8075, "strength_of_earth", false, "StrengthOfEarthAura")
        and not totemActive(8075) then
        local suggestion = canSuggestBuff(8075)
        if suggestion then return suggestion end
    end

    if manaSpringNeeded(env) and module:IsExtraSuggestionEnabled("mana_spring")
        and not buffActive(5675, "mana_spring", false, "ManaSpringAura")
        and not totemActive(5675) then
        local suggestion = canSuggestBuff(5675)
        if suggestion then return suggestion end
    end
    return nil
end

local function recordSuccessfulCast(spellID)
    local timestamp = now()
    local buffs = {
        { 324, "lightning_shield" },
        { 8024, "flametongue_weapon", 300 },
        { 8232, "windfury_weapon", 300 },
        { 16166, "lightning_mastery", 15 },
        { 425336, "rage_of_farseer", 25 },
    }
    for _, info in ipairs(buffs) do
        if sameFamily(spellID, info[1]) then
            module.buffBeliefs[info[2]] = {
                expires = info[3] and timestamp + info[3] or nil,
                appliedAt = timestamp,
            }
        end
    end
    if sameFamily(spellID, 8050) then
        local ok, guid = pcall(UnitGUID, "target")
        if ok and type(guid) == "string" and not isSecret(guid) then
            flameShockBelief = { guid = guid, expires = timestamp + 12 }
        end
    end
end

local tracker = CreateFrame("Frame", nil, UIParent)
tracker:RegisterEvent("PLAYER_ENTERING_WORLD")
tracker:RegisterEvent("SPELLS_CHANGED")
tracker:RegisterEvent("PLAYER_REGEN_DISABLED")
tracker:RegisterEvent("PLAYER_REGEN_ENABLED")
tracker:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
pcall(tracker.RegisterEvent, tracker, "TRAIT_CONFIG_UPDATED")
tracker:SetScript("OnEvent", function(_, event, ...)
    if event == "PLAYER_ENTERING_WORLD" then
        module.buffBeliefs = {}
        flameShockBelief = nil
        combatStartedAt = nil
        invalidateTalentCache()
    elseif event == "SPELLS_CHANGED" or event == "TRAIT_CONFIG_UPDATED" then
        invalidateTalentCache()
    elseif event == "PLAYER_REGEN_DISABLED" then
        combatStartedAt = now()
    elseif event == "PLAYER_REGEN_ENABLED" then
        combatStartedAt = nil
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        local unit, _, spellID = ...
        spellID = numberValue(spellID)
        if unit == "player" and spellID then recordSuccessfulCast(spellID) end
    end
end)

function module:GetSuggestion()
    if addon.db.shamanEnabled == false then return nil end
    local _, playerClass = UnitClass("player")
    if playerClass ~= "SHAMAN" then return nil end
    self.PendingSuggestion = nil
    self.TickFlashUsed = nil
    if type(IsMounted) == "function" and IsMounted() then return nil end

    local specKey = self:DetectSpec()
    local env = self:BuildEnv(specKey)
    addon:RunDeclaredRotation(self, specKey, env)

    local buffSuggestion = nextExtraSuggestion(env, specKey)
    if self.PendingSuggestion then
        if buffSuggestion then
            buffSuggestion.additional = { self.PendingSuggestion }
            return buffSuggestion
        end
        return self.PendingSuggestion
    end
    return buffSuggestion
end

function module:GetStatus()
    local specKey, source = self:DetectSpec()
    local title = self.RotationSpecs[specKey] and self.RotationSpecs[specKey].title or specKey
    return string.format("Shaman - %s (%s)", tostring(title), tostring(source))
end

function module:DebugRotation()
    local specKey, source = self:DetectSpec()
    local env = self:BuildEnv(specKey)
    addon:DebugPrint("Shaman spec=", specKey, "source=", source,
        "enemy=", env.hasActiveEnemy, "combat=", env.inCombat, "melee=", env.isMelee,
        "mana=", env.manaPct, "aoe=", env.isAoE, "maelstrom=", maelstromStacks())
end

addon:RegisterModule("SHAMAN", module)
