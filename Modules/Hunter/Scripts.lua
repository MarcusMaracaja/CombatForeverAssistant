-- Combat Forever Assistant â€” Hunter module: hub.
-- Builds the env, detects the spec, decides the suggestion and registers
-- the module with the core. The core pipeline (OnUpdate -> GetSuggestion)
-- takes it from here and flashes the button.
local moduleName, module = ...

local L = module.L

-- ---------------------------------------------------------------------------
-- Tracking frame (aliases created at load so later files can use them)
-- ---------------------------------------------------------------------------
local trackerFrame = CreateFrame("Frame", "CombatForeverAssistantHunterTracker", UIParent)
trackerFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
trackerFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
trackerFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
trackerFrame:RegisterEvent("UNIT_PET")
trackerFrame:RegisterEvent("UNIT_DIED")
trackerFrame:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")

trackerFrame:SetScript("OnEvent", function(_, event, ...)
    if event == "PLAYER_TARGET_CHANGED" then
        module.OnTargetChanged()
    elseif event == "PLAYER_ENTERING_WORLD" then
        module.AspectBelief = nil
        module.MarkBelief = { slot = 0, active = false }
        module.SerpentStingBelief = { slot = 0, applied = false, expires = 0 }
        module.WingClipBelief = { slot = 0, applied = false, expires = 0 }
        module.PET_IS_DEAD = false
    elseif event == "PLAYER_REGEN_ENABLED" then
        module.PET_IS_DEAD = false
    elseif event == "UNIT_PET" then
        local unit = ...
        if type(unit) == "string" then
            local ok, same = pcall(UnitIsUnit, unit, "player")
            if ok and same then
                local ok2, exists = pcall(UnitExists, "pet")
                local ok3, dead = pcall(UnitIsDeadOrGhost, "pet")
                module.PET_IS_DEAD = ok2 and exists and ok3 and dead or false
            end
        end
    elseif event == "UNIT_DIED" then
        local unit = ...
        if type(unit) == "string" then
            local ok, same = pcall(UnitIsUnit, unit, "pet")
            if ok and same then
                module.PET_IS_DEAD = true
            end
        end
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        local _, _, spellID = ...
        if type(spellID) == "number" and module.Compat and module.Compat.SpellInfoByID then
            local name = module.Compat.SpellInfoByID(spellID)
            module.RegisterCast(name)
        end
    end
end)

-- ---------------------------------------------------------------------------
-- Press suppress: when you press the button for the blinking spell, stop
-- blinking it immediately instead of waiting for the cast to land.
-- ---------------------------------------------------------------------------
module.PressSuppress = {}

function module.OnSpinPressed(button)
    if not button or not button.GetAttribute then return end
    local action = button:GetAttribute("action")
    if not action then return end
    local actionType, id = GetActionInfo(tonumber(action) or action)
    if actionType == "spell" and id then
        local name = module.Compat and module.Compat.SpellInfoByID and module.Compat.SpellInfoByID(id)
        if name then
            module.PressSuppress[name] = GetTime() + 0.6
        end
    end
end

function module.IsPressSuppressed(spellName)
    if not spellName or spellName == "" then return false end
    local untilTime = module.PressSuppress[spellName]
    return not not (untilTime and GetTime() < untilTime)
end

module.HooksDone = false
function module.HookActionButtonPress()
    if module.HooksDone then return end
    module.HooksDone = true
    module._hookedButtons = {}
    local function hookPrefix(prefix)
        for i = 1, 12 do
            local btn = _G[prefix .. i]
            if btn and not btn.cfaPressHooked then
                btn.cfaPressHooked = true
                hooksecurefunc(btn, "Click", function(self)
                    pcall(module.OnSpinPressed, self)
                end)
            end
        end
    end
    if type(SecureActionButton_OnClick) == "function" then
        hooksecurefunc("SecureActionButton_OnClick", function(self)
            pcall(module.OnSpinPressed, self)
        end)
        return
    end
    local prefixes = { "ActionButton", "MultiBarRightButton", "MultiBarLeftButton",
        "MultiBarBottomLeftButton", "MultiBarBottomRightButton",
        "PetActionButton", "StanceButton", "PossessButton" }
    for _, p in ipairs(prefixes) do hookPrefix(p) end
end

-- ---------------------------------------------------------------------------
-- Env + AoE detection
-- ---------------------------------------------------------------------------
local function countEnemiesInCombat()
    if _G.MaxDps and type(_G.MaxDps.SmartAoe) == "function" then
        local ok, n = pcall(_G.MaxDps.SmartAoe)
        if ok and type(n) == "number" then return n end
    end
    -- Fallback: no AoE detector available. Zero is safe (AoE nodes simply
    -- won't suggest); the player can still fire them from the rotation.
    return 0
end

function module:BuildEnv()
    local env = {}
    env.myHP = 100
    if type(UnitHealth) == "function" and type(UnitHealthMax) == "function" then
        local hp, maxHp = UnitHealth("player"), UnitHealthMax("player")
        if type(hp) == "number" and type(maxHp) == "number" and maxHp > 0 then
            env.myHP = math.floor((hp / maxHp) * 100)
        end
    end
    env.manaPct = 100
    if type(UnitPower) == "function" and type(UnitPowerMax) == "function" then
        local mp, maxMp = UnitPower("player"), UnitPowerMax("player")
        if type(mp) == "number" and type(maxMp) == "number" and maxMp > 0 then
            env.manaPct = math.floor((mp / maxMp) * 100)
        end
    end
    env.hasActiveEnemy = module.UnitTargetExistsAndAttackable()
    env.isPvP = module.IsPvPTarget()
    env.isMelee = false
    env.tooCloseForRanged = false
    if UnitExists("target") then
        if env.targetDistance == nil then
            -- no direct yard API trusted; infer from melee range / in-combat isMelee tap
            env.targetDistance = 100
        end
    end
    -- ranged dead zone: use Auto Shot range as probe when available
    local autoShotName = module.SpellName(75)
    local inAutoShotRange = nil
    if autoShotName and type(IsSpellInRange) == "function" then
        local ok, r = pcall(IsSpellInRange, autoShotName, "target")
        if ok then inAutoShotRange = r end
    end
    local meleeProbe = nil
    local wingName = module.SpellName(2974)
    if wingName and type(IsSpellInRange) == "function" then
        local ok, r = pcall(IsSpellInRange, wingName, "target")
        if ok then meleeProbe = r end
    end
    if type(UnitDistanceSquared) == "function" then
        local ok, sq = pcall(UnitDistanceSquared, "target")
        if ok and type(sq) == "number" and sq >= 0 then
            env.targetDistance = math.sqrt(sq)
            env.isMelee = env.targetDistance <= 10
            env.tooCloseForRanged = env.isMelee
        end
    end
    if env.targetDistance == nil then
        -- fallback: melee via Wing Clip probe, ranged via Auto Shot probe
        if meleeProbe == 1 then
            env.targetDistance = 5
            env.isMelee = true
            env.tooCloseForRanged = true
        elseif inAutoShotRange == 1 then
            env.targetDistance = 35
            env.isMelee = false
            env.tooCloseForRanged = false
        else
            env.targetDistance = 100
            env.tooCloseForRanged = false
            env.isMelee = false
        end
    end
    env.petAlive = UnitExists("pet") and not UnitIsDeadOrGhost("pet")
    env.inCombat = (type(UnitAffectingCombat) == "function" and UnitAffectingCombat("player")) and true or false
    env.isAoE = countEnemiesInCombat() >= 2
    return env
end

-- ---------------------------------------------------------------------------
-- Spec detection: override -> signature spells -> C_Traits points (SV wins ties)
-- ---------------------------------------------------------------------------
local TREE_HINTS = {
    BM = { "beast", "feras", "fera", "besta" },
    MM = { "marksman", "precis", "tirador", "sniper" },
    SV = { "surviv", "sobreviv" },
}

local _talentCountCache = nil
local function talentTreePoints(hints)
    if _talentCountCache then return _talentCountCache end
    _talentCountCache = false
    if not (C_ClassTalents and C_Traits) then return false end
    local okCfg, cfg = pcall(C_ClassTalents.GetActiveConfigID)
    if not okCfg or not cfg then return false end
    local okInfo, info = pcall(C_Traits.GetConfigInfo, cfg)
    if okInfo and type(info) == "table" and type(info.treeIDs) == "table" then
        local counts = {}
        for _, treeID in ipairs(info.treeIDs) do
            local okT, ti = pcall(C_Traits.GetTreeInfo, cfg, treeID)
            local treeName = (okT and type(ti) == "table" and type(ti.name) == "string") and ti.name:lower() or nil
            local key = nil
            if treeName then
                for k, list in pairs(hints) do
                    for _, hint in ipairs(list) do
                        if treeName:find(hint, 1, true) then key = k end
                    end
                end
            end
            if key then
                local okN, nodes = pcall(C_Traits.GetTreeNodes, treeID)
                local total = 0
                if type(nodes) == "table" then
                    for _, nodeID in ipairs(nodes) do
                        local okNI, ni = pcall(C_Traits.GetNodeInfo, cfg, nodeID)
                        if okNI and type(ni) == "table" then
                            total = total + (tonumber(ni.currentRank) or tonumber(ni.ranksPurchased) or tonumber(ni.activeRank) or 0)
                        end
                    end
                end
                counts[key] = total
            end
        end
        _talentCountCache = { counts = counts }
        return _talentCountCache
    end
    return false
end

function module:DetectSpec()
    local override = module.charDb and module.charDb.hunterSpec or nil
    if override == "BM" or override == "MM" or override == "SV" then
        return override, "override"
    end
    local cache = talentTreePoints(TREE_HINTS)
    local c = cache and cache.counts or nil
    local pointsBM = c and tonumber(c.BM) or 0
    local pointsMM = c and tonumber(c.MM) or 0
    local pointsSV = c and tonumber(c.SV) or 0
    if pointsBM > pointsMM and pointsBM > pointsSV then return "BM", "C_Traits" end
    if pointsMM > pointsBM and pointsMM > pointsSV then return "MM", "C_Traits" end
    if pointsBM > 0 or pointsMM > 0 or pointsSV > 0 then return "SV", "C_Traits" end
    if type(IsSpellKnown) == "function" then
        if IsSpellKnown(19306) then return "SV", "Counterattack" end
        if IsSpellKnown(19574) then return "BM", "Bestial Wrath" end
        if IsSpellKnown(1310786) then return "MM", "Sniper Shot" end
    end
    return "SV", "default"
end

-- ---------------------------------------------------------------------------
-- Aspects (global management)
-- ---------------------------------------------------------------------------
local function isGroupInCombat()
    if type(UnitAffectingCombat) == "function" and UnitAffectingCombat("player") then return true end
    local nP = (type(GetNumPartyMembers) == "function" and GetNumPartyMembers()) or 0
    for i = 1, nP do
        if type(UnitAffectingCombat) == "function" and UnitAffectingCombat("party" .. i) then return true end
    end
    local nR = (type(GetNumRaidMembers) == "function" and GetNumRaidMembers()) or 0
    for i = 1, nR do
        if type(UnitAffectingCombat) == "function" and UnitAffectingCombat("raid" .. i) then return true end
    end
    return false
end

function module:ManageAspects(env)
    local _, _ = nil, nil
    -- Out of combat: Cheetah solo / Pack in group
    if not isGroupInCombat() then
        local numParty = (type(GetNumPartyMembers) == "function" and GetNumPartyMembers()) or 0
        local numRaid = (type(GetNumRaidMembers) == "function" and GetNumRaidMembers()) or 0
        if numParty > 0 or numRaid > 1 then
            if not module.HasFamilyBuff("player", "AspectOfThePack") then
                return module:Suggest(13159, "Utility")
            end
        else
            if not module.HasFamilyBuff("player", "AspectOfTheCheetah") then
                return module:Suggest(5118, "Utility")
            end
        end
        return nil
    end
    -- In combat, melee: Beast/Monkey; ranged: Hawk (damage aspect)
    if env.tooCloseForRanged then
        local beingFocused = (type(UnitIsUnit) == "function" and UnitIsUnit("targettarget", "player"))
        if beingFocused then
            if not module.IsAspectOfMonkeyActive() then
                return module:Suggest(13163, "Utility")
            end
        else
            if not module.IsAspectOfBeastActive() then
                return module:Suggest(13161, "Utility")
            end
        end
        return nil
    end
    local dangerousAspect = module.IsAspectOfCheetahActive() or module.IsAspectOfPackActive()
    if not env.tooCloseForRanged and (env.manaPct > 70 or not module.IsAspectActive() or dangerousAspect) then
        if not module.IsAspectOfHawkActive() then
            return module:Suggest(13165, "Utility")
        end
    end
    return nil
end

-- ---------------------------------------------------------------------------
-- Suggestion plumbing
-- ---------------------------------------------------------------------------
module.TickFlashUsed = nil
module.PendingSuggestion = nil

function module:Suggest(spellID, color)
    if module.TickFlashUsed then return false end
    module.TickFlashUsed = true
    local knownID = module.Compat and module.Compat.HighestKnownSpellID and module.Compat.HighestKnownSpellID(spellID) or spellID
    module.PendingSuggestion = { spellID = knownID or spellID, color = color or "Utility" }
    return true
end

function module:TryFlash(spellID, color, condition, name, env)
    if module.TickFlashUsed then return false end
    local knownID = module.Compat and module.Compat.HighestKnownSpellID and module.Compat.HighestKnownSpellID(spellID) or spellID
    local spellName = module.SpellName(knownID or spellID)
    if not spellName then return false end
    if module.IsPressSuppressed(spellName) then return false end
    if type(condition) == "function" then
        local ok, res = pcall(condition, env)
        if not ok or not res then return false end
    end
    if not module.CheckCastable({
        SpellName = spellName,
        SpellID = knownID or spellID,
        EnemyTargetNeeded = true,
    }) then return false end
    return module:Suggest(knownID or spellID, color)
end

function module:GetSuggestion()
    local _, myClass = UnitClass("player")
    if myClass ~= "HUNTER" then return nil end
    if module.db and module.db.hunterEnabled == false then return nil end
    module.TickFlashUsed = nil
    module.PendingSuggestion = nil
    pcall(module.HookActionButtonPress)
    if IsMounted and IsMounted() then return nil end
    if type(UnitCastingInfo) == "function" then
        local ok, n = pcall(UnitCastingInfo, "player")
        if ok and n then return nil end
    end
    if type(UnitChannelInfo) == "function" then
        local ok, n = pcall(UnitChannelInfo, "player")
        if ok and n then return nil end
    end

    local env = module:BuildEnv()

    -- Pending suggestion from aspects/pet/etc. wins for this tick.
    if self:ManageAspects(env) then return module.PendingSuggestion end

    -- Pet management
    if env.petAlive then
        local mending = module.HasFamilyBuff("pet", "MendPet")
        local petHP = 100
        if type(UnitHealth) == "function" and type(UnitHealthMax) == "function" then
            local hp, maxHp = UnitHealth("pet"), UnitHealthMax("pet")
            if type(hp) == "number" and type(maxHp) == "number" and maxHp > 0 then
                petHP = math.floor((hp / maxHp) * 100)
            end
        end
        if petHP < 70 and not mending then
            if module:TryFlash(136, "Utility", function() return true end, "Mend Pet", env) then
                return module.PendingSuggestion
            end
        end
    else
        if not module.PET_IS_DEAD then
            if module:TryFlash(883, "Utility", function() return true end, "Call Pet", env) then
                return module.PendingSuggestion
            end
        end
    end

    -- Hunter's Mark
    if env.hasActiveEnemy and not module.IsMarkedByUs() and not module.IsMarked("target") then
        if module:TryFlash(1130, "Utility", function() return true end, "Hunter's Mark", env) then
            return module.PendingSuggestion
        end
    end

    -- Concussive Shot (PvP control / PvE aggro)
    if env.hasActiveEnemy and not env.isMelee and not module.IsClipped("target") then
        local beingFocused = type(UnitIsUnit) == "function" and UnitIsUnit("targettarget", "player")
        if env.isPvP or (env.inCombat and (beingFocused or not UnitExists("targettarget"))) then
            if module:TryFlash(5116, "Interrupt", function() return true end, "Concussive Shot", env) then
                return module.PendingSuggestion
            end
        end
    end

    -- Run the spec rotation (declared data)
    local specKey = self:DetectSpec()
    if specKey and module.RunDeclaredRotation then
        module:RunDeclaredRotation(module, specKey, env)
        if module.PendingSuggestion then return module.PendingSuggestion end
    end

    -- Auto Shot (filler)
    if env.hasActiveEnemy and not env.isMelee and not module:IsPressSuppressed(module.SpellName(75)) then
        if module:Suggest(75, "Damage") then return module.PendingSuggestion end
    end
    return nil
end

-- ---------------------------------------------------------------------------
-- Register with the core
-- ---------------------------------------------------------------------------
module:RegisterModule("HUNTER", module)
