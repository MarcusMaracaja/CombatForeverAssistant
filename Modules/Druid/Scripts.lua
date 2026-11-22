local _, addon = ...
local Compat = addon.Compat

local module = {
    classTag = "DRUID",
    RotationPredicates = {},
    RotationSpecs = {},
    buffBeliefs = {},
    targetBeliefs = {},
}

addon.modules.DRUID = module
module.addon = addon
module.Compat = Compat
module.db = addon.db
module.charDb = addon.charDb
module.Options = addon.Options

local SPEC_ORDER = { "BAL", "FER", "REST" }
local TREE_ORDER = { "BAL", "FER", "REST" }
local FERAL_FORMS = { CAT = true, BEAR = true }
local EXTRA_KEYS = { mark = true, thorns = true }

local SPELL_FAMILIES = {
    { 1126, 5232, 6756, 5234, 8907, 9884, 9885, 26990, 48469 },
    { 21849, 21850, 26991, 48470 },
    { 467, 782, 1075, 8914, 9756, 9910, 26992 },
    { 770, 778, 9749, 9907, 26993 },
    { 5176, 5177, 5178, 5179, 5180, 6780, 8905, 9912, 26984, 48459, 48461 },
    { 2912, 8949, 8950, 8951, 9875, 9876, 25298, 26986, 48464, 48465 },
    { 8921, 8924, 8925, 8926, 8927, 8928, 8929, 9833, 9834, 9835, 26987, 26988, 48462, 48463 },
    { 5570, 24974, 24975, 24976, 24977, 48468 },
    { 5221, 6800, 8992, 9829, 9830, 27001, 48572, 48573 },
    { 1082, 3029, 5201, 9849, 9850, 27000, 48570 },
    { 1822, 1823, 1824, 9904, 27003, 48574, 59881 },
    { 1079, 9492, 9493, 9752, 9894, 9896, 27008, 49799, 49800 },
    { 22568, 22827, 22828, 22829, 31018, 48577 },
    { 33876, 33982, 33983, 48565 },
    { 33878, 33986, 33987, 48564 },
    { 16857, 17390, 17391, 17392, 27011, 48475 },
    { 6807, 6808, 6809, 8972, 9745, 9880, 9881, 26996, 48480 },
    { 779, 780, 769, 9754, 9908, 48562 },
    { 99, 1735, 9490, 9747, 9898, 26998 },
    { 8936, 8938, 8939, 8940, 8941, 9750, 9856, 9857, 9858, 26980, 48442, 48443 },
    { 774, 1058, 1430, 2090, 2091, 3627, 8910, 9839, 9840, 9841, 25299, 26981, 48440, 48441 },
    { 5185, 5186, 5187, 5188, 5189, 6778, 8903, 9758, 9888, 9889, 25297, 26978, 26979, 48377, 48378 },
    { 33763, 48450, 48451 },
    { 50464, 50465, 50466, 50467, 50468, 50469 },
    { 740, 8918, 9862, 9863, 26983, 48446, 48447 },
    { 339, 1062, 5195, 5196, 9852, 9853, 26989 },
    { 5217, 6793, 9845, 9846 },
    { 5487, 9634 },
    { 33745, 48568, 48569 },
    { 33891, 65139 },
}

local familyBySpell = {}
for _, family in ipairs(SPELL_FAMILIES) do
    for _, spellID in ipairs(family) do familyBySpell[spellID] = family end
end

local function isSecret(value)
    if type(_G.issecretvalue) ~= "function" then return false end
    local ok, secret = pcall(_G.issecretvalue, value)
    return ok and secret == true
end

local function safeNumber(value)
    if type(value) ~= "number" or isSecret(value) or value ~= value
        or value == math.huge or value == -math.huge then
        return nil
    end
    return value
end

local function readNumber(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, value = pcall(fn, ...)
    return ok and safeNumber(value) or nil
end

local function now()
    return readNumber(GetTime) or 0
end

local function resolveSpellID(spellID)
    if type(spellID) ~= "number" then return nil end
    local family = familyBySpell[spellID]
    if family then
        for index = #family, 1, -1 do
            if Compat.SpellKnown(family[index]) then return family[index] end
        end
        return nil
    end
    local knownID = Compat.HighestKnownSpellID(spellID)
    if knownID and Compat.SpellKnown(knownID) then return knownID end
    return nil
end

local function spellName(spellID)
    local id = resolveSpellID(spellID) or spellID
    local name = Compat.SpellInfoByID(id)
    if type(name) == "string" and name ~= "" and not isSecret(name) then return name end
    return nil
end

module.SpellName = spellName
module.CheckCastable = function(info)
    return addon:CheckIfSpellCastable(info)
end

function module:Suggest(spellID, color)
    if self.TickFlashUsed then return false end
    self.PendingSuggestion = { spellID = spellID, color = color or "Utility" }
    self.TickFlashUsed = true
    return true
end

function module:TryFlash(spellID, color, condition, name, env, opts)
    if self.TickFlashUsed then return false end
    opts = opts or {}
    local knownID = resolveSpellID(spellID)
    if not knownID then
        if addon.debugMode then addon:DebugPrint("Druid", tostring(name or spellID), "spell desconhecida") end
        return false
    end
    local localizedName = spellName(knownID)
    if not localizedName then
        if addon.debugMode then addon:DebugPrint("Druid", tostring(name or spellID), "nome da spell indisponível") end
        return false
    end
    if type(condition) == "function" then
        local ok, passed = pcall(condition, env)
        if not ok or not passed then return false end
    end

    local unit = opts.unit
    if opts.unitKey and type(env) == "table" then unit = env[opts.unitKey] end
    local details = {}
    local castable = self.CheckCastable({
        SpellID = knownID,
        SpellName = localizedName,
        EnemyTargetNeeded = opts.noEnemy ~= true,
        Unit = unit or (opts.noEnemy and "player" or "target"),
        NoRangeCheck = opts.noRangeCheck == true,
        NotIfActive = opts.notIfActive == true,
        Debug = details,
    })
    if not castable then
        if addon.debugMode then
            addon:DebugPrint("Druid", tostring(name or spellID), "recusada:", tostring(details.reason))
        end
        return false
    end
    return self:Suggest(knownID, color or "Damage")
end

local function talentTreePoints()
    if module.talentCache then return module.talentCache end
    if now() - (module.lastTalentAttempt or 0) < 2 then return nil end
    module.lastTalentAttempt = now()
    if not (C_ClassTalents and C_Traits and C_ClassTalents.GetActiveConfigID
        and C_Traits.GetConfigInfo and C_Traits.GetTreeNodes and C_Traits.GetNodeInfo) then
        return nil
    end

    local okConfig, configID = pcall(C_ClassTalents.GetActiveConfigID)
    if not okConfig or type(configID) ~= "number" or isSecret(configID) then return nil end
    local okInfo, config = pcall(C_Traits.GetConfigInfo, configID)
    if not okInfo or type(config) ~= "table" or type(config.treeIDs) ~= "table" then return nil end

    local counts = {}
    for index, treeID in ipairs(config.treeIDs) do
        local specKey
        if C_Traits.GetTreeInfo then
            local okTree, treeInfo = pcall(C_Traits.GetTreeInfo, configID, treeID)
            local label = okTree and type(treeInfo) == "table"
                and (treeInfo.displayName or treeInfo.name) or nil
            if type(label) == "string" and not isSecret(label) then
                label = label:lower()
                if label:find("balance", 1, true) or label:find("equil", 1, true) then
                    specKey = "BAL"
                elseif label:find("feral", 1, true) then
                    specKey = "FER"
                elseif label:find("restor", 1, true) or label:find("restaur", 1, true) then
                    specKey = "REST"
                end
            end
        end
        specKey = specKey or TREE_ORDER[index]
        if specKey then
            local okNodes, nodeIDs = pcall(C_Traits.GetTreeNodes, treeID)
            local points = 0
            if okNodes and type(nodeIDs) == "table" then
                for _, nodeID in ipairs(nodeIDs) do
                    local okNode, nodeInfo = pcall(C_Traits.GetNodeInfo, configID, nodeID)
                    if okNode and type(nodeInfo) == "table" then
                        points = points + (safeNumber(nodeInfo.currentRank)
                            or safeNumber(nodeInfo.ranksPurchased)
                            or safeNumber(nodeInfo.activeRank) or 0)
                    end
                end
            end
            counts[specKey] = (counts[specKey] or 0) + points
        end
    end
    if next(counts) then
        module.talentCache = counts
        return counts
    end
    return nil
end

local TREE_ORDER_DRUID = { "BAL", "FER", "REST" }

-- Conta pontos de talento por árvore, igual ao método do Hunter.
-- Itera treeIDs do C_Traits e soma os ranks comprados de cada nó.
local function talentTreePointsByOrdinal()
    if not (C_ClassTalents and C_Traits) then return false end
    local okCfg, cfg = pcall(C_ClassTalents.GetActiveConfigID)
    if not okCfg or not cfg then return false end
    local okInfo, info = pcall(C_Traits.GetConfigInfo, cfg)
    if not okInfo or type(info) ~= "table" or type(info.treeIDs) ~= "table" then return false end
    local counts = {}
    for idx, treeID in ipairs(info.treeIDs) do
        local specKey = TREE_ORDER_DRUID[idx]
        if specKey then
            local okN, nodes = pcall(C_Traits.GetTreeNodes, treeID)
            local total = 0
            if type(nodes) == "table" then
                for _, nodeID in ipairs(nodes) do
                    local okNI, ni = pcall(C_Traits.GetNodeInfo, cfg, nodeID)
                    if okNI and type(ni) == "table" then
                        total = total + (safeNumber(ni.currentRank)
                            or safeNumber(ni.ranksPurchased)
                            or safeNumber(ni.activeRank) or 0)
                    end
                end
            end
            counts[specKey] = total
        end
    end
    return counts
end

local function detectedTalentSpec()
    local override = addon.charDb.druidSpec
    if override == "BAL" or override == "FER" or override == "REST" then
        return override, "override"
    end

    local counts = talentTreePointsByOrdinal()
    if counts then
        local selected, best, hasPoints = "BAL", 0, false
        for _, specKey in ipairs(TREE_ORDER_DRUID) do
            local points = counts[specKey] or 0
            if points > best then selected, best = specKey, points end
            if points > 0 then hasPoints = true end
        end
        if hasPoints then
            return selected, string.format("C_Traits BAL=%d FER=%d REST=%d",
                counts.BAL or 0, counts.FER or 0, counts.REST or 0)
        end
    end

    -- Fallback por signature spells
    if Compat.SpellKnown(24858) then return "BAL", "talent signature" end
    if Compat.SpellKnown(18562) or Compat.SpellKnown(33891) or Compat.SpellKnown(65139) then
        return "REST", "talent signature"
    end
    if Compat.SpellKnown(33876) or Compat.SpellKnown(33878)
        or Compat.SpellKnown(16979) or Compat.SpellKnown(33745) then
        return "FER", "talent signature"
    end
    return "BAL", "default"
end

local function activeForm()
    local formIDs = {
        [768] = "CAT",
        [5487] = "BEAR",
        [9634] = "BEAR",
        [24858] = "MOONKIN",
        [33891] = "TREE",
        [65139] = "TREE",
    }

    if type(GetShapeshiftFormID) == "function" then
        local formID = readNumber(GetShapeshiftFormID)
        if formID ~= nil then
            if formID == 0 then return "HUMANOID" end
            return formIDs[formID] or "OTHER"
        end
    end

    if type(GetShapeshiftForm) == "function" then
        local index = readNumber(GetShapeshiftForm)
        if index ~= nil then
            if index == 0 then return "HUMANOID" end
            if type(GetShapeshiftFormInfo) == "function" then
                local ok, icon, isActive, _, spellID = pcall(GetShapeshiftFormInfo, index)
                if ok then
                    if type(icon) == "table" then spellID = icon.spellID or icon.spellId end
                    spellID = safeNumber(spellID)
                    if spellID and formIDs[spellID] then return formIDs[spellID] end
                    if isActive == false then return "HUMANOID" end
                end
            end
            return "OTHER"
        end
    end

    local formAuras = {
        { 768, "CAT" }, { 5487, "BEAR" }, { 9634, "BEAR" },
        { 24858, "MOONKIN" }, { 33891, "TREE" }, { 65139, "TREE" },
    }
    for _, entry in ipairs(formAuras) do
        local name = spellName(entry[1])
        if name and Compat.CheckBuff(name, "player") then return entry[2] end
    end

    local powerType = readNumber(UnitPowerType, "player")
    if powerType == 3 then return "CAT" end
    if powerType == 1 then return "BEAR" end
    return powerType == 0 and "HUMANOID" or "UNKNOWN"
end

function module:SetSpecOverride(specKey)
    if specKey == "auto" then
        addon.charDb.druidSpec = nil
        module.talentCache = nil
        return true
    end
    if specKey ~= "BAL" and specKey ~= "FER" and specKey ~= "REST" then return false end
    addon.charDb.druidSpec = specKey
    return true
end

function module:SetFeralFormPreference(form)
    if not FERAL_FORMS[form] then return false end
    addon.charDb.druidFeralForm = form
    return true
end

function module:IsExtraSuggestionEnabled(key)
    if not EXTRA_KEYS[key] then return false end
    local settings = addon.charDb.druidExtras
    return type(settings) ~= "table" or settings[key] ~= false
end

function module:SetExtraSuggestionEnabled(key, enabled)
    if not EXTRA_KEYS[key] or type(enabled) ~= "boolean" then return false end
    if type(addon.charDb.druidExtras) ~= "table" then addon.charDb.druidExtras = {} end
    local settings = addon.charDb.druidExtras
    if enabled then
        settings[key] = nil
        if not next(settings) then addon.charDb.druidExtras = nil end
    else
        settings[key] = false
    end
    return true
end

function module:DetectSpec()
    local talentSpec, source = detectedTalentSpec()
    if talentSpec ~= "FER" then return talentSpec, source end
    local form = activeForm()
    if form == "CAT" or form == "BEAR" then return form, source .. " / form" end
    local preference = addon.charDb.druidFeralForm
    if preference ~= "CAT" and preference ~= "BEAR" then preference = "CAT" end
    return preference, source .. " / preference"
end

local function unitExists(unit)
    if type(UnitExists) ~= "function" then return false end
    local ok, exists = pcall(UnitExists, unit)
    return ok and not isSecret(exists) and exists == true
end

local function unitsAreSame(unit, other)
    if type(UnitIsUnit) ~= "function" then return false end
    local ok, same = pcall(UnitIsUnit, unit, other)
    return ok and not isSecret(same) and same == true
end

local function unitHealthPercent(unit)
    local health = readNumber(UnitHealth, unit)
    local maximum = readNumber(UnitHealthMax, unit)
    if not health or not maximum or maximum <= 0 then return nil end
    return math.max(0, math.min(100, health / maximum * 100))
end

local function powerPercent(unit, powerType)
    local current = readNumber(UnitPower, unit, powerType)
    local maximum = readNumber(UnitPowerMax, unit, powerType)
    if not current or not maximum or maximum <= 0 then return nil end
    return math.max(0, math.min(100, current / maximum * 100))
end

local function inCombat(unit)
    if type(UnitAffectingCombat) == "function" then
        local ok, value = pcall(UnitAffectingCombat, unit or "player")
        if ok and not isSecret(value) then return value == true end
    end
    if type(InCombatLockdown) == "function" then
        local ok, value = pcall(InCombatLockdown)
        return ok and not isSecret(value) and value == true or false
    end
    return false
end

local function targetGUID()
    if type(UnitGUID) ~= "function" then return nil end
    local ok, guid = pcall(UnitGUID, "target")
    if ok and type(guid) == "string" and not isSecret(guid) then return guid end
    return nil
end

local function sameSpellFamily(spellID, baseID)
    if spellID == baseID then return true end
    local family = familyBySpell[baseID]
    return family ~= nil and familyBySpell[spellID] == family
end

local DOT_INFO = {
    [1079] = { key = "rip", duration = 16 },
    [1822] = { key = "rake", duration = 9 },
    [5570] = { key = "insect_swarm", duration = 12 },
    [8921] = { key = "moonfire", duration = 12 },
    [99] = { key = "demoralizing_roar", duration = 30 },
    [16857] = { key = "faerie_fire_feral", duration = 40 },
    [770] = { key = "faerie_fire", duration = 40 },
    [33876] = { key = "mangle_cat", duration = 12 },
    [33878] = { key = "mangle_bear", duration = 12 },
    [33745] = { key = "lacerate", duration = 15, stacks = true },
}

local function beliefForTarget(key)
    local belief = module.targetBeliefs[key]
    local guid = targetGUID()
    if type(belief) == "table" and belief.guid == guid and now() < belief.expires then
        return belief
    end
    if belief then module.targetBeliefs[key] = nil end
    return nil
end

local function targetDebuffActive(spellID, key, requirePlayer)
    local name = spellName(spellID)
    if name and Compat.CheckDebuff(name, "target", requirePlayer) then return true end
    return beliefForTarget(key) ~= nil
end

local function targetDebuffStacks(spellID, key)
    if C_UnitAuras and type(C_UnitAuras.GetAuraDataByIndex) == "function" then
        local family = familyBySpell[spellID]
        local expectedName = spellName(spellID)
        for index = 1, 40 do
            local ok, aura = pcall(C_UnitAuras.GetAuraDataByIndex, "target", index, "HARMFUL")
            if not ok or not aura or type(aura) ~= "table" then break end
            local okID, auraID = pcall(function() return aura.spellId or aura.spellID end)
            auraID = okID and safeNumber(auraID) or nil
            local okName, auraName = pcall(function() return aura.name end)
            if okName and type(auraName) == "string" and not isSecret(auraName)
                and (auraName == expectedName
                    or (auraID and (auraID == spellID
                        or (family and familyBySpell[auraID] == family)))) then
                local okStacks, stacks = pcall(function() return aura.applications end)
                local count = okStacks and safeNumber(stacks) or nil
                if count ~= nil then return math.max(1, count) end
                local belief = beliefForTarget(key)
                return belief and belief.stacks or 1
            end
        end
    end
    local belief = beliefForTarget(key)
    return belief and belief.stacks or 0
end

local function buffActive(spellID, key, familyName)
    local status
    if familyName and addon.BuffLib and addon.BuffLib.Status then
        local ok, result = pcall(addon.BuffLib.Status, addon.BuffLib, "player", familyName)
        if ok and type(result) == "table" then
            status = result
            if status.present then return true end
        end
    end

    local names = {}
    local family = familyBySpell[spellID] or { spellID }
    for _, id in ipairs(family) do
        local name = Compat.SpellInfoByID(id)
        if type(name) == "string" and not isSecret(name) then names[#names + 1] = name end
    end
    if #names > 0 and Compat.CheckBuff(names, "player") then return true end

    local belief = module.buffBeliefs[key]
    if status and status.readable then
        module.buffBeliefs[key] = nil
        return false
    end
    return type(belief) == "table" and now() < belief.expires or false
end

local function playerIsFriendlyTarget()
    if not unitExists("target") or type(UnitIsFriend) ~= "function" then return false end
    local ok, friendly = pcall(UnitIsFriend, "player", "target")
    return ok and not isSecret(friendly) and friendly == true
end

local function isCasting(unit)
    if type(UnitCastingInfo) == "function" then
        local ok, name = pcall(UnitCastingInfo, unit)
        if ok and type(name) == "string" and name ~= "" and not isSecret(name) then return true end
    end
    if type(UnitChannelInfo) == "function" then
        local ok, name = pcall(UnitChannelInfo, unit)
        if ok and type(name) == "string" and name ~= "" and not isSecret(name) then return true end
    end
    return false
end

local function enemyCount(hasEnemy)
    local count = 0
    if C_NamePlate and type(C_NamePlate.EnumerateUnits) == "function" then
        local ok, units = pcall(function() return { C_NamePlate.EnumerateUnits() } end)
        if ok and type(units) == "table" then
            for _, unit in ipairs(units) do
                if unitExists(unit) and addon:Enemy(unit) then count = count + 1 end
            end
        end
    end
    if hasEnemy and count < 1 then return 1 end
    return count
end

local function chooseHealTarget()
    local selfHealth = unitHealthPercent("player")
    local targetHealth
    if playerIsFriendlyTarget() then targetHealth = unitHealthPercent("target") end
    if targetHealth and targetHealth < 95 and (not selfHealth or targetHealth < selfHealth) then
        return "target", targetHealth
    end
    if selfHealth and selfHealth < 95 then return "player", selfHealth end
    if targetHealth and targetHealth < 95 then return "target", targetHealth end
    return "player", selfHealth
end

local function isTargetInterruptible()
    if not unitExists("target") then return false end
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

function module:BuildEnv(specKey)
    local hasEnemy = addon:Enemy("target") == true
    local form = activeForm()
    local healUnit, healHealth = chooseHealTarget()
    local targetHealth = unitHealthPercent("target")
    local enemies = enemyCount(hasEnemy)
    local inInstance, instanceType = false, nil
    if type(IsInInstance) == "function" then
        local ok, inside, kind = pcall(IsInInstance)
        if ok and not isSecret(inside) and not isSecret(kind) then
            inInstance, instanceType = inside == true, kind
        end
    end
    local playerMana = powerPercent("player", 0)
    local rage = readNumber(UnitPower, "player", 1)
    local energy = readNumber(UnitPower, "player", 3)
    local combo = readNumber(GetComboPoints, "player", "target")
    if combo == nil then combo = readNumber(GetComboPoints, "player") end
    local targetLevel = readNumber(UnitLevel, "target")
    local classification
    if type(UnitClassification) == "function" then
        local ok, value = pcall(UnitClassification, "target")
        if ok and type(value) == "string" and not isSecret(value) then classification = value end
    end

    local env = {
        spec = specKey,
        talentSpec = detectedTalentSpec(),
        form = form,
        myHealth = unitHealthPercent("player"),
        hasActiveEnemy = hasEnemy,
        inCombat = inCombat("player"),
        isPvP = inInstance and (instanceType == "pvp" or instanceType == "arena"),
        isBoss = classification == "worldboss" or targetLevel == -1,
        targetHealth = targetHealth,
        targetDistance = addon:TargetDistance("target"),
        isMelee = addon:IsInMeleeRange("target"),
        enemyCount = enemies,
        isAoE = enemies >= 3 and classification ~= "worldboss",
        manaPct = playerMana,
        rage = rage,
        energy = energy,
        comboPoints = combo,
        healUnit = healUnit,
        healHealth = healHealth,
        emergencyHealing = specKey == "REST" and healHealth ~= nil and healHealth <= 35,
        targetInterruptible = hasEnemy and isTargetInterruptible() or false,
        targetDebuffRake = hasEnemy and targetDebuffActive(1822, "rake", true) or false,
        targetDebuffRip = hasEnemy and targetDebuffActive(1079, "rip", true) or false,
        targetDebuffMoonfire = hasEnemy and targetDebuffActive(8921, "moonfire", true) or false,
        targetDebuffInsectSwarm = hasEnemy and targetDebuffActive(5570, "insect_swarm", true) or false,
        targetDebuffFaerieFire = hasEnemy and targetDebuffActive(770, "faerie_fire", false) or false,
        targetDebuffFaerieFireFeral = hasEnemy
            and targetDebuffActive(16857, "faerie_fire_feral", false) or false,
        targetDebuffMangleCat = hasEnemy and targetDebuffActive(33876, "mangle_cat", false) or false,
        targetDebuffMangleBear = hasEnemy and targetDebuffActive(33878, "mangle_bear", false) or false,
        targetDebuffDemoralizingRoar = hasEnemy
            and targetDebuffActive(99, "demoralizing_roar", false) or false,
        lacerateStacks = hasEnemy and targetDebuffStacks(33745, "lacerate") or 0,
        tigerFuryActive = buffActive(5217, "tiger_fury", "TigersFury"),
        savageRoarActive = buffActive(52610, "savage_roar"),
        barkskinActive = buffActive(22812, "barkskin", "Barkskin"),
        lunarEclipse = buffActive(48518, "lunar_eclipse"),
        solarEclipse = buffActive(48517, "solar_eclipse"),
        rejuvActive = buffActive(774, "rejuvenation", "Rejuvenation"),
        regrowthActive = buffActive(8936, "regrowth", "Regrowth"),
        hasHoT = false,
        friendlyTarget = playerIsFriendlyTarget(),
        targetTargetIsPlayer = unitExists("targettarget")
            and unitsAreSame("targettarget", "player") or false,
        hasTargetTarget = unitExists("targettarget"),
        hasMana = (readNumber(UnitPowerMax, "player", 0) or 0) > 0,
    }
    env.restoration_heal = specKey == "REST" and healHealth ~= nil and healHealth < 95
    env.hasHoT = (healUnit and (Compat.CheckBuff(spellName(774), healUnit)
        or Compat.CheckBuff(spellName(8936), healUnit))) or false
    return env
end

local P = module.RotationPredicates
P.has_enemy = { label = "Attackable target", fn = function(env) return env.hasActiveEnemy end }
P.in_combat_enemy = {
    label = "In combat with an enemy",
    fn = function(env) return env.inCombat and env.hasActiveEnemy end,
}
P.needs_balance_form = {
    label = "Balance form missing",
    fn = function(env) return env.hasActiveEnemy and env.form ~= "MOONKIN" end,
}
P.needs_cat_form = {
    label = "Cat Form missing",
    fn = function(env) return env.hasActiveEnemy and env.form ~= "CAT" end,
}
P.needs_bear_form = {
    label = "Bear Form missing",
    fn = function(env) return env.hasActiveEnemy and env.form ~= "BEAR" end,
}
P.needs_tree_form = {
    label = "Tree of Life missing",
    fn = function(env) return env.emergencyHealing and env.form ~= "TREE" end,
}
P.balance_enemy = { label = "Balance combat target", fn = function(env) return env.spec == "BAL" and env.hasActiveEnemy end }
P.feral_cat_enemy = { label = "Cat Form combat target", fn = function(env) return env.spec == "CAT" and env.form == "CAT" and env.hasActiveEnemy end }
P.feral_bear_enemy = { label = "Bear Form combat target", fn = function(env) return env.spec == "BEAR" and env.form == "BEAR" and env.hasActiveEnemy end }
P.restoration_heal = { label = "Selected friendly target needs healing", fn = function(env) return env.spec == "REST" and env.healHealth ~= nil and env.healHealth < 95 end }
P.restoration_emergency = { label = "Selected friendly target needs emergency healing", fn = function(env) return env.spec == "REST" and env.healHealth ~= nil and env.healHealth <= 35 end }
P.lunar_eclipse = { label = "Lunar Eclipse active", fn = function(env) return env.lunarEclipse end }
P.solar_eclipse = { label = "Solar Eclipse active", fn = function(env) return env.solarEclipse end }
P.missing_insect_swarm = { label = "Insect Swarm missing", fn = function(env) return env.balance_enemy and not env.targetDebuffInsectSwarm end }
P.missing_moonfire = { label = "Moonfire missing", fn = function(env) return env.balance_enemy and not env.targetDebuffMoonfire end }
P.missing_faerie_fire = { label = "Faerie Fire missing", fn = function(env) return env.hasActiveEnemy and not env.targetDebuffFaerieFire end }
P.missing_feral_faerie_fire = { label = "Feral Faerie Fire missing", fn = function(env) return env.hasActiveEnemy and not env.targetDebuffFaerieFireFeral end }
P.boss_or_aoe = { label = "Boss or multiple enemies", fn = function(env) return env.isBoss or env.isAoE end }
P.starfall_lunar_boss = {
    label = "Lunar Eclipse on a boss or multiple enemies",
    fn = function(env) return env.lunarEclipse and (env.isBoss or env.isAoE) end,
}
P.wrath_filler = {
    label = "Wrath filler",
    fn = function(env) return env.balance_enemy and not env.lunarEclipse end,
}
P.starfire_filler = {
    label = "Starfire filler",
    fn = function(env) return env.balance_enemy and env.lunarEclipse end,
}
P.cat_needs_rake = { label = "Rake missing", fn = function(env) return env.feral_cat_enemy and (env.comboPoints or 0) < 5 and not env.targetDebuffRake end }
P.cat_needs_rip = { label = "Five combo points and Rip missing", fn = function(env) return env.feral_cat_enemy and (env.comboPoints or 0) >= 5 and not env.targetDebuffRip and (not env.targetHealth or env.targetHealth > 10) end }
P.cat_can_bite = {
    label = "Ferocious Bite ready",
    fn = function(env)
        return env.feral_cat_enemy and (env.comboPoints or 0) >= 5
            and env.targetDebuffRip and (not env.energy or env.energy >= 35)
    end,
}
P.cat_needs_savage_roar = {
    label = "Savage Roar missing",
    fn = function(env)
        return env.feral_cat_enemy and (env.comboPoints or 0) >= 1 and not env.savageRoarActive
    end,
}
P.cat_tigers_fury = {
    label = "Low energy and Tiger's Fury ready",
    fn = function(env) return env.feral_cat_enemy and (env.energy or 0) <= 35 and not env.tigerFuryActive end,
}
P.cat_needs_mangle = {
    label = "Mangle debuff missing",
    fn = function(env) return env.feral_cat_enemy and (env.comboPoints or 0) < 5 and not env.targetDebuffMangleCat end,
}
P.cat_builder = {
    label = "Build combo points",
    fn = function(env) return env.feral_cat_enemy and (env.comboPoints or 0) < 5 and (not env.energy or env.energy >= 40) end,
}
P.cat_fatal_bite = {
    label = "Low-health target finisher",
    fn = function(env)
        return env.feral_cat_enemy and env.targetHealth ~= nil and env.targetHealth <= 30
            and (env.comboPoints or 0) >= 3 and (not env.energy or env.energy >= 35)
    end,
}
P.bear_needs_enrage = {
    label = "Bear Form low rage",
    fn = function(env) return env.feral_bear_enemy and env.inCombat and (env.rage or 0) < 20 end,
}
P.bear_needs_taunt = {
    label = "Target attacking an ally",
    fn = function(env)
        return env.feral_bear_enemy and env.inCombat and env.hasTargetTarget
            and not env.targetTargetIsPlayer
    end,
}
P.bear_needs_bash = {
    label = "Interruptible enemy cast",
    fn = function(env) return env.feral_bear_enemy and env.inCombat and env.targetInterruptible end,
}
P.bear_needs_demo = {
    label = "Demoralizing Roar missing",
    fn = function(env) return env.feral_bear_enemy and not env.targetDebuffDemoralizingRoar end,
}
P.bear_needs_mangle = {
    label = "Mangle debuff missing",
    fn = function(env) return env.feral_bear_enemy and not env.targetDebuffMangleBear end,
}
P.bear_needs_lacerate = {
    label = "Lacerate stacks below five",
    fn = function(env) return env.feral_bear_enemy and env.inCombat and (env.lacerateStacks or 0) < 5 end,
}
P.bear_aoe = {
    label = "Multiple enemies in Bear Form",
    fn = function(env) return env.feral_bear_enemy and env.isAoE end,
}
P.bear_maul = {
    label = "High rage Maul",
    fn = function(env) return env.feral_bear_enemy and (env.rage or 0) >= 50 end,
}
P.heal_swiftmend = {
    label = "Urgent heal with a HoT active",
    fn = function(env) return env.restoration_heal and env.healHealth <= 45 and env.hasHoT end,
}
P.heal_regrowth = {
    label = "Health below sixty percent",
    fn = function(env) return env.restoration_heal and env.healHealth <= 60 end,
}
P.heal_touch = {
    label = "Health below seventy percent",
    fn = function(env) return env.restoration_heal and env.healHealth <= 70 end,
}
P.heal_lifebloom = {
    label = "Lifebloom missing",
    fn = function(env)
        return env.restoration_heal and env.healHealth <= 85
            and not Compat.CheckBuff(spellName(33763), env.healUnit)
    end,
}
P.heal_rejuvenation = {
    label = "Rejuvenation missing",
    fn = function(env)
        return env.restoration_heal and env.healHealth <= 90
            and not Compat.CheckBuff(spellName(774), env.healUnit)
    end,
}
P.heal_nourish = {
    label = "Nourish with a HoT active",
    fn = function(env) return env.restoration_heal and env.healHealth <= 85 and env.hasHoT end,
}
P.innervate_low_mana = {
    label = "Player has low mana",
    fn = function(env) return env.hasMana and (env.manaPct or 100) <= 20 end,
}
P.lacerate_not_capped = {
    label = "Lacerate stacks below five",
    fn = function(env) return env.feral_bear_enemy and (env.lacerateStacks or 0) < 5 end,
}

module.RotationSpecs = {
    BAL = {
        title = "Balance",
        nodes = {
            { id = "moonkin_form", spellID = 24858, name = "Moonkin Form",
                color = "Utility", condition = "needs_balance_form",
                opts = { noEnemy = true, noRangeCheck = true } },
            { id = "innervate", spellID = 29166, name = "Innervate",
                color = "Utility", condition = "innervate_low_mana",
                opts = { noEnemy = true, noRangeCheck = true } },
            { id = "faerie_fire", spellID = 770, name = "Faerie Fire",
                color = "Utility", condition = "missing_faerie_fire" },
            { id = "insect_swarm", spellID = 5570, name = "Insect Swarm",
                color = "Damage", condition = "missing_insect_swarm" },
            { id = "moonfire", spellID = 8921, name = "Moonfire",
                color = "Damage", condition = "missing_moonfire" },
            { id = "starfall", spellID = 53201, name = "Starfall",
                color = "AoE", condition = "starfall_lunar_boss" },
            { id = "force_of_nature", spellID = 33831, name = "Force of Nature",
                color = "Damage", condition = "boss_or_aoe" },
            { id = "wrath_eclipse", spellID = 5176, name = "Wrath",
                color = "Damage", condition = "solar_eclipse" },
            { id = "starfire_eclipse", spellID = 2912, name = "Starfire",
                color = "Damage", condition = "lunar_eclipse" },
            { id = "wrath", spellID = 5176, name = "Wrath",
                color = "Damage", condition = "wrath_filler" },
            { id = "starfire", spellID = 2912, name = "Starfire",
                color = "Damage", condition = "starfire_filler" },
        },
    },
    CAT = {
        title = "Feral (Cat)",
        nodes = {
            { id = "cat_form", spellID = 768, name = "Cat Form",
                color = "Utility", condition = "needs_cat_form",
                opts = { noEnemy = true, noRangeCheck = true } },
            { id = "innervate", spellID = 29166, name = "Innervate",
                color = "Utility", condition = "innervate_low_mana",
                opts = { noEnemy = true, noRangeCheck = true } },
            { id = "survival_instincts", spellID = 61336, name = "Survival Instincts",
                color = "Defensive", condition = "cat_low_health",
                opts = { noEnemy = true, noRangeCheck = true } },
            { id = "barkskin", spellID = 22812, name = "Barkskin",
                color = "Defensive", condition = "low_health",
                opts = { noEnemy = true, noRangeCheck = true } },
            { id = "tigers_fury", spellID = 5217, name = "Tiger's Fury",
                color = "Damage", condition = "cat_tigers_fury",
                opts = { noEnemy = true, noRangeCheck = true } },
            { id = "feral_faerie_fire", spellID = 16857, name = "Faerie Fire (Feral)",
                color = "Utility", condition = "missing_feral_faerie_fire" },
            { id = "savage_roar", spellID = 52610, name = "Savage Roar",
                color = "Utility", condition = "cat_needs_savage_roar",
                opts = { noEnemy = true, noRangeCheck = true } },
            { id = "mangle_cat", spellID = 33876, name = "Mangle (Cat)",
                color = "Damage", condition = "cat_needs_mangle" },
            { id = "rake", spellID = 1822, name = "Rake",
                color = "Damage", condition = "cat_needs_rake" },
            { id = "rip", spellID = 1079, name = "Rip",
                color = "Damage", condition = "cat_needs_rip" },
            { id = "ferocious_bite", spellID = 22568, name = "Ferocious Bite",
                color = "Damage", condition = "cat_can_bite" },
            { id = "ferocious_bite_fatal", spellID = 22568, name = "Ferocious Bite",
                color = "Damage", condition = "cat_fatal_bite" },
            { id = "claw", spellID = 1082, name = "Claw",
                color = "Damage", condition = "cat_builder" },
        },
    },
    BEAR = {
        title = "Feral (Bear)",
        nodes = {
            { id = "bear_form", spellID = 5487, name = "Bear Form",
                color = "Utility", condition = "needs_bear_form",
                opts = { noEnemy = true, noRangeCheck = true } },
            { id = "innervate", spellID = 29166, name = "Innervate",
                color = "Utility", condition = "innervate_low_mana",
                opts = { noEnemy = true, noRangeCheck = true } },
            { id = "survival_instincts", spellID = 61336, name = "Survival Instincts",
                color = "Defensive", condition = "bear_low_health",
                opts = { noEnemy = true, noRangeCheck = true } },
            { id = "frenzied_regeneration", spellID = 22842, name = "Frenzied Regeneration",
                color = "Defensive", condition = "bear_frenzied_regeneration",
                opts = { noEnemy = true, noRangeCheck = true } },
            { id = "barkskin", spellID = 22812, name = "Barkskin",
                color = "Defensive", condition = "low_health",
                opts = { noEnemy = true, noRangeCheck = true } },
            { id = "enrage", spellID = 5229, name = "Enrage",
                color = "Utility", condition = "bear_needs_enrage",
                opts = { noEnemy = true, noRangeCheck = true } },
            { id = "growl", spellID = 6795, name = "Growl",
                color = "Utility", condition = "bear_needs_taunt" },
            { id = "bash", spellID = 5211, name = "Bash",
                color = "Interrupt", condition = "bear_needs_bash" },
            { id = "feral_faerie_fire", spellID = 16857, name = "Faerie Fire (Feral)",
                color = "Utility", condition = "missing_feral_faerie_fire" },
            { id = "demoralizing_roar", spellID = 99, name = "Demoralizing Roar",
                color = "Utility", condition = "bear_needs_demo",
                opts = { noRangeCheck = true } },
            { id = "mangle_bear", spellID = 33878, name = "Mangle (Bear)",
                color = "Damage", condition = "bear_needs_mangle" },
            { id = "lacerate", spellID = 33745, name = "Lacerate",
                color = "Damage", condition = "bear_needs_lacerate" },
            { id = "swipe_bear", spellID = 779, name = "Swipe (Bear)",
                color = "AoE", condition = "bear_aoe" },
            { id = "maul", spellID = 6807, name = "Maul",
                color = "Damage", condition = "bear_maul" },
        },
    },
    REST = {
        title = "Restoration",
        nodes = {
            { id = "tree_of_life", spellID = 33891, name = "Tree of Life",
                color = "Utility", condition = "needs_tree_form",
                opts = { noEnemy = true, noRangeCheck = true } },
            { id = "innervate", spellID = 29166, name = "Innervate",
                color = "Utility", condition = "innervate_low_mana",
                opts = { noEnemy = true, noRangeCheck = true } },
            { id = "swiftmend", spellID = 18562, name = "Swiftmend",
                color = "Defensive", condition = "heal_swiftmend",
                opts = { noEnemy = true, noRangeCheck = true, unitKey = "healUnit" } },
            { id = "regrowth", spellID = 8936, name = "Regrowth",
                color = "Defensive", condition = "heal_regrowth",
                opts = { noEnemy = true, unitKey = "healUnit" } },
            { id = "healing_touch", spellID = 5185, name = "Healing Touch",
                color = "Defensive", condition = "heal_touch",
                opts = { noEnemy = true, unitKey = "healUnit" } },
            { id = "lifebloom", spellID = 33763, name = "Lifebloom",
                color = "Defensive", condition = "heal_lifebloom",
                opts = { noEnemy = true, unitKey = "healUnit" } },
            { id = "rejuvenation", spellID = 774, name = "Rejuvenation",
                color = "Defensive", condition = "heal_rejuvenation",
                opts = { noEnemy = true, unitKey = "healUnit" } },
            { id = "nourish", spellID = 50464, name = "Nourish",
                color = "Defensive", condition = "heal_nourish",
                opts = { noEnemy = true, unitKey = "healUnit" } },
        },
    },
}

P.cat_low_health = {
    label = "Cat Form critical health",
    fn = function(env) return env.spec == "CAT" and env.form == "CAT" and env.inCombat and (env.myHealth or 100) <= 30 end,
}
P.bear_low_health = {
    label = "Bear Form critical health",
    fn = function(env) return env.spec == "BEAR" and env.form == "BEAR" and env.inCombat and (env.myHealth or 100) <= 30 end,
}
P.low_health = {
    label = "Low health",
    fn = function(env) return env.inCombat and (env.myHealth or 100) <= 40 end,
}
P.bear_frenzied_regeneration = {
    label = "Bear Form low health and available rage",
    fn = function(env)
        return env.spec == "BEAR" and env.form == "BEAR" and env.inCombat
            and (env.myHealth or 100) <= 50 and (env.rage or 0) >= 10
    end,
}

local function nextExtraSuggestion()
    if module:IsExtraSuggestionEnabled("mark")
        and not buffActive(1126, "mark_of_the_wild", "MarkOfTheWild") then
        local id = resolveSpellID(1126)
        local name = id and spellName(id)
        if id and name and module.CheckCastable({
            SpellID = id, SpellName = name, EnemyTargetNeeded = false,
            Unit = "player", NoRangeCheck = true,
        }) then
            return { spellID = id, color = "Utility" }
        end
    end
    if module:IsExtraSuggestionEnabled("thorns")
        and not buffActive(467, "thorns", "Thorns") then
        local id = resolveSpellID(467)
        local name = id and spellName(id)
        if id and name and module.CheckCastable({
            SpellID = id, SpellName = name, EnemyTargetNeeded = false,
            Unit = "player", NoRangeCheck = true,
        }) then
            return { spellID = id, color = "Utility" }
        end
    end
    return nil
end

local function recordSuccessfulCast(spellID)
    local id = safeNumber(spellID)
    if not id then return end
    local guid = targetGUID()
    local timestamp = now()

    if sameSpellFamily(id, 1126) then
        module.buffBeliefs.mark_of_the_wild = { expires = timestamp + 3600 }
    elseif sameSpellFamily(id, 467) then
        module.buffBeliefs.thorns = { expires = timestamp + 600 }
    elseif id == 52610 then
        local points = readNumber(GetComboPoints, "player", "target") or 1
        module.buffBeliefs.savage_roar = { expires = timestamp + 9 + math.min(points, 5) * 3 }
    end

    if not guid then return end
    for baseID, info in pairs(DOT_INFO) do
        if sameSpellFamily(id, baseID) then
            local previous = module.targetBeliefs[info.key]
            local stacks = 1
            if info.stacks and type(previous) == "table" and previous.guid == guid
                and timestamp < previous.expires then
                stacks = math.min(5, (previous.stacks or 0) + 1)
            end
            module.targetBeliefs[info.key] = {
                guid = guid,
                expires = timestamp + info.duration,
                stacks = stacks,
            }
        end
    end
end

local tracker = CreateFrame("Frame")
tracker:RegisterEvent("PLAYER_ENTERING_WORLD")
tracker:RegisterEvent("PLAYER_DEAD")
tracker:RegisterEvent("SPELLS_CHANGED")
tracker:RegisterEvent("PLAYER_TALENT_UPDATE")
tracker:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
pcall(tracker.RegisterEvent, tracker, "TRAIT_CONFIG_UPDATED")
tracker:SetScript("OnEvent", function(_, event, ...)
    if event == "PLAYER_ENTERING_WORLD" or event == "PLAYER_DEAD" then
        wipe(module.buffBeliefs)
        wipe(module.targetBeliefs)
        module.talentCache = nil
        module.lastTalentAttempt = 0
    elseif event == "SPELLS_CHANGED" or event == "PLAYER_TALENT_UPDATE"
        or event == "TRAIT_CONFIG_UPDATED" then
        module.talentCache = nil
        module.lastTalentAttempt = 0
        if Compat.InvalidateSpellCaches then Compat.InvalidateSpellCaches() end
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        local unit, _, spellID = ...
        if unit == "player" then recordSuccessfulCast(spellID) end
    end
end)

function module:GetSuggestion()
    if addon.db.druidEnabled == false then return nil end
    local _, playerClass = UnitClass("player")
    if playerClass ~= "DRUID" or (type(IsMounted) == "function" and IsMounted()) then return nil end
    if Compat.CastingOrChanneling(nil, "player") then return nil end

    self.PendingSuggestion = nil
    self.TickFlashUsed = nil
    local specKey = self:DetectSpec()
    local env = self:BuildEnv(specKey)
    addon:RunDeclaredRotation(self, specKey, env)

    local extra = nextExtraSuggestion()
    local rotation = self.PendingSuggestion
    if extra then
        if rotation and env.emergencyHealing then
            rotation.additional = { extra }
            return rotation
        end
        if rotation then extra.additional = { rotation } end
        return extra
    end
    if rotation then return rotation end

    if addon.SuggestRacial and addon:SuggestRacial(self, env) then
        return self.PendingSuggestion
    end
    return nil
end

function module:GetStatus()
    local specKey, source = self:DetectSpec()
    local title = self.RotationSpecs[specKey] and self.RotationSpecs[specKey].title or specKey
    return string.format("Druid - %s (%s)", tostring(title), tostring(source))
end

function module:DebugRotation()
    local specKey, source = self:DetectSpec()
    local env = self:BuildEnv(specKey)
    addon:DebugPrint("Druid spec=", specKey, "source=", source, "form=", env.form,
        "enemy=", env.hasActiveEnemy, "combat=", env.inCombat, "mana=", env.manaPct,
        "energy=", env.energy, "rage=", env.rage, "combo=", env.comboPoints,
        "AoE=", env.enemyCount, "heal=", env.healUnit, env.healHealth)
    local nodes = self:GetEffectiveNodes(specKey) or {}
    for _, node in ipairs(nodes) do
        local enabled = node.enabled ~= false
        local conditionOK = addon.NodeConditionPass(self, env, node, true)
        addon:DebugPrint("  node", node.id, "enabled=", enabled, "condition=",
            node.condition, "conditionOK=", conditionOK)
    end
end

addon:RegisterModule("DRUID", module)
